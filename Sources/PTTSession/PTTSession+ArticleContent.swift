//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTSession + articleContent

extension PTTSession {

	// MARK: Public

	/// 單次文章內文讀取最多翻幾頁（重取畫面不佔額度）。
	///
	/// 內文頁能載的資訊比清單頁少（表頭與分隔線只在首頁佔位，其餘頁全是內文），
	/// 熱門文章的推文數量可能相當可觀，上限因此給得比 ``maximumListingPages`` 寬裕；
	/// 真正的收斂條件是「``PTTKey/pageForward`` 後行號區間不再前進」，這個常數純粹防跑掉。
	public static let maximumArticlePages = 300

	/// 讀取指定看板某一篇文章的內文。
	///
	/// 做法是跳到文章，以站方 footer 印出的行號區間為錨逐頁收斂（見 ``ArticleContentScanner``），
	/// 不做內容比對去重；翻頁鍵固定用 ``PTTKey/pageForward``，不用空白鍵——空白鍵在末頁
	/// 會直接離開這篇、跳到下一篇（見 ``PTTKey/pageForward`` 型別註解）。
	///
	/// **動畫**：偵測到「可播放的文字動畫」或傳統動畫檔的兩個追問，一律答否、不進入
	/// 逐頁判讀路徑，直接回傳 ``PTTArticleContent/isAnimation`` 為 `true` 且內文皆空的結果——
	/// 原樣內容交呈現層另一條路徑處理（tap A），不在本函式範圍（見 M3-b 拍板）。
	///
	/// **不完整**：頁數上限用盡、或收到的行號中間出現斷洞，回傳目前收到的部分並把
	/// ``PTTArticleContent/isComplete`` 標 `false`，不靜默截斷（見 M3-c 拍板）。只有連
	/// 第一頁都判讀不出來才丟 ``PTTSessionError/articleReadFailed(board:index:)``——
	/// 已經收到至少一頁時一律回傳部分結果，不把已收到的資料吞掉。
	public func articleContent(inBoard board: String, at index: Int) async throws -> PTTArticleContent {
		try beginOperation()
		defer { endOperation() }
		try await goToBoard(board)
		let opening: PTTScreenTarget = try await requestArticlePage([.text(String(index)), .enter, .enter])
		if let animation = try await animationContent(for: opening) { return animation }

		var state: ArticleReadState = .init()
		articlePages: while true {
			let page: ArticleContentScanner.Page? = currentScreen.flatMap {
				ArticleContentScanner.page(in: $0, isFirstPage: state.isFirstPage)
			}
			switch state.integrate(page) {
			case .converged:
				break articlePages
			case .advanced:
				guard state.pages < Self.maximumArticlePages else {
					state.pageLimitReached = true
					break articlePages
				}
				let target: PTTScreenTarget = try await requestArticlePage([.pageForward])
				if let animation = try await animationContent(for: target) { return animation }
			case .retry:
				let target: PTTScreenTarget = try await requestArticlePage([])
				if let animation = try await animationContent(for: target) { return animation }
			case .giveUp:
				break articlePages
			case .hardFailure:
				throw PTTSessionError.articleReadFailed(board: board, index: index)
			}
		}
		return state.assembleContent()
	}

	// MARK: Private

	/// ``articleContent(inBoard:at:)`` 每一次等畫面附掛的呼叫端目標：文章內文頁的兩種
	/// footer 格式，加動畫偵測的三個 prompt（``.arrived``、由呼叫端自己決定怎麼應答）。
	private static let articleAwaitingTargets: [PTTScreenTarget] = [
		PTTTargetTable.articleContentPage,
		PTTTargetTable.articleContentPageScrolled,
		PTTTargetTable.movieDetectedPrompt,
		PTTTargetTable.traditionalAnimationSpeedPrompt,
		PTTTargetTable.traditionalAnimationLineCountPrompt
	]

	/// 送出鍵、等到內文頁或動畫 prompt 之一——``articleContent(inBoard:at:)`` 逐頁讀取的共用入口。
	private func requestArticlePage(_ keys: [PTTKey]) async throws -> PTTScreenTarget {
		try await performSend(keys, awaiting: Self.articleAwaitingTargets, timeout: Self.standardTimeout)
	}

	/// 命中動畫偵測 prompt 時的收尾：送出對應的婉拒鍵、回傳標成動畫的內容；
	/// 命中的不是動畫 prompt 時回 `nil`，呼叫端照常往下判讀內文頁。
	///
	/// 三個 prompt 各自的婉拒鍵未經真實帳號連線覆核（見 ``PTTTargetTable/movieDetectedPrompt``
	/// 等型別註解）：可播放動畫答 `n`（M3-b 拍板）；傳統動畫的速度提問留空跳過；
	/// 是否模擬 24 行答 `n`、用現在的行數。
	private func animationContent(for target: PTTScreenTarget) async throws -> PTTArticleContent? {
		let declineKeys: [PTTKey]
		if target == PTTTargetTable.movieDetectedPrompt {
			declineKeys = [.text("n"), .enter]
		} else if target == PTTTargetTable.traditionalAnimationSpeedPrompt {
			declineKeys = [.enter]
		} else if target == PTTTargetTable.traditionalAnimationLineCountPrompt {
			declineKeys = [.text("n"), .enter]
		} else {
			return nil
		}
		_ = try await sendKeys(declineKeys)
		return PTTArticleContent(header: nil, bodyLines: [], commentLines: [], isAnimation: true, isComplete: true)
	}
}

// MARK: - ArticleReadState

/// ``PTTSession/articleContent(inBoard:at:)`` 逐頁收斂用的純狀態機。
///
/// 拆成獨立型別是為了讓「這一頁該怎麼處理」與「處理完之後要不要送下一批鍵」兩件事
/// 分開：本型別只管前者（讀資料、判連續性、算重試額度），後者留在
/// ``PTTSession/articleContent(inBoard:at:)`` 的迴圈裡——那裡才有 actor 隔離與送鍵權限。
private struct ArticleReadState {

	// MARK: Internal

	/// 目前是不是還在等第一頁（只有第一頁需要判讀表頭）。
	private(set) var isFirstPage = true

	/// 已成功收進來的頁數（不含重取）。
	private(set) var pages = 0

	/// 頁數上限用盡而中止——由呼叫端在檢查 ``pages`` 之後設定。
	var pageLimitReached = false

	/// 判讀這一頁（`nil` 代表 footer 解不出行號區間或內容列合併對不上，見
	/// ``ArticleContentScanner/page(in:isFirstPage:)``），回傳下一步該怎麼做。
	mutating func integrate(_ page: ArticleContentScanner.Page?) -> PageOutcome {
		guard let page else { return recordFailure() }
		if isFirstPage { header = page.header }
		if let previousRange, page.range != previousRange {
			let advances: Bool = page.range.lowerBound == previousRange.upperBound
				|| page.range.lowerBound == previousRange.upperBound + 1
			guard advances else { return recordFailure() }
		}
		failures = 0
		for (offset, line) in page.lines.enumerated() {
			collected[page.range.lowerBound + page.skippedLineCount + offset] = line
		}
		let converged: Bool = previousRange == page.range
		previousRange = page.range
		guard !converged else { return .converged }
		isFirstPage = false
		pages += 1
		return .advanced
	}

	/// 把目前累積的內容組成最終結果（不完整標記見 ``PTTArticleContent/isComplete``）。
	func assembleContent() -> PTTArticleContent {
		let sortedKeys: [Int] = collected.keys.sorted()
		let hasGap: Bool = {
			guard let first = sortedKeys.first, let last = sortedKeys.last else { return false }
			return (first ... last).contains { collected[$0] == nil }
		}()
		var bodyLines: [String] = []
		var commentLines: [String] = []
		for key in sortedKeys {
			guard let line = collected[key] else { continue }
			if ArticleContentScanner.isCommentLine(line) {
				commentLines.append(line)
			} else {
				bodyLines.append(line)
			}
		}
		return PTTArticleContent(
			header: header,
			bodyLines: bodyLines,
			commentLines: commentLines,
			isAnimation: false,
			isComplete: !pageLimitReached && !hasGap && !stalled
		)
	}

	// MARK: Private

	/// 表頭（僅首頁判得出時非 `nil`）。
	private var header: PTTArticleHeader?

	/// 依檔案行號收集的內文；重疊行自然覆蓋，見 ``ArticleContentScanner`` 型別註解。
	private var collected: [Int: String] = [:]

	/// 上一頁的行號區間；`nil` 代表還沒收到過任何一頁。
	private var previousRange: ClosedRange<Int>?

	/// 連續判讀失敗次數（`nil` 頁或連續性檢查沒過都算一次）。
	private var failures = 0

	/// 重試額度用盡而收手——存在理由見 ``PageOutcome/giveUp``：這種收手也算「沒讀完」，
	/// 不能讓 ``assembleContent()`` 只憑斷洞／頁數上限判完整度而漏掉這一種不完整的成因。
	private var stalled = false

	/// 記一次失敗，依重試額度與目前是否已收到內容決定下一步。
	private mutating func recordFailure() -> PageOutcome {
		failures += 1
		guard failures <= PTTSession.parseRetryLimit else {
			guard !collected.isEmpty else { return .hardFailure }
			stalled = true
			return .giveUp
		}
		return .retry
	}
}

// MARK: - PageOutcome

/// ``ArticleReadState/integrate(_:)`` 判讀一頁之後的下一步。
private enum PageOutcome {

	/// `Ctrl+F` 後行號區間不再前進：已到底，正常收斂。
	case converged

	/// 這一頁有效且往前推進了，可以送下一頁。
	case advanced

	/// 這一頁不可用，但重試額度還在——補重繪重取。
	case retry

	/// 重試額度用盡，但已收到至少一頁——收手回傳目前累積的部分。
	case giveUp

	/// 重試額度用盡，且連第一頁都沒收到——回報讀取失敗。
	case hardFailure
}
