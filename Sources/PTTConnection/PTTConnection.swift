//
//  PTTConnection
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - PTTConnectionRole

/// 連線角色：slot 仲裁的優先序依據。
public enum PTTConnectionRole: Equatable, Sendable {

	/// 前景互動連線（App / pttcli；`deviceIdentifier` 區分裝置）。前景優先：滿額時踢舊留新、且不被 CLI 搶佔。
	case foreground(deviceIdentifier: String)

	/// 短連線（pttdata 抓資料）：用完即斷、不常駐佔 slot、滿額時讓位給前景。
	case shortLived

	/// 是否前景角色（仲裁分支用）。
	public var isForeground: Bool {
		if case .foreground = self { return true }
		return false
	}
}

// MARK: - PTTConnectionError

/// 連線層錯誤。
public enum PTTConnectionError: Error, Equatable {

	/// 對已關閉的連線送資料。
	case connectionClosed

	/// slot 滿額且無可讓位的連線（短連線請求不搶佔前景）。
	case slotsExhausted
}

// MARK: - PTTConnection

/// 一條活連線的生命週期管理：下行 tap、[Y/n] 自動應答、keepalive、顯式 close。
///
/// 由 ``PTTConnectionEngine`` 建立（slot 配額與頻率閘在引擎層）；本層職責：
/// - 下行 raw bytes 原樣轉發給 ``inbound`` 訂閱者（不解碼、不剝前導——那是下游 codec 的事），
///   同時以 ``DuplicateLoginPromptScanner`` 監看「刪除重複連線 [Y/n]」prompt、
///   命中即自動應答 `Y`（踢舊留新、前景優先），一條連線只應答一次。
/// - 閒置達 keepalive 間隔即送 `ESC OA ESC OB` 載荷（上/下方向鍵、淨效果歸零的
///   client anti-idle 慣例，pttbbs `mbbsd/io.c` 明文承認）。keepalive 只對抗 NAT——
///   站方 OSS 的 in-session idle 踢線是死碼。Citadel 0.12.1 無 SSH transport 層
///   keepalive API（上游 repo 查證），故直接採載荷慣例；上游補 API 後可再降回 transport 層。
/// - 終止一律顯式 `close()`：讀流不響應 task cancellation（實連驗證）、
///   取消讀取任務會永久卡住，只能關 transport 讓流自然結束。
public actor PTTConnection {

	// MARK: Public

	/// 連線狀態。
	public enum State: Equatable, Sendable {

		/// 活連線（佔 1 slot）。
		case active

		/// 已終止（含原因；slot 已釋放）。
		case closed(DisconnectReason)
	}

	/// 連線識別（slot 表鍵）。
	public nonisolated let identifier: UUID = .init()

	/// 連線角色（仲裁依據；建立後不變）。
	public nonisolated let role: PTTConnectionRole

	/// 下行 raw byte 流（Big5-UAO + ANSI 原樣、含 HTTP 前導）；流結束 = 連線終止。
	public nonisolated let inbound: AsyncThrowingStream<[UInt8], any Error>

	/// 目前狀態。
	public private(set) var state: State = .active

	/// 最近一次上/下行流量時刻（LRU 仲裁與 keepalive 排程依據）。
	public private(set) var lastActivity: ContinuousClock.Instant

	/// 上行寫入（鍵盤輸入 / 指令 bytes）；已關閉丟 ``PTTConnectionError/connectionClosed``。
	public func send(_ bytes: [UInt8]) async throws {
		guard case .active = state else { throw PTTConnectionError.connectionClosed }
		try await transport.send(bytes)
		lastActivity = clock.now()
	}

	/// 顯式關閉（冪等）：關 transport 讓讀流自然結束、釋放 slot。
	public func close() async {
		await shutdown(reason: .localClose)
	}

	/// 包裝一條已建立的 transport；由引擎呼叫（`onClose` 回報 slot 釋放）。
	///
	/// - Parameters:
	///   - transport: 已連上的位元組管道。
	///   - role: 連線角色。
	///   - keepaliveInterval: 閒置多久送一次 keepalive 載荷（起始 20 分鐘、依掛機實測收斂調整）。
	///   - clock: 時間來源（測試注入假時鐘）。
	///   - onClose: 終止回呼（引擎釋放 slot、記頻率閘）。
	public init(
		transport: any PTTTransport,
		role: PTTConnectionRole,
		keepaliveInterval: Duration,
		clock: EngineClock,
		onClose: @escaping @Sendable (UUID, DisconnectReason) async -> Void
	) {
		self.transport = transport
		self.role = role
		self.keepaliveInterval = keepaliveInterval
		self.clock = clock
		self.onClose = onClose
		self.lastActivity = clock.now()
		(self.inbound, self.consumer) = AsyncThrowingStream.makeStream(of: [UInt8].self)
		Task { await self.start() }
	}

	// MARK: Private

	/// [Y/n] 自動應答 bytes：`Y` + CR（踢舊留新；CR 兼容行輸入型 prompt 變體，
	/// 單鍵型 prompt 的多餘 CR 由後續畫面吸收）。精確應答行為留待真實登入實測驗證。
	private static let duplicateLoginAnswer: [UInt8] = [0x59, 0x0D]

	/// keepalive 載荷：`ESC OA ESC OB`（上、下方向鍵各一，淨效果歸零）。
	private static let keepalivePayload: [UInt8] = [0x1B, 0x4F, 0x41, 0x1B, 0x4F, 0x42]

	/// 底層位元組管道。
	private let transport: any PTTTransport

	/// keepalive 閒置間隔。
	private let keepaliveInterval: Duration

	/// 時間來源。
	private let clock: EngineClock

	/// 終止回呼（只呼叫一次）。
	private let onClose: @Sendable (UUID, DisconnectReason) async -> Void

	/// 下行轉發的 continuation。
	private let consumer: AsyncThrowingStream<[UInt8], any Error>.Continuation

	/// [Y/n] prompt 掃描器（命中一次後不再比對）。
	private var scanner: DuplicateLoginPromptScanner = .init()

	/// 讀流主迴圈 task（init 尾啟動；shutdown 時取消兜底、正常靠流結束收攤）。
	private var pumpTask: Task<Void, Never>?

	/// keepalive 迴圈 task（init 尾啟動；shutdown 時取消）。
	private var keepaliveTask: Task<Void, Never>?

	/// 啟動背景迴圈（actor-isolated：nonisolated init 不能在 self escape 後存 task、集中到此）。
	private func start() {
		guard case .active = state else { return } // 建立後旋即 close 的 race：不再啟動
		pumpTask = Task { await self.pump() }
		keepaliveTask = Task { await self.keepaliveLoop() }
	}

	/// 讀流主迴圈：轉發下行、監看 [Y/n]、流結束時分類終止原因。
	private func pump() async {
		do {
			for try await chunk in transport.inbound {
				lastActivity = clock.now()
				if scanner.scan(chunk) {
					try? await transport.send(Self.duplicateLoginAnswer)
				}
				consumer.yield(chunk)
			}
			// 對端結束流：週日清晨例行重開窗視為常態、其餘為 serverClose。
			let reason: DisconnectReason =
				MaintenanceWindow.contains(clock.wallClockNow()) ? .routineMaintenance : .serverClose
			await shutdown(reason: reason)
		} catch {
			await shutdown(reason: .failure(String(describing: error)))
		}
	}

	/// keepalive 迴圈：閒置達間隔即送載荷；連線關閉或睡眠被取消即收攤。
	private func keepaliveLoop() async {
		while case .active = state {
			let idle = lastActivity.duration(to: clock.now())
			let remaining = keepaliveInterval - idle
			if remaining <= .zero {
				do {
					try await transport.send(Self.keepalivePayload)
					lastActivity = clock.now()
				} catch {
					return // 送不出去 → 讀流端會收斂到 shutdown
				}
			} else {
				do {
					try await clock.sleep(remaining)
				} catch {
					return // cancelled
				}
			}
		}
	}

	/// 終止收斂點（冪等）：設狀態 → 關 transport → 結束下行流 → 收攤背景 task → 回報引擎。
	private func shutdown(reason: DisconnectReason) async {
		guard case .active = state else { return }
		state = .closed(reason)
		await transport.close()
		consumer.finish()
		keepaliveTask?.cancel()
		if case .localClose = reason {
			pumpTask?.cancel() // 顯式關閉時兜底；流結束路徑上 pump 正是呼叫者、自然收攤
		}
		await onClose(identifier, reason)
	}
}
