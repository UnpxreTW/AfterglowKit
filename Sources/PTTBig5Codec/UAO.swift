//
//  PTTBig5Codec
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

/// UAO 對照表的公開存取點：以 lazy `static let` 一次性載入 generated blob。
///
/// `static let` 在 Swift 為執行緒安全的一次性初始化、`UAODecodeTable` 為 `Sendable`，
/// 因此於 Swift 6 strict concurrency 下安全。
/// 目前僅支援解碼：以 Big5 碼 `(lead << 8) | trail` 查 ``decode``。
/// 編碼方向（Unicode→Big5）於支援編碼時另行提供。
///
/// - Note: 公開 symbol 命名（`UAO` / `decode`）為工作名，命名定案前可調整。
public enum UAO {

	/// 解碼正本：完整 Big5-UAO → Unicode（含倚天擴充等全部對應，解碼無歧義）。
	public static let decode: UAODecodeTable = .init(packedZones: UAOTable.zones, expectedCount: UAOTable.decodeCount)
}
