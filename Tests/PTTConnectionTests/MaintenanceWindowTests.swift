//
//  PTTConnectionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTConnection
import Foundation
import Testing

/// 週日清晨例行重開窗判定（台北時間週日 04:00–08:00）。
private final class MaintenanceWindowTests {

	/// 以 ISO8601（含台北時區偏移）建測試時刻。
	private static func date(_ iso: String) -> Date {
		let formatter: ISO8601DateFormatter = .init()
		guard let parsed = formatter.date(from: iso) else {
			fatalError("測試時刻字串無法解析：\(iso)")
		}
		return parsed
	}

	/// 週日 05:00 台北 → 例行窗內（站方約 5:00 重開）。
	@Test
	private func `sunday early morning is maintenance window`() {
		#expect(MaintenanceWindow.contains(Self.date("2026-07-12T05:00:00+08:00")))
	}

	/// 窗界：04:00 起算、08:00 結束（前含後不含）。
	@Test
	private func `window boundaries`() {
		#expect(MaintenanceWindow.contains(Self.date("2026-07-12T04:00:00+08:00")))
		#expect(MaintenanceWindow.contains(Self.date("2026-07-12T07:59:59+08:00")))
		#expect(!MaintenanceWindow.contains(Self.date("2026-07-12T08:00:00+08:00")))
		#expect(!MaintenanceWindow.contains(Self.date("2026-07-12T03:59:59+08:00")))
	}

	/// 週日正午 → 窗外。
	@Test
	private func `sunday noon is not maintenance window`() {
		#expect(!MaintenanceWindow.contains(Self.date("2026-07-12T12:00:00+08:00")))
	}

	/// 平日清晨（週一 05:00）→ 窗外。
	@Test
	private func `weekday early morning is not maintenance window`() {
		#expect(!MaintenanceWindow.contains(Self.date("2026-07-13T05:00:00+08:00")))
	}

	/// 時區語義：UTC 週六 21:00 = 台北週日 05:00 → 窗內（判定跟台北牆鐘走）。
	@Test
	private func `utc saturday evening maps into taipei sunday window`() {
		#expect(MaintenanceWindow.contains(Self.date("2026-07-11T21:00:00Z")))
	}
}
