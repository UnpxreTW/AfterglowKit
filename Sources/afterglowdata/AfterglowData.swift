//
//  afterglowdata
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

/// dev-time 資料 / 表產生器進入點。
@main
struct AfterglowData {

	/// 進入點：解析 CLI 引數並分派子命令——`generate` 執行表產生（失敗 exit 1）、未知子命令印 usage 後 exit 2。
	static func main() {
		let arguments: Array = .init(CommandLine.arguments.dropFirst())
		switch arguments.first {
		case "generate":
			do {
				try Generator.run()
			} catch {
				FileHandle.standardError.write(Data("afterglowdata: \(error)\n".utf8))
				exit(1)
			}
		default:
			FileHandle.standardError.write(Data("usage: afterglowdata generate\n".utf8))
			exit(2)
		}
	}
}
