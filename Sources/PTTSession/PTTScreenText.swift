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

	/// 取某一列指定**欄區間**的文字（延續格略過、不另補空白）。
	///
	/// !!!: 欄不等於字元。站方畫面是定寬欄位排版，全形字佔兩欄卻只有一個字元——先攤成
	/// 字串再用字元位置切欄，遇到全形字就會整排往前錯一格（推文數欄的「爆」是最常見的
	/// 觸發點）。有格子矩陣就該按格子走，這是本函式存在的唯一理由。
	///
	/// 區間超出該列範圍的部分直接忽略，不視為錯誤——畫面殘影本來就可能短一截。
	public static func text(of row: [PTTCell], in columns: Range<Int>) -> String {
		var text: String = ""
		text.reserveCapacity(columns.count)
		for column in columns where row.indices.contains(column) && row[column].width > 0 {
			text.append(row[column].character)
		}
		return text
	}

	// MARK: Internal

	/// 去除前後空白（不引入 Foundation）。
	static func trimmed(_ value: String) -> String {
		var result: Substring = value[...]
		while let first = result.first, first.isWhitespace {
			result = result.dropFirst()
		}
		while let last = result.last, last.isWhitespace {
			result = result.dropLast()
		}
		return String(result)
	}
}
