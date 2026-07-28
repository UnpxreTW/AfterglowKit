//
//  PTTSessionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - TestScreens

/// 測試用的合成畫面內容。
///
/// 只保留目標表實際比對的關鍵字串與版面骨架，不重製整張站方畫面——
/// 這些字串本身正確與否由目標表負責，這裡只驗流程。
enum TestScreens {

	/// 主功能表。
	static let mainMenu: [String] = [
		"【主功能表】",
		"   (0)分類看板   (1)全部看板   (2)我的最愛",
		"   (T)alk    休閒聊天       (P)lay 遊樂場",
		"   (G)oodbye 離開，再見",
		"",
		"【 dreamer 您好，您是第 30162 位訪客 】 人, 我是 dreamer",
		"[呼叫器]打開"
	]

	/// 主功能表的離站確認。
	static let mainMenuExiting: [String] = [
		"【主功能表】",
		"您確定要離開【批踢踢實業坊】嗎(Y/N)？[N]"
	]

	/// 看板文章清單的表頭三列。
	static let boardHeader: [String] = [
		"【板主：someone】",
		"看板《Test》",
		"　　　　　　"
	]

	/// 看板清單畫面底部的功能列（命中「已在看板」目標的關鍵）。
	static let boardFooter: [String] = [
		"文章選讀  (y)回應(X%)推文(h)說明(←)離開",
		"看板資訊/設定  相關主題"
	]

	/// 已進到看板、但清單上還沒有文章列的畫面。
	static let inBoard: [String] = boardHeader + boardFooter

	/// 刪除錯誤嘗試記錄的詢問。
	static let deleteErrorAttempts: [String] = ["您要刪除以上錯誤嘗試的記錄嗎(Y/N)？[N]"]

	/// 密碼錯誤。
	static let wrongPassword: [String] = ["密碼不對或無此帳號，請重新輸入"]

	/// 資源用量超限。
	static let resourceLimit: [String] = ["您的程式耗用過多計算資源，請稍候再試"]

	/// 看板沒有任何文章。
	static let emptyBoard: [String] = ["沒有文章..."]

	/// 不會命中任何目標的畫面。
	static let unrelated: [String] = ["連線中，請稍候"]

	/// 看板文章清單（表頭 + 指定編號區間的文章列 + 底部功能列）。
	static func boardListing(from lower: Int, through upper: Int) -> [String] {
		boardHeader + (lower ... upper).map { "  \($0) + 7/23 alice      □ 測試標題" } + boardFooter
	}
}
