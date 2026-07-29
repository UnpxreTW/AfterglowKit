//
//  PTTSessionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTSession
import Testing

/// ``PTTSession/articles(inBoard:from:through:)`` 驗證：跳號、翻頁、區間過濾、收斂條件、判讀重試。
///
/// 全程餵假快照與假 sink、注入假時鐘，不對外連線、不等真實時間。
private final class PTTSessionListingTests {

	/// 一頁就涵蓋整段區間時只跳一次號、不多翻頁。
	@Test
	private func `a single page covers the whole range`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<[PTTArticleSummary]> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			let page: [PTTArticleSummary] = try await session.articles(inBoard: "Test", from: 1022, through: 1027)
			result.set(page)
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)
		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.articleListing(from: 1022, through: 1027))
		#expect(await harness.waitForCompletion())
		try await task.value
		#expect(result.value?.map(\.index) == Array(1022 ... 1027))
		let jump: [PTTKey] = [.text("1022"), .enter, .formFeed]
		#expect(harness.sink.batches[1] == jump)
		#expect(harness.sink.count == 2)
		harness.finish()
	}

	/// 一頁裝不下就翻頁，並在收到區間上界後停手。
	@Test
	private func `paging continues until the upper bound arrives`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<[PTTArticleSummary]> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			let page: [PTTArticleSummary] = try await session.articles(inBoard: "Test", from: 1000, through: 1024)
			result.set(page)
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)
		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.articleListing(from: 1000, through: 1018))
		#expect(await harness.waitForSend(count: 3))
		harness.yield(TestScreens.articleListing(from: 1019, through: 1037))
		#expect(await harness.waitForCompletion())
		try await task.value
		#expect(result.value?.map(\.index) == Array(1000 ... 1024))
		let pageDown: [PTTKey] = [.text(PTTSession.listingPageDownKey), .formFeed]
		#expect(harness.sink.batches[2] == pageDown)
		#expect(harness.sink.count == 3)
		harness.finish()
	}

	/// 翻頁後畫面**連著幾次**都沒再往前才收手，回已收到的部分。
	@Test
	private func `paging stops once the listing no longer advances`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<[PTTArticleSummary]> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			let page: [PTTArticleSummary] = try await session.articles(inBoard: "Test", from: 1000, through: 9999)
			result.set(page)
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)
		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.articleListing(from: 1000, through: 1005))
		for attempt in 3 ... (3 + PTTSession.parseRetryLimit) {
			#expect(await harness.waitForSend(count: attempt))
			harness.yield(TestScreens.articleListing(from: 1000, through: 1005))
		}
		#expect(await harness.waitForCompletion())
		try await task.value
		#expect(result.value?.map(\.index) == Array(1000 ... 1005))
		#expect(harness.sink.count == 3 + PTTSession.parseRetryLimit)
		harness.finish()
	}

	/// 同一頁再出現一次不算「清單到底了」——重取畫面再讀，讀到新的就繼續往下收。
	///
	/// !!!: 上一步留下的殘影跟這一頁長得一模一樣，等畫面那關只認得出「還在看板裡」。
	/// 直接收手的話會安靜地少收一段還說成功。
	@Test
	private func `a repeated page is re-read before the listing is called finished`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<[PTTArticleSummary]> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			let page: [PTTArticleSummary] = try await session.articles(inBoard: "Test", from: 1000, through: 1011)
			result.set(page)
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)
		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.articleListing(from: 1000, through: 1005))
		#expect(await harness.waitForSend(count: 3))
		harness.yield(TestScreens.articleListing(from: 1000, through: 1005))
		#expect(await harness.waitForSend(count: 4))
		harness.yield(TestScreens.articleListing(from: 1006, through: 1011))
		#expect(await harness.waitForCompletion())
		try await task.value
		#expect(result.value?.map(\.index) == Array(1000 ... 1011))
		// 重讀那一批只有重繪鍵：翻頁鍵混進來就真的跳過一頁了。
		let redrawOnly: [PTTKey] = [.formFeed]
		#expect(harness.sink.batches[3] == redrawOnly)
		#expect(harness.sink.count == 4)
		harness.finish()
	}

	/// 判讀不出來與停滯交替出現時照樣丟錯，不會回報成功。
	///
	/// !!!: 兩個計數器若讓對方歸零，這條交錯序列永遠碰不到丟錯的門檻——一半的畫面根本沒讀
	/// 出來，呼叫端卻收到一份殘缺資料外加一個成功。
	@Test
	private func `unreadable pages interleaved with stalls still report failure`() async {
		let harness: SessionHarness = .init()
		let task: Task<Void, any Error> = harness.run { session in
			_ = try await session.articles(inBoard: "Test", from: 1000, through: 9999)
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)
		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.articleListing(from: 1000, through: 1005))
		var sends = 2
		for _ in 1 ... PTTSession.parseRetryLimit {
			sends += 1
			#expect(await harness.waitForSend(count: sends))
			harness.yield(TestScreens.inBoard)
			sends += 1
			#expect(await harness.waitForSend(count: sends))
			harness.yield(TestScreens.articleListing(from: 1000, through: 1005))
		}
		sends += 1
		#expect(await harness.waitForSend(count: sends))
		harness.yield(TestScreens.inBoard)
		#expect(await harness.waitForCompletion())
		await #expect(throws: PTTSessionError.listingParseFailed("Test")) { try await task.value }
		harness.finish()
	}

	/// 區間外的文章列不收進結果（畫面一定會多給、過濾在我們這端）。
	@Test
	private func `articles outside the range are filtered out`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<[PTTArticleSummary]> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			let page: [PTTArticleSummary] = try await session.articles(inBoard: "Test", from: 1003, through: 1005)
			result.set(page)
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)
		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.articleListing(from: 1000, through: 1010))
		#expect(await harness.waitForCompletion())
		try await task.value
		#expect(result.value?.map(\.index) == Array(1003 ... 1005))
		harness.finish()
	}

	/// 看板一篇文章也沒有時回空陣列，不是錯誤。
	@Test
	private func `an empty board yields no articles`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<[PTTArticleSummary]> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			let page: [PTTArticleSummary] = try await session.articles(inBoard: "Test", from: 1, through: 10)
			result.set(page)
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)
		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.emptyBoard)
		#expect(await harness.waitForCompletion())
		try await task.value
		#expect(result.value?.isEmpty == true)
		harness.finish()
	}

	/// 判讀不出任何一列時重取畫面（只補重繪、不翻頁），下一張正常畫面即可收斂。
	@Test
	private func `an unreadable page is retried without paging past it`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<[PTTArticleSummary]> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			let page: [PTTArticleSummary] = try await session.articles(inBoard: "Test", from: 1000, through: 1002)
			result.set(page)
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)
		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.inBoard)
		#expect(await harness.waitForSend(count: 3))
		harness.yield(TestScreens.articleListing(from: 1000, through: 1002))
		#expect(await harness.waitForCompletion())
		try await task.value
		#expect(result.value?.map(\.index) == Array(1000 ... 1002))
		// 重試那一批只有重繪鍵，翻頁鍵不能混進來——翻過去就漏掉這一頁了。
		let redrawOnly: [PTTKey] = [.formFeed]
		#expect(harness.sink.batches[2] == redrawOnly)
		harness.finish()
	}

	/// 重試次數用盡仍判讀不出任何一列才回報失敗。
	@Test
	private func `listing parsing gives up after the retry limit`() async {
		let harness: SessionHarness = .init()
		let task: Task<Void, any Error> = harness.run { session in
			_ = try await session.articles(inBoard: "Test", from: 1000, through: 1002)
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)
		for attempt in 2 ... (2 + PTTSession.parseRetryLimit) {
			#expect(await harness.waitForSend(count: attempt))
			harness.yield(TestScreens.inBoard)
		}
		#expect(await harness.waitForCompletion())
		await #expect(throws: PTTSessionError.listingParseFailed("Test")) { try await task.value }
		harness.finish()
	}

	/// 區間不成立時直接回報、一顆鍵都不送。
	@Test
	private func `an invalid range is rejected before any key is sent`() async {
		let harness: SessionHarness = .init()
		await #expect(throws: PTTSessionError.invalidIndexRange) {
			_ = try await harness.session.articles(inBoard: "Test", from: 5, through: 1)
		}
		await #expect(throws: PTTSessionError.invalidIndexRange) {
			_ = try await harness.session.articles(inBoard: "Test", from: 0, through: 10)
		}
		#expect(harness.sink.count == 0)
		harness.finish()
	}
}
