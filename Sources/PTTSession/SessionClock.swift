//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - SessionClock

/// Session 的時間來源抽象：單調時刻與睡眠。
///
/// 節流閘、等畫面逾時、CPULIMIT 退避全走此介面，單元測試注入假時鐘以算術推進、
/// 不等真實時間。
///
/// **為何不共用連線層的 `EngineClock`**：`PTTConnection` 拖著 SwiftNIO 一整串
/// 傳輸相依，而 Session 對外只認「快照流 + 送鍵 sink」兩個抽象、刻意不依賴連線層。
/// 為了一個三行的時間介面把整條 SSH 相依鏈拉進本模組（與其測試）不划算，
/// 故此處另立同形的小型別；兩者若需再收斂，該做的是抽出共用的時間 target，
/// 不是讓 Session 反向依賴連線層。
public struct SessionClock: Sendable {

	/// 正式環境：`ContinuousClock`。
	public static let continuous: SessionClock = .init(
		now: { ContinuousClock.now },
		sleep: { try await ContinuousClock().sleep(for: $0) }
	)

	/// 目前單調時刻。
	public var now: @Sendable () -> ContinuousClock.Instant

	/// 睡眠指定時長；須響應 task cancellation（取消時丟 `CancellationError`）。
	public var sleep: @Sendable (Duration) async throws -> Void

	/// 以兩個注入點組裝時鐘（測試用；正式環境直接用 ``continuous``）。
	public init(
		now: @escaping @Sendable () -> ContinuousClock.Instant,
		sleep: @escaping @Sendable (Duration) async throws -> Void
	) {
		self.now = now
		self.sleep = sleep
	}
}
