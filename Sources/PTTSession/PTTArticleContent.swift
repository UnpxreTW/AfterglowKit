//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTArticleContent

/// 一篇文章的內文讀取結果。
///
/// **範圍**〔已拍板〕：只回內文行 ＋ 推文原始行；推文的結構化欄位（推／噓／箭頭、
/// 推文者、內容、IP、時間）不在本型別範圍，維持另切一站。``commentLines`` 因此是
/// 未經解析的原文，判準只有「這行是不是推文」（見 ``ArticleContentScanner``），
/// 內容本身照單全收。
///
/// **完整性**〔已拍板〕：頁數上限用盡、或行號區間出現斷洞時，``isComplete`` 為
/// `false`——呼叫端據此分得出「文章就這麼長」與「我們沒讀完」，讀取端不靜默截斷。
public struct PTTArticleContent: Equatable, Sendable {

	// MARK: Public

	/// 表頭（作者／標題／時間等）；首行判不出表頭版面時為 `nil`（如精華區純文字檔）。
	public let header: PTTArticleHeader?

	/// 內文行（不含表頭、不含推文），依檔案行號由上而下排序。
	public let bodyLines: [String]

	/// 推文原始行，依檔案行號由上而下排序；未經結構化解析。
	public let commentLines: [String]

	/// 這篇是不是站方判定的可播放動畫（文字動畫／傳統動畫）。
	///
	/// 為 `true` 時 ``bodyLines`` 與 ``commentLines`` 恆為空——引擎偵測到動畫 prompt
	/// 一律答否、不進入本型別的逐頁判讀路徑，原樣位元組交由呈現層另一條路徑播放
	/// （tap A，不在本切片範圍）。
	public let isAnimation: Bool

	/// 是否讀到文章真正的結尾（而非頁數上限用盡或行號斷洞而中止）。
	///
	/// `false` 時 ``bodyLines`` 與 ``commentLines`` 仍是目前收到的部分，不因不完整
	/// 而被丟棄——呼叫端可以先用這部分、只是知道它不是全部。
	public let isComplete: Bool

	/// 建立一份文章內文讀取結果。
	public init(
		header: PTTArticleHeader?,
		bodyLines: [String],
		commentLines: [String],
		isAnimation: Bool,
		isComplete: Bool
	) {
		self.header = header
		self.bodyLines = bodyLines
		self.commentLines = commentLines
		self.isAnimation = isAnimation
		self.isComplete = isComplete
	}
}
