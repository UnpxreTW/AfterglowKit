//
//  PTTConnectionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTConnection
import Foundation
import Testing

/// 引擎整合驗證：slot 仲裁（前景優先 + LRU、CLI 不搶佔）、頻率閘接線、
/// [Y/n] 自動應答、keepalive、顯式 close 與早夭被拒。全程 fake transport + 假時鐘。
private final class PTTConnectionEngineTests {

	/// keepalive 載荷 `ESC OA ESC OB`（byte 級規格斷言）。
	private static let keepalivePayload: [UInt8] = [0x1B, 0x4F, 0x41, 0x1B, 0x4F, 0x42]

	/// [Y/n] 自動應答 `Y` + CR。
	private static let duplicateAnswer: [UInt8] = [0x59, 0x0D]

	/// 建測試引擎（keepalive 預設拉長、避免干擾非 keepalive 測試）。
	private static func makeEngine(
		clock: TestClock,
		connector: FakeConnector,
		keepalive: Duration = .seconds(72_000)
	) -> PTTConnectionEngine {
		var configuration = PTTConnectionEngine.Configuration()
		configuration.keepaliveInterval = keepalive
		return PTTConnectionEngine(configuration: configuration, connector: connector, clock: clock.engineClock)
	}

	/// 發起 connect 並平行推進假時鐘直到完成（覆蓋 3s 閘與 30s backoff）。
	private static func connectAdvancing(
		_ engine: PTTConnectionEngine,
		role: PTTConnectionRole,
		clock: TestClock
	) async throws -> PTTConnection {
		async let connection = engine.connect(role: role)
		for _ in 0 ..< 40 {
			clock.advance(by: .seconds(1))
			await Task.yield()
			await Task.yield()
		}
		return try await connection
	}

	/// 下行 bytes 原樣轉發給訂閱者。
	@Test
	private func `inbound bytes forwarded`() async throws {
		let clock: TestClock = .init()
		let connector: FakeConnector = .init()
		// 顯式型別：static method 回傳型別 ≠ 宿主型別、不可交給 propertyTypes 推導。
		let engine: PTTConnectionEngine = Self.makeEngine(clock: clock, connector: connector)
		let connection = try await Self.connectAdvancing(engine, role: .foreground(deviceIdentifier: "mac"), clock: clock)
		let payload: [UInt8] = [0x48, 0x69, 0xB3, 0x5C] // "Hi" + 一個 Big5 字
		connector.transports[0].emit(payload)
		var iterator = connection.inbound.makeAsyncIterator()
		let received = try await iterator.next()
		#expect(received == payload)
		await connection.close()
	}

	/// 滿額時前景請求踢最久沒動的連線（LRU）讓位。
	@Test
	private func `foreground eviction picks least recently active`() async throws {
		let clock: TestClock = .init()
		let connector: FakeConnector = .init()
		// 顯式型別：static method 回傳型別 ≠ 宿主型別、不可交給 propertyTypes 推導。
		let engine: PTTConnectionEngine = Self.makeEngine(clock: clock, connector: connector)
		let first = try await Self.connectAdvancing(engine, role: .foreground(deviceIdentifier: "iphone"), clock: clock)
		let second = try await Self.connectAdvancing(engine, role: .foreground(deviceIdentifier: "ipad"), clock: clock)
		let third = try await Self.connectAdvancing(engine, role: .foreground(deviceIdentifier: "mac"), clock: clock)
		// 讓 second / third 有較新流量 → LRU = first。
		try await second.send([0x20])
		try await third.send([0x20])
		let fourth = try await Self.connectAdvancing(engine, role: .foreground(deviceIdentifier: "vision"), clock: clock)
		#expect(await first.state == .closed(.localClose))
		#expect(await second.state == .active)
		#expect(await third.state == .active)
		#expect(await fourth.state == .active)
		#expect(await engine.activeConnectionCount == 3)
		await engine.closeAll()
	}

	/// 前景請求優先踢非前景：短連線即使最新仍先讓位。
	@Test
	private func `foreground evicts short lived before foreground`() async throws {
		let clock: TestClock = .init()
		let connector: FakeConnector = .init()
		// 顯式型別：static method 回傳型別 ≠ 宿主型別、不可交給 propertyTypes 推導。
		let engine: PTTConnectionEngine = Self.makeEngine(clock: clock, connector: connector)
		let first = try await Self.connectAdvancing(engine, role: .foreground(deviceIdentifier: "iphone"), clock: clock)
		let second = try await Self.connectAdvancing(engine, role: .foreground(deviceIdentifier: "ipad"), clock: clock)
		let shortLived = try await Self.connectAdvancing(engine, role: .shortLived, clock: clock)
		try await shortLived.send([0x20]) // 短連線流量最新、純 LRU 會挑 first——政策須挑非前景
		let fourth = try await Self.connectAdvancing(engine, role: .foreground(deviceIdentifier: "mac"), clock: clock)
		#expect(await shortLived.state == .closed(.localClose))
		#expect(await first.state == .active)
		#expect(await second.state == .active)
		#expect(await fourth.state == .active)
		await engine.closeAll()
	}

	/// 短連線請求絕不搶佔前景：全前景滿額 → `slotsExhausted`。
	@Test
	private func `short lived never evicts foreground`() async throws {
		let clock: TestClock = .init()
		let connector: FakeConnector = .init()
		// 顯式型別：static method 回傳型別 ≠ 宿主型別、不可交給 propertyTypes 推導。
		let engine: PTTConnectionEngine = Self.makeEngine(clock: clock, connector: connector)
		_ = try await Self.connectAdvancing(engine, role: .foreground(deviceIdentifier: "iphone"), clock: clock)
		_ = try await Self.connectAdvancing(engine, role: .foreground(deviceIdentifier: "ipad"), clock: clock)
		_ = try await Self.connectAdvancing(engine, role: .foreground(deviceIdentifier: "mac"), clock: clock)
		await #expect(throws: PTTConnectionError.slotsExhausted) {
			_ = try await engine.connect(role: .shortLived)
		}
		#expect(await engine.activeConnectionCount == 3)
		await engine.closeAll()
	}

	/// 短連線便利包裝：用完即斷、slot 歸還。
	@Test
	private func `with short lived connection closes after use`() async throws {
		let clock: TestClock = .init()
		let connector: FakeConnector = .init()
		// 顯式型別：static method 回傳型別 ≠ 宿主型別、不可交給 propertyTypes 推導。
		let engine: PTTConnectionEngine = Self.makeEngine(clock: clock, connector: connector)
		let used = try await engine.withShortLivedConnection { connection in
			connection // 取回引用驗證關閉
		}
		#expect(await used.state == .closed(.localClose))
		#expect(await engine.activeConnectionCount == 0)
		#expect(connector.transports[0].isClosed)
	}

	/// 3 秒最小間隔接線：第二次 connect 在閘內不發起、滿 3 秒才連。
	@Test
	private func `gate blocks second connect within three seconds`() async throws {
		let clock: TestClock = .init()
		let connector: FakeConnector = .init()
		// 顯式型別：static method 回傳型別 ≠ 宿主型別、不可交給 propertyTypes 推導。
		let engine: PTTConnectionEngine = Self.makeEngine(clock: clock, connector: connector)
		let first = try await engine.connect(role: .foreground(deviceIdentifier: "iphone")) // 空閘、立即
		let secondTask = Task { try await engine.connect(role: .foreground(deviceIdentifier: "ipad")) }
		clock.advance(by: .seconds(1))
		await Task.yield()
		await Task.yield()
		#expect(connector.transports.count == 1) // 閘內：第二條還不許發起
		for _ in 0 ..< 5 {
			clock.advance(by: .seconds(1))
			await Task.yield()
			await Task.yield()
		}
		let second = try await secondTask.value
		#expect(connector.transports.count == 2)
		await first.close()
		await second.close()
	}

	/// connect 失敗記被拒：下一次至少 backoff 30 秒。
	@Test
	private func `failed connect enforces thirty second backoff`() async throws {
		let clock: TestClock = .init()
		let connector: FakeConnector = .init(failuresRemaining: 1)
		// 顯式型別：static method 回傳型別 ≠ 宿主型別、不可交給 propertyTypes 推導。
		let engine: PTTConnectionEngine = Self.makeEngine(clock: clock, connector: connector)
		await #expect(throws: FakeConnector.ConnectFailed.self) {
			_ = try await engine.connect(role: .foreground(deviceIdentifier: "iphone"))
		}
		let retryTask = Task { try await engine.connect(role: .foreground(deviceIdentifier: "iphone")) }
		for _ in 0 ..< 20 {
			clock.advance(by: .seconds(1))
			await Task.yield()
			await Task.yield()
		}
		#expect(connector.transports.isEmpty) // backoff 內（20s < 30s）：不得重連
		for _ in 0 ..< 20 {
			clock.advance(by: .seconds(1))
			await Task.yield()
			await Task.yield()
		}
		let retried = try await retryTask.value
		#expect(connector.transports.count == 1)
		await retried.close()
	}

	/// 建立後早夭（server 斷）→ 視為被拒、下一次 connect 進 backoff。
	@Test
	private func `early server drop records rejection`() async throws {
		let clock: TestClock = .init()
		let connector: FakeConnector = .init()
		// 顯式型別：static method 回傳型別 ≠ 宿主型別、不可交給 propertyTypes 推導。
		let engine: PTTConnectionEngine = Self.makeEngine(clock: clock, connector: connector)
		let connection = try await engine.connect(role: .foreground(deviceIdentifier: "iphone"))
		connector.transports[0].endStream() // 建立後立即被斷（早夭窗內）
		// 收斂條件須含 slot 釋放：state 在 shutdown 內先落定、被拒記錄晚於它（handleClose 於引擎
		// actor 內先釋放 slot 再記被拒）——只等 state 會與被拒記錄競態、backoff 斷言偶發失效。
		let dropped = await advanceUntil(clock, step: .milliseconds(100)) {
			let closed = await connection.state == .closed(.serverClose)
			let slotReleased = await engine.activeConnectionCount == 0
			return closed && slotReleased
		}
		#expect(dropped)
		let retryTask = Task { try await engine.connect(role: .foreground(deviceIdentifier: "iphone")) }
		for _ in 0 ..< 10 {
			clock.advance(by: .seconds(1))
			await Task.yield()
			await Task.yield()
		}
		#expect(connector.transports.count == 1) // backoff 內不得重連
		for _ in 0 ..< 30 {
			clock.advance(by: .seconds(1))
			await Task.yield()
			await Task.yield()
		}
		let retried = try await retryTask.value
		#expect(connector.transports.count == 2)
		await retried.close()
	}

	/// 週日清晨例行窗內被斷 → 分類為例行重開、不記被拒（重連不用等 30 秒）。
	@Test
	private func `maintenance window drop is routine and not a rejection`() async throws {
		let sunday = ISO8601DateFormatter().date(from: "2026-07-12T05:00:00+08:00")
		let clock: TestClock = .init(wallClock: sunday ?? Date())
		let connector: FakeConnector = .init()
		// 顯式型別：static method 回傳型別 ≠ 宿主型別、不可交給 propertyTypes 推導。
		let engine: PTTConnectionEngine = Self.makeEngine(clock: clock, connector: connector)
		let connection = try await engine.connect(role: .foreground(deviceIdentifier: "iphone"))
		connector.transports[0].endStream()
		let classified = await advanceUntil(clock, step: .milliseconds(100)) {
			await connection.state == .closed(.routineMaintenance)
		}
		#expect(classified)
		// 不算被拒：只需過 3 秒最小間隔即可重連（遠小於 30 秒 backoff）。
		let retryTask = Task { try await engine.connect(role: .foreground(deviceIdentifier: "iphone")) }
		for _ in 0 ..< 8 {
			clock.advance(by: .seconds(1))
			await Task.yield()
			await Task.yield()
		}
		let retried = try await retryTask.value
		#expect(connector.transports.count == 2)
		await retried.close()
	}

	/// [Y/n] 刪除重複連線 prompt：自動應答 `Y` + CR、一條連線只答一次。
	@Test
	private func `duplicate login prompt auto answered once`() async throws {
		let clock: TestClock = .init()
		let connector: FakeConnector = .init()
		// 顯式型別：static method 回傳型別 ≠ 宿主型別、不可交給 propertyTypes 推導。
		let engine: PTTConnectionEngine = Self.makeEngine(clock: clock, connector: connector)
		let connection = try await Self.connectAdvancing(engine, role: .foreground(deviceIdentifier: "iphone"), clock: clock)
		let transport = connector.transports[0]
		transport.emit([0xB1, 0xA1, 0x3F] + Array("[Y/n] ".utf8)) // Big5 前綴 + prompt
		let answered = await advanceUntil(clock, step: .milliseconds(100)) {
			transport.sentPayloads.contains(Self.duplicateAnswer)
		}
		#expect(answered)
		transport.emit(Array("[Y/n] ".utf8)) // 第二次出現不再應答
		_ = await advanceUntil(clock, step: .milliseconds(100), limit: 20) { false }
		let answers = transport.sentPayloads.filter { $0 == Self.duplicateAnswer }
		#expect(answers.count == 1)
		await connection.close()
	}

	/// 閒置達 keepalive 間隔 → 送 `ESC OA ESC OB` 載荷。
	@Test
	private func `keepalive payload sent after idle interval`() async throws {
		let clock: TestClock = .init()
		let connector: FakeConnector = .init()
		// 顯式型別：static method 回傳型別 ≠ 宿主型別、不可交給 propertyTypes 推導。
		let engine: PTTConnectionEngine = Self.makeEngine(clock: clock, connector: connector, keepalive: .seconds(60))
		let connection = try await engine.connect(role: .foreground(deviceIdentifier: "iphone"))
		let transport = connector.transports[0]
		let fired = await advanceUntil(clock, step: .seconds(10), limit: 30) {
			transport.sentPayloads.contains(Self.keepalivePayload)
		}
		#expect(fired)
		await connection.close()
	}

	/// 顯式 close：冪等、釋放 slot、關 transport。
	@Test
	private func `close is idempotent and releases slot`() async throws {
		let clock: TestClock = .init()
		let connector: FakeConnector = .init()
		// 顯式型別：static method 回傳型別 ≠ 宿主型別、不可交給 propertyTypes 推導。
		let engine: PTTConnectionEngine = Self.makeEngine(clock: clock, connector: connector)
		let connection = try await engine.connect(role: .foreground(deviceIdentifier: "iphone"))
		#expect(await engine.activeConnectionCount == 1)
		await connection.close()
		await connection.close()
		#expect(await connection.state == .closed(.localClose))
		#expect(await engine.activeConnectionCount == 0)
		#expect(connector.transports[0].isClosed)
		await #expect(throws: PTTConnectionError.connectionClosed) {
			try await connection.send([0x20])
		}
	}
}
