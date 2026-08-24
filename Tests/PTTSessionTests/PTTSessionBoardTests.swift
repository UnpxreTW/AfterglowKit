//
//  PTTSessionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTSession
import Testing

/// ``PTTSession`` 看板操作驗證：進板按鍵序列、最新編號判讀、空板與不存在的看板、關閉後的行為。
///
/// 全程餵假快照與假 sink、注入假時鐘，不對外連線、不等真實時間。
private final class PTTSessionBoardTests {

	/// 進板後跳到清單末端、判讀出最新編號。
	@Test
	private func `newest index reads the board listing`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<Int> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			let index: Int = try await session.newestIndex(ofBoard: "Test")
			result.set(index)
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)
		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.boardListing(from: 1022, through: 1027))
		#expect(await harness.waitForCompletion())
		try await task.value
		#expect(result.value == 1027)
		#expect(harness.sink.batches[1] == [.text("1"), .enter, .text("$"), .formFeed])
		harness.finish()
	}

	/// 進板的按鍵序列：先把畫面推回主功能表，再走看板快選、尾端補中斷鍵。
	@Test
	private func `entering a board resets to the main menu first`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<Int> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			let index: Int = try await session.newestIndex(ofBoard: "Test")
			result.set(index)
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)
		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.emptyBoard)
		#expect(await harness.waitForCompletion())
		try await task.value
		// !!!: 中斷鍵那段寫成 `[PTTKey](repeating:count:)` 而不是 `repeatElement(.interrupt,…)`
		// ——後者要靠 `+` 的鏈式推導回填元素型別，較舊的編譯器推不出來、直接編譯失敗。
		let expected: [PTTKey] = PTTKey.mainMenuReset
			+ [.text("qs"), .text("Test"), .enter]
			+ [PTTKey](repeating: .interrupt, count: 5)
			+ [.formFeed]
		#expect(harness.sink.batches[0] == expected)
		harness.finish()
	}

	/// 看板存在但沒有文章時回 0。
	@Test
	private func `empty board reports zero`() async throws {
		let harness: SessionHarness = .init()
		let result: ResultBox<Int> = .init()
		let task: Task<Void, any Error> = harness.run { session in
			let index: Int = try await session.newestIndex(ofBoard: "Test")
			result.set(index)
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)
		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.emptyBoard)
		#expect(await harness.waitForCompletion())
		try await task.value
		#expect(result.value == 0)
		harness.finish()
	}

	/// 進板失敗（退回主功能表離站確認）判定為看板不存在。
	@Test
	private func `unknown board is reported as such`() async {
		let harness: SessionHarness = .init()
		let task: Task<Void, any Error> = harness.run { session in
			_ = try await session.newestIndex(ofBoard: "NoSuchBoard")
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.mainMenuExiting)
		#expect(await harness.waitForCompletion())
		await #expect(throws: PTTSessionError.noSuchBoard("NoSuchBoard")) { try await task.value }
		harness.finish()
	}

	/// 清單判讀失敗會重取畫面重試，重試次數用盡才回報失敗。
	@Test
	private func `index parsing retries before giving up`() async {
		let harness: SessionHarness = .init()
		let task: Task<Void, any Error> = harness.run { session in
			_ = try await session.newestIndex(ofBoard: "Test")
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)
		for attempt in 2 ... (2 + PTTSession.parseRetryLimit) {
			#expect(await harness.waitForSend(count: attempt))
			harness.yield(TestScreens.boardHeader + ["  5000 + 7/23 alice   標題"] + TestScreens.boardFooter)
		}
		#expect(await harness.waitForCompletion())
		await #expect(throws: PTTSessionError.indexParseFailed("Test")) { try await task.value }
		#expect(harness.sink.count == 2 + PTTSession.parseRetryLimit)
		harness.finish()
	}

	/// 板名形狀不合法時一顆鍵都不送——它是進板路徑上呼叫端字串直接變成按鍵的入口。
	///
	/// !!!: 這一則釘的是「沒送出去」而不是「丟了錯」。只斷言錯誤的話，先把板名送出去
	/// 再回報失敗的實作也會通過，而那正是本檢查要擋的事。
	///
	/// !!!: 先收掉快照流、再讓假時鐘推到操作結束。檢查若不存在，這一句會往下走到等畫面
	/// 那關並以 ``PTTSessionError/screenStreamEnded`` 收場——測試當場紅掉，而不是停在
	/// 一個永遠不會被推進的等待上。
	@Test
	private func `a malformed board name never reaches the station`() async {
		let malformed: [String] = [
			"",
			"Test\u{0003}",
			"Test\rqs",
			"Test\n",
			"Test Board",
			"測試板",
			"ThirteenChars"
		]
		for name in malformed {
			let harness: SessionHarness = .init()
			harness.finish()
			let task: Task<Void, any Error> = harness.run { session in
				_ = try await session.newestIndex(ofBoard: name)
			}
			#expect(await harness.waitForCompletion())
			await #expect(throws: PTTSessionError.invalidBoardName(name)) { try await task.value }
			#expect(harness.sink.count == 0)
		}
	}

	/// 白名單容得下站上真的存在的板名形狀：英數混 `_` `-` `.`、長度到上限。
	///
	/// !!!: 這一則釘的是「不要判過嚴」。判嚴的失敗從呼叫端看起來與「看板不存在」
	/// 分不出來，比判鬆更難查。
	@Test
	private func `a board name at the shape boundary still gets sent`() async throws {
		let name: String = "A_b-c.d12345"
		#expect(name.count == BoardName.maximumLength)
		let harness: SessionHarness = .init()
		let task: Task<Void, any Error> = harness.run { session in
			_ = try await session.newestIndex(ofBoard: name)
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.inBoard)
		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.emptyBoard)
		#expect(await harness.waitForCompletion())
		try await task.value
		#expect(harness.sink.batches[0].contains(.text(name)))
		harness.finish()
	}

	/// 關閉之後不再受理操作。
	@Test
	private func `a closed session refuses further work`() async {
		let harness: SessionHarness = .init()
		await harness.session.close()
		await #expect(throws: PTTSessionError.closed) {
			try await harness.session.logIn(userIdentifier: "dreamer", password: "secret")
		}
		harness.finish()
	}
}
