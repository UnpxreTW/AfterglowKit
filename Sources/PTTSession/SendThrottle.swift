//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - SendThrottle

/// 全域送鍵節流閘：每一次送鍵都先過這道閘，避免踩到站方的 CPU 用量防濫用機制。
///
/// 站方對單一連線的 server 端 CPU time 設有每日上限，超用會把使用者踢到
/// 「程式耗用過多計算資源」畫面。因此自建 client 必須自己內建節流，而不是等被踢。
///
/// 純狀態機、不睡眠：呼叫端拿 ``requiredDelay(now:)`` 自行等待，時間一律由呼叫端
/// 注入 instant——與連線層頻率閘同一套寫法，單元測試用算術推進、不靠真實時鐘。
public struct SendThrottle: Sendable {

	// MARK: Public

	/// 兩次送鍵的最小間隔。
	///
	/// 起始值為保守估計、尚無實測數據；掛真實帳號量測後再收斂。
	/// 若實測頻繁命中資源上限畫面，這是第一個該往上調的旋鈕。
	public static let minimumInterval: Duration = .milliseconds(100)

	/// 命中「程式耗用過多計算資源」後的最小退避。
	///
	/// 取值對齊登入頻率閘被拒後的 30 秒退避（站方在該路徑上自己就 sleep 30 秒），
	/// 讓兩道自律機制的節奏一致。
	public static let resourceLimitBackoff: Duration = .seconds(30)

	/// 下一次送鍵前必須等待的時間；`.zero` = 立即可送。
	///
	/// 取兩道規則的最大值：最小送鍵間隔、資源上限退避。
	public func requiredDelay(now: ContinuousClock.Instant) -> Duration {
		var earliest: ContinuousClock.Instant = now
		if let last = lastSend {
			earliest = max(earliest, last + Self.minimumInterval)
		}
		if let limit = lastResourceLimit {
			earliest = max(earliest, limit + Self.resourceLimitBackoff)
		}
		return earliest > now ? now.duration(to: earliest) : .zero
	}

	/// 記錄一次實際送出（呼叫端在真的寫進 sink 時記、不是排隊時記）。
	public mutating func recordSend(at instant: ContinuousClock.Instant) {
		lastSend = instant
	}

	/// 記錄一次命中資源上限畫面；下次送鍵至少推遲 ``resourceLimitBackoff``。
	public mutating func recordResourceLimit(at instant: ContinuousClock.Instant) {
		lastResourceLimit = instant
	}

	/// 建立空閘（無歷史、立即可送）。
	public init() {}

	// MARK: Private

	/// 最近一次送鍵時刻。
	private var lastSend: ContinuousClock.Instant?

	/// 最近一次命中資源上限畫面的時刻。
	private var lastResourceLimit: ContinuousClock.Instant?
}
