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
/// **推文有兩層**：``commentLines`` 是站方原文照單全收，判準只有「這行是不是推文」
/// （見 ``ArticleContentScanner/isCommentLine(_:)``）；``comments`` 是把那些原文判讀成結構化
/// 欄位的結果。原文是正本、結構化是衍生視圖——``PTTComment`` 的內容欄前後空白已去除、判讀
/// 不出格式的列也不在裡面，要逐字保真、或要看那些判讀不出來的列，只有原文有。
///
/// 〔沿革〕結構化欄位原先拍板「不進本型別、另切一站」；那一站落地後以衍生視圖接回來，
/// 等於把該範圍裁定放寬到「不另存、但可從原始行導出」。原始行仍是正本。
///
/// **完整性**〔已拍板〕：頁數上限用盡、或行號區間出現斷洞時，``isComplete`` 為
/// `false`——呼叫端據此分得出「文章就這麼長」與「我們沒讀完」，讀取端不靜默截斷。
///
/// ``unparsedCommentLineCount`` 是另一個訊號、不是同一件事的別名：它數的是「前綴像推文、
/// 卻判不出站方格式」的列，成因不只一種（見該屬性）。兩個訊號分開，是因為成因不同、
/// 該做的事也不同。
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

	/// 由 ``commentLines`` 判讀出的結構化推文，依**檔案行號**由上而下排序。
	///
	/// 排序依據刻意是檔案行號而非 ``PTTComment/time``——站方那一欄不給年份，跨年文章排不出
	/// 正確先後。判讀不出站方格式的列不在其中（不會被湊成半組欄位混進來），數量走
	/// ``unparsedCommentLineCount``。
	///
	/// !!!: **來源位址欄的有無是整篇一起判的，而且它同時決定 ``PTTComment/message`` 切在哪裡**
	/// ——判成有位址欄時，內容尾端那一段會被切出去當 ``PTTComment/sourceIP``；判成沒有時，
	/// 同一段字留在內容裡。判準是「每一則都取得出位址才算有」，所以**只有一則推文的文章**會
	/// 退化成單則猜測，而 ``isComplete`` 為 `false` 時是拿收到的部分去判、可能與讀完整篇得出
	/// 不同結論。另一個判不準的方向是位址剛好佔滿十五格、內容也剛好填滿定寬——兩段之間沒有
	/// 空白可切，整篇會判成沒有位址欄、位址就留在內容尾端（見 ``ArticleCommentScanner``）。
	/// 受影響的不只位址欄——拿 ``PTTComment/message`` 做比對或去重的呼叫端同樣吃這個切點。
	///
	/// 判成哪一邊**在本屬性非空時**看得出來：判成有的話每一則的 ``PTTComment/sourceIP`` 都非
	/// `nil`。本屬性為空時無從觀察，不過那種情形整批判定必定是「沒有」，也沒有推文會受影響。
	///
	/// - Complexity: 與 ``commentLines`` 的長度成正比，每次存取重跑一次；每次重跑把每一列拆
	///   **一趟**，整批判定（有沒有位址欄）與逐則取欄位共用那一份結果，所以與
	///   ``unparsedCommentLineCount`` 兩個屬性各存取一次就是兩趟。這裡刻意不把判讀結果存起來：
	///   它從 ``commentLines`` 就推導得出來，存第二份的代價是兩份有機會不同步。
	public var comments: [PTTComment] {
		ArticleCommentScanner.comments(from: commentLines)
	}

	/// ``commentLines`` 裡「前綴像推文、卻判不出站方格式」的列數。
	///
	/// !!!: 大於零**不必然**代表判讀規則有問題。進 ``commentLines`` 的判準只看行首記號
	/// （見 ``ArticleContentScanner/isCommentLine(_:)``）、是刻意放寬的過近似，因此已知至少
	/// 三種成因：內文行剛好以「推 」「噓 」「→ 」開頭而被收了進來、畫面殘影把行尾吃掉、
	/// 站方改了寫檔格式。原文都還在 ``commentLines`` 裡、可自行判斷是哪一種——但只有第一種
	/// 一眼認得出來，後兩種在單一列上長得一樣，要看整篇是不是全體判不出來才分得開。
	///
	/// 這個數字存在的理由與 ``isComplete`` 同一條：讓型別自己說出「有東西沒收乾淨」，
	/// 而不是讓呼叫端自己想到要去比兩個陣列的長度差。
	///
	/// - Complexity: 成本同 ``comments``（每一列拆一趟）；兩個屬性各存取一次就是兩趟。
	public var unparsedCommentLineCount: Int {
		commentLines.count - comments.count
	}

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
