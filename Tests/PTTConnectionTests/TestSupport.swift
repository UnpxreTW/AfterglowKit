//
//  PTTConnectionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTConnection
import Foundation

// MARK: - TestClock

/// 假時鐘：時間只被 `advance(by:)` 推進；`sleep` 掛起等待推進、不等真實時間。
final class TestClock: @unchecked Sendable {

	// MARK: Lifecycle

	/// 建立假時鐘。
	///
	/// - Parameter wallClock: 固定牆鐘時刻（例行窗判定用；預設 2026-07-06T04:00:00Z＝週一正午台北時間、非例行窗）。
	init(wallClock: Date = Date(timeIntervalSince1970: 1_783_296_000)) {
		self.wallClock = wallClock
	}

	// MARK: Internal

	/// 目前假時刻。
	var now: ContinuousClock.Instant {
		lock.lock()
		defer { lock.unlock() }
		return current
	}

	/// 對應的 ``EngineClock``（牆鐘固定注入、預設非例行窗時刻）。
	var engineClock: EngineClock {
		EngineClock(
			now: { self.now },
			sleep: { try await self.sleep(for: $0) },
			wallClockNow: { self.wallClock }
		)
	}

	/// 推進假時間並喚醒到期的睡眠者。
	func advance(by duration: Duration) {
		lock.lock()
		current += duration
		let due = waiters.filter { $0.deadline <= current }
		waiters.removeAll { $0.deadline <= current }
		lock.unlock()
		for waiter in due {
			waiter.continuation.resume()
		}
	}

	// MARK: Private

	/// 睡眠者登記。
	private struct Waiter {

		/// 喚醒門檻。
		let deadline: ContinuousClock.Instant

		/// 識別（取消移除用）。
		let identifier: UUID

		/// 喚醒用 continuation。
		let continuation: CheckedContinuation<Void, Never>
	}

	/// 取消旗標盒（cancellation handler 與登記程序間的 race 防護）。
	private final class Cancelled: @unchecked Sendable {

		/// 已取消。
		var value = false
	}

	/// 保護 `current` / `waiters`。
	private let lock: NSLock = .init()

	/// 目前假時刻（基準取真實 now、之後只算術推進）。
	private var current: ContinuousClock.Instant = .now

	/// 掛起中的睡眠者。
	private var waiters: [Waiter] = []

	/// 固定牆鐘。
	private let wallClock: Date

	/// 假睡眠：登記 waiter、等 `advance` 推過 deadline；task 取消即丟 `CancellationError`。
	private func sleep(for duration: Duration) async throws {
		let identifier: UUID = .init()
		let cancelled: Cancelled = .init()
		try await withTaskCancellationHandler {
			try Task.checkCancellation()
			await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
				lock.lock()
				let deadline = current + duration
				if deadline <= current || cancelled.value {
					lock.unlock()
					continuation.resume()
					return
				}
				waiters.append(Waiter(deadline: deadline, identifier: identifier, continuation: continuation))
				lock.unlock()
			}
			try Task.checkCancellation()
		} onCancel: {
			cancelled.value = true
			lock.lock()
			let hit = waiters.first { $0.identifier == identifier }
			waiters.removeAll { $0.identifier == identifier }
			lock.unlock()
			hit?.continuation.resume()
		}
	}

}

// MARK: - FakeTransport

/// 假 transport：測試端手動餵下行、記錄上行與關閉狀態。
final class FakeTransport: PTTTransport, @unchecked Sendable {

	/// 建立假 transport。
	init() {
		(self.inbound, self.continuation) = AsyncThrowingStream.makeStream(of: [UInt8].self)
	}

	/// 已送出的上行 bytes（依序）。
	var sentPayloads: [[UInt8]] {
		lock.lock()
		defer { lock.unlock() }
		return sent
	}

	/// 是否已被關閉。
	var isClosed: Bool {
		lock.lock()
		defer { lock.unlock() }
		return closed
	}

	// MARK: Internal

	/// 下行流（`emit` / `endStream` / `failStream` 控制）。
	let inbound: AsyncThrowingStream<[UInt8], any Error>

	/// 記錄上行。
	func send(_ bytes: [UInt8]) async throws {
		try record(bytes)
	}

	/// 關閉：結束下行流（冪等）。
	func close() async {
		markClosed()
		continuation.finish()
	}

	/// 餵一段下行 bytes。
	func emit(_ bytes: [UInt8]) {
		continuation.yield(bytes)
	}

	/// 模擬對端結束流（server 斷線）。
	func endStream() {
		continuation.finish()
	}

	/// 模擬讀流失敗。
	func failStream(_ error: any Error) {
		continuation.finish(throwing: error)
	}

	// MARK: Private

	/// 下行流入口。
	private let continuation: AsyncThrowingStream<[UInt8], any Error>.Continuation

	/// 保護 `sent` / `closed`。
	private let lock: NSLock = .init()

	/// 上行記錄。
	private var sent: [[UInt8]] = []

	/// 關閉旗標。
	private var closed = false

	/// 同步記錄上行（NSLock 不可直接用於 async 函式體、抽出）。
	private func record(_ bytes: [UInt8]) throws {
		lock.lock()
		defer { lock.unlock() }
		guard !closed else { throw PTTConnectionError.connectionClosed }
		sent.append(bytes)
	}

	/// 同步設關閉旗標。
	private func markClosed() {
		lock.lock()
		defer { lock.unlock() }
		closed = true
	}
}

// MARK: - FakeConnector

/// 假 connector：每次 `connect` 產一顆新 ``FakeTransport``；可注入前置失敗次數。
final class FakeConnector: PTTTransportConnector, @unchecked Sendable {

	/// 建立假 connector。
	///
	/// - Parameter failuresRemaining: 前幾次 `connect` 直接丟錯（模擬網路 / server 拒絕）。
	init(failuresRemaining: Int = 0) {
		self.failuresRemaining = failuresRemaining
	}

	// MARK: Internal

	/// 模擬的連線失敗。
	struct ConnectFailed: Error {}

	/// 歷來產出的 transports（依序；測試端取用操控）。
	var transports: [FakeTransport] {
		lock.lock()
		defer { lock.unlock() }
		return made
	}

	/// 產新 transport；`failuresRemaining` > 0 時先消耗失敗。
	func connect(to endpoint: PTTEndpoint) async throws -> any PTTTransport {
		try nextTransport()
	}

	// MARK: Private

	/// 保護內部狀態。
	private let lock: NSLock = .init()

	/// 產出記錄。
	private var made: [FakeTransport] = []

	/// 剩餘的前置失敗次數。
	private var failuresRemaining: Int

	/// 同步產 transport（NSLock 不可直接用於 async 函式體、抽出）。
	private func nextTransport() throws -> FakeTransport {
		lock.lock()
		defer { lock.unlock() }
		if failuresRemaining > 0 {
			failuresRemaining -= 1
			throw ConnectFailed()
		}
		let transport: FakeTransport = .init()
		made.append(transport)
		return transport
	}
}

// MARK: - 測試共用小工具

/// 反覆推進假時鐘＋讓出執行權，直到條件成立或步數用盡（假時鐘下的收斂等待）。
func advanceUntil(
	_ clock: TestClock,
	step: Duration = .seconds(1),
	limit: Int = 200,
	condition: () async -> Bool
) async -> Bool {
	for _ in 0 ..< limit {
		if await condition() { return true }
		clock.advance(by: step)
		await Task.yield()
		await Task.yield()
	}
	return await condition()
}
