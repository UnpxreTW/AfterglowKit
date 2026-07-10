//
//  PTTConnectionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTConnection
import Testing

/// [Y/n] prompt 掃描驗證：字元邊界比對、DBCS 誤中防護、跨 chunk、escape 穿插。
private final class DuplicateLoginPromptScannerTests {

	/// `[Y/n]` 的 ASCII bytes。
	private static let pattern: [UInt8] = Array("[Y/n]".utf8)

	/// 純 ASCII 環境直接命中。
	@Test
	private func `detects plain prompt`() {
		var scanner: DuplicateLoginPromptScanner = .init()
		let hit = scanner.scan(Array("delete duplicate? ".utf8) + Self.pattern + [0x20])
		#expect(hit)
		#expect(scanner.detected)
	}

	/// Big5 中文前綴（雙位元組字）之後的 prompt 照樣命中。
	@Test
	private func `detects prompt after big5 text`() {
		var scanner: DuplicateLoginPromptScanner = .init()
		// 「您想刪除…」以任意合法 Big5 pair 代表（lead 0xB1–0xB3 × trail 0xA1）：內容不影響錨定。
		let big5Prefix: [UInt8] = [0xB1, 0xA1, 0xB2, 0xA1, 0xB3, 0xA1, 0x3F, 0x20]
		let hit = scanner.scan(big5Prefix + Self.pattern)
		#expect(hit)
	}

	/// pattern 起頭的 `[` 是某雙位元組字的 trail（0xB3 0x5B 配對）→ 不可誤中。
	@Test
	private func `no match when bracket is dbcs trail`() {
		var scanner: DuplicateLoginPromptScanner = .init()
		// raw byte 搜尋會在 index 1 誤中 [0x5B, 0x59, 0x2F, 0x6E, 0x5D]；DBCS 配對後 0x5B 已被 0xB3 吃掉。
		let bytes: [UInt8] = [0xB3, 0x5B, 0x59, 0x2F, 0x6E, 0x5D]
		let hit = scanner.scan(bytes)
		#expect(!hit)
		#expect(!scanner.detected)
	}

	/// pattern 跨 chunk 邊界持有比對進度。
	@Test
	private func `detects pattern split across chunks`() {
		var scanner: DuplicateLoginPromptScanner = .init()
		let firstHalf = scanner.scan([0x5B, 0x59]) // "[Y"
		#expect(!firstHalf)
		let secondHalf = scanner.scan([0x2F, 0x6E, 0x5D]) // "/n]"
		#expect(secondHalf)
	}

	/// escape 序列穿插在 pattern 之間：略過、不打斷比對。
	@Test
	private func `escape sequence does not break match`() {
		var scanner: DuplicateLoginPromptScanner = .init()
		let sgr: [UInt8] = [0x1B, 0x5B, 0x31, 0x6D] // ESC[1m
		let hit = scanner.scan([0x5B, 0x59] + sgr + [0x2F, 0x6E, 0x5D])
		#expect(hit)
	}

	/// escape 內的 `[Y/n]` 樣式 bytes（OSC 承載）不觸發（escape 全程略過）。
	@Test
	private func `bytes inside escape are ignored`() {
		var scanner: DuplicateLoginPromptScanner = .init()
		let osc: [UInt8] = [0x1B, 0x5D] + Self.pattern + [0x07] // OSC … BEL
		let hit = scanner.scan(osc)
		#expect(!hit)
	}

	/// 一條連線只命中一次：命中後續掃不再回報。
	@Test
	private func `detects only once`() {
		var scanner: DuplicateLoginPromptScanner = .init()
		let first = scanner.scan(Self.pattern)
		#expect(first)
		let second = scanner.scan(Self.pattern)
		#expect(!second)
		#expect(scanner.detected)
	}

	/// mismatch 後可用當前 byte 重新起頭（`[[Y/n]` 這類前綴重疊）。
	@Test
	private func `restarts match on repeated prefix byte`() {
		var scanner: DuplicateLoginPromptScanner = .init()
		let hit = scanner.scan([0x5B] + Self.pattern) // "[[Y/n]"
		#expect(hit)
	}

	/// UAO 使用者定義區 lead（0x81–0xA0）開頭的雙位元組字，其 trail 恰為 `[` 時
	/// 不可被拆開、跟後續真實 ASCII `Y/n]` 誤配成完整 prompt。
	@Test
	private func `no false match when uao lead trail forms bracket`() {
		var scanner: DuplicateLoginPromptScanner = .init()
		// 0x81 為 UAO 使用者定義區 lead（合法範圍 0x81–0xA0）、trail 0x5B 恰為 pattern[0]；
		// 若 lead 未被辨識，0x5B 會落回邊界比對、接上後續 "Y/n]" 誤湊成完整 [Y/n]。
		let bytes: [UInt8] = [0x81, 0x5B, 0x59, 0x2F, 0x6E, 0x5D]
		let hit = scanner.scan(bytes)
		#expect(!hit)
		#expect(!scanner.detected)
	}
}
