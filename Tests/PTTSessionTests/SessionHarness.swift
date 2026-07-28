//
//  PTTSessionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTSession
import PTTTerminal

// MARK: - SessionHarness

/// 受測 Session 的組裝：假時鐘 + 假 sink + 手動餵畫面的快照流。
final class SessionHarness: @unchecked Sendable {

	// MARK: Lifecycle

	/// 組一套乾淨的受測環境。
	init() {
		let clock: TestClock = .init()
		let sink: RecordingKeySink = .init(clock: clock)
		let (stream, continuation) = AsyncStream<PTTScreen>.makeStream()
		self.clock = clock
		self.sink = sink
		self.continuation = continuation
		self.session = PTTSession(screens: stream, keySink: sink.sink, clock: clock.sessionClock)
	}

	// MARK: Internal

	/// 假時鐘。
	let clock: TestClock

	/// 送鍵記錄。
	let sink: RecordingKeySink

	/// 受測 Session。
	let session: PTTSession

	/// 在背景 task 裡跑一段 Session 操作，完成時標記旗標。
	func run(_ body: @escaping @Sendable (PTTSession) async throws -> Void) -> Task<Void, any Error> {
		Task { [session, completion] in
			defer { completion.set() }
			try await body(session)
		}
	}

	/// 餵一張畫面。
	func yield(_ lines: [String]) {
		continuation.yield(makeScreen(lines))
	}

	/// 結束快照流（模擬連線關閉）。
	func finish() {
		continuation.finish()
	}

	/// 推進假時鐘直到累積送出批次達 `count`。
	func waitForSend(count: Int, step: Duration = .milliseconds(20), limit: Int = 400) async -> Bool {
		await advanceUntil(clock, step: step, limit: limit) { self.sink.count >= count }
	}

	/// 推進假時鐘直到受測 task 跑完。
	func waitForCompletion(step: Duration = .milliseconds(20), limit: Int = 400) async -> Bool {
		await advanceUntil(clock, step: step, limit: limit) { self.completion.isSet }
	}

	// MARK: Private

	/// 快照流入口。
	private let continuation: AsyncStream<PTTScreen>.Continuation

	/// 受測 task 的完成旗標。
	private let completion: CompletionFlag = .init()
}
