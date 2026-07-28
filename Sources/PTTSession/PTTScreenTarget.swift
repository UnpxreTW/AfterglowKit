//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTScreenTarget

/// 一張「目標畫面」的宣告式描述：要在畫面上看到哪些字串、看到之後怎麼辦。
///
/// **為什麼保留這張宣告式表**：站方沒有「重繪完成」訊號，唯一可靠的判斷方式就是
/// 「畫面上出現了哪些字」。把它寫成資料而非散落的 if，讓等畫面這件事只有一個實作、
/// 斷言與除錯都對著同一張表。至於高階操作（登入、進板、取最新編號）則用 async
/// 函數組合表達，不再整包資料化——Swift 有結構化並行與取消，不需要用全表驅動去補償。
public struct PTTScreenTarget: Equatable, Sendable {

	// MARK: Public

	/// 命中之後的處置。
	public enum Outcome: Equatable, Sendable {

		/// 這就是要等的畫面，等待結束。
		case arrived

		/// 自動應答後繼續等（空陣列 = 只補一顆重繪鍵、單純再看一次）。
		case respond([PTTKey])

		/// 命中資源上限畫面：記進節流閘、退避後重繪再等。全域攔截專用。
		case resourceLimit

		/// 已知的失敗畫面：直接丟錯，錯誤訊息取 ``PTTScreenTarget/name``。
		case failure
	}

	/// 目標名稱（錯誤訊息與除錯用；不參與比對）。
	public let name: String

	/// 偵測字串，AND 語義——全部都要在畫面上出現才算命中。
	public let patterns: [String]

	/// 命中後的處置。
	public let outcome: Outcome

	/// 比對攤平後的畫面文字。
	///
	/// 空 pattern 一律不命中——否則一張空表會匹配任何畫面，讓等待瞬間假成功。
	public func matches(_ screenText: String) -> Bool {
		guard !patterns.isEmpty else { return false }
		return patterns.allSatisfy { screenText.contains($0) }
	}

	/// 建立一張目標畫面描述。
	public init(name: String, patterns: [String], outcome: Outcome) {
		self.name = name
		self.patterns = patterns
		self.outcome = outcome
	}
}
