// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI
import UIKit

/// Nino'nun tasarım değerleri. Ekranlar sabit sayı ya da renk yazmaz; hepsi buradan gelir.
/// Tarif: docs/yeni/ios/tasarim.md, bölüm 1.
enum DS {
    enum Space {
        static let screen: CGFloat = 20
        static let gap: CGFloat = 12
        static let tile: CGFloat = 16
        static let inline: CGFloat = 8
        static let hair: CGFloat = 4
    }

    enum Radius {
        static let tile: CGFloat = 22
        static let control: CGFloat = 16
        static let inner: CGFloat = 8
        static let tag: CGFloat = 6
        static let stage: CGFloat = 28
    }

    enum Size {
        static let button: CGFloat = 58
        static let smallButton: CGFloat = 44
        static let icon: CGFloat = 44
        static let field: CGFloat = 52
        static let row: CGFloat = 52
        static let tag: CGFloat = 24
        /// iPad'de içerik sütununun en büyük genişliği.
        static let readable: CGFloat = 680
    }

    enum Palette {
        static let deep = Color(rgb: 0xE3ECFA)
        static let bg = Color(rgb: 0xEEF3FB)
        static let surface = Color.white.opacity(0.85)
        static let surface2 = Color(rgb: 0xE6EDF8)
        static let border = Color.white.opacity(0.75)
        static let borderStrong = Color(rgb: 0xD3DEEF)
        static let text = Color(rgb: 0x0A1430)
        static let secondary = Color(rgb: 0x55607A)
        static let tertiary = Color(rgb: 0x8A93A8)
        static let accent = Color(rgb: 0x0070D1)
        static let accentHi = Color(rgb: 0x1A86E8)
        static let accentText = Color(rgb: 0x0058A8)
        static let navy = Color(rgb: 0x003085)
        static let pro = Color(rgb: 0x00205B)
        static let proSoft = Color(rgb: 0xE2E8F5)
        static let success = Color(rgb: 0x1E6B45)
        static let warning = Color(rgb: 0x9A4A08)
        static let danger = Color(rgb: 0xB3261E)
        static let dangerSoft = Color(rgb: 0xFBE4E2)
        static let subtitleYellow = Color(rgb: 0xFFD54A)
        // Koyu sahne
        static let stageTop = Color(rgb: 0x151E36)
        static let stageBottom = Color(rgb: 0x06080F)
        static let freeGreen = Color(rgb: 0x6EE7A8)
        // Birincil düğme
        static let primaryTop = Color(rgb: 0x1B2747)
    }

    enum Font {
        static let display = SwiftUI.Font.system(size: 28, weight: .semibold)
        static let title = SwiftUI.Font.system(size: 22, weight: .semibold).monospacedDigit()
        static let headline = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 15)
        static let caption = SwiftUI.Font.system(size: 13, weight: .medium)
        static let heroTitle = SwiftUI.Font.system(size: 32, weight: .bold)
        static let heroLead = SwiftUI.Font.system(size: 16)
        static let step = SwiftUI.Font.system(size: 13, weight: .semibold)
    }

    /// Cihaz iPad mi (boyut sınıfına değil, cihaza bakılır).
    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
}

extension Color {
    /// 0xRRGGBB biçiminde renk.
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: opacity)
    }
}
