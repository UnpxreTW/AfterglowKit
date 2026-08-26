//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTPushCount

/// 文章清單列上的推文數欄位。
///
/// **這一欄只有兩格寬，站方本來就印不下完整數字**——所以這裡是「站方顯示了什麼」的
/// 忠實模型，不是「這篇有幾則推文」的精確值。要精確值得進文章內文數，不在清單畫面上。
/// 各分支照站方原始碼 `readdoent()` 組 `recom` 字串的那一段移植
/// （來源 https://github.com/ptt/pttbbs 的 `mbbsd/bbs.c`）。
public enum PTTPushCount: Equatable, Sendable {

// MARK: Public

	/// 空白：推文數在 -10 ～ 0 之間，站方不顯示。
	///
	/// !!!: 空白**不等於**沒有推文——小額噓文也落在這一格。想區分只能進文章內文。
	case none

	/// 1 ～ 99 則推文（站方以兩位數右對齊印出）。
	case pushes(Int)

	/// 爆：淨值已達站方上限。
	///
	/// 上限是欄位本身的夾擠值（見 ``maximumNetCount``），不是「剛好一百則」——超出的
	/// 部分在站方寫檔那一刻就被夾掉了，畫面上還原不出實際推了幾則。
	case exploded

	/// 噓文 11 則以上：站方只印得下十位數（`X1` = 11 ～ 19、`X9` = 90 ～ 99）。
	///
	/// 起點是 11 不是 10——站方走這條分支的條件是噓文數**大於** 10，剛好 10 則會落回空白欄。
	///
	/// 站方組字串時用 `X%d` 帶完整數字、再被欄寬截成兩格，所以個位數在畫面上就已經丟了；
	/// 這裡只還原到十位級距，不假裝知道確切數字。
	case booed(tensDigit: Int)

	/// `XX`：淨值已達站方下限（``maximumNetCount`` 的負值，同 ``exploded`` 的夾擠理由）。
	case heavilyBooed

	/// `--`：文章被鎖，站方不顯示推文數。
	case locked

	/// 未知樣式：站方版本差異或畫面殘影。原文照留，供呼叫端自行判斷或回報。
	case unrecognised(String)

	/// 站方推文數欄位的絕對值上限（`include/common.h` 的 `MAX_RECOMMENDS`，值為 100）。
	///
	/// 站方把推文淨值存在 `fileheader_t` 的一個 `char recommend` 裡（`include/pttstruct.h`），
	/// 每次寫檔都夾在 `±MAX_RECOMMENDS` 之間（`mbbsd/bbs.c` 的 `modify_dir_lite()`），
	/// 所以這個常數同時是欄位的值域邊界——``exploded`` 與 ``heavilyBooed`` 就是撞到這兩端。
	public static let maximumNetCount: Int = 100

	/// 這一格對應的站方淨值區間；畫面給不出數字時為 `nil`。
	///
	/// **軸是站方的淨值、不是「推了幾則」**：站方只存一個 `recommend` 欄位，推 +1、噓 -1，
	/// 清單畫面那兩格是它的顯示形。所以 ``booed(tensDigit:)`` 給的是**負值**區間，
	/// 而 ``none`` 涵蓋 `-10 ... 0`——推噓相抵之後落在這一段的文章，站方一律留白。
	///
	/// 兩端都是閉的：``exploded`` 與 ``heavilyBooed`` 不是開放端的「100 以上／以下」，
	/// 而是欄位被夾在上下限上（見 ``maximumNetCount``）。
	///
	/// !!!: 有區間**不等於**知道確切數字。``none`` 與 ``booed(tensDigit:)`` 天生只給得起
	/// 一個級距，站方在畫面上就沒印出那些位數（見各自的說明）。
	///
	/// `nil` 一律是同一個意思——「這一格沒有可還原的數字區間」：``locked``（站方印 `--`、
	/// 不顯示）、``unrecognised(_:)``（樣式認不得），以及帶值落在站方印得出來的範圍之外的
	/// ``pushes(_:)`` 與 ``booed(tensDigit:)``（本型別的 case 呼叫端也建得出來，建出了
	/// 站方印不出來的值就不假裝算得出區間）。
	///
	/// 各分支照站方原始碼 `readdoent()` 組 `recom` 字串的那一段移植
	/// （來源 https://github.com/ptt/pttbbs 的 `mbbsd/bbs.c`）。
	public var range: ClosedRange<Int>? {
		switch self {
		case .none: -Self.blankUpperMagnitude ... 0
		case let .pushes(count): Self.singleValue(count)
		case .exploded: Self.maximumNetCount ... Self.maximumNetCount
		case let .booed(tensDigit): Self.booed(tensDigit: tensDigit)
		case .heavilyBooed: -Self.maximumNetCount ... -Self.maximumNetCount
		case .locked, .unrecognised: nil
		}
	}

// MARK: Private

	/// 留白那一格涵蓋到的噓文淨值絕對值（站方走留白分支的條件是淨值**不小於** `-10`）。
	private static let blankUpperMagnitude: Int = 10

	/// ``pushes(_:)`` 的區間：站方印得出來才給。
	///
	/// 下界 1、上界 ``maximumNetCount`` 減一——淨值到達上限時站方改印「爆」、走不到這一格。
	private static func singleValue(_ count: Int) -> ClosedRange<Int>? {
		guard (1 ... maximumNetCount - 1).contains(count) else { return nil }
		return count ... count
	}

	/// ``booed(tensDigit:)`` 的區間。
	///
	/// !!!: 十位數 1 那一格是 `-19 ... -11`、**不是** `-19 ... -10`。站方走這條分支的條件是
	/// 淨值**小於** `-10`（`mbbsd/bbs.c` 的 `else if(ent->recommend<-10)`），剛好 `-10`
	/// 會落回留白那一格。這一格的起點正是本屬性存在的理由：它原本只寫在註解裡。
	///
	/// 十位數 0 站方印不出來（它印的是絕對值 11 ～ 99 的第一位），落在 1 ～ 9 之外一律回 `nil`。
	private static func booed(tensDigit: Int) -> ClosedRange<Int>? {
		guard (1 ... 9).contains(tensDigit) else { return nil }
		let upperMagnitude: Int = tensDigit * 10 + 9
		let lowerMagnitude: Int = tensDigit == 1 ? blankUpperMagnitude + 1 : tensDigit * 10
		return -upperMagnitude ... -lowerMagnitude
	}
}
