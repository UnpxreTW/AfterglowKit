//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTSessionError

/// Session 層的失敗。
public enum PTTSessionError: Error, Equatable {

	/// 等到逾時仍沒有任何目標畫面出現。
	case timedOut

	/// 快照流已結束（連線已關）、不可能再有新畫面。
	case screenStreamEnded

	/// Session 已被 ``PTTSession/close()`` 關閉。
	case closed

	/// 帳號或密碼為空（去除前後空白、截斷長度之後）。
	case emptyCredentials

	/// 命中已知的失敗畫面；附帶目標名稱。
	case unexpectedScreen(String)

	/// 同一次等待內自動應答次數超過上限——通常代表畫面卡在某個沒被表涵蓋的分支。
	case tooManyResponses(String)

	/// 進不了指定看板（看板不存在，或名稱打錯）。
	case noSuchBoard(String)

	/// 連續重試後仍無法從清單畫面判讀出最新編號。
	case indexParseFailed(String)

	/// 連續重試後仍無法從清單畫面判讀出任何一列文章。
	case listingParseFailed(String)

	/// 要求的編號區間不成立（起點小於 1，或起點大於終點）。
	case invalidIndexRange

	/// 連續重試後仍讀不到文章的任何一頁（footer 行號區間或畫面列合併皆判讀失敗），
	/// 且尚未成功收到過任何一頁——已收到至少一頁時改回傳部分結果並標不完整，
	/// 不丟這個錯誤（見 ``PTTArticleContent/isComplete``）。
	case articleReadFailed(board: String, index: Int)
}
