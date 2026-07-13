//
//  PTTBig5CodecTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTBig5Codec
import Foundation
import Testing

/// ``StreamTranscoder`` 驗收：涵蓋 9 個轉碼邊界 case 中的 1–7、9
/// （case 8 為 encode 方向，屬 ``UAO/encode(_:mode:)`` 範疇、非串流轉碼器職責，
/// 驗收見 `UAOTableTests.encode case 8 U+00DC`），外加三份真實
/// 登入畫面 golden capture 整段過機。
private final class TranscoderTests {

	/// ANSI SGR「粗體＋綠字」（`ESC[1;32m`）：case 1 的 lead 色來源，驗證整字取 lead 色。
	private let escSetBoldGreen: [UInt8] = [0x1B, 0x5B, 0x31, 0x3B, 0x33, 0x32, 0x6D]

	/// ANSI SGR「紅字」（`ESC[31m`）：插進 Big5 lead 與 trail 之間，製造 mid-char SGR 重排情境。
	private let escSetRed: [UInt8] = [0x1B, 0x5B, 0x33, 0x31, 0x6D]

	/// ANSI SGR 屬性重置（`ESC[m`）：關閉先前顏色，pin emit 順序時的收尾 escape token。
	private let escReset: [UInt8] = [0x1B, 0x5B, 0x6D]

	/// 游標歸位（`ESC[H`）：非 SGR 的 escape，用來驗證 pending lead 遇非 SGR escape 即放棄孤 lead。
	private let escCursorHome: [UInt8] = [0x1B, 0x5B, 0x48]

	/// `ESC[1;32m B3 ESC[31m 5C ESC[m`：許（0xB35C→U+8A31）夾紅色 SGR、trail=0x5C 雙重陷阱。
	/// 整字取 lead 色（綠）、mid-char SGR 重排到字後（＝下個字起生效）。
	/// emit 順序 pin：ESC[1;32m → 許 → ESC[31m → ESC[m，不臆造。
	@Test
	private func `case 1 double color mid char SGR reorder`() {
		var transcoder: StreamTranscoder = .init(target: .bbs)
		let input = escSetBoldGreen + [0xB3] + escSetRed + [0x5C] + escReset
		let tokens = transcoder.feed(input)
		#expect(tokens == [
			.escape(escSetBoldGreen), // lead 色先到、原序 emit
			.big5Char("\u{8A31}"), // 許：整字、取 lead 色
			.escape(escSetRed), // mid-char SGR 重排到字後
			.escape(escReset)
		])
		// serializeUTF8 還原為 lead色 + 許 + 紅 + reset 的 byte 流。
		let expected = escSetBoldGreen + Array("\u{8A31}".utf8) + escSetRed + escReset
		#expect(tokens.serializeUTF8() == expected)
	}

	/// lead byte 落在 chunk 尾（0xA1）：須持有不吐，待下個 chunk 補上 trail（0x40→U+3000）才 emit 整字。
	@Test
	private func `case 2 lead across chunk boundary`() {
		var transcoder: StreamTranscoder = .init(target: .bbs)
		// 'A' + lead 0xA1（落在 chunk 尾）
		let first = transcoder.feed([0x41, 0xA1])
		#expect(first == [.ascii(0x41)]) // lead 持有、尚未吐
		// trail 0x40（0xA140→U+3000 全形空白）+ 'B'
		let second = transcoder.feed([0x40, 0x42])
		#expect(second == [.big5Char("\u{3000}"), .ascii(0x42)])
	}

	/// escape 序列跨 chunk 邊界（`ESC[1` 與 `m` 拆兩包送入）：須跨 chunk 重組為單一 escape token 再 emit。
	@Test
	private func `case 3 escape across chunk boundary`() {
		var transcoder: StreamTranscoder = .init(target: .bbs)
		// ESC[1 …（半截）
		#expect(transcoder.feed([0x1B, 0x5B, 0x31]) == [])
		// …m + 'A'：escape 重組為單一 token。
		#expect(transcoder.feed([0x6D, 0x41]) == [.escape([0x1B, 0x5B, 0x31, 0x6D]), .ascii(0x41)])
	}

	/// ① + ③ 合擊：pending lead 跨 escape 又跨 chunk 邊界都持有到 trail 到齊。
	@Test
	private func `case 3 pending lead held across escape and chunk`() {
		var transcoder: StreamTranscoder = .init(target: .bbs)
		// lead 0xB3 + ESC[（mid-char SGR 半截）
		#expect(transcoder.feed([0xB3, 0x1B, 0x5B]) == [])
		// 31m（補完 SGR）+ trail 0x5C：許 emit、SGR 重排到字後。
		#expect(transcoder.feed([0x33, 0x31, 0x6D, 0x5C]) == [.big5Char("\u{8A31}"), .escape(escSetRed)])
	}

	/// pending lead 遇 CR/LF（非合法 trail）→ 放棄孤 lead、CR/LF 照常輸出。
	@Test
	private func `case 4 lone lead discarded on newline`() {
		var transcoder: StreamTranscoder = .init(target: .bbs)
		let tokens = transcoder.feed([0x41, 0xA1, 0x0D, 0x0A, 0x42]) // A <lone lead> CR LF B
		#expect(tokens == [.ascii(0x41), .ascii(0x0D), .ascii(0x0A), .ascii(0x42)])
	}

	/// pending lead 遇游標移動 escape（非 SGR）→ 放棄孤 lead、escape 照常輸出。
	@Test
	private func `case 4 lone lead discarded on cursor move`() {
		var transcoder: StreamTranscoder = .init(target: .bbs)
		let tokens = transcoder.feed([0xA1] + escCursorHome + [0x42]) // <lone lead> ESC[H B
		#expect(tokens == [.escape(escCursorHome), .ascii(0x42)])
	}

	/// 0xC6E7 必解出 ぁ U+3041，而非用錯表（cp950）會平移到的 ゃ U+3083。
	@Test
	private func `case 5 kana shift detection`() {
		var transcoder: StreamTranscoder = .init(target: .bbs)
		let tokens = transcoder.feed([0xC6, 0xE7])
		#expect(tokens == [.big5Char("\u{3041}")])
		#expect(tokens != [.big5Char("\u{3083}")])
	}

	/// 0xF9FA → ╭ U+256D（登入 banner 第一屏即有的倚天擴充字）。
	@Test
	private func `case 6 box drawing`() {
		var transcoder: StreamTranscoder = .init(target: .bbs)
		#expect(transcoder.feed([0xF9, 0xFA]) == [.big5Char("\u{256D}")])
	}

	/// 0xA140 → U+3000 全形空白：單一字、不可拆成兩個半形空白。
	@Test
	private func `case 7 fullwidth space not split`() {
		var transcoder: StreamTranscoder = .init(target: .bbs)
		let tokens = transcoder.feed([0xA1, 0x40])
		#expect(tokens.count == 1)
		#expect(tokens == [.big5Char("\u{3000}")])
		// serializeUTF8 = U+3000 三 byte，非兩個 0x20 半形空白。
		#expect(tokens.serializeUTF8() == Array("\u{3000}".utf8))
		#expect(tokens.serializeUTF8() != [0x20, 0x20])
	}

	/// zoneUserDefined 區（lead 0x81–0xA0，UAO 使用者定義區，標準 Big5 未收的罕用漢字為主）
	/// 在串流層須可解——鎖住回歸：table 層 `UAODecodeTable.lookup` 早已驗證 0x8140 可解出丗
	/// （`UAOTableTests.pointer corners`），但串流層曾把 lead 判定窄化為 0xA1–0xFE，
	/// 導致這段落地變 `.invalid(0x81) + .ascii(0x40)` 雜訊而非整字。
	@Test
	private func `case 10 zoneUserDefined lead range decodes correctly`() {
		var transcoder: StreamTranscoder = .init(target: .bbs)
		let tokens = transcoder.feed([0x81, 0x40]) // 0x8140 → 丗 U+4E17（zoneUserDefined 首格）
		#expect(tokens == [.big5Char("\u{4E17}")])
		#expect(tokens != [.invalid(0x81), .ascii(0x40)])
	}

	/// 高位區（lead 0xA1–0xFE × 合法 trail）在 UAO 正本 100% 滿表、實流不會 miss，
	/// 故注入空表逼出 fallback：每半形補 `'?'`、非整字 U+FFFD。
	@Test
	private func `case 9 unmapped DBCS fallback`() {
		var transcoder: StreamTranscoder = .init(target: .bbs, decodeMap: UAODecodeTable(values: []))
		let tokens = transcoder.feed([0xA1, 0x40]) // 合法 lead+trail、但空表必 miss
		#expect(tokens == [.invalid(0xA1), .invalid(0x40)])
		#expect(tokens.serializeUTF8() == [0x3F, 0x3F]) // "??"
	}

	/// bbs（全程 Big5）：前導剝除、NUL 不漏、輸出為合法 UTF-8、倚天線繪字（0xF9DE→╦）可出。
	@Test
	private func `golden BBS capture`() throws {
		for name in ["cap-bbs", "cap-bbs-none"] {
			let output = try transcodeWhole(name, target: .bbs)
			assertCommonGolden(output, name: name)
			let text: String = .init(decoding: output, as: UTF8.self)
			#expect(text.contains("\u{2566}"), "\(name): 倚天線繪字 ╦（0xF9DE）應解出")
		}
	}

	/// bbsu：banner 段 Big5、第一個 `ESC[H ESC[2J` 後切 UTF-8 passthrough。
	/// 切換點行為正確 = 錨點後的 tail 原樣（NUL 剝除）直通、為輸出尾段。
	@Test
	private func `golden BBSU capture`() throws {
		let raw = try loadCapture("cap-bbsu")
		let output = try transcodeWhole("cap-bbsu", target: .bbsu)
		assertCommonGolden(output, name: "cap-bbsu")
		// UTF-8 passthrough 段的倚天線繪（已是 UTF-8）原樣可見。
		let text: String = .init(decoding: output, as: UTF8.self)
		#expect(text.contains("╭╦╯"), "cap-bbsu: 切換後 UTF-8 線繪應直通")
		// 錨點後 tail 原樣直通：輸出尾段逐 byte 等於（NUL 剝除後的）capture tail。
		let prefix: Array = .init("HTTP/1.1 200 OK\r\n\r\n".utf8)
		let body: Array = .init(raw[prefix.count...])
		let anchor: [UInt8] = [0x1B, 0x5B, 0x48, 0x1B, 0x5B, 0x32, 0x4A] // ESC[H ESC[2J
		let anchorIdx = try #require(firstIndex(of: anchor, in: body), "找不到 bbsu 切換錨點")
		let tail = Array(body[(anchorIdx + anchor.count)...]).filter { $0 != 0x00 }
		#expect(Array(output.suffix(tail.count)) == tail, "cap-bbsu: 切換後 tail 應原樣直通為輸出尾段")
	}

	/// golden capture 整段過機：載入 fixture、feed 全量、finish 收尾未竟狀態，回傳 serializeUTF8 後的輸出 byte 流。
	private func transcodeWhole(_ name: String, target: StreamTranscoder.Target) throws -> [UInt8] {
		let bytes = try loadCapture(name)
		var transcoder: StreamTranscoder = .init(target: target)
		var tokens = transcoder.feed(bytes)
		tokens += transcoder.finish()
		return tokens.serializeUTF8()
	}

	/// 三份 capture 共通驗收：前導已剝、NUL 不漏、輸出非空且為合法 UTF-8。
	private func assertCommonGolden(_ output: [UInt8], name: String) {
		#expect(!output.isEmpty, "\(name): 輸出不應為空")
		#expect(!output.starts(with: Array("HTTP".utf8)), "\(name): HTTP 前導應已剝除")
		#expect(!output.contains(0x00), "\(name): NUL 不應漏進輸出")
		// round-trip：輸出 decode 成 UTF-8 再 encode 回去應 byte 不變（無被切斷的字）。
		let roundTrip: Array = .init(String(decoding: output, as: UTF8.self).utf8)
		#expect(roundTrip == output, "\(name): 輸出應為合法 UTF-8、無丟字 / 切字")
	}

	/// 讀取 test bundle `Captures/` 子目錄的 `<name>.bin` golden fixture；缺檔以 `#require` 直接讓測試失敗、不靜默跳過。
	private func loadCapture(_ name: String) throws -> [UInt8] {
		let url = try #require(
			Bundle.module.url(forResource: name, withExtension: "bin", subdirectory: "Captures"),
			"找不到 capture fixture：\(name).bin"
		)
		return try [UInt8](Data(contentsOf: url))
	}

	/// 樸素子序列搜尋：回傳 needle 在 haystack 首次出現的起始位移（定位 bbsu 的 `ESC[H ESC[2J` 切換錨點用）；無則 nil。
	private func firstIndex(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
		guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
		for start in 0 ... (haystack.count - needle.count) where Array(haystack[start ..< start + needle.count]) == needle {
			return start
		}
		return nil
	}
}
