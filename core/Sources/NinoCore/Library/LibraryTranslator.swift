// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// `LibraryTranslator` sonucunun kaynağı.
public enum LibraryOrigin: Equatable, Sendable {
    case legacyPack(String)
    case newPack(String)
    case pool
    case translator(TranslationOrigin)
}

public struct LibraryTranslation: Equatable, Sendable {
    public let source: String
    public let text: String
    public let origin: LibraryOrigin

    public var failed: Bool { origin == .translator(.none) }
}

/// Var olan `Translator`'ı değiştirmeden sarar:
/// paket (seçili oyun / kapsam) → havuz deposu → [havuz öncelikliyse süreli soru] → `Translator`.
/// `Translator` paketsiz (`pack: nil`) kurulmalıdır.
public actor LibraryTranslator {
    public let sourceLanguage: String
    public let targetLanguage: String
    private let translator: Translator
    private var library: LegacyLibrary
    private var scope = PackScope()
    private let pool: PoolClient?
    private let queue: PoolQueue?
    /// "Oyun paketleri" ayarı.
    public var packsEnabled: Bool
    /// Pakette olmayan satırı arka planda havuza da sor (sonraki görülmede hazır olsun).
    public var askInBackground: Bool
    /// Konsoldan ya da oyun tanımadan bilinen oyun.
    private var knownGame: String?

    public init(translator: Translator, library: LegacyLibrary, pool: PoolClient? = nil, queue: PoolQueue? = nil,
                sourceLanguage: String = "en", targetLanguage: String = "tr",
                packsEnabled: Bool = true, askInBackground: Bool = false) {
        self.translator = translator
        self.library = library
        self.pool = pool
        self.queue = queue
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.packsEnabled = packsEnabled
        self.askInBackground = askInBackground
    }

    /// Paketler yeniden okundu (güncelleyici yeni paket indirdi). Kapsam sıfırlanır.
    public func setLibrary(_ library: LegacyLibrary) {
        self.library = library
        scope.select(game: scope.selectedGame)
    }

    /// Kullanıcının elle seçtiği oyun (`nil`: seçim yok).
    public func selectGame(_ name: String?) { scope.select(game: name) }

    public func setKnownGame(_ name: String?) { knownGame = name }

    public func setPacksEnabled(_ on: Bool) { packsEnabled = on }

    /// Ayırt edici isabetin paket kimliği (oyun tanıma için; okununca silinir).
    public func takeDistinctiveHit() -> String? { scope.takeDistinctiveHit(in: library) }

    /// Havuza gidecek oyun ipucu: paket kapsamı, yoksa bilinen ya da seçili oyun.
    public var gameHint: String? { scope.scopeID(in: library) ?? knownGame ?? scope.selectedGame }

    public func translate(_ sentence: String) async -> LibraryTranslation {
        let source = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return LibraryTranslation(source: sentence, text: sentence, origin: .translator(.none)) }
        let enToTr = sourceLanguage == "en" && targetLanguage == "tr"
        // Satır anahtarı ve havuz yalnız İngilizce kaynak içindir.
        let pool = sourceLanguage == "en" ? self.pool : nil
        let queue = sourceLanguage == "en" ? self.queue : nil
        let game = knownGame ?? scope.selectedGame
        let poolFirst = await pool?.isPoolFirst(game: game, language: targetLanguage) ?? false
        await pool?.noteSeen(source)

        // 1. Paket (havuz öncelikli oyunda bakılmaz).
        if !poolFirst, packsEnabled, enToTr, let m = scope.lookup(source, in: library) {
            return LibraryTranslation(source: source, text: m.text, origin: m.legacy ? .legacyPack(m.packID) : .newPack(m.packID))
        }
        // 2. Havuz deposu.
        if let pool, let hit = await pool.translations.lookup(source) {
            return LibraryTranslation(source: source, text: hit, origin: .pool)
        }
        // 3. Havuz öncelikli oyun: süreli soru.
        if poolFirst, let pool {
            if let text = await pool.ask(source, game: game, poolFirst: true, deadline: await pool.poolFirstDeadline) {
                return LibraryTranslation(source: source, text: text, origin: .pool)
            }
        } else if askInBackground, let pool {
            let hint = gameHint
            Task { _ = await pool.ask(source, game: hint) }
        }
        // Pakette ve havuzda olmayan satır havuza önerilir.
        if let queue { await queue.record(source, game: gameHint) }
        // 4. Önbellek ve sağlayıcılar.
        let t = await translator.translate(source)
        return LibraryTranslation(source: t.source, text: t.text, origin: .translator(t.origin))
    }

    public func flush() async {
        await translator.flush()
        await pool?.translations.save()
    }
}
