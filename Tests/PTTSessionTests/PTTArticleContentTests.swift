//
//  PTTSessionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTSession
import Testing

/// ``PTTArticleContent`` 推文兩層（原始行 → 結構化）的接線驗證：判讀結果與排序依據、
/// 判讀不出的列數涵蓋哪些成因、來源位址欄的整批判定範圍是不是「一篇」。
private final class PTTArticleContentTests {

	/// 三種種類、兩式來源位址（完整與末段被遮）都判得出來；順序依檔案行號、不依時刻——
	/// 中間那則的時刻刻意早於第一則，判讀結果仍照原本的行順序排。
	@Test
	private func `raw comment lines are read into typed comments in file order`() {
		let content: PTTArticleContent = .init(
			header: nil,
			bodyLines: [],
			commentLines: [
				"推 bob:推文內容                                123.45.67.89 07/30 12:01",
				"噓 carol:噓文內容                               10.0.0.1 07/30 11:59",
				"→ dave:箭頭補充內容                            123.45.67.* 07/30 12:03"
			],
			isAnimation: false,
			isComplete: true
		)

		#expect(content.comments.map(\.type) == [.push, .boo, .arrow])
		#expect(content.comments.map(\.author) == ["bob", "carol", "dave"])
		#expect(content.comments.map(\.message) == ["推文內容", "噓文內容", "箭頭補充內容"])
		#expect(content.comments.map(\.sourceIP) == ["123.45.67.89", "10.0.0.1", "123.45.67.*"])
		#expect(content.comments.map(\.time) == ["07/30 12:01", "07/30 11:59", "07/30 12:03"])
		#expect(content.unparsedCommentLineCount == 0)
	}

	/// 判讀不出站方格式的列（這裡是行尾被畫面殘影吃掉）既不湊成半組欄位、也不靜默丟掉：
	/// 判得出來的照常回傳，判不出來的計進 ``PTTArticleContent/unparsedCommentLineCount``，
	/// 原文一列都不少。
	@Test
	private func `lines that do not match the station format are counted rather than dropped`() {
		let content: PTTArticleContent = .init(
			header: nil,
			bodyLines: [],
			commentLines: [
				"推 bob:推文內容                                          07/30 12:01",
				"推 eve:內容但時刻被殘影蓋掉",
				"→ dave:箭頭補充內容                                      07/30 12:03"
			],
			isAnimation: false,
			isComplete: true
		)

		#expect(content.comments.map(\.author) == ["bob", "dave"])
		#expect(content.unparsedCommentLineCount == 1)
		#expect(content.commentLines.count == 3)
	}

	/// 判讀不出來的列數是**過近似的代價**、不等於「判讀規則壞了」：內文行剛好以推文記號
	/// 開頭時會被收進 ``PTTArticleContent/commentLines``，再從這裡漏出來。這條釘的是那份
	/// 說明的正確性——照舊說法（「大於零＝格式模型與站方對不上」）會把維護者引去改 parser。
	@Test
	private func `a body line starting with a comment mark lands in the unparsed count`() {
		let content: PTTArticleContent = .init(
			header: nil,
			bodyLines: [],
			commentLines: ["→ 這是內文的一行，開頭剛好是箭頭記號"],
			isAnimation: false,
			isComplete: true
		)

		#expect(content.comments.isEmpty)
		#expect(content.unparsedCommentLineCount == 1)
	}

	/// 來源位址欄的有無以**一篇**為單位判定，不是逐列各判各的：同一篇裡只要有一列取不到位址，
	/// 整篇都當這個看板沒開這個設定，另外那幾列的位址就留在內容尾端、不硬切出來。
	///
	/// 這正是接線接在「整篇的推文原始行」上、而不是逐列判讀的理由——逐列判會讓同一篇裡的
	/// 欄位切法不一致。
	@Test
	private func `the source address column is judged per article rather than per line`() {
		let content: PTTArticleContent = .init(
			header: nil,
			bodyLines: [],
			commentLines: [
				"推 bob:推文內容                                123.45.67.89 07/30 12:01",
				"噓 carol:這則沒有位址                                    07/30 12:02"
			],
			isAnimation: false,
			isComplete: true
		)

		#expect(content.comments.count == 2)
		#expect(content.comments.allSatisfy { $0.sourceIP == nil })
		#expect(content.comments[0].message.hasSuffix("123.45.67.89"))
		#expect(content.unparsedCommentLineCount == 0)
	}

	/// 整批判定同時決定 ``PTTComment/sourceIP`` **與 ``PTTComment/message`` 的切點**，而它只看
	/// 得到手上這些列——所以同一列原文在「只收到它一則」與「還收到另一則沒位址的」兩種情形下
	/// 判出來的內容不同。讀取不完整時照樣判讀（不因不完整而丟掉已收到的），代價就是這個。
	///
	/// 這條把型別註解裡那段警語釘成回歸測試：`isComplete == true` 不代表位址欄判得準。
	@Test
	private func `the address column is judged on whatever lines were collected`() {
		let addressLike = "推 bob:我家 IP 是 1.2.3.4 07/30 12:01"

		let partial: PTTArticleContent = .init(
			header: nil,
			bodyLines: ["內文第1行"],
			commentLines: [addressLike],
			isAnimation: false,
			isComplete: false
		)
		// 只有這一則時，整批判定退化成單則猜測：行尾像位址就被切出去當位址。
		#expect(partial.comments.count == 1)
		#expect(partial.comments[0].sourceIP == "1.2.3.4")
		#expect(partial.comments[0].message == "我家 IP 是")

		let fuller: PTTArticleContent = .init(
			header: nil,
			bodyLines: ["內文第1行"],
			commentLines: [
				addressLike,
				"噓 carol:這則沒有位址                                    07/30 12:02"
			],
			isAnimation: false,
			isComplete: true
		)
		// 多收到一則沒位址的，整篇就判成沒開位址欄——同一列原文的內容因此多了一截。
		#expect(fuller.comments.map(\.sourceIP) == [nil, nil])
		#expect(fuller.comments[0].message == "我家 IP 是 1.2.3.4")
	}
}
