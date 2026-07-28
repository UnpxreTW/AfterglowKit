//
//  PTTSessionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTSession
import Testing

/// ``SendThrottle`` 純狀態機驗證：最小送鍵間隔、資源上限退避、兩者取大。
private final class SendThrottleTests {

	/// 沒有任何歷史時可立即送出。
	@Test
	private func `fresh throttle allows an immediate send`() {
		let throttle: SendThrottle = .init()
		#expect(throttle.requiredDelay(now: .now) == .zero)
	}

	/// 剛送完就再送：必須補滿最小間隔。
	@Test
	private func `second send waits out the minimum interval`() {
		var throttle: SendThrottle = .init()
		let start: ContinuousClock.Instant = .now
		throttle.recordSend(at: start)
		#expect(throttle.requiredDelay(now: start) == SendThrottle.minimumInterval)
		#expect(throttle.requiredDelay(now: start + .milliseconds(40)) == .milliseconds(60))
	}

	/// 間隔已過就不再等。
	@Test
	private func `delay clears once the interval has elapsed`() {
		var throttle: SendThrottle = .init()
		let start: ContinuousClock.Instant = .now
		throttle.recordSend(at: start)
		#expect(throttle.requiredDelay(now: start + SendThrottle.minimumInterval) == .zero)
		#expect(throttle.requiredDelay(now: start + .seconds(1)) == .zero)
	}

	/// 命中資源上限後改吃 30 秒退避，而不是 100 毫秒間隔。
	@Test
	private func `resource limit forces the long backoff`() {
		var throttle: SendThrottle = .init()
		let start: ContinuousClock.Instant = .now
		throttle.recordSend(at: start)
		throttle.recordResourceLimit(at: start)
		#expect(throttle.requiredDelay(now: start) == SendThrottle.resourceLimitBackoff)
		#expect(throttle.requiredDelay(now: start + .seconds(29)) == .seconds(1))
		#expect(throttle.requiredDelay(now: start + .seconds(30)) == .zero)
	}

	/// 退避期間又送了一次：兩道規則取大、退避仍主導。
	@Test
	private func `backoff outranks the minimum interval`() {
		var throttle: SendThrottle = .init()
		let start: ContinuousClock.Instant = .now
		throttle.recordResourceLimit(at: start)
		throttle.recordSend(at: start + .seconds(10))
		#expect(throttle.requiredDelay(now: start + .seconds(10)) == .seconds(20))
	}
}
