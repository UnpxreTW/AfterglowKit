//
//  PTTSession
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTKeySink

/// 送鍵出口：``PTTSession`` 對外界唯一的寫入抽象。
///
/// Session 只認得這個 sink 與一條 `PTTScreen` 快照流，不持有 `PTTTerminal` 或
/// `PTTConnection` 任何具體型別——編碼與實際傳輸由組裝層接線（同 `PTTConnection`
/// 引擎只依賴 `PTTTransport` 協定的作法）。因此本模組的測試全部餵假 sink、
/// 不對外連線。
public struct PTTKeySink: Sendable {

	/// 送出一串按鍵；實作端負責把 ``PTTKey/text(_:)`` 依 Big5-UAO 編碼後寫進連線。
	public var send: @Sendable ([PTTKey]) async throws -> Void

	/// 以一個送鍵閉包組裝 sink。
	public init(send: @escaping @Sendable ([PTTKey]) async throws -> Void) {
		self.send = send
	}
}
