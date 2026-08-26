//
//  PTTSessionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTSession
import Testing

/// ``PTTSession/articles(inBoard:from:through:)`` 起點上界驗證。
///
/// 上界的依據是站方印編號的那七格欄位（見 ``PTTSession/maximumStartingIndex``）：超過位數的
/// 起點送出去也讀不回來，所以在入口就擋。終點不設上界，兩則各釘一側。
///
/// 全程餵假快照與假 sink、注入假時鐘，不對外連線、不等真實時間。
private final class PTTSessionStartingIndexTests {

	/// 起點超過編號欄印得下的位數時直接回報、一顆鍵都不送。
	///
	/// !!!: 先收掉快照流、再讓假時鐘推到操作結束。上界檢查若不存在，這一句會往下走到
	/// 等畫面那關並以 ``PTTSessionError/screenStreamEnded`` 收場——測試當場紅掉，而不是
	/// 停在一個永遠不會被推進的等待上。
	@Test
	private func `a starting index beyond the readable column is rejected`() async {
		let harness: SessionHarness = .init()
		harness.finish()
		let task: Task<Void, any Error> = harness.run { session in
			_ = try await session.articles(
				inBoard: "Test",
				from: PTTSession.maximumStartingIndex + 1,
				through: .max
			)
		}
		#expect(await harness.waitForCompletion())
		await #expect(throws: PTTSessionError.invalidIndexRange) { try await task.value }
		#expect(harness.sink.count == 0)
	}

	/// 起點落在上界上仍照送——上界是「編號欄印得下」的那一格，不是再往內縮一格。
	///
	/// 終點刻意給超過上界的值：終點不進按鍵、也不設上界，請求區間超過看板現有文章是正常用法。
	@Test
	private func `a starting index at the upper bound is still sent`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<PTTArticleListing> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			let page: PTTArticleListing = try await session.articles(
				inBoard: "Test",
				from: PTTSession.maximumStartingIndex,
				through: PTTSession.maximumStartingIndex + 1
			)
			result.set(page)
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)
		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.emptyBoard)
		#expect(await harness.waitForCompletion())
		try await task.value
		#expect(result.value?.articles.isEmpty == true)
		#expect(harness.sink.batches[1] == [.text("9999999"), .enter, .formFeed])
		harness.finish()
	}
}
