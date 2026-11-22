// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Ana ekranın metin tablosu (`Resources/Home.xcstrings`).
enum HomeText {
    static let table = "Home"

    static func string(_ key: String, _ locale: Locale, _ arguments: CVarArg...) -> String {
        NinoL10n.string(key, table: table, language: NinoL10n.languageCode(for: locale), arguments: arguments)
    }
}

/// Ana ekran tablosundan metin görünümü.
struct HText: View {
    private let key: String
    private let arguments: [CVarArg]

    init(_ key: String, _ arguments: CVarArg...) {
        self.key = key
        self.arguments = arguments
    }

    var body: some View {
        NinoText(key, table: HomeText.table, arguments: arguments)
    }
}

// MARK: - Durum metinleri (ana-ekran.md §6.1, §8.3)

@MainActor
enum HomeStatus {
    /// Görüntü kaynağı öğesinin başlığı: "Oyun penceresi", "Capture Card" ya da "PS5".
    static func sourceTitle(_ state: AppState, _ locale: Locale) -> String {
        switch state.settings.videoSource {
        case .window: return HomeText.string("home.source.gameWindow", locale)
        case .card: return HomeText.string("home.source.captureCard", locale)
        case .ps5: return "PS5"
        }
    }

    /// Görüntü akıyor mu.
    static func isStreaming(_ state: AppState) -> Bool {
        switch state.source {
        case .ps5(let link): return link == .streaming
        case .window(let link): if case .reading = link { return true }; return false
        case .card(let link): if case .reading = link { return true }; return false
        }
    }

    static func sourceTone(_ state: AppState) -> NinoStatusTone {
        NinoStatusTone.source(streaming: isStreaming(state), translating: state.translation != .off)
    }

    /// Uzun değer (şerit öğesinin ipucu): PS5 yolunda, çeviri kapalı ve eşli PS5 varsa "<ad> · hazır"; değilse durum metni.
    static func sourceValue(_ state: AppState, _ locale: Locale) -> String {
        if state.settings.videoSource == .ps5, state.translation == .off, let console = state.pairedConsole {
            let name = console.name.isEmpty ? "PS5" : console.name
            return HomeText.string("home.source.ready %@", locale, name)
        }
        return sourceText(state, locale)
    }

    /// Alt şeritteki kısa değer ("Bulunamadı", "Uykuda"…). Uzun açıklama `sourceText`'tedir; şeritte ipucu olur.
    static func sourceShortValue(_ state: AppState, _ locale: Locale) -> String {
        if state.settings.videoSource == .ps5, state.translation == .off, let console = state.pairedConsole {
            let name = console.name.isEmpty ? "PS5" : console.name
            return HomeText.string("home.source.ready %@", locale, name)
        }
        let key = sourceShortKey(state)
        if let name = readingName(state) { return HomeText.string(key, locale, name) }
        return HomeText.string(key, locale)
    }

    /// Görüntü kaynağının kısa durum anahtarı. Her durum ve her kopma nedeni bir kısa etikete düşer.
    static func sourceShortKey(_ state: AppState) -> String {
        let translating = state.translation != .off
        switch state.source {
        case .ps5(let link):
            switch link {
            case .streaming: return "home.status.connected"
            case .connecting:
                return state.localNetworkBlocked && translating ? "home.short.localNetwork" : "home.status.connecting"
            case .idle: return state.pairedConsole != nil ? "home.short.paired" : "home.status.notConnected"
            case .dropped(let reason):
                if state.localNetworkBlocked {
                    switch reason {
                    case .notFound, .network, .other: return "home.short.localNetwork"
                    default: break
                    }
                }
                return dropShortKey(reason)
            }
        case .window(let link):
            switch link {
            case .idle: return "home.short.waiting"
            case .appMissing: return "home.short.appMissing"
            case .screenRecordingDenied: return "home.short.permission"
            case .searching: return "home.short.searching"
            case .reading: return "home.reading %@"
            }
        case .card(let link):
            switch link {
            case .idle: return "home.short.waiting"
            case .cameraDenied: return "home.short.permission"
            case .noCard: return "home.short.noCard"
            case .black: return "home.short.darkScreen"
            case .reading: return "home.reading %@"
            }
        }
    }

    /// PS5 kopma nedeninin kısa etiketi.
    static func dropShortKey(_ reason: SourceStatus.DropReason) -> String {
        switch reason {
        case .asleep: return "home.short.asleep"
        case .inUseElsewhere: return "home.short.busy"
        case .refused, .pairingInvalid: return "home.short.pairAgain"
        case .passcodeRequired: return "home.short.passcode"
        case .passcodeWrong: return "home.short.passcodeWrong"
        case .remotePlayDisabled: return "home.short.remotePlayOff"
        case .noPicture: return "home.short.noPicture"
        case .notFound: return "home.short.notFound"
        case .network: return "home.short.noReply"
        case .rejected: return "home.short.sessionRefused"
        case .other: return "home.drop.other"
        }
    }

    private static func readingName(_ state: AppState) -> String? {
        switch state.source {
        case .window(.reading(let name)), .card(.reading(let name)): return name
        default: return nil
        }
    }

    /// Bütün kısa etiket anahtarları (testler 12 dilde çözüldüklerini sınar).
    static let shortKeys = ["home.status.connected", "home.status.connecting", "home.status.notConnected",
                            "home.drop.other", "home.short.paired", "home.short.localNetwork", "home.short.waiting",
                            "home.short.appMissing", "home.short.permission", "home.short.searching",
                            "home.short.noCard", "home.short.darkScreen", "home.short.asleep", "home.short.busy",
                            "home.short.pairAgain", "home.short.passcode", "home.short.passcodeWrong",
                            "home.short.remotePlayOff", "home.short.noPicture", "home.short.notFound",
                            "home.short.noReply", "home.short.sessionRefused", "home.short.tvWaiting", "home.short.tvSetUp"]

    /// Görüntü kaynağının durum metni (§8.3).
    static func sourceText(_ state: AppState, _ locale: Locale) -> String {
        let translating = state.translation != .off
        let localNetwork = HomeText.string("home.warning.localNetwork", locale)
        switch state.source {
        case .ps5(let link):
            switch link {
            case .streaming:
                return HomeText.string("home.status.connected", locale)
            case .connecting:
                return state.localNetworkBlocked && translating ? localNetwork : HomeText.string("home.status.connecting", locale)
            case .idle:
                if let console = state.pairedConsole {
                    return HomeText.string("home.status.paired %@", locale, console.name.isEmpty ? "PS5" : console.name)
                }
                return HomeText.string("home.status.notConnected", locale)
            case .dropped(let reason):
                if state.localNetworkBlocked {
                    switch reason {
                    case .notFound, .network, .other: return localNetwork
                    default: break
                    }
                }
                return dropText(reason, locale)
            }
        case .window(let link):
            let xbox = state.settings.gameConsole == .xbox
            switch link {
            case .idle: return HomeText.string(xbox ? "home.window.idleXbox" : "home.window.idle", locale)
            case .appMissing: return HomeText.string("home.window.appMissing", locale)
            case .screenRecordingDenied: return HomeText.string("home.window.screenRecordingDenied", locale)
            case .searching: return HomeText.string(xbox ? "home.window.searchingXbox" : "home.window.searching", locale)
            case .reading(let appName): return HomeText.string("home.reading %@", locale, appName)
            }
        case .card(let link):
            switch link {
            case .idle: return HomeText.string("home.card.idle", locale)
            case .cameraDenied: return HomeText.string("home.card.cameraDenied", locale)
            case .noCard: return HomeText.string("home.card.noCard", locale)
            case .black: return HomeText.string("home.card.black", locale)
            case .reading(let cardName): return HomeText.string("home.reading %@", locale, cardName)
            }
        }
    }

    /// PS5 kopma nedeni metni (kurulum ve PS5 ekranları da aynı tabloyu kullanır).
    static func dropText(_ reason: SourceStatus.DropReason, _ locale: Locale) -> String {
        switch reason {
        case .asleep: return HomeText.string("home.drop.asleep", locale)
        case .inUseElsewhere: return HomeText.string("home.drop.inUseElsewhere", locale)
        case .refused: return HomeText.string("home.drop.refused", locale)
        case .passcodeRequired: return HomeText.string("home.drop.passcodeRequired", locale)
        case .passcodeWrong: return HomeText.string("home.drop.passcodeWrong", locale)
        case .pairingInvalid: return HomeText.string("home.drop.pairingInvalid", locale)
        case .remotePlayDisabled: return HomeText.string("home.drop.remotePlayDisabled", locale)
        case .noPicture: return HomeText.string("home.drop.noPicture", locale)
        case .notFound(let address): return HomeText.string("home.drop.notFound %@", locale, address)
        case .network: return HomeText.string("home.drop.network", locale)
        case .rejected(let code?):
            return HomeText.string("home.drop.rejectedCode %@", locale, String(format: "0x%08X", code))
        case .rejected(nil): return HomeText.string("home.drop.rejected", locale)
        case .other(let detail?) where !detail.isEmpty: return HomeText.string("home.drop.otherDetail %@", locale, detail)
        case .other: return HomeText.string("home.drop.other", locale)
        }
    }

    /// Çeviri bağlantısının değeri (§6.2), ilk uyan: havuz öncelikli oyun, kullanıcının kendi motoru, tanınan oyun,
    /// yalnız "Nino". Nino'nun kendi çevirisi marka adıyla yazılır; hiçbir dilde "ücretsiz" denmez.
    static func translationValue(_ state: AppState, _ locale: Locale) -> String {
        let game = state.game.flatMap { $0.name.isEmpty ? nil : $0 }
        if let game, game.poolFirst, state.settings.targetLanguage == "tr" {
            return HomeText.string("home.translation.poolGame %@", locale, game.name)
        }
        if state.settings.onlineTranslation { return engineName(state.settings.onlineEngine) }
        if let game { return HomeText.string("home.translation.poolGame %@", locale, game.name) }
        return "Nino"
    }

    static func engineName(_ engine: MacSettings.OnlineEngine) -> String {
        switch engine {
        case .deepl: return "DeepL"
        case .gemini: return "Gemini"
        case .openai: return "ChatGPT"
        case .claude: return "Claude"
        case .local: return "Ollama"
        }
    }

    /// Dilin adı arayüz dilinde ("en" → "İngilizce").
    static func languageName(_ code: String, _ locale: Locale) -> String {
        Locale(identifier: NinoL10n.languageCode(for: locale)).localizedString(forLanguageCode: code) ?? code
    }
}
