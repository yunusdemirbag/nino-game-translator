// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// Bir cümlenin çevirisi ve nereden geldiği.
public struct SessionTranslation: Equatable, Sendable {
    public var text: String
    public var origin: LiveLine.Origin
    /// Çevrilemedi (zincirin hiçbir halkası sonuç vermedi).
    public var failed: Bool
    /// `text` içindeki `⟦T1⟧` yer tutucularının tuş simgeleri (protokol.md "Tuş simgeleri").
    public var icons: [LinkIcon]

    public init(text: String, origin: LiveLine.Origin, failed: Bool = false, icons: [LinkIcon] = []) {
        self.text = text
        self.origin = origin
        self.failed = failed
        self.icons = icons
    }
}

/// Oturumun çevirmeni. Uygulamada `LibrarySubtitleTranslator` (paket → havuz → önbellek → sağlayıcılar),
/// testlerde sahtesi.
public protocol SubtitleTranslating: Sendable {
    func translate(_ sentence: String) async -> SessionTranslation
    /// Kullanıcının seçtiği ya da konsolun bildirdiği oyun (`nil`: bilinmiyor).
    func setKnownGame(_ name: String?) async
    /// Kullanıcının elle seçtiği oyun (paket kapsamı).
    func selectGame(_ name: String?) async
    /// Satır yalnız tek bir pakette bulunduysa o paketin kimliği (oyun tanıma oyu; okununca silinir).
    func takeDistinctiveHit() async -> String?
    /// Bu oyun havuz öncelikli mi?
    func isPoolFirst(game: String?) async -> Bool
    func setPacksEnabled(_ on: Bool) async
    func flush() async
}

public extension SubtitleTranslating {
    func setKnownGame(_ name: String?) async {}
    func selectGame(_ name: String?) async {}
    func takeDistinctiveHit() async -> String? { nil }
    func isPoolFirst(game: String?) async -> Bool { false }
    func setPacksEnabled(_ on: Bool) async {}
    func flush() async {}
}

/// NinoCore'un `LibraryTranslator`'ını oturuma uyarlar.
public struct LibrarySubtitleTranslator: SubtitleTranslating {
    public let library: LibraryTranslator
    public let pool: PoolClient?
    public let targetLanguage: String

    public init(library: LibraryTranslator, pool: PoolClient?, targetLanguage: String) {
        self.library = library
        self.pool = pool
        self.targetLanguage = targetLanguage
    }

    public func translate(_ sentence: String) async -> SessionTranslation {
        let t = await library.translate(sentence)
        switch t.origin {
        case .legacyPack, .newPack: return SessionTranslation(text: t.text, origin: .pack)
        case .pool: return SessionTranslation(text: t.text, origin: .pool)
        case .translator(.cache), .translator(.pack): return SessionTranslation(text: t.text, origin: .cache)
        case .translator(.provider): return SessionTranslation(text: t.text, origin: .engine)
        case .translator(.none): return SessionTranslation(text: t.source, origin: .untranslated, failed: true)
        }
    }

    public func setKnownGame(_ name: String?) async { await library.setKnownGame(name) }
    public func selectGame(_ name: String?) async { await library.selectGame(name) }
    public func takeDistinctiveHit() async -> String? { await library.takeDistinctiveHit() }
    public func isPoolFirst(game: String?) async -> Bool {
        await pool?.isPoolFirst(game: game, language: targetLanguage) ?? false
    }
    public func setPacksEnabled(_ on: Bool) async { await library.setPacksEnabled(on) }
    public func flush() async { await library.flush() }
}

/// Sağlayıcıyı motor başına önbellekle sarar (`EngineCacheStore`; `Translations/v1-<motor>-…jsonl`).
/// Sağlayıcının kendi önbelleği yok; eski uygulamanın dosyaları burada okunur ve sürdürülür.
public struct CachedProvider: TranslationProvider {
    public let base: TranslationProvider
    public let cache: EngineCache
    public let key: @Sendable (String) -> String

    public var name: String { base.name }

    public init(base: TranslationProvider, cache: EngineCache, key: @escaping @Sendable (String) -> String) {
        self.base = base
        self.cache = cache
        self.key = key
    }

    public func translate(_ text: String, from source: String, to target: String) async throws -> String {
        let k = key(text)
        if let hit = await cache.lookup(k) { return hit }
        let out = try await base.translate(text, from: source, to: target)
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != text { await cache.store(k, trimmed) }
        return out
    }
}

/// Cihaz içi çeviriden önce oyun deyimlerini düz İngilizceye çevirir (`ceviri.md` §3).
public struct IdiomPlainingProvider: TranslationProvider {
    public let base: TranslationProvider
    public var name: String { base.name }
    public init(base: TranslationProvider) { self.base = base }

    public func translate(_ text: String, from source: String, to target: String) async throws -> String {
        try await base.translate(source == "en" ? GameIdioms.apply(text) : text, from: source, to: target)
    }
}
