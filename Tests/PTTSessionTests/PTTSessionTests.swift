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

/// ``PTTSession`` 登入圈驗證：登入流程、全域攔截與退避、送鍵節流、等畫面的界線與逾時。
///
/// 全程餵假快照與假 sink、注入假時鐘，不對外連線、不等真實時間。
private final class PTTSessionTests {

	/// 登入成功：一次送完帳號密碼、等到主功能表。
	@Test
	private func `login sends credentials once and settles on the main menu`() async throws {
		let harness: SessionHarness = .init()
		let task: Task<Void, any Error> = harness.run { session in
			try await session.logIn(userIdentifier: "dreamer", password: "secret")
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.mainMenu)
		#expect(await harness.waitForCompletion())
		try await task.value
		#expect(harness.sink.batches == [[.text("dreamer"), .enter, .text("secret"), .enter, .formFeed]])
		harness.finish()
	}

	/// 帳號密碼先截斷到站方上限、再去除前後空白。
	@Test
	private func `credentials are truncated to the site limits`() async throws {
		let harness: SessionHarness = .init()
		let task: Task<Void, any Error> = harness.run { session in
			try await session.logIn(userIdentifier: "  abcdefghijklmnop", password: "0123456789ab")
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.mainMenu)
		#expect(await harness.waitForCompletion())
		try await task.value
		#expect(harness.sink.batches.first == [.text("abcdefghij"), .enter, .text("01234567"), .enter, .formFeed])
		harness.finish()
	}

	/// 空帳號或空密碼直接拒絕，一顆鍵都不送。
	@Test
	private func `empty credentials are rejected without sending anything`() async {
		let harness: SessionHarness = .init()
		await #expect(throws: PTTSessionError.emptyCredentials) {
			try await harness.session.logIn(userIdentifier: "   ", password: "secret")
		}
		#expect(harness.sink.count == 0)
		harness.finish()
	}

	/// 登入途中的錯誤嘗試記錄詢問由全域表自動應答，流程不中斷。
	@Test
	private func `login auto answers the delete error attempts prompt`() async throws {
		let harness: SessionHarness = .init()
		let task: Task<Void, any Error> = harness.run { session in
			try await session.logIn(userIdentifier: "dreamer", password: "secret")
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.deleteErrorAttempts)
		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.mainMenu)
		#expect(await harness.waitForCompletion())
		try await task.value
		#expect(harness.sink.batches[1] == [.text("y"), .enter, .formFeed])
		harness.finish()
	}

	/// 密碼錯誤畫面是已知失敗，直接回報而不是等到逾時。
	@Test
	private func `wrong password screen fails fast`() async {
		let harness: SessionHarness = .init()
		let task: Task<Void, any Error> = harness.run { session in
			try await session.logIn(userIdentifier: "dreamer", password: "secret")
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.wrongPassword)
		#expect(await harness.waitForCompletion())
		await #expect(throws: PTTSessionError.unexpectedScreen("密碼不對或無此帳號")) {
			try await task.value
		}
		harness.finish()
	}

	/// 沒有任何目標畫面出現時，等滿逾時就放棄。
	@Test
	private func `wait gives up after the timeout`() async {
		let harness: SessionHarness = .init()
		let task: Task<Void, any Error> = harness.run { session in
			try await session.logIn(userIdentifier: "dreamer", password: "secret")
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.unrelated)
		#expect(await harness.waitForCompletion(step: .seconds(1), limit: 60))
		await #expect(throws: PTTSessionError.timedOut) { try await task.value }
		harness.finish()
	}

	/// 快照流結束（連線已關）時不再空等逾時。
	@Test
	private func `wait stops once the screen stream ends`() async {
		let harness: SessionHarness = .init()
		let task: Task<Void, any Error> = harness.run { session in
			try await session.logIn(userIdentifier: "dreamer", password: "secret")
		}
		#expect(await harness.waitForSend(count: 1))
		harness.finish()
		#expect(await harness.waitForCompletion())
		await #expect(throws: PTTSessionError.screenStreamEnded) { try await task.value }
	}

	/// 命中資源上限畫面：先記進節流閘、退避滿三十秒才送下一顆鍵。
	@Test
	private func `resource limit screen backs off before the next send`() async throws {
		let harness: SessionHarness = .init()
		let task: Task<Void, any Error> = harness.run { session in
			try await session.logIn(userIdentifier: "dreamer", password: "secret")
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.resourceLimit)
		#expect(await harness.waitForSend(count: 2, step: .seconds(1), limit: 120))
		harness.yield(TestScreens.mainMenu)
		#expect(await harness.waitForCompletion())
		try await task.value
		let first: ContinuousClock.Instant? = harness.sink.instant(at: 0)
		let second: ContinuousClock.Instant? = harness.sink.instant(at: 1)
		guard let first, let second else {
			Issue.record("預期記錄到兩批送鍵")
			return
		}
		#expect(first.duration(to: second) >= SendThrottle.resourceLimitBackoff)
		#expect(harness.sink.batches[1] == [.formFeed])
		harness.finish()
	}

	/// 節流退避期間補進來的畫面不算「這次送鍵的回應」。
	///
	/// 界線取在真的寫進 sink 的前一刻：退避途中補上的主功能表屬於退避前的殘影，
	/// 送鍵之後沒有新畫面，等待就該走到逾時而不是誤判登入成功。
	@Test
	private func `screens arriving during the backoff are not counted as the response`() async {
		let harness: SessionHarness = .init()
		let task: Task<Void, any Error> = harness.run { session in
			try await session.logIn(userIdentifier: "dreamer", password: "secret")
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.resourceLimit)
		_ = await advanceUntil(harness.clock, step: .seconds(1), limit: 5) { false }
		harness.yield(TestScreens.mainMenu)
		#expect(await harness.waitForSend(count: 2, step: .seconds(1), limit: 120))
		#expect(await harness.waitForCompletion(step: .seconds(1), limit: 40))
		await #expect(throws: PTTSessionError.timedOut) { try await task.value }
		harness.finish()
	}

	/// 一般連續送鍵之間至少隔一個最小節流間隔。
	@Test
	private func `consecutive sends keep the minimum interval`() async throws {
		let harness: SessionHarness = .init()
		let task: Task<Void, any Error> = harness.run { session in
			try await session.logIn(userIdentifier: "dreamer", password: "secret")
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.deleteErrorAttempts)
		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.mainMenu)
		#expect(await harness.waitForCompletion())
		try await task.value
		let first = try #require(harness.sink.instant(at: 0), "預期記錄到兩批送鍵")
		let second = try #require(harness.sink.instant(at: 1), "預期記錄到兩批送鍵")
		#expect(first.duration(to: second) >= SendThrottle.minimumInterval)
		harness.finish()
	}

	/// 每一批送出的按鍵都以重繪鍵收尾。
	@Test
	private func `every batch ends with the redraw key`() async throws {
		let harness: SessionHarness = .init()
		let task: Task<Void, any Error> = harness.run { session in
			try await session.logIn(userIdentifier: "dreamer", password: "secret")
		}
		#expect(await harness.waitForSend(count: 1))
		harness.yield(TestScreens.deleteErrorAttempts)
		#expect(await harness.waitForSend(count: 2))
		harness.yield(TestScreens.mainMenu)
		#expect(await harness.waitForCompletion())
		try await task.value
		#expect(harness.sink.batches.allSatisfy { $0.last == .formFeed })
		harness.finish()
	}

	/// 固定控制序列的位元組：Enter／重繪／中斷／方向鍵；字面文字不在此層決定編碼。
	@Test
	private func `control keys carry fixed byte sequences`() {
		#expect(PTTKey.enter.controlBytes == [0x0D])
		#expect(PTTKey.formFeed.controlBytes == [0x0C])
		#expect(PTTKey.interrupt.controlBytes == [0x03])
		#expect(PTTKey.arrowLeft.controlBytes == [0x1B, 0x4F, 0x44])
		#expect(PTTKey.text("abc").controlBytes == nil)
	}
}
