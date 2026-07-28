//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTPushCount

/// 文章清單列上的推文數欄位。
///
/// **這一欄只有兩格寬，站方本來就印不下完整數字**——所以這裡是「站方顯示了什麼」的
/// 忠實模型，不是「這篇有幾則推文」的精確值。要精確值得進文章內文數，不在清單畫面上。
/// 各分支照站方原始碼 `readdoent()` 組 `recom` 字串的那一段移植
/// （來源 https://github.com/ptt/pttbbs 的 `mbbsd/bbs.c`）。
public enum PTTPushCount: Equatable, Sendable {

	/// 空白：推文數在 -10 ～ 0 之間，站方不顯示。
	///
	/// !!!: 空白**不等於**沒有推文——小額噓文也落在這一格。想區分只能進文章內文。
	case none

	/// 1 ～ 99 則推文（站方以兩位數右對齊印出）。
	case pushes(Int)

	/// 爆：推文數達站方上限（100 則以上）。
	case exploded

	/// 噓文 10 則以上：站方只印得下十位數（`X1` = 10 ～ 19、`X9` = 90 ～ 99）。
	///
	/// 站方組字串時用 `X%d` 帶完整數字、再被欄寬截成兩格，所以個位數在畫面上就已經丟了；
	/// 這裡只還原到十位級距，不假裝知道確切數字。
	case booed(tensDigit: Int)

	/// `XX`：噓文數達站方上限（100 則以上）。
	case heavilyBooed

	/// `--`：文章被鎖，站方不顯示推文數。
	case locked

	/// 未知樣式：站方版本差異或畫面殘影。原文照留，供呼叫端自行判斷或回報。
	case unrecognised(String)
}
