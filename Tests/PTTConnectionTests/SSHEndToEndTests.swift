//
//  PTTConnectionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTConnection
import Crypto
import NIOCore
import NIOEmbedded
import NIOSSH
import Testing

/// in-process SSH 端對端：client / server 雙 `NIOSSHHandler` 以 EmbeddedChannel 對倒 bytes
/// 完成真實握手（KEX、none auth、PTY / shell），驗證會話成形後的下行資料鏈路與
/// TCP 收線終止語義（不連網；`tcpShutdown` 為真 NIOSSH 產物、非測試替身——該錯誤型別無 public init）。
private final class SSHEndToEndTests {

	/// server 端測試 auth delegate：接受任何 none 請求（重現 bbs-sshd 的 none auth 行為）。
	private final class AcceptAnyNoneAuthenticationDelegate: NIOSSHServerUserAuthenticationDelegate {

		/// 名目宣告 password（none 請求不受此集合限制、一律進 delegate）。
		let supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods = .password

		/// none 請求一律成功、其餘拒絕。
		func requestReceived(
			request: NIOSSHUserAuthenticationRequest,
			responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>
		) {
			if case .none = request.request {
				responsePromise.succeed(.success)
			} else {
				responsePromise.succeed(.failure)
			}
		}
	}

	/// server 端 session handler：對 PTY / shell request 一律回覆成功（重現 bbs-sshd 的會話建立）。
	private final class ApprovingSessionHandler: ChannelInboundHandler {

		typealias InboundIn = SSHChannelData

		/// 對 PTY / shell request 回 `ChannelSuccessEvent`（回覆序與請求序一致）。
		func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
			switch event {
			case is SSHChannelRequestEvent.PseudoTerminalRequest, is SSHChannelRequestEvent.ShellRequest:
				context.channel.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil)
			default:
				context.fireUserInboundEventTriggered(event)
			}
		}
	}

	/// server 端 child channel 的捕捉盒（initializer 回呼與測試本體間的交接；單 loop 同步、不跨界）。
	private final class ChannelBox {

		/// 捕捉到的 channel。
		var channel: (any Channel)?
	}

	/// 已成形的 in-process 會話（真實握手完成、PTY / shell 已獲 server 確認）。
	private struct EstablishedSession {

		/// client 端 parent channel（TCP 替身；收線測試的作用點）。
		let clientParent: EmbeddedChannel

		/// server 端 parent channel。
		let serverParent: EmbeddedChannel

		/// 受測 transport（架在 client 端 channel 上）。
		let transport: NIOSSHPTTTransport

		/// transport 下行流。
		let inbound: AsyncThrowingStream<[UInt8], any Error>

		/// server 端 session child channel（下行資料的寫入點）。
		let serverChild: any Channel
	}

	/// 會話建立途中的 harness 失敗（server child 未成形等）。
	private struct SessionSetupFailure: Error {}

	/// 對倒兩端 outbound bytes 直到雙向靜默（EmbeddedEventLoop 上所有回呼同步完成）。
	private static func interact(_ client: EmbeddedChannel, _ server: EmbeddedChannel) throws {
		var transferred = true
		while transferred {
			transferred = false
			client.embeddedEventLoop.run()
			server.embeddedEventLoop.run()
			if let bytes = try client.readOutbound(as: ByteBuffer.self) {
				try server.writeInbound(bytes)
				transferred = true
			}
			if let bytes = try server.readOutbound(as: ByteBuffer.self) {
				try client.writeInbound(bytes)
				transferred = true
			}
		}
	}

	/// 建立完成真實握手與 PTY / shell 會話的 in-process 連線。
	///
	/// client 側重用正式碼的 ``NoneAuthenticationDelegate`` 與 ``PinnedHostKeysDelegate``
	/// （pin 對 in-process server 的臨時 host key）、child channel 組法與 connector 一致
	/// （allowRemoteHalfClosure + 橋接 handler），只把 TCP 換成 EmbeddedChannel 對倒。
	private static func makeEstablishedSession() throws -> EstablishedSession {
		let serverKey: NIOSSHPrivateKey = .init(ed25519Key: .init())
		let clientParent: EmbeddedChannel = .init()
		let serverParent: EmbeddedChannel = .init()
		let serverChildBox: ChannelBox = .init()
		let serverHandler: NIOSSHHandler = .init(
			role: .server(SSHServerConfiguration(
				hostKeys: [serverKey],
				userAuthDelegate: AcceptAnyNoneAuthenticationDelegate()
			)),
			allocator: serverParent.allocator,
			inboundChildChannelInitializer: { childChannel, _ in
				serverChildBox.channel = childChannel
				return childChannel.pipeline.addHandler(ApprovingSessionHandler())
			}
		)
		let clientHandler: NIOSSHHandler = .init(
			role: .client(SSHClientConfiguration(
				userAuthDelegate: NoneAuthenticationDelegate(username: "bbs"),
				serverAuthDelegate: PinnedHostKeysDelegate(pinnedHostKeys: [serverKey.publicKey])
			)),
			allocator: clientParent.allocator,
			inboundChildChannelInitializer: nil
		)
		try serverParent.pipeline.syncOperations.addHandler(serverHandler)
		try clientParent.pipeline.syncOperations.addHandler(clientHandler)
		try serverParent.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 2222)).wait()
		try clientParent.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 22)).wait()
		try interact(clientParent, serverParent) // 版本交換 → KEX → none auth
		let readyPromise = clientParent.eventLoop.makePromise(of: Void.self)
		let (inbound, continuation) = AsyncThrowingStream.makeStream(of: [UInt8].self)
		let bridge: PTTSessionBridgeHandler = .init(
			pseudoTerminalRequest: .init(
				wantReply: true,
				term: "xterm",
				terminalCharacterWidth: 80,
				terminalRowHeight: 24,
				terminalPixelWidth: 0,
				terminalPixelHeight: 0,
				terminalModes: SSHTerminalModes([.ECHO: 1])
			),
			sessionReadyPromise: readyPromise,
			inboundContinuation: continuation
		)
		let childPromise = clientParent.eventLoop.makePromise(of: Channel.self)
		clientHandler.createChannel(childPromise, channelType: .session) { childChannel, _ in
			childChannel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).flatMap {
				childChannel.pipeline.addHandler(bridge)
			}
		}
		try interact(clientParent, serverParent) // channel open → PTY → shell 往返
		let clientChild = try childPromise.futureResult.wait()
		try readyPromise.futureResult.wait()
		guard let serverChild = serverChildBox.channel else { throw SessionSetupFailure() }
		let transport: NIOSSHPTTTransport = .init(
			parentChannel: clientParent,
			childChannel: clientChild,
			inbound: inbound
		)
		return EstablishedSession(
			clientParent: clientParent,
			serverParent: serverParent,
			transport: transport,
			inbound: inbound,
			serverChild: serverChild
		)
	}

	/// 真實握手 + 會話成形後，server 下行 bytes 原樣抵達 transport inbound（資料鏈路全程過機）。
	@Test
	private func `server bytes reach transport inbound`() async throws {
		let session = try Self.makeEstablishedSession()
		let payload = session.serverChild.allocator.buffer(bytes: [0xA1, 0x40, 0x0D])
		try session.serverChild.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(payload))).wait()
		try Self.interact(session.clientParent, session.serverParent)
		var iterator = session.inbound.makeAsyncIterator()
		#expect(try await iterator.next() == [0xA1, 0x40, 0x0D])
		_ = try? session.clientParent.finish()
		_ = try? session.serverParent.finish()
	}

	/// 顯式 `close()` 收 parent TCP 後，NIOSSH 對 child 打 `tcpShutdown`——
	/// inbound 須 clean 結束、不得以錯誤收尾（正常關線非故障；實連曾誤以錯誤結束、此為回歸釘點）。
	@Test
	private func `local close ends inbound cleanly`() async throws {
		let session = try Self.makeEstablishedSession()
		await session.transport.close()
		session.clientParent.embeddedEventLoop.run()
		var iterator = session.inbound.makeAsyncIterator()
		#expect(try await iterator.next() == nil)
	}

	/// transport → 連線層串接：對端 TCP 斷線（與顯式 close 同一 `tcpShutdown` 路徑）
	/// 分類為 ``DisconnectReason/serverClose``、不誤判 ``DisconnectReason/failure(_:)``。
	@Test
	private func `remote drop classifies as server close`() async throws {
		let session = try Self.makeEstablishedSession()
		let clock: TestClock = .init()
		let connection: PTTConnection = .init(
			transport: session.transport,
			role: .foreground(deviceIdentifier: "endtoend"),
			keepaliveInterval: .seconds(20 * 60),
			clock: clock.engineClock,
			onClose: { _, _ in }
		)
		session.clientParent.pipeline.fireChannelInactive()
		let converged = await advanceUntil(clock) {
			await connection.state == .closed(.serverClose)
		}
		#expect(converged)
	}

}
