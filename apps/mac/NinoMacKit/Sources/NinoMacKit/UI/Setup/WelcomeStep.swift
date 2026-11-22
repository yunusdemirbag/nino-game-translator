// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Adım 1: Hoş geldin (kurulum.md §3). Üç hâl: konsol seçimi, PS5 karşılaması, Xbox karşılaması.
struct WelcomeStep: View {
    let state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            switch state.setup.welcome {
            case .chooseConsole: ConsoleChoice(state: state).transition(.opacity)
            case .ps5: PS5Welcome(state: state).transition(.opacity)
            case .xbox: XboxWelcome(state: state).transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: state.setup.welcome)
    }
}

// MARK: - 3a. Konsol seçimi

private struct ConsoleChoice: View {
    let state: AppState
    @Environment(\.locale) private var locale

    var body: some View {
        NinoSetupStepLayout(icon: .logo, title: SetupText.string("setup.welcome.choose.title", locale),
                            message: SetupText.string("setup.welcome.choose.message", locale)) {
            HStack(spacing: NinoSpacing.m) {
                ConsoleCard(asset: .consolePS5, upright: true, name: "PS5",
                            detail: SetupText.string("setup.welcome.choose.ps5", locale)) {
                    SetupFlow.chooseConsole(.ps5, state)
                }
                ConsoleCard(asset: .consoleXbox, upright: false, name: "Xbox",
                            detail: SetupText.string("setup.welcome.choose.xbox", locale)) {
                    SetupFlow.chooseConsole(.xbox, state)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Büyük konsol kartı: üstte sehpada duran görsel, altında ad + ok ve açıklama.
private struct ConsoleCard: View {
    let asset: NinoAsset
    let upright: Bool
    let name: String
    let detail: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: NinoSpacing.s) {
                asset.image
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(.horizontal, upright ? 0 : 12)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180, alignment: .bottom)
                HStack {
                    Text(verbatim: name).font(.nino(.headline)).foregroundStyle(NinoColor.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: NinoSymbol.chevron)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(hovering ? NinoColor.accentText : NinoColor.textSecondary)
                        .flipsForRightToLeftLayoutDirection(true)
                }
                .padding(.top, NinoSpacing.xs)
                Text(detail)
                    .font(.nino(.callout))
                    .foregroundStyle(NinoColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 280 - 2 * NinoSpacing.l, alignment: .topLeading)
            .ninoTile()
            .overlay {
                if hovering {
                    NinoRadius.shape(NinoRadius.card).strokeBorder(NinoColor.accent.opacity(0.9), lineWidth: 1.5)
                }
            }
            .contentShape(NinoRadius.shape(NinoRadius.card))
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(verbatim: "\(name), \(detail)"))
    }
}

// MARK: - 3c. PS5 karşılaması

private struct PS5Welcome: View {
    let state: AppState
    @Environment(\.locale) private var locale

    private var messageKey: String {
        switch state.settings.targetLanguage {
        case "tr": return "setup.welcome.ps5.message.turkish"
        case "ar": return "setup.welcome.ps5.message.arabic"
        default: return "setup.welcome.ps5.message.other"
        }
    }

    var body: some View {
        NinoSetupStepLayout(icon: .logo, title: SetupText.string("setup.welcome.ps5.title", locale),
                            message: SetupText.string(messageKey, locale)) {
            VStack(alignment: .leading, spacing: NinoSpacing.m) {
                HStack {
                    Text(SetupText.string("setup.welcome.need", locale).uppercased(with: locale))
                        .font(.nino(.callout))
                        .foregroundStyle(NinoColor.textSecondary)
                    Spacer()
                    Label { KText("setup.welcome.duration") } icon: { Image(systemName: "clock") }
                        .font(.nino(.callout))
                        .foregroundStyle(NinoColor.textSecondary)
                }
                .padding(.horizontal, NinoSpacing.xs)
                HStack(spacing: NinoSpacing.m) {
                    RequirementTile(systemImage: NinoSymbol.controllerFill, title: "PS5",
                                    detail: SetupText.string("setup.welcome.need.ps5", locale))
                    RequirementTile(systemImage: "tv.fill", title: SetupText.string("setup.welcome.need.tv", locale),
                                    detail: SetupText.string("setup.welcome.need.tv.detail", locale))
                    RequirementTile(systemImage: "person.crop.circle.badge.plus",
                                    title: SetupText.string("setup.welcome.need.account", locale),
                                    detail: SetupText.string("setup.welcome.need.account.detail", locale))
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top) {
                    SetupLink(systemImage: NinoSymbol.gameWindow,
                              title: SetupText.string("setup.welcome.thisComputer", locale),
                              help: SetupText.string("setup.welcome.thisComputer.help", locale)) {
                        SetupFlow.playOnThisComputer(state)
                    }
                    Spacer(minLength: NinoSpacing.l)
                    CaptureCardLink(state: state)
                }
                .padding(.top, NinoSpacing.s)
            }
        }
    }
}

/// "Capture Card'ım var": rehberi açar (§10).
struct CaptureCardLink: View {
    let state: AppState
    @Environment(\.locale) private var locale

    var body: some View {
        SetupLink(systemImage: NinoSymbol.captureCard, title: SetupText.string("setup.welcome.captureCard", locale),
                  help: SetupText.string("setup.welcome.captureCard.help", locale)) {
            state.setup.captureGuideOpen = true
        }
    }
}

/// Gereksinim karosu: 48'lik degrade daire içinde beyaz simge, başlık ve açıklama.
private struct RequirementTile: View {
    let systemImage: String
    let title: String
    let detail: String
    @State private var appeared = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.ninoStaticRendering) private var isStatic
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = appeared || isStatic || reduceMotion
        VStack(alignment: .leading, spacing: NinoSpacing.s) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(NinoGradients.iconFill(scheme)))
                .shadow(color: NinoColor.accent.color(scheme).opacity(0.4), radius: 10, y: 4)
            Text(title).font(.nino(.headline))
            Text(detail)
                .font(.nino(.callout))
                .foregroundStyle(NinoColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 150 - 2 * NinoSpacing.l, alignment: .topLeading)
        .ninoTile()
        .scaleEffect(shown ? 1 : 0.96)
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(NinoMotion.spring(0.5, 0.8).delay(0.05)) { appeared = true }
        }
    }
}

// MARK: - 3d. Xbox karşılaması

private struct XboxWelcome: View {
    let state: AppState
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    var body: some View {
        NinoSetupStepLayout(icon: .symbol(NinoSymbol.controllerFill),
                            title: SetupText.string("setup.xbox.title", locale),
                            message: SetupText.string("setup.xbox.message", locale)) {
            VStack(spacing: NinoSpacing.l) {
                XboxConnectList(state: state)
                HStack(spacing: NinoSpacing.l) {
                    SetupLink(systemImage: "safari", title: SetupText.string("setup.xbox.browser", locale)) {
                        openURL(SetupLinks.xboxCloud)
                    }
                    CaptureCardLink(state: state)
                }
            }
            .frame(maxWidth: 640)
        }
    }
}
