//
//  PTTSessionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTSession
import Testing

/// 清單讀取遇上「沒有文章」畫面時的處置：只有跳號後的第一張才代表看板真的是空的。
///
/// 與 ``PTTSessionListingTests`` 同一組假快照 harness，另立一檔是因為這一支釘的是
/// 「不可信的畫面怎麼收場」，與翻頁、區間過濾那組不是同一件事。
private final class PTTSessionEmptyBoardListingTests {

	/// 讀到一半冒出「沒有文章」的畫面時不丟掉已收到的部分，改標成不完整。
	///
	/// 釘的是**處置方式**：把已收資料換成一個空清單，正是這則測試要擋的事。
	@Test
	private func `an empty board screen mid listing keeps what was collected`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<PTTArticleListing> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			let page: PTTArticleListing = try await session.articles(inBoard: "Test", from: 1000, through: 1024)
			result.set(page)
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)
		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.articleListing(from: 1000, through: 1018))
		#expect(await harness.waitForSend(count: 3))
		harness.yield(TestScreens.emptyBoard)
		#expect(await harness.waitForCompletion())
		try await task.value
		#expect(result.value?.articles.map(\.index) == Array(1000 ... 1018))
		#expect(result.value?.isComplete == false)
		harness.finish()
	}

	/// 「沒有文章」只認第一張畫面：重取後才出現的那張不算數，即使一篇都還沒收到。
	///
	/// 看板是不是空的在跳號那一刻就定了。判讀失敗重取之後才冒出這張，代表畫面本身可疑，
	/// 認了就會把「沒讀到」說成「這裡沒有」——空清單得標成不完整，兩者呼叫端才分得開。
	@Test
	private func `an empty board screen after a retry is not trusted`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<PTTArticleListing> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			let page: PTTArticleListing = try await session.articles(inBoard: "Test", from: 1000, through: 1024)
			result.set(page)
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)
		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.inBoard)
		#expect(await harness.waitForSend(count: 3))
		harness.yield(TestScreens.emptyBoard)
		#expect(await harness.waitForCompletion())
		try await task.value
		#expect(result.value?.articles.isEmpty == true)
		#expect(result.value?.isComplete == false)
		harness.finish()
	}
}
