//
//  PTTConnectionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTConnection
import NIOEmbedded
import Testing

/// host key pinning 驗證：內建組雙 key 命中、未知 key 以 hostKeyMismatch 拒絕。
private final class PinnedHostKeysDelegateTests {

	/// 內建 pinned 組的 ed25519 key 命中 → 驗證通過。
	@Test
	private func `pinned ed25519 key passes validation`() throws {
		let loop: EmbeddedEventLoop = .init()
		let delegate: PinnedHostKeysDelegate = .init(pinnedHostKeys: PTTHostKeys.pttcc)
		let promise = loop.makePromise(of: Void.self)
		delegate.validateHostKey(hostKey: SSHTestKeys.pttEd25519, validationCompletePromise: promise)
		try promise.futureResult.wait()
	}

	/// 內建 pinned 組的 ECDSA key 也命中（協商到哪把由偏好序決定、整組都要可過）。
	@Test
	private func `pinned ecdsa key passes validation`() throws {
		let loop: EmbeddedEventLoop = .init()
		let delegate: PinnedHostKeysDelegate = .init(pinnedHostKeys: PTTHostKeys.pttcc)
		let promise = loop.makePromise(of: Void.self)
		delegate.validateHostKey(hostKey: SSHTestKeys.pttECDSA, validationCompletePromise: promise)
		try promise.futureResult.wait()
	}

	/// 不在 pinned 組的 key → 以 ``PTTConnectionError/hostKeyMismatch`` 拒絕。
	@Test
	private func `unpinned key fails with host key mismatch`() {
		let loop: EmbeddedEventLoop = .init()
		let delegate: PinnedHostKeysDelegate = .init(pinnedHostKeys: PTTHostKeys.pttcc)
		let promise = loop.makePromise(of: Void.self)
		delegate.validateHostKey(hostKey: SSHTestKeys.unrelatedEd25519, validationCompletePromise: promise)
		#expect(throws: PTTConnectionError.hostKeyMismatch) {
			try promise.futureResult.wait()
		}
	}

	/// 注入替代 pinned 組時以注入組為準（站方換鑰 / 測試替身路徑）。
	@Test
	private func `injected pinned set overrides built in keys`() throws {
		let loop: EmbeddedEventLoop = .init()
		let delegate: PinnedHostKeysDelegate = .init(pinnedHostKeys: [SSHTestKeys.unrelatedEd25519])
		let acceptPromise = loop.makePromise(of: Void.self)
		delegate.validateHostKey(hostKey: SSHTestKeys.unrelatedEd25519, validationCompletePromise: acceptPromise)
		try acceptPromise.futureResult.wait()
		let rejectPromise = loop.makePromise(of: Void.self)
		delegate.validateHostKey(hostKey: SSHTestKeys.pttEd25519, validationCompletePromise: rejectPromise)
		#expect(throws: PTTConnectionError.hostKeyMismatch) {
			try rejectPromise.futureResult.wait()
		}
	}
}
