// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Ana ekrandan itilen sayfalar.
enum Route: Hashable {
    case settings, profile, packs, target, platform, ps5, psn, about, history, tvInstall, tvUpdate
}

/// Uygulamanın kökü. Sıra: karşılama görülmediyse karşılama; kurulum bitmediyse kurulum adımı; değilse ana ekran.
/// Tarif: docs/yeni/ios/kurulum.md §2.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var stack: [Route] = []

    private enum Stage { case welcome, setup, home }

    private var stage: Stage {
        if !model.welcomeSeen { return .welcome }
        return model.step == .done ? .home : .setup
    }

    var body: some View {
        content
            .overlay(alignment: .bottomTrailing) { assistant }
            .background(AppBackdrop())
            .font(DS.Font.body)
            .foregroundStyle(DS.Palette.text)
            .preferredColorScheme(.light)
            .tint(DS.Palette.accent)
            .environment(\.locale, Loc.locale)
            .environment(\.layoutDirection, Languages.direction(for: model.settings.targetLanguage))
            .id(model.settings.targetLanguage)
    }

    @ViewBuilder private var content: some View {
        switch stage {
        case .welcome:
            WelcomeScreen(target: $model.settings.targetLanguage, onFinish: model.finishWelcome)
        case .setup:
            setupScreen
        case .home:
            NavigationStack(path: $stack) {
                HomeScreen(path: $stack).navigationDestination(for: Route.self, destination: page)
            }
            #if DEBUG
            // Ekran karşılaştırması: NINO_SCREENSHOT_ROUTE=tvinstall ile TV kurulumu ekranı doğrudan açılır.
            .onAppear { if ProcessInfo.processInfo.environment["NINO_SCREENSHOT_ROUTE"] == "tvinstall" { stack = [.tvInstall] } }
            #endif
            .overlayPreferenceValue(TourAnchorKey.self) { anchors in
                if showsTour { CoachTour(anchors: anchors) { withAnimation { model.coachTourDone = true } } }
            }
        }
    }

    // MARK: Yüzen robot

    /// Karşılamada ve kurulumda hep; ana ekranda yalnız alt sayfa açık değilken ve tur bitince.
    @ViewBuilder private var assistant: some View {
        let onHome = stage == .home
        if !onHome || (stack.isEmpty && model.coachTourDone) {
            // Kurulumda alttaki büyük düğmenin ve onun üstündeki satırın üstünde durur: 52 + 44 + 20 + 3 × 12.
            let lift: CGFloat = onHome ? DS.Space.gap : 52 + 44 + 20 + 3 * 12
            AskNinoButton()
                .padding(.trailing, DS.Space.screen)
                .padding(.bottom, lift)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var showsTour: Bool { !model.coachTourDone && stack.isEmpty && !model.isRunning }

    // MARK: Kurulum

    @ViewBuilder private var setupScreen: some View {
        let xbox = model.isXbox
        if model.step <= .psnLogin {
            if !model.platformChosen {
                PlatformScreen(onBack: { model.welcomeSeen = false }, onDone: {})
            } else if xbox {
                XboxLoginScreen(onBack: unchoosePlatform, onSkip: model.skipSetup, onDone: leaveSignIn)
            } else {
                PSNScreen(onBack: unchoosePlatform, onSkip: model.skipSetup, onDone: leaveSignIn)
            }
        } else if model.step == .console {
            if xbox {
                XboxConsoleScreen(onBack: model.back, onSkip: model.skipSetup, onSignIn: model.back, onDone: model.advance)
            } else {
                PairScreen(onBack: model.back, onSkip: model.skipSetup, onDone: model.advance)
            }
        } else {
            TargetScreen(onBack: model.back, onDone: model.advance)
        }
    }

    private func unchoosePlatform() { model.platformChosen = false }

    /// Girişten sonra: karşılama adımındaysak önce giriş adımına, sonra konsol adımına geçilir.
    private func leaveSignIn() {
        if model.step == .welcome { model.advance() }
        model.advance()
    }

    // MARK: Alt sayfalar

    private func pop() { _ = stack.popLast() }

    /// Bir sayfayı kapatıp yerine başkasını açar (ör. önce giriş, ardından eşleme).
    private func replaceTop(with route: Route) {
        pop()
        stack.append(route)
    }

    @ViewBuilder private func page(_ route: Route) -> some View {
        switch route {
        case .settings: SettingsScreen(path: $stack)
        case .profile: ProfileScreen(path: $stack)
        case .packs: PacksScreen()
        case .about: AboutScreen()
        case .history: HistoryScreen()
        case .psn: PSNScreen(onBack: pop, onDone: pop)
        case .target: TargetScreen(setup: false, onBack: pop, onDone: pop)
        case .tvInstall: TVInstallScreen(onDone: { stack = [] })
        case .tvUpdate: TVInstallScreen(update: true, onDone: { stack = [] })
        case .platform:
            PlatformScreen(onBack: pop) {
                pop()
                let xboxIncomplete = !model.xboxSignedIn || model.xboxConsole == nil
                if model.isXbox && xboxIncomplete { stack.append(.ps5) }
            }
        case .ps5:
            consolePage
        }
    }

    /// "PS5 ve bağlantı": giriş eksikse önce giriş, sonra eşleme ya da Xbox seçimi.
    @ViewBuilder private var consolePage: some View {
        if model.isXbox {
            if model.xboxSignedIn {
                XboxConsoleScreen(onBack: pop, onSignIn: model.xboxSignOut, onDone: pop)
            } else {
                XboxLoginScreen(onBack: pop, onDone: { replaceTop(with: .ps5) })
            }
        } else if model.accountID == nil {
            PSNScreen(onBack: pop, onDone: { replaceTop(with: .ps5) })
        } else {
            PairScreen(onBack: pop, onDone: pop)
        }
    }
}
