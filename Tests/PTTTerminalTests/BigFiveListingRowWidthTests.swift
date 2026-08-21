//
//  PTTTerminalTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import PTTBig5Codec
@testable import PTTTerminal
import Testing

/// 以真實 Big5 位元組餵完整轉碼管線（``StreamTranscoder`` → ``Sequence/serializeUTF8()`` →
/// ``PTTTerminal/feed(_:)``），逐格釘住畫面的欄寬。
///
/// **為什麼要釘**：站方版面是按「一個 Big5 雙位元組字＝兩欄」排的，但清單畫面天天出現的
/// `□`(U+25A1)、`ˇ`(U+02C7)、`★`(U+2605)、全形游標 `●`(U+25CF) 在 Unicode 東亞寬度分類
/// 裡都是 **Ambiguous**。就一般文字而言，SwiftTerm 1.13.0 的欄寬只認 `eastAsianWide` 一張表
/// （`Utilities.swift` 的 `columnWidth(rune:)`／`isEastAsianWide(_:)`，無 ambiguous 設定可調），
/// 這幾個字因此回一欄。
///
/// 一欄或兩欄不是風格問題：格子矩陣的欄號就是 `PTTSession` 判讀欄位的座標，差一欄整列的
/// 欄位就整批平移。目前這個對應關係沒有任何測試釘著，SwiftTerm 換版或改判 ambiguous
/// 都會靜默改變判讀結果——本檔即為此而立，餵的是真位元組、斷言的是實際格子。
private final class BigFiveListingRowWidthTests {

	/// 把一段 Big5 位元組走完整條轉碼管線、餵進終端，回第一列的格子。
	private static func firstRow(ofBig5 bytes: [UInt8]) async -> [PTTCell] {
		var transcoder: StreamTranscoder = .init(target: .bbs)
		let tokens: [PTTByte] = transcoder.feed(bytes) + transcoder.finish()
		let terminal: PTTTerminal = .init()
		await terminal.feed(tokens.serializeUTF8())
		return await terminal.screen.rows[0]
	}

	/// 東亞寬度 Ambiguous 的四個常見記號各佔**一**欄，同列的一般漢字佔兩欄。
	///
	/// 四個字站方都是印成兩欄的；這裡斷言的是我們手上這顆終端實際給出的欄寬，
	/// 兩者不一致本身就是要被釘住的事實（見型別註解）。漢字 `許` 一併餵進來當對照組：
	/// 它在 `eastAsianWide` 表內、確實回兩欄並帶一格延續格，證明測到的差異來自寬度分類、
	/// 不是整條管線都沒把寬字元認出來。
	@Test
	private func `ambiguous width big5 symbols occupy a single column`() async {
		let bytes: [UInt8] = [
			0xA1, 0xB4, // ● U+25CF 全形游標記號
			0xA1, 0xBC, // □ U+25A1 一般文章類別記號
			0xA3, 0xBE, // ˇ U+02C7 投票文類別記號
			0xA1, 0xB9, // ★ U+2605 置底文編號欄記號
			0xB3, 0x5C  // 許 U+8A31 對照組：東亞寬字
		]
		let row: [PTTCell] = await Self.firstRow(ofBig5: bytes)
		#expect(row[0].character == "●")
		#expect(row[0].width == 1)
		#expect(row[1].character == "□")
		#expect(row[1].width == 1)
		#expect(row[2].character == "ˇ")
		#expect(row[2].width == 1)
		#expect(row[3].character == "★")
		#expect(row[3].width == 1)
		#expect(row[4].character == "許")
		#expect(row[4].width == 2)
		#expect(row[5].width == 0)
	}

	/// 帶全形游標記號的清單列：游標之後的每一欄都比站方座標少一欄。
	///
	/// 餵的位元組照站方 `readdoent()` 的版面排（來源 https://github.com/ptt/pttbbs 的
	/// `mbbsd/bbs.c`）：兩欄游標記號、五位編號、一欄空白、一欄狀態記號、兩欄推文數、
	/// 五欄日期、一欄空白、十三欄作者、兩欄類別記號、一欄空白、標題。
	///
	/// !!!: 站方座標下狀態記號在第 8 欄、日期在第 11–15 欄，正是 `ArticleListingScanner`
	/// 逐欄切欄位用的常數；下面斷言的實際落點分別是第 7 欄與第 10–14 欄。差的那一欄
	/// 來自全形游標記號只佔到一格。推文數的 `爆` 是一般漢字、兩欄如實，平移量因此
	/// 只由前面出現過幾個 Ambiguous 記號決定，不會沿列累加。
	@Test
	private func `full width cursor marker shifts the rest of a listing row by one column`() async {
		var bytes: [UInt8] = [0xA1, 0xB4] // 站方 0–1：全形游標記號 ●
		bytes += Array("12345 +".utf8) // 站方 2–6 編號、7 空白、8 狀態記號
		bytes += [0xC3, 0x7A] // 站方 9–10：推文數「爆」
		bytes += Array("12/25 unpxre       ".utf8) // 站方 11–15 日期、16 空白、17–29 作者
		bytes += [0xA1, 0xBC] // 站方 30–31：類別記號 □
		bytes += Array(" [test] ".utf8) // 站方 32 空白、33– 標題
		bytes += [0xB4, 0xFA, 0xB8, 0xD5] // 標題內的漢字「測試」
		let row: [PTTCell] = await Self.firstRow(ofBig5: bytes)
		#expect(row[0].character == "●")
		#expect(String(row[1 ... 5].map(\.character)) == "12345")
		#expect(row[7].character == "+")
		#expect(row[8].character == "爆")
		#expect(row[8].width == 2)
		#expect(row[9].width == 0)
		#expect(String(row[10 ... 14].map(\.character)) == "12/25")
		#expect(String(row[16 ... 21].map(\.character)) == "unpxre")
		#expect(row[29].character == "□")
		#expect(row[29].width == 1)
		#expect(String(row[31 ... 36].map(\.character)) == "[test]")
		#expect(row[38].character == "測")
		#expect(row[38].width == 2)
		#expect(row[40].character == "試")
		#expect(row[40].width == 2)
	}
}
