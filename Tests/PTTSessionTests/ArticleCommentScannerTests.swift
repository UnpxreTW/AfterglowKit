//
//  PTTSessionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTSession
import Testing

/// ``ArticleCommentScanner`` 判讀驗證：三種種類、來源位址欄有無、內容邊界、格式不符的列。
private final class ArticleCommentScannerTests {

	/// 依站方欄寬規則組一行推文原始行（`FormatCommentString()` 去掉色碼之後的樣子）。
	///
	/// 內容欄寬照站方的 `78 - 3 - 6 - 1 - 6 - 推文者長度`（有位址欄再少十五格）算；
	/// 補白這裡按字元數補，站方按顯示欄數補——判讀是從行尾往回錨的，不受這個差異影響，
	/// 全形字的案例才刻意用得到這一點。
	private static func line(
		_ type: PTTCommentType,
		author: String,
		message: String,
		sourceIP: String? = nil,
		time: String = "07/31 12:34"
	) -> String {
		let padding: String = .init(
			repeating: " ",
			count: max(0, contentWidth(author: author, sourceIP: sourceIP) - message.count)
		)
		let address: String = sourceIP.map {
			String(repeating: " ", count: max(0, 15 - $0.count)) + $0
		} ?? ""
		return "\(type.rawValue) \(author):\(message)\(padding)\(address) \(time)"
	}

	/// 站方給這一則推文的內容欄寬。
	private static func contentWidth(author: String, sourceIP: String?) -> Int {
		(sourceIP == nil ? 62 : 47) - author.count
	}

	/// 組一行**尾段直接接在內容後面**的推文原始行。
	///
	/// `line(_:author:message:sourceIP:time:)` 會把內容補白到定寬，補白之後行尾取到的
	/// 段落恆為空字串——那正是沒有位址欄時該有的樣子，卻也讓位址判定的分支測不到。
	/// 要測那些分支就得讓內容與尾段之間只有一格空白，故另備這個組法。
	private static func lineEndingWith(_ tail: String, time: String = "07/31 12:34") -> String {
		"推 bob:內容 \(tail) \(time)"
	}

	/// 三種種類各判得出來，且各自的欄位都切在對的地方。
	@Test
	private func `reads all three comment types`() {
		let lines: [String] = PTTCommentType.allCases.map {
			Self.line($0, author: "alice", message: "說了一句")
		}
		let comments: [PTTComment] = ArticleCommentScanner.comments(from: lines)
		#expect(comments.map(\.type) == PTTCommentType.allCases)
		#expect(comments.allSatisfy { $0.author == "alice" })
		#expect(comments.allSatisfy { $0.message == "說了一句" })
		#expect(comments.allSatisfy { $0.time == "07/31 12:34" })
		#expect(comments.allSatisfy { $0.sourceIP == nil })
	}

	/// 沒開來源位址欄的看板：尾段只有時刻，內容不被切走一段。
	@Test
	private func `reads a comment from a board without the address field`() {
		let comments: [PTTComment] = ArticleCommentScanner.comments(
			from: [Self.line(.push, author: "bob", message: "同意")]
		)
		#expect(comments == [PTTComment(type: .push, author: "bob", message: "同意", sourceIP: nil, time: "07/31 12:34")])
	}

	/// 有開來源位址欄的看板：位址切出來、不留在內容裡。
	@Test
	private func `reads the source address when the board logs it`() {
		let lines: [String] = [
			Self.line(.push, author: "bob", message: "同意", sourceIP: "123.45.67.89"),
			Self.line(.boo, author: "carol", message: "不同意", sourceIP: "1.2.3.4")
		]
		let comments: [PTTComment] = ArticleCommentScanner.comments(from: lines)
		#expect(comments.map(\.sourceIP) == ["123.45.67.89", "1.2.3.4"])
		#expect(comments.map(\.message) == ["同意", "不同意"])
	}

	/// 站方把位址末段遮成星號的那一式同樣認得，且照原文回傳、不還原。
	@Test
	private func `reads a masked source address`() {
		let comments: [PTTComment] = ArticleCommentScanner.comments(
			from: [Self.line(.arrow, author: "dave", message: "補充", sourceIP: "123.45.67.*")]
		)
		#expect(comments.first?.sourceIP == "123.45.67.*")
		#expect(comments.first?.message == "補充")
	}

	/// 同一篇裡只要有一則收不到位址，整篇就判成沒有位址欄。
	///
	/// 這一條釘的是「每一則都要有」而不是「有一則有就算有」——判準若鬆成後者，
	/// 有位址那則的位址會被切走、沒位址那則的內容尾巴也會跟著被當成位址。
	@Test
	private func `treats the whole article as having no address field when one comment lacks it`() {
		let lines: [String] = [
			Self.line(.push, author: "bob", message: "同意", sourceIP: "1.2.3.4"),
			Self.line(.push, author: "carol", message: "了解")
		]
		#expect(!ArticleCommentScanner.sourceIPLogged(in: lines))
		let comments: [PTTComment] = ArticleCommentScanner.comments(from: lines)
		#expect(comments.map(\.sourceIP) == [nil, nil])
		#expect(comments.first?.message.hasPrefix("同意") == true)
		#expect(comments.first?.message.hasSuffix("1.2.3.4") == true)
	}

	/// 全篇都收得出位址才算有這一欄。
	@Test
	private func `decides the address field over the whole article`() {
		let withAddress: [String] = [
			Self.line(.push, author: "bob", message: "同意", sourceIP: "1.2.3.4"),
			Self.line(.push, author: "carol", message: "同意", sourceIP: "5.6.7.8")
		]
		#expect(ArticleCommentScanner.sourceIPLogged(in: withAddress))
		#expect(!ArticleCommentScanner.sourceIPLogged(in: [Self.line(.push, author: "bob", message: "同意")]))
	}

	/// 一則推文都認不出來時不會誤判成「有位址欄」。
	@Test
	private func `does not claim an address field for an article without comments`() {
		#expect(!ArticleCommentScanner.sourceIPLogged(in: []))
		#expect(!ArticleCommentScanner.sourceIPLogged(in: ["※ 發信站: 批踢踢實業坊(ptt.cc)"]))
	}

	/// 沒有位址欄時，內容補白讓行尾取不到任何段落——位址判定不必靠內容長什麼樣。
	@Test
	private func `content padding leaves no trailing token when there is no address field`() {
		#expect(!ArticleCommentScanner.sourceIPLogged(in: [Self.line(.push, author: "bob", message: "版本 1.2.3.4")]))
	}

	/// 位址欄的樣子逐段驗：段數不對、段值超出範圍、空段、非數字、整段過長都不算位址。
	@Test
	private func `rejects malformed address fields`() {
		let malformed: [String] = [
			"1.2.3",
			"1.2.3.4.5",
			"1.2.3.999",
			"1.2.3.",
			".2.3.4",
			"1234.2.3.4",
			"1.2.3.x",
			"1234.1234.1234.1234"
		]
		for tail in malformed {
			#expect(ArticleCommentScanner.comment(from: Self.lineEndingWith(tail), sourceIPLogged: true) == nil)
		}
	}

	/// 完整位址與遮蔽式都收，邊界值 255 也收。
	@Test
	private func `accepts both plain and masked address fields`() {
		let plain: PTTComment? = ArticleCommentScanner.comment(
			from: Self.lineEndingWith("255.255.255.255"),
			sourceIPLogged: true
		)
		#expect(plain?.sourceIP == "255.255.255.255")
		#expect(plain?.message == "內容")
		let masked: PTTComment? = ArticleCommentScanner.comment(
			from: Self.lineEndingWith("123.45.67.*"),
			sourceIPLogged: true
		)
		#expect(masked?.sourceIP == "123.45.67.*")
	}

	/// 內容剛好填滿定寬、又剛好以位址的樣子結尾——這是純文字層分不開的那一種。
	///
	/// 同篇還有一則沒有位址，整批判定因此把它留在內容裡；這一條同時證明那道判定確實
	/// 是為了這個情形而存在，不是可有可無的裝飾。
	@Test
	private func `keeps an address-looking tail in the message when the article has no address field`() {
		let width: Int = Self.contentWidth(author: "bob", sourceIP: nil)
		let filled: String = .init(repeating: "x", count: width - "10.0.0.1".count) + "10.0.0.1"
		let lines: [String] = [
			Self.line(.push, author: "bob", message: filled),
			Self.line(.push, author: "carol", message: "了解")
		]
		#expect(!ArticleCommentScanner.sourceIPLogged(in: lines))
		#expect(ArticleCommentScanner.comments(from: lines).first?.message == filled)
	}

	/// 推文者與內容切在**第一個**冒號，內容裡的冒號照留。
	@Test
	private func `splits the author at the first colon only`() {
		let comments: [PTTComment] = ArticleCommentScanner.comments(
			from: [Self.line(.push, author: "erin", message: "重點: 這裡還有一個冒號")]
		)
		#expect(comments.first?.author == "erin")
		#expect(comments.first?.message == "重點: 這裡還有一個冒號")
	}

	/// 看板設成推文對齊時，站方補在代號右邊的空白不算代號的一部分。
	@Test
	private func `trims the padding a board with aligned comments adds to the author`() {
		let comments: [PTTComment] = ArticleCommentScanner.comments(
			from: ["推 bob         :對齊看板                                          07/31 12:34"]
		)
		#expect(comments.first?.author == "bob")
		#expect(comments.first?.message == "對齊看板")
	}

	/// 內容剛好填滿定寬、與尾段之間沒有補白時照樣切得開。
	@Test
	private func `reads a message that exactly fills the fixed width`() {
		let filled: String = .init(repeating: "x", count: Self.contentWidth(author: "bob", sourceIP: nil))
		let comments: [PTTComment] = ArticleCommentScanner.comments(from: [Self.line(.push, author: "bob", message: filled)])
		#expect(comments.first?.message == filled)
	}

	/// 內容為空的推文回空字串、不是判讀失敗。
	@Test
	private func `reads a comment with an empty message`() {
		let comments: [PTTComment] = ArticleCommentScanner.comments(from: [Self.line(.push, author: "bob", message: "")])
		#expect(comments.first?.message == "")
		#expect(comments.first?.author == "bob")
	}

	/// 全形字不會讓判讀偏掉——欄位是從行尾往回錨的，不靠欄數推算。
	@Test
	private func `wide characters do not shift the parsed fields`() {
		let comments: [PTTComment] = ArticleCommentScanner.comments(
			from: [Self.line(.boo, author: "frank", message: "全形全形全形全形全形", sourceIP: "9.9.9.9")]
		)
		#expect(comments.first?.message == "全形全形全形全形全形")
		#expect(comments.first?.sourceIP == "9.9.9.9")
	}

	/// 轉錄記錄與站方尾註不是推文（開頭不是三個種類記號）。
	@Test
	private func `rejects lines that are not comments`() {
		let lines: [String] = [
			"※ someone:轉錄至看板 Test                                       07/31 12:34",
			"※ 發信站: 批踢踢實業坊(ptt.cc), 來自: 1.2.3.4",
			"這是內文的一行"
		]
		#expect(ArticleCommentScanner.comments(from: lines).isEmpty)
	}

	/// 種類記號後面沒有那一格空白就不是推文列。
	@Test
	private func `rejects a line without the space after the type mark`() {
		#expect(ArticleCommentScanner.comment(from: "推bob:沒有空白                07/31 12:34", sourceIPLogged: false) == nil)
	}

	/// 行尾不是站方時刻格式就整列作廢，不把尾段併進內容。
	@Test
	private func `rejects a line whose tail is not a station timestamp`() {
		#expect(ArticleCommentScanner.comment(from: "推 bob:被蓋掉的尾段", sourceIPLogged: false) == nil)
		#expect(ArticleCommentScanner.comment(from: "推 bob:壞掉的時刻                7/31 12:34", sourceIPLogged: false) == nil)
	}

	/// 形狀對、但月日時分超出範圍的尾段不是站方時刻（站方那一欄是 `strftime` 印的）。
	@Test
	private func `rejects an out-of-range timestamp`() {
		let outOfRange: [String] = ["13/01 12:34", "00/01 12:34", "07/32 12:34", "07/00 12:34", "07/31 24:34", "07/31 12:60"]
		for time in outOfRange {
			let line: String = Self.line(.push, author: "bob", message: "內容", time: time)
			#expect(ArticleCommentScanner.comment(from: line, sourceIPLogged: false) == nil)
		}
	}

	/// 說了有位址欄卻認不出位址時回 `nil`，不把位址欄的內容默默併進內容。
	@Test
	private func `rejects a line whose address field cannot be read`() {
		let line: String = Self.line(.push, author: "bob", message: "沒有位址")
		#expect(ArticleCommentScanner.comment(from: line, sourceIPLogged: true) == nil)
		#expect(ArticleCommentScanner.comment(from: line, sourceIPLogged: false) != nil)
	}

	/// 冒號前面那段太長就不是推文者代號（站方代號上限十二格）。
	@Test
	private func `rejects a line whose author exceeds the identifier width`() {
		let line: String = "推 abcdefghijklm:超過上限                                     07/31 12:34"
		#expect(ArticleCommentScanner.comment(from: line, sourceIPLogged: false) == nil)
	}

	/// 冒號只出現在時刻裡的列不是推文列——代號那一段會含空白而被擋下。
	@Test
	private func `rejects a line whose first colon is inside the timestamp`() {
		#expect(ArticleCommentScanner.comment(from: "推 bob 沒有冒號                  07/31 12:34", sourceIPLogged: false) == nil)
	}

	/// 認不出來的列被略過、其餘照收——呼叫端可用進出數量差看出少了幾列。
	@Test
	private func `skips unreadable lines and keeps the rest`() {
		let lines: [String] = [
			Self.line(.push, author: "bob", message: "第一則"),
			"推 bob:尾段壞了",
			Self.line(.boo, author: "carol", message: "第三則")
		]
		let comments: [PTTComment] = ArticleCommentScanner.comments(from: lines)
		#expect(comments.count == 2)
		#expect(comments.map(\.message) == ["第一則", "第三則"])
	}

}
