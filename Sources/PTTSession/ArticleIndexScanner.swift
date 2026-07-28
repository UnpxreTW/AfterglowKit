//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import PTTTerminal

// MARK: - ArticleIndexScanner

/// 從看板文章清單畫面判讀「最新一篇的編號」。
///
/// 前提是畫面已經跳到清單末端（送 `1` + Enter 定位到第一篇、再送 `$` 跳到最後一篇）。
///
/// **連號驗證防的是什麼**：候選編號取自畫面左側編號欄，而畫面可能殘留上一頁的字、
/// 或因寬字元對齊偏移把別欄的數字切進編號欄。要求最大候選往下數個連號都在畫面上，
/// 就能把這類雜訊擋掉。它**不是**用來排除置底文——置底文的編號欄顯示的是星號、
/// 根本不會產生數字候選。
public enum ArticleIndexScanner {

	// MARK: Public

	/// 略過的表頭列數（看板標題與欄位說明佔畫面最上方三列）。
	public static let headerLineCount = 3

	/// 編號欄寬度：每列只取最左側這幾欄找數字。
	public static let indexColumnWidth = 9

	/// 連號驗證深度：候選編號往下數這麼多個都要出現在畫面上。
	///
	/// 候選本身小於此值時（新開的看板只有兩三篇文章），驗證深度收斂到候選值本身，
	/// 不會因為湊不滿而誤判失敗。
	public static let verificationDepth = 6

	/// 判讀最新編號；回 `nil` 表示畫面雜訊過多、無法可靠判定（呼叫端應重取畫面再試）。
	///
	/// 「看板沒有文章」不走這裡回 0——那是另一張目標畫面（畫面上直接寫著沒有文章），
	/// 由呼叫端在等畫面階段就分流掉，這裡只處理「有清單」的情形。
	public static func newestIndex(in screen: PTTScreen) -> Int? {
		let screenText: String = PTTScreenText.flattened(screen)
		var candidates: Set<Int> = []
		for row in screen.rows.dropFirst(headerLineCount) {
			candidates.formUnion(numbers(inFirst: indexColumnWidth, of: row))
		}
		for candidate in candidates.sorted(by: >) where candidate > 0 {
			let depth: Int = min(candidate, verificationDepth)
			let verified: Bool = (1 ..< depth).allSatisfy { screenText.contains(String(candidate - $0)) }
			if verified { return candidate }
		}
		return nil
	}

	// MARK: Private

	/// 取一列最左側 `columns` 欄裡所有的十進位數字串。
	///
	/// 逐格走而非先組字串再切——格數就是顯示欄數，全形字不會讓欄位計算偏掉。
	/// 只認 ASCII 數字：全形數字不會出現在編號欄，放行只會多開一條誤判的路。
	private static func numbers(inFirst columns: Int, of row: [PTTCell]) -> [Int] {
		var found: [Int] = []
		var digits: String = ""
		for cell in row.prefix(columns) {
			if cell.character.isASCII, cell.character.isNumber {
				digits.append(cell.character)
				continue
			}
			if let number = Int(digits) { found.append(number) }
			digits = ""
		}
		if let number = Int(digits) { found.append(number) }
		return found
	}
}
