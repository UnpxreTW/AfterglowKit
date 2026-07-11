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
		.library(name: "PTTConnection", targets: ["PTTConnection"]),
		.executable(name: "afterglowdata", targets: ["afterglowdata"]),
	],
	dependencies: [
		.package(url: "https://github.com/UnpxreTW/SwiftStyleKit.git", from: "2.0.0"),
		// SSH 依賴走 exact pin：transport 對演算法組合與 delegate API 敏感、升版須人工重驗。
		.package(url: "https://github.com/apple/swift-nio.git", exact: "2.101.2"),
		.package(url: "https://github.com/apple/swift-nio-ssh.git", exact: "0.14.0"),
		// swift-crypto 僅測試用（in-process SSH server 的 host key 生成）；
		// 本就是 swift-nio-ssh 的 transitive 依賴、exact pin 與既解析版本一致。
		.package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.0"),
	],
	targets: [
		// Big5-UAO codec：對照表 blob + loader + 串流轉碼器（零外部 dep、可孤立編譯）。
		.target(
			name: "PTTBig5Codec",
			plugins: [
				.plugin(name: "SwiftStyleLint", package: "SwiftStyleKit"),
			]
		),
		// SSH 連線引擎：slot 配額仲裁、登入頻率閘、[Y/n] 應答、keepalive、顯式 close，
		// 以及架在官方 swift-nio-ssh 上的薄 transport（PTY 位元組管道）。
		.target(
			name: "PTTConnection",
			dependencies: [
				.product(name: "NIOCore", package: "swift-nio"),
				.product(name: "NIOPosix", package: "swift-nio"),
				.product(name: "NIOSSH", package: "swift-nio-ssh"),
			],
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
		.testTarget(
			name: "PTTConnectionTests",
			dependencies: [
				"PTTConnection",
				.product(name: "Crypto", package: "swift-crypto"),
				.product(name: "NIOCore", package: "swift-nio"),
				.product(name: "NIOEmbedded", package: "swift-nio"),
				.product(name: "NIOSSH", package: "swift-nio-ssh"),
			]
		),
	]
)
