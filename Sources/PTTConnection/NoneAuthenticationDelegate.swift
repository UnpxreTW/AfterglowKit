//
//  PTTConnection
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOSSH

// MARK: - NoneAuthenticationDelegate

/// SSH none 驗證 delegate：ptt.cc 的 `bbs` / `bbsu` 帳號接受 none auth
/// （身分驗證在 BBS 登入畫面內完成、不在 SSH 層）。
///
/// 首次詢問即提交 none offer；若被 server 拒絕（非 ptt.cc 已知行為、防禦性處理）
/// 第二次詢問回覆 `nil` 表示無更多驗證手段、讓 NIOSSH 以驗證失敗收攤，不無限重試。
final class NoneAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate {

	// MARK: Lifecycle

	/// 以 SSH 層登入帳號建立 delegate。
	init(username: String) {
		self.username = username
	}

	// MARK: Internal

	/// 提交下一個驗證手段：首次 none offer、其後 `nil`（放棄）。
	func nextAuthenticationType(
		availableMethods: NIOSSHAvailableUserAuthenticationMethods,
		nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
	) {
		guard !hasOfferedNoneAuthentication else {
			nextChallengePromise.succeed(nil)
			return
		}
		hasOfferedNoneAuthentication = true
		// !!!: serviceName 參數被 NIOSSH 忽略（offer 不保存、訊息層自帶 service 名），傳空字串即可。
		nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(username: username, serviceName: "", offer: .none))
	}

	// MARK: Private

	/// SSH 層登入帳號（`bbs` / `bbsu`）。
	private let username: String

	/// 是否已提交過 none offer（再被詢問＝offer 已遭拒）。
	private var hasOfferedNoneAuthentication = false
}
