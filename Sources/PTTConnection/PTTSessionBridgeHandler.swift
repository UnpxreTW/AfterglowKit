//
//  PTTConnection
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOSSH

// MARK: - PTTSessionBridgeHandler

/// session child channel 尾端的橋接 handler：建立 PTY 會話、把 NIO 事件翻成 async 位元組流。
///
/// - 會話建立：`channelActive` 送 PTY request，收到 server 成功回覆再送 shell request、
///   再成功即 succeed `sessionReadyPromise`。成敗判定監聽 ``ChannelSuccessEvent`` /
///   ``ChannelFailureEvent``（channel request 的回覆序與請求序一致），
///   不依賴 `triggerUserOutboundEvent` future 的完成時機語義。
/// - 下行橋接：`.channel`（stdout）與 `.stdErr`（extended data）合流 yield 進 inbound 流，
///   與引擎既有的合流行為一致；`channelInactive` 結束流、`errorCaught` 以錯誤結束流——
///   唯會話成形後的 `NIOSSHError` `tcpShutdown` 正規化為 clean finish（見 ``errorCaught(context:error:)``）。
/// - 內部狀態只在單一 event loop 的 pipeline 回呼內讀寫、不跨界，無需同步。
///
/// - Important: `@unchecked Sendable` 的成立前提＝單 event loop confinement：可變狀態
///   （`phase`）只在 pipeline 回呼與 ``abortSetup(dueTo:)`` 觸碰、兩者皆保證在 channel
///   所屬 loop 上執行；標註只為讓 handler 能被同 loop 的 `@Sendable` 閉包
///   （setOption 鏈、`whenFailure`）捕獲，不表示可跨執行緒使用。
final class PTTSessionBridgeHandler: ChannelInboundHandler, @unchecked Sendable {

	// MARK: Lifecycle

	/// 以會話參數與橋接出口建立 handler。
	///
	/// - Parameters:
	///   - pseudoTerminalRequest: PTY request 事件（term / 窗口尺寸由 connector 參數化）。
	///   - sessionReadyPromise: PTY + shell 皆獲 server 確認時 succeed；建立途中失敗即 fail。
	///     本 handler 是 promise 的唯一完成者（`phase` 守衛單次完成；`handlerRemoved` 與
	///     ``abortSetup(dueTo:)`` 兜底、確保任何路徑都不留懸置 promise）。
	///   - inboundContinuation: 下行位元組流入口。
	init(
		pseudoTerminalRequest: SSHChannelRequestEvent.PseudoTerminalRequest,
		sessionReadyPromise: EventLoopPromise<Void>,
		inboundContinuation: AsyncThrowingStream<[UInt8], any Error>.Continuation
	) {
		self.pseudoTerminalRequest = pseudoTerminalRequest
		self.sessionReadyPromise = sessionReadyPromise
		self.inboundContinuation = inboundContinuation
	}

	// MARK: Internal

	typealias InboundIn = SSHChannelData

	/// 會話建立途中的失敗原因。
	enum SetupFailure: Error, Equatable {

		/// server 對 PTY 或 shell request 回覆失敗。
		case channelRequestRejected

		/// 會話尚未成形 channel 即關閉（含 connector 的建立逾時強制收線）。
		case closedDuringSetup
	}

	/// channel 活化：送出 PTY request、啟動建立序列。
	func channelActive(context: ChannelHandlerContext) {
		context.triggerUserOutboundEvent(pseudoTerminalRequest, promise: nil)
		context.fireChannelActive()
	}

	/// server 對 channel request 的成敗回覆：推進 PTY → shell → ready 的建立序列。
	func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
		switch event {
		case is ChannelSuccessEvent:
			advanceSetup(context: context)
		case is ChannelFailureEvent:
			failSetup(SetupFailure.channelRequestRejected)
			context.close(promise: nil)
		default:
			context.fireUserInboundEventTriggered(event)
		}
	}

	/// 下行資料：stdout 與 stderr 合流 yield（原樣位元組、不解碼不剝前導）。
	func channelRead(context: ChannelHandlerContext, data: NIOAny) {
		let channelData = unwrapInboundIn(data)
		// !!!: NIOSSH 下行恆為 byteBuffer（fileRegion 僅屬出站最佳化），此 guard 不可達、防禦性略過。
		guard case let .byteBuffer(buffer) = channelData.data else { return }
		if channelData.type == .channel || channelData.type == .stdErr {
			inboundContinuation.yield(Array(buffer.readableBytesView))
		}
	}

	/// channel 終止：建立未完成則 fail ready，並結束下行流（流結束 = 連線終止）。
	func channelInactive(context: ChannelHandlerContext) {
		failSetup(SetupFailure.closedDuringSetup)
		inboundContinuation.finish()
		context.fireChannelInactive()
	}

	/// 讀寫錯誤：建立未完成則 fail ready，下行流以錯誤收尾並關閉 channel。
	///
	/// 唯一例外：**會話成形後**的 `NIOSSHError` `tcpShutdown` 正規化為 clean finish——
	/// parent TCP 收線時 NIOSSH 對尚未關閉的 child 一律打此錯誤（顯式 `close()` 與對端
	/// 斷線同一路徑），而 bbs-sshd 斷線本就不做 SSH 層 clean close，屬正常連線終止形態、
	/// 不得讓引擎誤分類為故障（實連驗證：`close()` 後 inbound 曾以此錯誤結束）。
	/// 會話未成形時不套用：連線建立失敗須以錯誤回報呼叫端。
	func errorCaught(context: ChannelHandlerContext, error: any Error) {
		failSetup(error) // 只在建立中把 phase 推向 failed、不會動 ready——其後以 phase 判會話是否已成形
		if phase == .ready, let sshError = error as? NIOSSHError, sshError.type == .tcpShutdown {
			inboundContinuation.finish()
		} else {
			inboundContinuation.finish(throwing: error)
		}
		context.close(promise: nil)
	}

	/// pipeline 拆除兜底：確保 ready promise 與下行流在任何路徑都被收攤（不留懸置 promise）。
	func handlerRemoved(context: ChannelHandlerContext) {
		failSetup(SetupFailure.closedDuringSetup)
		inboundContinuation.finish()
	}

	/// 建立中止（connector 於 child channel 建立失敗時呼叫；handler 可能從未進 pipeline）。
	///
	/// 必須在 channel 所屬的 event loop 上呼叫——與 pipeline 回呼共用 `phase` 守衛、
	/// 同 loop 序列化保證 ready promise 單次完成。
	func abortSetup(dueTo error: any Error) {
		failSetup(error)
		inboundContinuation.finish()
	}

	// MARK: Private

	/// 會話建立進度（channel request 回覆依請求序到達、單向推進）。
	private enum SetupPhase {

		/// 等 PTY request 回覆。
		case awaitingPseudoTerminalReply

		/// 等 shell request 回覆。
		case awaitingShellReply

		/// 會話已成形（ready promise 已 succeed）。
		case ready

		/// 建立失敗（ready promise 已 fail）。
		case failed
	}

	/// PTY request 事件（connector 組好整顆傳入）。
	private let pseudoTerminalRequest: SSHChannelRequestEvent.PseudoTerminalRequest

	/// 會話成形 promise（succeed / fail 各僅一次、由 `phase` 守衛）。
	private let sessionReadyPromise: EventLoopPromise<Void>

	/// 下行位元組流入口（`finish` 冪等、可安心在多個終止路徑呼叫）。
	private let inboundContinuation: AsyncThrowingStream<[UInt8], any Error>.Continuation

	/// 建立進度；只在 event loop 回呼內讀寫。
	private var phase: SetupPhase = .awaitingPseudoTerminalReply

	/// 收到一次成功回覆：PTY 確認後送 shell request、shell 確認後宣告 ready。
	private func advanceSetup(context: ChannelHandlerContext) {
		switch phase {
		case .awaitingPseudoTerminalReply:
			phase = .awaitingShellReply
			context.triggerUserOutboundEvent(SSHChannelRequestEvent.ShellRequest(wantReply: true), promise: nil)
		case .awaitingShellReply:
			phase = .ready
			sessionReadyPromise.succeed(())
		case .ready, .failed:
			break // 本層不再發 request、多餘的成功回覆防禦性忽略
		}
	}

	/// 建立未完成時以指定錯誤收攤 ready promise（已定案則為 no-op、保證單次完成）。
	private func failSetup(_ error: any Error) {
		switch phase {
		case .awaitingPseudoTerminalReply, .awaitingShellReply:
			phase = .failed
			sessionReadyPromise.fail(error)
		case .ready, .failed:
			break
		}
	}
}
