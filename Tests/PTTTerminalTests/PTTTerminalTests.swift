//
//  PTTTerminalTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTTerminal
import Testing

/// ``PTTTerminal`` headless grid 引擎驗證：初始空白畫面、ASCII／SGR／寬字元寫入、
/// CUP 超出底行 clamp（PR #129）、``screenDidChange`` 通知、游標可見性、
/// host 端查詢（DSR／CPR）的 ``PTTTerminal/outbound`` 回覆。全程不連真實 SSH，
/// 直接餵合成的 UTF-8 + ANSI 位元組。
private final class PTTTerminalTests {

	/// 未餵任何位元組時：80×24 全空白格、游標在原點且可見。
	///
	/// 空白格前景／背景皆為 `.defaultColor`——對映 SwiftTerm `CharData.defaultAttr`
	/// （`fg: .defaultColor, bg: .defaultColor`，buffer 初始填充實際使用的 attribute；
	/// 不是 `Attribute.empty` 的 `bg: .defaultInvertedColor`，兩者用途不同，v1.13.0 原始碼核對）。
	@Test
	private func `initial screen is blank with cursor at origin`() async {
		let terminal: PTTTerminal = .init()
		let screen: PTTScreen = await terminal.screen
		#expect(screen.rows.count == PTTTerminal.rows)
		#expect(screen.rows[0].count == PTTTerminal.columns)
		let expectedBlank: PTTCell = .init(
			character: " ", width: 1, foregroundColor: .defaultColor, backgroundColor: .defaultColor, attributes: []
		)
		#expect(screen.rows[0][0] == expectedBlank)
		#expect(screen.cursor == PTTCursor(column: 0, row: 0, isVisible: true))
	}

	/// 純 ASCII 文字逐格寫入、游標隨之右移。
	@Test
	private func `feed writes ascii text and advances cursor`() async {
		let terminal: PTTTerminal = .init()
		await terminal.feed(Array("Hi".utf8))
		let screen: PTTScreen = await terminal.screen
		#expect(screen.rows[0][0].character == "H")
		#expect(screen.rows[0][1].character == "i")
		#expect(screen.cursor == PTTCursor(column: 2, row: 0, isVisible: true))
	}

	/// CR/LF 換行後續寫的字落在下一列第 0 欄（驗證 `rows[row][column]` 索引方向未顛倒）。
	@Test
	private func `carriage return and linefeed move to next row`() async {
		let terminal: PTTTerminal = .init()
		await terminal.feed(Array("A\r\nB".utf8))
		let screen: PTTScreen = await terminal.screen
		#expect(screen.rows[0][0].character == "A")
		#expect(screen.rows[1][0].character == "B")
		#expect(screen.cursor == PTTCursor(column: 1, row: 1, isVisible: true))
	}

	/// SGR 粗體 + 紅色前景（`ESC[1;31m`）套用到後續寫入的字。
	@Test
	private func `feed applies sgr bold and color`() async {
		let terminal: PTTTerminal = .init()
		let sgr: [UInt8] = [0x1B, 0x5B, 0x31, 0x3B, 0x33, 0x31, 0x6D] // ESC[1;31m
		await terminal.feed(sgr + Array("A".utf8))
		let cell: PTTCell = await terminal.screen.rows[0][0]
		#expect(cell.character == "A")
		#expect(cell.attributes.contains(.bold))
		#expect(cell.foregroundColor == .ansi256(1))
	}

	/// 全形字（CJK 寬字元）佔兩欄：首欄 `width == 2`、次欄為延續格 `width == 0`。
	@Test
	private func `wide character occupies two columns with continuation cell`() async {
		let terminal: PTTTerminal = .init()
		await terminal.feed(Array("許".utf8))
		let screen: PTTScreen = await terminal.screen
		#expect(screen.rows[0][0].character == "許")
		#expect(screen.rows[0][0].width == 2)
		#expect(screen.rows[0][1].width == 0)
		#expect(screen.rows[0][1].character == " ")
		#expect(screen.cursor.column == 2)
	}

	/// CUP 座標超出最底行（`ESC[9999;1H`）clamp 成最底行——PTT 站方私有部署已知會送出此類序列
	/// （`ptt/pttbbs` PR #129），由 SwiftTerm `restrictCursor()` 內部處理，見 ``PTTTerminal`` 型別註解。
	@Test
	private func `cursor position beyond bottom row clamps to last row`() async {
		let terminal: PTTTerminal = .init()
		let cup: [UInt8] = [0x1B, 0x5B, 0x39, 0x39, 0x39, 0x39, 0x3B, 0x31, 0x48] // ESC[9999;1H
		await terminal.feed(cup + Array("X".utf8))
		let screen: PTTScreen = await terminal.screen
		#expect(screen.cursor.row == PTTTerminal.rows - 1)
		#expect(screen.rows[PTTTerminal.rows - 1][0].character == "X")
	}

	/// 有實際畫面變化的 ``PTTTerminal/feed(_:)`` 後，``PTTTerminal/screenDidChange`` 會 yield 一次。
	@Test
	private func `screen did change yields after a visible update`() async {
		let terminal: PTTTerminal = .init()
		await terminal.feed(Array("A".utf8))
		var iterator: AsyncStream<Void>.AsyncIterator = terminal.screenDidChange.makeAsyncIterator()
		let received: Void? = await iterator.next()
		#expect(received != nil)
	}

	/// 游標可見性隨 `ESC[?25l`（隱藏）／`ESC[?25h`（顯示）切換。
	@Test
	private func `cursor visibility follows show and hide escape sequences`() async {
		let terminal: PTTTerminal = .init()
		let hide: [UInt8] = [0x1B, 0x5B, 0x3F, 0x32, 0x35, 0x6C] // ESC[?25l
		let show: [UInt8] = [0x1B, 0x5B, 0x3F, 0x32, 0x35, 0x68] // ESC[?25h
		await terminal.feed(hide)
		#expect(await terminal.screen.cursor.isVisible == false)
		await terminal.feed(show)
		#expect(await terminal.screen.cursor.isVisible == true)
	}

	/// host 送出裝置狀態查詢（DSR／CPR，`ESC[6n`）時，SwiftTerm 會透過 delegate 的
	/// `send(source:data:)`（協定內唯一無預設實作的方法）要求終端回覆游標位置；
	/// 這條回覆須經 ``PTTTerminal/outbound`` 轉發給呼叫端送回 SSH 連線，否則 host 端永遠等不到回應。
	@Test
	private func `device status report triggers outbound cursor position reply`() async {
		let terminal: PTTTerminal = .init()
		let dsr: [UInt8] = [0x1B, 0x5B, 0x36, 0x6E] // ESC[6n
		await terminal.feed(dsr)
		var iterator: AsyncStream<[UInt8]>.AsyncIterator = terminal.outbound.makeAsyncIterator()
		let reply: [UInt8]? = await iterator.next()
		#expect(reply == Array("\u{1B}[1;1R".utf8))
	}
}
