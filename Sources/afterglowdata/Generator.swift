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

	/// b2u / u2b 文字表解析失敗（非 UTF-8、或行格式不符 `<big5> <unicode>`）。
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

/// UAO 對照表產生器進入點：取得 b2u／u2b 原始表 → 交給 ``DecodeTableGenerator`` /
/// ``EncodeTableGenerator`` 各自斷言與 pack → 交給 ``UAOTableRenderer`` 組檔 → 寫 `UAOTable.swift`。
///
/// 原始表不 vendored：優先讀本機 override 檔、否則自 MozTW 官方 repo 的
/// **commit-pinned** raw URL 下載；無論來源，SHA-256 不符即 hard-fail。
/// 兩個方向寫檔前皆以真實 runtime loader（``UAODecodeTable`` / ``UAOEncodeTable``）解回
/// packed bytes 做全表 round-trip 自驗。consumer build 永不連網、永不重生。
enum Generator {

	/// 套件根目錄：本檔在 `<root>/Sources/afterglowdata/Generator.swift`，往上三層。
	static let packageRoot = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	/// moztw/www.moztw.org 的固定 commit；升級表版本時更新此 pin 與兩個 SHA。
	static let sourcePin = "bbb049deaeeb256a4d781162f71665c2e244701e"

	/// b2u 原始表 SHA-256（drift / 截斷偵測；與來源無關、一律驗）。
	static let expectedB2USHA = "73e6457e39ca6d09efeaa32a7ad760d02f6fb35acd9ea0b2102114d584c37995"

	/// b2u 完整筆數（126 lead × 157 trail 滿格）；解析結果與 zone 加總不符即 hard-fail。
	static let expectedB2UCount = 19_782

	/// u2b 原始表 SHA-256（drift / 截斷偵測；與來源無關、一律驗）。
	static let expectedU2BSHA = "2edfd7b1d758cec2b7ba0d47cfca08ef8a70c14da8ae53bffa282e6c397299cf"

	/// u2b 完整筆數（含 `0xFFFD` 無對應哨兵列）；moztw 檔案原生行數。
	static let expectedU2BCount = 65_407

	/// u2b 中 `0xFFFD`（無對應）哨兵筆數：這部分不落 encode 表、查無即語意等價於 `nil`。
	static let expectedU2BSentinelCount = 39_491

	/// u2b 中「有對應」筆數＝ canonical（可逆）＋ best-fit（近似）；encode 表只收這部分。
	static let expectedEncodeCount = 25_916

	/// 有對應筆數中，可逆（canonical：經 b2u 回查等於原字）的筆數。
	static let expectedCanonicalCount = 19_316

	/// 有對應筆數中，不可逆（best-fit：近似替代，回查得到不同字或非合法 Big5 pointer）的筆數。
	static let expectedBestFitCount = 6600

	/// b2u 本機 override（存在就用、不下載；仍驗 SHA）。
	static var localB2UPath: String { packageRoot.appendingPathComponent("uao250-b2u.txt").path }

	/// u2b 本機 override（存在就用、不下載；仍驗 SHA）。
	static var localU2BPath: String { packageRoot.appendingPathComponent("uao250-u2b.txt").path }

	/// 產出檔路徑：寫入 PTTBig5Codec 的 Generated 目錄，consumer build 直接編譯、永不重生。
	static var outPath: String { packageRoot.appendingPathComponent("Sources/PTTBig5Codec/Generated/UAOTable.swift").path }

	/// MozTW 官方 repo 的 commit-pinned b2u raw URL；pin 固定使下載內容可與 SHA-256 對驗。
	static var sourceURL: URL {
		URL(
			string: "https://raw.githubusercontent.com/moztw/www.moztw.org/\(sourcePin)/docs/big5/table/uao250-b2u.txt"
		)!
	}

	/// MozTW 官方 repo 的 commit-pinned u2b raw URL；同一 pin、不同檔名。
	static var sourceURLU2B: URL {
		URL(
			string: "https://raw.githubusercontent.com/moztw/www.moztw.org/\(sourcePin)/docs/big5/table/uao250-u2b.txt"
		)!
	}

	/// 產生器主流程：b2u → decode 斷言與 pack、u2b → encode 斷言與 pack、兩者交給 renderer 組檔寫入。
	static func run() throws {
		let (data, origin) = try loadFile(localPath: localB2UPath, remoteURL: sourceURL)
		try verifySHA(data, expected: expectedB2USHA)
		guard let text = String(bytes: data, encoding: .utf8) else {
			throw GeneratorError.parse("b2u 原始表非 UTF-8")
		}
		let b2uRows = try parseTable(text, label: "b2u")
		try expect("b2uCount", b2uRows.count, expectedB2UCount)
		let b2uMap: [UInt16: UInt16] = .init(uniqueKeysWithValues: b2uRows.map { ($0.big5, $0.unicode) })
		let decoded = try DecodeTableGenerator.build(b2u: b2uMap)

		let (u2bData, u2bOrigin) = try loadFile(localPath: localU2BPath, remoteURL: sourceURLU2B)
		try verifySHA(u2bData, expected: expectedU2BSHA)
		guard let u2bText = String(bytes: u2bData, encoding: .utf8) else {
			throw GeneratorError.parse("u2b 原始表非 UTF-8")
		}
		let u2bRows = try parseTable(u2bText, label: "u2b")
		let encoded = try EncodeTableGenerator.build(u2b: u2bRows, b2u: b2uMap)

		// swiftformat:disable:next redundantType — render() 回傳 String，非 UAOTableRenderer 自身；
		// propertyTypes 規則會誤把 static factory 推成宿主型別（見 swift 守則已知坑）。
		let content: String = UAOTableRenderer.render(decoded: decoded, encoded: encoded)
		try content.write(toFile: outPath, atomically: true, encoding: .utf8)
		print("✅ 已寫入 \(outPath)")
		print("   b2u 來源：\(origin)（SHA-256 驗證通過）")
		print("   u2b 來源：\(u2bOrigin)（SHA-256 驗證通過）")
		let sizes = zip(DecodeTableGenerator.zones, decoded.packedZones)
			.map { "\($0.name) \($0.expectedCount) 筆/\($1.count)B" }
		print("   decode \(expectedB2UCount)（完整 b2u、六 zone varint）：\(sizes.joined(separator: "、"))")
		print(
			"   encode \(encoded.keys.count)（u2b canonical \(expectedCanonicalCount) + best-fit \(expectedBestFitCount)）：" +
				"keys \(encoded.packedKeys.count)B + values \(encoded.packedValues.count)B"
		)
		print("   滿格、全表 round-trip 與 spot-check 通過。")
	}

	/// 取得原始表 bytes 與來源描述：本機 override 存在即用（不下載）、否則自 pinned URL 下載；皆失敗即 throw。
	/// b2u／u2b 共用同一套「本機優先、否則下載」邏輯，差別只在路徑與 URL。
	static func loadFile(localPath: String, remoteURL: URL) throws -> (Data, String) {
		if FileManager.default.fileExists(atPath: localPath) {
			return try (Data(contentsOf: URL(fileURLWithPath: localPath)), "本機 override \(localPath)")
		}
		do {
			return try (Data(contentsOf: remoteURL), remoteURL.absoluteString)
		} catch {
			throw GeneratorError.sourceUnavailable(
				"無本機 override（\(localPath)）且下載失敗：\(error)。可手動下載後放至 override 路徑再重跑。"
			)
		}
	}

	/// 驗原始表 SHA-256 與期望值相符；與來源無關一律驗，防 drift 與截斷。
	static func verifySHA(_ data: Data, expected: String) throws {
		let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
		guard actual == expected else {
			throw GeneratorError.shaMismatch(expected: expected, actual: actual)
		}
	}

	/// 解析 b2u／u2b 共用的兩欄格式（CRLF）：`<big5-or-0xFFFD> <unicode>`。
	/// 保留檔案原序回傳（u2b 依 Unicode 遞增排列、encode 表的二分搜尋前提靠此序）。
	static func parseTable(_ text: String, label: String) throws -> [(big5: UInt16, unicode: UInt16)] {
		var rows: [(big5: UInt16, unicode: UInt16)] = []
		// 以 Character.isNewline 切行：CRLF 在 Swift 為單一 grapheme，split(separator: "\n") 切不開。
		for line in text.split(whereSeparator: { $0.isNewline }) {
			if line.hasPrefix("#") { continue }
			let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
			guard tokens.count == 2, let big5 = parseHex(tokens[0]), let uni = parseHex(tokens[1]) else {
				throw GeneratorError.parse("\(label) 行：\(line)")
			}
			rows.append((big5: big5, unicode: uni))
		}
		return rows
	}

	/// `0x` 前綴的十六進位 token → UInt16（Swift radix 解析不吃前綴、需先剝）。
	static func parseHex(_ token: Substring) -> UInt16? {
		var digits = token
		if digits.hasPrefix("0x") || digits.hasPrefix("0X") { digits = digits.dropFirst(2) }
		return UInt16(digits, radix: 16)
	}

	/// 將遞增 / 近乎遞增的 `UInt16` 序列 pack 成 base64 varint 串：首值 LEB128、後續 zigzag-LEB128 差分。
	/// decode 的六 zone value 陣列與 encode 的 key／value 陣列共用同一套 pack 邏輯
	/// （runtime 端對應的還原邏輯見 `PTTBig5Codec.VarintDeltaCodec`）。
	static func packVarint(_ values: [UInt16]) -> String {
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
}
