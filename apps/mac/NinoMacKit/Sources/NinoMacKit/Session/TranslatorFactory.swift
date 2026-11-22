// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// Ayarlardan çeviri zincirini kurar (ceviri.md §1–§4):
/// paket → havuz deposu → [havuz öncelikliyse süreli soru] → önbellek → çevrimiçi motor (motor başına önbellek) →
/// cihaz içi çeviri (motor başına önbellek, yedek) → havuz sunucusunun ücretsiz çevirisi (son yedek).
public struct TranslatorFactory: Sendable {
    /// Zinciri kurmak için gerekenler; motor değişince yeni zincir kurulur.
    public struct Inputs: Sendable {
        public var settings: MacSettings
        public var library: LegacyLibrary
        /// Ortak havuz istemcisi (uygulama ömrünce tek); adres yoksa nil.
        public var pool: PoolClient?
        /// Gönderme kuyruğu; "ortak havuz" kapalıysa nil.
        public var queue: PoolQueue?
        /// `Translations/` (motor başına önbellek dosyaları).
        public var cacheDirectory: URL?
        public var secrets: SecretStore
        public var providerTransport: ProviderTransport
        /// Cihaz içi çevirmen (macOS 26+). Testlerde sahte verilir.
        public var deviceProvider: TranslationProvider?
        /// Çevrimiçi motorun uyarısı değişince (nil: uyarı kalktı).
        public var onAlert: @Sendable (MacSettings.OnlineEngine, ProviderAlert?) -> Void
        /// Çevrimiçi motorun her isteğinin sonucu (otomatik teşhis `tr.errors`): nil başarı, yoksa HTTP benzeri durum
        /// (0 ağ yok, 408 zaman aşımı). Önbellekten gelenler ve hiç gönderilmeyenler sayılmaz.
        public var onResult: (@Sendable (Int?) -> Void)?

        public init(settings: MacSettings, library: LegacyLibrary, pool: PoolClient?, queue: PoolQueue?,
                    cacheDirectory: URL?, secrets: SecretStore, providerTransport: ProviderTransport,
                    deviceProvider: TranslationProvider?,
                    onAlert: @escaping @Sendable (MacSettings.OnlineEngine, ProviderAlert?) -> Void) {
            self.settings = settings
            self.library = library
            self.pool = pool
            self.queue = queue
            self.cacheDirectory = cacheDirectory
            self.secrets = secrets
            self.providerTransport = providerTransport
            self.deviceProvider = deviceProvider
            self.onAlert = onAlert
        }
    }

    /// Kurulan zincir ve bilgisi.
    public struct Built: Sendable {
        public var translator: LibrarySubtitleTranslator
        /// Kullanılan çevrimiçi motor (yoksa nil: yalnız cihaz içi).
        public var onlineEngine: MacSettings.OnlineEngine?
        public var providerNames: [String]
    }

    public init() {}

    // MARK: Kurallar

    /// "Çevrimiçi çeviri etkin" (ceviri.md §2): açık, kaynak `en`, hedef seçilebilir, DeepL'de hedef destekli, motor hazır.
    public static func onlineEngine(for s: MacSettings, secrets: SecretStore) -> MacSettings.OnlineEngine? {
        guard s.onlineTranslation, s.sourceLanguage == "en", TargetLanguage.find(s.targetLanguage) != nil else { return nil }
        let engine = s.onlineEngine
        if engine == .deepl, !DeepLProvider.supports(s.targetLanguage) { return nil }
        switch engine {
        case .local:
            guard LocalModelServer.normalize(s.localAIBaseURL) != nil else { return nil }
            return engine
        default:
            let key = (try? secrets.get(account(for: engine))) ?? nil
            return (key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? nil : engine
        }
    }

    /// NinoCore'un anahtar hesabı (`LegacySecretStore` bunu eski hesap adına eşler).
    public static func account(for engine: MacSettings.OnlineEngine) -> String { "provider.\(engine.rawValue).key" }

    static func service(_ e: MacSettings.OnlineEngine) -> AIService? {
        switch e {
        case .deepl: return nil
        case .gemini: return .gemini
        case .openai: return .openai
        case .claude: return .claude
        case .local: return .local
        }
    }

    static func savedModel(_ e: MacSettings.OnlineEngine, _ s: MacSettings) -> String? {
        switch e {
        case .gemini: return s.geminiModel
        case .openai: return s.openAIModel
        case .claude: return s.claudeModel
        case .local: return s.localAIModel
        case .deepl: return nil
        }
    }

    /// Uyarıdan ana ekranın sorun türü.
    public static func problemKind(_ alert: ProviderAlert) -> OnlineEngineProblem.Kind {
        switch alert {
        case .invalidKey: return .badKey
        case .quotaExhausted: return .quota
        case .network: return .network
        case .server: return .server
        case .modelRejected: return .model
        }
    }

    // MARK: Kurulum

    public func build(_ input: Inputs) async -> Built {
        let s = input.settings
        let source = s.sourceLanguage, target = s.targetLanguage
        let caches = EngineCacheStore(directory: input.cacheDirectory)
        var providers: [TranslationProvider] = []
        var timeout: Duration = .seconds(5)
        let online = Self.onlineEngine(for: s, secrets: input.secrets)

        if let engine = online, let provider = makeOnline(engine, input) {
            let cache = await caches.cache(engine: provider.engine, source: source, target: target)
            let base = input.onResult.map { ReportingProvider(base: provider.provider, report: $0) as TranslationProvider }
                ?? provider.provider
            providers.append(CachedProvider(base: base, cache: cache, key: provider.key))
            timeout = .seconds(provider.timeout + 1)
        }
        if let device = input.deviceProvider {
            let cache = await caches.cache(engine: EngineName.device, source: source, target: target)
            let plained = IdiomPlainingProvider(base: device)
            providers.append(CachedProvider(base: plained, cache: cache, key: { EngineCacheKey.device($0) }))
        }
        // Son yedek: havuzun sunucudaki ücretsiz çevirisi (anahtar yok ya da cihaz içi çeviri çalışmıyorsa).
        if source == "en", let pool = input.pool {
            providers.append(PoolFallbackProvider(pool: pool))
        }

        let chain = ProviderChain(providers: providers, timeout: timeout)
        let translator = Translator(cache: TranslationCache(), chain: chain, pack: nil,
                                    sourceLanguage: source, targetLanguage: target)
        let library = LibraryTranslator(translator: translator, library: input.library, pool: input.pool,
                                        queue: s.sharePool ? input.queue : nil,
                                        sourceLanguage: source, targetLanguage: target,
                                        packsEnabled: s.gamePacks, askInBackground: s.sharePool)
        return Built(translator: LibrarySubtitleTranslator(library: library, pool: input.pool, targetLanguage: target),
                     onlineEngine: online, providerNames: providers.map(\.name))
    }

    private struct Online {
        var provider: TranslationProvider
        var engine: String
        var timeout: Int
        var key: @Sendable (String) -> String
    }

    private func makeOnline(_ engine: MacSettings.OnlineEngine, _ input: Inputs) -> Online? {
        let s = input.settings
        let onAlert = input.onAlert
        let health = ProviderHealth(onChange: { alert in onAlert(engine, alert) })
        let key = ((try? input.secrets.get(Self.account(for: engine))) ?? nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if engine == .deepl {
            guard let key, !key.isEmpty else { return nil }
            let glossary: Glossary? = s.targetLanguage == "tr" ? BuiltinGlossary.enTr : nil
            let p = DeepLProvider(apiKey: key, glossary: glossary, transport: input.providerTransport, health: health)
            return Online(provider: p, engine: EngineName.deepL, timeout: 4, key: { p.cacheKey($0) })
        }
        guard let service = Self.service(engine) else { return nil }
        let model: AIModel
        var base: URL?
        if service == .local {
            base = LocalModelServer.normalize(s.localAIBaseURL)
            model = AIModel(id: LocalModelServer.modelName(s.localAIModel))
        } else {
            guard let m = ModelCatalog.builtin.resolve(service, saved: Self.savedModel(engine, s)) else { return nil }
            model = m
        }
        let config = AIProviderConfig(service: service, model: model, apiKey: key, localBaseURL: base)
        guard config.isReady else { return nil }
        let p = AIProvider(config: config, transport: input.providerTransport, health: health)
        return Online(provider: p, engine: p.engineName, timeout: service == .local ? 15 : 5,
                      key: { EngineCacheKey.ai($0) })
    }
}

// MARK: - Çevirmen hazırlığı

public enum TranslatorReadinessCheck {
    /// Cihaz içi çevirmenin durumu (ana ekran uyarısı).
    public static func current(source: String, target: String) async -> TranslatorReadiness {
        guard makeOnDeviceTranslationProvider() != nil else {
            return .unsupported(source: source, target: target, systemHasTranslator: false)
        }
        #if canImport(Translation)
        if #available(macOS 26.0, *) {
            if await OnDeviceTranslationProvider.isInstalled(from: source, to: target) { return .ready }
            return .languagePackMissing(source: source, target: target)
        }
        #endif
        return .unsupported(source: source, target: target, systemHasTranslator: false)
    }
}

/// Çevrimiçi motorun isteklerini sayar (otomatik teşhis): başarı ya da hata türünden HTTP benzeri durum.
public struct ReportingProvider: TranslationProvider {
    public let base: TranslationProvider
    public let report: @Sendable (Int?) -> Void
    public var name: String { base.name }

    public init(base: TranslationProvider, report: @escaping @Sendable (Int?) -> Void) {
        self.base = base
        self.report = report
    }

    public func translate(_ text: String, from source: String, to target: String) async throws -> String {
        do {
            let out = try await base.translate(text, from: source, to: target)
            report(nil)
            return out
        } catch {
            if let status = Self.status(error) { report(status) }
            throw error
        }
    }

    /// Hata → durum; `nil`: istek gönderilmedi (sayılmaz).
    static func status(_ error: Error) -> Int? {
        if error is CancellationError { return 408 }
        if let u = error as? URLError { return u.code == .timedOut ? 408 : 0 }
        switch error as? ProviderFailure {
        case .invalidKey?: return 401
        case .quotaExhausted?, .minuteLimit?: return 429
        case .modelRejected?: return 400
        case .network?: return 0
        case let .server(code)?: return code
        case .badResponse?: return 502
        case .notReady?: return nil
        case nil: return 0
        }
    }
}
