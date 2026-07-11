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

/// 橋接 handler：PTY → shell 建立序列、下行合流、終止語義（EmbeddedChannel 驅動、不連網）。
private final class PTTSessionBridgeHandlerTests {

	/// 測試共用的建立參數（80x24 xterm、與 connector 預設一致）。
	private static let pseudoTerminalRequest: SSHChannelRequestEvent.PseudoTerminalRequest = .init(
		wantReply: true,
		term: "xterm",
		terminalCharacterWidth: 80,
		terminalRowHeight: 24,
		terminalPixelWidth: 0,
		terminalPixelHeight: 0,
		terminalModes: SSHTerminalModes([.ECHO: 1])
	)

	/// 組一條掛好 recorder + 橋接 handler 的 EmbeddedChannel（回傳各觀察點）。
	private static func makeChannel() throws -> (
		channel: EmbeddedChannel,
		recorder: OutboundUserEventRecorder,
		ready: EventLoopFuture<Void>,
		inbound: AsyncThrowingStream<[UInt8], any Error>
	) {
		let channel: EmbeddedChannel = .init()
		let recorder: OutboundUserEventRecorder = .init()
		let readyPromise = channel.eventLoop.makePromise(of: Void.self)
		let (inbound, continuation) = AsyncThrowingStream.makeStream(of: [UInt8].self)
		let bridge: PTTSessionBridgeHandler = .init(
			pseudoTerminalRequest: pseudoTerminalRequest,
			sessionReadyPromise: readyPromise,
			inboundContinuation: continuation
		)
		try channel.pipeline.syncOperations.addHandlers([recorder, bridge])
		return (channel, recorder, readyPromise.futureResult, inbound)
	}

	/// 活化後依序送 PTY、shell request，兩度確認後 ready。
	@Test
	private func `pty then shell then ready on confirmations`() throws {
		let (channel, recorder, ready, _) = try Self.makeChannel()
		try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 22)).wait()
		let ptyRequest = recorder.events.first as? SSHChannelRequestEvent.PseudoTerminalRequest
		#expect(ptyRequest == Self.pseudoTerminalRequest)
		#expect(recorder.events.count == 1) // shell request 須等 PTY 確認、不併發搶跑
		channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
		let shellRequest = recorder.events.dropFirst().first as? SSHChannelRequestEvent.ShellRequest
		#expect(shellRequest == SSHChannelRequestEvent.ShellRequest(wantReply: true))
		channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
		try ready.wait()
		_ = try? channel.finish()
	}

	/// 任一 request 遭 server 拒絕 → ready 以 channelRequestRejected 失敗並收線。
	@Test
	private func `channel failure event fails setup and closes channel`() throws {
		let (channel, _, ready, _) = try Self.makeChannel()
		try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 22)).wait()
		channel.pipeline.fireUserInboundEventTriggered(ChannelFailureEvent())
		#expect(throws: PTTSessionBridgeHandler.SetupFailure.channelRequestRejected) {
			try ready.wait()
		}
		channel.embeddedEventLoop.run()
		#expect(channel.isActive == false)
	}

	/// stdout 與 stderr 位元組合流、原樣 yield 進下行流。
	@Test
	private func `channel and stderr data merge into inbound stream`() async throws {
		let (channel, _, ready, inbound) = try Self.makeChannel()
		try await channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 22)).get()
		channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
		channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
		try await ready.get()
		let standardOutput = channel.allocator.buffer(bytes: [0x61, 0x62])
		let standardError = channel.allocator.buffer(bytes: [0x63])
		try channel.writeInbound(SSHChannelData(type: .channel, data: .byteBuffer(standardOutput)))
		try channel.writeInbound(SSHChannelData(type: .stdErr, data: .byteBuffer(standardError)))
		var iterator = inbound.makeAsyncIterator()
		#expect(try await iterator.next() == [0x61, 0x62])
		#expect(try await iterator.next() == [0x63])
		_ = try? channel.finish()
	}

	/// channel 終止 → 下行流自然結束（流結束 = 連線終止）。
	@Test
	private func `channel inactive finishes inbound stream`() async throws {
		let (channel, _, ready, inbound) = try Self.makeChannel()
		try await channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 22)).get()
		channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
		channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
		try await ready.get()
		try await channel.close().get()
		var iterator = inbound.makeAsyncIterator()
		#expect(try await iterator.next() == nil)
	}

	/// 讀寫錯誤 → 下行流以該錯誤收尾（引擎據此分類 failure 終止原因）。
	@Test
	private func `error caught finishes inbound stream throwing`() async throws {
		struct PipelineFailure: Error {}
		let (channel, _, ready, inbound) = try Self.makeChannel()
		try await channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 22)).get()
		channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
		channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
		try await ready.get()
		channel.pipeline.fireErrorCaught(PipelineFailure())
		var iterator = inbound.makeAsyncIterator()
		await #expect(throws: PipelineFailure.self) {
			_ = try await iterator.next()
		}
		channel.embeddedEventLoop.run()
		#expect(channel.isActive == false)
	}

	/// 會話尚未成形即斷線 → ready 以 closedDuringSetup 失敗（含 connector 逾時強制收線路徑）。
	@Test
	private func `channel inactive during setup fails ready`() throws {
		let (channel, _, ready, _) = try Self.makeChannel()
		try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 22)).wait()
		try channel.close().wait()
		#expect(throws: PTTSessionBridgeHandler.SetupFailure.closedDuringSetup) {
			try ready.wait()
		}
	}

	/// abortSetup（child channel 建立失敗、handler 未進 pipeline）→ ready 失敗、下行流結束。
	@Test
	private func `abort setup fails ready and finishes stream`() async throws {
		struct CreationFailure: Error, Equatable {}
		let loop: EmbeddedEventLoop = .init()
		let readyPromise = loop.makePromise(of: Void.self)
		let (inbound, continuation) = AsyncThrowingStream.makeStream(of: [UInt8].self)
		let bridge: PTTSessionBridgeHandler = .init(
			pseudoTerminalRequest: Self.pseudoTerminalRequest,
			sessionReadyPromise: readyPromise,
			inboundContinuation: continuation
		)
		bridge.abortSetup(dueTo: CreationFailure())
		bridge.abortSetup(dueTo: CreationFailure()) // 重複呼叫不得雙完成 promise
		#expect(throws: CreationFailure()) {
			try readyPromise.futureResult.wait()
		}
		var iterator = inbound.makeAsyncIterator()
		#expect(try await iterator.next() == nil)
	}
}
