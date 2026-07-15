//
//  PTTTerminal
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import SwiftTerm

// MARK: - PTTTerminal

/// PTT 終端 headless grid 引擎：吃已解碼的 UTF-8 + ANSI 位元組流、內部用 SwiftTerm `Terminal`
/// 跑完整 VT100/xterm 狀態機，對外只吐 ``PTTScreen`` 這個與渲染機制無關的格子矩陣快照。
///
/// **rendering 層解耦**：呼叫端只看得到 ``PTTScreen`` / ``PTTCell`` / ``PTTColor`` /
/// ``PTTAttributes`` 這幾個不依賴 SwiftTerm 的值型別；SwiftUI 自製 renderer、單元測試斷言、
/// 未來其他 rendering 路徑都可以直接消費，不需要匯入 SwiftTerm。
///
/// **架構定位**：整體架構四層管線的 Layer 3（Connection → Codec → **Terminal** → Session）。
/// 本 actor 只依賴 SwiftTerm，不依賴 `PTTBig5Codec` 或 `PTTConnection`——上游把
/// `[PTTByte]` 序列化成 `[UInt8]`（`Sequence.serializeUTF8()`）後餵進 ``feed(_:)``，
/// 下游（`PTTSession`，未來里程碑）讀 ``screen`` 做語意萃取，兩端組裝都在本模組之外。
///
/// **尺寸**：固定 ``columns`` × ``rows``（PyPtt pattern 假設）；resize 待未來里程碑依實測需求
/// 再參數化，此版本不提供可變尺寸 API，避免發佈尚未支援的行為。
///
/// **CUP clamp**：PTT 站方曾出現 `ESC[9999;1H` 這類超出畫面底部的游標定位（`ptt/pttbbs`
/// PR #129 記載），官方建議 clamp 成最底行。這個行為由 SwiftTerm `Terminal.restrictCursor()`
/// 內部處理（`cmdCursorPosition` → `setCursor` → `restrictCursor`：
/// `buffer.y = min(rows - 1, max(0, buffer.y))`，v1.13.0 原始碼核對）——只要固定
/// `rows: 24` 建構即自動成立，本層不需要重複實作 clamp。
public actor PTTTerminal {

	// MARK: Public

	/// 固定欄數（PTT 標準 80 欄）。
	public static let columns = 80

	/// 固定列數（PTT 標準 24 列）。
	public static let rows = 24

	/// 目前螢幕快照：``rows`` × ``columns`` cell 矩陣 + 游標位置。每次存取即時從 SwiftTerm
	/// buffer 讀出、不快取——呼叫端應以 ``screenDidChange`` 決定何時重讀，不宜高頻輪詢本屬性。
	public var screen: PTTScreen {
		snapshot()
	}

	/// 螢幕變化通知：每次 ``feed(_:)`` 後若 SwiftTerm 回報有實際更新範圍即 yield 一次；
	/// 只保留最新一次待處理通知（`bufferingNewest(1)`），消費端收到後應讀 ``screen``
	/// 取最新快照，不依賴 yield 次數推斷變化內容。
	public nonisolated let screenDidChange: AsyncStream<Void>

	/// host 端查詢觸發的回覆位元組流（例如 DSR／CPR 這類終端會自動回應的查詢）。
	/// 呼叫端（未來 Session／Connection 組裝層）需接上、把這些位元組送回 SSH 連線，
	/// 否則送出這類查詢的 host 端會等不到回應——``TerminalOutboundBridge`` 的 `send`
	/// 是 SwiftTerm delegate 協定內唯一沒有預設實作的方法，代表這條路徑必定會被使用。
	public nonisolated let outbound: AsyncStream<[UInt8]>

	/// 餵一段已解碼的 UTF-8 + ANSI 位元組（``Sequence/serializeUTF8()`` 的輸出，見 `PTTBig5Codec`）。
	/// 可任意切割、跨呼叫的 escape／寬字元狀態由 SwiftTerm 內部 buffer 持有。
	public func feed(_ bytes: [UInt8]) {
		terminal.feed(byteArray: bytes)
		guard terminal.getUpdateRange() != nil else { return }
		terminal.clearUpdateRange()
		screenChangeContinuation.yield()
	}

	/// 建立一顆全新的 headless 終端（初始狀態：空白畫面、游標在 (0, 0)、可見）。
	public init() {
		let (screenStream, screenContinuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
		let (outboundStream, outboundContinuation) = AsyncStream<[UInt8]>.makeStream()
		self.screenDidChange = screenStream
		self.screenChangeContinuation = screenContinuation
		self.outbound = outboundStream
		let bridge: TerminalOutboundBridge = .init(outbound: outboundContinuation)
		self.bridge = bridge
		self.terminal = Terminal(delegate: bridge, options: .init(cols: Self.columns, rows: Self.rows))
	}

	// MARK: Private

	/// 底層 SwiftTerm 引擎（headless：不綁 `LocalProcess` 或任何 UI view，直接實例化 `Terminal` 本體）。
	private let terminal: Terminal

	/// delegate 橋接（見 ``TerminalOutboundBridge`` 型別註解說明為何不讓 actor 自己當 delegate）。
	private let bridge: TerminalOutboundBridge

	/// ``screenDidChange`` 的 continuation。
	private let screenChangeContinuation: AsyncStream<Void>.Continuation

	/// 把 SwiftTerm buffer 讀成不依賴渲染機制的 ``PTTScreen`` 快照。
	private func snapshot() -> PTTScreen {
		var rows: [[PTTCell]] = []
		rows.reserveCapacity(Self.rows)
		for row in 0 ..< Self.rows {
			var line: [PTTCell] = []
			line.reserveCapacity(Self.columns)
			for column in 0 ..< Self.columns {
				line.append(cell(column: column, row: row))
			}
			rows.append(line)
		}
		let location: (x: Int, y: Int) = terminal.getCursorLocation()
		let cursor: PTTCursor = .init(column: location.x, row: location.y, isVisible: bridge.isCursorVisible)
		return .init(rows: rows, cursor: cursor)
	}

	/// 讀單一格；寬字元延續格與正規化空白格（NUL → 半形空白）規則見 ``PTTCell`` 型別註解。
	///
	/// col/row 落在 ``columns`` / ``rows`` 範圍內時 `getCharData` 恆非 nil；下方 `blank` 只是
	/// 防禦性 fallback（理論上不可達），色值對齊 SwiftTerm `CharData.defaultAttr`
	/// （`fg: .defaultColor, bg: .defaultColor`，v1.13.0 原始碼核對，見 ``PTTTerminal`` 測試註解）。
	private func cell(column: Int, row: Int) -> PTTCell {
		let blank: PTTCell = .init(
			character: " ",
			width: 1,
			foregroundColor: .defaultColor,
			backgroundColor: .defaultColor,
			attributes: []
		)
		guard let charData = terminal.getCharData(col: column, row: row) else {
			return blank
		}
		guard charData.width > 0 else {
			return .init(
				character: " ",
				width: 0,
				foregroundColor: PTTColor(charData.attribute.fg),
				backgroundColor: PTTColor(charData.attribute.bg),
				attributes: PTTAttributes(charData.attribute.style)
			)
		}
		let rawCharacter: Character = terminal.getCharacter(col: column, row: row) ?? " "
		let character: Character = rawCharacter.unicodeScalars.first?.value == 0 ? " " : rawCharacter
		return .init(
			character: character,
			width: Int(charData.width),
			foregroundColor: PTTColor(charData.attribute.fg),
			backgroundColor: PTTColor(charData.attribute.bg),
			attributes: PTTAttributes(charData.attribute.style)
		)
	}
}
