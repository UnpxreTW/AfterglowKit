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

/// ``PTTSession/articleContent(inBoard:at:)`` 驗證：逐頁收斂、行號連續性檢查、動畫偵測、
/// 不完整標記、送鍵紅線（不用空白鍵）。全程餵假快照與假 sink、注入假時鐘，不對外連線。
private final class PTTSessionArticleContentTests {

	// MARK: 逐頁收斂

	/// 兩頁文章：首頁判出表頭、次頁與首頁重疊一行銜接、`Ctrl+F` 再送一次收到相同行號區間
	/// 即正常收斂（必收 case：末頁 `Ctrl+F` no-op 後正確收斂）。順便驗證推文原始行與
	/// 內文行正確分流，以及那些原始行一路判讀成結構化推文（欄位層另有單元測試）。
	@Test
	private func `reads across pages and converges when the range stops advancing`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<PTTArticleContent> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			result.set(try await session.articleContent(inBoard: "Test", at: 5))
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)

		// 首頁：3 列表頭 + 分隔線 + 19 行內文（檔案行 5~23），footer 1~23。
		#expect(await harness.waitForSend(count: 2))
		let firstPageBody: [String] = TestScreens.articleBodyLines(count: 19, startingAt: 5)
		let firstPageRows: [String] = TestScreens.standardArticleHeader + [TestScreens.headerSeparator] + firstPageBody
		harness.yield(TestScreens.articleContentScreen(
			contentRows: firstPageRows,
			footer: TestScreens.footerCurrentDisplay(1 ... 23)
		))

		// 次頁：與首頁重疊第 23 行、內容 23~45，末列換成一則推文原始行。
		#expect(await harness.waitForSend(count: 3))
		var secondPageBody: [String] = TestScreens.articleBodyLines(count: 23, startingAt: 23)
		secondPageBody[secondPageBody.count - 1] = TestScreens.sampleCommentLines[0]
		let secondPageLines: [String] = TestScreens.articleContentScreen(
			contentRows: secondPageBody,
			footer: TestScreens.footerCurrentDisplay(23 ... 45)
		)
		harness.yield(secondPageLines)

		// 再送一次 Ctrl+F：行號區間不再前進，視為到底。
		#expect(await harness.waitForSend(count: 4))
		harness.yield(secondPageLines)

		#expect(await harness.waitForCompletion())
		try await task.value
		let content: PTTArticleContent = try #require(result.value)

		#expect(content.isAnimation == false)
		#expect(content.isComplete == true)
		#expect(content.header?.fields.count == 3)
		#expect(content.header?.fields.first?.name == "作者")
		#expect(content.commentLines == [TestScreens.sampleCommentLines[0]])
		#expect(content.comments.map(\.type) == [.push])
		#expect(content.comments.map(\.author) == ["bob"])
		#expect(content.unparsedCommentLineCount == 0)
		#expect(content.bodyLines.count == 40) // 檔案行 5~44，扣掉被換成推文的第 45 行
		#expect(content.bodyLines.first == "內文第5行的示意文字")
		#expect(content.bodyLines.last == "內文第44行的示意文字")

		#expect(harness.sink.batches[1] == [.text("5"), .enter, .enter, .formFeed])
		#expect(harness.sink.batches[2] == [.pageForward, .formFeed])
		#expect(harness.sink.batches[3] == [.pageForward, .formFeed])
		harness.finish()
	}

	// MARK: 連續性與畫面不穩定

	/// 必收 case：上下半頁來自不同頁的半重繪畫面——行號區間與前一頁對不上（既非重疊、
	/// 也非緊接），視為不穩定，補 `Ctrl+L` 重取、不當成進展收下。
	@Test
	private func `a mismatched footer range is redrawn instead of accepted`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<PTTArticleContent> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			result.set(try await session.articleContent(inBoard: "Test", at: 5))
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)

		#expect(await harness.waitForSend(count: 2))
		let firstPageBody: [String] = TestScreens.articleBodyLines(count: 23, startingAt: 1)
		harness.yield(TestScreens.articleContentScreen(
			contentRows: firstPageBody,
			footer: TestScreens.footerCurrentDisplay(1 ... 23)
		))

		// 半重繪：footer 說 30~40，既不是 23（重疊）也不是 24（緊接）。
		#expect(await harness.waitForSend(count: 3))
		let mismatchedBody: [String] = TestScreens.articleBodyLines(count: 11, startingAt: 30)
		harness.yield(TestScreens.articleContentScreen(
			contentRows: mismatchedBody,
			footer: TestScreens.footerCurrentDisplay(30 ... 40)
		))

		// 補重繪後收到正確的次頁：與首頁重疊第 23 行。
		#expect(await harness.waitForSend(count: 4))
		let secondPageBody: [String] = TestScreens.articleBodyLines(count: 23, startingAt: 23)
		let secondPageLines: [String] = TestScreens.articleContentScreen(
			contentRows: secondPageBody,
			footer: TestScreens.footerCurrentDisplay(23 ... 45)
		)
		harness.yield(secondPageLines)

		#expect(await harness.waitForSend(count: 5))
		harness.yield(secondPageLines)

		#expect(await harness.waitForCompletion())
		try await task.value
		let content: PTTArticleContent = try #require(result.value)

		#expect(content.isComplete == true)
		#expect(content.bodyLines.count == 45) // 檔案行 1~45，半重繪那頁未被採信、無斷洞
		// 半重繪那次只補重繪、不翻頁：批次是純 formFeed。
		#expect(harness.sink.batches[3] == [.formFeed])
		#expect(harness.sink.batches[4] == [.pageForward, .formFeed])
		harness.finish()
	}

	/// 必收 case：footer 字串本身在（命中呼叫端目標），但行號區間解不出來（如半重繪把數字
	/// 蓋成不可判讀的殘影）——視為畫面不穩定，補重繪重取、不猜行號。
	@Test
	private func `an unparseable line range is redrawn`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<PTTArticleContent> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			result.set(try await session.articleContent(inBoard: "Test", at: 5))
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)

		// 首頁 footer 有「目前顯示」字樣（呼叫端目標命中），但行號被殘影蓋成 "--~--"。
		#expect(await harness.waitForSend(count: 2))
		let garbledBody: [String] = TestScreens.articleBodyLines(count: 23, startingAt: 1)
		harness.yield(TestScreens.articleContentScreen(
			contentRows: garbledBody,
			footer: " 目前顯示: 第 --~-- 行"
		))

		#expect(await harness.waitForSend(count: 3))
		let firstPageBody: [String] = TestScreens.articleBodyLines(count: 23, startingAt: 1)
		let firstPageLines: [String] = TestScreens.articleContentScreen(
			contentRows: firstPageBody,
			footer: TestScreens.footerCurrentDisplay(1 ... 23)
		)
		harness.yield(firstPageLines)

		#expect(await harness.waitForSend(count: 4))
		harness.yield(firstPageLines)

		#expect(await harness.waitForCompletion())
		try await task.value
		let content: PTTArticleContent = try #require(result.value)

		#expect(content.isComplete == true)
		#expect(content.bodyLines.count == 23)
		// 判讀不出行號那次只補重繪、不翻頁。
		#expect(harness.sink.batches[2] == [.formFeed])
		harness.finish()
	}

	/// 必收 case：舊式狀態列（無行號區間）畫面被判為不可用，不誤讀成合法的一頁。
	@Test
	private func `an old-style status bar page is treated as unusable`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<PTTArticleContent> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			result.set(try await session.articleContent(inBoard: "Test", at: 5))
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)

		// 舊式狀態列本身不含「目前顯示」／「顯示範圍」字樣、也不含任何動畫 prompt 字樣，
		// 呼叫端目標與全域表皆不命中，底層 wait() 會直接跳過、等下一張畫面——
		// 這裡改用「首頁本身」就是舊式狀態列來驗證：`send()` 等到的是後續補上的正常首頁。
		#expect(await harness.waitForSend(count: 2))
		let firstPageBody: [String] = TestScreens.articleBodyLines(count: 23, startingAt: 1)
		let firstPageLines: [String] = TestScreens.articleContentScreen(
			contentRows: firstPageBody,
			footer: TestScreens.footerCurrentDisplay(1 ... 23)
		)
		// 先餵一張舊式狀態列（不命中任何目標，wait() 內部略過、不觸發新的 send）。
		harness.yield([TestScreens.oldStyleStatusBar])
		harness.yield(firstPageLines)

		#expect(await harness.waitForSend(count: 3))
		harness.yield(firstPageLines)

		#expect(await harness.waitForCompletion())
		try await task.value
		let content: PTTArticleContent = try #require(result.value)

		#expect(content.isComplete == true)
		#expect(content.bodyLines.count == 23)
		harness.finish()
	}

	// MARK: 動畫偵測

	/// 必收 case（動畫 prompt 三式之一）：偵測到可播放文字動畫時答 `n`，標成動畫、內文皆空。
	@Test
	private func `a movie prompt is declined and marked as animation`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<PTTArticleContent> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			result.set(try await session.articleContent(inBoard: "Test", at: 5))
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)

		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.movieDetectedPromptScreen)

		#expect(await harness.waitForCompletion())
		try await task.value
		let content: PTTArticleContent = try #require(result.value)

		#expect(content.isAnimation == true)
		#expect(content.isComplete == true)
		#expect(content.bodyLines.isEmpty)
		#expect(content.commentLines.isEmpty)
		#expect(harness.sink.batches[2] == [.text("n"), .enter, .formFeed])
		#expect(harness.sink.count == 3)
		harness.finish()
	}

	/// 必收 case（動畫 prompt 三式之二）：傳統動畫檔的播放速度提問留空跳過。
	@Test
	private func `a traditional animation speed prompt is declined`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<PTTArticleContent> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			result.set(try await session.articleContent(inBoard: "Test", at: 5))
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)

		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.traditionalAnimationSpeedPromptScreen)

		#expect(await harness.waitForCompletion())
		try await task.value
		let content: PTTArticleContent = try #require(result.value)

		#expect(content.isAnimation == true)
		#expect(harness.sink.batches[2] == [.enter, .formFeed])
		harness.finish()
	}

	/// 必收 case（動畫 prompt 三式之三）：是否模擬 24 行答 `n`，用現在的行數。
	@Test
	private func `a traditional animation line count prompt is declined`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<PTTArticleContent> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			result.set(try await session.articleContent(inBoard: "Test", at: 5))
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)

		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.traditionalLineCountPromptScreen)

		#expect(await harness.waitForCompletion())
		try await task.value
		let content: PTTArticleContent = try #require(result.value)

		#expect(content.isAnimation == true)
		#expect(harness.sink.batches[2] == [.text("n"), .enter, .formFeed])
		harness.finish()
	}

	// MARK: 不完整

	/// 重試額度用盡但已收到內容——回傳目前累積的部分並標不完整，不丟錯把已收到的資料吞掉。
	@Test
	private func `gives up with partial content once retries are exhausted`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<PTTArticleContent> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			result.set(try await session.articleContent(inBoard: "Test", at: 5))
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)

		#expect(await harness.waitForSend(count: 2))
		let firstPageBody: [String] = TestScreens.articleBodyLines(count: 23, startingAt: 1)
		harness.yield(TestScreens.articleContentScreen(
			contentRows: firstPageBody,
			footer: TestScreens.footerCurrentDisplay(1 ... 23)
		))

		// 之後每次都收到解不出行號的殘影，連續超過重試上限。
		var sends = 2
		for _ in 0 ... PTTSession.parseRetryLimit {
			sends += 1
			#expect(await harness.waitForSend(count: sends))
			harness.yield(TestScreens.articleContentScreen(
				contentRows: firstPageBody,
				footer: " 目前顯示: 第 --~-- 行"
			))
		}

		#expect(await harness.waitForCompletion())
		try await task.value
		let content: PTTArticleContent = try #require(result.value)

		#expect(content.isComplete == false)
		#expect(content.bodyLines.count == 23)
		harness.finish()
	}

	/// 連第一頁都判讀不出來時丟錯，不回傳一份空得沒有意義的「部分結果」。
	@Test
	private func `fails when no page is ever readable`() async {
		let harness: SessionHarness = .init()
		let task: Task<Void, any Error> = harness.run { session in
			_ = try await session.articleContent(inBoard: "Test", at: 5)
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)

		var sends = 1
		for _ in 0 ..< (PTTSession.parseRetryLimit + 1) {
			sends += 1
			#expect(await harness.waitForSend(count: sends))
			harness.yield([" 目前顯示: 第 --~-- 行"])
		}

		#expect(await harness.waitForCompletion())
		await #expect(throws: PTTSessionError.articleReadFailed(board: "Test", index: 5)) {
			try await task.value
		}
		harness.finish()
	}

	// MARK: 送鍵紅線

	/// 反向測試：全程送出的鍵序列（除了進板那一批既有邏輯）不含空白鍵——空白鍵在末頁
	/// 會直接離開文章跳到下一篇，行為測試抓不到這種誤用，只能靠釘死鍵序列本身。
	@Test
	private func `sent key sequences never include the space bar`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<PTTArticleContent> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			result.set(try await session.articleContent(inBoard: "Test", at: 5))
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)

		#expect(await harness.waitForSend(count: 2))
		let firstPageBody: [String] = TestScreens.articleBodyLines(count: 19, startingAt: 5)
		let firstPageRows: [String] = TestScreens.standardArticleHeader + [TestScreens.headerSeparator] + firstPageBody
		harness.yield(TestScreens.articleContentScreen(
			contentRows: firstPageRows,
			footer: TestScreens.footerCurrentDisplay(1 ... 23)
		))

		#expect(await harness.waitForSend(count: 3))
		let secondPageBody: [String] = TestScreens.articleBodyLines(count: 23, startingAt: 23)
		let secondPageLines: [String] = TestScreens.articleContentScreen(
			contentRows: secondPageBody,
			footer: TestScreens.footerCurrentDisplay(23 ... 45)
		)
		harness.yield(secondPageLines)

		#expect(await harness.waitForSend(count: 4))
		harness.yield(secondPageLines)

		#expect(await harness.waitForCompletion())
		try await task.value
		let content: PTTArticleContent = try #require(result.value)
		#expect(content.isComplete == true)

		// 批次 0 是 goToBoard 既有的 mainMenuReset（含空白鍵，紅線不管這批）；
		// 從批次 1（開文章）起才是本函式自己送的鍵，這些一律不含空白鍵。
		for batch in harness.sink.batches[1...] {
			#expect(!batch.contains(.text(" ")))
		}
		harness.finish()
	}
}
