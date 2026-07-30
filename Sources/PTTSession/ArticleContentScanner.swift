//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import PTTTerminal

// MARK: - ArticleContentScanner

/// 把文章內文畫面判讀成檔案行，錨點是站方 footer 自己印出來的行號區間、不做內容比對。
///
/// **收斂與去重錨 ＝ footer 行號區間**：每張畫面讀 footer 拿到 `(first, last)`，以行號
/// 為 key 收進結果——重疊行（正常翻頁必重疊恰好一行）自然覆蓋掉，不需要額外的去重步驟。
/// footer 認不出行號區間的畫面（`override_msg` 蓋掉、舊式狀態列、半重繪殘影）一律回 `nil`，
/// 由呼叫端補 `Ctrl+L` 重取，不猜。來源：直接讀 `ptt/pttbbs` 的 `mbbsd/pmore.c`。
///
/// **與 ``ArticleListingScanner`` 唯一的方法分歧**：清單畫面是站方 `printf` 定寬版面，
/// 可以按欄位常數精確切；文章表頭是 pmore 依終端寬度重排過的結果，沒有這種定寬版面可移植，
/// 因此表頭只能以「名稱 → 值」對切（``PTTArticleHeader``），而非欄位常數。
public enum ArticleContentScanner {

	// MARK: Public

	/// 一頁內文的判讀結果。
	public struct Page: Equatable, Sendable {

		/// footer 印出的檔案行號區間。
		public let range: ClosedRange<Int>

		/// 表頭（僅首頁可能非 `nil`，見型別註解）。
		public let header: PTTArticleHeader?

		/// `range` 起點被表頭 + 分隔線佔掉的行數（非首頁恆為 0）。
		public let skippedLineCount: Int

		/// 合併後的檔案行（不含表頭與分隔線），數量固定為 `range.count - skippedLineCount`。
		public let lines: [String]
	}

	/// 表頭之後、內文之前的分隔線列數（pmore 固定畫一整列 `─`，佔一個折行位）。
	public static let headerSeparatorRowCount = 1

	/// 解析 footer 偵測列裡的「N~M 行」區間。
	///
	/// 站方 footer 有兩種格式（`目前顯示: 第 %02d~%02d 行` 與水平捲動時的
	/// `顯示範圍: %d~%d 欄位, %02d~%02d 行`），本函式不分兩式各寫一套，改成掃整列找
	/// 「數字 ~ 數字」後面緊接（可有空白）「行」字的那一組——水平捲動式的第一組數字後面
	/// 接的是「欄位」不是「行」，天然被跳過，兩式因此共用同一條解析路徑。
	///
	/// 認不出行號區間（`override_msg` 蓋掉、舊式狀態列、半重繪殘影）一律回 `nil`，
	/// 由呼叫端當「畫面不穩定」處理，不猜。
	public static func lineRange(inFooter footerLine: String) -> ClosedRange<Int>? {
		let characters: [Character] = Array(footerLine)
		var index = 0
		var lastMatch: ClosedRange<Int>?
		while index < characters.count {
			guard characters[index].isASCII, characters[index].isNumber else {
				index += 1
				continue
			}
			var firstDigits: String = ""
			while index < characters.count, characters[index].isASCII, characters[index].isNumber {
				firstDigits.append(characters[index])
				index += 1
			}
			guard index < characters.count, characters[index] == "~" else { continue }
			index += 1
			var secondDigits: String = ""
			while index < characters.count, characters[index].isASCII, characters[index].isNumber {
				secondDigits.append(characters[index])
				index += 1
			}
			guard !secondDigits.isEmpty else { continue }
			var lookahead: Int = index
			while lookahead < characters.count, characters[lookahead] == " " { lookahead += 1 }
			guard lookahead < characters.count, characters[lookahead] == "行" else { continue }
			guard let first = Int(firstDigits), let last = Int(secondDigits), first <= last else { continue }
			lastMatch = first ... last
		}
		return lastMatch
	}

	/// 判讀一頁內文畫面：解析 footer 行號區間，首頁另外剝表頭與分隔線、其餘列合併成檔案行。
	///
	/// 回 `nil` 代表「這頁不能用」——footer 解不出行號區間，或畫面內容列合併後的數量
	/// 與 footer 宣稱的行數對不上（見 ``mergeContentRows(_:expectedLineCount:)``）。
	/// 兩種情形呼叫端一律補 `Ctrl+L` 重取、不翻頁、不推進，沿用 M2「對不上就整頁作廢」的紀律。
	///
	/// - Parameters:
	///   - screen: 目前畫面快照。
	///   - isFirstPage: 是不是這篇文章收到的第一頁——只有第一頁需要判讀表頭。
	public static func page(
		in screen: PTTScreen,
		isFirstPage: Bool
	) -> Page? {
		guard let footerLine = PTTScreenText.lines(of: screen).last else { return nil }
		guard let range = lineRange(inFooter: footerLine) else { return nil }
		var contentRows: [[PTTCell]] = Array(screen.rows.dropLast(1))
		var header: PTTArticleHeader?
		var skippedLineCount = 0
		if isFirstPage {
			let detected: (header: PTTArticleHeader?, skippedRowCount: Int) = self.header(in: contentRows)
			header = detected.header
			skippedLineCount = detected.skippedRowCount
			contentRows = Array(contentRows.dropFirst(skippedLineCount))
		}
		let expectedLineCount: Int = range.count - skippedLineCount
		guard let lines = mergeContentRows(contentRows, expectedLineCount: expectedLineCount) else { return nil }
		return Page(range: range, header: header, skippedLineCount: skippedLineCount, lines: lines)
	}

	/// 這一行是不是推文原始行（推 / 噓 / →）。
	///
	/// !!!: 判準是三個推文符號 + 一格空白的固定前綴，這是 PTT 慣例格式，非本檔已讀碼實證
	/// 的 `mbbsd/pmore.c` 片段所直接涵蓋（該檔只讀了畫面版面與翻頁行為，未讀推文列印段）——
	/// 標記為推論，掛真帳號實測後若前綴有出入，修這裡即可。
	public static func isCommentLine(_ line: String) -> Bool {
		commentPrefixes.contains { line.hasPrefix($0) }
	}

	// MARK: Internal

	/// 判讀首頁表頭：首行以「作者」開頭 → 本站文章（3 列）；「發信人」開頭 → 轉信文章（4 列）；
	/// 兩者皆非 → 沒有表頭（如精華區純文字檔）。末列為空則再減一列（來源同型別註解）。
	///
	/// 回傳的 `skippedRowCount` 已含分隔線列（``headerSeparatorRowCount``），供呼叫端
	/// 直接拿去跳過表頭 + 分隔線、不必再另外加一次。
	///
	/// !!!: 「末列空白再減一」的判準是「畫面上這一列是不是空白」，推論成因是 pmore 依此
	/// 決定实際渲染幾列表頭；未經真實帳號連線覆核是否恰好對應站方 `fh.lines` 的內部值——
	/// 若判斷錯誤，`mergeContentRows` 的總數比對通常會抓到（見該函式型別註解），不會靜默
	/// 錯位，但仍屬未證實假設，掛真帳號實測後若有出入，修這裡即可。
	static func header(in rows: [[PTTCell]]) -> (header: PTTArticleHeader?, skippedRowCount: Int) {
		guard let firstRow = rows.first else { return (nil, 0) }
		let firstLine: String = PTTScreenText.trimmed(rowText(firstRow))
		var count: Int = headerRowCount(firstLine: firstLine)
		guard count > 0 else { return (nil, 0) }
		if rows.indices.contains(count - 1), PTTScreenText.trimmed(rowText(rows[count - 1])).isEmpty {
			count -= 1
		}
		let fields: [PTTArticleHeaderField] = rows.prefix(count).compactMap { row in
			field(in: PTTScreenText.trimmed(rowText(row)))
		}
		return (PTTArticleHeader(fields: fields), count + headerSeparatorRowCount)
	}

	/// 把畫面內容列合併成檔案行；合併後的行數與 `expectedLineCount` 對不上時回 `nil`。
	///
	/// 折行記號 `\`（列尾非空白字元）是「這列還沒完、下一列接續」的訊號；記號在 80 欄
	/// 剛好填滿時不印，此時只能靠合併後的總數比對抓出判讀錯了——這正是 `expectedLineCount`
	/// 存在的理由，折行記號本身只當輔助、不當唯一判準（見型別註解）。
	///
	/// !!!: 這個訊號天生有歧義——若某個檔案行本身就以反斜線結尾（原始內容，非折行記號），
	/// 會被誤判成續行、與下一列黏成一行。安全網是總數比對：誤黏會讓合併後行數少於
	/// `expectedLineCount`（兩列變一行），多數情況下會觸發整頁作廢重取，不會靜默留下
	/// 錯誤內容；極端情況（多處誤判剛好互相抵消總數）仍可能漏網，未進一步防禦。
	static func mergeContentRows(_ rows: [[PTTCell]], expectedLineCount: Int) -> [String]? {
		guard expectedLineCount >= 0 else { return nil }
		guard expectedLineCount > 0 else { return rows.isEmpty ? [] : nil }
		var lines: [String] = []
		lines.reserveCapacity(expectedLineCount)
		var current: String = ""
		var isAccumulating = false
		for row in rows {
			let trimmed: String = rightTrimmed(rowText(row))
			let continues: Bool = trimmed.last == "\\"
			current += continues ? String(trimmed.dropLast()) : trimmed
			isAccumulating = true
			if !continues {
				lines.append(current)
				current = ""
				isAccumulating = false
			}
		}
		if isAccumulating { lines.append(current) }
		guard lines.count == expectedLineCount else { return nil }
		return lines
	}

	// MARK: Private

	/// 推文列的固定前綴（見 ``isCommentLine(_:)`` 型別註解的推論警語）。
	private static let commentPrefixes: [String] = ["推 ", "噓 ", "→ "]

	/// 表頭列數（未計分隔線、未套用「末列空白再減一」）。
	private static func headerRowCount(firstLine: String) -> Int {
		if firstLine.hasPrefix("作者") { return 3 }
		if firstLine.hasPrefix("發信人") { return 4 }
		return 0
	}

	/// 把一列表頭文字切成「名稱 → 值」：取第一段連續兩個以上空白當分隔。
	///
	/// 切不出分隔時整行當名稱、值留空——比起丟掉這列，保留原文讓呼叫端自行判斷更安全。
	private static func field(in line: String) -> PTTArticleHeaderField? {
		let characters: [Character] = Array(line)
		var index = 0
		while index < characters.count {
			if characters[index] == " ", index + 1 < characters.count, characters[index + 1] == " ", index > 0 {
				var gapEnd: Int = index
				while gapEnd < characters.count, characters[gapEnd] == " " { gapEnd += 1 }
				let name: String = PTTScreenText.trimmed(String(characters[0 ..< index]))
				let value: String = PTTScreenText.trimmed(String(characters[gapEnd...]))
				guard !name.isEmpty else { return nil }
				return PTTArticleHeaderField(name: name, value: value)
			}
			index += 1
		}
		let name: String = PTTScreenText.trimmed(line)
		guard !name.isEmpty else { return nil }
		return PTTArticleHeaderField(name: name, value: "")
	}

	/// 一列的整寬文字（不略過延續格以外的任何格、含尾端空白，供折行記號判讀用）。
	private static func rowText(_ row: [PTTCell]) -> String {
		PTTScreenText.text(of: row, in: 0 ..< PTTTerminal.columns)
	}

	/// 只去尾端空白、保留開頭與中段——內文行的縮排是內容一部分，不能跟著被吃掉。
	private static func rightTrimmed(_ value: String) -> String {
		var result: Substring = value[...]
		while let last = result.last, last == " " { result = result.dropLast() }
		return String(result)
	}
}
