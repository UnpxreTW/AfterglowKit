//
//  PTTConnection
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - DuplicateLoginPromptScanner

/// 在 raw Big5 + ANSI 下行流中偵測「刪除重複登入連線」的 `[Y/n]` prompt。
///
/// 同帳號已有 ≥3 條連線時，登入流程會出現
/// 「您想刪除其他重複登入的連線嗎？[Y/n]」（mbbsd `multi_user_check()`、
/// prompt 前後帶 0–1s / 0–5s 隨機延遲）。錨定尾端 ASCII `[Y/n]`——
/// 中文前綴可能隨站方改版微調，`[Y/n]` 才是穩定錨。
///
/// 錨定必須 DBCS-aware：`[` `Y` `n` `]` 落在 Big5 trail 範圍（0x40–0x7E），
/// 裸 byte 搜尋可能從某個雙位元組字的 trail 開始誤配；`/`（0x2F）落在該範圍外，
/// 若緊接在某 lead byte 之後反而必然判定為孤 lead 放棄、不影響配對安全性——
/// 因此掃描器維護 lead/trail 配對與 escape 略過狀態，只在字元邊界比對。
public struct DuplicateLoginPromptScanner: Sendable {

	// MARK: Public

	/// 已偵測到 prompt（terminal 狀態、命中後不重置——一條連線只應答一次）。
	public private(set) var detected = false

	/// 吃一段下行 chunk；回傳 true = 本段內首次命中 prompt。
	///
	/// 可任意切割餵入（pattern 跨 chunk 的比對進度、pending lead、escape 狀態皆跨 chunk 持有）。
	public mutating func scan(_ chunk: [UInt8]) -> Bool {
		guard !detected else { return false }
		for byte in chunk {
			consume(byte)
			if detected { return true }
		}
		return false
	}

	/// 建立掃描器（乾淨狀態）。
	public init() {}

	// MARK: Private

	/// escape 序列型別（與 `StreamTranscoder` 的完整性判定同語義）。
	private enum EscapeKind {

		/// 只收到起手 ESC、型別未定。
		case pending

		/// CSI（`ESC [`）：吃到 final byte 0x40–0x7E 結束。
		case csi

		/// SS3（`ESC O`）：再吃一 byte 結束。
		case ss3

		/// OSC（`ESC ]`）：吃到 BEL 結束。
		case osc
	}

	/// 錨定 pattern：ASCII `[Y/n]`。
	private static let pattern: [UInt8] = [0x5B, 0x59, 0x2F, 0x6E, 0x5D]

	/// Big5 trail 合法範圍：0x40–0x7E ∪ 0xA1–0xFE。
	private static func isValidTrail(_ byte: UInt8) -> Bool {
		(0x40 ... 0x7E).contains(byte) || (0xA1 ... 0xFE).contains(byte)
	}

	/// pattern 已比對到的長度。
	private var matched = 0

	/// 持有中的 Big5 lead（等 trail；期間任何 byte 不參與 pattern 比對）。
	private var pendingLead = false

	/// 進行中的 escape 序列（nil = 不在 escape 中；期間 byte 全略過、不參與 pattern 比對）。
	private var escape: EscapeKind?

	/// 單 byte 狀態機：escape 略過 → DBCS 配對 → 字元邊界的 pattern 比對。
	private mutating func consume(_ byte: UInt8) {
		if let kind = escape {
			continueEscape(kind, byte: byte)
			return
		}
		if byte == 0x1B { // ESC 起手（DBCS 中夾 escape 照舊持有 lead）
			escape = .pending
			return
		}
		if pendingLead {
			// 合法 trail → 配對成雙位元組字；非法 trail → 孤 lead 放棄、byte 落回邊界比對。
			pendingLead = false
			if Self.isValidTrail(byte) {
				matched = 0 // 雙位元組字打斷 pattern
				return
			}
		}
		if byte >= 0x81, byte <= 0xFE { // Big5 lead：持有、打斷 pattern（含 UAO 使用者定義區 0x81–0xA0）
			pendingLead = true
			matched = 0
			return
		}
		matchPattern(byte)
	}

	/// escape 序列續收：依型別判定結束點（CSI final byte / SS3 一 byte / OSC 到 BEL / 其餘兩 byte）。
	private mutating func continueEscape(_ kind: EscapeKind, byte: UInt8) {
		switch kind {
		case .pending:
			switch byte {
			case 0x5B: escape = .csi
			case 0x4F: escape = .ss3
			case 0x5D: escape = .osc
			default: escape = nil // 兩 byte escape 到此結束
			}
		case .csi:
			if (0x40 ... 0x7E).contains(byte) { escape = nil } // final byte
		case .ss3:
			escape = nil
		case .osc:
			if byte == 0x07 { escape = nil } // BEL
		}
	}

	/// 字元邊界上的 pattern 前綴比對（mismatch 時允許以當前 byte 重新起頭）。
	private mutating func matchPattern(_ byte: UInt8) {
		if byte == Self.pattern[matched] {
			matched += 1
			if matched == Self.pattern.count {
				detected = true
			}
		} else {
			matched = (byte == Self.pattern[0]) ? 1 : 0
		}
	}
}
