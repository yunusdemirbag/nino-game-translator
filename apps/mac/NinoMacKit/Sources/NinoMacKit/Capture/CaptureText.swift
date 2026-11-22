// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// `Resources/Capture.xcstrings` tablosundan metin (görüntü kaynakları ve Greenlight kurulumu).
enum CaptureText {
    static let table = "Capture"

    static func string(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), table: table, bundle: .module)
    }
}
