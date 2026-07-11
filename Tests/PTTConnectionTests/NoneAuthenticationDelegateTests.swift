//
//  PTTConnectionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTConnection
import NIOEmbedded
import NIOSSH
import Testing

/// none 驗證 delegate：首問提交 none offer、被拒後回 nil 收攤（不無限重試）。
private final class NoneAuthenticationDelegateTests {

	/// 首次詢問 → 以指定帳號提交 none offer。
	@Test
	private func `offers none authentication with username on first ask`() throws {
		let loop: EmbeddedEventLoop = .init()
		let delegate: NoneAuthenticationDelegate = .init(username: "bbs")
		let promise = loop.makePromise(of: NIOSSHUserAuthenticationOffer?.self)
		delegate.nextAuthenticationType(availableMethods: .all, nextChallengePromise: promise)
		let offer = try #require(try promise.futureResult.wait())
		#expect(offer.username == "bbs")
		guard case .none = offer.offer else {
			Issue.record("offer 應為 none、實得 \(offer.offer)")
			return
		}
	}

	/// 第二次詢問（none 已遭拒）→ 回 nil 表示無更多手段、讓 NIOSSH 以驗證失敗收攤。
	@Test
	private func `gives up after none offer is rejected`() throws {
		let loop: EmbeddedEventLoop = .init()
		let delegate: NoneAuthenticationDelegate = .init(username: "bbs")
		let firstPromise = loop.makePromise(of: NIOSSHUserAuthenticationOffer?.self)
		delegate.nextAuthenticationType(availableMethods: .all, nextChallengePromise: firstPromise)
		_ = try firstPromise.futureResult.wait()
		let secondPromise = loop.makePromise(of: NIOSSHUserAuthenticationOffer?.self)
		delegate.nextAuthenticationType(availableMethods: .all, nextChallengePromise: secondPromise)
		#expect(try secondPromise.futureResult.wait() == nil)
	}
}
