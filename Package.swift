// swift-tools-version: 6.0

import PackageDescription

let package = Package(
	name: "AfterglowKit",
	platforms: [
		.iOS(.v17),
		.macOS(.v15),
	],
	products: [
		.library(name: "PTTBig5Codec", targets: ["PTTBig5Codec"]),
		.executable(name: "afterglowdata", targets: ["afterglowdata"]),
	],
	dependencies: [
		.package(url: "https://github.com/UnpxreTW/SwiftStyleKit.git", from: "2.0.0"),
	],
	targets: [
		// Big5-UAO codec：對照表 blob + loader + 串流轉碼器（零外部 dep、可孤立編譯）。
		.target(
			name: "PTTBig5Codec",
			plugins: [
				.plugin(name: "SwiftStyleLint", package: "SwiftStyleKit"),
			]
		),
		// dev-time 資料 / 表產生器。
		.executableTarget(
			name: "afterglowdata",
			dependencies: ["PTTBig5Codec"],
			plugins: [
				.plugin(name: "SwiftStyleLint", package: "SwiftStyleKit"),
			]
		),
		.testTarget(
			name: "PTTBig5CodecTests",
			dependencies: ["PTTBig5Codec"],
			// golden 輸入：真實登入畫面 raw byte 捕獲（StreamTranscoder 整段過機驗收）。
			resources: [.copy("Captures")]
		),
	]
)
