//
//  afterglowdata
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import PTTBig5Codec

// MARK: - GeneratorError

/// 產生器錯誤；任一即 hard-fail、不寫檔。
enum GeneratorError: Error, CustomStringConvertible {

	/// 原始表取得失敗：無本機 override 且 pinned URL 下載失敗；附細節與手動救援指引。
	case sourceUnavailable(String)

	/// 原始表 SHA-256 與 pin 不符：疑上游 drift 或下載截斷，一律 hard-fail 不寫檔。
	case shaMismatch(expected: String, actual: String)

	/// b2u 文字表解析失敗（非 UTF-8、或行格式不符 `<big5> <unicode>`）。
	case parse(String)

	/// 筆數斷言失敗：指明欄位與期望／實際筆數（滿格前提被打破的訊號）。
	case countMismatch(field: String, expected: Int, actual: Int)

	/// 寫檔前自驗失敗：滿格、全表 round-trip、spot-check／canary 任一道閘不過。
	case validation(String)

	/// 人讀錯誤描述（繁中）；產生器 CLI 直接印出供除錯定位。
	var description: String {
		switch self {
		case let .sourceUnavailable(detail):
			"原始表取得失敗：\(detail)"
		case let .shaMismatch(expected, actual):
			"SHA-256 不符：expected \(expected)、actual \(actual)（原始表 drift / 截斷）"
		case let .parse(detail):
			"解析失敗：\(detail)"
		case let .countMismatch(field, expected, actual):
			"count 不符 \(field)：expected \(expected)、actual \(actual)"
		case let .validation(detail):
			"驗證失敗：\(detail)"
		}
	}
}

// MARK: - Generator

/// UAO 解碼表產生器：取得 b2u 原始表 → 滿格斷言 → 分 zone varint pack → 寫 `UAOTable.swift`。
///
/// 原始表不 vendored：優先讀本機 override 檔、否則自 MozTW 官方 repo 的
/// **commit-pinned** raw URL 下載；無論來源，SHA-256 不符即 hard-fail。
/// 寫檔前以「滿格 × 全表 round-trip × spot-check」三道閘自驗（透過真實
/// ``UAODecodeTable`` loader 解回即將寫入的 bytes）。consumer build 永不連網、永不重生。
enum Generator {

	/// 六個 zone：lead 範圍 + 內容描述；滿格前提下筆數 = lead 數 × 157。
	struct Zone {

		/// 滿格前提下本 zone 筆數：lead 數 × 每 lead 157 trail。
		var expectedCount: Int { (Int(leadHigh) - Int(leadLow) + 1) * UAODecodeTable.trailsPerLead }

		/// zone 常數識別字，原樣寫入產生檔作 StaticString 名稱。
		let name: String

		/// zone 起始 lead byte（含）。
		let leadLow: UInt8

		/// zone 結束 lead byte（含）。
		let leadHigh: UInt8

		/// 寫入產生檔的區段中文說明（描述該 lead 範圍收錄的內容）。
		let comment: String
	}

	/// 套件根目錄：本檔在 `<root>/Sources/afterglowdata/Generator.swift`，往上三層。
	static let packageRoot = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	/// moztw/www.moztw.org 的固定 commit；升級表版本時更新此 pin 與 SHA。
	static let sourcePin = "bbb049deaeeb256a4d781162f71665c2e244701e"

	/// b2u 原始表 SHA-256（drift / 截斷偵測；與來源無關、一律驗）。
	static let expectedB2USHA = "73e6457e39ca6d09efeaa32a7ad760d02f6fb35acd9ea0b2102114d584c37995"

	/// b2u 完整筆數（126 lead × 157 trail 滿格）；解析結果與 zone 加總不符即 hard-fail。
	static let expectedB2UCount = 19_782

	/// 六個 zone 的 lead 分區定義；依 lead 遞增排列、串接即涵蓋完整 Big5 pointer 空間。
	static let zones: [Zone] = [
		Zone(
			name: "zoneUserDefined",
			leadLow: 0x81,
			leadHigh: 0xA0,
			comment: "UAO 使用者定義區（標準 Big5 未收的罕用漢字為主、近乎 Unicode 遞增）"
		),
		Zone(
			name: "zoneSymbols",
			leadLow: 0xA1,
			leadHigh: 0xA3,
			comment: "標準 Big5 符號區"
		),
		Zone(
			name: "zoneHanziL1",
			leadLow: 0xA4,
			leadHigh: 0xC6,
			comment: "標準 Big5 常用字 Level 1"
		),
		Zone(
			name: "zoneKanaCyrillic",
			leadLow: 0xC7,
			leadHigh: 0xC8,
			comment: "倚天／UAO 假名・西里爾區"
		),
		Zone(
			name: "zoneHanziL2",
			leadLow: 0xC9,
			leadHigh: 0xF9,
			comment: "標準 Big5 次常用字 Level 2"
		),
		Zone(
			name: "zoneExtension",
			leadLow: 0xFA,
			leadHigh: 0xFE,
			comment: "UAO 延伸區（倚天線繪等）"
		)
	]

	/// pointer 次序的合法 trail 序列：0x40–0x7E、再 0xA1–0xFE。
	static let trailSequence: [UInt8] = Array(0x40 ... 0x7E) + Array(0xA1 ... 0xFE)

	/// 本機 override（存在就用、不下載；仍驗 SHA）。
	static var localB2UPath: String { packageRoot.appendingPathComponent("uao250-b2u.txt").path }

	/// 產出檔路徑：寫入 PTTBig5Codec 的 Generated 目錄，consumer build 直接編譯、永不重生。
	static var outPath: String { packageRoot.appendingPathComponent("Sources/PTTBig5Codec/Generated/UAOTable.swift").path }

	/// MozTW 官方 repo 的 commit-pinned raw URL；pin 固定使下載內容可與 SHA-256 對驗。
	static var sourceURL: URL {
		URL(
			string: "https://raw.githubusercontent.com/moztw/www.moztw.org/\(sourcePin)/docs/big5/table/uao250-b2u.txt"
		)!
	}

	/// 產生器主流程：載入來源 → 驗 SHA → 解析 → 滿格展開 → varint pack → 自驗 → 寫 `UAOTable.swift`。
	static func run() throws {
		let (data, origin) = try loadSource()
		try verifySHA(data)
		guard let text = String(bytes: data, encoding: .utf8) else {
			throw GeneratorError.parse("b2u 原始表非 UTF-8")
		}
		let b2u = try parseB2U(text)
		try expect("b2uCount", b2u.count, expectedB2UCount)
		// 滿格斷言 + 依 pointer 序展開各 zone 的 value 序列。
		let zoneValues = try denseZoneValues(b2u: b2u)
		let packed = zoneValues.map { encodeVarintZone($0) }
		try validate(packedZones: packed, b2u: b2u)
		let content = render(packedZones: packed)
		try content.write(toFile: outPath, atomically: true, encoding: .utf8)
		print("✅ 已寫入 \(outPath)")
		print("   來源：\(origin)（SHA-256 驗證通過）")
		let sizes = zip(zones, packed).map { "\($0.name) \($0.expectedCount) 筆/\($1.count)B" }
		print("   decode \(expectedB2UCount)（完整 b2u、六 zone varint）：\(sizes.joined(separator: "、"))")
		print("   滿格、全表 round-trip 與 spot-check 通過。")
	}

	/// 取得原始表 bytes 與來源描述：本機 override 存在即用（不下載）、否則自 pinned URL 下載；皆失敗即 throw。
	static func loadSource() throws -> (Data, String) {
		if FileManager.default.fileExists(atPath: localB2UPath) {
			return try (Data(contentsOf: URL(fileURLWithPath: localB2UPath)), "本機 override \(localB2UPath)")
		}
		do {
			return try (Data(contentsOf: sourceURL), sourceURL.absoluteString)
		} catch {
			throw GeneratorError.sourceUnavailable(
				"無本機 override（\(localB2UPath)）且下載失敗：\(error)。可手動下載後放至 override 路徑再重跑。"
			)
		}
	}

	/// 驗原始表 SHA-256 與 ``expectedB2USHA`` 相符；與來源無關一律驗，防 drift 與截斷。
	static func verifySHA(_ data: Data) throws {
		let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
		guard actual == expectedB2USHA else {
			throw GeneratorError.shaMismatch(expected: expectedB2USHA, actual: actual)
		}
	}

	/// 解析 b2u（CRLF）：`b2u[big5] = unicode`。
	static func parseB2U(_ text: String) throws -> [UInt16: UInt16] {
		var map: [UInt16: UInt16] = .init(minimumCapacity: 20_000)
		// 以 Character.isNewline 切行：CRLF 在 Swift 為單一 grapheme，split(separator: "\n") 切不開。
		for line in text.split(whereSeparator: { $0.isNewline }) {
			if line.hasPrefix("#") { continue }
			let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
			guard tokens.count == 2, let big5 = parseHex(tokens[0]), let uni = parseHex(tokens[1]) else {
				throw GeneratorError.parse("b2u 行：\(line)")
			}
			map[big5] = uni
		}
		return map
	}

	/// `0x` 前綴的十六進位 token → UInt16（Swift radix 解析不吃前綴、需先剝）。
	static func parseHex(_ token: Substring) -> UInt16? {
		var digits = token
		if digits.hasPrefix("0x") || digits.hasPrefix("0X") { digits = digits.dropFirst(2) }
		return UInt16(digits, radix: 16)
	}

	/// value-only 密集表示的前提：126 lead × 157 trail 滿格。任一格缺 → hard-fail
	/// （上游若出洞，此表示法不再成立、需回退 (key, value) pair 方案）。
	static func denseZoneValues(b2u: [UInt16: UInt16]) throws -> [[UInt16]] {
		var result: [[UInt16]] = []
		for zone in zones {
			var values: [UInt16] = []
			values.reserveCapacity(zone.expectedCount)
			for lead in zone.leadLow ... zone.leadHigh {
				for trail in trailSequence {
					let key = (UInt16(lead) << 8) | UInt16(trail)
					guard let uni = b2u[key] else {
						throw GeneratorError.validation("滿格斷言失敗：\(hex(key)) 無對應（value-only 密集表示前提不成立）")
					}
					guard uni != 0 else {
						throw GeneratorError.validation("\(hex(key)) 對應 U+0000（非法 value）")
					}
					values.append(uni)
				}
			}
			try expect("\(zone.name) 筆數", values.count, zone.expectedCount)
			result.append(values)
		}
		return result
	}

	/// 將 zone 的 value 序列 pack 成 base64 varint 串：首值 LEB128、後續 zigzag-LEB128 差分（近乎遞增的表可大幅縮小）。
	static func encodeVarintZone(_ values: [UInt16]) -> String {
		var bytes: [UInt8] = []
		bytes.reserveCapacity(values.count * 2)
		var previous: Int32 = 0
		var isFirst = true
		for value in values {
			let current: Int32 = .init(value)
			let raw: UInt32
			if isFirst {
				raw = UInt32(bitPattern: current)
				isFirst = false
			} else {
				let delta = current &- previous
				raw = UInt32(bitPattern: (delta << 1) ^ (delta >> 31)) // zigzag
			}
			var remaining = raw
			while remaining >= 0x80 {
				bytes.append(UInt8(remaining & 0x7F) | 0x80)
				remaining >>= 7
			}
			bytes.append(UInt8(remaining))
			previous = current
		}
		return Data(bytes).base64EncodedString()
	}

	/// 寫檔前自驗：以真實 ``UAODecodeTable`` loader 解回 packed bytes、全表 19,782 筆 round-trip、
	/// spot-check 含 canary 與非法 key 檢查。
	static func validate(packedZones: [String], b2u: [UInt16: UInt16]) throws {
		guard let table = UAODecodeTable(base64Zones: packedZones, expectedCount: expectedB2UCount) else {
			throw GeneratorError.validation("zone blob 無法 round-trip 解析")
		}
		// 全表 round-trip：19,782 筆逐一比對（涵蓋滿格、排序、varint 正確性）。
		for (key, expected) in b2u {
			guard table.lookup(key) == expected else {
				let gotText = table.lookup(key).map { hex($0) } ?? "nil"
				throw GeneratorError.validation("round-trip \(hex(key))：\(gotText) ≠ \(hex(expected))")
			}
		}
		// spot-check（含 canary：0xC6E7 誤觸 ゃ ＝ 載到舊/錯表）。
		try checkLookup(table, 0xC6E7, 0x3041, "ぁ U+3041")
		if table.lookup(0xC6E7) == 0x3083 {
			throw GeneratorError.validation("canary：0xC6E7 解出 ゃ(U+3083)、應為 ぁ(U+3041) — 載到舊/錯表")
		}
		try checkLookup(table, 0xF9FA, 0x256D, "╭ U+256D")
		try checkLookup(table, 0xF9DE, 0x2566, "╦ U+2566")
		try checkLookup(table, 0xA140, 0x3000, "全形空格 U+3000")
		try checkLookup(table, 0xB35C, 0x8A31, "許 U+8A31")
		// 非法 key 必回 nil。
		for bad: UInt16 in [0x0041, 0x8039, 0xA17F, 0xFF40] where table.lookup(bad) != nil {
			throw GeneratorError.validation("非法 key \(hex(bad)) 應回 nil")
		}
	}

	/// spot-check 單筆：lookup 結果須等於期望 Unicode，否則 throw `.validation`。
	static func checkLookup(_ table: UAODecodeTable, _ key: UInt16, _ expected: UInt16, _ name: String) throws {
		let got = table.lookup(key)
		guard got == expected else {
			let gotText = got.map { hex($0) } ?? "nil"
			throw GeneratorError.validation("spot-check \(name)：lookup(\(hex(key))) = \(gotText)、應為 \(hex(expected))")
		}
	}

	/// 筆數斷言：actual ≠ expected 即 throw `.countMismatch`（滿格與解析完整性的統一檢查點）。
	static func expect(_ field: String, _ actual: Int, _ expected: Int) throws {
		guard actual == expected else {
			throw GeneratorError.countMismatch(field: field, expected: expected, actual: actual)
		}
	}

	/// UInt16 → `0xXXXX` 大寫十六進位字串（錯誤訊息呈現用）。
	static func hex(_ value: UInt16) -> String {
		"0x" + String(format: "%04X", value)
	}

	/// 組出 `UAOTable.swift` 全文：檔頭、來源與表示法註記、六 zone StaticString 常數、zones 聚合 property。
	static func render(packedZones: [String]) -> String {
		var constants = ""
		for (zone, packed) in zip(zones, packedZones) {
			let low: String = .init(zone.leadLow, radix: 16, uppercase: true)
			let high: String = .init(zone.leadHigh, radix: 16, uppercase: true)
			constants += """

				\t/// lead 0x\(low)–0x\(high)、\(zone.expectedCount) 筆——\(zone.comment)。
				\tstatic let \(zone.name): StaticString = "\(packed)"

				"""
		}
		return """
			//
			//  PTTBig5Codec
			//
			//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
			//  Licensed under the Apache License 2.0. See LICENSE for details.
			//
			//  SPDX-License-Identifier: Apache-2.0

			//  GENERATED BY `swift run afterglowdata generate` — DO NOT EDIT.
			//  來源：uao250 b2u（完整 \(expectedB2UCount) 筆、126 lead × 157 trail 滿格）、
			//  取自 moztw/www.moztw.org@\(sourcePin.prefix(12))、SHA-256 驗證見產生器常數。
			//  表示法：value-only 密集陣列、分六 zone 之 base64 varint 串
			//  （首值 LEB128、後續 zigzag-LEB128 差分；key 由 Big5 pointer 公式推導、不儲存）。

			// swiftformat:disable all
			// 原因：本檔為產生器機械產出，格式規則對其無指引意義。

			enum UAOTable {

			\t/// 表來源識別（uao250 ＝ UAO 2.50）。
			\tstatic let source = "uao250"

			\t/// 解碼表總筆數（126 lead × 157 trail 滿格）。
			\tstatic let decodeCount = \(expectedB2UCount)

			\t// swiftlint:disable line_length
			\t// 原因：blob 行長由資料量決定。
			\(constants)
			\t// swiftlint:enable line_length

			\t/// 依 lead 序串接＝完整 pointer 空間（餵 ``UAODecodeTable``）。
			\tstatic var zones: [StaticString] {
			\t\t[zoneUserDefined, zoneSymbols, zoneHanziL1, zoneKanaCyrillic, zoneHanziL2, zoneExtension]
			\t}
			}

			"""
	}
}
