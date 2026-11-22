// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Boşluk ölçeği (tasarim-dili.md §3).
public enum NinoSpacing {
    /// 4: yazı ile alt satırı arası.
    public static let xs: CGFloat = 4
    /// 8: simge ile yazı arası, sıkı yığınlar.
    public static let s: CGFloat = 8
    /// 12: karo içi satırlar, karolar arası.
    public static let m: CGFloat = 12
    /// 16: karonun iç boşluğu, düğmenin yatay iç boşluğu.
    public static let l: CGFloat = 16
    /// 24: ekran kenar boşluğu.
    public static let xl: CGFloat = 24
    /// 32: büyük ayrım.
    public static let xxl: CGFloat = 32
}

/// Köşe yarıçapları (§4). Hepsi sürekli (squircle) köşe ile çizilir: `NinoRadius.shape(.card)`.
public enum NinoRadius {
    public static let card: CGFloat = 22
    public static let control: CGFloat = 14
    public static let inner: CGFloat = 10
    public static let tag: CGFloat = 6
    public static let pill: CGFloat = 999

    /// Sürekli köşeli yuvarlak dikdörtgen.
    public static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

/// Sabit ölçüler (§5).
public enum NinoSize {
    public static let buttonHeight: CGFloat = 40
    public static let buttonHeightLarge: CGFloat = 44
    public static let buttonHeightHero: CGFloat = 52
    public static let rowHeight: CGFloat = 40
    public static let keyIcon: CGFloat = 24
    public static let statusDot: CGFloat = 8
    public static let sidebarWidth: CGFloat = 240
    public static let mainColumn: CGFloat = 380
    public static let windowWidth: CGFloat = 1040
    public static let windowHeight: CGFloat = 720
    /// Ana pencerenin en çok genişliği (1040 × 1,25).
    public static let windowMaxWidth: CGFloat = 1300
}

/// Animasyonlar için ortak yardımcılar.
public enum NinoMotion {
    /// "Yay (t, s)": t tepki süresi, s sönüm oranı.
    public static func spring(_ response: Double, _ damping: Double) -> Animation {
        .spring(response: response, dampingFraction: damping)
    }
}

public extension View {
    /// "Hareketi azalt" açıksa animasyonsuz, değilse verilen animasyonla.
    func ninoAnimation<V: Equatable>(_ animation: Animation?, value: V, reduceMotion: Bool) -> some View {
        self.animation(reduceMotion ? nil : animation, value: value)
    }
}
