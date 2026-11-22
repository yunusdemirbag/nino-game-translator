// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Hazır çeviri arayan her şey (oyun paketleri). Bulamazsa `nil`.
public protocol PhraseLookup: Sendable {
    func lookup(_ sentence: String) -> String?
    /// Bu kaynağın oyun terimleri.
    var terms: [Term] { get }
}

/// Çeviri sırası: önbellek → oyun paketi → çevirmen zinciri. Terimler korunur,
/// sonuç Türkçe kurallarına göre toparlanır.
public actor Translator {
    public let sourceLanguage: String
    public let targetLanguage: String
    private let cache: TranslationCache
    private let chain: ProviderChain
    private let postProcessor: TurkishPostProcessor
    private var pack: PhraseLookup?
    private var userTerms: [Term]
    private var unsavedStores = 0
    /// Bu kadar yeni kayıttan sonra önbellek diske yazılır.
    public let saveEvery: Int

    public init(cache: TranslationCache = TranslationCache(),
                chain: ProviderChain,
                pack: PhraseLookup? = nil,
                userTerms: [Term] = [],
                sourceLanguage: String = "en",
                targetLanguage: String = "tr",
                postProcessor: TurkishPostProcessor = TurkishPostProcessor(),
                saveEvery: Int = 20) {
        self.saveEvery = max(1, saveEvery)
        self.cache = cache
        self.chain = chain
        self.pack = pack
        self.userTerms = userTerms
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.postProcessor = postProcessor
    }

    /// Seçili oyunun paketini değiştirir (`nil`: paket yok).
    public func setPack(_ pack: PhraseLookup?) { self.pack = pack }
    public func setUserTerms(_ terms: [Term]) { userTerms = terms }

    public func translate(_ sentence: String) async -> Translation {
        let source = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return Translation(source: sentence, text: sentence, origin: .none) }

        if let cached = await cache.lookup(source) {
            return Translation(source: source, text: cached, origin: .cache)
        }
        if let hit = pack?.lookup(source) {
            return Translation(source: source, text: hit, origin: .pack)
        }

        // Kullanıcı terimleri paket terimlerinden önce gelir.
        let protector = TermProtector(terms: userTerms + (pack?.terms ?? []))
        let protected = protector.protect(source)

        // Yalnız terimlerden oluşan cümle çevirmene gitmez.
        let leftover = protected.text.replacingOccurrences(of: #"⟦\d+⟧"#, with: "", options: .regularExpression)
        if !protected.replacements.isEmpty, !leftover.contains(where: \.isLetter),
           let restored = protector.restore(protected.text, protected) {
            return Translation(source: source, text: restored, origin: .pack)
        }
        let result = await chain.translate(protected.text, from: sourceLanguage, to: targetLanguage) { candidate in
            protector.restore(candidate, protected) != nil
        }
        guard let result, let restored = protector.restore(result.text, protected) else {
            return Translation(source: source, text: source, origin: .none)
        }
        let text = postProcessor.process(restored, source: source)
        await cache.store(source: source, text: text, origin: result.provider)
        unsavedStores += 1
        if unsavedStores >= saveEvery { await flush() }
        return Translation(source: source, text: text, origin: .provider(result.provider))
    }

    /// Önbelleği diske yazar (dosyası varsa).
    public func flush() async {
        try? await cache.save()
        unsavedStores = 0
    }

    /// Birden çok cümleyi sırayla çevirir.
    public func translate(_ sentences: [String]) async -> [Translation] {
        var out: [Translation] = []
        for s in sentences { out.append(await translate(s)) }
        return out
    }
}
