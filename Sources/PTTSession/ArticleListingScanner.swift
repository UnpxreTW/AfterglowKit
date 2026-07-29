//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import PTTTerminal

// MARK: - ArticleListingScanner

/// 把看板文章清單畫面判讀成 ``PTTArticleSummary``。
///
/// **欄位位置是站方版面的定值**，取自原始碼裡實際印出每一列的那串格式
/// （`%7d` 編號、一格空白、一格狀態記號、兩格推文數、`%-6.5s` 日期、`%-13.12s` 作者、
/// 兩格類別記號、一格空白、標題）——來源 https://github.com/ptt/pttbbs 的 `mbbsd/bbs.c`
/// （`readdoent()`）。
///
/// !!!: **按格子切、不按字元切**。既有的 Python 實作是把畫面攤成字串再用字元位置切欄，
/// 那在推文數欄出現全形字（「爆」）時整排會往前錯一格、作者與標題全歪掉。我們手上有
/// 完整的格子矩陣，直接按欄位切就沒有這個問題，故此處刻意不照抄上游的切法。
public enum ArticleListingScanner {

	// MARK: Public

	/// 略過的表頭列數（看板標題、快捷鍵提示、欄位說明佔畫面最上方三列）。
	public static let headerLineCount = 3

	/// 略過的底部列數（最後一列是功能提示列、不是文章）。
	public static let footerLineCount = 1

	/// 編號欄最左側保留給游標記號的欄數。
	///
	/// 站方把編號印成右對齊七欄，而原始碼在那一行的註解裡言明那七欄是「五位數 ＋ 兩欄游標
	/// 記號」；游標本身是 `>`（一欄）或全形圓點（兩欄），移到別列時又是以同寬空白覆蓋回去、
	/// 不把原本的數字補回來。也就是說**編號欄最左邊這兩欄隨時可能不是數字**。
	public static let cursorReservedColumns = 2

	/// 一張畫面上最多有幾列的編號可能被游標記號蓋掉。
	///
	/// 站方一次只畫一個游標：現在停的那一列被記號蓋住，剛離開的那一列被空白蓋回去。
	/// 需要重建的列多過這個數量，那就不是游標造成的，而是這張畫面根本不是同一頁。
	public static let cursorAffectedRowLimit = 2

	/// 判讀整張畫面上所有能認出來的文章列（依畫面由上而下，即編號遞增）。
	///
	/// 認不出編號的列（置底文、空白列、殘影）直接略過——清單畫面本來就混著這些東西，
	/// 略過它們是正常判讀的一部分，不是失敗。整張畫面一列都認不出來才由呼叫端當作
	/// 判讀失敗處理。
	///
	/// **本函式假設整頁的文章列連號遞增**，一般看板清單畫面即是如此（置底文印星號、沒有編號，
	/// 而且只出現在整份清單的最後）。判讀出來的列會據此過一次校準，把被游標記號蓋掉的編號位數
	/// 補回來（見 ``cursorReservedColumns``）；整頁對不起來時回空陣列，等同「這張畫面判讀不
	/// 出來」，由呼叫端重取畫面。編號本來就不連號的畫面不在適用範圍內。
	public static func summaries(in screen: PTTScreen) -> [PTTArticleSummary] {
		let page: [PTTArticleSummary] = screen.rows
			.dropFirst(headerLineCount)
			.dropLast(footerLineCount)
			.compactMap { summary(in: $0) }
		return restoringIndices(of: page)
	}

	/// 判讀單一列；不是文章列時回 `nil`。
	public static func summary(in row: [PTTCell]) -> PTTArticleSummary? {
		guard let index = ArticleIndexScanner.numbers(inFirst: indexColumns.count, of: row).last, index > 0 else {
			return nil
		}
		// !!!: 這幾個 optional 一律寫成明講型別的區域變數、不靠 init 參數位置回推——
		// CI 釘的編譯器比開發機舊，把 `flatMap(PTTArticleMark.init(rawValue:))` 這類
		// 要從函式參考回推元素型別的寫法留在參數位置，本機過得了、CI 未必（M1 已踩過一次）。
		let markCharacter: Character? = text(row, markColumns).first
		let mark: PTTArticleMark? = markCharacter.flatMap { PTTArticleMark(rawValue: $0) }
		return PTTArticleSummary(
			index: index,
			mark: mark,
			pushCount: pushCount(fromColumn: PTTScreenText.trimmed(text(row, pushCountColumns))),
			date: PTTScreenText.trimmed(text(row, dateColumns)),
			author: PTTScreenText.trimmed(text(row, authorColumns)),
			kind: PTTArticleKind(rawValue: PTTScreenText.trimmed(text(row, kindColumns))),
			title: PTTScreenText.trimmed(text(row, titleColumns))
		)
	}

	// MARK: Private

	/// 編號欄（右對齊；最左側一到兩格可能被游標記號佔用）。
	private static let indexColumns: Range<Int> = 0 ..< 7

	/// 狀態記號欄。
	private static let markColumns: Range<Int> = 8 ..< 9

	/// 推文數欄。
	private static let pushCountColumns: Range<Int> = 9 ..< 11

	/// 日期欄（其後還有一格欄寬補白）。
	private static let dateColumns: Range<Int> = 11 ..< 16

	/// 作者欄。
	private static let authorColumns: Range<Int> = 17 ..< 30

	/// 類別記號欄。
	private static let kindColumns: Range<Int> = 30 ..< 32

	/// 標題欄（類別記號後還有一格空白，一併交給前後空白去除處理）。
	private static let titleColumns: Range<Int> = 32 ..< PTTTerminal.columns

	/// 取某一欄區間的文字。
	private static func text(_ row: [PTTCell], _ columns: Range<Int>) -> String {
		PTTScreenText.text(of: row, in: columns)
	}

	/// 用整頁的連號關係補回被游標記號蓋掉的編號位數。
	///
	/// 一頁之內的文章列必定連號遞增——置底文不佔編號，而且只出現在整份清單的最後。
	/// 游標記號只蓋得掉編號的**前**幾位（欄位是右對齊的），蓋掉之後讀到的值必定是真值的
	/// 十進位後綴、也必定比真值小；因此各列各自推出來的起始編號裡，**最大**的那個就是真的。
	///
	/// !!!: 補回來的值要能通過 ``isTruncation(_:of:)``，**而且需要補的列數不能多過游標蓋得到的
	/// 列數**。少了後面這道，兩頁位數不同但同餘的畫面會整片通過——例如舊頁 2345 起、新頁 12345
	/// 起，逐列都「差一位且是後綴」，於是整批舊列被貼上新頁的編號交出去，正好是這裡最該擋的事。
	/// 對不上就整頁作廢回空陣列、由呼叫端重取；少收一段還看得出來，收到張冠李戴的編號看不出來。
	private static func restoringIndices(of page: [PTTArticleSummary]) -> [PTTArticleSummary] {
		let candidates: [Int] = page.enumerated().map { $0.element.index - $0.offset }
		guard let base: Int = candidates.max() else { return page }
		var restored: [PTTArticleSummary] = []
		restored.reserveCapacity(page.count)
		var rebuilt = 0
		for (offset, article) in page.enumerated() {
			let index: Int = base + offset
			if index == article.index {
				restored.append(article)
				continue
			}
			rebuilt += 1
			guard rebuilt <= cursorAffectedRowLimit, isTruncation(article.index, of: index) else { return [] }
			restored.append(article.replacingIndex(with: index))
		}
		return restored
	}

	/// 讀到的編號是不是「真值被游標記號蓋掉前幾位」之後的樣子。
	///
	/// 蓋掉的欄數不可能超過站方保留給游標的那幾欄；蓋掉之後剩下的必定是真值的十進位後綴。
	/// 兩個條件都成立才敢改寫編號——否則那是別頁的列，不是被蓋掉的列。
	private static func isTruncation(_ read: Int, of actual: Int) -> Bool {
		let readDigits: String = .init(read)
		let actualDigits: String = .init(actual)
		let missing: Int = actualDigits.count - readDigits.count
		guard missing > 0, missing <= cursorReservedColumns else { return false }
		return actualDigits.hasSuffix(readDigits)
	}

	/// 判讀推文數欄的兩格內容。
	///
	/// !!!: 認不得就認不得，不試著從相鄰欄位「救」出一個數字。上游那套要先剝掉狀態記號
	/// 前綴，是因為它切的範圍把狀態記號欄一起吃進來了；我們切的就是推文數那兩格，
	/// 這裡再做同樣的剝除只會在畫面真的錯位時，把一個錯的數字說得像是對的。
	private static func pushCount(fromColumn column: String) -> PTTPushCount {
		switch column {
		case "":
			return .none
		case "爆":
			return .exploded
		case "XX":
			return .heavilyBooed
		case "--":
			return .locked
		default:
			break
		}
		if let pushes = Int(column), pushes > 0 { return .pushes(pushes) }
		if column.first == "X", let tensDigit = Int(column.dropFirst()) { return .booed(tensDigit: tensDigit) }
		return .unrecognised(column)
	}
}
