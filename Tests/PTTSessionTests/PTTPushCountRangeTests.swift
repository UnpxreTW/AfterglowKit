//
//  PTTSessionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTSession
import Testing

/// ``PTTPushCount/range`` 驗證：級距邊界、夾擠上下限、沒有區間的那幾格，以及值域全覆蓋。
///
/// 這一組釘的是**原本只寫在註解裡的語義**——尤其「噓文十位數 1 的起點是 11 不是 10」。
/// 註解沒有鑑別力：寫錯了沒有人會紅，搬到型別上才有。
private final class PTTPushCountRangeTests {

	/// 站方印得出數字的每一格（`爆`／`XX` 也算——它們說的是欄位撞到夾擠上下限）。
	private static let numericCases: [PTTPushCount] =
		[.none, .exploded, .heavilyBooed]
			+ (1 ... PTTPushCount.maximumNetCount - 1).map { PTTPushCount.pushes($0) }
			+ (1 ... 9).map { PTTPushCount.booed(tensDigit: $0) }

	/// 留白那一格是推噓相抵後的 `-10 ... 0`，不是「沒有推文」。
	@Test
	private func `a blank column spans the net values the station does not print`() {
		#expect(PTTPushCount.none.range == -10 ... 0)
	}

	/// 推文數那一格印的就是確切淨值，區間退化成單一值。
	@Test
	private func `a printed push count is a single net value`() {
		#expect(PTTPushCount.pushes(1).range == 1 ... 1)
		#expect(PTTPushCount.pushes(42).range == 42 ... 42)
		#expect(PTTPushCount.pushes(99).range == 99 ... 99)
	}

	/// 噓文十位數 1 的起點是 `-11`、不是 `-10`。
	///
	/// !!!: 這一則就是本屬性存在的理由。站方走 `X%d` 那條分支的條件是淨值**小於** `-10`
	/// （`mbbsd/bbs.c` 的 `else if(ent->recommend<-10)`），剛好 `-10` 會落回留白那一格；
	/// 照十位數直覺寫成 `-19 ... -10` 就會與留白那一格重疊，而重疊在畫面上看不出來。
	@Test
	private func `the first booed decade starts at eleven not ten`() {
		#expect(PTTPushCount.booed(tensDigit: 1).range == -19 ... -11)
	}

	/// 其餘十位數是完整的十位級距（負值、由絕對值換算）。
	@Test
	private func `the remaining booed decades span a full ten`() {
		#expect(PTTPushCount.booed(tensDigit: 2).range == -29 ... -20)
		#expect(PTTPushCount.booed(tensDigit: 9).range == -99 ... -90)
	}

	/// `爆` 與 `XX` 是欄位被夾在上下限上，兩端都是閉的、不是開端的「以上／以下」。
	@Test
	private func `the saturated columns pin the clamped bounds`() {
		#expect(PTTPushCount.exploded.range == 100 ... 100)
		#expect(PTTPushCount.heavilyBooed.range == -100 ... -100)
		#expect(PTTPushCount.maximumNetCount == 100)
	}

	/// 站方沒印數字的那兩格沒有區間。
	@Test
	private func `columns without a number have no range`() {
		#expect(PTTPushCount.locked.range == nil)
		#expect(PTTPushCount.unrecognised("??").range == nil)
	}

	/// 帶值落在站方印得出來的範圍之外時回 `nil`，不憑公式硬算一個區間出來。
	///
	/// 這幾個值判讀端產不出來，但本型別的 case 是公開的、呼叫端建得出來。
	@Test
	private func `payloads the station cannot print have no range`() {
		#expect(PTTPushCount.pushes(0).range == nil)
		#expect(PTTPushCount.pushes(-3).range == nil)
		#expect(PTTPushCount.pushes(100).range == nil)
		#expect(PTTPushCount.booed(tensDigit: 0).range == nil)
		#expect(PTTPushCount.booed(tensDigit: 10).range == nil)
	}

	/// 站方值域 `-100 ... 100` 的每一個值都恰好被一格涵蓋一次——不重疊、也不留洞。
	///
	/// !!!: 這一則抓的是逐格斷言抓不到的東西。級距邊界寫錯時，多半不是某一格自己看起來不對，
	/// 而是它與鄰居重疊或中間空一格；分開看每一格都合理，合起來才露餯。
	@Test
	private func `every net value the field can hold is covered exactly once`() {
		let ranges: [ClosedRange<Int>] = Self.numericCases.compactMap(\.range)
		#expect(ranges.count == Self.numericCases.count)
		for value in -PTTPushCount.maximumNetCount ... PTTPushCount.maximumNetCount {
			let hits: Int = ranges.count { $0.contains(value) }
			#expect(hits == 1, "淨值 \(value) 被涵蓋 \(hits) 次")
		}
	}
}
