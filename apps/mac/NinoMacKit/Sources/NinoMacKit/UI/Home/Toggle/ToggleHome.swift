// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Cam anahtarlı orta alan (ana-ekran.md §5.1).
struct ToggleHome: View {
    let state: AppState
    let ui: HomeUIState
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ninoStaticRendering) private var isStatic
    @Environment(\.colorScheme) private var scheme

    private var on: Bool { state.translation == .on }

    var body: some View {
        GeometryReader { proxy in
            if isStatic {
                // ImageRenderer kaydırma alanını çizemez: içerik üstten başlar, taşan kesilir.
                content(minHeight: proxy.size.height)
                    .frame(height: proxy.size.height, alignment: .top)
                    .clipped()
            } else {
                ScrollView(.vertical) {
                    content(minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(ReturnKeyShortcut { ui.handleReturnKey(state) })
    }

    private func content(minHeight: CGFloat) -> some View {
        VStack(spacing: 16) {
            UpdateBanner(state: state)
            Spacer(minLength: 0)
            switchBlock
            HomeActionButtons(state: state)
            HomeWarnings(state: state)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NinoSpacing.xl)
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }

    private var switchBlock: some View {
        VStack(spacing: on ? 20 : 28) {
            if on {
                LiveTV(state: state)
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.94)))
            }
            GlassSwitch(state: state, ui: ui)
            if !on {
                HText("home.switch.description")
                    .font(.nino(.callout))
                    .foregroundStyle(NinoColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, on ? 12 : 40)
        .frame(maxWidth: .infinity)
        .background {
            Circle()
                .fill(on ? NinoFixedColor.flagRed.color(opacity: 0.22) : NinoColor.accent.color(scheme).opacity(0.10))
                .frame(width: 520, height: 520)
                .blur(radius: 90)
                .animation(.easeInOut(duration: 0.6), value: on)
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : NinoMotion.spring(0.6, 0.86), value: on)
    }
}

/// Anahtarın üstündeki canlı TV (§5.4). Her zaman soldan sağa.
struct LiveTV: View {
    let state: AppState

    var body: some View {
        let width: CGFloat = 580
        let height = width * 9 / 16
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(NinoRGB(0.05, 0.05, 0.07).color)
                screen.padding(7)
            }
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.28), radius: 24, y: 14)
            RoundedRectangle(cornerRadius: 2).fill(NinoRGB(0.12, 0.12, 0.15).color).frame(width: 34, height: 14)
            Capsule().fill(NinoRGB(0.12, 0.12, 0.15).color).frame(width: 150, height: 6)
            Text(verbatim: state.lastLine?.source.isEmpty == false ? state.lastLine!.source : " ")
                .font(.nino(.callout).italic())
                .foregroundStyle(NinoColor.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: width)
                .padding(.top, 10)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .combine)
    }

    private var screen: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ZStack {
            LinearGradient(colors: [NinoRGB(0.10, 0.13, 0.24).color, NinoRGB(0.16, 0.10, 0.20).color],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [NinoFixedColor.flagRed.color(opacity: 0.18), .clear], center: .bottomTrailing,
                           startRadius: 10, endRadius: 348)
            VStack(spacing: 0) {
                HStack {
                    LiveBadge()
                    Spacer()
                }
                Spacer(minLength: 0)
                LiveLineArea(line: state.lastLine, style: state.settings.style, size: 27)
                    .padding(.bottom, 10)
            }
            .padding(20)
        }
        .clipShape(shape)
    }
}
