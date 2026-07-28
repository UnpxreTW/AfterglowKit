//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTKey

/// 送往站方的單一按鍵。
///
/// **編碼責任分工**：``text(_:)`` 只帶字面文字、不決定位元組——站方走 Big5-UAO，
/// 實際編碼由組裝層（façade）呼叫 `PTTBig5Codec` 完成；其餘按鍵是固定的 ASCII／
/// SS3 控制序列，直接由 ``controlBytes`` 給出。本模組因此不依賴 codec。
public enum PTTKey: Equatable, Sendable {

	/// 字面文字（帳號、板名、指令字母、數字…）。
	case text(String)

	/// Enter（CR，0x0D）。
	case enter

	/// Ctrl+L（0x0C）：逼站方重畫整個畫面。等畫面三件套之一，每串按鍵尾端自動補一顆。
	case formFeed

	/// Ctrl+C（0x03）：中斷進板動畫等佔用畫面的播放。
	case interrupt

	/// 方向鍵：上。
	case arrowUp

	/// 方向鍵：下。
	case arrowDown

	/// 方向鍵：左。
	case arrowLeft

	/// 方向鍵：右。
	case arrowRight

	/// 萬用 reset：空白鍵 + 左方向鍵 ×5，把任何畫面推回主功能表。
	///
	/// 左鍵在 PTT 是「離開目前層級」，連按五次足以從最深的選單層回到主功能表；
	/// 前置空白是為了先關掉可能佔用畫面的「請按任意鍵繼續」。
	public static let mainMenuReset: [PTTKey] = [
		.text(" "),
		.arrowLeft,
		.arrowLeft,
		.arrowLeft,
		.arrowLeft,
		.arrowLeft
	]

	/// 固定控制序列的位元組；``text(_:)`` 回 `nil`（字面文字須由組裝層依 Big5-UAO 編碼）。
	///
	/// 方向鍵取 SS3 形式（`ESC O A`…）而非 CSI（`ESC [ A`）——站方 io.c 的慣例即此，
	/// 連線層 keepalive 送的 `ESC OA ESC OB` 也是同一組編碼。
	public var controlBytes: [UInt8]? {
		switch self {
		case .text: nil
		case .enter: [0x0D]
		case .formFeed: [0x0C]
		case .interrupt: [0x03]
		case .arrowUp: [0x1B, 0x4F, 0x41]
		case .arrowDown: [0x1B, 0x4F, 0x42]
		case .arrowRight: [0x1B, 0x4F, 0x43]
		case .arrowLeft: [0x1B, 0x4F, 0x44]
		}
	}
}
