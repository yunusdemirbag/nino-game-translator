// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Arayüz metinleri. Arayüz dili çeviri dilini izler ve uygulama yeniden açılmadan anında değişir; bu yüzden metinler
/// sistemin seçtiği dilden değil, burada tutulan dilin paketinden okunur.
enum Loc {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var code = "tr"
    nonisolated(unsafe) private static var bundle: Bundle?

    /// Arayüz dili ("tr", "ar", "fil" …).
    static var language: String { lock.withLock { code } }

    static func setLanguage(_ newCode: String) {
        let path = Bundle.main.path(forResource: newCode, ofType: "lproj")
        lock.withLock {
            code = newCode
            bundle = path.flatMap(Bundle.init(path:))
        }
    }

    static func text(_ key: String) -> String {
        let b = lock.withLock { bundle }
        if let b {
            let value = b.localizedString(forKey: key, value: "\u{0}", table: nil)
            if value != "\u{0}" { return value }
        }
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static var locale: Locale { Locale(identifier: language) }
}

/// Arayüz metni; ek değerler `%@` / `%lld` yerlerine konur.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = Loc.text(key)
    return args.isEmpty ? format : String(format: format, locale: Loc.locale, arguments: args)
}
