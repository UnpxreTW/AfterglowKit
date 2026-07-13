//
//  PTTTerminal
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTScreen

/// 一次終端畫面快照：cell 矩陣 + 游標狀態，與底層渲染機制無關（見 ``PTTTerminal`` 型別註解的
/// 「rendering 層解耦」設計原則）。呼叫端可直接拿本結構餵 SwiftUI 自製 renderer、
/// 單元測試斷言、或未來其他 rendering 路徑，不需匯入 SwiftTerm。
public struct PTTScreen: Equatable, Sendable {

	/// 固定 ``PTTTerminal/rows`` 列、每列固定 ``PTTTerminal/columns`` 欄的 cell 矩陣（`rows[row][column]`）。
	public let rows: [[PTTCell]]

	/// 游標位置與可見性。
	public let cursor: PTTCursor

	/// 建立一次快照。
	public init(rows: [[PTTCell]], cursor: PTTCursor) {
		self.rows = rows
		self.cursor = cursor
	}
}
