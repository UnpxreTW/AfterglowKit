//
//  PTTConnectionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTConnection
import NIOCore
import NIOSSH

// MARK: - OutboundUserEventRecorder

/// 記錄流經 pipeline 的 outbound user event（PTY / shell request 發送序斷言用）。
///
/// outbound 事件自觸發點往 head 傳播——本 handler 須加在受測 handler 之前（head 側）才收得到。
/// 只在 `EmbeddedChannel` 單執行緒情境使用、不跨界。
final class OutboundUserEventRecorder: ChannelOutboundHandler {

	/// 依序記到的 outbound user event。
	private(set) var events: [Any] = []

	/// 記錄事件並照常向 head 轉發。
	func triggerUserOutboundEvent(context: ChannelHandlerContext, event: Any, promise: EventLoopPromise<Void>?) {
		events.append(event)
		context.triggerUserOutboundEvent(event, promise: promise)
	}

	// MARK: Internal

	typealias OutboundIn = SSHChannelData
	typealias OutboundOut = SSHChannelData
}

// MARK: - SSHTestKeys

/// 測試用 host key 材料。
enum SSHTestKeys {

	/// ptt.cc 的 ed25519 host key（與內建 pinned 組同源；pin 命中路徑用）。
	static let pttEd25519 = makeKey(
		"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDqjN1kJZrgrY6skGqVGT/JHeoZRuTlnRO38IUKEzaW0"
	)

	/// ptt.cc 的 ECDSA P-256 host key（pin 命中路徑用）。
	static let pttECDSA = makeKey(
		// swiftlint:disable:next line_length
		"ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBF2BVrQ8abQ5CEeUEfUybHXFlaFkLwWBfiLN53KnTGyTpJbUCrpTTPHIr325IaKhed+Lx2POwrDwpga8USPBoqc="
	)

	/// 測試專用的無關 ed25519 key（離線產生、無對應真實主機；pin 未命中路徑用）。
	static let unrelatedEd25519 = makeKey(
		"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBX07CBTcA6jGjYCKV+7kEVmX0qwDgYj2K1SV6jbUpKc"
	)

	/// 解析 OpenSSH 公鑰字面值（測試常數、解析失敗直接斷言終止）。
	private static func makeKey(_ openSSHPublicKey: String) -> NIOSSHPublicKey {
		guard let key = try? NIOSSHPublicKey(openSSHPublicKey: openSSHPublicKey) else {
			preconditionFailure("測試 host key 字面值不合法：\(openSSHPublicKey)")
		}
		return key
	}
}
