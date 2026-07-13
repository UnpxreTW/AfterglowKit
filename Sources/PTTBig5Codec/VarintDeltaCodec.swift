//
//  PTTBig5Codec
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

/// 共用的 varint 差分序列解碼：首值 LEB128 原值、後續 zigzag-LEB128 差分還原成 `[UInt16]`。
///
/// ``UAODecodeTable``（滿格 Big5 pointer 序列）與 ``UAOEncodeTable``（稀疏 Unicode key／value
/// 兩條並行序列）在儲存層都是「近乎遞增或區域平緩」的 `UInt16` 序列，寫入端由 `afterglowdata`
/// 產生器另行 pack（見 `Generator.encodeVarintZone`），本型別只負責 runtime 端還原、兩者共用同一套邏輯。
enum VarintDeltaCodec {

	/// 解一段 varint 差分序列：首值 LEB128 原值、後續 zigzag-LEB128 差分。
	/// 任何越界／截斷 → `false`（呼叫端 trap 或回 nil）。
	static func decode(_ raw: Data, into values: inout [UInt16]) -> Bool {
		var index = raw.startIndex
		var previous: Int32 = 0
		var isFirst = true
		while index < raw.endIndex {
			var shift: UInt32 = 0
			var accumulated: UInt32 = 0
			while true {
				guard index < raw.endIndex, shift <= 28 else { return false }
				let byte = raw[index]
				index += 1
				accumulated |= UInt32(byte & 0x7F) << shift
				if byte & 0x80 == 0 { break }
				shift += 7
			}
			let value: Int32
			if isFirst {
				value = Int32(bitPattern: accumulated)
				isFirst = false
			} else {
				let delta: Int32 = .init(bitPattern: (accumulated >> 1) ^ (0 &- (accumulated & 1))) // zigzag 還原
				value = previous &+ delta
			}
			guard value >= 0, value <= 0xFFFF else { return false }
			values.append(UInt16(value))
			previous = value
		}
		return true
	}
}
