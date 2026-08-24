//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - BoardName

/// 板名的形狀檢查。
///
/// 板名會被原樣打進站方的看板快選欄位（`qs` 之後那一格），所以它是進板路徑上
/// 「呼叫端給的字串直接變成送出的按鍵」的地方。不先驗形狀的話，字串裡的換行、
/// `Ctrl` 類控制字元或超長內容會被當成後續操作送進去，站方看到的就不再是我們以為
/// 送出的那串——後果不是解析失敗，是安靜地跑到別的畫面去。
///
/// **判準取站方自己的規則**（來源 https://github.com/ptt/pttbbs 的
/// `common/bbs/string.c` `is_valid_brdname()`）：長度上限 `IDLEN`（`include/pttstruct.h`
/// 為 12）、字元限英數與 `_` `-` `.`。
///
/// !!!: 站方那支還多兩條——長度下限 2、首字必須是英文字母。**這裡刻意不套**：那支是
/// 建板時的入口檢查，站上既有看板未必都是在該規則生效後建的；我們的目的是擋掉會改變
/// 送出內容的字元，不是複製站方的建板政策。判嚴會把一個真的進得去的看板擋在門外，
/// 而那種失敗從呼叫端看起來與「看板不存在」無法分辨。
enum BoardName {

	// MARK: Internal

	/// 板名長度上限（站方 `IDLEN`）。
	static let maximumLength: Int = 12

	/// 板名形狀是否合法。空字串一律不合法——它送出去只會是一個空的看板快選。
	static func isValid(_ name: String) -> Bool {
		guard !name.isEmpty, name.unicodeScalars.count <= maximumLength else { return false }
		return name.unicodeScalars.allSatisfy(isAllowed)
	}

	// MARK: Private

	/// 白名單逐字元判定。
	///
	/// !!!: 不用 `Character` 的 `isLetter`／`isNumber`——那兩個吃的是 Unicode 分類，
	/// 中文板名之類的字串會整串通過，等於沒擋。這裡直接比對 ASCII 純量範圍。
	private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
		switch scalar {
		case "A" ... "Z", "a" ... "z", "0" ... "9": true
		case "_", "-", ".": true
		default: false
		}
	}
}
