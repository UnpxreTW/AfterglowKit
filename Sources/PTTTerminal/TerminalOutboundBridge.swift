//
//  PTTTerminal
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import SwiftTerm

// MARK: - TerminalOutboundBridge

/// `TerminalDelegate` 橋接：把 SwiftTerm 的同步 callback 轉成 continuation yield，
/// 不碰 actor-isolated 狀態——避免 ``PTTTerminal`` 初始化中 `self` 逃逸（actor init 內把
/// 尚未完成初始化的 self 交給會保存 weak 參照的第三方 API 不合法）；callback 只會落在
/// ``PTTTerminal/feed(_:)`` 內 `terminal.feed` 的同步呼叫鏈中，天生序列化、不需額外同步保護。
///
/// `send(source:data:)` 是 `TerminalDelegate` 協定內唯一沒有預設空實作的方法（v1.13.0 原始碼核對）——
/// 代表這條路徑一定會被使用（host 端的 DSR／CPR 這類自動查詢會觸發）；其餘方法沿用預設空實作，
/// 因為本引擎是 headless，不需要標題列／選取狀態／視窗操作這類 UI 專屬回呼。
final class TerminalOutboundBridge: TerminalDelegate {

	/// 建立橋接。
	init(outbound: AsyncStream<[UInt8]>.Continuation) {
		self.outbound = outbound
	}

	/// 目前游標是否可見（``showCursor(source:)``／``hideCursor(source:)`` 回呼維護；預設可見）。
	private(set) var isCursorVisible = true

	/// SwiftTerm 要求把資料送回 host（本協定唯一沒有預設實作的方法）。
	func send(source: Terminal, data: ArraySlice<UInt8>) {
		outbound.yield(Array(data))
	}

	/// host 端送出「顯示游標」指令（`ESC[?25h`）。
	func showCursor(source: Terminal) {
		isCursorVisible = true
	}

	/// host 端送出「隱藏游標」指令（`ESC[?25l`）。
	func hideCursor(source: Terminal) {
		isCursorVisible = false
	}

	/// host 端查詢觸發的回覆位元組（DSR／CPR 等）；``PTTTerminal/outbound`` 直接轉發本 stream。
	private let outbound: AsyncStream<[UInt8]>.Continuation

}
