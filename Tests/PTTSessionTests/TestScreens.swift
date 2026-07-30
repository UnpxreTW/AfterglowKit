//
//  PTTSessionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import PTTTerminal

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
	///
	/// 這個版本只保證**編號欄**落在正確的欄位上，其餘欄位是示意骨架——
	/// 供只看編號的判讀（``ArticleIndexScanner``）使用。要逐欄位斷言請用
	/// ``articleListing(from:through:)`` 或
	/// ``articleRow(index:cursorColumns:mark:pushCount:date:author:kind:title:)``。
	static func boardListing(from lower: Int, through upper: Int) -> [String] {
		boardHeader + (lower ... upper).map { "  \($0) + 7/23 alice      □ 測試標題" } + boardFooter
	}

	/// 依站方欄位寬度組一列文章清單。
	///
	/// 欄位起點以**欄**計（非字元）：編號 0、狀態記號 8、推文數 9、日期 11、作者 17、
	/// 類別記號 30、標題 33。`pushCount`、`date`、`kind` 須自行給滿欄寬（分別為 2、5、2 欄），
	/// 因為它們可能是全形字——這裡不替呼叫端猜顯示寬度。
	///
	/// `cursorColumns` 模擬游標記號佔掉編號欄最左邊幾欄：一欄是 ASCII 游標、兩欄是全形圓點，
	/// 而站方把游標移開時是以同寬空白覆蓋回去、不還原數字。這裡一律填空白——`>`、圓點、空白
	/// 對編號判讀是同一回事（都不是數字），差別只在蓋掉幾欄。
	static func articleRow(
		index: Int,
		cursorColumns: Int = 0,
		mark: Character = " ",
		pushCount: String = "  ",
		date: String = " 7/23",
		author: String = "alice",
		kind: String = "□",
		title: String = "測試標題"
	) -> String {
		var indexField: String = .init(repeating: " ", count: max(0, 7 - "\(index)".count)) + "\(index)"
		if cursorColumns > 0 {
			indexField = String(repeating: " ", count: cursorColumns) + indexField.dropFirst(cursorColumns)
		}
		let authorField: String = author + String(repeating: " ", count: max(0, 13 - author.count))
		return indexField + " " + String(mark) + pushCount + date + " " + authorField + kind + " " + title
	}

	/// 依站方欄位寬度組一整張清單畫面（表頭 + 指定編號區間 + 底部功能列）。
	static func articleListing(from lower: Int, through upper: Int) -> [String] {
		boardHeader + (lower ... upper).map { articleRow(index: $0) } + boardFooter
	}

	// MARK: 文章內文（M3）

	/// 本站文章的表頭三列（首行「作者」開頭）。
	static let standardArticleHeader: [String] = [
		"作者  alice (Alice)                              看板  Test",
		"標題  測試標題",
		"時間  Mon Jul 30 12:00:00 2026"
	]

	/// 轉信文章的表頭四列（首行「發信人」開頭）。
	static let forwardedArticleHeader: [String] = [
		"發信人  alice (Alice)                            看板  Test",
		"標題  Fw: 測試標題",
		"時間  Mon Jul 30 12:00:00 2026",
		"文章網址  https://example.invalid/x"
	]

	/// pmore 表頭後那條分隔線（畫滿整列、不是檔案內容）。
	static let headerSeparator = String(repeating: "─", count: 78)

	/// 推文原始行的三個樣式（推 / 噓 / →）。
	static let sampleCommentLines: [String] = [
		"推 bob:推文內容                                          07/30 12:01",
		"噓 carol:噓文內容                                         07/30 12:02",
		"→ dave:箭頭補充內容                                       07/30 12:03"
	]

	/// 站方偵測到可播放文字動畫的詢問。
	static let movieDetectedPromptScreen: [String] = [" ★ 這份文件是可播放的文字動畫，要開始播放嗎? [Y/n]"]

	/// 傳統動畫檔：詢問播放速度。
	static let traditionalAnimationSpeedPromptScreen: [String] = ["這可能是傳統動畫檔, 若要直接播放請輸入速度(秒): "]

	/// 傳統動畫檔：詢問是否模擬 24 行。
	static let traditionalLineCountPromptScreen: [String] = [
		"傳統動畫是以 24 行為單位設計的, 要模擬 24 行嗎? (否則會用現在的行數)[Yn] "
	]

	/// 舊式狀態列（無行號區間，`bpref.oldstatusbar` 走這條時 footer 認不出行號）。
	static let oldStyleStatusBar = "  瀏覽 P.1(50%)  "

	/// `override_msg` 蓋掉行號區間那一段的示意文字（同樣認不出行號）。
	static let overrideMessage = " ‣ 已依您的要求執行 "

	/// 依指定行數量產內文行（純測試骨架，內容本身不重要）。
	static func articleBodyLines(count: Int, startingAt start: Int = 1) -> [String] {
		(start ..< (start + count)).map { "內文第\($0)行的示意文字" }
	}

	/// footer「目前顯示: 第 N~M 行」格式（未水平捲動）。
	static func footerCurrentDisplay(_ range: ClosedRange<Int>) -> String {
		" 目前顯示: 第 \(twoDigits(range.lowerBound))~\(twoDigits(range.upperBound)) 行"
	}

	/// footer「顯示範圍: N~M 欄位, N~M 行」格式（水平捲動時）。
	static func footerScrolled(columns: ClosedRange<Int> = 1 ... 80, lines range: ClosedRange<Int>) -> String {
		let lines: String = "\(twoDigits(range.lowerBound))~\(twoDigits(range.upperBound))"
		return " 顯示範圍: \(columns.lowerBound)~\(columns.upperBound) 欄位, \(lines) 行"
	}

	/// 組一頁文章內文畫面：`contentRows`（可能含表頭 + 分隔線，不含 footer）依序填進
	/// 前 ``PTTTerminal/rows`` `- 1` 列，缺的列補空白；最後一列固定放 `footer`。
	static func articleContentScreen(contentRows: [String], footer: String) -> [String] {
		var lines: [String] = Array(contentRows.prefix(PTTTerminal.rows - 1))
		while lines.count < PTTTerminal.rows - 1 { lines.append("") }
		lines.append(footer)
		return lines
	}

	// MARK: Private

	/// 個位數補一個前導零，符合站方 `%02d` 格式；不足兩位以上的值原樣輸出。
	private static func twoDigits(_ value: Int) -> String {
		value < 10 ? "0\(value)" : "\(value)"
	}
}
