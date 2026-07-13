//
//  PTTConnection
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOPosix
import NIOSSH

// MARK: - NIOSSHPTTTransportConnector

/// 架在官方 swift-nio-ssh 上的薄 transport 工廠：對 ``PTTEndpoint`` 建 SSH 連線
/// （none auth + pinned host key）、開 session child channel、送 PTY / shell request，
/// 把 NIO channel 橋接成 ``PTTTransport`` 的 async 位元組介面。
///
/// 演算法組合與 ptt.cc（`SSH-2.0-bbs-sshd`）的交集：KEX `curve25519-sha256`、
/// host key `ssh-ed25519` / `ecdsa-sha2-nistp256`、cipher `aes256-gcm@openssh.com`——
/// 皆在 NIOSSH 內建提案內，逕用預設組、不需自訂演算法面。
public struct NIOSSHPTTTransportConnector: PTTTransportConnector {

	// MARK: Public

	/// 對端點建立一條 SSH PTY 連線；PTY / shell 皆獲 server 確認才回傳。
	///
	/// 失敗一律丟錯（由引擎記入頻率閘）；握手層錯誤（如 host key 驗證被拒）
	/// 優先於 child channel 的間接錯誤回報。
	public func connect(to endpoint: PTTEndpoint) async throws -> any PTTTransport {
		let errorRecorder: SSHConnectionErrorRecordingHandler = .init()
		let bootstrap = makeBootstrap(
			pinnedHostKeys: pinnedHostKeys,
			username: endpoint.username,
			errorRecorder: errorRecorder
		)
		let parentChannel = try await bootstrap.connect(host: endpoint.host, port: endpoint.port).get()
		let (inbound, inboundContinuation) = AsyncThrowingStream.makeStream(of: [UInt8].self)
		let sessionReadyPromise = parentChannel.eventLoop.makePromise(of: Void.self)
		let pseudoTerminalRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
			wantReply: true,
			term: "xterm",
			terminalCharacterWidth: terminalColumnCount,
			terminalRowHeight: terminalRowCount,
			terminalPixelWidth: 0,
			terminalPixelHeight: 0,
			terminalModes: SSHTerminalModes([.ECHO: 1])
		)
		let childChannelFuture = makeChildChannelFuture(
			parentChannel: parentChannel,
			pseudoTerminalRequest: pseudoTerminalRequest,
			sessionReadyPromise: sessionReadyPromise,
			inboundContinuation: inboundContinuation
		)
		// 建立逾時保險：逾時只「關 parent channel」，讓 inactive / handlerRemoved
		// 路徑收攤 ready promise（維持唯一完成者、避免雙完成競態）。
		let setupTimeoutTask = parentChannel.eventLoop.scheduleTask(in: TimeAmount(sessionSetupTimeout)) {
			parentChannel.close(promise: nil)
		}
		do {
			let childChannel = try await childChannelFuture.get()
			try await sessionReadyPromise.futureResult.get()
			setupTimeoutTask.cancel()
			return NIOSSHPTTTransport(parentChannel: parentChannel, childChannel: childChannel, inbound: inbound)
		} catch {
			setupTimeoutTask.cancel()
			parentChannel.close(promise: nil)
			throw errorRecorder.recordedError ?? error
		}
	}

	/// 建立 connector。
	///
	/// - Parameters:
	///   - pinnedHostKeys: 信任的 host key 組（預設 ``PTTHostKeys/pttcc``；
	///     測試或站方換鑰時注入替代組）。
	///   - terminalColumnCount: PTY 窗口寬（字元數；ptt.cc 標準畫面 80 欄）。
	///   - terminalRowCount: PTY 窗口高（列數；ptt.cc 標準畫面 24 列）。
	///   - sessionSetupTimeout: TCP 連上後，握手＋驗證＋PTY／shell 成形的總時限；
	///     逾時強制收線、`connect(to:)` 以錯誤收場（防 server 無回應時呼叫端永久懸置）。
	public init(
		pinnedHostKeys: Set<NIOSSHPublicKey> = PTTHostKeys.pttcc,
		terminalColumnCount: Int = 80,
		terminalRowCount: Int = 24,
		sessionSetupTimeout: Duration = .seconds(30)
	) {
		self.pinnedHostKeys = pinnedHostKeys
		self.terminalColumnCount = terminalColumnCount
		self.terminalRowCount = terminalRowCount
		self.sessionSetupTimeout = sessionSetupTimeout
	}

	// MARK: Private

	/// 信任的 host key 組。
	private let pinnedHostKeys: Set<NIOSSHPublicKey>

	/// PTY 窗口寬（字元數）。
	private let terminalColumnCount: Int

	/// PTY 窗口高（列數）。
	private let terminalRowCount: Int

	/// 會話成形總時限。
	private let sessionSetupTimeout: Duration

	/// 組出對 ``PTTEndpoint`` 建連用的 `ClientBootstrap`：channelInitializer 內就地建構
	/// none-auth 與 pinned-host-key 兩個 delegate、掛上 `NIOSSHHandler` 與錯誤紀錄 handler。
	///
	/// - Note: `SSHClientConfiguration` 與兩個 delegate 皆非 Sendable，只能在
	///   channelInitializer 閉包內就地建構、不可存為 connector 屬性或跨 await 持有。
	private func makeBootstrap(
		pinnedHostKeys: Set<NIOSSHPublicKey>,
		username: String,
		errorRecorder: SSHConnectionErrorRecordingHandler
	) -> ClientBootstrap {
		ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
			.channelInitializer { channel in
				let configuration: SSHClientConfiguration = .init(
					userAuthDelegate: NoneAuthenticationDelegate(username: username),
					serverAuthDelegate: PinnedHostKeysDelegate(pinnedHostKeys: pinnedHostKeys)
				)
				let handler: NIOSSHHandler = .init(
					role: .client(configuration),
					allocator: channel.allocator,
					inboundChildChannelInitializer: nil
				)
				// channelInitializer 保證在 channel 的 event loop 上執行：走 syncOperations
				// 加 handler（future 版 addHandlers 要求 Sendable、NIOSSHHandler 顯式不可）。
				return channel.eventLoop.makeCompletedFuture {
					try channel.pipeline.syncOperations.addHandlers([handler, errorRecorder])
				}
			}
	}

	/// 在 parent channel 的 event loop 上開 session child channel、送 PTY request，
	/// 並把橋接 handler 掛上去。
	///
	/// - Note: `NIOSSHHandler` 顯式非 Sendable：取得與 createChannel 全程留在 parent 的
	///   event loop 上（flatSubmit + syncOperations）、不跨 Sendable 邊界。
	///   橋接 handler 在 loop 上先建構、並為 ready promise 的唯一完成者：
	///   child channel 建立失敗（握手死亡、channel open 被拒）一律經 `abortSetup`
	///   收攤——SSH child channel 與 parent 共用同一 event loop，`phase` 守衛
	///   在單 loop 序列化下保證 promise 單次完成、不留懸置。
	private func makeChildChannelFuture(
		parentChannel: Channel,
		pseudoTerminalRequest: SSHChannelRequestEvent.PseudoTerminalRequest,
		sessionReadyPromise: EventLoopPromise<Void>,
		inboundContinuation: AsyncThrowingStream<[UInt8], Error>.Continuation
	) -> EventLoopFuture<Channel> {
		parentChannel.eventLoop.flatSubmit {
			let bridgeHandler: PTTSessionBridgeHandler = .init(
				pseudoTerminalRequest: pseudoTerminalRequest,
				sessionReadyPromise: sessionReadyPromise,
				inboundContinuation: inboundContinuation
			)
			let childChannelPromise = parentChannel.eventLoop.makePromise(of: Channel.self)
			do {
				let handler = try parentChannel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
				handler.createChannel(childChannelPromise, channelType: .session) { childChannel, _ in
					childChannel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).flatMap {
						childChannel.pipeline.addHandler(bridgeHandler)
					}
				}
			} catch {
				childChannelPromise.fail(error)
			}
			childChannelPromise.futureResult.whenFailure { error in
				bridgeHandler.abortSetup(dueTo: error)
			}
			return childChannelPromise.futureResult
		}
	}

}
