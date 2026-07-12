//
//  afterglowdata
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import PTTBig5Codec

/// decode 方向（Big5-UAO → Unicode）的斷言與 pack：b2u 滿格展開 → 六 zone varint →
/// 以真實 ``UAODecodeTable`` loader 做全表 round-trip 自驗。
enum DecodeTableGenerator {

	/// 六個 zone：lead 範圍 + 內容描述；滿格前提下筆數 = lead 數 × 157。
	struct Zone {

		/// 滿格前提下本 zone 筆數：lead 數 × 每 lead 157 trail。
		var expectedCount: Int { (Int(leadHigh) - Int(leadLow) + 1) * UAODecodeTable.trailsPerLead }

		/// zone 常數識別字，原樣寫入產生檔作 StaticString 名稱。
		let name: String

		/// zone 起始 lead byte（含）。
		let leadLow: UInt8

		/// zone 結束 lead byte（含）。
		let leadHigh: UInt8

		/// 寫入產生檔的區段中文說明（描述該 lead 範圍收錄的內容）。
		let comment: String
	}

	/// decode 斷言與 pack 完成後的產出：六 zone 各自的 base64 varint 串。
	struct Result {

		/// 依 `zones` 順序對齊的 pack 結果。
		let packedZones: [String]
	}

	/// 六個 zone 的 lead 分區定義；依 lead 遞增排列、串接即涵蓋完整 Big5 pointer 空間。
	static let zones: [Zone] = [
		Zone(
			name: "zoneUserDefined",
			leadLow: 0x81,
			leadHigh: 0xA0,
			comment: "UAO 使用者定義區（標準 Big5 未收的罕用漢字為主、近乎 Unicode 遞增）"
		),
		Zone(
			name: "zoneSymbols",
			leadLow: 0xA1,
			leadHigh: 0xA3,
			comment: "標準 Big5 符號區"
		),
		Zone(
			name: "zoneHanziL1",
			leadLow: 0xA4,
			leadHigh: 0xC6,
			comment: "標準 Big5 常用字 Level 1"
		),
		Zone(
			name: "zoneKanaCyrillic",
			leadLow: 0xC7,
			leadHigh: 0xC8,
			comment: "倚天／UAO 假名・西里爾區"
		),
		Zone(
			name: "zoneHanziL2",
			leadLow: 0xC9,
			leadHigh: 0xF9,
			comment: "標準 Big5 次常用字 Level 2"
		),
		Zone(
			name: "zoneExtension",
			leadLow: 0xFA,
			leadHigh: 0xFE,
			comment: "UAO 延伸區（倚天線繪等）"
		)
	]

	/// pointer 次序的合法 trail 序列：0x40–0x7E、再 0xA1–0xFE。
	static let trailSequence: [UInt8] = Array(0x40 ... 0x7E) + Array(0xA1 ... 0xFE)

	/// 滿格展開 → pack → 自驗，回傳六 zone 的 base64 varint 串。
	static func build(b2u: [UInt16: UInt16]) throws -> Result {
		let zoneValues = try denseZoneValues(b2u: b2u)
		let packed = zoneValues.map { Generator.packVarint($0) }
		try validate(packedZones: packed, b2u: b2u)
		return Result(packedZones: packed)
	}

	/// value-only 密集表示的前提：126 lead × 157 trail 滿格。任一格缺 → hard-fail
	/// （上游若出洞，此表示法不再成立、需回退 (key, value) pair 方案）。
	static func denseZoneValues(b2u: [UInt16: UInt16]) throws -> [[UInt16]] {
		var result: [[UInt16]] = []
		for zone in zones {
			var values: [UInt16] = []
			values.reserveCapacity(zone.expectedCount)
			for lead in zone.leadLow ... zone.leadHigh {
				for trail in trailSequence {
					let key = (UInt16(lead) << 8) | UInt16(trail)
					guard let uni = b2u[key] else {
						throw GeneratorError.validation("滿格斷言失敗：\(Generator.hex(key)) 無對應（value-only 密集表示前提不成立）")
					}
					guard uni != 0 else {
						throw GeneratorError.validation("\(Generator.hex(key)) 對應 U+0000（非法 value）")
					}
					values.append(uni)
				}
			}
			try Generator.expect("\(zone.name) 筆數", values.count, zone.expectedCount)
			result.append(values)
		}
		return result
	}

	/// 寫檔前自驗：以真實 ``UAODecodeTable`` loader 解回 packed bytes、全表 19,782 筆 round-trip、
	/// spot-check 含 canary 與非法 key 檢查。
	static func validate(packedZones: [String], b2u: [UInt16: UInt16]) throws {
		guard let table = UAODecodeTable(base64Zones: packedZones, expectedCount: Generator.expectedB2UCount) else {
			throw GeneratorError.validation("decode zone blob 無法 round-trip 解析")
		}
		// 全表 round-trip：19,782 筆逐一比對（涵蓋滿格、排序、varint 正確性）。
		for (key, expected) in b2u {
			guard table.lookup(key) == expected else {
				let gotText = table.lookup(key).map { Generator.hex($0) } ?? "nil"
				throw GeneratorError.validation("decode round-trip \(Generator.hex(key))：\(gotText) ≠ \(Generator.hex(expected))")
			}
		}
		// spot-check（含 canary：0xC6E7 誤觸 ゃ ＝ 載到舊/錯表）。
		try check(table, 0xC6E7, 0x3041, "ぁ U+3041")
		if table.lookup(0xC6E7) == 0x3083 {
			throw GeneratorError.validation("canary：0xC6E7 解出 ゃ(U+3083)、應為 ぁ(U+3041) — 載到舊/錯表")
		}
		try check(table, 0xF9FA, 0x256D, "╭ U+256D")
		try check(table, 0xF9DE, 0x2566, "╦ U+2566")
		try check(table, 0xA140, 0x3000, "全形空格 U+3000")
		try check(table, 0xB35C, 0x8A31, "許 U+8A31")
		// 非法 key 必回 nil。
		for bad: UInt16 in [0x0041, 0x8039, 0xA17F, 0xFF40] where table.lookup(bad) != nil {
			throw GeneratorError.validation("非法 key \(Generator.hex(bad)) 應回 nil")
		}
	}

	/// spot-check 單筆：decode lookup 結果須等於期望 Unicode，否則 throw `.validation`。
	static func check(_ table: UAODecodeTable, _ key: UInt16, _ expected: UInt16, _ name: String) throws {
		let got = table.lookup(key)
		guard got == expected else {
			let gotText = got.map { Generator.hex($0) } ?? "nil"
			throw GeneratorError.validation(
				"spot-check \(name)：lookup(\(Generator.hex(key))) = \(gotText)、應為 \(Generator.hex(expected))"
			)
		}
	}
}
