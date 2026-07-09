//
//  PTTConnection
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Citadel
import Foundation
import NIOCore
@preconcurrency import NIOSSH // NIOSSHUserAuthenticationOffer 未標 Sendable（前 strict concurrency 時代碼）

// MARK: - CitadelPTTTransportConnector

/// 正式環境的 transport 工廠：Citadel SSH 連線（none auth、80x24 xterm PTY）。
public struct CitadelPTTTransportConnector: PTTTransportConnector {

	/// 建立 SSH 連線並開 PTY；none auth（server 忽略密碼內容、實連驗證通過）。
	///
	/// host key 目前 `acceptAnything`（與實連探針一致）；host key pinning 屬後續強化、非本層現階段範圍。
	public func connect(to endpoint: PTTEndpoint) async throws -> any PTTTransport {
		let settings: SSHClientSettings = .init(
			host: endpoint.host,
			port: endpoint.port,
			authenticationMethod: { .custom(NoneAuthenticationDelegate(username: endpoint.username)) },
			hostKeyValidator: .acceptAnything()
		)
		let client = try await SSHClient.connect(to: settings)
		return CitadelPTTTransport(client: client)
	}

	/// 建立工廠。
	public init() {}
}

// MARK: - NoneAuthenticationDelegate

/// SSH none auth：送 `offer: .none`（Citadel 無內建 `.none` method、走 `.custom` delegate；實連驗證可過）。
private struct NoneAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate {

	/// SSH 層帳號（`bbs` / `bbsu`）。
	let username: String

	/// 一律回 none offer（server 端 bbs-sshd 接受、密碼內容被忽略）。
	func nextAuthenticationType(
		availableMethods: NIOSSHAvailableUserAuthenticationMethods,
		nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
	) {
		nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(username: username, serviceName: "", offer: .none))
	}
}

// MARK: - CitadelPTTTransport

/// Citadel 實作的位元組管道：withPTY session 收在單一背景 task 內，
/// 上下行各走一條 AsyncStream 橋接，`TTYStdinWriter` 不跨出 withPTY 閉包。
///
/// 終止語義（實連驗證）：`TTYOutput` 讀流不響應 task cancellation，
/// 唯一可靠終止是 `client.close()` 讓 channel 關閉、讀流自然結束；
/// close 與 withPTY 內部 close 會 race 出無害的「already closed」錯誤，這裡吞掉。
final class CitadelPTTTransport: PTTTransport {

	/// 包裝一條已連上的 SSH client、開 80x24 xterm PTY session（背景 task 持有整個 withPTY 生命週期）。
	init(client: SSHClient) {
		let clientBox: UncheckedSendableBox = .init(client)
		self.clientBox = clientBox
		let (inboundStream, inboundContinuation) = AsyncThrowingStream.makeStream(of: [UInt8].self)
		let (outboundStream, outboundContinuation) = AsyncStream.makeStream(of: [UInt8].self)
		self.inbound = inboundStream
		self.outboundContinuation = outboundContinuation
		Task {
			do {
				try await clientBox.wrapped.withPTY(Self.ptyRequest) { ttyOutput, writer in
					let writerBox: UncheckedSendableBox = .init(writer)
					try await withThrowingTaskGroup(of: Void.self) { group in
						group.addTask { // 寫迴圈：writer 只在此 task 內使用
							for await bytes in outboundStream {
								try await writerBox.wrapped.write(ByteBuffer(bytes: bytes))
							}
						}
						for try await output in ttyOutput {
							switch output {
							case let .stdout(buffer), let .stderr(buffer):
								inboundContinuation.yield(Array(buffer.readableBytesView))
							}
						}
						group.cancelAll() // 讀流結束 → 收攤寫迴圈
					}
				}
				inboundContinuation.finish()
			} catch {
				inboundContinuation.finish(throwing: error)
			}
			outboundContinuation.finish()
		}
	}

	// MARK: Internal

	/// 下行 raw byte 流（stdout / stderr 合流；PTY 下 server 只走 stdout）。
	let inbound: AsyncThrowingStream<[UInt8], any Error>

	/// 上行寫入：交給 session task 內的寫迴圈（管道已收攤即丟 ``PTTConnectionError/connectionClosed``）。
	func send(_ bytes: [UInt8]) async throws {
		if case .terminated = outboundContinuation.yield(bytes) {
			throw PTTConnectionError.connectionClosed
		}
	}

	/// 顯式關閉（冪等）：收攤寫流 → `client.close()` 讓讀流結束；close race 錯誤吞掉。
	func close() async {
		outboundContinuation.finish()
		do {
			try await clientBox.wrapped.close()
		} catch {
			// 「already closed」race（實連驗證為無害）；其他 close 錯誤此時也無資源可救，一併吞。
		}
	}

	// MARK: Private

	/// PTY 參數：80x24 xterm（尺寸先固定、resize 實測後再參數化）。
	private static var ptyRequest: SSHChannelRequestEvent.PseudoTerminalRequest {
		SSHChannelRequestEvent.PseudoTerminalRequest(
			wantReply: true,
			term: "xterm",
			terminalCharacterWidth: 80,
			terminalRowHeight: 24,
			terminalPixelWidth: 0,
			terminalPixelHeight: 0,
			terminalModes: .init([.ECHO: 1])
		)
	}

	/// SSH client（boxed；close 用）。
	private let clientBox: UncheckedSendableBox<SSHClient>

	/// 上行管道入口。
	private let outboundContinuation: AsyncStream<[UInt8]>.Continuation
}

// MARK: - UncheckedSendableBox

/// Citadel 型別的 Sendable 橋接盒。
///
/// Citadel 0.12.1 是 swift-tools 5.9（前 strict concurrency）時代碼：
/// `SSHClient` / `TTYStdinWriter` 皆未標 Sendable，但其可變狀態由 NIO event loop
/// 綁定管理（`NIOLoopBoundBox`、`Channel` 為 `_NIOPreconcurrencySendable`），
/// 實連探針亦已跨 task 使用實測。上游補 Sendable 標註後可移除此盒。
private struct UncheckedSendableBox<Wrapped>: @unchecked Sendable {

	/// 包一層。
	init(_ wrapped: Wrapped) {
		self.wrapped = wrapped
	}

	/// 被包裝的值。
	let wrapped: Wrapped
}
