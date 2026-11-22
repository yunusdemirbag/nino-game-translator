// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Ekranların açık buz mavisi zemini: çapraz degrade ve iki yumuşak ışık lekesi. Hareketsizdir.
struct ScreenBackground: View {
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                LinearGradient(colors: [Color(rgb: 0xF7FAFF), DS.Palette.deep],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [DS.Palette.accent.opacity(0.22), .clear],
                               center: UnitPoint(x: 0.10, y: 0.08),
                               startRadius: 0, endRadius: size.width * 0.9)
                RadialGradient(colors: [DS.Palette.pro.opacity(0.16), .clear],
                               center: UnitPoint(x: 0.95, y: 0.95),
                               startRadius: 0, endRadius: max(size.width, size.height * 0.5))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Uygulamanın en dış katmanı ve açılış animasyonunun zemini: yavaşça süzülen iki bulanık daire.
struct AppBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(rgb: 0xF7FAFF), Color(rgb: 0xE3EDFC)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(DS.Palette.accent.opacity(0.22))
                .frame(width: 520, height: 520)
                .blur(radius: 120)
                .offset(x: drift ? -260 : -200, y: drift ? -220 : -170)
            Circle()
                .fill(Color(rgb: 0x00215C).opacity(0.16))
                .frame(width: 600, height: 600)
                .blur(radius: 140)
                .offset(x: drift ? 300 : 240, y: drift ? 260 : 210)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}
