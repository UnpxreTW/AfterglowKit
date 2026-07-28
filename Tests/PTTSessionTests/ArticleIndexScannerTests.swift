//
//  PTTSessionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTSession
import PTTTerminal
import Testing

/// ``ArticleIndexScanner`` 判讀驗證：連號驗證、表頭略過、編號欄邊界、雜訊排除。
private final class ArticleIndexScannerTests {

	/// 表頭：三列佔位，內容不重要、只要不含會干擾的數字。
	private static let header: [String] = [
		"【板主：someone】",
		"看板《Test》",
		"　　　　　　"
	]

	/// 產生一段編號連續的文章清單列。
	private static func listing(from lower: Int, through upper: Int) -> [String] {
		(lower ... upper).map { "  \($0) + 7/23 alice      □ 測試標題" }
	}

	/// 一般清單：取最大且連號驗證通過的編號。
	@Test
	private func `reads the newest index from a consecutive listing`() {
		let screen: PTTScreen = makeScreen(Self.header + Self.listing(from: 1022, through: 1027))
		#expect(ArticleIndexScanner.newestIndex(in: screen) == 1027)
	}

	/// 表頭三列裡的數字不算候選。
	@Test
	private func `ignores numbers in the header lines`() {
		var lines: [String] = Self.header
		lines[0] = "  9999 表頭不該被當成文章編號"
		let screen: PTTScreen = makeScreen(lines + Self.listing(from: 1022, through: 1027))
		#expect(ArticleIndexScanner.newestIndex(in: screen) == 1027)
	}

	/// 編號欄以「欄」為單位、不是以「字元」為單位。
	///
	/// 四個全形字就吃掉八欄，後面的數字已經落在編號欄外；若改用字元數去切，
	/// 這些數字會被誤收成候選、而且它們彼此連號、連號驗證也擋不住。
	@Test
	private func `ignores numbers beyond the index column`() {
		let lines: [String] = (1230 ... 1235).map { "全形全形 \($0) 這不是編號" }
		let screen: PTTScreen = makeScreen(Self.header + lines)
		#expect(ArticleIndexScanner.newestIndex(in: screen) == nil)
	}

	/// 孤零零一個大數字：連號驗證擋下、回 nil 讓呼叫端重取畫面。
	@Test
	private func `returns nil when consecutive verification fails`() {
		let screen: PTTScreen = makeScreen(Self.header + ["  5000 + 7/23 alice      標題"])
		#expect(ArticleIndexScanner.newestIndex(in: screen) == nil)
	}

	/// 文章數少於驗證深度時，驗證深度收斂到候選值本身、不因湊不滿而失敗。
	@Test
	private func `handles a board with fewer articles than the verification depth`() {
		let screen: PTTScreen = makeScreen(Self.header + Self.listing(from: 1, through: 3))
		#expect(ArticleIndexScanner.newestIndex(in: screen) == 3)
	}

	/// 完全沒有數字的畫面回 nil。
	@Test
	private func `returns nil for a listing without any number`() {
		let screen: PTTScreen = makeScreen(Self.header + ["       ★ 置底公告", "       ★ 板規"])
		#expect(ArticleIndexScanner.newestIndex(in: screen) == nil)
	}

	/// 寬字元不會把編號欄的欄位計算推歪（延續格佔的是欄、不是字元）。
	@Test
	private func `wide characters do not shift the index column`() {
		let listing: [String] = (1022 ... 1027).map { "  \($0) ◆ 七月 測試標題與全形字" }
		let screen: PTTScreen = makeScreen(Self.header + listing)
		#expect(ArticleIndexScanner.newestIndex(in: screen) == 1027)
	}

}
