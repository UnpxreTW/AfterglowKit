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
/// - Warning: **按格子切、不按字元切**。既有的 Python 實作是把畫面攤成字串再用字元位置切欄，
///   那在推文數欄出現全形字（「爆」）時整排會往前錯一格、作者與標題全歪掉。我們手上有
///   完整的格子矩陣，直接按欄位切就沒有這個問題，故此處刻意不照抄上游的切法。
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

	/// 承認整頁編號基準所需的「原樣相符」列數。
	///
	/// 基準取自各列各自推出來的起始編號裡最大的那個，而定義基準的那一列必然與基準相符——
	/// 那是算式的結果、不是佐證。故要求**另有一列**原樣相符，合計兩列，基準才算被畫面自己
	/// 證實過。少於這個數量就整頁作廢：只有一列判讀得出來時，該列若被游標記號蓋掉，基準就是
	/// 被蓋掉之後那個值本身，既不會被改寫也不會被擋下，直接交出錯編號。
	public static let corroboratedRowCount = 2

	/// 判讀整張畫面上所有能認出來的文章列（依畫面由上而下，即編號遞增）。
	///
	/// 認不出編號的列（置底文、空白列、殘影）直接略過——清單畫面本來就混著這些東西，
	/// 略過它們是正常判讀的一部分，不是失敗。認得出來的列**少於
	/// ``corroboratedRowCount`` 列**時整張畫面回空陣列，由呼叫端當作判讀失敗處理：
	/// 那樣的畫面湊不出足以檢驗編號基準的資訊（見 ``corroboratedRowCount``）。
	///
	/// **本函式假設整頁的文章列連號遞增**，一般看板清單畫面即是如此（置底文印星號、沒有編號，
	/// 而且只出現在整份清單的最後）。判讀出來的列會據此過一次校準，把被游標記號蓋掉的編號位數
	/// 補回來（見 ``cursorReservedColumns``）；整頁對不起來時回空陣列，等同「這張畫面判讀不
	/// 出來」，由呼叫端重取畫面。編號本來就不連號的畫面不在適用範圍內。
	///
	/// 認出來的列還要一起過一道日期欄形狀驗證（見 ``hasStationDateShape(_:)``）：只要有一列的
	/// 日期欄不是站方寫得出來的樣子，**整張畫面**作廢回空陣列，而不是把那一列略過。認得出編號
	/// 卻讀到不成形狀的日期，表示這張畫面的欄位切點對不上——半重繪、殘影，或這根本不是文章
	/// 清單版面；此時同一列的其餘每一欄都不可信，逐列寬待只會把錯的資料說得像對的。
	public static func summaries(in screen: PTTScreen) -> [PTTArticleSummary] {
		let page: [PTTArticleSummary] = screen.rows
			.dropFirst(headerLineCount)
			.dropLast(footerLineCount)
			.compactMap { summary(in: $0) }
		guard page.allSatisfy({ hasStationDateShape($0.date) }) else { return [] }
		return restoringIndices(of: page)
	}

	/// 判讀單一列；不是文章列時回 `nil`。
	///
	/// 本函式**不**驗日期欄形狀。那道驗證不符時的處置是整張畫面作廢，屬畫面層的判斷，
	/// 因此住在 ``summaries(in:)``；下放到這裡就成了逐列略過，正是它要擋掉的那種寬待。
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
	/// - Warning: 補回來的值要能通過 ``isTruncation(_:of:)``，**而且需要補的列數不能多過游標蓋得到的
	///   列數**。少了後面這道，兩頁位數不同但同餘的畫面會整片通過——例如舊頁 2345 起、新頁 12345
	///   起，逐列都「差一位且是後綴」，於是整批舊列被貼上新頁的編號交出去，正好是這裡最該擋的事。
	///   對不上就整頁作廢回空陣列、由呼叫端重取；少收一段還看得出來，收到張冠李戴的編號看不出來。
	///
	/// - Warning: 前兩道判準管的是「被改寫的列可不可信」，**基準本身可不可信是第三道**——原樣相符的列
	///   要有 ``corroboratedRowCount`` 列，否則整頁作廢。少了這道，單列頁與幾乎整片重建的畫面
	///   都由一列自己說了算，而那一列正是可能被游標蓋掉的那列。
	private static func restoringIndices(of page: [PTTArticleSummary]) -> [PTTArticleSummary] {
		let candidates: [Int] = page.enumerated().map { $0.element.index - $0.offset }
		guard let base: Int = candidates.max() else { return page }
		var restored: [PTTArticleSummary] = []
		restored.reserveCapacity(page.count)
		var rebuilt = 0
		var matched: Int = 0
		for (offset, article) in page.enumerated() {
			let index: Int = base + offset
			if index == article.index {
				matched += 1
				restored.append(article)
				continue
			}
			rebuilt += 1
			guard rebuilt <= cursorAffectedRowLimit, isTruncation(article.index, of: index) else { return [] }
			restored.append(article.replacingIndex(with: index))
		}
		guard matched >= corroboratedRowCount else { return [] }
		return restored
	}

	/// 日期欄的內容是不是站方寫得出來的形狀（前後空白已去除）。
	///
	/// 驗證集收的是站方**程式自動產生**的形狀：`mbbsd/record.c` 的
	/// `SNPRINTF(fh->date, "%2d/%02d", ptime.tm_mon + 1, ptime.tm_mday)`（月一到兩位、
	/// 日恆兩位），以及 `include/pttstruct.h` 的欄位宣告 `char date[6];` 自帶註解
	/// 「`[02/02] or space(5)`」言明的**整欄空白**——後者同樣是站方的合法值，故空字串放行。
	///
	/// 板主的**手動編輯**路徑不在驗證集內：`mbbsd/bbs.c` 以 `getdata_str` 收輸入、只用
	/// `%5.5s` 正規化長度，寫得進任意五個字，形狀不可枚舉。**刻意不收**——收任意值等於
	/// 這道驗證失效；代價是那種列會讓整張畫面判失敗，由既有的重取上限收束。
	///
	/// - Warning: 驗證集要收齊「自動寫入路徑產得出來的全部值」。少收一種，效果不是變嚴而是變成
	///   **永遠好不了的迴圈**：畫面壞掉重取會拿到好畫面，合法值驗不過則重取幾次都一樣，
	///   最後一律以判讀失敗收場。全空白那一種是最容易漏掉的。
	///
	/// - Important: 這是煙霧偵測器、不是位移證明：整列左移一欄時 `12/31` 會讀成 `2/31`，形狀仍合法、
	///   值卻是錯的。它擋得住切點歪到讀出非日期的那類畫面，擋不住恰好仍長得像日期的位移。
	private static func hasStationDateShape(_ date: String) -> Bool {
		if date.isEmpty { return true }
		let fields: [Substring] = date.split(separator: "/", omittingEmptySubsequences: false)
		guard fields.count == 2 else { return false }
		let monthDigits: Substring = fields[0]
		let dayDigits: Substring = fields[1]
		guard (1 ... 2).contains(monthDigits.count), dayDigits.count == 2 else { return false }
		guard isDigits(monthDigits), isDigits(dayDigits) else { return false }
		guard let month = Int(monthDigits), let day = Int(dayDigits) else { return false }
		return (1 ... 12).contains(month) && (1 ... 31).contains(day)
	}

	/// 整段都是 ASCII 數字。
	///
	/// - Warning: 不能只靠 `Int(_:)` 收尾——它認得 `+1` 這種帶正負號的寫法，而站方的 `%2d/%02d`
	///   印不出這種東西；少了這一關，`+1/09` 會被當成合法日期放行。
	private static func isDigits(_ text: Substring) -> Bool {
		!text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
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
	/// - Warning: 認不得就認不得，不試著從相鄰欄位「救」出一個數字。上游那套要先剝掉狀態記號
	///   前綴，是因為它切的範圍把狀態記號欄一起吃進來了；我們切的就是推文數那兩格，
	///   這裡再做同樣的剝除只會在畫面真的錯位時，把一個錯的數字說得像是對的。
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
