//
//  PTTConnection
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOSSH

// MARK: - NIOSSHPTTTransport

/// 架在 swift-nio-ssh 上的 ``PTTTransport``：一條已成形的 SSH PTY 位元組管道。
///
/// 由 ``NIOSSHPTTTransportConnector`` 建立（PTY / shell 已獲 server 確認才交付）。
/// 上行直寫 child channel（`Channel` 為 Sendable、write 自任意執行緒呼叫會自動 hop 回
/// event loop，不需要額外的寫迴圈 task）；下行流由 ``PTTSessionBridgeHandler`` 驅動。
final class NIOSSHPTTTransport: PTTTransport, Sendable {

	// MARK: Lifecycle

	/// 包裝一組已成形的 SSH channel。
	///
	/// - Parameters:
	///   - parentChannel: SSH 連線本體（顯式 close 的作用對象；關閉時 child 隨之終止）。
	///   - childChannel: session child channel（上行寫入的作用對象）。
	///   - inbound: 由橋接 handler 驅動的下行位元組流。
	init(parentChannel: any Channel, childChannel: any Channel, inbound: AsyncThrowingStream<[UInt8], any Error>) {
		self.parentChannel = parentChannel
		self.childChannel = childChannel
		self.inbound = inbound
	}

	// MARK: Internal

	let inbound: AsyncThrowingStream<[UInt8], any Error>

	/// 上行寫入 raw bytes；channel 已關以 ``PTTConnectionError/connectionClosed`` 回報（維持協定語義）。
	func send(_ bytes: [UInt8]) async throws {
		let buffer = childChannel.allocator.buffer(bytes: bytes)
		let channelData: SSHChannelData = .init(type: .channel, data: .byteBuffer(buffer))
		do {
			try await childChannel.writeAndFlush(channelData).get()
		} catch let error as ChannelError where error == .ioOnClosedChannel || error == .alreadyClosed {
			throw PTTConnectionError.connectionClosed
		}
	}

	/// 顯式關閉（冪等）：關 parent channel、child 隨之 inactive、下行流自然結束；
	/// 關閉 race 的「already closed」類錯誤依協定要求吞掉。
	func close() async {
		try? await parentChannel.close().get()
	}

	// MARK: Private

	/// SSH 連線本體。
	private let parentChannel: any Channel

	/// session child channel。
	private let childChannel: any Channel
}
