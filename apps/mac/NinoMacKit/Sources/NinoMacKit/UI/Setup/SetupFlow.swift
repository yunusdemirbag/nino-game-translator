// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Kurulum tablosundan metin (`Resources/Setup.xcstrings`).
enum SetupText {
    static let table = "Setup"

    static func string(_ key: String, _ locale: Locale, _ arguments: CVarArg...) -> String {
        NinoL10n.string(key, table: table, language: NinoL10n.languageCode(for: locale), arguments: arguments)
    }
}

/// Kurulum tablosundan metin görünümü.
struct KText: View {
    private let key: String
    private let arguments: [CVarArg]

    init(_ key: String, _ arguments: CVarArg...) {
        self.key = key
        self.arguments = arguments
    }

    var body: some View {
        NinoText(key, table: SetupText.table, arguments: arguments)
    }
}

/// Sihirbazın gezinme kuralları (kurulum.md §1, §12). Ekrandan bağımsız; testler doğrudan çağırır.
@MainActor
public enum SetupFlow {
    /// Sayfa noktası sayısı ("bitti" sayılmaz).
    public static let stepCount = 7

    /// Uygulama açılırken başlangıç adımı (§1).
    /// - Parameter doneRecord: Anahtarlıktaki "kurulum bitti" kaydı (nil: kayıt hiç yok).
    /// Kayıt hiç yoksa (çok eski kurulum) hesap + PS5 + eşli TV "bitti" sayılır; çağıran bunu kayda yazar.
    public static func startStep(doneRecord: Bool?, hasAccount: Bool, hasConsole: Bool,
                                 hasPairedTV: Bool) -> SetupStep {
        let done = doneRecord ?? (hasAccount && hasConsole && hasPairedTV)
        if done { return .done }
        if hasAccount && hasConsole { return .tv }
        return .welcome
    }

    /// Geçerli adımın noktadaki sırası (0…6).
    public static func dotIndex(_ step: SetupStep) -> Int {
        switch step {
        case .welcome: return 0
        case .secondAccount: return 1
        case .psnLogin: return 2
        case .console: return 3
        case .tv: return 4
        case .test: return 5
        case .betterTranslation, .done: return 6
        }
    }

    public enum ForwardButton: Equatable, Sendable { case none, proceed, skip }

    /// Geri yalnız ilk ekranda (konsol seçimi) görünmez.
    public static func showsBack(_ state: AppState) -> Bool {
        !(state.setupStep == .welcome && state.setup.welcome == .chooseConsole)
    }

    /// Sağ alttaki düğme: konsol seçiminde ve denemede yok; çeviri adımında çevrimiçi motor hazır değilse "Şimdilik Geç".
    public static func forwardButton(_ state: AppState) -> ForwardButton {
        switch state.setupStep {
        case .welcome: return state.setup.welcome == .chooseConsole ? .none : .proceed
        case .test, .done: return .none
        case .betterTranslation: return state.readyOnlineEngine != nil ? .proceed : .skip
        default: return .proceed
        }
    }

    /// İlerleme koşulu (§12).
    public static func canContinue(_ state: AppState) -> Bool {
        if state.setup.continueAlwaysEnabled { return true }
        switch state.setupStep {
        case .welcome, .secondAccount, .betterTranslation: return true
        case .psnLogin: return state.psnAccount.isSignedIn
        case .console: return state.pairedConsole != nil
        case .tv: return state.pairedTV != nil || state.settings.output == .computer
        case .test, .done: return false
        }
    }

    /// Devam (ya da Şimdilik Geç).
    public static func goNext(_ state: AppState) {
        guard canContinue(state) else { return }
        switch state.setupStep {
        case .welcome:
            switch state.setup.welcome {
            case .chooseConsole: return
            case .ps5:
                state.settings.gameConsole = .ps5
                state.settings.videoSource = .ps5
                state.setupStep = .secondAccount
            case .xbox:
                state.settings.gameConsole = .xbox
                state.settings.videoSource = .window
                state.setupStep = .tv
            }
        case .secondAccount: state.setupStep = .psnLogin
        case .psnLogin: state.setupStep = .console
        case .console: state.setupStep = .tv
        case .tv: state.setupStep = .test
        case .test: state.setupStep = .betterTranslation
        case .betterTranslation: state.finishSetup()
        case .done: break
        }
    }

    /// Geri.
    public static func goBack(_ state: AppState) {
        switch state.setupStep {
        case .welcome:
            state.setup.welcome = .chooseConsole
        case .secondAccount:
            state.setup.welcome = .ps5
            state.setupStep = .welcome
        case .psnLogin: state.setupStep = .secondAccount
        case .console: state.setupStep = .psnLogin
        case .tv:
            if state.settings.gameConsole == .xbox {
                state.setup.welcome = .xbox
                state.setupStep = .welcome
            } else {
                state.setupStep = .console
            }
        case .test: state.setupStep = .tv
        case .betterTranslation: state.setupStep = .test
        case .done: break
        }
    }

    // MARK: Kısa yollar

    /// Konsol seçimindeki kart.
    public static func chooseConsole(_ console: MacSettings.GameConsole, _ state: AppState) {
        if console == .ps5 {
            state.settings.gameConsole = .ps5
            state.settings.videoSource = .ps5
        }
        state.setup.welcome = console == .ps5 ? .ps5 : .xbox
    }

    /// "Monitörde Remote Play ile oynuyorum": sihirbaz biter.
    public static func playOnThisComputer(_ state: AppState) {
        state.settings.gameConsole = .ps5
        state.settings.videoSource = .window
        state.finishSetup()
    }

    /// İkinci hesap adımındaki "Seç": Remote Play penceresinden oku, sihirbaz biter.
    public static func readRemotePlayWindow(_ state: AppState) {
        state.settings.gameConsole = .ps5
        state.settings.videoSource = .window
        if state.pairedTV == nil { state.settings.output = .computer }
        state.finishSetup()
    }

    /// TV adımında "TV'm yok": çıktı bilgisayar, sonraki adım.
    public static func noTV(_ state: AppState) {
        state.settings.output = .computer
        state.setupStep = .test
    }

    /// Deneme adımında "Evet, görüyorum".
    public static func testSeen(_ state: AppState) {
        state.overlayAdjusting = false
        state.setupStep = .betterTranslation
    }

    /// Yakalama kartı rehberi "Bitti" (sihirbazdan açıldıysa).
    public static func captureGuideDone(toTV: Bool, _ state: AppState) {
        state.settings.videoSource = .card
        state.settings.output = toTV ? .tv : .computer
        state.setup.captureGuideOpen = false
        state.setupStep = toTV && state.pairedTV == nil ? .tv : .test
    }
}
