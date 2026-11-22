// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreText
import SwiftUI
import UIKit

/// Uygulama içi logo. Görselin kenarında parıltı payı olduğu için 1.21 kat büyük çizilip istenen kareye konur.
struct NinoLogo: View {
    var size: CGFloat = 40

    var body: some View {
        Image("Logo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size * 1.21, height: size * 1.21)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// "Nino / GAME TRANSLATOR" yazısı.
struct NinoWordmark: View {
    var size: CGFloat = 24
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: size * 0.02) {
            Text(verbatim: "Nino").font(.system(size: size, weight: .bold, design: .rounded))
            Text(verbatim: "GAME TRANSLATOR")
                .font(.system(size: max(8, size * 0.32), weight: .semibold, design: .rounded))
                .tracking(size * 0.09)
                .foregroundStyle(DS.Palette.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Nino Game Translator"))
    }
}

// MARK: Altyazı yazı tipleri

/// Altyazının yazı tipi. Ham değerler kayıtlı ayarlarla aynıdır.
enum SubtitleTypeface: String, CaseIterable, Codable, Sendable {
    case action = "condensed", modern, rounded, system

    var title: String {
        switch self {
        case .action: L("pack.style.action")
        case .modern: L("subtitle.font.modern")
        case .rounded: L("subtitle.font.rounded")
        case .system: L("subtitle.font.system")
        }
    }

    private var files: (regular: String, bold: String)? {
        switch self {
        case .action: ("BarlowCondensed-SemiBold", "BarlowCondensed-Bold")
        case .modern: ("Barlow-SemiBold", "Barlow-Bold")
        case .rounded: ("Nunito-SemiBold", "Nunito-Bold")
        case .system: nil
        }
    }

    /// Sabit boyda yazı tipi (Dinamik Yazı ile büyümez).
    func font(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        SubtitleFonts.registerOnce()
        guard let files else { return .system(size: size, weight: weight) }
        let heavy = [Font.Weight.bold, .heavy, .black].contains(weight)
        return .custom(heavy ? files.bold : files.regular, fixedSize: size)
    }

    /// Aksiyon yazısında harf aralığı boyun %1'i.
    func tracking(size: CGFloat) -> CGFloat { self == .action ? size * 0.01 : 0 }
}

enum SubtitleFonts {
    private static let once: Void = {
        guard let folder = Bundle.main.url(forResource: "fonts", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static func registerOnce() { _ = once }
}

// MARK: Sağdan sola

enum TextDirection {
    /// Metinde Arap harfi var mı.
    static func isArabic(_ text: String) -> Bool {
        text.unicodeScalars.contains { s in
            switch s.value {
            case 0x0620...0x064A, 0x066E...0x06D3, 0x06FA...0x06FF, 0x0750...0x077F,
                 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF: true
            default: false
            }
        }
    }

    /// Arapça metnin her satırının başına sağdan sola işareti koyar.
    static func prepared(_ text: String) -> String {
        guard isArabic(text) else { return text }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "\u{200F}" + $0 }
            .joined(separator: "\n")
    }
}

extension View {
    /// Altyazı metninin yönü yazının kendisinden seçilir.
    @ViewBuilder func subtitleDirection(for text: String, fill: Bool = false) -> some View {
        if TextDirection.isArabic(text) {
            environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: fill ? .infinity : nil)
        } else {
            self
        }
    }
}
