// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

// Renk belirteçleri (docs/yeni/mac/tasarim-dili.md §1).
//
// Kullanım:
//   Text("…").foregroundStyle(NinoColor.textSecondary)          // ShapeStyle olarak; tema ortamdan okunur
//   .shadow(color: NinoColor.accent.color(scheme).opacity(0.35)) // düz Color gerektiğinde
//   @Environment(\.colorScheme) var scheme
//
// Renkler ortamdaki `colorScheme`'e göre çözülür; `preferredColorScheme` yerine
// `.environment(\.colorScheme, …)` de yeter (ekran görüntüsü testleri böyle çalışır).

/// sRGB bir rengi 0–1 bileşenlerle ya da onaltılık değerle tanımlar.
public struct NinoRGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `0xEEF3FB` biçiminde onaltılık değer.
    public init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    /// Gri ton: üç bileşen aynı.
    public init(gray: Double) { self.init(gray, gray, gray) }

    public var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
    public func color(opacity: Double) -> Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity) }
}

/// Açık ve koyu temada ayrı değeri olan renk belirteci.
public struct NinoColor: ShapeStyle, Equatable, Sendable {
    public var light: NinoRGB
    public var dark: NinoRGB
    /// Açık temadaki opaklık.
    public var lightOpacity: Double
    /// Koyu temadaki opaklık.
    public var darkOpacity: Double

    public init(light: NinoRGB, dark: NinoRGB, lightOpacity: Double = 1, darkOpacity: Double = 1) {
        self.light = light
        self.dark = dark
        self.lightOpacity = lightOpacity
        self.darkOpacity = darkOpacity
    }

    public init(light: UInt32, dark: UInt32) {
        self.init(light: NinoRGB(hex: light), dark: NinoRGB(hex: dark))
    }

    /// Belli bir temadaki düz renk.
    public func color(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? dark.color(opacity: darkOpacity) : light.color(opacity: lightOpacity)
    }

    /// Aynı belirtecin saydamlaştırılmış hâli (ShapeStyle olarak da kullanılır).
    public func opacity(_ value: Double) -> NinoColor {
        NinoColor(light: light, dark: dark, lightOpacity: lightOpacity * value, darkOpacity: darkOpacity * value)
    }

    public func resolve(in environment: EnvironmentValues) -> Color {
        color(environment.colorScheme)
    }

    // MARK: Belirteçler (§1)

    public static let background = NinoColor(light: 0xEEF3FB, dark: 0x050A1A)
    public static let surface = NinoColor(light: 0xFFFFFF, dark: 0x0E1733)
    public static let surface2 = NinoColor(light: 0xE6EDF8, dark: 0x16224A)
    public static let tileBorder = NinoColor(light: 0xDCE5F3, dark: 0x22305A)
    public static let border = NinoColor(light: 0xD3DEEF, dark: 0x2A3A68)
    public static let textPrimary = NinoColor(light: 0x0A1430, dark: 0xF2F5FB)
    public static let textSecondary = NinoColor(light: 0x55607A, dark: 0x9DA9C6)
    public static let accent = NinoColor(light: 0x0070D1, dark: 0x2D8CFF)
    public static let accentHi = NinoColor(light: 0x1A86E8, dark: 0x5AA6FF)
    public static let onAccent = NinoColor(light: 0xFFFFFF, dark: 0xFFFFFF)
    public static let accentText = NinoColor(light: 0x0058A8, dark: 0x7DB8FF)
    public static let accentSoft = NinoColor(light: 0xDDEBFA, dark: 0x132A55)
    public static let pro = NinoColor(light: 0x00205B, dark: 0x9FC2FF)
    public static let proSoft = NinoColor(light: 0xE2E8F5, dark: 0x1A2A50)
    public static let success = NinoColor(light: 0x1E6B45, dark: 0x5FD39A)
    public static let successSoft = NinoColor(light: 0xDDF1E6, dark: 0x123527)
    public static let warning = NinoColor(light: 0x9A4A08, dark: 0xF5AE62)
    public static let danger = NinoColor(light: 0xB3261E, dark: 0xFF8A80)
    public static let dangerSoft = NinoColor(light: 0xFBE4E2, dark: 0x3A1E24)
    public static let dangerBorder = NinoColor(light: 0xEDB6B0, dark: 0x6B3A40)
    public static let onDanger = NinoColor(light: 0xFFFFFF, dark: 0x17181B)

    // MARK: Temaya bağlı sabitler (§1, "belirteç dışındaki sabit renkler")

    /// Cam yüzeylerin 1 pt kenarı; açıkta beyaz %75, koyuda beyaz %12.
    public static let glassEdge = NinoColor(light: NinoRGB(gray: 1), dark: NinoRGB(gray: 1),
                                            lightOpacity: 0.75, darkOpacity: 0.12)
    /// Cam yüzeyin altına serilen renk; açıkta beyaz %55, koyuda (0.06, 0.10, 0.22) %55.
    public static let glassFill = NinoColor(light: NinoRGB(gray: 1), dark: NinoRGB(0.06, 0.10, 0.22),
                                            lightOpacity: 0.55, darkOpacity: 0.55)
}

/// Temayla değişmeyen sabit renkler (§1).
public enum NinoFixedColor {
    /// Birincil düğme, seçili bölme, simge kutusu degradesinin sonu.
    public static let deepNavy = NinoRGB(0.0, 0.19, 0.52)
    /// Açık çeviri anahtarı, CANLI noktası, canlı ışık.
    public static let flagRed = NinoRGB(0.89, 0.04, 0.09)
    /// Anahtar izinin alt tonu.
    public static let flagRedDark = NinoRGB(0.66, 0.02, 0.08)
    /// Sarı altyazı (#FFE135).
    public static let subtitleYellow = NinoRGB(1.0, 0.88, 0.21)
    /// TV'deki "Toplam İndirme" sayısı.
    public static let downloadGreen = NinoRGB(0.48, 0.91, 0.48)
}
