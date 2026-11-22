// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import SwiftUI

/// Çeviri dilleri. Kayıtlı ayarlarda kod tutulur ("tr", "ar", Filipince için "tl").
enum Languages {
    struct Choice: Hashable, Sendable {
        let code: String
        let name: String
        let flag: String
        let englishName: String
    }

    /// Seçicideki sıra; Türkçe en üstte.
    static let all: [Choice] = [
        Choice(code: "tr", name: "Türkçe", flag: "🇹🇷", englishName: "Turkish"),
        Choice(code: "ar", name: "العربية", flag: "🇸🇦", englishName: "Arabic"),
        Choice(code: "hi", name: "हिन्दी", flag: "🇮🇳", englishName: "Hindi"),
        Choice(code: "id", name: "Bahasa Indonesia", flag: "🇮🇩", englishName: "Indonesian"),
        Choice(code: "th", name: "ไทย", flag: "🇹🇭", englishName: "Thai"),
        Choice(code: "vi", name: "Tiếng Việt", flag: "🇻🇳", englishName: "Vietnamese"),
        Choice(code: "ur", name: "اردو", flag: "🇵🇰", englishName: "Urdu"),
        Choice(code: "bn", name: "বাংলা", flag: "🇧🇩", englishName: "Bengali"),
        Choice(code: "ms", name: "Bahasa Melayu", flag: "🇲🇾", englishName: "Malay"),
        Choice(code: "tl", name: "Filipino", flag: "🇵🇭", englishName: "Filipino"),
        Choice(code: "nl", name: "Nederlands", flag: "🇳🇱", englishName: "Dutch"),
    ]

    /// "tr-TR" → "tr"; "fil" → "tl".
    static func normalized(_ code: String) -> String {
        let lower = code.lowercased()
        if lower.hasPrefix("fil") { return "tl" }
        return String(lower.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
    }

    static func choice(_ code: String) -> Choice? { all.first { $0.code == normalized(code) } }
    static func flag(_ code: String) -> String { choice(code)?.flag ?? "🌐" }
    static func nativeName(_ code: String) -> String { choice(code)?.name ?? code }
    static func isTurkish(_ code: String) -> Bool { normalized(code) == "tr" }
    static func isRightToLeft(_ code: String) -> Bool { ["ar", "fa", "he", "ur"].contains(normalized(code)) }

    /// Arayüzün dili çeviri dilini izler. Apple Filipinceyi "fil" diye tanır.
    static func interfaceCode(for target: String) -> String {
        guard let c = choice(target) else { return "en" }
        return c.code == "tl" ? "fil" : c.code
    }

    /// İlk açılışta: sistem dili listedeyse o, değilse Türkçe.
    static func preferred(_ preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        guard let first = preferredLanguages.first, let c = choice(first) else { return "tr" }
        return c.code
    }

    static func locale(for target: String) -> Locale { Locale(identifier: interfaceCode(for: target)) }
    static func direction(for target: String) -> LayoutDirection { isRightToLeft(target) ? .rightToLeft : .leftToRight }

    /// `String(localized:)` ile okunan metinler de bir sonraki açılışta aynı dilde olsun.
    static func rememberInterface(for target: String, defaults: UserDefaults = .standard) {
        defaults.set([interfaceCode(for: target)], forKey: "AppleLanguages")
    }
}

/// Çeviri dili seçici: kapsül içinde bayrak (istenirse dilin adı) ve aşağı ok; dokununca dillerin listesi açılır.
struct LanguageMenu: View {
    @Binding var selection: String
    var showsName = false

    var body: some View {
        Menu {
            ForEach(Languages.all, id: \.code) { language in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selection = language.code }
                } label: {
                    if language.code == Languages.normalized(selection) {
                        Label { Text(verbatim: language.flag + "  " + language.name) } icon: { Image(systemName: "checkmark") }
                    } else {
                        Text(verbatim: language.flag + "  " + language.name)
                    }
                }
            }
        } label: {
            capsule
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: Languages.nativeName(selection)))
    }

    private var capsule: some View {
        let tint = DS.Palette.accent
        return HStack(spacing: 6) {
            Text(verbatim: Languages.flag(selection)).font(.system(size: 20))
            if showsName { Text(verbatim: Languages.nativeName(selection)).font(DS.Font.headline) }
            Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).opacity(0.7)
        }
        .foregroundStyle(DS.Palette.text)
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .background { Capsule().fill(tint.opacity(0.10)) }
        .overlay { Capsule().strokeBorder(tint.opacity(0.8), lineWidth: 1.5) }
        .contentShape(Capsule())
    }
}
