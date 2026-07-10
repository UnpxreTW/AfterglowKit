//
//  PTTConnection
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - LoginFrequencyGate

/// 登入頻率閘：對照站方 utmpd `action_frequently()` 的三道閾值
/// （距上次 ≤3 秒、>10 次/分、>60 次/時 → 拒 + sleep 30 秒斷線），
/// 在 client 端先行自律——**絕不 3 秒內重登、被拒後 backoff ≥30 秒**。
///
/// 純狀態機、不睡眠：呼叫端拿 ``requiredDelay(now:)`` 自行等待。
/// 時間一律由呼叫端注入 instant，單元測試用算術推進、不靠真實時鐘。
public struct LoginFrequencyGate: Sendable {

	// MARK: Public

	/// 硬底線：兩次登入嘗試的最小間隔（站方 ≤3s 即拒；client 端取同值自律）。
	public static let minimumInterval: Duration = .seconds(3)

	/// 被拒後的最小 backoff（站方拒絕時 server 端 sleep 30s 後斷線；client 端至少等同樣久）。
	public static let rejectionBackoff: Duration = .seconds(30)

	/// 每分鐘登入次數上限（含本次；站方 >10 次/分即拒）。
	public static let attemptsPerMinute = 10

	/// 每小時登入次數上限（含本次；站方 >60 次/時即拒）。
	public static let attemptsPerHour = 60

	/// 下一次登入嘗試前必須等待的時間；`.zero` = 立即可登。
	///
	/// 取四道規則的最大值：3 秒最小間隔、被拒 backoff、分鐘窗、小時窗。
	public func requiredDelay(now: ContinuousClock.Instant) -> Duration {
		var earliest = now
		if let last = attempts.last {
			earliest = max(earliest, last + Self.minimumInterval)
		}
		if let rejection = lastRejection {
			earliest = max(earliest, rejection + Self.rejectionBackoff)
		}
		earliest = max(earliest, windowOpening(now: now, window: .seconds(60), limit: Self.attemptsPerMinute))
		earliest = max(earliest, windowOpening(now: now, window: .seconds(3600), limit: Self.attemptsPerHour))
		return earliest > now ? now.duration(to: earliest) : .zero
	}

	/// 記錄一次登入嘗試（呼叫端在實際發起 connect 時記、不是排隊時記）。
	public mutating func recordAttempt(at instant: ContinuousClock.Instant) {
		attempts.append(instant)
		let horizon = instant - .seconds(3600)
		attempts.removeAll { $0 < horizon }
	}

	/// 記錄一次被拒（連線失敗 / 登入期早夭都保守視為拒）；下次嘗試至少推遲 ``rejectionBackoff``。
	public mutating func recordRejection(at instant: ContinuousClock.Instant) {
		lastRejection = instant
	}

	/// 建立空閘（無歷史、立即可登）。
	public init() {}

	// MARK: Private

	/// 最近一小時內的登入嘗試時刻（升冪；超窗即修剪）。
	private var attempts: [ContinuousClock.Instant] = []

	/// 最近一次被拒時刻。
	private var lastRejection: ContinuousClock.Instant?

	/// 滑動窗規則：窗內已滿 `limit` 次 → 等到「窗內只剩 `limit - 1` 次舊嘗試」的時刻
	/// （阻擋者 = 由新往舊數第 `limit` 次那筆，它滑出窗外新嘗試才不超限）。
	private func windowOpening(now: ContinuousClock.Instant, window: Duration, limit: Int) -> ContinuousClock.Instant {
		let windowStart = now - window
		let inWindow = attempts.filter { $0 >= windowStart } // attempts 升冪（recordAttempt 單調追加）
		guard inWindow.count >= limit, let blocking = inWindow.dropLast(limit - 1).last else { return now }
		return blocking + window
	}
}
