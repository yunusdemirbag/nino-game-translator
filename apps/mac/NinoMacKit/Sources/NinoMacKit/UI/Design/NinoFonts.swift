// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import CoreText
import SwiftUI

// Yazı tipleri (docs/yeni/mac/tasarim-dili.md §2).
//
//   Text("…").font(.nino(.headline))
//   Text("…").font(.subtitle(.condensed, size: 46, bold: true))
//
// Uygulama açılınca bir kez `NinoFonts.registerBundledFonts()` çağrılır (NinoScenes yapar);
// yazı tipleri yalnız bu uygulama için kaydedilir, sisteme kurulmaz.

/// Arayüz yazı belirteçleri. Boylar sabittir.
public enum NinoTextStyle: CaseIterable, Sendable {
    case display, title, headline, body, callout, caption, button, code

    public var size: CGFloat {
        switch self {
        case .display: return 28
        case .title: return 22
        case .headline: return 17
        case .body: return 15
        case .callout: return 13
        case .caption: return 13
        case .button: return 15
        case .code: return 22
        }
    }

    public var weight: Font.Weight {
        switch self {
        case .display, .title, .headline, .button, .code: return .semibold
        case .body: return .regular
        case .callout, .caption: return .medium
        }
    }
}

public extension Font {
    /// Tasarım dilindeki yazı belirteci.
    static func nino(_ style: NinoTextStyle) -> Font {
        let font = Font.system(size: style.size, weight: style.weight)
        return style == .code ? font.monospacedDigit() : font
    }

    /// Sistemin yuvarlak yazısı (kelime işareti, sürüm hapı, kurulum başlığı).
    static func ninoRounded(_ size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// "Impact" (yoksa sistemin en kalını), en kalın ağırlık. İndirme sayacı.
    static func ninoImpact(_ size: CGFloat) -> Font {
        if NSFont(name: "Impact", size: size) != nil {
            return .custom("Impact", fixedSize: size).weight(.black)
        }
        return .system(size: size, weight: .black)
    }

    /// Altyazı yazısı: sabit boy (sistemin yazı büyütmesiyle değişmez). Kalın değilse yarı kalın çizilir.
    static func subtitle(_ font: SubtitleStyle.Font, size: CGFloat, bold: Bool) -> Font {
        NinoFonts.subtitleFont(font, size: size, weight: bold ? .bold : .semibold)
    }
}

public enum NinoFonts {
    /// Paketteki yazı tipi dosyaları (Resources/Fonts).
    public static let bundledFontFiles = [
        "BarlowCondensed-SemiBold", "BarlowCondensed-Bold", "Barlow-SemiBold", "Barlow-Bold", "Nunito-Variable",
    ]

    @MainActor private static var registered = false

    /// Yazı tiplerini yalnız bu süreç için kaydeder. Birden çok çağrı zararsızdır.
    @MainActor
    public static func registerBundledFonts() {
        guard !registered else { return }
        registered = true
        let urls = bundledFontFiles.compactMap { Bundle.module.url(forResource: $0, withExtension: "ttf") }
        for url in urls {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            error?.release()
        }
    }

    /// Altyazı yazı tipi; "kalın" sayılanlar kalın ve üstü, kalan her şey yarı kalın çizilir.
    public static func subtitleFont(_ font: SubtitleStyle.Font, size: CGFloat, weight: Font.Weight) -> Font {
        let isBold = weight == .bold || weight == .heavy || weight == .black
        switch font {
        case .condensed:
            return .custom(isBold ? "BarlowCondensed-Bold" : "BarlowCondensed-SemiBold", fixedSize: size)
        case .modern:
            return .custom(isBold ? "Barlow-Bold" : "Barlow-SemiBold", fixedSize: size)
        case .rounded:
            return nunito(size: size, weight: isBold ? 700 : (weight == .medium ? 500 : 600))
        case .system:
            return .system(size: size, weight: isBold ? .bold : weight)
        }
    }

    /// Nunito değişken yazı tipi, istenen "wght" ekseniyle (adlı örnek adı SwiftUI'de ekseni yitiriyor).
    private static func nunito(size: CGFloat, weight: Double) -> Font {
        let wght = 0x7767_6874 // 'wght'
        let base = CTFontCreateWithName("Nunito-Regular" as CFString, size, nil)
        let variation = CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: [wght: weight]] as CFDictionary)
        return Font(CTFontCreateCopyWithAttributes(base, size, nil, variation))
    }

    /// Harf aralığı: Aksiyon'da boyun %1'i, diğerlerinde 0.
    public static func subtitleTracking(_ font: SubtitleStyle.Font, size: CGFloat) -> CGFloat {
        font == .condensed ? size * 0.01 : 0
    }

    /// Seçicideki sıra: Aksiyon, Modern, Yuvarlak, Sistem.
    public static let subtitleFontOrder: [SubtitleStyle.Font] = [.condensed, .modern, .rounded, .system]
}
