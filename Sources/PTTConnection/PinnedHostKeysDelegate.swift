//
//  PTTConnection
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOSSH

// MARK: - PinnedHostKeysDelegate

/// host key 驗證 delegate：只信 pinned 組、整把 key 精確比對。
///
/// `NIOSSHPublicKey` 的等值比較以 key 原始位元組表示進行，比 fingerprint 字串比對更強
/// （無雜湊碰撞面）。未命中即拒絕：host key mismatch 是安全訊號（可能 MITM 或站方換鑰）
/// 而非暫時性網路錯誤；重試節奏由引擎層頻率閘統一管制、本層不加特例。
final class PinnedHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {

	// MARK: Lifecycle

	/// 以 pinned 組建立 delegate。
	init(pinnedHostKeys: Set<NIOSSHPublicKey>) {
		self.pinnedHostKeys = pinnedHostKeys
	}

	// MARK: Internal

	/// 命中 pinned 組即信任；未命中以 ``PTTConnectionError/hostKeyMismatch`` 拒絕、中止握手。
	func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
		if pinnedHostKeys.contains(hostKey) {
			validationCompletePromise.succeed(())
		} else {
			validationCompletePromise.fail(PTTConnectionError.hostKeyMismatch)
		}
	}

	// MARK: Private

	/// 信任的 host key 組。
	private let pinnedHostKeys: Set<NIOSSHPublicKey>
}
