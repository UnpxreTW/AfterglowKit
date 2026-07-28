//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTArticleMark

/// 文章清單列上「編號」後面那一格的狀態記號。
///
/// 一個字元同時編碼兩件事：**已讀狀態**（未讀／已讀／發表後被修改過）與**標記狀態**
/// （精華、我的標記、已解決、待處理標籤）。取值與含義照站方原始碼的 `type` 變數移植，
/// 不自行歸納——來源 https://github.com/ptt/pttbbs 的 `mbbsd/bbs.c`（`readdoent()`）。
///
/// 兩軸擠進一格是站方版面的既成事實，這裡沿用同一組字元、不硬拆成兩個欄位：
/// 拆了反而要替「未讀且被標記」這種本來就只有一個字元表達的狀態發明對照關係。
public enum PTTArticleMark: Character, Sendable {

	/// 已讀。
	case read = " "

	/// 未讀。
	case unread = "+"

	/// 已讀過、但作者之後修改過內文。
	case modified = "~"

	/// 已讀的精華文章。
	case digest = "*"

	/// 未讀的精華文章。
	case unreadDigest = "#"

	/// 已標記且已標成解決。
	case markedSolved = "!"

	/// 已標記、已讀。
	case marked = "m"

	/// 已標記、未讀。
	case markedUnread = "M"

	/// 已標記、讀過後又被修改。
	case markedModified = "="

	/// 已標成解決、已讀。
	case solved = "s"

	/// 已標成解決、未讀。
	case solvedUnread = "S"

	/// 被貼上待處理標籤（板務批次操作用）。
	case tagged = "D"
}
