//
//  PTTBig5Codec
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

/// UAO 對照表的公開存取點：以 lazy `static let` 一次性載入 generated blob。
///
/// `static let` 在 Swift 為執行緒安全的一次性初始化、`UAODecodeTable` / `UAOEncodeTable`
/// 皆為 `Sendable`，因此於 Swift 6 strict concurrency 下安全。
/// 解碼：以 Big5 碼 `(lead << 8) | trail` 查 ``decode``。
/// 編碼：Unicode scalar → Big5-UAO，見 ``encode(_:mode:)``。
///
/// - Note: 公開 symbol 命名（`UAO` / `decode` / `encode`）為工作名，命名定案前可調整。
public enum UAO {

	/// 解碼正本：完整 Big5-UAO → Unicode（含倚天擴充等全部對應，解碼無歧義）。
	public static let decode: UAODecodeTable = .init(packedZones: UAOTable.zones, expectedCount: UAOTable.decodeCount)

	/// 編碼正本：Unicode → Big5-UAO（u2b 表中「有對應」的 25,916 筆；`0xFFFD` 哨兵不落表）。
	public static let encodeTable: UAOEncodeTable = .init(
		packedKeys: UAOTable.encodeKeys,
		packedValues: UAOTable.encodeValues,
		expectedCount: UAOTable.encodeCount
	)

	/// 編碼：Unicode scalar → Big5-UAO 2-byte 原始輸出值（`(byte0 << 8) | byte1`）。
	///
	/// - Parameter mode: `.strict`（預設）僅回傳可逆（經 ``decode`` 回查等於原字）的 canonical
	///   對應；`.bestFit` 額外允許不可逆的近似替代（如 `U+00A6 → 0x7C20`＝`"| "` ASCII 近似）。
	///   u2b 表本身即混合 canonical／best-fit／sentinel 三類、不可整表盲吞，
	///   預設 strict 是刻意的保守門檻。
	public static func encode(_ scalar: UInt16, mode: UAOEncodeMode = .strict) -> UInt16? {
		guard let raw = encodeTable.lookup(scalar) else { return nil }
		guard mode == .bestFit else {
			return decode.lookup(raw) == scalar ? raw : nil
		}
		return raw
	}
}
