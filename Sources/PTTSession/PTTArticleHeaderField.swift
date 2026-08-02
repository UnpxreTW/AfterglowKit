//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTArticleHeaderField

/// 文章表頭的一組「名稱 → 值」。
///
/// !!!: 名稱與值以每列**第一段連續兩個以上空白**切開，不用欄位常數——pmore 會依終端寬度
/// 重排表頭（見 ``PTTArticleHeader`` 型別註解），沒有像清單畫面那樣的定寬版面可移植。
/// 這是盡力而為的行級切法，右浮的第二欄位（如首列右側的「看板」）不會被切出來、
/// 會整段留在 ``value`` 裡；要精確結構化得另外解析浮動欄位，不在本切片範圍。
public struct PTTArticleHeaderField: Equatable, Sendable {

	// MARK: Public

	/// 欄位名稱（如「作者」「標題」「時間」）。
	public let name: String

	/// 欄位值（可能夾帶右浮的第二欄位原文，見型別註解）。
	public let value: String

	/// 建立一組表頭欄位。
	public init(name: String, value: String) {
		self.name = name
		self.value = value
	}
}
