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

/// 對已提交的 generated 表做 decode spot-check 與完整性 assert。
private final class UAOTableTests {

	/// 0xC6E7 → ぁ U+3041，且 canary：不可解出 ゃ U+3083（誤觸＝載到舊/錯表）。
	@Test
	private func `hiragana small a canary`() {
		#expect(UAO.decode.lookup(0xC6E7) == 0x3041)
		#expect(UAO.decode.lookup(0xC6E7) != 0x3083)
	}

	/// 0xF9FA → ╭ U+256D（倚天擴充線繪字、登入 banner 第一屏即有）。
	@Test
	private func `box drawing`() {
		#expect(UAO.decode.lookup(0xF9FA) == 0x256D)
	}

	/// 0xA140 → 全形空格 U+3000。
	@Test
	private func `fullwidth space`() {
		#expect(UAO.decode.lookup(0xA140) == 0x3000)
	}

	/// decode 正本筆數 = 完整 b2u 19,782 = 126 lead × 157 trail（滿格）。
	@Test
	private func `decode count`() {
		#expect(UAO.decode.values.count == 19_782)
		#expect(UAO.decode.values.count == (126 * UAODecodeTable.trailsPerLead))
		#expect(UAOTable.decodeCount == 19_782)
	}

	/// 滿格表無 U+0000 對應（varint 解碼 / 對齊錯位的哨兵檢查）。
	@Test
	private func `no null values`() {
		#expect(!UAO.decode.values.contains(0))
	}

	/// 非法 lead / trail 一律回 nil（合法 key 因滿格必命中）。
	@Test
	private func `invalid key returns nil`() {
		#expect(UAO.decode.lookup(0x0041) == nil) // lead 0x00：非 Big5
		#expect(UAO.decode.lookup(0x8039) == nil) // trail 0x39 < 0x40
		#expect(UAO.decode.lookup(0xA17F) == nil) // trail 0x7F：合法區間外
		#expect(UAO.decode.lookup(0xFF40) == nil) // lead 0xFF > 0xFE
	}

	/// pointer 公式邊界：四個角落 key 都可解（滿格前提）。
	@Test
	private func `pointer corners`() {
		#expect(UAO.decode.lookup(0x8140) != nil) // 第一格
		#expect(UAO.decode.lookup(0x81FE) != nil) // 首 lead 末 trail
		#expect(UAO.decode.lookup(0xFE40) != nil) // 末 lead 首 trail
		#expect(UAO.decode.lookup(0xFEFE) == 0x8288) // 最後一格（uao250 末行）
	}
}
