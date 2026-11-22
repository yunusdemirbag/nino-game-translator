// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Ana pencerenin bütün içeriği (ana-ekran.md §1): zemin, açılış, kurulum ya da ana ekran, robot, sayfalar.
/// Arayüz dili ve yönü çeviri dilinden, tema Ayarlar'daki görünümden gelir.
public struct MainWindowView: View {
    private let state: AppState
    private let ui: HomeUIState
    @Environment(\.ninoStaticRendering) private var isStatic
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(state: AppState, ui: HomeUIState) {
        self.state = state
        self.ui = ui
    }

    /// Arayüz dili: çeviri diliyle aynı; desteklenmeyen dilde İngilizce. Filipince "fil".
    public static func interfaceLanguage(for target: String) -> String {
        let code = target == "tl" ? "fil" : target
        return supportedLanguages.contains(code) ? code : "en"
    }

    public static let supportedLanguages: Set<String> = ["en", "tr", "ar", "bn", "fil", "hi", "id", "ms", "nl", "th", "ur", "vi"]

    private var language: String { Self.interfaceLanguage(for: state.settings.targetLanguage) }

    public var body: some View {
        ZStack {
            NinoWindowBackground()
            if state.isSetupComplete {
                if ui.splashFinished {
                    HomeView(state: state, ui: ui)
                        .transition(.opacity)
                }
            } else {
                SetupHost(state: state)
                    .opacity(ui.splashFinished ? 1 : 0)
            }
            if ui.splashFinished {
                robot.transition(.scale.combined(with: .opacity))
            }
            if !ui.splashFinished {
                NinoSplashView {
                    withAnimation(.easeOut(duration: 0.35)) { ui.splashFinished = true }
                }
                .transition(.opacity)
            }
        }
        .font(.nino(.body))
        .foregroundStyle(NinoColor.textPrimary)
        .tint(NinoColor.accentText)
        .frame(minWidth: NinoSize.windowWidth, idealWidth: NinoSize.windowWidth, maxWidth: NinoSize.windowMaxWidth,
               minHeight: NinoSize.windowHeight, idealHeight: NinoSize.windowHeight)
        .environment(\.locale, Locale(identifier: language))
        .environment(\.layoutDirection, NinoL10n.isRightToLeft(languageCode: language) ? .rightToLeft : .leftToRight)
        .preferredColorScheme(colorScheme)
        .sheet(item: Binding(get: { state.activeSheet }, set: { state.activeSheet = $0 })) { sheet in
            SheetHost(state: state, sheet: sheet)
                .environment(\.locale, Locale(identifier: language))
                .environment(\.layoutDirection,
                             NinoL10n.isRightToLeft(languageCode: language) ? .rightToLeft : .leftToRight)
        }
        .onChange(of: state.translation) { old, new in
            ui.translationChanged(state, from: old)
            updateBubble(old: old, new: new)
        }
        .onChange(of: language, initial: true) { _, code in
            // Seçilen dil sistemin uygulama dili tercihine de yazılır (sonraki açılış için).
            guard !isStatic else { return }
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }

    private var layoutDirection: LayoutDirection {
        NinoL10n.isRightToLeft(languageCode: language) ? .rightToLeft : .leftToRight
    }

    private var colorScheme: ColorScheme? {
        switch state.settings.appearance {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }

    /// Robot: ana ekranda sol alt (24, 60), kurulumda sağ alt (24, 96).
    private var robot: some View {
        let home = state.isSetupComplete
        // Ana ekranda sahne hiç aynalanmadığı için robot sağdan sola dilde de solda kalır (sağda fiş var).
        return AskNinoButton(state: state, showBubble: home && ui.startedBubbleVisible)
            .padding(home ? .leading : .trailing, 24)
            .padding(.bottom, home ? 60 : 96)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: home ? .bottomLeading : .bottomTrailing)
            .environment(\.layoutDirection, home ? .leftToRight : layoutDirection)
            .animation(NinoMotion.spring(0.4, 0.8), value: ui.startedBubbleVisible)
    }

    /// "Başladı" balonu: çeviri başlayınca 7 sn; durunca hemen söner.
    private func updateBubble(old: TranslationPhase, new: TranslationPhase) {
        if new == .on, old != .on, state.isSetupComplete {
            ui.startedBubbleVisible = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(7))
                guard state.translation == .on else { return }
                withAnimation(.easeOut(duration: 0.4)) { ui.startedBubbleVisible = false }
            }
        } else if new == .off, ui.startedBubbleVisible {
            withAnimation(.easeOut(duration: 0.25)) { ui.startedBubbleVisible = false }
        }
    }
}

/// Sayfaların yönlendirmesi (§1.3). Yer tutucular gerçek sayfalar yazıldıkça değiştirilir.
struct SheetHost: View {
    let state: AppState
    let sheet: Sheet

    var body: some View {
        switch sheet {
        case .settings: SettingsView(state: state, initialSection: nil)
        case .settingsTranslation: SettingsView(state: state, initialSection: .translation)
        case .history: HistorySheet(state: state)
        case .about: AboutSheet(state: state)
        case .health: HealthSheet(state: state)
        case .reportProblem: ReportProblemSheet(state: state)
        case .askNino: AskNinoSheet(state: state)
        default: PlaceholderSheet(title: sheet.rawValue) { state.activeSheet = nil }
        }
    }
}

/// Kurulum ekranının yönlendirmesi (kurulum.md'yi yazacak ajan doldurur).
struct SetupHost: View {
    let state: AppState

    var body: some View {
        SetupView(state: state)
    }
}
