//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import PTTTerminal

// MARK: - PTTScreenText

/// 把 `PTTScreen` 格子矩陣攤成可做子字串比對的純文字。
public enum PTTScreenText {

	// MARK: Public

	/// 每列一個字串：寬字元的延續格略過、行尾空白去除。
	///
	/// 延續格（`width == 0`）承載的是前一個全形字的第二欄、本身沒有字元意義，
	/// 保留它會在文字裡插入一顆假空白、讓「看板資訊/設定」這類 pattern 對不上。
	public static func lines(of screen: PTTScreen) -> [String] {
		screen.rows.map { row in
			var line: String = ""
			line.reserveCapacity(row.count)
			for cell in row where cell.width > 0 {
				line.append(cell.character)
			}
			while line.last == " " {
				line.removeLast()
			}
			return line
		}
	}

	/// 整個畫面攤成單一字串（列間以換行相接），供目標 pattern 比對。
	public static func flattened(_ screen: PTTScreen) -> String {
		lines(of: screen).joined(separator: "\n")
	}
}
