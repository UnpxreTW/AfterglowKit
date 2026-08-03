//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTCommentType

/// 推文列開頭那兩格印的種類。
///
/// 取值照站方寫檔時用的 `ctype` 表移植（`FormatCommentString()`，來源
/// https://github.com/ptt/pttbbs 的 `mbbsd/comments.c`），順序對應同 repo `mbbsd/bbs.c`
/// 裡 `RECTYPE_GOOD` / `RECTYPE_BAD` / `RECTYPE_ARROW` 的列舉。
public enum PTTCommentType: String, CaseIterable, Sendable {

	/// 推（`RECTYPE_GOOD`）：站方把該文的推文數加一。
	case push = "推"

	/// 噓（`RECTYPE_BAD`）：站方把該文的推文數減一。
	case boo = "噓"

	/// →（`RECTYPE_ARROW`）：只留言，站方不動推文數。
	///
	/// !!!: 這一種不必然是推文者自己選的。作者推自己的文章、或距上一則推文不足九十秒，
	/// 站方都會**強制**改成這一種再寫檔；寫進檔案之後就看不出原本想推還是想噓了。
	case arrow = "→"
}
