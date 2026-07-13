//
//  PTTBig5Codec
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

/// Big5-UAO → Unicode 解碼表：value-only 密集陣列 + O(1) 算術查表。
///
/// UAO 2.50 的 b2u 是 **100% 滿格 grid**——126 個 lead（0x81–0xFE）× 157 個合法
/// trail（0x40–0x7E ∪ 0xA1–0xFE）＝ 19,782 筆、無空洞——因此 key 可由標準 Big5
/// pointer 公式推導、不需儲存：`index = (lead - 0x81) * 157 + trail 偏移`。
///
/// 儲存形式為分 zone 的 varint 串（首值 LEB128、後續 zigzag-LEB128 差分；
/// UAO 各區 value 近乎遞增、差分多為 1 byte），載入時展開成單一 `[UInt16]`。
/// 只持一個 value 陣列、無參考型別 → `Sendable`，可安全做 global `static let`。
public struct UAODecodeTable: Sendable {

	// MARK: Public

	/// 每個 lead 的合法 trail 數：0x40–0x7E（63）＋ 0xA1–0xFE（94）。
	public static let trailsPerLead = 157

	/// 合法 lead byte 範圍：UAO 2.50 b2u 為滿格 grid，0x81–0xFE 共 126 個 lead 全數有值，越界即非雙位元組首碼。
	public static let leadRange: ClosedRange<UInt8> = 0x81 ... 0xFE

	/// pointer 順序（lead 主序、trail 次序）的 Unicode scalar 值。
	public let values: [UInt16]

	/// 以 Big5 碼 `(lead << 8) | trail` 查表；lead / trail 非法或表空 → `nil`。
	public func lookup(_ key: UInt16) -> UInt16? {
		guard
			let index = UAODecodeTable.pointer(lead: UInt8(key >> 8), trail: UInt8(key & 0xFF)),
			index < values.count
		else { return nil }
		return values[index]
	}

	// MARK: Package

	/// 從 base64 字串陣列載入（產生器寫檔前自驗用；同一 package 內可見）。
	package init?(base64Zones: [String], expectedCount: Int) {
		var decoded: [UInt16] = []
		decoded.reserveCapacity(expectedCount)
		for zone in base64Zones {
			guard
				let raw = Data(base64Encoded: zone),
				VarintDeltaCodec.decode(raw, into: &decoded)
			else { return nil }
		}
		guard decoded.count == expectedCount else { return nil }
		self.values = decoded
	}

	// MARK: Lifecycle

	/// 直接以 value 陣列建構（內部 / 測試用；空陣列＝一律查不到）。
	init(values: [UInt16]) {
		self.values = values
	}

	/// 從 generated 的分 zone base64 varint `StaticString` 載入（runtime 正路）。
	///
	/// 依序解碼各 zone 串接成完整 pointer 空間；筆數不符或串損毀 → trap
	/// （提交的 blob 損毀，重跑 `swift run afterglowdata generate` 修復）。
	init(packedZones: [StaticString], expectedCount: Int) {
		var decoded: [UInt16] = []
		decoded.reserveCapacity(expectedCount)
		for zone in packedZones {
			let data = zone.withUTF8Buffer { Data($0) }
			guard
				let raw = Data(base64Encoded: data),
				VarintDeltaCodec.decode(raw, into: &decoded)
			else {
				fatalError("UAOTable zone blob 損毀 — 重跑：swift run afterglowdata generate")
			}
		}
		guard decoded.count == expectedCount else {
			fatalError(
				"UAOTable 筆數不符（\(decoded.count) ≠ \(expectedCount)）— 重跑：swift run afterglowdata generate"
			)
		}
		self.values = decoded
	}

	// MARK: Internal

	/// 標準 Big5 pointer 公式；非法 lead / trail → `nil`。
	static func pointer(lead: UInt8, trail: UInt8) -> Int? {
		guard leadRange.contains(lead) else { return nil }
		let trailOffset: Int
		switch trail {
		case 0x40 ... 0x7E: trailOffset = Int(trail) - 0x40
		case 0xA1 ... 0xFE: trailOffset = Int(trail) - 0xA1 + 63
		default: return nil
		}
		return (Int(lead) - 0x81) * trailsPerLead + trailOffset
	}
}
