//
//  PTTBig5Codec
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

/// Unicode → Big5-UAO 編碼表：稀疏 key（Unicode scalar）＋ 遞增陣列二分搜尋。
///
/// 與 ``UAODecodeTable`` 的滿格 grid 不同，u2b 的 Unicode key 空間稀疏、無法用
/// pointer 公式推導，因此改用 (key, value) 兩條索引對齊的遞增陣列 + 二分搜尋
/// （即 decode 表優化前退場的 pair 表示法，encode 方向仍適用）。
///
/// `values[i]` 為兩個原始輸出 byte 組成的 `(byte0 << 8) | byte1`：多數是合法
/// Big5 lead/trail pair，少數是 u2b 表本身提供的 ASCII 近似替代（如
/// `U+00A6 → 0x7C20`＝`"| "`）——兩者在儲存層一視同仁，可逆性（canonical／
/// best-fit）由呼叫端對照 ``UAODecodeTable`` 動態判定（見 `UAO.encode(_:mode:)`），
/// 不另外持久化分類位元。
///
/// 只收 u2b 表中「有對應」的筆數；`0xFFFD` 哨兵（無對應）語意等價於查無、不落表。
public struct UAOEncodeTable: Sendable {

	// MARK: Public

	/// 遞增排序、去重的 Unicode scalar key，與 `values` 索引對齊。
	public let keys: [UInt16]

	/// 對應輸出 2-byte 原始值（`(byte0 << 8) | byte1`），索引與 `keys` 對齊。
	public let values: [UInt16]

	/// 以 Unicode scalar 查表；二分搜尋、無對應（含原表 `0xFFFD` 哨兵）→ `nil`。
	public func lookup(_ scalar: UInt16) -> UInt16? {
		var low = 0
		var high = keys.count - 1
		while low <= high {
			let mid = (low + high) / 2
			if keys[mid] == scalar {
				return values[mid]
			} else if keys[mid] < scalar {
				low = mid + 1
			} else {
				high = mid - 1
			}
		}
		return nil
	}

	// MARK: Package

	/// 從 base64 key／value 兩段載入（產生器寫檔前自驗用；同一 package 內可見）。
	package init?(base64Keys: String, base64Values: String, expectedCount: Int) {
		guard let keyRaw = Data(base64Encoded: base64Keys), let valueRaw = Data(base64Encoded: base64Values) else {
			return nil
		}
		var decodedKeys: [UInt16] = []
		var decodedValues: [UInt16] = []
		decodedKeys.reserveCapacity(expectedCount)
		decodedValues.reserveCapacity(expectedCount)
		guard
			VarintDeltaCodec.decode(keyRaw, into: &decodedKeys),
			VarintDeltaCodec.decode(valueRaw, into: &decodedValues),
			decodedKeys.count == expectedCount,
			decodedValues.count == expectedCount
		else { return nil }
		self.keys = decodedKeys
		self.values = decodedValues
	}

	// MARK: Lifecycle

	/// 直接以 key／value 陣列建構（內部 / 測試用；必須遞增排序、索引對齊，呼叫端自負）。
	init(keys: [UInt16], values: [UInt16]) {
		self.keys = keys
		self.values = values
	}

	/// 從 generated 的 base64 varint `StaticString` 一對載入（runtime 正路）。
	///
	/// 筆數不符或串損毀 → trap（提交的 blob 損毀，重跑 `swift run afterglowdata generate` 修復）。
	init(packedKeys: StaticString, packedValues: StaticString, expectedCount: Int) {
		var decodedKeys: [UInt16] = []
		var decodedValues: [UInt16] = []
		decodedKeys.reserveCapacity(expectedCount)
		decodedValues.reserveCapacity(expectedCount)
		let keyData = packedKeys.withUTF8Buffer { Data($0) }
		let valueData = packedValues.withUTF8Buffer { Data($0) }
		guard
			let keyRaw = Data(base64Encoded: keyData),
			let valueRaw = Data(base64Encoded: valueData),
			VarintDeltaCodec.decode(keyRaw, into: &decodedKeys),
			VarintDeltaCodec.decode(valueRaw, into: &decodedValues),
			decodedKeys.count == expectedCount,
			decodedValues.count == expectedCount
		else {
			fatalError("UAOTable encode blob 損毀 — 重跑：swift run afterglowdata generate")
		}
		self.keys = decodedKeys
		self.values = decodedValues
	}
}
