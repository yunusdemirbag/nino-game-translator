// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// Köşe, ipucu, kart, ek alan (`ElementTranslator`) ile telefon ve harita kartı (`PhoneTranslator`) çevirileri.
///
/// Oturumun çevirmeni değişince (`setTranslator`) ve paketler yenilenince (`setPackLookup`) aynı nesne güncellenir;
/// okuyucular yeniden kurulmaz.
/// - Paket: eşzamanlı "bilinen" (yalnız paket; ek alanlar havuza gitmez, okuma-hatti.md §11).
/// - Havuz: telefon ve harita kartında tek istekte sorulur, bilinmeyenler kuyruğa önerilir (telefon-harita.md §6).
/// - Kalan: cihaz içi çevirmen varsa o, yoksa oturumun çeviri zinciri.
public final class OverlayTranslator: GameReading.ElementTranslator, GameReading.PhoneTranslator, @unchecked Sendable {
    public struct Pool: Sendable {
        public var client: PoolClient?
        public var queue: PoolQueue?
        public var sharing: Bool
        public var game: String?
        public init(client: PoolClient? = nil, queue: PoolQueue? = nil, sharing: Bool = false, game: String? = nil) {
            self.client = client
            self.queue = queue
            self.sharing = sharing
            self.game = game
        }
    }

    private let lock = NSLock()
    private var translator: SubtitleTranslating
    private var packLookup: (@Sendable (String) -> String?)?
    private var pool: Pool
    private var device: TranslationProvider?
    private var source: String
    private var target: String

    public init(translator: SubtitleTranslating, packLookup: (@Sendable (String) -> String?)? = nil, pool: Pool = Pool(),
                device: TranslationProvider? = nil, sourceLanguage: String = "en", targetLanguage: String = "tr") {
        self.translator = translator
        self.packLookup = packLookup
        self.pool = pool
        self.device = device
        self.source = sourceLanguage
        self.target = targetLanguage
    }

    public func setTranslator(_ t: SubtitleTranslating) { lock.withLock { translator = t } }
    public func setPackLookup(_ f: (@Sendable (String) -> String?)?) { lock.withLock { packLookup = f } }
    public func setPool(_ p: Pool) { lock.withLock { pool = p } }
    public func setGame(_ id: String?) { lock.withLock { pool.game = id } }
    public func setLanguages(source: String, target: String) { lock.withLock { self.source = source; self.target = target } }

    private var snapshot: (SubtitleTranslating, Pool, TranslationProvider?, String, String) {
        lock.withLock { (translator, pool, device, source, target) }
    }

    // MARK: ElementTranslator

    public func known(_ text: String) -> String? { packKnown(text) }

    private func packKnown(_ text: String) -> String? {
        let lookup = lock.withLock { packLookup }
        return lookup?(text)
    }

    /// Hepsi çevrilemezse hata (ek alan eski hâline döner, aday yeniden denenir); çevrilemeyen parça aslıyla kalır.
    public func translate(_ texts: [String]) async throws -> [String] {
        let (t, _, _, _, _) = snapshot
        var out: [String] = []
        var any = false
        for text in texts {
            let r = await t.translate(text)
            if r.failed { out.append(text) } else { out.append(r.text); any = true }
        }
        guard any || texts.isEmpty else { throw TranslationProviderError.emptyResult }
        return out
    }

    // MARK: PhoneTranslator

    public var targetLanguage: String { lock.withLock { target } }

    public func known(_ text: String) async -> String? {
        if let hit = packKnown(text) { return hit }
        let p = lock.withLock { pool }
        return await p.client?.translations.lookup(text)
    }

    public var reportsToPool: Bool { lock.withLock { pool.sharing && pool.queue != nil } }

    public func report(_ texts: [String]) async {
        let p = lock.withLock { pool }
        guard p.sharing, let queue = p.queue else { return }
        for t in texts { _ = await queue.record(t, game: p.game) }
    }

    public var asksPool: Bool { lock.withLock { pool.sharing && pool.client != nil } }

    public func askPool(_ texts: [String], context: [String]) async -> [String?] {
        let p = lock.withLock { pool }
        guard let client = p.client else { return texts.map { _ in nil } }
        var out: [String?] = []
        for t in texts { out.append(await client.ask(t, game: p.game, poolFirst: true, deadline: await client.poolFirstDeadline)) }
        return out
    }

    public func translateOnDevice(_ text: String) async throws -> String {
        let (t, _, device, source, target) = snapshot
        if let device { return try await device.translate(text, from: source, to: target) }
        let r = await t.translate(text)
        if r.failed { throw TranslationProviderError.emptyResult }
        return r.text
    }
}
