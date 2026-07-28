//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import PTTTerminal

// MARK: - PTTSession

/// 畫面狀態機：把「一連串按鍵 + 等到某張畫面」這件事收成可組合的 async 操作。
///
/// **依賴形狀**：只吃兩個抽象——一條 `PTTScreen` 快照流、一個 ``PTTKeySink``。
/// 不持有 `PTTTerminal` 或 `PTTConnection` 任何具體型別，組裝由外層負責
/// （同 `PTTConnection` 引擎只依賴 `PTTTransport` 協定的作法）。因此本型別的測試
/// 全部餵假快照與假 sink、不對外連線。
///
/// **等畫面怎麼等**：站方沒有「重繪完成」訊號，所以照既有可行做法走三件套——
/// 每串按鍵尾端補一顆重繪鍵、以整張新畫面為比對單位、逾時分級（一般 3 秒、
/// 登入圈 10 秒；發文的 60 秒等發文功能落地時再加）。
///
/// **不重複管連線層已管的事**：連線配額、重複登入的刪除詢問、登入頻率自律都在
/// `PTTConnection` 層完成。Session 看得到那些畫面但不應答它們——等到連線層處理完、
/// 畫面自然往下走。
///
/// **觀察方式**：actor + 快照流，不用物件對物件的觀察機制（會踩上一次性追蹤、
/// 重建與保留環三個坑）。
public actor PTTSession {

	// MARK: Public

	/// 一般畫面的等待上限。
	public static let standardTimeout: Duration = .seconds(3)

	/// 登入圈的等待上限（站方在踢重複連線前後會插入數秒隨機延遲，故放寬）。
	public static let loginTimeout: Duration = .seconds(10)

	/// 單次等待內允許的自動應答次數上限。
	///
	/// 上游沒有這道閘、純靠逾時收斂；這裡加一道，讓「畫面在兩張之間來回、每張都命中
	/// 應答型目標」的情況早點以明確錯誤結束，而不是耗滿逾時再回報一個看不出原因的失敗。
	public static let maximumResponses = 12

	/// 清單畫面判讀失敗時的重試次數（畫面競態是常態，重取一次多半就好了）。
	public static let parseRetryLimit = 2

	/// 帳號長度上限（站方截斷值）。
	public static let maximumIdentifierLength = 12

	/// 密碼長度上限（站方截斷值）。
	public static let maximumPasswordLength = 8

	/// 目前最新的畫面快照；還沒收到任何畫面時為 `nil`。
	public var currentScreen: PTTScreen? {
		latestScreen
	}

	/// 登入。成功時代表已經站在主功能表上。
	///
	/// 帳號與密碼會先截斷到站方上限再去除前後空白——順序照站方行為，先截後修。
	///
	/// !!!: 帳號後面不加逗號。加逗號會要求站方改用 UTF-8 送畫面，但本專案自己備有
	/// Big5-UAO 轉碼器，且站方的 UTF-8 模式無法還原雙色字；維持 Big5 才是完整的那條路。
	///
	/// 帳號與密碼一次送完、不等中間的提示畫面：站方接受預先輸入，中途分支
	/// （錯誤嘗試記錄、暫存檔選單、任意鍵提示…）由全域攔截表自動處理。
	public func logIn(userIdentifier: String, password: String) async throws {
		let identifier: String = Self.trimmed(String(userIdentifier.prefix(Self.maximumIdentifierLength)))
		let secret: String = Self.trimmed(String(password.prefix(Self.maximumPasswordLength)))
		guard !identifier.isEmpty, !secret.isEmpty else { throw PTTSessionError.emptyCredentials }
		_ = try await send(
			[.text(identifier), .enter, .text(secret), .enter],
			awaiting: [PTTTargetTable.mainMenu],
			timeout: Self.loginTimeout
		)
	}

	/// 取指定看板目前最新一篇文章的編號；看板存在但沒有文章時回 `0`。
	///
	/// 做法是進板後跳到清單末端（`1` + Enter 定位第一篇、`$` 跳最後一篇），
	/// 再由 ``ArticleIndexScanner`` 判讀編號欄。判讀失敗會重取畫面重試。
	public func newestIndex(ofBoard board: String) async throws -> Int {
		try await goToBoard(board)
		for _ in 0 ... Self.parseRetryLimit {
			let target: PTTScreenTarget = try await send(
				[.text("1"), .enter, .text("$")],
				awaiting: [PTTTargetTable.emptyBoard, PTTTargetTable.inBoard],
				timeout: Self.standardTimeout
			)
			if target == PTTTargetTable.emptyBoard { return 0 }
			guard let screen = latestScreen else { continue }
			if let index = ArticleIndexScanner.newestIndex(in: screen) { return index }
		}
		throw PTTSessionError.indexParseFailed(board)
	}

	/// 送出一串按鍵，然後等到其中一張目標畫面出現。
	///
	/// 只有送鍵之後才抵達的畫面算數——送鍵前那張畫面即使命中也不採信，
	/// 否則上一步留下的殘影會讓等待立刻假成功。
	///
	/// !!!: 界線取在「真的寫進 sink 的前一刻」，不是進入本函式的時候。節流閘可能先讓
	/// 這次送鍵等上一段時間，那段等待期間流上補進來的畫面仍屬於上一步的產物；
	/// 界線若取得太早，那些殘影就會被誤認成本次送鍵的回應。
	@discardableResult
	public func send(
		_ keys: [PTTKey],
		awaiting targets: [PTTScreenTarget],
		timeout: Duration
	) async throws -> PTTScreenTarget {
		try startPump()
		let generation: Int = try await sendKeys(keys)
		return try await wait(for: targets, after: generation, timeout: timeout)
	}

	/// 不送鍵、直接等目標畫面（站方主動送出的畫面，例如剛連上時的進站畫面）。
	@discardableResult
	public func waitFor(_ targets: [PTTScreenTarget], timeout: Duration) async throws -> PTTScreenTarget {
		try startPump()
		return try await wait(for: targets, after: 0, timeout: timeout)
	}

	/// 停止消費快照流。
	///
	/// 消費快照流的背景 task 會持有 Session，不主動停就等於讓 Session 活到流結束為止；
	/// 用完呼叫這裡切斷即可。關閉後不再受理任何操作。
	public func close() {
		pump?.cancel()
		pump = nil
		isClosed = true
	}

	/// 建立 Session。
	///
	/// - Parameters:
	///   - screens: 畫面快照流；每次站方重繪後應 yield 一張最新快照。
	///   - keySink: 送鍵出口。
	///   - clock: 時間來源；測試注入假時鐘。
	///   - globalTargets: 全域攔截表，附掛在每一次等待的呼叫端目標之後。
	public init(
		screens: AsyncStream<PTTScreen>,
		keySink: PTTKeySink,
		clock: SessionClock = .continuous,
		globalTargets: [PTTScreenTarget] = PTTTargetTable.globals
	) {
		self.screens = screens
		self.keySink = keySink
		self.clock = clock
		self.globalTargets = globalTargets
	}

	// MARK: Private

	/// 等畫面的輪詢間隔。
	///
	/// !!!: 這裡刻意用輪詢而不是「新畫面到達就喚醒等待者」。喚醒式寫法要自己處理
	/// 逾時與喚醒的競態、以及等待中被取消時 continuation 的歸屬，複雜度全落在
	/// 最不該出錯的地方；輪詢版的取消語義直接由睡眠本身提供，也讓假時鐘測試不必
	/// 模擬喚醒順序。代價是最多多等一個輪詢間隔——相對於站方重繪的百毫秒級節奏可忽略。
	private static let pollInterval: Duration = .milliseconds(20)

	/// 去除前後空白（不引入 Foundation）。
	private static func trimmed(_ value: String) -> String {
		var result: Substring = value[...]
		while let first = result.first, first.isWhitespace {
			result = result.dropFirst()
		}
		while let last = result.last, last.isWhitespace {
			result = result.dropLast()
		}
		return String(result)
	}

	/// 畫面快照流。
	private let screens: AsyncStream<PTTScreen>

	/// 送鍵出口。
	private let keySink: PTTKeySink

	/// 時間來源。
	private let clock: SessionClock

	/// 全域攔截表。
	private let globalTargets: [PTTScreenTarget]

	/// 全域送鍵節流閘。
	private var throttle: SendThrottle = .init()

	/// 最新畫面快照。
	private var latestScreen: PTTScreen?

	/// 畫面世代編號：每收到一張新快照 +1，用來分辨「送鍵之後才來的畫面」。
	private var screenGeneration = 0

	/// 消費快照流的背景 task。
	private var pump: Task<Void, Never>?

	/// 快照流是否已結束（連線已關）。
	private var isStreamFinished = false

	/// 是否已被 ``close()`` 關閉。
	private var isClosed = false

	/// 啟動快照流的消費（冪等）。
	///
	/// !!!: 用 `Task.detached` 而非繼承隔離的 `Task`——繼承隔離時整個 `for await`
	/// 迴圈都算在本 actor 上，讀流與處理流交錯在同一個隔離域裡，反而更難看出
	/// 哪些狀態變更是原子的。分離後只有 ``ingest(_:)`` 這一步跳回 actor，邊界清楚。
	private func startPump() throws {
		guard !isClosed else { throw PTTSessionError.closed }
		guard pump == nil else { return }
		pump = Task.detached { [screens] in
			for await screen in screens {
				await self.ingest(screen)
			}
			await self.markStreamFinished()
		}
	}

	/// 收下一張新快照。
	private func ingest(_ screen: PTTScreen) {
		latestScreen = screen
		screenGeneration += 1
	}

	/// 標記快照流已結束。
	private func markStreamFinished() {
		isStreamFinished = true
	}

	/// 過節流閘送出一串按鍵，尾端補上重繪鍵；回傳送出前最後一刻的畫面世代。
	///
	/// 回傳值就是「這次送鍵的回應從哪一張畫面開始算」的界線，見 ``send(_:awaiting:timeout:)``。
	private func sendKeys(_ keys: [PTTKey]) async throws -> Int {
		let delay: Duration = throttle.requiredDelay(now: clock.now())
		if delay > .zero { try await clock.sleep(delay) }
		throttle.recordSend(at: clock.now())
		var payload: [PTTKey] = keys
		if payload.last != .formFeed { payload.append(.formFeed) }
		let generation: Int = screenGeneration
		try await keySink.send(payload)
		return generation
	}

	/// 等畫面主迴圈：每有一張比 `generation` 新的快照就比對一次目標表。
	///
	/// 兩張快照之間若來得太密，只會比對到最新那張——這與「以整張新畫面為比對單位」
	/// 的前提一致：中途那些半成品畫面本來就不該拿來判斷。
	private func wait(
		for targets: [PTTScreenTarget],
		after generation: Int,
		timeout: Duration
	) async throws -> PTTScreenTarget {
		let table: [PTTScreenTarget] = targets + globalTargets
		var checked: Int = generation
		var responses = 0
		var deadline: ContinuousClock.Instant = clock.now() + timeout
		while true {
			if screenGeneration > checked, let screen = latestScreen {
				checked = screenGeneration
				let text: String = PTTScreenText.flattened(screen)
				if let target = table.first(where: { $0.matches(text) }) {
					let arrived: PTTScreenTarget? = try await handle(target, responses: &responses, checked: &checked)
					if let arrived { return arrived }
					deadline = clock.now() + timeout
				}
			}
			if isStreamFinished, screenGeneration <= checked { throw PTTSessionError.screenStreamEnded }
			guard clock.now() < deadline else { throw PTTSessionError.timedOut }
			try await clock.sleep(Self.pollInterval)
		}
	}

	/// 處置一次命中；回傳非 nil 代表這就是要等的畫面、等待到此結束。
	///
	/// 自動應答會把 `checked` 推到該次送鍵的界線，讓應答期間補進來的殘影不被當成回應。
	private func handle(
		_ target: PTTScreenTarget,
		responses: inout Int,
		checked: inout Int
	) async throws -> PTTScreenTarget? {
		switch target.outcome {
		case .arrived:
			return target
		case .failure:
			throw PTTSessionError.unexpectedScreen(target.name)
		case let .respond(keys):
			try await respond(keys, to: target, responses: &responses, checked: &checked)
		case .resourceLimit:
			throttle.recordResourceLimit(at: clock.now())
			// 只補重繪鍵；退避由節流閘在送出前吃掉。
			try await respond([], to: target, responses: &responses, checked: &checked)
		}
		return nil
	}

	/// 自動應答一次，並守住單次等待的應答次數上限。
	private func respond(
		_ keys: [PTTKey],
		to target: PTTScreenTarget,
		responses: inout Int,
		checked: inout Int
	) async throws {
		responses += 1
		guard responses <= Self.maximumResponses else { throw PTTSessionError.tooManyResponses(target.name) }
		checked = try await sendKeys(keys)
	}

	/// 進看板：先把畫面推回主功能表，再走看板快選。
	///
	/// 尾端連送中斷鍵是為了跳過某些看板的進板動畫；動畫若有「任意鍵」或
	/// 「互動式動畫播放中」的提示，則由全域攔截表接手。
	private func goToBoard(_ board: String) async throws {
		var keys: [PTTKey] = PTTKey.mainMenuReset
		keys.append(.text("qs"))
		keys.append(.text(board))
		keys.append(.enter)
		keys.append(contentsOf: repeatElement(PTTKey.interrupt, count: 5))
		let target: PTTScreenTarget = try await send(
			keys,
			awaiting: [PTTTargetTable.inBoard, PTTTargetTable.mainMenuExiting],
			timeout: Self.standardTimeout
		)
		guard target != PTTTargetTable.mainMenuExiting else { throw PTTSessionError.noSuchBoard(board) }
	}
}
