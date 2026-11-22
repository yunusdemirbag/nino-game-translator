// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Açılış animasyonu (salondaki TV'nin içinde oynar): dönen ışık halkası, netleşen logo, marka yazısı.
struct SplashView: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoIn = false
    @State private var textIn = false
    @State private var spin = false
    @State private var leaving = false
    @State private var flagGlow = false
    @State private var shine = false

    var body: some View {
        ZStack {
            AppBackdrop()
            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .strokeBorder(AngularGradient(colors: [.clear, DS.Palette.accent, DS.Palette.accentHi, .clear, .clear],
                                                      center: .center), lineWidth: 3)
                        .frame(width: 290, height: 290)
                        .blur(radius: 1.5)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .opacity(logoIn ? 1 : 0)
                    Circle()
                        .fill(DS.Palette.accent.opacity(0.25))
                        .frame(width: 220, height: 220)
                        .blur(radius: 60)
                        .scaleEffect(logoIn ? 1 : 0.4)
                    NinoLogo(size: 200)
                        .overlay { flagHighlight }
                        .scaleEffect(logoIn ? 1 : 0.72)
                        .blur(radius: logoIn ? 0 : 14)
                        .opacity(logoIn ? 1 : 0)
                }
                VStack(spacing: 6) {
                    NinoWordmark(size: 34)
                    Text(L("home.tagline")).font(DS.Font.body).foregroundStyle(DS.Palette.secondary)
                }
                .opacity(textIn ? 1 : 0)
                .offset(y: textIn ? 0 : 12)
            }
            .scaleEffect(leaving ? 1.06 : 1)
            .opacity(leaving ? 0 : 1)
        }
        .task { await run() }
    }

    /// Logodaki bayrağın üstünde kırmızı nabız ve geçen beyaz parlama.
    private var flagHighlight: some View {
        let box = CGSize(width: 59.8, height: 21.2)
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.95, green: 0.12, blue: 0.16))
                .frame(width: box.width * 1.15, height: box.height * 1.3)
                .blur(radius: 18)
                .blendMode(.screen)
                .opacity(flagGlow ? 0.85 : 0)
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: box.width * 0.35, height: box.height)
                .offset(x: shine ? box.width * 0.75 : -box.width * 0.75)
                .opacity(shine ? 0 : 1)
                .blendMode(.plusLighter)
                .frame(width: box.width, height: box.height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .opacity(textIn ? 1 : 0)
        }
        .offset(y: -65)
        .allowsHitTesting(false)
    }

    private func run() async {
        if reduceMotion {
            logoIn = true
            textIn = true
            try? await Task.sleep(for: .milliseconds(900))
            onFinish()
            return
        }
        withAnimation(.spring(response: 0.9, dampingFraction: 0.72)) { logoIn = true }
        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { spin = true }
        try? await Task.sleep(for: .milliseconds(650))
        withAnimation(.easeOut(duration: 0.6)) { textIn = true }
        withAnimation(.easeInOut(duration: 0.55).repeatCount(6, autoreverses: true)) { flagGlow = true }
        withAnimation(.easeInOut(duration: 0.9).delay(0.15)) { shine = true }
        try? await Task.sleep(for: .milliseconds(1700))
        withAnimation(.easeIn(duration: 0.45)) { leaving = true }
        try? await Task.sleep(for: .milliseconds(450))
        onFinish()
    }
}
