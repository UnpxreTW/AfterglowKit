//
//  PTTTerminal
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import SwiftTerm

// MARK: - PTTAttributes

/// 一個 cell 的文字樣式旗標。
public struct PTTAttributes: OptionSet, Equatable, Sendable {

	/// 粗體。
	public static let bold: PTTAttributes = .init(rawValue: 1 << 0)

	/// 底線。
	public static let underline: PTTAttributes = .init(rawValue: 1 << 1)

	/// 閃爍。
	public static let blink: PTTAttributes = .init(rawValue: 1 << 2)

	/// 前景／背景反白。
	public static let inverse: PTTAttributes = .init(rawValue: 1 << 3)

	/// 不可見（畫面應留白；複製／貼上行為由呼叫端決定）。
	public static let invisible: PTTAttributes = .init(rawValue: 1 << 4)

	/// 淡化（較低對比）。
	public static let dim: PTTAttributes = .init(rawValue: 1 << 5)

	/// 斜體。
	public static let italic: PTTAttributes = .init(rawValue: 1 << 6)

	/// 加刪除線。
	public static let crossedOut: PTTAttributes = .init(rawValue: 1 << 7)

	/// 底層 bit 表示；不與 SwiftTerm `CharacterStyle` 共用編碼，逐項轉換見下方 `init(_:)`，
	/// 避免上游 bit layout 未來變動時本型別靜默錯位。
	public let rawValue: UInt8

	/// 由 raw bit 值建構。
	public init(rawValue: UInt8) {
		self.rawValue = rawValue
	}
}

extension PTTAttributes {

	/// 由 SwiftTerm `CharacterStyle` 逐項轉換；``PTTTerminal`` 讀 cell attribute 時的唯一轉換點。
	init(_ style: CharacterStyle) {
		var result: PTTAttributes = []
		if style.contains(.bold) { result.insert(.bold) }
		if style.contains(.underline) { result.insert(.underline) }
		if style.contains(.blink) { result.insert(.blink) }
		if style.contains(.inverse) { result.insert(.inverse) }
		if style.contains(.invisible) { result.insert(.invisible) }
		if style.contains(.dim) { result.insert(.dim) }
		if style.contains(.italic) { result.insert(.italic) }
		if style.contains(.crossedOut) { result.insert(.crossedOut) }
		self = result
	}
}
