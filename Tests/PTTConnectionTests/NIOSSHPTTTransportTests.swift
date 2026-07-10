//
//  PTTConnectionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTConnection
import NIOCore
import NIOEmbedded
import NIOSSH
import Testing

/// transport 本體：上行寫入包裝、關閉語義（EmbeddedChannel 替身、不連網）。
private final class NIOSSHPTTTransportTests {

	/// 讓 write 以指定錯誤失敗的 outbound handler（重現關閉後寫入的失敗形態）。
	private final class WriteFailingHandler: ChannelOutboundHandler {

		/// 下一次 write 要失敗的錯誤。
		var error: ChannelError = .ioOnClosedChannel

		/// 以 `error` fail 掉寫入 promise、不往 head 轉發。
		func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
			promise?.fail(error)
		}

		// MARK: Internal

		typealias OutboundIn = SSHChannelData
		typealias OutboundOut = SSHChannelData
	}

	/// 組一顆 parent / child 皆為 EmbeddedChannel 的 transport（child 先行 activate 供寫入）。
	private static func makeTransport() throws -> (
		transport: NIOSSHPTTTransport,
		parent: EmbeddedChannel,
		child: EmbeddedChannel
	) {
		let parent: EmbeddedChannel = .init()
		let child: EmbeddedChannel = .init()
		try parent.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 22)).wait()
		try child.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 22)).wait()
		let (inbound, _) = AsyncThrowingStream.makeStream(of: [UInt8].self)
		let transport: NIOSSHPTTTransport = .init(parentChannel: parent, childChannel: child, inbound: inbound)
		return (transport, parent, child)
	}

	/// send → 包成 `.channel` 型 SSHChannelData 直寫 child channel。
	@Test
	private func `send writes channel data to child channel`() async throws {
		let (transport, _, child) = try Self.makeTransport()
		try await transport.send([0x59, 0x0D])
		let written = try child.readOutbound(as: SSHChannelData.self)
		let expected = child.allocator.buffer(bytes: [0x59, 0x0D])
		#expect(written == SSHChannelData(type: .channel, data: .byteBuffer(expected)))
	}

	/// 寫入以「channel 已關」類錯誤失敗 → send 映射為 ``PTTConnectionError/connectionClosed``。
	///
	/// EmbeddedChannel 不模擬關閉後寫入失敗（`write0` 無條件成功），以注入的
	/// outbound handler 重現真實 channel 的失敗形態、驗證映射層；其他錯誤原樣透傳。
	@Test
	private func `send maps closed channel errors to connection closed`() async throws {
		let (transport, _, child) = try Self.makeTransport()
		let failure: WriteFailingHandler = .init()
		try child.pipeline.syncOperations.addHandler(failure, position: .first)
		failure.error = ChannelError.ioOnClosedChannel
		await #expect(throws: PTTConnectionError.connectionClosed) {
			try await transport.send([0x59])
		}
		failure.error = ChannelError.alreadyClosed
		await #expect(throws: PTTConnectionError.connectionClosed) {
			try await transport.send([0x59])
		}
		failure.error = ChannelError.outputClosed
		await #expect(throws: ChannelError.outputClosed) {
			try await transport.send([0x59])
		}
	}

	/// close 關 parent channel、且冪等（重複呼叫吞 already-closed race）。
	@Test
	private func `close shuts parent channel and is idempotent`() async throws {
		let (transport, parent, _) = try Self.makeTransport()
		await transport.close()
		parent.embeddedEventLoop.run()
		#expect(parent.isActive == false)
		await transport.close() // 第二次不得丟錯或當機
	}
}
