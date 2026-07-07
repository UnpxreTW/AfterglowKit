//
//  PTTBig5Codec
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTByte

/// 串流轉碼器吐出的結構化 token：把 raw byte stream 拆成語義單元，
/// 讓 escape 重排 / 雙色字 / fallback 對齊等規則在 token 層斷言乾淨，
/// 也為未來的 typed event stream 介面預留。最終餵 SwiftTerm 走 ``serializeUTF8()``。
///
/// 四 case 對應轉碼輸出的四類單元：字面 byte、Big5-UAO 字、escape 序列、解碼失敗 byte。
public enum PTTByte: Equatable, Sendable {

	/// 單一字面 byte。bbs（Big5）模式下為 ASCII（0x00–0x7F）控制 / 可見字；
	/// bbsu UTF-8 passthrough 模式下亦承載原樣 UTF-8 byte（含 ≥0x80）逐 byte 直通，
	/// 由下游 SwiftTerm 重組——passthrough 不在轉碼器內解析 scalar。
	case ascii(UInt8)

	/// 配對成功的雙位元組 Big5-UAO 字（已查表解成 Unicode）。
	case big5Char(Character)

	/// 完整的 ANSI escape sequence（原樣 byte，含 ESC）。
	case escape([UInt8])

	/// 解碼失敗的 byte。``serializeUTF8()`` 補半形 `'?'` 保欄位對齊（非 U+FFFD），
	/// 一個失敗的雙位元組 pair → 兩個 ``invalid`` → 兩個 `'?'` → 兩欄。
	case invalid(UInt8)
}

extension Sequence<PTTByte> {

	/// 把 token 流 flatten 成 UTF-8 + ANSI byte 序列，餵 `SwiftTerm.feed(byteArray:)`（外部解碼後餵 UTF-8）。
	public func serializeUTF8() -> [UInt8] {
		var out: [UInt8] = []
		for token in self {
			switch token {
			case let .ascii(byte):
				out.append(byte)
			case let .big5Char(character):
				out.append(contentsOf: character.utf8)
			case let .escape(bytes):
				out.append(contentsOf: bytes)
			case .invalid:
				out.append(0x3F) // '?'：每半形補一個、保欄位對齊
			}
		}
		return out
	}
}
