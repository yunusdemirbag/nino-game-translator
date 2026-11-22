// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

// Altyazı satırının çizimi (ana-ekran.md §9, §11.3, §12). TV'deki satır, canlı TV, ekran dışı pencere,
// yayın penceresi ve Ayarlar'daki önizlemeler bunu kullanır. Yön arayüzden değil yazının kendisinden gelir.

public enum SubtitleText {
    /// Arap harfli metinde her paragrafın başına görünmez sağdan sola işareti (U+200F) konur.
    public static func directional(_ text: String) -> String {
        guard text.containsArabicScript else { return text }
        return text.components(separatedBy: "\n").map { "\u{200F}" + $0 }.joined(separator: "\n")
    }

    public static func direction(of text: String) -> LayoutDirection {
        text.containsArabicScript ? .rightToLeft : .leftToRight
    }

    /// Klasik satırın bölünmesi: en çok 3 satıra dengeli (satır başına 42 karakter hedefi). Konuşmacı adı
    /// ("ARTHUR:") sonraki sözcükle birlikte tutulur. 3 satıra sığmazsa küçültme oranı (en az 0,75) döner.
    /// Satır sonu içeren ya da 42 karakterden kısa metin olduğu gibi kalır.
    public static func balancedLines(_ text: String, target: Int = 42) -> (text: String, shrink: CGFloat) {
        if text.contains("\n") || text.count <= target { return (text, 1) }
        var words: [String] = []
        let raw = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var index = 0
        while index < raw.count {
            if index == 0, raw[index].hasSuffix(":"), raw.count > 1 {
                words.append(raw[0] + " " + raw[1])
                index = 2
            } else {
                words.append(raw[index])
                index += 1
            }
        }
        let lineCount = min(3, Int((Double(text.count) / Double(target)).rounded(.up)))
        let perLine = Double(text.count) / Double(lineCount)
        var lines: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : current + " " + word
            if !current.isEmpty, Double(candidate.count) > perLine * 1.08, lines.count < lineCount - 1 {
                lines.append(current)
                current = word
            } else {
                current = candidate
            }
        }
        lines += current.isEmpty ? [] : [current]
        let longest = lines.map(\.count).max() ?? 0
        let shrink = longest > target ? max(0.75, CGFloat(target) / CGFloat(longest)) : 1
        return (lines.joined(separator: "\n"), shrink)
    }
}

/// Temalı satır (§12). B yazı boyudur.
public struct ThemedSubtitleLine: View {
    private let text: String
    private let style: SubtitleStyle
    private let size: CGFloat
    private let lineLimit: Int?

    public init(_ text: String, style: SubtitleStyle, size: CGFloat, lineLimit: Int? = 2) {
        self.text = text
        self.style = style
        self.size = size
        self.lineLimit = lineLimit
    }

    private var color: Color {
        style.textColor == .yellow ? NinoFixedColor.subtitleYellow.color : .white
    }

    private var weight: Font.Weight {
        switch style.theme {
        case .minimal: return .medium
        case .contrast, .outline, .cinema: return .bold
        case .classic, .glass: return style.bold ? .bold : .semibold
        }
    }

    private var label: some View { label(color) }

    private func label(_ color: Color) -> some View {
        Text(SubtitleText.directional(text))
            .font(NinoFonts.subtitleFont(style.font, size: size, weight: weight))
            .tracking(NinoFonts.subtitleTracking(style.font, size: size))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineLimit(lineLimit)
            .environment(\.layoutDirection, SubtitleText.direction(of: text))
    }

    public var body: some View {
        let b = size
        switch style.theme {
        case .classic:
            label
                .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                .padding(.horizontal, 0.5 * b)
                .padding(.vertical, 0.2 * b)
                .background(RoundedRectangle(cornerRadius: 0.3 * b, style: .continuous)
                    .fill(Color.black.opacity(Double(style.background) / 100 * 0.85)))
        case .cinema:
            label
                .shadow(color: .black, radius: 0.08 * b, y: 0.04 * b)
                .shadow(color: .black.opacity(0.9), radius: 0.3 * b)
        case .minimal:
            label
                .shadow(color: .black.opacity(0.9), radius: 0.06 * b, y: 1)
                .shadow(color: .black.opacity(0.5), radius: 0.25 * b)
        case .glass:
            let blue = NinoRGB(0.18, 0.55, 1.0)
            let shape = RoundedRectangle(cornerRadius: 0.45 * b, style: .continuous)
            label
                .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
                .padding(.horizontal, 0.6 * b)
                .padding(.vertical, 0.25 * b)
                .background(shape.fill(NinoRGB(0.024, 0.047, 0.118).color(opacity: 0.86)))
                .overlay(shape.strokeBorder(blue.color(opacity: 0.45), lineWidth: max(1, 0.045 * b)))
                .shadow(color: blue.color(opacity: 0.25), radius: 0.4 * b)
        case .contrast:
            label
                .padding(.horizontal, 0.45 * b)
                .padding(.vertical, 0.18 * b)
                .background(RoundedRectangle(cornerRadius: 0.12 * b, style: .continuous).fill(Color.black))
        case .outline:
            let offset = max(1, 0.07 * b)
            ZStack {
                ForEach(0..<8, id: \.self) { index in
                    let angle = Double(index) * .pi / 4
                    label(.black)
                        .offset(x: cos(angle) * offset, y: sin(angle) * offset)
                }
                label
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.6), radius: 0.15 * b)
        }
    }
}

/// Klasik satır (§11.3): ekran dışı pencerede "Klasik" tema ya da paragraf, yayın penceresinde her zaman.
public struct ClassicSubtitleLine: View {
    public enum Box: Sendable {
        /// Yarı saydam kutu (ekran dışı pencere): opaklık zemin yüzdesi / 100 (güncel değilse × 0,83).
        case translucent
        /// Yayın penceresi: zemin > 0 ise tam koyu kutu, 0 ise kutu yok.
        case solid
    }

    private let text: String
    private let style: SubtitleStyle
    private let scale: CGFloat
    private let isCurrent: Bool
    private let isParagraph: Bool
    private let box: Box
    private let fade: Double

    /// - Parameters:
    ///   - scale: Ekran yüksekliği / 1080.
    ///   - fade: Yayın penceresinde önceki satırların yazı solukluğu (1 / 0,6 / 0,45).
    public init(_ text: String, style: SubtitleStyle, scale: CGFloat, isCurrent: Bool, isParagraph: Bool = false,
                box: Box = .translucent, fade: Double = 1) {
        self.text = text
        self.style = style
        self.scale = scale
        self.isCurrent = isCurrent
        self.isParagraph = isParagraph
        self.box = box
        self.fade = fade
    }

    public var body: some View {
        let split = SubtitleText.balancedLines(text)
        let size = CGFloat(style.fontSize) * scale * (isCurrent ? 1 : 0.8) * split.shrink
        let color = style.textColor == .yellow ? NinoFixedColor.subtitleYellow.color : Color.white
        let hasBox = box == .translucent || style.background > 0
        let boxOpacity: Double = {
            switch box {
            case .translucent: return Double(style.background) / 100 * (isCurrent ? 1 : 0.83)
            case .solid: return style.background > 0 ? 1 : 0
            }
        }()
        let band = style.backgroundShape == .band
        let corner = band ? 0 : 10 * scale
        let shadowRadius: CGFloat = box == .solid && hasBox ? 0 : 2 * scale
        // Yayın penceresinde Arapça için yön işareti eklenmez.
        let shown = box == .solid ? split.text : SubtitleText.directional(split.text)
        Text(shown)
            .font(.subtitle(style.font, size: size, bold: style.bold))
            .tracking(NinoFonts.subtitleTracking(style.font, size: size))
            .lineSpacing(size * 0.3)
            .foregroundStyle(color.opacity(box == .solid && hasBox ? fade : 1))
            .multilineTextAlignment(isParagraph ? .leading : .center)
            .environment(\.layoutDirection, box == .solid ? .leftToRight : SubtitleText.direction(of: text))
            .shadow(color: shadowRadius > 0 ? .black : .clear, radius: shadowRadius, y: 2 * scale)
            .padding(.vertical, (isCurrent ? 10 : 6) * scale)
            .padding(.horizontal, (isCurrent ? 26 : 20) * scale)
            .frame(maxWidth: band ? .infinity : nil, alignment: isParagraph ? .leading : .center)
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.black.opacity(boxOpacity)))
    }
}

/// Ek alan kutusu (§11.3): görev, bildirim, telefon çevirisi.
public struct ExtraAreaBox: View {
    private let text: String
    private let style: SubtitleStyle
    private let scale: CGFloat
    private let solid: Bool

    public init(_ text: String, style: SubtitleStyle, scale: CGFloat, solid: Bool = false) {
        self.text = text
        self.style = style
        self.scale = scale
        self.solid = solid
    }

    public var body: some View {
        let scaled = CGFloat(style.fontSize) * scale * 0.55  // ek kutular altyazının yarısından biraz büyük
        let size = scaled < 12 ? 12 : scaled
        Text(SubtitleText.directional(text))
            .font(.subtitle(style.font, size: size, bold: false))
            .foregroundStyle(style.textColor == .yellow ? NinoFixedColor.subtitleYellow.color : Color.white)
            .multilineTextAlignment(.leading)
            .padding(.vertical, 6 * scale)
            .padding(.horizontal, 14 * scale)
            .background(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                .fill(Color.black.opacity(solid ? 1 : 0.85)))
    }
}

/// Tema ve yazı tipi adları (ana-ekran.md §12, tasarim-dili.md §2); Ayarlar'daki seçiciler de kullanır.
public enum SubtitleNames {
    public static func theme(_ theme: SubtitleStyle.Theme, locale: Locale) -> String {
        NinoL10n.string("home.theme.\(theme.rawValue)", table: HomeText.table, locale: locale)
    }

    /// Kısa tarif ("Yarı saydam kutu"…).
    public static func themeDetail(_ theme: SubtitleStyle.Theme, locale: Locale) -> String {
        NinoL10n.string("home.theme.\(theme.rawValue).detail", table: HomeText.table, locale: locale)
    }

    public static func font(_ font: SubtitleStyle.Font, locale: Locale) -> String {
        NinoL10n.string("home.font.\(font.rawValue)", table: HomeText.table, locale: locale)
    }
}
