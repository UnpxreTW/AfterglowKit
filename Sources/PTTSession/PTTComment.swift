//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTComment

/// 一則推文。
///
/// **這是「站方把推文寫進檔案時印了什麼」的模型**——每個欄位都對得上站方組那一行的格式
/// （`FormatCommentString()`，來源 https://github.com/ptt/pttbbs 的 `mbbsd/comments.c`）。
/// 去掉色碼之後那一行長這樣：
///
/// ```text
/// 推 someone:內容內容                                  123.45.67.89 07/31 12:34
/// │  │       │                                         │            └ 站方時刻
/// │  │       │                                         └ 來源位址（看板有開才有這一段）
/// │  │       └ 推文內容（站方補空白補到定寬）
/// │  └ 推文者代號
/// └ 種類
/// ```
///
/// 推文本身不帶年份、也不帶推文者的暱稱或權限——站方那一行就只印得出這幾樣，
/// 想要更多得另外查，不是這個型別漏了。
public struct PTTComment: Equatable, Sendable {

	// MARK: Public

	/// 種類（推／噓／→）。
	public let type: PTTCommentType

	/// 推文者代號。
	///
	/// 看板設定成推文對齊時，站方會把代號補空白補到十二格再寫檔；補的空白屬版面、
	/// 不屬代號，這裡已經去掉。
	public let author: String

	/// 推文內容。
	///
	/// 前後空白都已去除：尾端那些是站方補到定寬的版面、開頭那一格通常是推文者自己按的
	/// （站方在冒號後不補空白）。要逐字保真的用途請改讀推文原始行，這個欄位是判讀結果。
	public let message: String

	/// 來源位址；看板沒開「推文記錄來源位址」時為 `nil`。
	///
	/// !!!: 站方可能把位址末段遮成 `*`（`obfuscate_ipstr()` 把最後一個點之後整段換成一個
	/// 星號，來源同 repo 的 `common/bbs/string.c`），開關是站方編譯期設定、從公開原始碼
	/// 判不出來，所以 `123.45.67.89` 與 `123.45.67.*` 兩式都可能出現，照原文回傳、不還原。
	public let sourceIP: String?

	/// 站方印的時刻，格式為「月/日 時:分」。
	///
	/// 站方這一欄不給年份（`%m/%d %H:%M`）。跨年的文章要靠文章本身的時間推，
	/// 不要拿這個欄位自己補年份。
	public let time: String

	/// 建立一則推文。
	public init(
		type: PTTCommentType,
		author: String,
		message: String,
		sourceIP: String?,
		time: String
	) {
		self.type = type
		self.author = author
		self.message = message
		self.sourceIP = sourceIP
		self.time = time
	}
}
