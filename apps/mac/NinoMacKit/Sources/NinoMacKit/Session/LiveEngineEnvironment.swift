// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// `LiveEngine`'in dışarıya dokunan her şeyi. Uygulama `live(identity:)` ile kurar; testler geçici klasör,
/// bellek kasası, geçici UserDefaults, 0 portları, sahte kaynak ve sahte çevirmen verir.
public struct LiveEngineEnvironment: Sendable {
    public var identity: AppIdentity
    public var folder: DataFolder
    /// Klasör kararının notları (`remoteplay.log`'a yazılır).
    public var folderNotes: [String]
    public var settingsStore: SettingsStore
    public var vault: Vault
    public var ports: DisplayLinks.Ports
    public var appVersion: String
    /// Ortak havuz ve paket sunucusu; nil ise havuz ve paket indirme kapalı.
    public var poolBaseURL: URL?
    public var packsBaseURL: URL?
    /// Havuz/paket ağı. nil ise hiç istek gitmez (testler).
    public var poolTransport: PoolTransport?
    public var providerTransport: ProviderTransport
    /// Güncelleme, sayaç, Nino'ya Sor ve sorun bildirimi ağı; nil ise hiç istek gitmez (testler).
    public var network: NetworkClient?
    /// Cihaz içi çevirmen (macOS 26+).
    public var deviceProvider: @Sendable () -> TranslationProvider?
    /// Okuyucu (uygulamada bekçili Vision okuyucusu).
    public var textReader: GameReading.TextReader
    public var clock: GameReading.Clock
    /// Görüntü kaynağı. Verilmezse ayara göre gerçek kaynak (PS5 Remote Play).
    public var makeSource: (@Sendable (MacSettings, SourceCallbacks) -> SessionSource)?
    /// Çevirmen. Verilmezse `TranslatorFactory` (paket → havuz → önbellek → sağlayıcılar).
    public var makeTranslator: (@Sendable (TranslatorFactory.Inputs) async -> SubtitleTranslating)?
    /// PS5'in çalıştırdığı oyunu sormak için (120 sn'de bir); nil ise sorulmaz.
    public var consoleDiscovery: ConsoleDiscovering?
    /// Cihaz içi dil paketinin durumuna bakılsın mı.
    public var checksTranslatorReadiness: Bool
    /// Bilgisayardaki ayarlar (ör. `NINO_POOL_URL`).
    public var processEnvironment: [String: String]
    /// TV kurulumu (gerçek ağ). Testlerde nil.
    public var makeTVSetup: (@MainActor @Sendable (AppState, SecureRecords, DataFolder, DisplayLinks) -> TVSetupController)?
    /// Telefon panelinin okuyucusu (yalnız işlemci; Neural Engine altyazıya kalsın). Testler sahtesini verir.
    public var phoneTextReader: GameReading.TextReader = GameReading.CPUTextReader()
    /// İlk saniyelerde oyunu ekrandan tanıyan hafif okuyucu (hızlı Vision, işlemcide); nil ise yapılmaz.
    public var quickTextReader: GameReading.TextReader? = GameReading.QuickTextReader()
    /// Telefonu şekilden bulma (Vision dikdörtgen bulucusu); nil ise yalnız renk yolları.
    public var phoneRectangles: GameReading.PhoneRectangleDetector?
    /// Ölçüm gönderimi (olcum.md); nil ise ölçüm istemcisi hiç kurulmaz (testler: gerçek gönderim yok).
    public var telemetryTransport: TelemetryTransport?
    /// Çeviri açıkken sistem uykusu engellensin mi (testlerde kapalı).
    public var preventsSleep = false
    /// Yerel ağ izni tahmini (PS5 bulunamayınca); nil ise tahmin yapılmaz.
    public var localNetworkProbe: (@Sendable () async -> LocalNetworkProbe.Verdict)?
    /// Anahtar denemesi (örnek satır); nil ise gerçek sağlayıcı. Testler sahtesini verir (ağ yok).
    public var keyCheck: (@Sendable (MacSettings.OnlineEngine, String) async -> (KeyCheckResult, String?))?

    public init(identity: AppIdentity, folder: DataFolder, folderNotes: [String] = [], settingsStore: SettingsStore,
                vault: Vault, ports: DisplayLinks.Ports, appVersion: String, poolBaseURL: URL?, packsBaseURL: URL?,
                poolTransport: PoolTransport?, providerTransport: ProviderTransport,
                deviceProvider: @escaping @Sendable () -> TranslationProvider?, textReader: GameReading.TextReader,
                clock: GameReading.Clock, makeSource: (@Sendable (MacSettings, SourceCallbacks) -> SessionSource)? = nil,
                makeTranslator: (@Sendable (TranslatorFactory.Inputs) async -> SubtitleTranslating)? = nil,
                consoleDiscovery: ConsoleDiscovering? = nil, checksTranslatorReadiness: Bool = true,
                processEnvironment: [String: String] = [:]) {
        self.identity = identity
        self.folder = folder
        self.folderNotes = folderNotes
        self.settingsStore = settingsStore
        self.vault = vault
        self.ports = ports
        self.appVersion = appVersion
        self.poolBaseURL = poolBaseURL
        self.packsBaseURL = packsBaseURL
        self.poolTransport = poolTransport
        self.providerTransport = providerTransport
        self.deviceProvider = deviceProvider
        self.textReader = textReader
        self.clock = clock
        self.makeSource = makeSource
        self.makeTranslator = makeTranslator
        self.consoleDiscovery = consoleDiscovery
        self.checksTranslatorReadiness = checksTranslatorReadiness
        self.processEnvironment = processEnvironment
        self.makeTVSetup = nil
        self.network = nil
    }

    /// Ortak havuz sunucusu (havuz-paketler.md §6).
    public static let defaultPoolURL = "https://nino-pool.y-demirbag2506.workers.dev"
    /// Havuz adresinin ayar anahtarı.
    public static let poolURLDefaultsKey = "ninoPoolURL"
    public static let packsURLDefaultsKey = "ninoPacksURL"

    /// Çalışan uygulamanın gerçek ortamı.
    public static func live(identity: AppIdentity, bundle: Bundle = .main) -> LiveEngineEnvironment {
        let resolved = DataFolder.resolved(identity: identity)
        let store = SettingsStore(identity: identity)
        let env = ProcessInfo.processInfo.environment
        let pool = PoolConfiguration.resolveURL([env["NINO_POOL_URL"], store.defaults.string(forKey: poolURLDefaultsKey),
                                                 defaultPoolURL])
        // Paketler havuz sunucusundan iner (ilerleme.md "Oyun paketleri" kararı).
        let packs = PoolConfiguration.resolveURL([env["NINO_PACKS_URL"], store.defaults.string(forKey: packsURLDefaultsKey),
                                                  pool?.absoluteString])
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
        let clock = GameReading.SystemClock()
        var live = LiveEngineEnvironment(
            identity: identity, folder: resolved.folder, folderNotes: resolved.notes, settingsStore: store,
            vault: KeychainVault(identity: identity), ports: .standard, appVersion: version,
            poolBaseURL: pool, packsBaseURL: packs, poolTransport: URLSessionPoolTransport(session: .shared),
            providerTransport: URLSession.shared, deviceProvider: { makeOnDeviceTranslationProvider() },
            textReader: OCRFallback.makeGuardedReader(clock: clock),
            clock: clock, consoleDiscovery: RemotePlayDiscovery(), processEnvironment: env)
        let defaults = store.defaults
        live.network = URLSessionNetworkClient()
        live.phoneRectangles = GameReading.VisionRectangleDetector()
        live.telemetryTransport = URLSessionTelemetryTransport()
        live.preventsSleep = true
        live.localNetworkProbe = { await LocalNetworkProbe.run() }
        live.makeTVSetup = { state, records, folder, links in
            TVSetupController(state: state, environment: .live(records: records, folder: folder, server: links,
                                                               bundle: bundle, defaults: defaults))
        }
        return live
    }
}
