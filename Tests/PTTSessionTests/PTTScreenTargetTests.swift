//
//  PTTSessionTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

@testable import PTTSession
import PTTTerminal
import Testing

/// ``PTTScreenTarget`` 比對語義與 ``PTTScreenText`` 攤平規則驗證。
private final class PTTScreenTargetTests {

	/// 所有 pattern 都出現才算命中。
	@Test
	private func `matches only when every pattern appears`() {
		let target: PTTScreenTarget = .init(name: "測試", patterns: ["甲", "乙"], outcome: .arrived)
		#expect(target.matches("甲\n乙"))
		#expect(!target.matches("甲\n丙"))
	}

	/// 空 pattern 表永遠不命中——否則一張空表會匹配任何畫面。
	@Test
	private func `an empty pattern list never matches`() {
		let target: PTTScreenTarget = .init(name: "空表", patterns: [], outcome: .arrived)
		#expect(!target.matches("任何畫面"))
	}

	/// 攤平時略過寬字元延續格，否則全形字之間會多出假空白、pattern 對不上。
	@Test
	private func `flattened text drops wide character continuation cells`() {
		let text: String = PTTScreenText.flattened(makeScreen(TestScreens.inBoard))
		#expect(text.contains("看板資訊/設定"))
		#expect(PTTTargetTable.inBoard.matches(text))
	}

	/// 攤平時去除行尾空白、列間以換行相接。
	@Test
	private func `flattened text trims trailing blanks and joins rows with newlines`() {
		let screen: PTTScreen = makeScreen(["第一列", "第二列"])
		let lines: [String] = PTTScreenText.lines(of: screen)
		#expect(lines[0] == "第一列")
		#expect(lines[1] == "第二列")
		#expect(lines[2] == "")
		#expect(lines.count == PTTTerminal.rows)
	}

	/// 主功能表畫面命中主功能表目標，但不會誤命中離站確認目標。
	@Test
	private func `main menu screen does not match the exit confirmation target`() {
		let text: String = PTTScreenText.flattened(makeScreen(TestScreens.mainMenu))
		#expect(PTTTargetTable.mainMenu.matches(text))
		#expect(!PTTTargetTable.mainMenuExiting.matches(text))
	}

	/// 全域表把資源上限排在最前面——它是唯一必須立刻退避的畫面。
	@Test
	private func `resource limit is the first global target`() {
		#expect(PTTTargetTable.globals.first?.outcome == .resourceLimit)
	}

	/// 「任意鍵」pattern 最寬鬆，排在全域表最後、讓具體畫面先命中。
	@Test
	private func `any key target is last among the globals`() {
		#expect(PTTTargetTable.globals.last?.name == "請按任意鍵繼續")
	}
}
