//
//  PTTTerminal
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import SwiftTerm

// MARK: - PTTColor

/// 一個 cell 的前景／背景色來源分類。
///
/// 只描述色彩「怎麼表達」，不解析成實際 RGB——default 色的真正色值由下游渲染層
/// （App、pttcli 等）依自己的主題決定，見 ``PTTTerminal`` 的「rendering 層解耦」設計原則。
public enum PTTColor: Equatable, Sendable {

	/// 使用終端預設前景色。
	case defaultColor

	/// 使用終端預設反白色（inverse 模式常見；呼叫端依主題決定實際色值）。
	case defaultInvertedColor

	/// 16／256 色 ANSI 色票索引（0–15 為標準 16 色、16–255 為擴充 256 色）。
	case ansi256(UInt8)

	/// 24-bit true color。
	case trueColor(red: UInt8, green: UInt8, blue: UInt8)
}

extension PTTColor {

	/// 由 SwiftTerm `Attribute.Color` 轉換；``PTTTerminal`` 讀 cell attribute 時的唯一轉換點。
	init(_ color: Attribute.Color) {
		self = switch color {
		case .defaultColor:
			.defaultColor
		case .defaultInvertedColor:
			.defaultInvertedColor
		case let .ansi256(code):
			.ansi256(code)
		case let .trueColor(red, green, blue):
			.trueColor(red: red, green: green, blue: blue)
		}
	}
}
