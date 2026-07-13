//
//  PTTTerminal
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTCell

/// 螢幕格子矩陣的單一格。
///
/// Big5 全形字（含 UAO 解碼出的字）在畫面上佔兩欄：本 cell 的 ``width`` 為 2，
/// 其後緊接一個 ``width`` 為 0 的延續格（承載該全形字佔用的第二欄、不可獨立渲染）——
/// 對映 SwiftTerm 內部把寬字元第二欄存成 `code: 0, size: 0` 的慣例（v1.13.0 原始碼核對）。
/// 呼叫端渲染遇 `width == 0` 應跳過該欄（前一格的 `width == 2` 已涵蓋）。
public struct PTTCell: Equatable, Sendable {

	/// 顯示字元。未寫入／已清空的格一律正規化為半形空白——SwiftTerm 內部以 NUL（U+0000）
	/// 表示這類格，該編碼對下游渲染沒有意義，故在此層正規化、呼叫端不需再處理 NUL。
	public let character: Character

	/// 本格佔用的欄數：1（一般字）、2（全形字首欄）、0（全形字延續格，見型別註解）。
	public let width: Int

	/// 前景色。
	public let foregroundColor: PTTColor

	/// 背景色。
	public let backgroundColor: PTTColor

	/// 文字樣式旗標。
	public let attributes: PTTAttributes

	/// 建立一個 cell。
	public init(
		character: Character,
		width: Int,
		foregroundColor: PTTColor,
		backgroundColor: PTTColor,
		attributes: PTTAttributes
	) {
		self.character = character
		self.width = width
		self.foregroundColor = foregroundColor
		self.backgroundColor = backgroundColor
		self.attributes = attributes
	}
}
