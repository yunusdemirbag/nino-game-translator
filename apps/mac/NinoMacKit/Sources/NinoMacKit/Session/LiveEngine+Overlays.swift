// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// Okuma hattının eşzamanlı "pakette mi" sorusu ve ekran öğelerinin paket araması. Paketler yenilenince ya da oyun
/// değişince güncellenir; okuyucu yeniden kurulmaz.
public final class PackGate: @unchecked Sendable {
    private let lock = NSLock()
    private var library = LegacyLibrary()
    private var enabled = false
    /// Kullanıcının elle seçtiği oyun (PS5 başka oyun söylemiyorsa): satırlar yalnız o oyunun paketinde aranır.
    private var selectedGame: String?

    public init() {}

    public func update(library: LegacyLibrary? = nil, enabled: Bool? = nil, selectedGame: String?? = nil) {
        lock.withLock {
            if let library { self.library = library }
            if let enabled { self.enabled = enabled }
            if let selectedGame { self.selectedGame = selectedGame }
        }
    }

    public func lookup(_ text: String) -> String? {
        let (lib, on, game) = lock.withLock { (library, enabled, selectedGame) }
        guard on else { return nil }
        if let game {
            guard let i = lib.index(forGameNamed: game) else { return nil }
            return lib.packs[i].exact(text)
        }
        return lib.exact(text)?.text
    }

    public func isInPack(_ text: String) -> Bool { lookup(text) != nil }
}

extension LiveEngine {
    /// Paket araması bu ayarlarda açık mı (paketler yalnız İngilizce → Türkçe).
    static func packsEnabled(_ s: MacSettings) -> Bool {
        s.gamePacks && s.sourceLanguage == "en" && s.targetLanguage == "tr"
    }

    /// Oyunun nereden bilindiği (telefon-harita.md §1.1).
    var phoneKnowledge: GameReading.PhoneGame.Knowledge {
        // Son oynanan tahmini kesin değil: bilinmiyor sayılır (telefon ve harita okuması açık kalır).
        guard let c = games.current, games.evidence != .lastPlayed else { return .unknown }
        return games.isCertain ? .certain(c.name) : .packGuess(c.name)
    }

    /// Telefon araması (ve GTA 6 kuralları) açık mı.
    func phoneDecision(_ s: MacSettings) -> GameReading.PhoneGame.Decision {
        GameReading.PhoneGame.decide(cornersEnabled: s.translateCorners, sourceLanguage: s.sourceLanguage,
                                     targetLanguage: s.targetLanguage, game: phoneKnowledge,
                                     lastGameWasPoolPriority: env.settingsStore.lastGamePoolFirst)
    }

    func overlayOptions(_ s: MacSettings) -> ScreenOverlays.Options {
        var o = ScreenOverlays.Options()
        o.cornersEnabled = s.translateCorners && s.sourceLanguage == "en"
        o.extraAreas = s.extraAreas.prefix(MacSettings.maxExtraAreas).map {
            GameReading.ExtraArea(id: $0.id, name: $0.name, box: Self.box($0.region), enabled: $0.enabled)
        }
        o.isTargetLanguage = sessionOptions(s).isTargetLanguage
        return o
    }

    func overlayPool(_ s: MacSettings) -> OverlayTranslator.Pool {
        OverlayTranslator.Pool(client: pool, queue: poolQueue, sharing: s.sharePool, game: games.current?.id)
    }

    /// Oyun değişti: telefon kararı yeniden verilir, okuyucunun oyun anahtarı ve "pakette mi" bilgisi yenilenir.
    func refreshGameForReading() {
        let s = state.settings
        let decision = phoneDecision(s)
        if let remember = decision.rememberPoolPriority { env.settingsStore.lastGamePoolFirst = remember }
        let selected: String? = games.console == nil ? games.user?.name : nil
        packGate.update(enabled: Self.packsEnabled(s), selectedGame: .some(selected))
        overlayTranslator?.setGame(games.current?.id)
        guard let session else { return }
        let packGame = games.current?.id
        let reported = games.isCertain ? games.current?.name : nil
        Task {
            await session.reader.setPhoneGame(decision.on, packGame: packGame)
            await session.overlays?.setReportedGame(reported)
            await session.overlays?.setPhoneGame(decision.on)
        }
    }

    func overlayEvent(_ e: OverlayEvent, token: Int) {
        guard token == sessionToken else { return }
        switch e {
        case let .extraAreas(list):
            state.extraAreaTexts = list
        case let .screenGame(name):
            screenIdentified(name)
        case let .elementsShown(list):
            subtitleLog.write(LineLogText.elements(list))
        case let .regionShown(id, text):
            subtitleLog.write(LineLogText.region(id: id, text: text))
        }
    }
}
