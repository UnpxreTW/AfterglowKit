//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTArticleListing

/// 一段編號區間的文章清單讀取結果。
///
/// **完整性**：翻頁次數用盡、收到的編號中間出現斷洞、或讀到一半遇上不可信的畫面時，
/// ``isComplete`` 為 `false`——呼叫端據此分得出「清單就這麼多」與「我們沒讀完」，讀取端
/// 不靜默截斷。這條保證與 ``PTTArticleContent/isComplete`` 是同一條，兩處刻意用同一個
/// 名字、同一個語義。
public struct PTTArticleListing: Equatable, Sendable {

	// MARK: Public

	/// 收到的文章摘要，依編號遞增排序。
	///
	/// 區間內查無文章、或看板本身沒有文章時為空——「查無」是正常結果、不是不完整。
	public let articles: [PTTArticleSummary]

	/// 是否把請求區間讀到了盡頭（而非翻頁次數用盡、或中間漏掉整頁）。
	///
	/// !!!: 停在 `upperIndex` **之前**不代表不完整——請求區間超過看板現有文章時，清單停在
	/// 最後一篇就是正確答案。判準有三個：翻頁次數用盡、收到的編號出現斷洞、以及讀取中途遇上
	/// 不可信的畫面而收手。第二個靠的是清單編號連號這條不變量：收進來的編號本該是連續的一段，
	/// 中間有洞就是確定漏掉了整頁。第三個現行只有一種來源——清單讀到一半出現「沒有文章」的
	/// 畫面（那張畫面只在第一張時才代表看板真的是空的）。
	///
	/// !!!: 空的 ``articles`` 配 `false` 是有意義的值、不是矛盾：它說的是「一篇都沒收到，而且
	/// 這不代表這裡沒有文章」，與空清單配 `true`（區間內查無、或看板本身沒有文章）是兩件事。
	///
	/// `false` 時 ``articles`` 仍是目前收到的部分、不因不完整而被丟棄——呼叫端可以先用
	/// 這部分，只是知道它不是全部。
	public let isComplete: Bool

	/// 建立一份清單讀取結果。
	public init(articles: [PTTArticleSummary], isComplete: Bool) {
		self.articles = articles
		self.isComplete = isComplete
	}
}
