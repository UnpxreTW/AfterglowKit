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

/// ``ArticleListingScanner`` 判讀驗證：各種推文數樣式、狀態與類別記號、置底文略過、表頭表尾邊界。
///
/// 逐欄斷言的列取自上游實作註解裡的真實畫面樣本（`PyPtt/_api_util.py` 的
/// `# >  7485   9 8/09 CodingMan    □ …` 那四行），不是自己編的版面——版面若有出入，
/// 出入會直接被這幾條測試抓到。
private final class ArticleListingScannerTests {

	/// 表頭：三列佔位。
	private static let header: [String] = [
		"【板主：someone】",
		"[←]離開 [→]閱讀 [i]看板資訊/設定",
		"   編號    日 期 作  者       文  章  標  題"
	]

	/// 底部功能列。
	private static let footer: [String] = ["文章選讀  (y)回應(X%)推文(h)說明(←)離開"]

	/// 由單一列組出畫面上的那一列格子、判讀該列。
	///
	/// !!!: 逐欄判讀走 ``ArticleListingScanner/summary(in:)`` 這個單列入口、不繞
	/// ``ArticleListingScanner/summaries(in:)``：後者還要檢驗整頁的編號基準，而基準需要
	/// 兩列原樣相符才承認（見 ``ArticleListingScanner/corroboratedRowCount``），單列畫面
	/// 一律回空陣列。欄位切法與基準檢驗是兩件事，各測各的。
	private static func summary(ofRow row: String) -> PTTArticleSummary? {
		let screen: PTTScreen = makeScreen(header + [row] + footer)
		return ArticleListingScanner.summary(in: screen.rows[header.count])
	}

	/// 一般列：游標列、個位數推文、五欄日期、十二字作者、一般類別記號。
	@Test
	private func `reads every field of a plain row`() throws {
		let summary: PTTArticleSummary = try #require(
			Self.summary(ofRow: ">  7485   9 8/09 CodingMan    □ [閒聊] PTT Library 更新")
		)
		#expect(summary.index == 7485)
		#expect(summary.mark == .read)
		#expect(summary.pushCount == .pushes(9))
		#expect(summary.date == "8/09")
		#expect(summary.author == "CodingMan")
		#expect(summary.kind == .normal)
		#expect(summary.title == "[閒聊] PTT Library 更新")
	}

	/// 已標記未讀的列：狀態記號欄有字、推文數欄仍照常判讀。
	@Test
	private func `reads the marked unread row`() throws {
		let summary: PTTArticleSummary = try #require(
			Self.summary(ofRow: "> 79189 M 1 9/17 LittleCalf   □ [公告] 禁言退文公告")
		)
		#expect(summary.index == 79_189)
		#expect(summary.mark == .markedUnread)
		#expect(summary.pushCount == .pushes(1))
		#expect(summary.author == "LittleCalf")
	}

	/// 推文數欄是全形「爆」：後面的欄位不能被推著跑掉。
	///
	/// !!!: 這正是「按格子切、不按字元切」的理由——「爆」在字串裡只佔一個字元、
	/// 在畫面上佔兩欄，先攤字串再切欄的作法會把作者判成 `odojeda`。
	@Test
	private func `a full width push column does not shift the later fields`() throws {
		let summary: PTTArticleSummary = try #require(
			Self.summary(ofRow: ">781508 +爆 9/17 jodojeda     □ [新聞] 國人吃魚少")
		)
		#expect(summary.index == 781_508)
		#expect(summary.mark == .unread)
		#expect(summary.pushCount == .exploded)
		#expect(summary.date == "9/17")
		#expect(summary.author == "jodojeda")
		#expect(summary.title == "[新聞] 國人吃魚少")
	}

	/// 噓文欄只印得下十位數，判讀成十位級距、不假裝知道確切數字。
	@Test
	private func `the boo column is read as a tens digit`() throws {
		let summary: PTTArticleSummary = try #require(
			Self.summary(ofRow: ">781406 +X1 9/17 kingofage111 R: [申請] ReDmango 請辭板主職務")
		)
		#expect(summary.pushCount == .booed(tensDigit: 1))
		#expect(summary.author == "kingofage111")
		#expect(summary.kind == .reply)
		#expect(summary.title == "[申請] ReDmango 請辭板主職務")
	}

	/// 噓爆與鎖文兩種站方自己就印不出數字的欄位。
	@Test
	private func `reads the heavily booed and locked push columns`() throws {
		let booed: PTTArticleSummary = try #require(
			Self.summary(ofRow: TestScreens.articleRow(index: 12, pushCount: "XX", author: "bob"))
		)
		#expect(booed.pushCount == .heavilyBooed)
		let locked: PTTArticleSummary = try #require(
			Self.summary(ofRow: TestScreens.articleRow(index: 13, pushCount: "--", kind: "鎖"))
		)
		#expect(locked.pushCount == .locked)
		#expect(locked.kind == .locked)
	}

	/// 沒有推文的列：空白欄不等於零，判成「站方沒顯示」。
	@Test
	private func `a blank push column reads as none`() throws {
		let summary: PTTArticleSummary = try #require(
			Self.summary(ofRow: "   9457     4/17 Sumiremywife □ [問題] 關於爬蟲的一些問題")
		)
		#expect(summary.pushCount == .none)
		#expect(summary.date == "4/17")
		#expect(summary.author == "Sumiremywife")
	}

	/// 認不得的推文數樣式原文照留、整列照樣回傳。
	@Test
	private func `an unknown push column keeps the raw text`() throws {
		let summary: PTTArticleSummary = try #require(
			Self.summary(ofRow: TestScreens.articleRow(index: 42, pushCount: "?!"))
		)
		#expect(summary.pushCount == .unrecognised("?!"))
		#expect(summary.index == 42)
	}

	/// 認不得的狀態與類別記號回 nil，但不讓整列判讀失敗。
	@Test
	private func `unknown marks do not discard the row`() throws {
		let summary: PTTArticleSummary = try #require(
			Self.summary(ofRow: TestScreens.articleRow(index: 7, mark: "?", kind: "凸"))
		)
		#expect(summary.mark == nil)
		#expect(summary.kind == nil)
		#expect(summary.index == 7)
	}

	/// 置底文（編號欄是星號）略過、不當成判讀失敗。
	@Test
	private func `pinned rows are skipped`() {
		let screen: PTTScreen = makeScreen(
			Self.header
				+ [TestScreens.articleRow(index: 9458), TestScreens.articleRow(index: 9459)]
				+ ["    ★  m爆 2/14 ubcs         □ [公告] 板規公告"]
				+ Self.footer
		)
		let summaries: [PTTArticleSummary] = ArticleListingScanner.summaries(in: screen)
		#expect(summaries.map(\.index) == [9458, 9459])
	}

	/// 表頭不參與判讀。
	@Test
	private func `header rows are not parsed`() {
		var header: [String] = Self.header
		header[0] = TestScreens.articleRow(index: 9999, title: "表頭不該被當成文章")
		let screen: PTTScreen = makeScreen(
			header + (1022 ... 1023).map { TestScreens.articleRow(index: $0) } + Self.footer
		)
		#expect(ArticleListingScanner.summaries(in: screen).map(\.index) == [1022, 1023])
	}

	/// 底部功能列不參與判讀。
	///
	/// !!!: 功能列要擺在**畫面最後一列**才測得到——畫面一定是滿的 24 列，隨手接在內容後面的話，
	/// 被略過的其實是下面那些空白補白列，`footerLineCount` 改成 0 這條測試照樣會過。
	@Test
	private func `the bottom function row is not parsed`() {
		var lines: [String] = .init(repeating: "", count: PTTTerminal.rows)
		for (offset, line) in Self.header.enumerated() {
			lines[offset] = line
		}
		lines[Self.header.count] = TestScreens.articleRow(index: 1022)
		lines[Self.header.count + 1] = TestScreens.articleRow(index: 1023)
		lines[PTTTerminal.rows - 1] = TestScreens.articleRow(index: 8888, title: "功能列不該被當成文章")
		#expect(ArticleListingScanner.summaries(in: makeScreen(lines)).map(\.index) == [1022, 1023])
	}

	/// 游標記號蓋掉編號欄最左邊兩欄時，用整頁的連號關係把位數補回來。
	///
	/// !!!: 這是最惡劣的一種壞法——蓋掉之後**仍是個合法的數字**，不補回來就會安靜地把這一列
	/// 記到別篇文章的編號底下。站方保留給游標的就是這兩欄，五位數以上的看板天天踩得到。
	@Test
	private func `the cursor marker does not truncate the index`() {
		let screen: PTTScreen = makeScreen(
			Self.header
				+ [TestScreens.articleRow(index: 781_508, cursorColumns: 2)]
				+ (781_509 ... 781_512).map { TestScreens.articleRow(index: $0) }
				+ Self.footer
		)
		#expect(ArticleListingScanner.summaries(in: screen).map(\.index) == Array(781_508 ... 781_512))
	}

	/// 編號滿七位時連一欄的 ASCII 游標都蓋得到，一樣補得回來。
	@Test
	private func `a seven digit index survives a one column cursor`() {
		let screen: PTTScreen = makeScreen(
			Self.header
				+ [TestScreens.articleRow(index: 1_234_567, cursorColumns: 1)]
				+ (1_234_568 ... 1_234_569).map { TestScreens.articleRow(index: $0) }
				+ Self.footer
		)
		#expect(
			ArticleListingScanner.summaries(in: screen).map(\.index) == Array(1_234_567 ... 1_234_569)
		)
	}

	/// 缺太多位就不是游標蓋出來的——後綴對得上也不重建，整頁作廢。
	@Test
	private func `an index missing more digits than the cursor covers is discarded`() {
		let screen: PTTScreen = makeScreen(
			Self.header
				+ [TestScreens.articleRow(index: 45)]
				+ [TestScreens.articleRow(index: 12_346)]
				+ Self.footer
		)
		#expect(ArticleListingScanner.summaries(in: screen).isEmpty)
	}

	/// 要重建的列數多過游標蓋得到的列數就整頁作廢。
	///
	/// !!!: 這道閘擋的是「兩頁位數不同、卻逐列同餘」的殘影——舊頁 2345 起、新頁 12345 起，
	/// 每一列都「差一位而且是後綴」，光靠後綴判準會整批放行，把舊列貼上新頁的編號交出去。
	@Test
	private func `a listing needing more rebuilt rows than the cursor covers is discarded`() {
		let screen: PTTScreen = makeScreen(
			Self.header
				+ (2345 ... 2354).map { TestScreens.articleRow(index: $0) }
				+ (12_355 ... 12_359).map { TestScreens.articleRow(index: $0) }
				+ Self.footer
		)
		#expect(ArticleListingScanner.summaries(in: screen).isEmpty)
	}

	/// 重繪只到一半的畫面（上半是新頁、下半還是舊頁）整頁作廢，不把兩頁混起來交出去。
	@Test
	private func `a half redrawn listing is discarded`() {
		let screen: PTTScreen = makeScreen(
			Self.header
				+ (1200 ... 1202).map { TestScreens.articleRow(index: $0) }
				+ (980 ... 982).map { TestScreens.articleRow(index: $0) }
				+ Self.footer
		)
		#expect(ArticleListingScanner.summaries(in: screen).isEmpty)
	}

	/// 只判讀得出一列、而那一列被游標記號蓋掉時整頁作廢——不拿被蓋掉的值當整頁基準。
	///
	/// !!!: 這是最難察覺的一種壞法：整頁只有一列，基準就取自它自己，於是「補回位數」那道
	/// 判準永遠不會啟動，一個被蓋掉之後仍然合法的數字直接被當成真編號交出去。畫面上沒有
	/// 任何東西能反駁它，所以不猜。
	@Test
	private func `a single row page is discarded when the base cannot be corroborated`() {
		let screen: PTTScreen = makeScreen(
			Self.header + [TestScreens.articleRow(index: 781_508, cursorColumns: 2)] + Self.footer
		)
		#expect(ArticleListingScanner.summaries(in: screen).isEmpty)
	}

	/// 只判讀得出一列時一律作廢，編號看起來再正常也一樣。
	///
	/// !!!: 判準是「基準有沒有旁證」，不是「這個編號像不像被蓋過」——畫面上分不出
	/// 「本來就短」與「被蓋掉之後剛好變短」，所以兩者同樣不承認。代價是只有一篇文章的
	/// 看板讀不出來，換掉的是「安靜地回一個錯編號」。
	@Test
	private func `a single row page is discarded even when the index looks intact`() {
		let screen: PTTScreen = makeScreen(
			Self.header + [TestScreens.articleRow(index: 42)] + Self.footer
		)
		#expect(ArticleListingScanner.summaries(in: screen).isEmpty)
	}

	/// 幾乎整片都要重建、只剩基準那一列原樣相符時整頁作廢。
	///
	/// !!!: 重建的列數還在游標蓋得到的範圍內（兩列），後綴與位數兩道判準也都過得了關——
	/// 擋下這張畫面的只有「基準要有旁證」這一道。
	@Test
	private func `a page rebuilt down to its base row alone is discarded`() {
		let screen: PTTScreen = makeScreen(
			Self.header
				+ (781_508 ... 781_509).map { TestScreens.articleRow(index: $0, cursorColumns: 2) }
				+ [TestScreens.articleRow(index: 781_510)]
				+ Self.footer
		)
		#expect(ArticleListingScanner.summaries(in: screen).isEmpty)
	}

	/// 整張畫面沒有任何文章列時回空陣列（呼叫端據此重取畫面）。
	@Test
	private func `a listing without any article row reads as empty`() {
		let screen: PTTScreen = makeScreen(Self.header + Self.footer)
		#expect(ArticleListingScanner.summaries(in: screen).isEmpty)
	}

	/// 多列清單依畫面順序回傳（即編號遞增）。
	@Test
	private func `rows come back in screen order`() {
		let screen: PTTScreen = makeScreen(TestScreens.articleListing(from: 1022, through: 1027))
		#expect(ArticleListingScanner.summaries(in: screen).map(\.index) == Array(1022 ... 1027))
	}

	/// 一列的日期欄不成形狀就整張畫面作廢——**不是**只略過那一列。
	///
	/// !!!: 這條釘的是處置方式、不是判斷式。把整頁作廢改成逐列略過，其餘每一條測試照樣會過，
	/// 呼叫端卻會收到「四列看起來很正常」的一頁——而那一頁的欄位切點其實已經對不上了。
	@Test
	private func `a row with a malformed date discards the whole screen`() {
		let screen: PTTScreen = makeScreen(
			Self.header
				+ (1022 ... 1025).map { TestScreens.articleRow(index: $0) }
				+ [TestScreens.articleRow(index: 1026, date: "ab/cd")]
				+ Self.footer
		)
		#expect(ArticleListingScanner.summaries(in: screen).isEmpty)
	}

	/// 日期欄整欄空白是站方的合法值（`char date[6]` 的欄位註解自寫「`or space(5)`」），照常判讀。
	///
	/// !!!: 這一種若沒收進驗證集，畫面本身是好的、重取幾次都一樣，於是整段讀取以判讀失敗
	/// 收場——形狀驗證漏收合法值的代價不是變嚴，是永遠好不了。
	@Test
	private func `a blank date column is accepted`() throws {
		let summary: PTTArticleSummary = try #require(
			Self.summary(ofRow: TestScreens.articleRow(index: 1022, date: "     "))
		)
		#expect(summary.index == 1022)
		#expect(summary.date == "")
		#expect(summary.author == "alice")
	}

	/// 站方 `%2d/%02d` 印得出來的兩端值都認得。
	@Test(arguments: [" 1/01", "12/31", " 8/09", "02/02"])
	private func `dates the station can print are accepted`(date: String) throws {
		let summary: PTTArticleSummary = try #require(
			Self.summary(ofRow: TestScreens.articleRow(index: 1022, date: date))
		)
		#expect(summary.index == 1022)
	}

	/// 站方印不出來的日期一律不收：月日超界、日只有一位、帶正負號、非數字、缺斜線。
	///
	/// !!!: `+1/09` 這條專門釘住「不能只靠 `Int(_:)` 收尾」——它認得帶號的寫法，
	/// 而站方的 `%2d/%02d` 印不出這種東西。
	@Test(arguments: ["13/01", " 0/09", " 8/00", " 8/32", " 8/9 ", "+1/09", "ab/cd", "  809"])
	private func `dates the station cannot print are rejected`(date: String) {
		let screen: PTTScreen = makeScreen(
			Self.header + [TestScreens.articleRow(index: 1022, date: date)] + Self.footer
		)
		#expect(ArticleListingScanner.summaries(in: screen).isEmpty)
	}
}
