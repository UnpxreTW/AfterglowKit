//
//  PTTConnection
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - EngineClock

/// 引擎的時間來源抽象：單調時刻、睡眠、牆鐘。
///
/// 頻率閘 / keepalive / 早夭判定全走此介面，單元測試注入假時鐘以算術推進、
/// 不靠真實等待（連線引擎測試永不 sleep 牆鐘時間）。
public struct EngineClock: Sendable {

	/// 正式環境：`ContinuousClock` + 系統牆鐘。
	public static let continuous: EngineClock = .init(
		now: { ContinuousClock.now },
		sleep: { try await ContinuousClock().sleep(for: $0) },
		wallClockNow: { Date() }
	)

	/// 目前單調時刻（頻率閘、keepalive 排程、早夭窗以此計）。
	public var now: @Sendable () -> ContinuousClock.Instant

	/// 睡眠指定時長；須響應 task cancellation（取消時丟 `CancellationError`）。
	public var sleep: @Sendable (Duration) async throws -> Void

	/// 目前牆鐘時刻（僅「週日清晨例行斷線窗」判定需要日曆語義）。
	public var wallClockNow: @Sendable () -> Date

	/// 以三個注入點組裝時鐘（測試用；正式環境直接用 ``continuous``）。
	public init(
		now: @escaping @Sendable () -> ContinuousClock.Instant,
		sleep: @escaping @Sendable (Duration) async throws -> Void,
		wallClockNow: @escaping @Sendable () -> Date
	) {
		self.now = now
		self.sleep = sleep
		self.wallClockNow = wallClockNow
	}
}

// MARK: - DisconnectReason

/// 連線終止原因分類；slot 釋放時隨 ``PTTConnection/state`` 回報。
public enum DisconnectReason: Equatable, Sendable {

	/// 我們顯式 `close()`（前景轉背景、LRU 讓位、CLI 用畢即斷）。
	case localClose

	/// 對端結束流、且落在週日清晨例行重開窗——視為常態、不當異常告警。
	case routineMaintenance

	/// 對端結束流（例行窗以外）。
	case serverClose

	/// 讀流丟錯（網路層失敗；帶錯誤描述）。
	case failure(String)
}

// MARK: - MaintenanceWindow

/// 站方例行重開窗判定：每週日清晨約 5:00（台北時間）例行重開、所有連線必斷。
public enum MaintenanceWindow {

	/// 判定時刻是否落在例行重開窗（台北時間週日 04:00–08:00，取寬容窗涵蓋「約 5:00」的浮動）。
	public static func contains(
		_ date: Date,
		timeZone: TimeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
	) -> Bool {
		var calendar: Calendar = .init(identifier: .gregorian)
		calendar.timeZone = timeZone
		let parts = calendar.dateComponents([.weekday, .hour], from: date)
		return parts.weekday == 1 && (4 ..< 8).contains(parts.hour ?? -1)
	}
}
