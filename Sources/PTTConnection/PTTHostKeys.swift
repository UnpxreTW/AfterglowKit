//
//  PTTConnection
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import NIOSSH

// MARK: - PTTHostKeys

/// ptt.cc 的內建 pinned host key 組（transport 出廠預設、不做 TOFU）。
///
/// 首連常發生在不可信網路，TOFU 的首連本身就是攻擊窗、且需要持久儲存引入狀態管理；
/// 內建 pin 把信任錨定在發佈時點的多通道交叉核驗（TCP keyscan、DNS SSHFP、站方公告指紋），
/// 不依賴連線當下的網路環境。站方輪替金鑰時 pinned 組全 miss、連線會全數失敗——
/// 復原路徑＝隨 App 更新內建組；亦可經 ``NIOSSHPTTTransportConnector`` 的
/// `pinnedHostKeys` 參數注入替代組（測試或外部組態）。
public enum PTTHostKeys {

	/// ptt.cc 的兩把 pinned key（ssh-ed25519 與 ecdsa-sha2-nistp256）。
	///
	/// 站方另提供 RSA host key、但不入組：swift-nio-ssh 不支援 RSA host key 演算法、
	/// 協商不會選到。兩把都 pin 的理由：實際協商到哪把由 client 演算法偏好序決定
	/// （上游實作細節、非我們控制面），pin 整組避免依賴偏好序。
	public static let pttcc: Set<NIOSSHPublicKey> = [
		makeKey("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDqjN1kJZrgrY6skGqVGT/JHeoZRuTlnRO38IUKEzaW0"),
		// swiftlint:disable:next line_length
		makeKey("ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBF2BVrQ8abQ5CEeUEfUybHXFlaFkLwWBfiLN53KnTGyTpJbUCrpTTPHIr325IaKhed+Lx2POwrDwpga8USPBoqc="),
	]

	/// 解析 OpenSSH 格式公鑰字面值；內建常數解析失敗屬程式員錯誤、直接斷言終止。
	private static func makeKey(_ openSSHPublicKey: String) -> NIOSSHPublicKey {
		guard let key = try? NIOSSHPublicKey(openSSHPublicKey: openSSHPublicKey) else {
			preconditionFailure("內建 host key 字面值不合法：\(openSSHPublicKey)")
		}
		return key
	}
}
