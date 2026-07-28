//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTTargetTable

/// 目標畫面表。
///
/// 表內的偵測字串移植自 PyPtt 的 target 表（`PyPtt/screens.py`、`PyPtt/_api_loginout.py`、
/// `PyPtt/_api_util.py`、`PyPtt/connect_core.py`，皆為上游現行版本讀碼取得）。
/// 站方的按鍵序列與畫面文字由同一支 server 產生，與連線方式無關，因此這套畫面知識
/// 可以整套沿用。來源：https://github.com/PyPtt/PyPtt
///
/// **偵測字串未經真實帳號連線覆核**——本專案的自動化測試一律不對外連線，
/// 表內字串只能靠上游讀碼與離線畫面捕獲交叉對照。掛真實帳號實測後若發現落差，
/// 修這張表即可，不需要動流程碼。
public enum PTTTargetTable {

	// MARK: Public

	/// 主功能表。登入成功的判準。
	public static let mainMenu: PTTScreenTarget = .init(
		name: "主功能表",
		patterns: ["離開，再見", "人, 我是", "[呼叫器]"],
		outcome: .arrived
	)

	/// 主功能表的離站確認畫面。進板失敗時會退回這裡，因此拿它當「進板沒成功」的訊號。
	public static let mainMenuExiting: PTTScreenTarget = .init(
		name: "主功能表離站確認",
		patterns: ["【主功能表】", "您確定要離開"],
		outcome: .arrived
	)

	/// 已在看板的文章清單畫面。
	public static let inBoard: PTTScreenTarget = .init(
		name: "看板文章清單",
		patterns: ["看板資訊/設定", "文章選讀", "相關主題"],
		outcome: .arrived
	)

	/// 看板存在但一篇文章也沒有。
	public static let emptyBoard: PTTScreenTarget = .init(
		name: "看板無文章",
		patterns: ["沒有文章..."],
		outcome: .arrived
	)

	/// 全域攔截表：每一次等畫面都會附掛在呼叫端自己的目標之後。
	///
	/// 順序即優先序（先命中先處置）。資源上限擺第一，確保它不會被任何其他分支蓋過——
	/// 那是唯一一個「必須立刻退避、不能照常往下走」的畫面。
	public static let globals: [PTTScreenTarget] = [
		resourceLimit,
		wrongCredentials,
		reenterCredentials,
		systemOverloaded,
		resetContactEmail,
		secureConnectionOnly,
		unfinishedArticle,
		draftSelection,
		deleteErrorAttempts,
		tooFrequentLogin,
		registrationPending,
		syncingFriendList,
		passwordAccepted,
		boardList,
		categorisedBoards,
		mailMenu,
		mailBox,
		animationPlaying,
		anyKey
	]

	// MARK: Internal

	/// 資源用量超限：站方把連線推到這個畫面，必須退避而非繼續送鍵。
	static let resourceLimit: PTTScreenTarget = .init(
		name: "程式耗用過多計算資源",
		patterns: ["程式耗用過多"],
		outcome: .resourceLimit
	)

	/// 帳號或密碼錯誤。
	static let wrongCredentials: PTTScreenTarget = .init(
		name: "密碼不對或無此帳號",
		patterns: ["密碼不對"],
		outcome: .failure
	)

	/// 站方要求重打帳號密碼，等同認證失敗。
	static let reenterCredentials: PTTScreenTarget = .init(
		name: "請重新輸入帳號密碼",
		patterns: ["請重新輸入"],
		outcome: .failure
	)

	/// 系統過載，站方拒絕本次登入。
	static let systemOverloaded: PTTScreenTarget = .init(
		name: "系統過載",
		patterns: ["系統過載"],
		outcome: .failure
	)

	/// 站方要求先重設聯絡信箱才能繼續，屬需要使用者親自處理的分支。
	static let resetContactEmail: PTTScreenTarget = .init(
		name: "請重新設定聯絡信箱",
		patterns: ["請重新設定您的聯絡信箱"],
		outcome: .failure
	)

	/// 帳號被設定為只接受安全連線。
	static let secureConnectionOnly: PTTScreenTarget = .init(
		name: "此帳號只能使用安全連線",
		patterns: ["此帳號已設定為只能使用安全連線"],
		outcome: .failure
	)

	/// 上次有一篇文章沒編輯完。
	///
	/// !!!: 這裡刻意不自動應答。上游的做法是直接送「放棄編輯」把暫存內容丟掉，
	/// 但那是使用者的文字資料，函式庫不該替他決定丟或留；改成回報錯誤、
	/// 讓上層把選擇權交還給使用者。
	static let unfinishedArticle: PTTScreenTarget = .init(
		name: "有一篇文章尚未完成",
		patterns: ["有一篇文章尚未完成"],
		outcome: .failure
	)

	/// 暫存檔選單：直接按 Enter 取預設項通過（不觸及任何暫存內容）。
	static let draftSelection: PTTScreenTarget = .init(
		name: "請選擇暫存檔",
		patterns: ["請選擇暫存檔 (0-9)[0]"],
		outcome: .respond([.enter])
	)

	/// 錯誤嘗試記錄：答 y 清掉後繼續。
	static let deleteErrorAttempts: PTTScreenTarget = .init(
		name: "刪除錯誤嘗試記錄",
		patterns: ["您要刪除以上錯誤嘗試的記錄嗎"],
		outcome: .respond([.text("y"), .enter])
	)

	/// 登入太頻繁的提示畫面：按空白鍵略過即可。
	///
	/// 這是提示、不是拒絕；真正的自律（不在三秒內重登、被拒後退避）由連線層的
	/// 登入頻率閘負責，Session 層只要別被這張畫面卡住。
	static let tooFrequentLogin: PTTScreenTarget = .init(
		name: "登入太頻繁",
		patterns: ["登入太頻繁"],
		outcome: .respond([.text(" ")])
	)

	/// 註冊申請單處理中：按 Enter 通過。
	static let registrationPending: PTTScreenTarget = .init(
		name: "註冊申請單處理中",
		patterns: ["◆ 您的註冊申請單尚在處理中"],
		outcome: .respond([.enter])
	)

	/// 正在同步線上使用者與好友名單：不需要按鍵，等下一張畫面即可。
	static let syncingFriendList: PTTScreenTarget = .init(
		name: "同步線上使用者及好友名單",
		patterns: ["正在更新與同步線上使用者及好友名單"],
		outcome: .respond([])
	)

	/// 密碼正確的過場提示：不需要按鍵，等下一張畫面即可。
	static let passwordAccepted: PTTScreenTarget = .init(
		name: "密碼正確",
		patterns: ["密碼正確"],
		outcome: .respond([])
	)

	/// 看板列表：推回主功能表。
	static let boardList: PTTScreenTarget = .init(
		name: "看板列表",
		patterns: ["【看板列表】"],
		outcome: .respond(PTTKey.mainMenuReset)
	)

	/// 分類看板：推回主功能表。
	static let categorisedBoards: PTTScreenTarget = .init(
		name: "分類看板",
		patterns: ["【分類看板】"],
		outcome: .respond(PTTKey.mainMenuReset)
	)

	/// 電子郵件選單：推回主功能表。
	static let mailMenu: PTTScreenTarget = .init(
		name: "電子郵件選單",
		patterns: ["【電子郵件】", "我的信箱", "寄信給帳號站長"],
		outcome: .respond(PTTKey.mainMenuReset)
	)

	/// 郵件選單（信箱已滿時登入會直接落到這裡）：推回主功能表。
	///
	/// 信箱容量的判讀屬郵件功能範圍、不在此處理；這裡只負責別讓登入流程卡住。
	static let mailBox: PTTScreenTarget = .init(
		name: "郵件選單",
		patterns: ["【郵件選單】", "[~]資源回收筒", "鴻雁往返"],
		outcome: .respond(PTTKey.mainMenuReset)
	)

	/// 互動式動畫播放中：送中斷鍵跳出。
	static let animationPlaying: PTTScreenTarget = .init(
		name: "互動式動畫播放中",
		patterns: ["互動式動畫播放中"],
		outcome: .respond([.interrupt, .interrupt, .interrupt, .interrupt, .interrupt])
	)

	/// 請按任意鍵繼續：按空白鍵。
	///
	/// 這條 pattern 最寬鬆（不少畫面底部都有這行），因此排在全域表最後，
	/// 讓具體的畫面先有機會命中。
	static let anyKey: PTTScreenTarget = .init(
		name: "請按任意鍵繼續",
		patterns: ["任意鍵"],
		outcome: .respond([.text(" ")])
	)
}
