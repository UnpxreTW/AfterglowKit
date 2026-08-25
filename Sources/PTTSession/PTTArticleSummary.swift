//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTArticleSummary

/// 看板文章清單上的一列。
///
/// **這是「清單畫面說了什麼」的模型、不是文章本身的模型**——清單只給得起編號、狀態記號、
/// 推文數欄、月日、作者代號與被截斷過的標題。發文年份、完整標題、內文、推文明細都不在
/// 清單畫面上，要另外進文章取（M3 的範圍）。
///
/// 置底文（公告）不會出現在這裡：站方在編號欄印星號而非編號，本型別沒有編號可填，
/// 由 ``ArticleListingScanner`` 略過。
///
/// !!!: **已被安全刪除的文章仍然是清單上的一列，而且各欄都合法**——站方認它的依據是作者欄
/// 整格只有一個 `-`（`mbbsd/bbs.c` 的 `readdoent()`，`ent->owner` 是不是 `"-"`），認出來之後
/// 類別記號照樣印 `□`＝``PTTArticleKind/normal``，已讀狀態則被寫死成已讀、不查閱讀記錄。
/// ``PTTArticleKind`` 的型別說明寫著「從清單畫面無法分辨」，這裡補上唯一那個辨識點：
/// ``author`` 的那個 `-`。判讀端不替呼叫端過濾這種列——它是站方真的印出來的一列。
///
/// !!!: 上一段成立的前提是站方編了 `SAFE_ARTICLE_DELETE` 而**沒有**編 `COLORIZED_SAFEDEL`。
/// 後者會讓 `readdoent()` 走另一條早退路徑、印出完全不同的版面（無推文數欄、記號改成 `╳`），
/// 那種列不符合 ``ArticleListingScanner`` 的欄位表、會被判成不可用而不是被誤讀。兩個巨集在
/// 公開樹裡都只有 `#ifdef`（`sample/pttbbs.conf` 的那行是註解掉的），判不出實際站台編了哪些
/// ——同 ``PTTComment`` 位址欄那類編譯期分支的處置：不猜，把兩種後果都寫明。
public struct PTTArticleSummary: Equatable, Sendable {

	// MARK: Public

	/// 文章在看板中的編號（站方的 `%7d` 欄，可用來直接跳到該篇）。
	public let index: Int

	/// 狀態記號；站方印了本型別未涵蓋的字元時為 `nil`。
	///
	/// 記號屬呈現用資訊、不參與識別，因此無法辨認時整列照樣回傳、不視為判讀失敗。
	public let mark: PTTArticleMark?

	/// 推文數欄（站方只有兩格、本身就是被壓縮過的資訊，見 ``PTTPushCount``）。
	public let pushCount: PTTPushCount

	/// 發表日期，格式為「月/日」（站方清單不給年份）。
	public let date: String

	/// 作者代號（站方欄寬 12 字，超長會被截斷）。
	///
	/// 整格只有一個 `-` 時代表這篇已被安全刪除，不是有人叫這個名字（見型別註解）。
	public let author: String

	/// 類別記號；站方印了本型別未涵蓋的記號時為 `nil`（同 ``mark`` 的處置理由）。
	public let kind: PTTArticleKind?

	/// 標題（不含類別記號；站方欄寬有限，長標題在畫面上就已被截斷）。
	public let title: String

	/// 建立一列清單摘要。
	public init(
		index: Int,
		mark: PTTArticleMark?,
		pushCount: PTTPushCount,
		date: String,
		author: String,
		kind: PTTArticleKind?,
		title: String
	) {
		self.index = index
		self.mark = mark
		self.pushCount = pushCount
		self.date = date
		self.author = author
		self.kind = kind
		self.title = title
	}

	// MARK: Internal

	/// 換掉編號、其餘欄位照舊。
	///
	/// 供 ``ArticleListingScanner`` 把被游標記號蓋掉的編號位數補回來用。其餘欄位都來自同一列、
	/// 沒有跟著改的道理，所以這裡只開編號這一個口。
	func replacingIndex(with index: Int) -> PTTArticleSummary {
		.init(
			index: index,
			mark: mark,
			pushCount: pushCount,
			date: date,
			author: author,
			kind: kind,
			title: title
		)
	}
}
