//
//  PTTSessionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTSession
import Foundation
import PTTTerminal

// MARK: - TestClock

/// 假時鐘：時間只被 ``advance(by:)`` 推進；`sleep` 掛起等待推進、不等真實時間。
final class TestClock: @unchecked Sendable {

	// MARK: Internal

	/// 目前假時刻。
	var now: ContinuousClock.Instant {
		lock.lock()
		defer { lock.unlock() }
		return current
	}

	/// 對應的 ``SessionClock``。
	var sessionClock: SessionClock {
		SessionClock(now: { self.now }, sleep: { try await self.sleep(for: $0) })
	}

	/// 推進假時間並喚醒到期的睡眠者。
	func advance(by duration: Duration) {
		lock.lock()
		current += duration
		let due: [Waiter] = waiters.filter { $0.deadline <= current }
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

	/// 假睡眠：登記 waiter、等 ``advance(by:)`` 推過 deadline；task 取消即丟 `CancellationError`。
	private func sleep(for duration: Duration) async throws {
		let identifier: UUID = .init()
		let cancelled: Cancelled = .init()
		try await withTaskCancellationHandler {
			try Task.checkCancellation()
			await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
				lock.lock()
				let deadline: ContinuousClock.Instant = current + duration
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
			let hit: Waiter? = waiters.first { $0.identifier == identifier }
			waiters.removeAll { $0.identifier == identifier }
			lock.unlock()
			hit?.continuation.resume()
		}
	}
}

// MARK: - RecordingKeySink

/// 假送鍵出口：記錄每一批送出的按鍵與送出當下的假時刻。
final class RecordingKeySink: @unchecked Sendable {

	// MARK: Lifecycle

	/// 建立記錄用 sink。
	///
	/// - Parameter clock: 用來標記送出時刻的假時鐘（節流斷言需要）。
	init(clock: TestClock) {
		self.clock = clock
	}

	// MARK: Internal

	/// 對應的 ``PTTKeySink``。
	var sink: PTTKeySink {
		PTTKeySink { keys in self.record(keys) }
	}

	/// 已送出的批次（依序）。
	var batches: [[PTTKey]] {
		lock.lock()
		defer { lock.unlock() }
		return sent.map(\.keys)
	}

	/// 已送出的批次數。
	var count: Int {
		lock.lock()
		defer { lock.unlock() }
		return sent.count
	}

	/// 第 `index` 批送出當下的假時刻；超出範圍回 `nil`。
	func instant(at index: Int) -> ContinuousClock.Instant? {
		lock.lock()
		defer { lock.unlock() }
		guard sent.indices.contains(index) else { return nil }
		return sent[index].instant
	}

	// MARK: Private

	/// 單筆送出記錄。
	private struct Record {

		/// 送出的按鍵。
		let keys: [PTTKey]

		/// 送出當下的假時刻。
		let instant: ContinuousClock.Instant
	}

	/// 保護 `sent`。
	private let lock: NSLock = .init()

	/// 送出記錄。
	private var sent: [Record] = []

	/// 標記送出時刻用的假時鐘。
	private let clock: TestClock

	/// 同步記錄一批（NSLock 不可直接用於 async 函式體、抽出）。
	private func record(_ keys: [PTTKey]) {
		lock.lock()
		defer { lock.unlock() }
		sent.append(Record(keys: keys, instant: clock.now))
	}
}

// MARK: - CompletionFlag

/// 完成旗標：讓假時鐘驅動迴圈知道受測 task 已經跑完。
final class CompletionFlag: @unchecked Sendable {

	// MARK: Internal

	/// 是否已完成。
	var isSet: Bool {
		lock.lock()
		defer { lock.unlock() }
		return value
	}

	/// 標記完成。
	func set() {
		lock.lock()
		defer { lock.unlock() }
		value = true
	}

	// MARK: Private

	/// 保護 `value`。
	private let lock: NSLock = .init()

	/// 旗標本體。
	private var value = false
}

// MARK: - ResultBox

/// 執行緒安全的結果盒：把背景 task 的回傳值帶回測試主體。
final class ResultBox<Value: Sendable>: @unchecked Sendable {

	// MARK: Internal

	/// 已寫入的值；尚未寫入時為 `nil`。
	var value: Value? {
		lock.lock()
		defer { lock.unlock() }
		return stored
	}

	/// 寫入結果。
	func set(_ newValue: Value) {
		lock.lock()
		defer { lock.unlock() }
		stored = newValue
	}

	// MARK: Private

	/// 保護 `stored`。
	private let lock: NSLock = .init()

	/// 值本體。
	private var stored: Value?
}

// MARK: - 測試共用小工具

/// 反覆推進假時鐘＋讓出執行權，直到條件成立或步數用盡。
///
/// 讓出執行權走**極短真實 sleep**（每步 100µs）而非 `Task.yield()`：並行測試把
/// cooperative pool 佔滿時，純 yield 的緊迴圈可能整輪跑完而受測背景 task 一次都沒被排程。
/// 與「假時鐘、不等真實時間」不衝突——等待量不隨模擬時長增長、只付排程成本。
func advanceUntil(
	_ clock: TestClock,
	step: Duration = .milliseconds(20),
	limit: Int = 400,
	condition: () -> Bool
) async -> Bool {
	for _ in 0 ..< limit {
		if condition() { return true }
		clock.advance(by: step)
		try? await Task.sleep(for: .microseconds(100))
	}
	return condition()
}

/// 由字串列組出一張 `PTTScreen`（不足處補空白、超出畫面寬高截斷）。
///
/// 寬字判定用「碼位 >= 0x2E80」這個測試專用近似——測試字串只有 ASCII 與 CJK 兩類，
/// 不需要完整的東亞寬度表；正式路徑的寬度來自終端引擎本身、不經過這裡。
func makeScreen(_ lines: [String]) -> PTTScreen {
	var rows: [[PTTCell]] = []
	for index in 0 ..< PTTTerminal.rows {
		let source: String = index < lines.count ? lines[index] : ""
		var row: [PTTCell] = []
		for character in source {
			guard row.count < PTTTerminal.columns else { break }
			let isWide: Bool = character.unicodeScalars.first.map { $0.value >= 0x2E80 } ?? false
			row.append(makeCell(character, width: isWide ? 2 : 1))
			if isWide, row.count < PTTTerminal.columns {
				row.append(makeCell(" ", width: 0))
			}
		}
		while row.count < PTTTerminal.columns {
			row.append(makeCell(" ", width: 1))
		}
		rows.append(row)
	}
	return PTTScreen(rows: rows, cursor: PTTCursor(column: 0, row: 0, isVisible: true))
}

/// 組一個預設配色的格子。
///
/// 非 `private`：``ArticleContentScannerTests`` 也需要直接組 `[PTTCell]` 列
/// （測折行合併／80 欄無記號續行），不透過 ``makeScreen(_:)`` 整張畫面繞。
func makeCell(_ character: Character, width: Int) -> PTTCell {
	PTTCell(
		character: character,
		width: width,
		foregroundColor: .defaultColor,
		backgroundColor: .defaultColor,
		attributes: []
	)
}
