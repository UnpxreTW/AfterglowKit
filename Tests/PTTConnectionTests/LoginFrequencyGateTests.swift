//
//  PTTConnectionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTConnection
import Testing

/// 頻率閘純邏輯驗證：3 秒最小間隔、被拒 backoff ≥30 秒、分鐘 / 小時滑動窗。
private final class LoginFrequencyGateTests {

	/// 無歷史 → 立即可登。
	@Test
	private func `idle gate requires no delay`() {
		let gate: LoginFrequencyGate = .init()
		#expect(gate.requiredDelay(now: .now) == .zero)
	}

	/// 剛登過 → 3 秒內不可重登（硬底線）、滿 3 秒放行。
	@Test
	private func `three second minimum between attempts`() {
		var gate: LoginFrequencyGate = .init()
		let base = ContinuousClock.Instant.now
		gate.recordAttempt(at: base)
		#expect(gate.requiredDelay(now: base + .seconds(1)) == .seconds(2))
		#expect(gate.requiredDelay(now: base + .seconds(3)) == .zero)
	}

	/// 被拒 → 至少 30 秒 backoff（覆蓋 3 秒規則）。
	@Test
	private func `rejection enforces thirty second backoff`() {
		var gate: LoginFrequencyGate = .init()
		let base = ContinuousClock.Instant.now
		gate.recordAttempt(at: base)
		gate.recordRejection(at: base)
		#expect(gate.requiredDelay(now: base + .seconds(5)) == .seconds(25))
		#expect(gate.requiredDelay(now: base + .seconds(30)) == .zero)
	}

	/// 一分鐘內第 10 次後：要等最舊嘗試滑出 60 秒窗才可再登。
	@Test
	private func `per minute window blocks eleventh attempt`() {
		var gate: LoginFrequencyGate = .init()
		let base = ContinuousClock.Instant.now
		for index in 0 ..< 10 {
			gate.recordAttempt(at: base + .seconds(index * 4)) // 每 4 秒一次、避開 3 秒規則
		}
		// 第 10 次在 base+36s；3 秒規則只要求 base+39s，但分鐘窗要等 base（第 1 次）+60s。
		let now = base + .seconds(40)
		#expect(gate.requiredDelay(now: now) == .seconds(20))
		#expect(gate.requiredDelay(now: base + .seconds(60)) == .zero)
	}

	/// 一小時內第 60 次後：小時窗生效。
	@Test
	private func `per hour window blocks sixty first attempt`() {
		var gate: LoginFrequencyGate = .init()
		let base = ContinuousClock.Instant.now
		for index in 0 ..< 60 {
			gate.recordAttempt(at: base + .seconds(index * 61)) // 每 61 秒一次、避開分鐘窗
		}
		// 第 60 次在 base+3599s；小時窗要等第 1 次（base）滑出 3600 秒窗。
		let now = base + .seconds(3602)
		#expect(gate.requiredDelay(now: now) == .zero) // base 已滑出（3602 > 3600）→ 窗內剩 59 次、放行
		let crowded = base + .seconds(3599)
		#expect(gate.requiredDelay(now: crowded) > .zero) // 60 次全在窗內 → 擋
	}
}
