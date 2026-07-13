//
//  PTTTerminal
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTCursor

/// 游標位置與可見性快照。
public struct PTTCursor: Equatable, Sendable {

	/// 欄（0-based，從左算起）。
	public let column: Int

	/// 列（0-based，從上算起）。已由 SwiftTerm `Terminal.restrictCursor()` 內部 clamp 在
	/// `0 ..< PTTTerminal.rows`，含 PR #129（`ptt/pttbbs`）描述的
	/// 「CUP 座標超出最底行 clamp 成最底行」情境，見 ``PTTTerminal`` 型別註解。
	public let row: Int

	/// 是否可見；對應 host 端 `ESC[?25h` / `ESC[?25l` 顯示／隱藏游標指令。
	public let isVisible: Bool

	/// 建立游標快照。
	public init(column: Int, row: Int, isVisible: Bool) {
		self.column = column
		self.row = row
		self.isVisible = isVisible
	}
}
