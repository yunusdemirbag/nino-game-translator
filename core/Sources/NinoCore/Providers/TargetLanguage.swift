// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Çeviri hedef dili.
public struct TargetLanguage: Equatable, Hashable, Sendable {
    /// İki harfli kod (Filipince `tl`).
    public let code: String
    /// Dilin kendi adıyla adı.
    public let nativeName: String
    /// İstemlerde geçen İngilizce adı.
    public let promptName: String
    /// DeepL bu dile çeviriyor mu?
    public let deepLSupported: Bool

    public static let all: [TargetLanguage] = [
        .init(code: "tr", nativeName: "Türkçe", promptName: "Turkish", deepLSupported: true),
        .init(code: "ar", nativeName: "العربية", promptName: "Arabic", deepLSupported: true),
        .init(code: "hi", nativeName: "हिन्दी", promptName: "Hindi", deepLSupported: false),
        .init(code: "id", nativeName: "Bahasa Indonesia", promptName: "Indonesian", deepLSupported: true),
        .init(code: "th", nativeName: "ไทย", promptName: "Thai", deepLSupported: true),
        .init(code: "vi", nativeName: "Tiếng Việt", promptName: "Vietnamese", deepLSupported: true),
        .init(code: "ur", nativeName: "اردو", promptName: "Urdu", deepLSupported: false),
        .init(code: "bn", nativeName: "বাংলা", promptName: "Bengali", deepLSupported: false),
        .init(code: "ms", nativeName: "Bahasa Melayu", promptName: "Malay", deepLSupported: false),
        .init(code: "tl", nativeName: "Filipino", promptName: "Filipino", deepLSupported: false),
        .init(code: "nl", nativeName: "Nederlands", promptName: "Dutch", deepLSupported: true),
    ]

    public static let turkish = all[0]

    /// Kodu bulur: ilk iki harf, küçük harf; `fil…` → `tl`.
    public static func find(_ code: String) -> TargetLanguage? {
        let n = normalize(code)
        return all.first { $0.code == n }
    }

    public static func normalize(_ code: String) -> String {
        let c = code.trimmingCharacters(in: .whitespaces).lowercased()
        if c.hasPrefix("fil") { return "tl" }
        return String(c.prefix(2))
    }

    /// İlk açılış: sistem dillerinden ilki listedeyse o, değilse Türkçe.
    public static func initial(preferred: [String] = Locale.preferredLanguages) -> TargetLanguage {
        if let first = preferred.first, let lang = find(first) { return lang }
        return turkish
    }

    /// Arayüz dili kodu (Filipince `fil`).
    public var interfaceCode: String { code == "tl" ? "fil" : code }

    public var isRightToLeft: Bool { Self.isRightToLeft(code) }

    public static func isRightToLeft(_ code: String) -> Bool {
        ["ar", "fa", "he", "ur"].contains(normalize(code))
    }

    /// Arap harfi içeren her paragrafın başına U+200F koyar (varsa eklemez).
    public static func markRightToLeft(_ text: String) -> String {
        text.components(separatedBy: "\n").map { p in
            guard p.unicodeScalars.contains(where: isArabicScalar), !p.hasPrefix("\u{200F}") else { return p }
            return "\u{200F}" + p
        }.joined(separator: "\n")
    }

    static func isArabicScalar(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF: return true
        default: return false
        }
    }
}
