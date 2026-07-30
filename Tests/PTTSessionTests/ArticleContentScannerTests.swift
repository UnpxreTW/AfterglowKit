//
//  PTTSessionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTSession
import PTTTerminal
import Testing

/// ``ArticleContentScanner`` 判讀邏輯的單元驗證：footer 行號解析、表頭偵測、
/// 折行合併、推文原始行分類。全程不對外連線，餵合成的 `PTTScreen` / `[PTTCell]`。
private final class ArticleContentScannerTests {

	// MARK: footer 行號解析

	/// 「目前顯示: 第 N~M 行」格式（未水平捲動）解出正確的行號區間。
	@Test
	private func `parses the current display footer format`() {
		#expect(ArticleContentScanner.lineRange(inFooter: TestScreens.footerCurrentDisplay(23 ... 45)) == 23 ... 45)
	}

	/// 「顯示範圍: N~M 欄位, N~M 行」格式只取行號那組，不誤取前面的欄位範圍。
	@Test
	private func `parses only the line range in the scrolled footer format`() {
		let footer: String = TestScreens.footerScrolled(columns: 5 ... 84, lines: 23 ... 45)
		#expect(ArticleContentScanner.lineRange(inFooter: footer) == 23 ... 45)
	}

	/// 必收 case：舊式狀態列（無行號）判為不可用，不誤讀。
	@Test
	private func `an old-style status bar has no readable line range`() {
		#expect(ArticleContentScanner.lineRange(inFooter: TestScreens.oldStyleStatusBar) == nil)
	}

	/// 必收 case：`override_msg` 蓋掉行號區間那一幀解不出行號。
	@Test
	private func `an override message frame has no readable line range`() {
		#expect(ArticleContentScanner.lineRange(inFooter: TestScreens.overrideMessage) == nil)
	}

	// MARK: 折行合併

	/// 必收 case：折行續行合併——前一列尾端有 `\` 記號，接續到下一列合成一個檔案行。
	@Test
	private func `a wrap indicator merges the continuation row into one line`() {
		let firstRowText: String = String(repeating: "A", count: 79) + "\\"
		let rows: [[PTTCell]] = [cellRow(firstRowText), cellRow("BC")]
		let merged: [String]? = ArticleContentScanner.mergeContentRows(rows, expectedLineCount: 1)
		#expect(merged == [String(repeating: "A", count: 79) + "BC"])
	}

	/// 必收 case：80 欄剛好填滿、無 `\` 記號的續行——記號漏印時只靠合併後的行數比對抓出來，
	/// 對不上就整頁作廢（回 `nil`），不誤把兩個檔案行的內容黏成別的東西回傳。
	@Test
	private func `a full-width row without an indicator invalidates the page on count mismatch`() {
		let fullRowText: String = String(repeating: "A", count: PTTTerminal.columns)
		let rows: [[PTTCell]] = [cellRow(fullRowText), cellRow("Z")]
		// 這兩列實際上是同一個檔案行的延續（無記號可辨），expectedLineCount 因此該是 1；
		// 演算法辨不出續行、把它們各自收成一行 ⇒ 合併後 2 行對不上期望的 1 行 ⇒ 回 nil。
		let merged: [String]? = ArticleContentScanner.mergeContentRows(rows, expectedLineCount: 1)
		#expect(merged == nil)
	}

	/// 無折行時逐列各自成一個檔案行（對照組：確認正常路徑不受折行邏輯干擾）。
	@Test
	private func `rows without wrapping each become their own line`() {
		let rows: [[PTTCell]] = [cellRow("第一行"), cellRow("第二行"), cellRow("第三行")]
		let merged: [String]? = ArticleContentScanner.mergeContentRows(rows, expectedLineCount: 3)
		#expect(merged == ["第一行", "第二行", "第三行"])
	}

	// MARK: 表頭偵測（透過 page(in:isFirstPage:) 整合測）

	/// 必收 case：本站文章 3 列表頭（首行「作者」開頭）。
	@Test
	private func `a standard article header is three rows`() {
		let body: [String] = TestScreens.articleBodyLines(count: 19)
		let contentRows: [String] = TestScreens.standardArticleHeader + [TestScreens.headerSeparator] + body
		let footer: String = TestScreens.footerCurrentDisplay(1 ... 23)
		let screen: PTTScreen = makeScreen(TestScreens.articleContentScreen(contentRows: contentRows, footer: footer))
		let page: ArticleContentScanner.Page? = ArticleContentScanner.page(in: screen, isFirstPage: true)
		#expect(page?.header?.fields.count == 3)
		#expect(page?.header?.fields.first?.name == "作者")
		#expect(page?.skippedLineCount == 4)
		#expect(page?.lines == body)
	}

	/// 必收 case：轉信文章 4 列表頭（首行「發信人」開頭）。
	@Test
	private func `a forwarded article header is four rows`() {
		let body: [String] = TestScreens.articleBodyLines(count: 18)
		let contentRows: [String] = TestScreens.forwardedArticleHeader + [TestScreens.headerSeparator] + body
		let footer: String = TestScreens.footerCurrentDisplay(1 ... 23)
		let screen: PTTScreen = makeScreen(TestScreens.articleContentScreen(contentRows: contentRows, footer: footer))
		let page: ArticleContentScanner.Page? = ArticleContentScanner.page(in: screen, isFirstPage: true)
		#expect(page?.header?.fields.count == 4)
		#expect(page?.header?.fields.first?.name == "發信人")
		#expect(page?.skippedLineCount == 5)
		#expect(page?.lines == body)
	}

	/// 必收 case：首行非「作者:」／「發信人:」的無表頭檔（如精華區純文字檔）——不勉強套表頭版面。
	@Test
	private func `a first line that is neither header prefix has no header`() {
		let body: [String] = TestScreens.articleBodyLines(count: 23)
		let footer: String = TestScreens.footerCurrentDisplay(1 ... 23)
		let screen: PTTScreen = makeScreen(TestScreens.articleContentScreen(contentRows: body, footer: footer))
		let page: ArticleContentScanner.Page? = ArticleContentScanner.page(in: screen, isFirstPage: true)
		#expect(page?.header == nil)
		#expect(page?.skippedLineCount == 0)
		#expect(page?.lines == body)
	}

	/// 非首頁不判表頭，即使第一列文字剛好長得像表頭首行。
	@Test
	private func `header detection is skipped on pages after the first`() {
		var body: [String] = TestScreens.articleBodyLines(count: 22)
		body.insert("作者這行只是內文剛好撞字", at: 0)
		let footer: String = TestScreens.footerCurrentDisplay(24 ... 46)
		let screen: PTTScreen = makeScreen(TestScreens.articleContentScreen(contentRows: body, footer: footer))
		let page: ArticleContentScanner.Page? = ArticleContentScanner.page(in: screen, isFirstPage: false)
		#expect(page?.header == nil)
		#expect(page?.skippedLineCount == 0)
		#expect(page?.lines == body)
	}

	// MARK: 推文原始行分類

	/// 推 / 噓 / → 前綴的行判為推文原始行。
	@Test
	private func `push boo and arrow prefixes are classified as comment lines`() {
		for line in TestScreens.sampleCommentLines {
			#expect(ArticleContentScanner.isCommentLine(line))
		}
	}

	/// 一般內文行不誤判為推文。
	@Test
	private func `an ordinary body line is not classified as a comment`() {
		#expect(!ArticleContentScanner.isCommentLine("這是一般內文，不是推文"))
	}
}

/// 組一列 80 欄寬的 `[PTTCell]`：`text` 之後補半形空白到欄寬（測試只用 ASCII，寬度皆為 1）。
private func cellRow(_ text: String) -> [PTTCell] {
	var row: [PTTCell] = text.map { makeCell($0, width: 1) }
	while row.count < PTTTerminal.columns { row.append(makeCell(" ", width: 1)) }
	return row
}
