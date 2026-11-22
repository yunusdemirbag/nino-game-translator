// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Eski sürümlerin klasör ve Anahtar Zinciri adları. Yalnız bir kez veri taşımak için kullanılır, hiçbir yerde
/// gösterilmez. Kodda düz yazı olarak geçmesin diye base64 tutulur.
enum LegacyNames {
    private static func decode(_ value: String) -> String {
        String(decoding: Data(base64Encoded: value) ?? Data(), as: UTF8.self)
    }

    /// Eski veri ve günlük klasörünün adı.
    static let folder = decode("Q291Y2hTdWJz")
    /// Eski iPhone/iPad uygulamasının Anahtar Zinciri hizmet adı.
    static let keychainService = decode("Y29tLmNvdWNoc3Vicy5pb3M=")
}
