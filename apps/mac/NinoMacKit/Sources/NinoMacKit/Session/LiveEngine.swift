// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import CoreGraphics
import Foundation
import NinoCore

/// Gerçek motor: kaynak → okuma → çeviri → çıkışlar (mimari.md "Session").
///
/// Ana iş parçacığında yaşar ve yalnız AppState'e yazar. Okuma ve çeviri `SubtitleSession` aktöründe,
/// TV yolları `DisplayLinks`'te. Deneme yapısı (`.development`) hiçbir zaman kendiliğinden çeviri ya da bağlantı
/// başlatmaz; yalnız kullanıcı "Başlat" deyince.
@MainActor
public final class LiveEngine: AppEngine {
    public let state: AppState
    public let env: LiveEngineEnvironment
    public let records: SecureRecords
    public let secrets: LegacySecretStore
    public let consoleStore: VaultConsoleStore
    public let history: HistoryStore
    public let subtitleLog: RotatingLog
    public let remotePlayLog: RotatingLog
    public let placements: GameReading.PlacementStore
    /// Sorun kaydı (`sorunlar.json`, Sistem sağlığı ve sorun bildirimi okur).
    public let problems: ProblemLog

    /// Paketlerin anlık kopyası (okuma hattının eşzamanlı "pakette mi" sorusu için).
    public private(set) var library = LegacyLibrary()
    public private(set) var pool: PoolClient?
    public private(set) var poolQueue: PoolQueue?
    public private(set) var packUpdater: PackUpdater?

    /// TV yolları (uygulama ömrünce tek; sunucular ilk gerekince açılır: çeviri ya da TV kurulumu).
    public let links: DisplayLinks
    /// TV kurulumu (TVSetup/); testlerde nil.
    public private(set) var tvSetup: TVSetupController?
    /// Güncelleme denetimi (GitHub; Sparkle sonra) ve indirme sayacı; ağ yoksa nil.
    public internal(set) var updater: UpdateService?
    public private(set) var downloadCounter: DownloadCounterService?
    /// Uygulama yardımcıları (AppSupport/: Sparkle, kısayollar, ekranı çevir, admin modu, debug kareleri); testlerde nil.
    public internal(set) var support: NinoAppSupport?

    // Oturum
    public private(set) var session: SubtitleSession?
    private var sessionTask: Task<Void, Never>?
    var source: SessionSource?
    private var startTask: Task<Void, Never>?
    private var timers: [Task<Void, Never>] = []
    private var rebuildTask: Task<Void, Never>?
    /// Görünüm gönderimleri sırayla gider (kaydırıcı sürüklenirken son değer en son ulaşır).
    private var styleSend: Task<Void, Never>?
    var sessionToken = 0
    /// "Pakette mi" ve ekran öğelerinin paket araması (okuyucu yeniden kurulmadan güncellenir).
    let packGate = PackGate()
    /// Oturumun ekran öğesi çevirmeni (çevirmen değişince güncellenir).
    var overlayTranslator: OverlayTranslator?
    /// Oturumun okuyucusu (okuma hatası bekçisiyle sarılmış `env.textReader`).
    private(set) var readingTextReader: GameReading.TextReader
    /// Ölçüm (nil: gönderim yolu yok).
    var meter: SessionMeter?
    var lifecycleObservers: [NSObjectProtocol] = []
    var sleepActivity: NSObjectProtocol?
    /// Bağlı TV sayısı (ölçüm: bağlandı/koptu).
    private var lastDisplayCount = 0
    /// Otomatik teşhis bekçisi (DiagWatch.swift, DiagMonitor.swift; bağlantılar LiveEngine+Diag.swift).
    lazy var diag: DiagMonitor = makeDiag()
    /// PS5 bu oturumda akıyor mu ve kopmadan sonraki bağlanma denemesi (teşhis izi).
    var diagPS5Streaming = false
    var diagPS5Retries = 0
    /// Son uyanış (uyanıştan hemen sonraki TV kopmaları `resume` sayılır).
    var lastWake: Date?
    /// Açık TV bağlantıları (kimlik → "bağlandı" olayı) ve bu oturumda ölçüme `tv_connect`'i gidenler.
    var liveTVLinks: [String: DisplayLinkEvent] = [:]
    var meteredTVLinks: Set<String> = []
    /// Ekrandan oyun tanıma denemeleri (havuz-paketler.md §6).
    var identifySchedule = IdentifySchedule()
    /// İlk saniyelerde her karede hafif okumayla oyun tanıma (GameAuto.swift).
    lazy var quickSense: GameReading.QuickGameSense? = env.quickTextReader.map {
        GameReading.QuickGameSense(reader: $0, clock: env.clock)
    }
    /// Son oynanan tahmini ne zamandan beri doğrulanmadı (`env.clock` ms).
    var seedSinceMs: Int?
    var localNetworkProbing = false
    private var screenTranslationOn = false
    var lastLocalNetworkProbe: Date?
    public private(set) var activeOnlineEngine: MacSettings.OnlineEngine?
    public internal(set) var games = GameTracker()
    /// Son açılışta yapılanların notları (testler ve günlük).
    public internal(set) var notes: [String] = []
    /// Başlatma bitince (testler bekler).
    public private(set) var lastStart: Task<Void, Never>?
    public private(set) var libraryLoad: Task<Void, Never>?
    /// Son PS5 aramasının sonuçları (eşleştirmede seçilen PS5'in kimliği için).
    var lastFoundConsoles: [DiscoveredPS5] = []
    lazy var psnLogin = PSNLoginController(store: consoleStore, log: consoleLog)
    /// Oyun penceresi, yakalama kartı ve Xbox (Capture/).
    lazy var capture: CaptureCoordinator = {
        let log = subtitleLog
        let override = isDevelopment ? env.settingsStore.defaults.string(forKey: CaptureEnvironment.windowTargetDefaultsKey) : nil
        return CaptureCoordinator(state: state, settingsStore: env.settingsStore,
                                  environment: .live(windowTargetOverride: override), log: { log.write($0) })
    }()
    var consoleLogForActions: ConsoleLog { consoleLog }
    func rebuildTranslatorNow() { scheduleRebuild() }

    public init(state: AppState, environment env: LiveEngineEnvironment) {
        self.state = state
        self.env = env
        self.records = SecureRecords(vault: env.vault)
        self.secrets = LegacySecretStore(vault: env.vault)
        self.consoleStore = VaultConsoleStore(records: records)
        self.history = HistoryStore(folder: env.folder)
        self.subtitleLog = RotatingLog(url: env.folder.subtitleLog)
        self.remotePlayLog = RotatingLog(url: env.folder.remotePlayLog)
        self.placements = Self.openPlacements(env.folder)
        self.problems = ProblemLog(folder: env.folder)
        self.readingTextReader = env.textReader
        self.links = DisplayLinks(ports: env.ports, senderName: "Nino", appVersion: env.appVersion)
        state.attach(self)
        links.onCountChange = { [weak self] n in
            Task { @MainActor in self?.displayCountChanged(n) }
        }
        links.onLinkEvent = { [weak self] e in
            Task { @MainActor in self?.tvLinkEvent(e) }
        }
        if let make = env.makeTVSetup { tvSetup = make(state, records, env.folder, links) }
        if let network = env.network {
            updater = GitHubUpdateChecker(network: network, currentVersion: env.appVersion, install: { info in
                if let url = info?.downloadURL ?? info?.notesURL { NSWorkspace.shared.open(url) }
            })
            downloadCounter = DownloadCounterService(network: network, defaults: env.settingsStore.defaults)
        }
        bootstrap()
        meter = makeTelemetry().map(SessionMeter.init)
        startTelemetry()
        startDiag()
        observeWake()
    }

    /// Bağlı TV sayısı (ölçüm olayları artık bağlantı başına: `tvLinkEvent`).
    private func displayCountChanged(_ n: Int) {
        lastDisplayCount = n
        state.connectedDisplays = n
        state.sheetsStatus.healthMetrics.connectedTVs = n
    }

    /// Uygulamanın gerçek motoru.
    public static func live(identity: AppIdentity = .current(), state: AppState) -> LiveEngine {
        LiveEngine(state: state, environment: .live(identity: identity))
    }

    public var isDevelopment: Bool { env.identity.flavor != .release }

    // MARK: - Açılış

    private func bootstrap() {
        for n in env.folderNotes { remotePlayLog.write(n) }
        let store = env.settingsStore
        // `settings` didSet motora gider; açılışta kaydetmesin diye önce motor yokmuş gibi yazmayız: değer aynıysa didSet bir şey yapmaz.
        let loaded = store.load()
        loading = true
        state.settings = loaded
        loading = false
        state.adminMode = AdminModeRules.isOn(flavor: env.identity.flavor, flag: store.adminMode)
        state.adminBadges = AdminModeRules.showsBadges(flavor: env.identity.flavor, adminOn: state.adminMode)
        state.downloadTotal = store.downloadTotal > 0 ? store.downloadTotal : nil
        state.coversFolder = env.folder.coversFolder
        state.sheetsStatus.dataFolder = env.folder
        state.sheetsStatus.deviceFacts = DeviceFacts.current()
        state.sheetsStatus.problems = problems.all
        state.history = history.load()

        // Kasa: PSN, PS5, TV, kurulum, anahtarlar.
        if let id = try? records.accountID() { state.psnAccount = .signedIn(accountID: id) }
        state.pairedConsole = try? records.pairedConsole()
        state.pairedTV = try? records.pairedTV()
        if (try? records.setupComplete()) == true { state.setupStep = .done }
        state.settingsStatus.passcodeSaved = ((try? records.loginPasscode()) ?? nil)?.isEmpty == false
        state.settingsStatus.savedKeys = Set(MacSettings.OnlineEngine.allCases.filter {
            ((try? records.translationKey($0)) ?? nil) != nil
        })
        state.setup.geminiKeySaved = state.settingsStatus.savedKeys.contains(.gemini)
        state.nudges.attach(defaults: env.settingsStore.defaults)
        state.settingsStatus.overlayServerPort = Int(env.ports.legacy == 0 ? LegacyEventServer.defaultPort : env.ports.legacy)
        state.source = Self.idleSource(for: state.settings)
        refreshGameMemory()
        // Oyun penceresi / kart / Xbox durumları (Capture/); testler kendi kaynağını verir, onlarda kurulmaz.
        if env.makeSource == nil { _ = capture }

        setUpPool()
        libraryLoad = Task { await reloadLibrary() }
        refreshReadiness()

        // Kendiliğinden işler yalnız yayın yapısında (deneme yapısı ağa ve PS5'e kendiliğinden çıkmaz).
        guard !isDevelopment else {
            notes.append("deneme yapısı: kendiliğinden başlatma yok")
            store.defaults.removeObject(forKey: DefaultsKey.resumeAfterRelaunch)
            return
        }
        Task { await checkPacks(.launch) }
        if let at = store.defaults.object(forKey: DefaultsKey.resumeAfterRelaunch) as? Double {
            store.defaults.removeObject(forKey: DefaultsKey.resumeAfterRelaunch)
            if Date().timeIntervalSince1970 - at <= 120, state.isSetupComplete, state.canStart {
                notes.append("yeniden açılış: çeviri sürdürülüyor")
                startTranslation()
            }
        }
    }

    private var loading = false

    static func idleSource(for s: MacSettings) -> SourceStatus {
        switch s.videoSource {
        case .ps5: return .ps5(.idle)
        case .window: return .window(.idle)
        case .card: return .card(.idle)
        }
    }

    /// Öğrenilen altyazı yeri. NinoCore'un biçimi eski `subtitle-layout.json`'dan farklı; yeni dosya açılır,
    /// ilk açılışta eski örneklerle doldurulur (eski dosyaya dokunulmaz).
    static func openPlacements(_ folder: DataFolder) -> GameReading.PlacementStore {
        let url = folder.support.appendingPathComponent("altyazi-yeri.json")
        let fresh = !FileManager.default.fileExists(atPath: url.path)
        let store = GameReading.PlacementStore(url: url)
        if fresh {
            for (game, bands) in DataFiles.subtitleLayout(at: folder.subtitleLayoutFile) {
                for b in bands { store.record(GameReading.Box(left: 0.14, top: b.top, right: 0.86, bottom: b.bottom), game: game) }
            }
        }
        return store
    }

    // MARK: Havuz ve paketler

    private func setUpPool() {
        guard let transport = env.poolTransport, let base = env.poolBaseURL else { return }
        let lang = state.settings.targetLanguage
        let config = PoolConfiguration(baseURL: base, enabled: state.settings.sharePool, platform: "mac",
                                       appVersion: env.appVersion)
        let install = installID
        let translations = PoolTranslations(root: env.folder.support, language: lang)
        pool = PoolClient(configuration: config, transport: transport, translations: translations, install: install)
        if state.settings.sharePool {
            poolQueue = PoolQueue(directory: env.folder.poolFolder, configuration: config, transport: transport,
                                  legacyQueueFile: env.folder.support.appendingPathComponent("pool.json"))
        }
        if let packsBase = env.packsBaseURL {
            let packConfig = PoolConfiguration(baseURL: packsBase, enabled: true, platform: "mac", appVersion: env.appVersion)
            packUpdater = PackUpdater(packsDirectory: env.folder.packsFolder,
                                      statusFile: env.folder.support.appendingPathComponent("packs-remote.json"),
                                      configuration: packConfig, transport: transport)
        }
    }

    /// Veri klasöründeki paketleri okur (internet gerekmez).
    public func reloadLibrary() async {
        let dir = env.folder.packsFolder
        let lib = await Task.detached { LegacyLibrary(directories: [dir]) }.value
        library = lib
        packGate.update(library: lib, enabled: Self.packsEnabled(state.settings))
        state.settingsStatus.gamePacks = Self.groupedPacks(lib.infos.filter { $0.id != LegacyLibrary.generalPackID }
            .map { GamePackInfo(id: $0.id, name: $0.title, lines: $0.lineCount) })
        state.sheetsStatus.packGames = lib.infos.filter { $0.id != LegacyLibrary.generalPackID }.map(\.title)
        if let sense = quickSense {
            Task.detached { sense.setMarkers(GameReading.GameMarkers(library: lib)) }
        }
        if state.isTranslating { scheduleRebuild() }
    }

    /// Ayarlar'daki kütüphane listesi: aynı oyunun paketleri (gömülü ve havuz, ör. gta6 ve pool-gta-6) asıl kimlikle
    /// tek satır olur; ad tablodaki adla, satır sayısı en büyük paketinki (paketler büyük ölçüde aynı satırları taşır).
    nonisolated static func groupedPacks(_ packs: [GamePackInfo]) -> [GamePackInfo] {
        var order: [String] = []
        var byGame: [String: GamePackInfo] = [:]
        for p in packs {
            let key = GameIDs.id(p.id) ?? GameIDs.id(p.name) ?? p.id
            let name = GameIDs.knownName(p.id) ?? GameIDs.knownName(p.name) ?? p.name
            if let have = byGame[key] {
                byGame[key] = GamePackInfo(id: have.id, name: have.name, lines: max(have.lines, p.lines))
            } else {
                order.append(key)
                byGame[key] = GamePackInfo(id: p.id, name: name, lines: p.lines)
            }
        }
        return order.compactMap { byGame[$0] }
    }

    /// Sunucudan paket güncellemesi; internet yoksa sessizce paketsiz sürer.
    public func checkPacks(_ reason: PackUpdater.Reason) async {
        guard let packUpdater, state.settings.gamePacks else { return }
        guard let result = await packUpdater.checkIfDue(reason) else { return }
        diagPacks(result)
        if result.listFailed { notes.append("paket listesi alınamadı; eldeki paketlerle sürülüyor") }
        if result.changed { await reloadLibrary() }
    }

    // MARK: Çevirmen hazırlığı

    private func refreshReadiness() {
        guard env.checksTranslatorReadiness else { return }
        let s = state.settings
        Task {
            let r = await TranslatorReadinessCheck.current(source: s.sourceLanguage, target: s.targetLanguage)
            self.state.translator = r
        }
    }

    // MARK: - Ayarlar

    /// Görünümü sıraya koyup hub'a yollar (47800 giden/gelen ve 8787 eski yol; bağlanmamış TV'ye sonra yeniden gider).
    func pushStyle(_ style: SubtitleStyle) {
        let message = NinoStyle(style)
        let previous = styleSend
        styleSend = Task { [links] in
            await previous?.value
            try? await links.hub.send(.style(message))
        }
    }

    /// Sıradaki görünüm gönderimleri bitene dek bekler (testler).
    func styleSent() async { await styleSend?.value }

    public func settingsChanged(from old: MacSettings, to new: MacSettings) {
        guard !loading else { return }
        env.settingsStore.save(new)
        if old.sourceLanguage != new.sourceLanguage || old.targetLanguage != new.targetLanguage {
            refreshReadiness()
            Task { await pool?.translations.switchLanguage(new.targetLanguage) }
        }
        if old.sharePool != new.sharePool { Task { await self.poolSettingChanged(new.sharePool) } }
        // Görünüm her zaman hemen hub'a gider (ayarlar.md §6.3): çeviri kapalıyken de deneme altyazısını gösteren TV
        // kaydırıcıyla birlikte büyür; bağlı çıkış yoksa hub son görünümü saklar, sonra bağlanana yollar.
        if old.style != new.style { pushStyle(new.style) }
        if !state.isTranslating, state.translation == .off {
            if old.videoSource != new.videoSource { state.source = Self.idleSource(for: new) }
            return
        }
        // Kaynak değişti: durdur ve yeni kaynakla yeniden başlat.
        if old.videoSource != new.videoSource || old.gameConsole != new.gameConsole {
            stopTranslation()
            startTranslation()
            return
        }
        do {
            if old.output != new.output {
                let onTV = state.subtitlesOnTV
                Task { await links.hub.setSubtitlesOnTV(onTV) }
            }
        }
        if let session {
            if old.region != new.region {
                let region = GameReading.Region(Self.box(new.region))
                Task { await session.reader.setRegion(region) }
            }
            if old.subtitlesOnly != new.subtitlesOnly {
                let on = new.subtitlesOnly
                Task { await session.reader.setSubtitlesOnly(on) }
            }
            if old.showSpeakerNames != new.showSpeakerNames || old.areaPreset != new.areaPreset {
                let o = sessionOptions(new)
                Task { await session.setOptions(o) }
            }
            if old.translateCorners != new.translateCorners || old.extraAreas != new.extraAreas
                || old.sourceLanguage != new.sourceLanguage || old.targetLanguage != new.targetLanguage {
                let o = overlayOptions(new)
                Task { await session.overlays?.setOptions(o) }
            }
            if old.targetLanguage != new.targetLanguage {
                let lang = new.targetLanguage
                Task { await session.overlays?.switchLanguage(lang) }
            }
            if old.translateCorners != new.translateCorners || old.sourceLanguage != new.sourceLanguage
                || old.targetLanguage != new.targetLanguage || old.gamePacks != new.gamePacks {
                refreshGameForReading()
            }
        }
        if Self.translationInputsChanged(old, new) { scheduleRebuild() }
    }

    static func translationInputsChanged(_ a: MacSettings, _ b: MacSettings) -> Bool {
        a.sourceLanguage != b.sourceLanguage || a.targetLanguage != b.targetLanguage
            || a.onlineTranslation != b.onlineTranslation || a.onlineEngine != b.onlineEngine
            || a.geminiModel != b.geminiModel || a.openAIModel != b.openAIModel || a.claudeModel != b.claudeModel
            || a.localAIBaseURL != b.localAIBaseURL || a.localAIModel != b.localAIModel
            || a.gamePacks != b.gamePacks || a.sharePool != b.sharePool
    }

    private func poolSettingChanged(_ on: Bool) async {
        if !on {
            await poolQueue?.clear()
            poolQueue = nil
        } else if poolQueue == nil, let transport = env.poolTransport, let base = env.poolBaseURL {
            let config = PoolConfiguration(baseURL: base, enabled: true, platform: "mac", appVersion: env.appVersion)
            poolQueue = PoolQueue(directory: env.folder.poolFolder, configuration: config, transport: transport)
        }
        // Havuz istemcisinin "enabled" bayrağı kurulurken verilir: yeniden kurulur.
        if let transport = env.poolTransport, let base = env.poolBaseURL {
            let config = PoolConfiguration(baseURL: base, enabled: on, platform: "mac", appVersion: env.appVersion)
            let translations = pool?.translations ?? PoolTranslations(root: env.folder.support, language: state.settings.targetLanguage)
            pool = PoolClient(configuration: config, transport: transport, translations: translations,
                              install: pool?.install ?? installID)
        }
    }

    /// Çeviri sürerken motor/dil/paket ayarı değişti: zincir yeniden kurulur (bir motorun önbelleği ötekine karışmasın).
    private func scheduleRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let session = self.session else { return }
            let t = await self.makeTranslator()
            await session.setTranslator(t)
            await session.setOptions(self.sessionOptions(self.state.settings))
            self.overlayTranslator?.setTranslator(t)
            self.overlayTranslator?.setPool(self.overlayPool(self.state.settings))
            self.overlayTranslator?.setLanguages(source: self.state.settings.sourceLanguage,
                                                 target: self.state.settings.targetLanguage)
            await self.applyKnownGame(to: t)
        }
    }

    // MARK: - Çeviri

    public func startTranslation() {
        guard state.translation == .off else { return }
        guard state.canStart else {
            notes.append("başlatılamaz: kaynak ya da çıkış hazır değil")
            return
        }
        state.translation = .starting
        sessionToken += 1
        let token = sessionToken
        let task = Task { await self.beginSession(token: token) }
        startTask = task
        lastStart = task
    }

    private func beginSession(token: Int) async {
        // Önceki durdurma (TV'ye "durdu", bağlantı kapama) yeni oturumun üstüne düşmesin.
        await lastStop?.value
        let s = state.settings
        await libraryLoad?.value
        var tvHosts: [String] = []
        if let tv = state.pairedTV, tv.brand == .androidTV, state.subtitlesOnTV { tvHosts.append(tv.host) }
        await links.start(tvHosts: tvHosts)
        for n in links.notes { remotePlayLog.write(n) }
        await links.hub.setSubtitlesOnTV(state.subtitlesOnTV)
        try? await links.hub.send(.style(NinoStyle(s.style)))
        guard token == sessionToken else { return }

        // Oyun: elle seçilen ya da son oynanan hemen etkin (okuyucu, telefon kararı ve havuz bundan kurulur).
        games.startSession(at: Date())
        seedGameForSession()
        let translator = await makeTranslator()
        packGate.update(enabled: Self.packsEnabled(s))
        state.textReadingFailure = nil
        readingTextReader = ReadingWatch(base: env.textReader, onText: { [weak self] in
            // Yazı tanıma bir metin döndürdü (otomatik teşhis `ocr.silent` sayacı; saniyede en çok bir).
            Task { @MainActor in self?.diag.record(.ocrText) }
        }) { [weak self] failing in
            Task { @MainActor in self?.readingFailureChanged(failing, token: token) }
        }
        // Telefon paneli (telefon-harita.md "Giriş noktası"): hafıza veri klasöründe `phone-memory-<dil>.json`.
        let overlayTranslator = OverlayTranslator(translator: translator, packLookup: { [packGate] in packGate.lookup($0) },
                                                  pool: overlayPool(s), device: env.deviceProvider(),
                                                  sourceLanguage: s.sourceLanguage, targetLanguage: s.targetLanguage)
        self.overlayTranslator = overlayTranslator
        let phone = GameReading.PhoneWatcher(textReader: env.phoneTextReader, clock: env.clock,
                                             memory: .init(directory: env.folder.support, language: s.targetLanguage),
                                             translator: overlayTranslator, rectangles: env.phoneRectangles)
        let reader = makeReader(s, phone: phone)
        let overlays = ScreenOverlays(reader: reader, textReader: readingTextReader, phone: phone,
                                      translator: overlayTranslator, output: links.output, clock: env.clock,
                                      options: overlayOptions(s), onEvent: { [weak self] e in
                                          Task { @MainActor in self?.overlayEvent(e, token: token) }
                                      })
        let decision = phoneDecision(s)
        await overlays.setReportedGame(games.isCertain ? games.current?.name : nil)
        await overlays.setPhoneGame(decision.on)
        let session = SubtitleSession(reader: reader, translator: translator, output: links.output, clock: env.clock,
                                      options: sessionOptions(s), overlays: overlays, onEvent: { [weak self] e in
                                          Task { @MainActor in self?.handle(e, token: token) }
                                      })
        guard token == sessionToken else { return }
        self.session = session
        await applyKnownGame(to: translator)
        guard token == sessionToken else { self.session = nil; return }
        gameChanged()

        let callbacks = SourceCallbacks(status: { [weak self] st in
            Task { @MainActor in self?.sourceChanged(st, token: token) }
        }, consoleMoved: { [weak self] p in
            Task { @MainActor in self?.state.pairedConsole = PairedConsole(name: p.name, host: p.host) }
        }, gameArea: { [weak self] rect in
            Task { @MainActor in
                guard let self, token == self.sessionToken else { return }
                self.state.gameAreaFrame = rect
            }
        })
        let source = env.makeSource?(s, callbacks)
            ?? capture.makeSource(s, callbacks: callbacks)
            ?? SessionSources.live(settings: s, store: consoleStore, log: consoleLog, callbacks: callbacks)
        self.source = source
        let tapped = support?.tap(source.frames.frames()) ?? source.frames.frames()
        let frames = quickTap(tapped, token: token)
        sessionTask = Task.detached { await session.run(frames) }
        try? await links.hub.send(.started)
        guard token == sessionToken else {
            // Başlarken durduruldu: kaynak kapatılır, çeviri açılmaz.
            source.stop()
            sessionTask?.cancel()
            return
        }
        state.translation = .on
        // TV uygulamasını bu Mac'in adresiyle açar ve açık tutar (LG/Samsung; eski TV uygulaması da).
        // Samsung'da TV zaten bağlıysa dokunulmaz; LG'de yalnız TV kendi girişine geçince yeniden açılır.
        if state.subtitlesOnTV, state.pairedTV != nil { tvSetup?.startKeepingAppOpen() }
        diagSessionStarted(s)
        meter?.sessionStarted()
        tvLinksSessionStarted()
        if let telemetry = meter?.telemetry {
            let brand = Self.telemetryBrand(state.pairedTV)
            Task { await telemetry.setTVBrand(brand) }
        }
        holdSleepAssertion(true)
        identifySchedule.start(at: Date())
        quickSense?.start()
        if games.isConfirmed { quickSense?.stop() }
        state.sheetsStatus.healthMetrics.translating = true
        state.sheetsStatus.healthMetrics.sourceIsPS5 = s.videoSource == .ps5
        state.sheetsStatus.healthMetrics.subtitlesOnTV = state.subtitlesOnTV
        state.sheetsStatus.healthMetrics.usesOnlineOrLocalEngine = activeOnlineEngine != nil
        subtitleLog.write("Çeviri başladı (\(s.videoSource.rawValue) → \(s.output.rawValue))")
        startTimers(token: token)
        Task { await self.checkPacks(.launch) }
    }

    public func stopTranslation() {
        guard state.translation != .off else { return }
        sessionToken += 1
        startTask?.cancel()
        startTask = nil
        for t in timers { t.cancel() }
        timers = []
        rebuildTask?.cancel()
        let session = self.session, links = self.links, task = sessionTask, source = self.source
        self.session = nil
        self.sessionTask = nil
        self.source = nil
        source?.stop()
        task?.cancel()
        if state.translation == .on { meter?.sessionEnded(game: games.current?.id, source: telemetrySource) }
        diag.record(.sessionStop)
        diagPS5Streaming = false
        holdSleepAssertion(false)
        screenTranslationOn = false
        tvSetup?.stopKeepingAppOpen()
        state.translation = .off
        state.textReadingFailure = nil
        state.sheetsStatus.healthMetrics.translating = false
        state.sheetsStatus.healthMetrics.receivingVideo = false
        state.source = Self.idleSource(for: state.settings)
        quickSense?.stop()
        seedSinceMs = nil
        state.lastLine = nil
        state.extraAreaTexts = []
        state.gameAreaFrame = nil
        state.localNetworkBlocked = false
        games.endSession()
        subtitleLog.write("Çeviri durdu")
        let queue = poolQueue
        let stopped = Task {
            await session?.stop()
            try? await links.hub.clear(id: nil)
            try? await links.hub.send(.stopped)
            await links.disconnectTVs()
            _ = await queue?.run()
        }
        lastStop = stopped
    }

    /// Durdurma bitince (testler bekler).
    public private(set) var lastStop: Task<Void, Never>?

    private var consoleLog: ConsoleLog {
        let log = remotePlayLog
        return ConsoleLog(path: env.folder.remotePlayLog.path, write: { log.write($0) })
    }

    func makeTranslator() async -> SubtitleTranslating {
        let s = state.settings
        var input = TranslatorFactory.Inputs(
            settings: s, library: library, pool: pool, queue: poolQueue,
            cacheDirectory: env.folder.translationsFolder, secrets: secrets,
            providerTransport: env.providerTransport, deviceProvider: env.deviceProvider(),
            onAlert: { [weak self] engine, alert in
                Task { @MainActor in
                    let problem = alert.map { OnlineEngineProblem(engine: engine, kind: TranslatorFactory.problemKind($0)) }
                    if let problem, problem != self?.state.onlineEngineProblem {
                        self?.recordError(Self.telemetryCode(problem.kind))
                    }
                    self?.state.onlineEngineProblem = problem
                }
            })
        input.onResult = { [weak self] status in
            Task { @MainActor in self?.diag.record(status.map { .trError(http: $0) } ?? .trOK) }
        }
        if let custom = env.makeTranslator { return await custom(input) }
        let built = await TranslatorFactory().build(input)
        activeOnlineEngine = built.onlineEngine
        if built.onlineEngine == nil { state.onlineEngineProblem = nil }
        return built.translator
    }

    private func makeReader(_ s: MacSettings, phone: GameReading.PhoneWatcher?) -> GameReading.Reader {
        var cfg = GameReading.Reader.Configuration()
        cfg.region = GameReading.Region(Self.box(s.region))
        cfg.fastDetection = s.fastSubtitleDetection
        cfg.subtitlesOnly = s.subtitlesOnly
        // Telefon oyunu (GTA 6) kararı: havuz önceliği, kartlar, oyun anahtarı, harita = menü (telefon-harita.md §1.1).
        // Oyun bilinmiyorsa son oyunun "havuz öncelikli" bilgisi kullanılır (veri-uyumu.md `ninoLastGamePoolFirst`).
        GameReading.GTA6Rules.apply(phoneDecision(s).on, packGame: games.current?.id, to: &cfg)
        let gate = packGate
        return GameReading.Reader(textReader: readingTextReader, clock: env.clock, configuration: cfg,
                                  placementStore: placements, phone: phone,
                                  isInPack: { gate.isInPack($0) })
    }

    func sessionOptions(_ s: MacSettings) -> SubtitleSession.Options {
        var o = SubtitleSession.Options()
        o.showSpeakerNames = s.showSpeakerNames
        o.targetLanguage = s.targetLanguage
        o.position = s.areaPreset == .top || (s.region.bottom < 0.5) ? .top : .bottom
        if Self.packsEnabled(s) {
            let gate = packGate
            o.packLookup = { gate.lookup($0) }
        }
        if s.targetLanguage != "tr" {
            let check = TargetLanguageCheck(guesser: NaturalLanguageGuesser())
            let target = s.targetLanguage, source = s.sourceLanguage
            o.isTargetLanguage = { check.isAlreadyTarget($0, target: target, source: source) }
        }
        return o
    }

    static func box(_ r: Region) -> GameReading.Box {
        GameReading.Box(left: r.left, top: r.top, right: r.right, bottom: r.bottom)
    }

    // MARK: - Oturum olayları

    /// Ekranı çevir başladı/bitti (AppSupport/ScreenTranslation doğrudan da çağırabilir).
    public func screenTranslationActive(_ on: Bool) {
        guard on != screenTranslationOn, let overlays = session?.overlays else { return }
        screenTranslationOn = on
        Task { await overlays.setSuspended(on) }
    }

    private func readingFailureChanged(_ failing: Bool, token: Int) {
        guard token == sessionToken else { return }
        if failing {
            let free = ReadingWatch.freeDiskGB() ?? 100
            state.textReadingFailure = TextReadingFailure(freeDiskGB: free)
            subtitleLog.write("Yazı okunamıyor (boş disk \(String(format: "%.1f", free)) GB)")
            recordError(free < 10 ? TelemetryCode.storageFull : TelemetryCode.ocrFailed)
        } else {
            state.textReadingFailure = nil
        }
    }

    private func handle(_ e: SessionEvent, token: Int) {
        guard token == sessionToken else { return }
        switch e {
        case let .shown(line, id):
            logShown(id: id)
            diagLineShown(line)
            noteShownLine(line)
            state.lastLine = line
            meter?.lineShown(line)
            let origin: HistoryOrigin = line.origin == .pack ? .pack : .engine
            state.history = HistoryStore.adding(HistoryEntry(date: Date(), source: line.source, translated: line.translated,
                                                             origin: origin), to: state.history)
            history.save(state.history)
            state.sheetsStatus.healthMetrics.subtitleLines += 1
            if line.origin != .untranslated { state.sheetsStatus.healthMetrics.translatedLines += 1 }
            if let ms = line.latencyMs {
                let m = state.sheetsStatus.healthMetrics.maxTranslationMs ?? 0
                state.sheetsStatus.healthMetrics.maxTranslationMs = max(m, ms)
            }
        case .cleared:
            state.lastLine = nil
        case let .packVote(id):
            let title = library.pack(for: id)?.title
            if games.vote(packID: id, title: title) { gameChanged() }
        case .readerStuck:
            subtitleLog.write("Okuma takıldı; hat sıfırlandı")
            diag.record(.ocrStuck)
        case let .frame(box):
            state.settingsStatus.lastFrame = box.image
            meter?.frameSeen()
            diag.sampleFrame(box.image)
        case let .ocr(ms):
            meter?.ocr(ms: ms)
            diag.record(.ocrSlow(ms: ms))
        case let .fps(n):
            diag.framesPerSecond(n)
        case .stripLearned:
            subtitleLog.write("Altyazı şeridi öğrenildi")
        case let .trace(t):
            logTrace(t)
        }
    }

    private func sourceChanged(_ status: SourceStatus, token: Int) {
        guard token == sessionToken else { return }
        let before = state.source
        state.source = status
        if case let .ps5(link) = status {
            let previous: SourceStatus.ConsoleLink? = { if case let .ps5(l) = before { return l }; return nil }()
            meter?.ps5Status(link, before: previous)
            diagPS5Status(link)
            localNetworkCheck(link)
            switch link {
            case .streaming:
                if case .ps5(.streaming) = before {} else { quickSenseStreamResumed() }
                state.sheetsStatus.healthMetrics.receivingVideo = true
                state.sheetsStatus.healthMetrics.connections += 1
                state.sheetsStatus.healthMetrics.ps5DownSince = nil
                state.localNetworkBlocked = false
                state.health.consoleLink = .good
                state.health.videoStream = .good
            case let .dropped(reason):
                state.sheetsStatus.healthMetrics.receivingVideo = false
                state.sheetsStatus.healthMetrics.lastDropReason = HealthDropReason(reason)
                if case .ps5(.streaming) = before { state.sheetsStatus.healthMetrics.dropsWhileStreaming += 1 }
                if state.sheetsStatus.healthMetrics.ps5DownSince == nil { state.sheetsStatus.healthMetrics.ps5DownSince = Date() }
                state.health.consoleLink = .poor
                state.health.incidents.insert(HealthSnapshot.Incident(date: Date(), cause: "\(reason)"), at: 0)
                if state.health.incidents.count > 50 { state.health.incidents.removeLast(state.health.incidents.count - 50) }
                games.consoleLost()
                let wasStreaming: Bool = { if case .ps5(.streaming) = before { return true }; return false }()
                let record = ProblemRecord(date: Date(), kind: wasStreaming ? .ps5Dropped : .ps5Unreachable,
                                           reason: HealthDropReason(reason).rawValue,
                                           network: state.sheetsStatus.healthMetrics.network.rawValue, game: state.game?.name)
                if wasStreaming || state.sheetsStatus.problems.last?.kind != record.kind {
                    problems.add(record)
                    state.sheetsStatus.problems = problems.all
                    remotePlayLog.write(record.logLine)
                }
                if case .ps5(.streaming) = before, let session {
                    // Bağlantı koptu: hat ve sıra sıfırlanır, TV temizlenir.
                    Task { await session.reset() }
                }
                subtitleLog.write("PS5: bağlı değil")
            case .connecting:
                state.sheetsStatus.healthMetrics.connectAttempts += 1
                subtitleLog.write("PS5: bağlanıyor")
            case .idle:
                break
            }
        }
    }

    // MARK: - Oyun

    private func startTimers(token: Int) {
        // PS5'in bildirdiği oyun: 120 sn'de bir yalnız bağlı PS5'in adresine.
        if let discovery = env.consoleDiscovery, state.settings.videoSource == .ps5 {
            timers.append(Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(120))
                    guard let self, token == self.sessionToken else { return }
                    guard case .ps5(.streaming) = self.state.source, let host = self.state.pairedConsole?.host else { continue }
                    let found = try? await discovery.probe(address: host, duration: 2)
                    if self.games.consoleReported(name: found?.runningApp, titleID: found?.runningAppID) { self.gameChanged() }
                }
            })
        }
        // Ekranı çevir sürerken / sonucu ekrandayken köşe ve ipucu katmanı durur (sonucun yerine geçmesin).
        timers.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, token == self.sessionToken else { return }
                let active = self.support.map { $0.screen.isRunning || $0.screen.showing } ?? false
                self.screenTranslationActive(active)
            }
        })
        // Ekrandan oyun tanıma (havuz-paketler.md §6): zamanı geldiyse son kare sunucuya.
        timers.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard let self, token == self.sessionToken else { return }
                self.identifyIfDue()
                self.checkSeed()
            }
        })
        // Havuz: gönderme kuyruğu ve oyunun çevirileri dakikada bir.
        if pool != nil || poolQueue != nil {
            timers.append(Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    guard let self, token == self.sessionToken else { return }
                    let queue = self.poolQueue, pool = self.pool, game = self.games.current?.id
                    _ = await queue?.run()
                    await pool?.refreshConfig()
                    if self.state.settings.sharePool { _ = await pool?.sync(game: game) }
                }
            })
        }
    }

    /// Oyun değişti: ana ekran, çevirmenin oyun bilgisi, paket bakışı, havuz çevirileri.
    func gameChanged() {
        defer { refreshGameForReading() }
        let previous = state.game
        if let c = games.current, let evidence = games.evidence {
            state.game = RecognizedGame(id: c.id, name: c.name, poolFirst: previous?.id == c.id ? previous?.poolFirst ?? false : false,
                                        evidence: evidence)
            gameConfirmedIfNeeded()
            if let session {
                Task {
                    let t = await session.currentTranslator
                    await self.applyKnownGame(to: t)
                    let poolFirst = await t.isPoolFirst(game: c.id)
                    if self.state.game?.id == c.id { self.state.game?.poolFirst = poolFirst }
                    if evidence != .lastPlayed { self.env.settingsStore.lastGamePoolFirst = poolFirst }
                }
            }
            if previous?.id != c.id, !isDevelopment || state.isTranslating {
                Task {
                    await self.checkPacks(.newGame)
                    if self.state.settings.sharePool { _ = await self.pool?.sync(game: c.id, force: true) }
                }
            }
        } else {
            state.game = nil
        }
    }

    private func applyKnownGame(to t: SubtitleTranslating) async {
        // Son oynanan tahmini de havuz önceliği için hemen bilinir (yanlışsa ekran/paket kısa sürede düzeltir).
        let certain = games.isCertain || games.evidence == .lastPlayed ? games.current?.name : nil
        await t.setKnownGame(certain)
        await t.selectGame(games.user?.name)
    }

    // MARK: Son oynanan (PS5 adı → oyun)

    var consoleKey: String? {
        guard let c = state.pairedConsole else { return nil }
        return c.name.isEmpty ? c.host : c.name
    }

    var lastGames: [String: String] {
        get { env.settingsStore.defaults.dictionary(forKey: "lastGames") as? [String: String] ?? [:] }
        set { env.settingsStore.defaults.set(newValue, forKey: "lastGames") }
    }
}
