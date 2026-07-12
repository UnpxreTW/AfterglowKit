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

	/// case 8（研究報告 §③、`decisions.md` D-015）：U+00DC（Ü）→ 0xA0BA，且經 decode 回查等於原字（canonical）。
	@Test
	private func `encode case 8 U+00DC`() {
		#expect(UAO.encode(0x00DC) == 0xA0BA)
		#expect(UAO.decode.lookup(0xA0BA) == 0x00DC)
	}

	/// strict 模式只回傳可逆（canonical）對應；U+00A6（¦）u2b 給的是不可逆 best-fit ASCII 近似（`0x7C20`＝`"| "`）。
	@Test
	private func `encode strict rejects best fit`() {
		#expect(UAO.encode(0x00A6, mode: .strict) == nil)
		#expect(UAO.encode(0x00A6, mode: .bestFit) == 0x7C20)
		// best-fit 值本身不可逆：0x7C 不是合法 Big5 lead（decode 回查為 nil）。
		#expect(UAO.decode.lookup(0x7C20) == nil)
	}

	/// 純哨兵（u2b 全表只有 `0xFFFD` 一列）→ 兩種模式皆回 nil。
	@Test
	private func `encode sentinel returns nil`() {
		#expect(UAO.encode(0x0081) == nil)
		#expect(UAO.encode(0x0081, mode: .bestFit) == nil)
	}

	/// encode 表筆數 = u2b 有對應筆數（canonical 19,316 + best-fit 6,600）。
	@Test
	private func `encode count`() {
		#expect(UAO.encodeTable.keys.count == 25_916)
		#expect(UAO.encodeTable.values.count == 25_916)
		#expect(UAOTable.encodeCount == 25_916)
	}

	/// encode key 陣列必須嚴格遞增（``UAOEncodeTable.lookup`` 二分搜尋的前提）。
	@Test
	private func `encode keys strictly ascending`() {
		let keys = UAO.encodeTable.keys
		for index in 1 ..< keys.count {
			#expect(keys[index] > keys[index - 1])
		}
	}
}
