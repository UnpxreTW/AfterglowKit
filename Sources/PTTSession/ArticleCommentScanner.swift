//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - ArticleCommentScanner

/// 把推文原始行判讀成 ``PTTComment``。
///
/// **版面是站方寫檔時的定值**：站方以
/// `"%s%s " ANSI_COLOR(33) "%s" ANSI_RESET ANSI_COLOR(33) ":%-*s" ANSI_RESET "%s\n"`
/// 組出整行再附加到文章檔尾（`FormatCommentString()`，來源
/// https://github.com/ptt/pttbbs 的 `mbbsd/comments.c`），去掉色碼後就是
/// 「種類 ＋ 一格空白 ＋ 推文者 ＋ 冒號 ＋ 定寬內容 ＋ 尾段」。尾段由同 repo `mbbsd/bbs.c`
/// 的推文流程組出：看板有開推文記錄來源位址時是「十五格右對齊位址 ＋ 一格空白 ＋ 時刻」，
/// 沒開時只有「一格空白 ＋ 時刻」。內容欄寬則是 `78 - 3 - 6 - 1 - 6 - 推文者長度`
/// （有開位址再少十五格）——**兩種情形整行都恰好佔滿 78 欄**。
///
/// !!!: **一律從行尾往回錨、不用欄位常數**。內容欄寬會隨推文者代號長度浮動（站方是先扣掉
/// `strlen(myid)` 才決定欄寬的），只有時刻永遠佔行尾十一格；從右邊切就不必先知道推文者多長。
/// 這也是本型別與 ``ArticleListingScanner`` 的方法差異：清單畫面是定寬欄位、推文行不是。
///
/// !!!: **來源位址欄與內容之間在純文字層沒有硬分界**——站方唯一的硬分界是色碼（內容欄印在
/// `ESC[33m` 之內、尾段在 `ANSI_RESET` 之後），而推文原始行到我們手上時色彩屬性已經沒了。
/// 多數情形仍分得開：內容欄是補白補到定寬的，沒有位址欄時整段就以補白收尾、尾端取不到東西。
/// 真正分不開的只有「內容剛好填滿定寬、又剛好以位址的樣子結尾」這一種，故再加一道整批判定
/// 補上：看板開了這個設定時每一則推文都會有位址，只要有一則取不到就當整篇都沒開。
public enum ArticleCommentScanner {

	// MARK: Public

	/// 判讀一整篇文章的推文原始行。
	///
	/// 來源位址欄的有無由整批一起判（見型別註解），所以請整篇一次交進來、不要逐行呼叫
	/// ``comment(from:sourceIPLogged:)`` 自己拼——那樣每一行都得自己猜有沒有位址欄。
	///
	/// 認不出格式的列略過、不中斷整批：交進來的是文章讀取路徑已經分類成推文的那些列，
	/// 走到這裡還認不出來代表格式模型與站方對不上。呼叫端要察覺這件事，比對「交進來幾列」
	/// 與「拿回去幾則」的差額即可——本函式不會為了湊數而回半組欄位。
	public static func comments(from lines: [String]) -> [PTTComment] {
		let logged: Bool = sourceIPLogged(in: lines)
		return lines.compactMap { comment(from: $0, sourceIPLogged: logged) }
	}

	/// 判讀單一推文原始行；認不出格式時回 `nil`。
	///
	/// - Parameter sourceIPLogged: 這篇文章的推文尾段帶不帶來源位址欄。傳 `true` 卻在尾段
	///   認不出位址時回 `nil`，不把位址欄的內容默默併進 ``PTTComment/message``。
	public static func comment(from line: String, sourceIPLogged: Bool) -> PTTComment? {
		guard let parts: Parts = parts(of: line) else { return nil }
		var message: Substring = parts.message
		var sourceIP: String?
		if sourceIPLogged {
			guard let address: String = trailingAddress(of: message) else { return nil }
			message = message.dropLast(address.count)
			sourceIP = address
		}
		return PTTComment(
			type: parts.type,
			author: String(parts.author),
			message: PTTScreenText.trimmed(String(message)),
			sourceIP: sourceIP,
			time: String(parts.time)
		)
	}

	// MARK: Internal

	/// 站方時刻欄的欄寬（`%m/%d %H:%M`，來源同 repo 的 `common/sys/time.c`）。
	static let timeWidth: Int = 11

	/// 站方來源位址欄的欄寬（`%15s` 右對齊）。
	static let sourceIPWidth: Int = 15

	/// 推文者代號的長度上限（站方的 `IDLEN`）。
	///
	/// 站方那個緩衝區是以**位元組**計的，而全形字在站方的編碼下一個字佔兩個位元組；
	/// 以字元數比對只會比站方寬鬆，不會誤擋掉站方寫得出來的代號。
	static let authorWidthLimit: Int = 12

	/// 這批推文原始行的尾段帶不帶來源位址欄。
	///
	/// 判準是「**每一則**認得出格式的推文，內容尾端都收得出一個位址」——看板開了這個設定就
	/// 是全篇都有，漏一則就代表那不是位址欄、是誰的內容剛好以位址結尾。
	///
	/// !!!: 這條判準在兩個方向上會判不準，兩者的爆炸半徑都是整篇、不是單則。①一篇只有一則
	/// 推文時它退化成單則猜測（該則內容剛好填滿定寬又以位址結尾就會被誤收成位址）；②位址剛好
	/// 佔滿十五格、內容也剛好填滿定寬時，兩段中間沒有空白可切，整篇會被判成沒有位址欄、位址
	/// 留在內容尾端。②的觸發條件之一（內容能不能剛好填滿定寬）取決於站方輸入函式的長度語意，
	/// **未實測、屬推論**。
	static func sourceIPLogged(in lines: [String]) -> Bool {
		let messages: [Substring] = lines.compactMap { parts(of: $0)?.message }
		guard !messages.isEmpty else { return false }
		return messages.allSatisfy { trailingAddress(of: $0) != nil }
	}

	// MARK: Private

	/// 一行推文拆出來的四段；內容段尚未從尾端切出來源位址。
	private struct Parts {

		/// 種類。
		let type: PTTCommentType

		/// 推文者代號（站方推文對齊補的空白已去除）。
		let author: Substring

		/// 內容段（含站方補到定寬的空白，也含尚未切出的來源位址欄）。
		let message: Substring

		/// 時刻段。
		let time: Substring
	}

	/// 把一行推文原始行拆成四段；不合站方格式時回 `nil`。
	private static func parts(of line: String) -> Parts? {
		var body: Substring = line[...]
		while body.last == " " {
			body = body.dropLast()
		}
		guard let type: PTTCommentType = leadingType(of: body) else { return nil }
		let afterType: Substring = body.dropFirst(2)
		guard let colon: Substring.Index = afterType.firstIndex(of: ":") else { return nil }
		// 站方推文對齊是左對齊補到十二格（`%-*s`），補的空白只會在代號右邊。
		var author: Substring = afterType[..<colon]
		while author.last == " " {
			author = author.dropLast()
		}
		guard isAuthor(author) else { return nil }
		var rest: Substring = afterType[afterType.index(after: colon)...]
		guard rest.count > timeWidth else { return nil }
		let time: Substring = rest.suffix(timeWidth)
		guard isStationTime(time) else { return nil }
		rest = rest.dropLast(timeWidth)
		// 時刻前面那一格空白是站方組尾段時固定加的，兩種尾段都有；沒有就不是尾段。
		guard rest.last == " " else { return nil }
		return Parts(type: type, author: author, message: rest.dropLast(), time: time)
	}

	/// 判讀行首的種類；開頭不是「種類 ＋ 一格空白」時回 `nil`。
	private static func leadingType(of body: Substring) -> PTTCommentType? {
		guard body.count > 2, body.dropFirst().first == " ", let mark: Character = body.first else {
			return nil
		}
		return PTTCommentType(rawValue: String(mark))
	}

	/// 這一段像不像推文者代號。
	///
	/// 只驗長度上限與「不含空白」，**不驗字元集**——站方的匿名推文選項會把代號換成暱稱，
	/// 暱稱取自使用者檔案裡的自由文字（`angel_load_my_fullnick()`，來源同 repo 的
	/// `mbbsd/angel.c`），不受代號字元集約束。
	///
	/// !!!: 那種暱稱若含空白會被這一關擋掉、含冒號則會讓切點落在暱稱裡（切的是第一個冒號）。
	/// 兩者都不會把欄位默默換成別的東西，但那一則會判讀不出來、或內容少一截。此路徑窄且
	/// **未經實測、屬推論**，掛真帳號時覆核。
	private static func isAuthor(_ value: Substring) -> Bool {
		guard !value.isEmpty, value.count <= authorWidthLimit else { return false }
		return !value.contains { $0.isWhitespace }
	}

	/// 這一段是不是站方的時刻格式「月/日 時:分」。
	///
	/// 除了形狀，月日時分還各自驗範圍。站方這一欄是 `strftime` 印的、必定合法，所以超出範圍
	/// 就代表那不是站方印的時刻；**這一關是整條判讀的主錨**（把不是推文的列擋在外面靠的是它，
	/// 不是前面的代號那關），放寬它等於放寬其他每一關。
	private static func isStationTime(_ value: Substring) -> Bool {
		let characters: [Character] = .init(value)
		guard characters.count == timeWidth else { return false }
		guard characters[2] == "/", characters[5] == " ", characters[8] == ":" else { return false }
		guard let month: Int = twoDigits(of: characters, at: 0), (1 ... 12).contains(month) else {
			return false
		}
		guard let day: Int = twoDigits(of: characters, at: 3), (1 ... 31).contains(day) else {
			return false
		}
		guard let hour: Int = twoDigits(of: characters, at: 6), (0 ... 23).contains(hour) else {
			return false
		}
		guard let minute: Int = twoDigits(of: characters, at: 9), (0 ... 59).contains(minute) else {
			return false
		}
		return true
	}

	/// 取時刻欄裡從 `position` 起的兩位十進位數字；不是 ASCII 數字時回 `nil`。
	///
	/// 這裡刻意排除全形數字：站方印的是 ASCII，畫面上出現全形數字代表那不是站方的時刻欄。
	private static func twoDigits(of characters: [Character], at position: Int) -> Int? {
		let digits: [Character] = [characters[position], characters[position + 1]]
		guard digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
		return Int(String(digits))
	}

	/// 取內容段尾端那個像來源位址的段落；不像就回 `nil`。
	///
	/// 站方把位址右對齊印在十五格裡，所以有位址欄時它必定是內容段最後一個非空白段落；
	/// 沒有位址欄時內容段以補白收尾，這裡取到的是空字串、正好回 `nil`。
	private static func trailingAddress(of message: Substring) -> String? {
		let token: Substring = if let separator: Substring.Index = message.lastIndex(of: " ") {
			message[message.index(after: separator)...]
		} else {
			message
		}
		guard !token.isEmpty, token.count <= sourceIPWidth, isAddress(token) else { return nil }
		return String(token)
	}

	/// 這一段是不是站方會印在來源位址欄裡的樣子。
	///
	/// 收兩式：完整的四段位址，以及末段被站方遮成 `*` 的那式（`obfuscate_ipstr()` 把最後一個
	/// 點之後整段換成一個星號，來源同 repo 的 `common/bbs/string.c`；遮或不遮是站方編譯期
	/// 設定、從公開原始碼判不出來，故兩式都收）。
	///
	/// 不收 IPv6：站方這一欄在本次讀碼的版本裡是 IPv4（欄寬常數 `IPV4LEN` 為 15、取值來自
	/// `getremotename()` 的 `sin_addr`，來源同 repo 的 `include/pttstruct.h` 與 `mbbsd/mbbsd.c`）。
	private static func isAddress(_ token: Substring) -> Bool {
		let groups: [Substring] = token.split(separator: ".", omittingEmptySubsequences: false)
		guard groups.count == 4, let last: Substring = groups.last else { return false }
		guard groups.dropLast().allSatisfy({ isAddressGroup($0) }) else { return false }
		return last == "*" || isAddressGroup(last)
	}

	/// 位址其中一段（十進位、不超過 255）。
	private static func isAddressGroup(_ group: Substring) -> Bool {
		guard !group.isEmpty, group.count <= 3 else { return false }
		guard group.allSatisfy({ $0.isASCII && $0.isNumber }), let value: Int = Int(group) else {
			return false
		}
		return value <= 255
	}
}
