//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTArticleHeader

/// 文章開頭的表頭區塊（作者／標題／時間／轉信來源等）。
///
/// **這不是檔案原行的忠實重建**——pmore 依終端寬度把表頭重排成自己的版面
/// （`mf_parseHeaders()`，來源 https://github.com/ptt/pttbbs 的 `mbbsd/pmore.c`），
/// 與內文行的「按行號精確重建」是刻意不同的兩套方法（見 ``ArticleContentScanner``
/// 型別註解「唯一分歧點」）。表頭列數由首行決定：`作者:` 開頭為本站文章（3 列）、
/// `發信人:` 開頭為轉信文章（4 列）；末列為空則再減一。首行兩者皆非時沒有表頭，
/// 由 ``ArticleContentScanner`` 回傳 `nil`、不勉強套用版面。
public struct PTTArticleHeader: Equatable, Sendable {

	// MARK: Public

	/// 依畫面由上而下的表頭欄位。
	public let fields: [PTTArticleHeaderField]

	/// 建立一份表頭。
	public init(fields: [PTTArticleHeaderField]) {
		self.fields = fields
	}
}
