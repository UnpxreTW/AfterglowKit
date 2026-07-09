//
//  PTTConnection
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - PTTConnectionEngine

/// 連線引擎：slot 配額仲裁與登入頻率閘的單一正本。
///
/// 生命週期狀態機（每條連線）：
/// 背景 / 無連線（不佔 slot）→ 頻率閘 → SSH connect + none auth 登入 →
/// [Y/n] prompt 踢舊留新（連線層自動應答）→ Active（佔 1 slot、keepalive）→
/// 顯式 close 釋放 slot。
///
/// 仲裁政策：
/// - 同帳號穩態上限 **3 slot**（mbbsd `multi_user_check()`：新連線寫 utmp 前檢查）。
/// - **前景優先 + LRU 釋放**：前景請求滿額時踢最久沒動的連線讓位（先挑非前景、都前景才踢 LRU 前景）。
/// - **CLI 走短連線**：不保留固定 slot；滿額時只讓位非前景、絕不搶佔前景，
///   無位可讓丟 ``PTTConnectionError/slotsExhausted``。
/// - 頻率閘：連線前等 ``LoginFrequencyGate`` 放行；connect 失敗或建立後
///   ``Configuration/earlyDropWindow`` 內被對端斷線，保守記一次被拒（下次 ≥30s）。
public actor PTTConnectionEngine {

	// MARK: Public

	/// 引擎組態。
	public struct Configuration: Sendable {

		/// 連線端點（預設 `bbs@ptt.cc:22`）。
		public var endpoint: PTTEndpoint = .bbs

		/// 同帳號 slot 上限（站方穩態上限 3 條；不可調高、只供測試調低）。
		public var maximumSlots = 3

		/// keepalive 閒置間隔（起始 20 分鐘、依掛機實測收斂調整）。
		public var keepaliveInterval: Duration = .seconds(20 * 60)

		/// 早夭窗：建立後多久內被對端斷線視同被拒（server 拒登入時 sleep 30s 才斷線，取 60s 涵蓋）。
		public var earlyDropWindow: Duration = .seconds(60)

		/// 預設組態。
		public init() {}
	}

	/// 目前佔用中的 slot 數（活連線；不含仲裁中的保留位）。
	public var activeConnectionCount: Int { slots.count }

	/// 建立一條連線：騰位（仲裁）→ 頻率閘 → connect → 佔 slot。
	///
	/// - Parameter role: 連線角色；決定滿額時的讓位規則。
	/// - Returns: 活連線（呼叫端負責在轉背景 / 用畢時顯式 `close()`——前景連背景斷）。
	public func connect(role: PTTConnectionRole) async throws -> PTTConnection {
		try await makeRoom(for: role)
		reservedSlots += 1
		defer { reservedSlots -= 1 }
		while true { // 閘後重查：等待期間其他連線可能又記了嘗試
			let delay = gate.requiredDelay(now: clock.now())
			if delay <= .zero { break }
			try await clock.sleep(delay)
		}
		gate.recordAttempt(at: clock.now())
		let transport: any PTTTransport
		do {
			transport = try await connector.connect(to: configuration.endpoint)
		} catch {
			gate.recordRejection(at: clock.now()) // 連不上保守視為被拒（backoff ≥30s、不 hammer）
			throw error
		}
		// swiftformat:disable:next propertyTypes — trailing closure init 會被誤改寫成裸 tuple（formatter 已知誤判）
		let connection = PTTConnection(
			transport: transport,
			role: role,
			keepaliveInterval: configuration.keepaliveInterval,
			clock: clock
		) { [weak self] identifier, reason in
			await self?.handleClose(identifier: identifier, reason: reason)
		}
		slots[connection.identifier] = SlotEntry(connection: connection, openedAt: clock.now())
		return connection
	}

	/// 短連線便利包裝（CLI / pttdata）：連線 → 執行 → **用完即斷**，不常駐佔 slot。
	public func withShortLivedConnection<Result: Sendable>(
		_ body: @Sendable (PTTConnection) async throws -> Result
	) async throws -> Result {
		let connection = try await connect(role: .shortLived)
		do {
			let result = try await body(connection)
			await connection.close()
			return result
		} catch {
			await connection.close()
			throw error
		}
	}

	/// 關閉全部連線（App 終止 / 登出收攤）。
	public func closeAll() async {
		let open = slots.values.map(\.connection)
		slots.removeAll()
		for connection in open {
			await connection.close()
		}
	}

	/// 建立引擎。
	///
	/// - Parameters:
	///   - configuration: 組態（預設 3 slot、keepalive 20 分）。
	///   - connector: transport 工廠（正式環境 ``CitadelPTTTransportConnector``、測試注入 fake）。
	///   - clock: 時間來源（測試注入假時鐘）。
	public init(
		configuration: Configuration = Configuration(),
		connector: any PTTTransportConnector,
		clock: EngineClock = .continuous
	) {
		self.configuration = configuration
		self.connector = connector
		self.clock = clock
	}

	// MARK: Private

	/// slot 表項。
	private struct SlotEntry {

		/// 佔用此 slot 的連線。
		let connection: PTTConnection

		/// 建立時刻（早夭窗判定）。
		let openedAt: ContinuousClock.Instant
	}

	/// 引擎組態。
	private let configuration: Configuration

	/// transport 工廠。
	private let connector: any PTTTransportConnector

	/// 時間來源。
	private let clock: EngineClock

	/// 登入頻率閘（引擎內單一正本）。
	private var gate: LoginFrequencyGate = .init()

	/// 佔用中的 slot（key = 連線識別）。
	private var slots: [UUID: SlotEntry] = [:]

	/// 仲裁通過、connect 進行中的保留位（防重入超賣）。
	private var reservedSlots = 0

	/// 滿額時依角色讓位；短連線無位可讓即丟錯。
	private func makeRoom(for role: PTTConnectionRole) async throws {
		while slots.count + reservedSlots >= configuration.maximumSlots {
			guard let victim = await evictionVictim(for: role) else {
				throw PTTConnectionError.slotsExhausted
			}
			slots.removeValue(forKey: victim.identifier) // 先釋放帳面、再關（close 為 async）
			await victim.close()
		}
	}

	/// 讓位者挑選：先挑非前景中的 LRU；前景請求在全前景時退而踢 LRU 前景，短連線請求則不搶佔前景。
	private func evictionVictim(for role: PTTConnectionRole) async -> PTTConnection? {
		let candidates = slots.values.map(\.connection)
		let nonForeground = candidates.filter { !$0.role.isForeground }
		if let victim = await leastRecentlyActive(of: nonForeground) { return victim }
		guard role.isForeground else { return nil }
		return await leastRecentlyActive(of: candidates)
	}

	/// 取一組連線中最久沒有流量的（LRU）。
	private func leastRecentlyActive(of connections: [PTTConnection]) async -> PTTConnection? {
		var oldest: (connection: PTTConnection, activity: ContinuousClock.Instant)?
		for connection in connections {
			let activity = await connection.lastActivity
			if let current = oldest, activity >= current.activity { continue }
			oldest = (connection, activity)
		}
		return oldest?.connection
	}

	/// 連線終止回報：釋放 slot；非本地關閉且早夭 → 保守記一次被拒。
	private func handleClose(identifier: UUID, reason: DisconnectReason) {
		guard let entry = slots.removeValue(forKey: identifier) else { return }
		switch reason {
		case .serverClose, .failure:
			let age = entry.openedAt.duration(to: clock.now())
			if age <= configuration.earlyDropWindow {
				gate.recordRejection(at: clock.now())
			}
		case .localClose, .routineMaintenance:
			break // 顯式關閉與例行重開都不是被拒
		}
	}
}
