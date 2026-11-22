// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore
import Observation

// Anahtarsız çeviri için küçük öneriler ve kuralları:
// - ana ekranda paketsiz bir oyun tanınınca "Bu oyun için çeviri anahtarı ekle" (oyun başına kapatılır),
// - cihaz içi çevirinin dil paketi eksikse bir kez indirme önerisi,
// - Sistem sağlığı "Çeviri" satırının hangi yolla çevrildiği.

/// Kalıcı işaretler (UserDefaults; testlerde geçici alan). Motor `attach(defaults:)` ile bağlar.
@MainActor
@Observable
public final class TranslationNudges {
    /// Anahtar önerisi kapatılmış oyunların kimlikleri.
    public private(set) var dismissedKeyGames: Set<String> = []
    /// Dil paketi indirme önerisi gösterildi mi (bir kez).
    public private(set) var languagePackOffered = false
    @ObservationIgnored private var defaults: UserDefaults?

    static let dismissedKey = "ninoKeySuggestionDismissed"
    static let packOfferedKey = "ninoLanguagePackOffered"

    public init() {}

    public func attach(defaults: UserDefaults) {
        self.defaults = defaults
        dismissedKeyGames = Set(defaults.stringArray(forKey: Self.dismissedKey) ?? [])
        languagePackOffered = defaults.bool(forKey: Self.packOfferedKey)
    }

    public func dismissKeySuggestion(gameID: String) {
        dismissedKeyGames.insert(gameID)
        defaults?.set(dismissedKeyGames.sorted(), forKey: Self.dismissedKey)
    }

    public func markLanguagePackOffered() {
        languagePackOffered = true
        defaults?.set(true, forKey: Self.packOfferedKey)
    }
}

/// Çevirinin şu anki yolu (Sistem sağlığı "Çeviri" satırı).
public enum TranslationPath: Equatable, Sendable {
    /// Kullanıcının motoru; cihaz içi çeviri ve havuz yedekte.
    case engine(MacSettings.OnlineEngine)
    /// Anahtar yok: havuz (açıksa) ve cihaz içi çeviri.
    case poolAndDevice
    case deviceOnly
    /// Cihaz içi çevirinin dil paketi eksik / bu Mac'te yok: yalnız havuz.
    case poolOnly(packMissing: Bool)
    /// Hiçbir yol yok (anahtar yok, havuz kapalı, cihaz içi çeviri çalışmıyor).
    case none(packMissing: Bool)

    public var level: HealthLevel {
        switch self {
        case .engine, .poolAndDevice, .deviceOnly: return .good
        case .poolOnly: return .fair
        case .none: return .problem
        }
    }
}

public enum TranslationNudgeRules {
    /// Gerçekten kullanılacak çevrimiçi motor (TranslatorFactory.onlineEngine'in ekrandaki eşi: anahtarın kendisi
    /// yerine "kayıtlı mı" bilgisine bakar).
    public static func readyEngine(_ s: MacSettings, savedKeys: Set<MacSettings.OnlineEngine>,
                                   geminiKeySaved: Bool = false) -> MacSettings.OnlineEngine? {
        guard s.onlineTranslation, s.sourceLanguage == "en", TargetLanguage.find(s.targetLanguage) != nil else { return nil }
        let e = s.onlineEngine
        switch e {
        case .local: return LocalModelServer.normalize(s.localAIBaseURL) != nil ? e : nil
        case .deepl: return savedKeys.contains(e) && DeepLProvider.supports(s.targetLanguage) ? e : nil
        case .gemini: return savedKeys.contains(e) || geminiKeySaved ? e : nil
        case .openai, .claude: return savedKeys.contains(e) ? e : nil
        }
    }

    public static func path(engine: MacSettings.OnlineEngine?, readiness: TranslatorReadiness,
                            sharePool: Bool, sourceLanguage: String) -> TranslationPath {
        if let engine { return .engine(engine) }
        let pool = sharePool && sourceLanguage == "en"
        switch readiness {
        case .ready: return pool ? .poolAndDevice : .deviceOnly
        case .languagePackMissing: return pool ? .poolOnly(packMissing: true) : .none(packMissing: true)
        case .unsupported: return pool ? .poolOnly(packMissing: false) : .none(packMissing: false)
        }
    }

    /// Oyunun Nino'da hazır çevirisi var mı: paketten tanındı, havuz öncelikli (GTA 6) ya da kurulu bir paket.
    public static func hasReadyTranslations(_ game: RecognizedGame, packs: [GamePackInfo], settings: MacSettings) -> Bool {
        if game.poolFirst { return true }
        guard settings.gamePacks, settings.sourceLanguage == "en", settings.targetLanguage == "tr" else { return false }
        if game.evidence == .pack { return true }
        return packs.contains { $0.id == game.id || GameTracker.same($0.name, game.name) }
    }

    /// Ana ekrandaki anahtar önerisinin oyunu (gösterilmeyecekse nil).
    public static func keySuggestionGame(game: RecognizedGame?, setupComplete: Bool,
                                         engine: MacSettings.OnlineEngine?, settings: MacSettings,
                                         packs: [GamePackInfo], dismissed: Set<String>) -> RecognizedGame? {
        guard setupComplete, engine == nil, settings.sourceLanguage == "en", let game,
              game.evidence != .lastPlayed, !dismissed.contains(game.id),
              !hasReadyTranslations(game, packs: packs, settings: settings) else { return nil }
        return game
    }

    /// Dil paketi önerisi bir kez: kurulum bitti, paket eksik, daha önce önerilmedi.
    public static func offersLanguagePack(readiness: TranslatorReadiness, setupComplete: Bool, offered: Bool) -> Bool {
        guard setupComplete, !offered, case .languagePackMissing = readiness else { return false }
        return true
    }
}

public extension AppState {
    /// Şu an kullanılacak çevrimiçi motor (anahtar kayıtlı, dil uygun); yoksa nil.
    var readyOnlineEngine: MacSettings.OnlineEngine? {
        TranslationNudgeRules.readyEngine(settings, savedKeys: settingsStatus.savedKeys,
                                          geminiKeySaved: setup.geminiKeySaved)
    }

    var translationPath: TranslationPath {
        TranslationNudgeRules.path(engine: readyOnlineEngine, readiness: translator,
                                   sharePool: settings.sharePool, sourceLanguage: settings.sourceLanguage)
    }

    var keySuggestionGame: RecognizedGame? {
        TranslationNudgeRules.keySuggestionGame(game: game, setupComplete: isSetupComplete, engine: readyOnlineEngine,
                                                settings: settings, packs: settingsStatus.gamePacks,
                                                dismissed: nudges.dismissedKeyGames)
    }

    var offersLanguagePack: Bool {
        TranslationNudgeRules.offersLanguagePack(readiness: translator, setupComplete: isSetupComplete,
                                                 offered: nudges.languagePackOffered)
    }
}
