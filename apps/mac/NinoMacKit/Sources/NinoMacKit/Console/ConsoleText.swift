// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// `Resources/Console.xcstrings` tablosundan metin.
enum ConsoleText {
    static let table = "Console"

    static func string(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), table: table, bundle: .module)
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: args)
    }

    /// "İleti (ayrıntı) Sorun sürerse bu dosyayı bize gönderin: <yol>".
    static func withDetailAndLog(_ message: String, detail: String?, logPath: String) -> String {
        var text = message
        if let extra = detail, !extra.isEmpty {
            text += " (" + extra + ")"
        }
        if !logPath.isEmpty { text += " " + format("console.error.sendLog", logPath) }
        return text
    }
}
