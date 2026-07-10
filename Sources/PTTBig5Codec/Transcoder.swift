//
//  PTTBig5Codec
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

/// ESC-aware Big5-UAO → UTF-8 串流狀態機。
///
/// 增量吃 SSH raw byte chunk、吐 ``PTTByte`` token；`feed(_:)` 可任意切割，
/// 跨 chunk 的 pending lead 與半截 escape 都持有到資料到齊。
///
/// 三條硬規格（皆有對應測試 case 驗收）：
/// - ① pending Big5 lead 跨 escape 序列與 chunk 邊界持有，直到 trail 到齊。
/// - ② escape 相對輸出 char-atomic：永不在 UTF-8 字中間切斷。
/// - ③ 雙色字（mid-char SGR）：整字取 lead 色、夾在中間的 SGR 重排到字後
///   （＝下個字起生效）。精確 emit 順序見 ``feed(_:)`` 內註解與測試 case 1。
///
/// 其餘 stream 規則（皆有實測根據）：
/// - 起手剝 19-byte HTTP 前導 `HTTP/1.1 200 OK\r\n\r\n`（錨定 pattern、非硬編長度；前導不存在則不剝）。
/// - NUL（0x00）忽略（terminal 慣例），永不漏進輸出。
/// - Big5 lead 範圍引用 ``UAODecodeTable/leadRange``（單一正本，非本檔另訂）；配對後查
///   ``UAODecodeTable/lookup(_:)``；miss → 每半形補 `'?'`。
/// - bbsu target：偵測第一個 `ESC[H ESC[2J` 後切 UTF-8 passthrough（切點 session-specific、不硬編 byte offset）；
///   bbs target 全程 Big5。
public struct StreamTranscoder: Sendable {

	// MARK: Public

	/// 連線 target 類型：決定是否在第一個 clear-screen 後切 UTF-8 passthrough。
	public enum Target: Sendable {

		/// `bbs@`：全程 Big5-UAO。
		case bbs

		/// `bbsu@`：banner 段 Big5、第一個 `ESC[H ESC[2J` 後純 UTF-8。
		case bbsu
	}

	/// 吃一段 raw byte chunk、回該段產生的 token。跨 chunk 狀態（pending lead、半截 escape、
	/// passthrough 切換）由 transcoder 持有，可任意切割餵入。
	public mutating func feed(_ chunk: [UInt8]) -> [PTTByte] {
		var out: [PTTByte] = []
		var index = chunk.startIndex
		// 起手剝 HTTP 前導（可能跨 chunk）。
		if !prefixDone {
			while index < chunk.endIndex {
				let byte = chunk[index]
				if byte == Self.httpPreamble[prefixMatched.count] {
					prefixMatched.append(byte)
					index += 1
					if prefixMatched.count == Self.httpPreamble.count {
						prefixDone = true // 完整命中 → 整段剝除
						prefixMatched = []
						break
					}
				} else {
					// 中途歧異 → 前導不存在：把已吞的回放進正常處理、再續處理當前 byte。
					prefixDone = true
					let buffered = prefixMatched
					prefixMatched = []
					for replay in buffered {
						consume(replay, into: &out)
					}
					break
				}
			}
			if !prefixDone { return out } // chunk 用盡仍在比對前導 → 下個 chunk 續比
		}
		while index < chunk.endIndex {
			consume(chunk[index], into: &out)
			index += 1
		}
		return out
	}

	/// 串流結束時呼叫：丟棄尾端孤 lead、吐出殘留的 held SGR 與半截 escape（best-effort）。
	public mutating func finish() -> [PTTByte] {
		var out: [PTTByte] = []
		pendingLead = nil
		flushHeldEscapes(into: &out)
		if inEscape, !escapeBuffer.isEmpty {
			emitEscape(escapeBuffer, into: &out)
			escapeBuffer = []
			inEscape = false
		}
		return out
	}

	/// 建立 transcoder；target 與解碼表定案後不可變，串流狀態（pending lead、escape、passthrough）全由內部持有。
	///
	/// - Parameters:
	///   - target: 連線類型；`.bbsu` 才會在第一個 `ESC[H ESC[2J` 後切 UTF-8 passthrough。
	///   - decodeMap: Big5→Unicode 查表，預設正本 ``UAO/decode``；測試可注入殘缺表逼出 fallback。
	public init(target: Target = .bbs, decodeMap: UAODecodeTable = UAO.decode) {
		self.target = target
		self.decodeMap = decodeMap
	}

	// MARK: Private

	/// 起手剝除的 HTTP 前導 pattern（`HTTP/1.1 200 OK\r\n\r\n`、19 byte）；逐 byte 錨定比對、中途歧異即整段回放，非硬編長度。
	private static let httpPreamble: Array = .init("HTTP/1.1 200 OK\r\n\r\n".utf8)

	/// `ESC[H`（游標歸位）byte 序列：bbsu passthrough 錨點 `ESC[H ESC[2J` 的前半。
	private static let cursorHome: [UInt8] = [0x1B, 0x5B, 0x48]

	/// `ESC[2J`（清屏）byte 序列：緊接 `ESC[H` 出現即觸發 bbsu 切 UTF-8 passthrough。
	private static let clearScreen: [UInt8] = [0x1B, 0x5B, 0x32, 0x4A]

	/// escape buffer 上限：防一顆走丟的 ESC 吞掉整條流（防禦性，正常流不會觸及）。
	private static let escapeBufferCap = 64

	/// UAO trail 範圍：0x40–0x7E ∪ 0xA1–0xFE（C0 控制碼永不可能是 trail）。
	private static func isValidTrail(_ byte: UInt8) -> Bool {
		(0x40 ... 0x7E).contains(byte) || (0xA1 ... 0xFE).contains(byte)
	}

	/// SGR = CSI 以 `m`（0x6D）收尾。
	private static func isSGR(_ escape: [UInt8]) -> Bool {
		escape.count >= 3 && escape[0] == 0x1B && escape[1] == 0x5B && escape.last == 0x6D
	}

	/// 判斷 escape buffer 是否已收完一段完整序列。
	private static func isEscapeComplete(_ buffer: [UInt8]) -> Bool {
		guard buffer.count >= 2 else { return false } // 至少 ESC + 一 byte 才知型別
		switch buffer[1] {
		case 0x5B: // CSI：ESC [ … final(0x40–0x7E)
			guard buffer.count >= 3, let final = buffer.last else { return false }
			return (0x40 ... 0x7E).contains(final)
		case 0x4F: // SS3：ESC O <one>
			return buffer.count >= 3
		case 0x5D: // OSC：ESC ] … BEL
			return buffer.last == 0x07
		default: // 兩 byte escape（ESC c / ESC 7 …）
			return true
		}
	}

	/// 連線 target；`.bbsu` 才啟用 clear-screen 錨點後的 UTF-8 passthrough 切換。
	private let target: Target

	/// Big5→Unicode 查表；由 init 注入，正式流用 ``UAO/decode``、測試可注入殘缺表逼出 `'?'` fallback。
	private let decodeMap: UAODecodeTable

	/// HTTP 前導比對游標（match 中的 byte 數）；`prefixDone` 後不再比對。
	private var prefixMatched: [UInt8] = []

	/// HTTP 前導處理已結束（完整剝除、或確認不存在並回放）；此後 byte 全走正常狀態機。
	private var prefixDone = false

	/// bbsu 已切到 UTF-8 passthrough。
	private var passthrough = false

	/// 持有中的 Big5 lead（等 trail）。
	private var pendingLead: UInt8?

	/// 跨 chunk 累積中的 escape byte（含起手 ESC）；空 = 不在 escape 中。
	private var escapeBuffer: [UInt8] = []

	/// 正在累積 escape 序列（起手 ESC 已收到）；與 ``escapeBuffer`` 同步設定 / 清空。
	private var inEscape = false

	/// 在 pending lead 期間遇到的 mid-char SGR：暫存、字 emit 後再依序吐出（③ 重排）。
	private var heldEscapes: [[UInt8]] = []

	/// 上一個「已 emit」的 escape 是否為 `ESC[H`（緊鄰偵測 `ESC[H ESC[2J` 錨點用）。
	private var lastEmittedEscapeWasHome = false

	/// 單一 byte 的分派核心：依序處理 escape 續收、ESC 起手（pending lead 不丟）、NUL 忽略、
	/// passthrough 直通、Big5 lead/trail 配對與 0x80–0xA0 失敗 byte。
	private mutating func consume(_ byte: UInt8, into out: inout [PTTByte]) {
		if inEscape {
			accumulateEscape(byte, into: &out)
			return
		}
		if byte == 0x1B { // ESC：起手 escape（即使 pending lead 也持有 lead、不丟）
			inEscape = true
			escapeBuffer = [byte]
			return
		}
		if byte == 0x00 { // NUL：忽略，永不進輸出
			return
		}
		if passthrough { // bbsu 切換後：原樣直通 byte，下游重組 UTF-8
			out.append(.ascii(byte))
			lastEmittedEscapeWasHome = false
			return
		}
		// bbs / bbsu banner 段：Big5 狀態機
		if let lead = pendingLead {
			if Self.isValidTrail(byte) {
				emitBig5Pair(lead: lead, trail: byte, into: &out)
				return
			}
			// 非合法 trail（CR/LF/游標移動以外的非 escape byte）→ 孤 lead，放棄（case 4）。
			pendingLead = nil
			flushHeldEscapes(into: &out)
			// 落下去把 byte 當無 pending lead 的新 byte 處理。
		}
		if UAODecodeTable.leadRange.contains(byte) { // Big5 lead：持有等 trail（範圍＝ codec 正本，含 UAO 使用者定義區 0x81–0xA0）
			pendingLead = byte
			return
		}
		if byte < 0x80 { // ASCII（含 CR/LF/TAB 等控制）
			out.append(.ascii(byte))
			lastEmittedEscapeWasHome = false
			return
		}
		// 0x80（唯一剩餘值）：非 ASCII 也非合法 lead → 失敗 byte
		out.append(.invalid(byte))
		lastEmittedEscapeWasHome = false
	}

	/// 配對雙位元組 + 查表；命中吐 ``PTTByte/big5Char(_:)``、miss 補兩個 `'?'`，
	/// 然後依序吐出 held SGR（③ 重排：整字取 lead 色、SGR 移到字後）。
	private mutating func emitBig5Pair(lead: UInt8, trail: UInt8, into out: inout [PTTByte]) {
		let key = (UInt16(lead) << 8) | UInt16(trail)
		if let value = decodeMap.lookup(key), let scalar = Unicode.Scalar(value) {
			out.append(.big5Char(Character(scalar)))
		} else {
			out.append(.invalid(lead))
			out.append(.invalid(trail))
		}
		pendingLead = nil
		flushHeldEscapes(into: &out)
		lastEmittedEscapeWasHome = false
	}

	/// escape 累積中每 byte 進此：收滿完整序列或觸及 ``escapeBufferCap`` 即結算、轉交 ``handleCompletedEscape(_:into:)``。
	private mutating func accumulateEscape(_ byte: UInt8, into out: inout [PTTByte]) {
		escapeBuffer.append(byte)
		if Self.isEscapeComplete(escapeBuffer) || escapeBuffer.count >= Self.escapeBufferCap {
			let escape = escapeBuffer
			escapeBuffer = []
			inEscape = false
			handleCompletedEscape(escape, into: &out)
		}
	}

	/// 完整 escape 分流：pending lead 期間的 SGR 暫存進 ``heldEscapes``（③ 重排）、非 SGR 令孤 lead 放棄後照常 emit。
	private mutating func handleCompletedEscape(_ escape: [UInt8], into out: inout [PTTByte]) {
		if pendingLead != nil {
			if Self.isSGR(escape) {
				heldEscapes.append(escape) // ③：mid-char SGR 暫存、字後再吐
				return
			}
			// pending lead 期間遇非 SGR escape（游標移動 / 清屏等）→ 孤 lead，放棄。
			pendingLead = nil
			flushHeldEscapes(into: &out)
		}
		emitEscape(escape, into: &out)
	}

	/// 吐出 escape token 並維護 bbsu 錨點狀態：緊鄰 `ESC[H` 後的 `ESC[2J` 觸發 passthrough（只切一次、不回頭）。
	private mutating func emitEscape(_ escape: [UInt8], into out: inout [PTTByte]) {
		out.append(.escape(escape))
		// bbsu 錨點：緊鄰的 `ESC[H` 後接 `ESC[2J` → 切 UTF-8 passthrough（只切一次）。
		if target == .bbsu, !passthrough, lastEmittedEscapeWasHome, escape == Self.clearScreen {
			passthrough = true
		}
		lastEmittedEscapeWasHome = (escape == Self.cursorHome)
	}

	/// 依序吐出 ③ 暫存的 mid-char SGR（＝下個字起生效），並同步維護 `ESC[H` 錨點旗標。
	private mutating func flushHeldEscapes(into out: inout [PTTByte]) {
		guard !heldEscapes.isEmpty else { return }
		for escape in heldEscapes {
			out.append(.escape(escape))
			lastEmittedEscapeWasHome = (escape == Self.cursorHome)
		}
		heldEscapes = []
	}
}
