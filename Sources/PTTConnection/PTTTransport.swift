//
//  PTTConnection
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - PTTEndpoint

/// SSH 連線端點：host / port / SSH username。
///
/// username 是 SSH 層帳號（`bbs` = Big5、`bbsu` = UTF-8 debug 對照），
/// 不是 PTT 使用者帳號——後者在 BBS 登入畫面內輸入、屬 Session 層職責。
public struct PTTEndpoint: Equatable, Sendable {

	/// 全程 Big5-UAO 的正式入口 `bbs@ptt.cc:22`。
	public static let bbs: PTTEndpoint = .init(username: "bbs")

	/// UTF-8 debug 對照入口 `bbsu@ptt.cc:22`（僅對照驗證用、有損轉碼不可作正本）。
	public static let bbsu: PTTEndpoint = .init(username: "bbsu")

	/// SSH 主機名。
	public let host: String

	/// SSH port。
	public let port: Int

	/// SSH 層登入帳號（`bbs` / `bbsu`；server 接受 none auth、密碼內容被忽略）。
	public let username: String

	/// 建立端點；預設指向 ptt.cc:22。
	public init(host: String = "ptt.cc", port: Int = 22, username: String = "bbs") {
		self.host = host
		self.port = port
		self.username = username
	}
}

// MARK: - PTTTransport

/// 一條已建立的 SSH PTY 位元組管道抽象。
///
/// 引擎邏輯（slot 仲裁 / 頻率閘 / prompt 應答 / keepalive）只依賴此協定，
/// 真實網路走具體 transport 實作（consumer 注入）、單元測試注入 fake——引擎測試永不連真站
/// （PTT 封鎖雲端機房 IP，CI 上連線必失敗且屬對外行為）。
public protocol PTTTransport: Sendable {

	/// 下行 raw byte 流（Big5-UAO + ANSI 原樣、含 HTTP 前導——前導由下游
	/// `StreamTranscoder` 剝除，本層不剝、避免雙剝）。流結束 = 連線終止。
	var inbound: AsyncThrowingStream<[UInt8], any Error> { get }

	/// 上行寫入 raw bytes（鍵盤輸入 / prompt 應答）。
	func send(_ bytes: [UInt8]) async throws

	/// 顯式關閉連線並釋放底層資源。必須冪等；實作須吞關閉 race 的
	/// 「already closed」類錯誤（實連驗證：讀流不響應 cancellation、終止只能走顯式 close）。
	func close() async
}

// MARK: - PTTTransportConnector

/// 建立 ``PTTTransport`` 的工廠抽象；引擎經此連線，測試注入 fake connector。
public protocol PTTTransportConnector: Sendable {

	/// 對端點建立一條 SSH PTY 連線。失敗丟錯、由引擎記入頻率閘。
	func connect(to endpoint: PTTEndpoint) async throws -> any PTTTransport
}
