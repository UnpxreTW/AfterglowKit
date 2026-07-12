//
//  afterglowdata
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import PTTBig5Codec

/// encode 方向（Unicode → Big5-UAO）的斷言與 pack：u2b 稀疏、無法套用 decode 的密集陣列
/// 表示法，改用遞增 key／value 兩段陣列 + 二分搜尋；同樣以真實 ``UAOEncodeTable`` loader
/// 做全表 round-trip 自驗。
enum EncodeTableGenerator {

	/// encode 斷言與 pack 完成後的產出：key／value 兩段 base64 varint 串，附原始陣列供上游列印筆數。
	struct Result {

		/// 遞增排序的 Unicode scalar key（未 pack，供呼叫端取筆數 / 列印）。
		let keys: [UInt16]

		/// key 對齊的 2-byte 原始輸出值（未 pack）。
		let values: [UInt16]

		/// `keys` pack 後的 base64 varint 串。
		let packedKeys: String

		/// `values` pack 後的 base64 varint 串。
		let packedValues: String
	}

	/// u2b 非哨兵列 → encode key／value 陣列 → pack → 自驗，回傳 ``Result``。
	static func build(u2b: [(big5: UInt16, unicode: UInt16)], b2u: [UInt16: UInt16]) throws -> Result {
		let (keys, values) = try buildArrays(u2b: u2b, b2u: b2u)
		// swiftformat:disable:next redundantType — packVarint() 回傳 String，非 Generator 自身（已知坑）。
		let packedKeys: String = Generator.packVarint(keys)
		let packedValues: String = Generator.packVarint(values)
		try validate(packedKeys: packedKeys, packedValues: packedValues, keys: keys, values: values)
		return Result(keys: keys, values: values, packedKeys: packedKeys, packedValues: packedValues)
	}

	/// u2b 非哨兵列 → encode key／value 陣列（遞增 Unicode key、對齊 raw 2-byte value）；
	/// 同時驗總筆數／哨兵筆數／有對應筆數，以及 canonical／best-fit 二分（對照 b2u 回查）。
	static func buildArrays(
		u2b: [(big5: UInt16, unicode: UInt16)],
		b2u: [UInt16: UInt16]
	) throws -> (keys: [UInt16], values: [UInt16]) {
		try Generator.expect("u2bCount", u2b.count, Generator.expectedU2BCount)
		var keys: [UInt16] = []
		var values: [UInt16] = []
		keys.reserveCapacity(Generator.expectedEncodeCount)
		values.reserveCapacity(Generator.expectedEncodeCount)
		var sentinelCount = 0
		var canonicalCount = 0
		var bestFitCount = 0
		var previousKey: UInt16?
		for row in u2b {
			if let previous = previousKey {
				guard row.unicode > previous else {
					throw GeneratorError.validation("u2b 非遞增或重複 key：\(Generator.hex(row.unicode))")
				}
			}
			previousKey = row.unicode
			if row.big5 == 0xFFFD {
				sentinelCount += 1
				continue
			}
			guard row.big5 != 0 else {
				throw GeneratorError.validation("\(Generator.hex(row.unicode)) 對應 0x0000（非法 value）")
			}
			keys.append(row.unicode)
			values.append(row.big5)
			if b2u[row.big5] == row.unicode {
				canonicalCount += 1
			} else {
				bestFitCount += 1
			}
		}
		try Generator.expect("u2bSentinelCount", sentinelCount, Generator.expectedU2BSentinelCount)
		try Generator.expect("encodeCount", keys.count, Generator.expectedEncodeCount)
		try Generator.expect("encodeCanonicalCount", canonicalCount, Generator.expectedCanonicalCount)
		try Generator.expect("encodeBestFitCount", bestFitCount, Generator.expectedBestFitCount)
		return (keys, values)
	}

	/// 寫檔前自驗：以真實 ``UAOEncodeTable`` loader 解回 packed bytes、全表逐一 round-trip、
	/// spot-check（含研究報告 §③ case 8：U+00DC → 0xA0BA）。
	static func validate(packedKeys: String, packedValues: String, keys: [UInt16], values: [UInt16]) throws {
		guard
			let table = UAOEncodeTable(base64Keys: packedKeys, base64Values: packedValues, expectedCount: keys.count)
		else {
			throw GeneratorError.validation("encode blob 無法 round-trip 解析")
		}
		for (key, expected) in zip(keys, values) {
			guard table.lookup(key) == expected else {
				let gotText = table.lookup(key).map { Generator.hex($0) } ?? "nil"
				throw GeneratorError.validation("encode round-trip \(Generator.hex(key))：\(gotText) ≠ \(Generator.hex(expected))")
			}
		}
		// case 8（研究報告 §③、`decisions.md` D-015）：U+00DC（Ü）→ 0xA0BA。
		guard table.lookup(0x00DC) == 0xA0BA else {
			throw GeneratorError.validation("encode spot-check U+00DC：應為 0xA0BA")
		}
		// 純哨兵（無對應）必回 nil：0x0081 全表只有 0xFFFD 一列。
		guard table.lookup(0x0081) == nil else {
			throw GeneratorError.validation("encode 非法 key 0x0081（純哨兵）應回 nil")
		}
	}
}
