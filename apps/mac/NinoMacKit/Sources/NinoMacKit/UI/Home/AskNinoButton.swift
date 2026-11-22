// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Yüzen robot düğmesi "Nino'ya Sor" (ana-ekran.md §1.4) ve "Başladı" balonu.
/// Yüzün kendi çizimi ve hareketi ayrı tarifte; burada basit süzülme ve göz kırpma var.
struct AskNinoButton: View {
    let state: AppState
    let showBubble: Bool
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ninoStaticRendering) private var isStatic
    @State private var hovering = false
    @State private var floatUp = false
    @State private var blinking = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                state.open(.askNino)
            } label: {
                (blinking ? NinoBotImage.blink : NinoBotImage.open).image
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .offset(y: floatUp ? -2 : 2)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Color.white.opacity(0.92)))
                    .ninoGlass(in: Circle(), interactive: true)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .shadow(color: NinoColor.pro.color(scheme).opacity(hovering ? 0.28 : 0.18), radius: hovering ? 16 : 12, y: 6)
            .scaleEffect(hovering ? 1.05 : 1)
            .animation(NinoMotion.spring(0.3, 0.7), value: hovering)
            .onHover { hovering = $0 }
            .help(HomeText.string("home.askNino", locale))
            .accessibilityLabel(HomeText.string("home.askNino", locale))
            if showBubble {
                HText("home.startedBubble")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                    .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                            removal: .opacity))
            }
        }
        .task { await idle() }
    }

    private func idle() async {
        guard !isStatic, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { floatUp = true }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 3...5)))
            blinking = true
            try? await Task.sleep(for: .milliseconds(140))
            blinking = false
        }
    }
}
