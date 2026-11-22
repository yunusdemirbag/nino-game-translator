// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Açılış animasyonu (ana-ekran.md §7). Pencerenin tamamında ve salondaki TV'de (küçültülmüş, koyu) oynar.
/// Ekran görüntüsünde (`ninoStaticRendering`) logonun ve yazının son hâli durur, bitiş bildirilmez.
public struct NinoSplashView: View {
    private let onFinished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ninoStaticRendering) private var isStatic
    @Environment(\.colorScheme) private var scheme

    @State private var logoIn = false
    @State private var captionVisible = false
    @State private var spin = false
    @State private var flagGlow = 0.0
    @State private var glint = 0.0
    @State private var exiting = false

    public init(onFinished: @escaping () -> Void = {}) {
        self.onFinished = onFinished
    }

    public var body: some View {
        let shownLogo = logoIn || isStatic
        let shownText = captionVisible || isStatic
        ZStack {
            NinoWindowBackground()
            VStack(spacing: 28) {
                ZStack {
                    ring.opacity(shownLogo ? 1 : 0)
                    Circle()
                        .fill(NinoColor.accent.color(scheme).opacity(0.25))
                        .frame(width: 220, height: 220)
                        .blur(radius: 60)
                        .scaleEffect(shownLogo ? 1 : 0.4)
                    NinoLogo(size: 200)
                        .overlay { flagGlint.offset(y: -65) }
                        .scaleEffect(shownLogo ? 1 : 0.72)
                        .blur(radius: shownLogo ? 0 : 14)
                        .opacity(shownLogo ? 1 : 0)
                }
                .frame(width: 290, height: 290)
                VStack(spacing: 6) {
                    NinoWordmark(size: 34, alignment: .center)
                    HText("home.splash.tagline")
                        .font(.nino(.body))
                        .foregroundStyle(NinoColor.textSecondary)
                }
                .opacity(shownText ? 1 : 0)
                .offset(y: shownText ? 0 : 12)
            }
            .scaleEffect(exiting ? 1.06 : 1)
            .opacity(exiting ? 0 : 1)
        }
        .accessibilityHidden(true)
        .task { await play() }
    }

    private var ring: some View {
        Circle()
            .strokeBorder(AngularGradient(colors: [.clear, NinoColor.accent.color(scheme),
                                                   NinoColor.accentHi.color(scheme), .clear, .clear],
                                          center: .center), lineWidth: 3)
            .frame(width: 290, height: 290)
            .blur(radius: 1.5)
            .rotationEffect(.degrees(spin ? 360 : 0))
    }

    /// Logodaki bayrağın üstünde kırmızı ışık ve kayan parıltı. Bayrak alanı ≈ 59,8 × 21,2.
    private var flagGlint: some View {
        let flag = CGSize(width: 59.8, height: 21.2)
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(NinoRGB(0.95, 0.12, 0.16).color)
                .frame(width: flag.width * 1.15, height: flag.height * 1.3)
                .blur(radius: 18)
                .blendMode(.screen)
                .opacity(flagGlow)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading,
                                     endPoint: .trailing))
                .frame(width: flag.width * 0.35, height: flag.height)
                .offset(x: flag.width * (-0.75 + 1.5 * glint))
                .opacity(glint > 0 ? 1 - glint : 0)
                .blendMode(.plusLighter)
                .frame(width: flag.width, height: flag.height)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .allowsHitTesting(false)
    }

    private func play() async {
        guard !isStatic else { return }
        if reduceMotion {
            logoIn = true
            captionVisible = true
            try? await Task.sleep(for: .milliseconds(900))
            onFinished()
            return
        }
        withAnimation(NinoMotion.spring(0.9, 0.72)) { logoIn = true }
        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { spin = true }
        try? await Task.sleep(for: .milliseconds(650))
        withAnimation(.easeOut(duration: 0.6)) { captionVisible = true }
        // Bayrak ışığı: yanar, söner, yeniden yanar; sönüşe kadar yanık kalır.
        Task { @MainActor in
            for target in [0.85, 0.0, 0.85] {
                withAnimation(.easeInOut(duration: 0.55)) { flagGlow = target }
                try? await Task.sleep(for: .milliseconds(550))
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeInOut(duration: 0.9)) { glint = 1 }
        }
        try? await Task.sleep(for: .milliseconds(1700))
        withAnimation(.easeIn(duration: 0.45)) { exiting = true }
        try? await Task.sleep(for: .milliseconds(450))
        onFinished()
    }
}
