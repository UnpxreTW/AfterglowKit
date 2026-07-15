//
//  PTTBig5Codec
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

/// ``UAO/encode(_:mode:)`` 的可逆性門檻。
public enum UAOEncodeMode: Sendable, Equatable {

	/// 僅回傳可逆（round-trippable）對應：`UAO.decode.lookup(raw) == scalar`。
	case strict

	/// 額外允許不可逆的 best-fit 近似替代。
	case bestFit
}
