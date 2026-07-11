//
//  PTTConnection
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation
import NIOCore

// MARK: - SSHConnectionErrorRecordingHandler

/// parent channel 尾端的錯誤記錄 handler：留住第一個握手 / 傳輸層錯誤。
///
/// 握手層失敗（如 host key 驗證被拒）發生在 parent pipeline，child channel 的建立
/// future 只會看到「channel 已關」類的間接錯誤；connector 於連線失敗時改拋本 handler
/// 記到的第一個錯誤，讓 ``PTTConnectionError/hostKeyMismatch`` 等安全訊號不被吞成通用錯誤。
final class SSHConnectionErrorRecordingHandler: ChannelInboundHandler, @unchecked Sendable {

	// MARK: Internal

	typealias InboundIn = Any

	/// 記到的第一個錯誤；無錯誤為 `nil`。
	var recordedError: (any Error)? {
		lock.lock()
		defer { lock.unlock() }
		return firstError
	}

	/// 記錄第一個錯誤並收線（NIOSSH 多數錯誤路徑已自行關閉、close 冪等兜底）。
	func errorCaught(context: ChannelHandlerContext, error: any Error) {
		record(error)
		context.close(promise: nil)
	}

	// MARK: Private

	/// 保護 `firstError`。
	// !!!: 寫入只發生在 event loop、讀取在 connector 的呼叫端 task——跨執行緒讀寫故仍需鎖。
	private let lock: NSLock = .init()

	/// 第一個錯誤。
	private var firstError: (any Error)?

	/// 同步記錄（只留第一個；後續錯誤多為第一個錯誤的連鎖、資訊量低）。
	private func record(_ error: any Error) {
		lock.lock()
		defer { lock.unlock() }
		if firstError == nil {
			firstError = error
		}
	}
}
