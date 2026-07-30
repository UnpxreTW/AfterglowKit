//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTArticleKind

/// 標題前面那兩格的類別記號。
///
/// 站方在作者欄之後、標題之前固定印兩格的類別記號，取值照原始碼 `readdoent()` 裡
/// 決定 `mark` 的那段 switch 移植（來源 https://github.com/ptt/pttbbs 的 `mbbsd/bbs.c`）。
///
/// !!!: ``normal`` 的 `□` 同時也是「已被安全刪除」文章的記號——站方兩者印同一個字，
/// 從清單畫面無法分辨。想知道是不是已刪，得看文章本身。
public enum PTTArticleKind: String, Sendable {

	/// 一般文章（也可能是已被安全刪除的文章，見型別註解）。
	case normal = "□"

	/// 投票文。
	case vote = "ˇ"

	/// 回覆文。
	case reply = "R:"

	/// 轉錄文。
	case forwarded = "轉"

	/// 已鎖定的文章（不可再推文或修改）。
	case locked = "鎖"
}
