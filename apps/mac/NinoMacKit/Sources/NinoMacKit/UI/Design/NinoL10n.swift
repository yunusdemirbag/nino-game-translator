// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

// Metinler (docs/yeni/mac/mimari.md, "Metinler").
//
// Arayüz dili çeviri diliyle aynıdır ve ortamdaki `\.locale`'den okunur. Her alan kendi
// tablosunu kullanır (`Home`, `Settings`, …):
//
//   NinoText("home.status.connected", table: "Home")                 // görünüm
//   NinoL10n.string("home.version %@", table: "Home", locale: locale, version)  // düz metin
//
// Desteklenmeyen dilde İngilizceye düşülür. Filipince için "fil" kullanılır.

public enum NinoL10n {
    /// Arayüz dilinin kodu ("tr", "ar", "fil"…). Filipince "tl" de "fil" sayılır.
    public static func languageCode(for locale: Locale) -> String {
        let code = locale.language.languageCode?.identifier ?? "en"
        return code == "tl" ? "fil" : code
    }

    /// Çeviri dili sağdan sola yazılıyorsa (Arapça, Farsça, İbranice, Urduca).
    public static func isRightToLeft(languageCode: String) -> Bool {
        ["ar", "fa", "he", "ur"].contains(languageCode)
    }

    /// Bir anahtarın arayüz dilindeki karşılığı; yoksa İngilizcesi, o da yoksa anahtarın kendisi.
    public static func string(_ key: String, table: String, locale: Locale, _ arguments: CVarArg...) -> String {
        string(key, table: table, language: languageCode(for: locale), arguments: arguments)
    }

    public static func string(_ key: String, table: String, language: String, arguments: [CVarArg] = []) -> String {
        let format = lookup(key, table: table, language: language)
            ?? lookup(key, table: table, language: "en")
            ?? key
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: language), arguments: arguments)
    }

    private static let missing = "\u{1}__nino_missing__"

    private static func lookup(_ key: String, table: String, language: String) -> String? {
        guard let bundle = languageBundle(language) else { return nil }
        let value = bundle.localizedString(forKey: key, value: missing, table: table)
        return value == missing ? nil : value
    }

    private static let bundleCache = NSCache<NSString, Bundle>()

    private static func languageBundle(_ language: String) -> Bundle? {
        if let cached = bundleCache.object(forKey: language as NSString) { return cached }
        guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        bundleCache.setObject(bundle, forKey: language as NSString)
        return bundle
    }
}

/// Ortamdaki arayüz diliyle çevrilen metin. `Text` gibi `.font`, `.foregroundStyle` alır.
public struct NinoText: View {
    private let key: String
    private let table: String
    private let arguments: [CVarArg]
    @Environment(\.locale) private var locale

    public init(_ key: String, table: String, _ arguments: CVarArg...) {
        self.init(key, table: table, arguments: arguments)
    }

    public init(_ key: String, table: String, arguments: [CVarArg]) {
        self.key = key
        self.table = table
        self.arguments = arguments
    }

    public var body: some View {
        Text(verbatim: NinoL10n.string(key, table: table, language: NinoL10n.languageCode(for: locale),
                                       arguments: arguments))
    }
}

/// Metnin içinde Arap harfi var mı (harf aralığı, eğim ve yazı yönü kuralları, ana-ekran.md §9).
public extension String {
    var containsArabicScript: Bool {
        unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) || (0x0750...0x077F).contains($0.value)
            || (0x08A0...0x08FF).contains($0.value) || (0xFB50...0xFDFF).contains($0.value)
            || (0xFE70...0xFEFF).contains($0.value) }
    }
}
