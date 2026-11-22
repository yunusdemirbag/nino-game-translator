// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import NinoCore
import NinoRemotePlay
import SwiftUI
import Translation
import UIKit

/// Uygulamanın bütün durumu: kurulum, çeviri oturumu, ayarlar.
@MainActor
final class AppModel: ObservableObject {
    enum Step: Int, CaseIterable, Comparable {
        case welcome, psnLogin, console, output, done
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    /// Konsol bağlantısının durumu.
    enum Link: Equatable {
        case streaming
        case connecting
        case disconnected(Reason)
    }

    /// Bağlantının neden koptuğu ya da kurulamadığı.
    enum Reason: Equatable {
        case stopped
        case asleep
        case inUse
        case refused
        case noPicture
        case notFound(String)
        case network
        case rejected(code: UInt32?)
        case loginPasscode
        case loginPasscodeIncorrect
        case other(String)

        /// Otomatik teşhis için kopma sebebi (bkz. DiagWatch `ps5.no_return`).
        var diagCause: String? {
            switch self {
            case .asleep: "ps5_standby"
            case .inUse: "kicked"
            case .noPicture: "stalled"
            case .rejected: "ps5_closed"
            default: nil
            }
        }

        /// Ölçüm için kısa kod (metin değil).
        var code: String {
            switch self {
            case .stopped: "stopped"
            case .asleep: "asleep"
            case .inUse: "in_use"
            case .refused: "refused"
            case .noPicture: "no_picture"
            case .notFound: "not_found"
            case .network: "network"
            case .rejected: "rejected"
            case .loginPasscode: "passcode"
            case .loginPasscodeIncorrect: "passcode_wrong"
            case .other: "other"
            }
        }

        /// `other` nedeninin metni (Xbox oturumu kendi metnini verir; PS5'te gösterilmez).
        var detail: String? {
            if case let .other(text) = self { return text }
            return nil
        }

        /// Ekranda gösterilecek metin (durdurma ve ayrıntısız nedenlerde yok).
        var message: String? {
            switch self {
            case .stopped, .other: nil
            case .asleep: L("ps5.turnon")
            case .inUse: L("session.error.inuse")
            case .refused: L("session.error.refused")
            case .noPicture: L("session.error.nopicture")
            case let .notFound(host): L("session.error.notatip", host)
            case .network: L("session.error.unreachable")
            case .loginPasscode: L("ps5.reason.passcode")
            case .loginPasscodeIncorrect: L("ps5.reason.passcodeWrong")
            case let .rejected(code?):
                L("session.error.rejected",
                  String(format: "0x%08x", code))
            case .rejected(nil):
                L("session.error.notstarted")
            }
        }
    }

    struct RecentLine: Identifiable, Equatable {
        let id: Int
        let source: String
        let translation: String
        let fromPack: Bool
    }

    // MARK: Bağımlılıklar

    let store: SecureStore
    let defaults: UserDefaults
    let folders: AppFolders
    /// Hiçbir şey diske ve ağa yazılmaz (testler, deneme).
    let ephemeral: Bool

    // MARK: Kurulum

    @Published var welcomeSeen: Bool { didSet { defaults.set(welcomeSeen, forKey: Keys.welcomeSeen) } }
    @Published private(set) var step: Step
    @Published private(set) var platform: ConsoleKind
    @Published var platformChosen: Bool
    @Published private(set) var accountID: Data?
    @Published private(set) var console: PairedConsole?
    @Published private(set) var tv: PairedTV?
    @Published private(set) var tvKeySaved: Bool
    @Published var tvAppMissing = false
    /// TV uygulamasının bilinen sürümü (TV bağlanırken bildirdi ya da kurulumda okundu).
    @Published var tvAppSeenVersion: String?
    /// Telefonun kurabileceği TV paketlerinin sürümleri (önbellekteki ya da uygulamadaki; indirilmez).
    @Published var tvPackageVersions: [PairedTV.Brand: String] = [:]
    @Published private(set) var xboxConsole: XboxConsole?
    /// Saklı Microsoft jetonu var ve yenileme jetonu boş değil.
    @Published private(set) var xboxSignedIn: Bool
    @Published var coachTourDone: Bool { didSet { defaults.set(coachTourDone, forKey: Keys.coachTourDone) } }
    @Published var notifyDisconnect: Bool { didSet { defaults.set(notifyDisconnect, forKey: Keys.notifyDisconnect) } }
    @Published var notifyPackUpdates: Bool { didSet { defaults.set(notifyPackUpdates, forKey: Keys.notifyPackUpdates) } }
    @Published private(set) var hasLoginPasscode: Bool

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            if !ephemeral { settings.save(to: defaults) }
            if settings.targetLanguage != oldValue.targetLanguage { applyInterfaceLanguage() }
            if settings.style != oldValue.style, let link = tvLink {
                let style = settings.style.ninoStyle
                Task { await link.send(.style(style)) }
            }
            if settings.output != oldValue.output, let link = tvLink {
                let onTV = !settings.output.showsOnPhone
                Task { await link.setSubtitlesOnTV(onTV) }
            }
        }
    }

    // MARK: Çeviri

    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    @Published private(set) var isDemo = false
    @Published private(set) var demoLine: SampleLines.Line?
    @Published private(set) var link: Link = .disconnected(.stopped)
    @Published private(set) var lastFailure: Reason?
    @Published private(set) var stack = SubtitleStack()
    @Published private(set) var recentLines: [RecentLine] = []
    @Published private(set) var sessionLines = 0
    @Published private(set) var sessionPackLines = 0
    @Published private(set) var runningSince: Date?
    @Published private(set) var history = SubtitleHistory()
    @Published private(set) var tvConnected = false
    @Published private(set) var lastFrame: CGImage?
    @Published private(set) var downloadTotal: Int

    var lastSessionSeconds: Int? {
        let v = defaults.integer(forKey: Keys.lastSessionSeconds)
        return v > 0 ? v : nil
    }

    // Oturum parçaları
    private var session: RemotePlaySession?
    private var xboxSession: XboxSession?
    /// Microsoft hesabı ve Xbox jeton zinciri.
    let xboxAccount: XboxAccount
    /// Xbox ve Microsoft uçlarına giden istekler (testlerde sahte yanıtlar).
    let xboxWeb: XboxWeb
    /// Testler: gerçek WebRTC yerine.
    var xboxPeerOverride: XboxSession.PeerFactory?
    /// Testler: kısa bekleme süreleri.
    var xboxTiming = XboxSession.Timing()
    private var reading: ReadingSession?
    private var runTask: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?
    private var tvLink: TVLink?
    /// Bağlı TV uygulaması sayısı (eski 8787, web TV girişi, yeni Android TV).
    @Published private(set) var tvClients = 0
    private var output: LiveOutput?
    private var demoTask: Task<Void, Never>?
    private var stackTimer: Task<Void, Never>?
    private var userStopped = false
    /// Geçmişe yazılan satırlar (uzayan/geri gelen satır ikinci kez yazılmaz).
    private var recordedIDs: Set<Int> = []
    /// Ekrandan tanınan oyun (telefon oyunu kararı için; çeviri durunca unutulur).
    private var screenGame: String?

    /// PS5 bağlantısı koptuğunda (kullanıcı durdurmadan) çağrılır.
    var onConnectionLost: (() -> Void)?
    var keepScreenAwake: (Bool) -> Void = { _ in }
    /// Testler: çevirmen zincirinin yerine.
    var providerOverride: [TranslationProvider]?

    // MARK: Kuruluş

    init(store: SecureStore, defaults: UserDefaults = .standard, folders: AppFolders, ephemeral: Bool = false,
         preferredLanguages: [String] = Locale.preferredLanguages, xboxWeb: XboxWeb = URLSessionXboxWeb()) {
        self.store = store
        self.defaults = defaults
        self.folders = folders
        self.ephemeral = ephemeral
        welcomeSeen = defaults.bool(forKey: Keys.welcomeSeen)
        coachTourDone = defaults.bool(forKey: Keys.coachTourDone)
        notifyDisconnect = defaults.object(forKey: Keys.notifyDisconnect) as? Bool ?? true
        notifyPackUpdates = defaults.object(forKey: Keys.notifyPackUpdates) as? Bool ?? true
        downloadTotal = defaults.integer(forKey: Keys.downloadTotal)
        disabledPacks = defaults.stringArray(forKey: Keys.disabledPacks) ?? []
        settings = AppSettings.load(from: defaults, preferredLanguages: preferredLanguages)

        let accountID = store.load(Data.self, for: Keys.accountID)
        let console = store.load(PairedConsole.self, for: Keys.console)
        let tv = store.load(PairedTV.self, for: Keys.tv)
        let tvKey = store.load(String.self, for: Keys.tvKey)
        let xbox = store.load(XboxConsole.self, for: Keys.xboxConsole)
        let xboxToken = MicrosoftToken(stored: store.load(String.self, for: Keys.xboxUserToken))
        let savedPlatform = defaults.string(forKey: Keys.platform).flatMap(ConsoleKind.init(rawValue:))
        self.accountID = accountID
        self.console = console
        self.tv = tv
        tvKeySaved = tvKey != nil
        xboxConsole = xbox
        xboxSignedIn = xboxToken != nil
        self.xboxWeb = xboxWeb
        let tokenChanged = TokenRelay()
        xboxAccount = XboxAccount(web: xboxWeb, token: xboxToken, onToken: { tokenChanged.send($0) })
        platform = savedPlatform ?? .playstation
        platformChosen = savedPlatform != nil || accountID != nil || console != nil
        hasLoginPasscode = Self.validPasscode(store.load(String.self, for: Keys.loginPasscode)) != nil

        let complete = store.load(Bool.self, for: Keys.setupComplete) == true
        let skipped = defaults.bool(forKey: Keys.setupSkipped)
        let xboxReady = savedPlatform == .xbox && xbox != nil && xboxToken != nil
        if complete && (skipped || (accountID != nil && console != nil)) || (xboxReady && complete) {
            step = .done
        } else if skipped {
            step = .output
        } else {
            step = .welcome
        }
        if !ephemeral {
            history = SubtitleHistory.load(from: folders.historyFile)
            Task {
                await self.loadTVPackageVersions()
                await self.loadPacks()
                if await GamePackLibrary.update(folders: self.folders) { await self.reloadPacks() }
            }
        }
        applyInterfaceLanguage()
        tokenChanged.handler = { [weak self] token in
            Task { @MainActor in self?.storeXboxToken(token) }
        }
    }

    func applyInterfaceLanguage() {
        Loc.setLanguage(Languages.interfaceCode(for: settings.targetLanguage))
        if !ephemeral { Languages.rememberInterface(for: settings.targetLanguage, defaults: defaults) }
        objectWillChange.send()
    }

    // MARK: Kurulum adımları

    var isXbox: Bool { platform == .xbox }

    /// TV eşlenmiş (kayıt ve anahtarı var).
    var hasPairedTV: Bool { tv != nil && tvKeySaved }

    var consolePaired: Bool { isXbox ? (xboxConsole != nil && xboxSignedIn) : (console != nil && accountID != nil) }

    /// Altyazının gideceği yer hazır.
    var outputReady: Bool { settings.output.showsOnPhone || hasPairedTV }

    var canStart: Bool { consolePaired && outputReady }

    var canAdvance: Bool {
        switch step {
        case .welcome: true
        case .psnLogin: isXbox ? xboxSignedIn : accountID != nil
        case .console: isXbox ? xboxConsole != nil : console != nil
        case .output: hasPairedTV || settings.output.showsOnPhone
        case .done: false
        }
    }

    func advance() {
        guard canAdvance, let next = Step(rawValue: step.rawValue + 1) else { return }
        setStep(next)
    }

    func back() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        setStep(prev)
    }

    private func setStep(_ s: Step) {
        step = s
        if s == .done { store.save(true, for: Keys.setupComplete) }
    }

    /// Karşılamadan çıkış ("Atla" ya da "Başlayalım").
    func finishWelcome() {
        welcomeSeen = true
        if step == .welcome { setStep(.psnLogin) }
    }

    /// "Şimdilik Geç": altyazının yerine atlanır.
    func skipSetup() {
        defaults.set(true, forKey: Keys.setupSkipped)
        setStep(.output)
    }

    func choosePlatform(_ kind: ConsoleKind) {
        platform = kind
        platformChosen = true
        defaults.set(kind.rawValue, forKey: Keys.platform)
    }

    /// PSN girişinin yönlendirmesinden hesap kimliği.
    func completePSNLogin(redirect: URL) async throws {
        let id = try await PSNLogin.accountID(redirect: redirect)
        accountID = id
        store.save(id, for: Keys.accountID)
    }

    func pairConsole(address: String, info: ConsoleInfo?, pin: String) async throws {
        let paired = try await Consoles.pair(address: address, info: info, pin: pin, accountID: accountID)
        console = paired
        store.save(paired, for: Keys.console)
    }

    /// TV'yi seçer: TV uygulamasına bağlanmayı dener, kaydeder. Dönüş: TV uygulaması yanıt verdi mi.
    @discardableResult
    func pairTV(_ target: PairedTV, port: UInt16 = NinoLink.defaultPort) async -> Bool {
        let reachable = target.host.isEmpty ? true : await Displays.probe(host: target.host, port: port)
        tv = target
        store.save(target, for: Keys.tv)
        store.save("", for: Keys.tvKey)
        tvKeySaved = true
        tvAppMissing = !reachable
        if settings.output.showsOnPhone { settings.output = .tv }
        return reachable
    }

    func useOutput(_ target: SubtitleOutputTarget) { settings.output = target }

    func saveLoginPasscode(_ text: String) -> Bool {
        guard let code = Self.validPasscode(text) else { return false }
        store.save(code, for: Keys.loginPasscode)
        hasLoginPasscode = true
        return true
    }

    func removeLoginPasscode() {
        store.remove(Keys.loginPasscode)
        hasLoginPasscode = false
    }

    static func validPasscode(_ text: String?) -> String? {
        guard let t = text?.trimmingCharacters(in: .whitespaces), t.count == 4,
              t.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return t
    }

    /// Kurulumu sıfırlar (karşılama yeniden gösterilmez).
    func resetSetup() {
        stop()
        for k in [Keys.accountID, Keys.console, Keys.tv, Keys.tvKey, Keys.setupComplete, Keys.loginPasscode,
                  Keys.xboxConsole, Keys.xboxUserToken] { store.remove(k) }
        xboxSignedIn = false
        let account = xboxAccount
        Task { await account.signOut() }
        defaults.removeObject(forKey: Keys.platform)
        defaults.removeObject(forKey: Keys.setupSkipped)
        accountID = nil
        console = nil
        tv = nil
        tvKeySaved = false
        xboxConsole = nil
        hasLoginPasscode = false
        platform = .playstation
        platformChosen = false
        tvAppMissing = false
        step = .welcome
    }

    // MARK: Xbox girişi ve seçimi

    /// Microsoft'tan cihaz kodu ister.
    func xboxRequestCode() async throws -> DeviceCodeChallenge {
        try await xboxAccount.requestCode()
    }

    /// Kullanıcı kodu onaylayana kadar bekler; jeton saklanır.
    func xboxWaitForApproval(_ code: DeviceCodeChallenge) async throws {
        let token = try await xboxAccount.waitForApproval(code)
        storeXboxToken(token)
    }

    /// Hesaptaki Xbox'lar.
    func xboxConsoles() async throws -> [XboxConsole] {
        try await XboxCloud(account: xboxAccount, web: xboxWeb).consoles()
    }

    func chooseXbox(_ console: XboxConsole) {
        xboxConsole = console
        store.save(console, for: Keys.xboxConsole)
    }

    /// Microsoft çıkışı: jeton silinir (seçili Xbox kalır).
    func xboxSignOut() {
        storeXboxToken(nil)
        let account = xboxAccount
        Task { await account.signOut() }
    }

    private func storeXboxToken(_ token: MicrosoftToken?) {
        if let token {
            store.save(token.stored, for: Keys.xboxUserToken)
        } else {
            store.remove(Keys.xboxUserToken)
        }
        xboxSignedIn = token != nil
    }

    // MARK: Demo

    func startDemo() {
        guard !isRunning, !isStarting, !isDemo else { return }
        isDemo = true
        demoLine = nil
        keepScreenAwake(true)
        demoTask = Task { [weak self] in
            var index = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard let self, !Task.isCancelled else { return }
                self.demoLine = SampleLines.line(index, for: self.settings.targetLanguage)
                index += 1
                try? await Task.sleep(for: .milliseconds(2800))
                guard !Task.isCancelled else { return }
                self.demoLine = nil
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }

    func stopDemo() {
        guard isDemo else { return }
        demoTask?.cancel()
        demoTask = nil
        isDemo = false
        demoLine = nil
        keepScreenAwake(false)
    }

    // MARK: Başlat / durdur

    /// Çeviriyi başlatır: PS5'e Remote Play ile bağlanır, kareleri okur, çevirir; altyazıyı TV'ye ve/veya telefona verir.
    func start() async {
        stopDemo()
        guard !isRunning, !isStarting, canStart else { return }
        let ps5 = console, xbox = xboxConsole
        guard isXbox ? xbox != nil : ps5 != nil else { return }
        isStarting = true
        defer { isStarting = false }
        if notifyDisconnect && !ephemeral { ConnectionAlert.requestPermission() }
        userStopped = false
        lastFailure = nil
        link = .connecting
        let output = LiveOutput { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        self.output = output
        guard let reading = try? makeReading(output: output) else {
            link = .disconnected(.other("engine"))
            return
        }
        self.reading = reading
        await openTVLink(output: output)
        await applyPhoneGame()
        if isXbox, let xbox {
            openXboxSession(xbox, reading: reading)
        } else if let ps5 {
            openSession(console: ps5, reading: reading)
        }
        isRunning = true
        AppDiagnosis.shared.note("session.start")
        runningSince = Date()
        recentLines = []
        sessionLines = 0
        sessionPackLines = 0
        keepScreenAwake(true)
    }

    /// Kare kaynağıyla (PS5 olmadan) çalıştırır: testler ve deneme.
    func start(with source: FrameSource, tv tvOutput: SubtitleOutput? = nil, textReader: GameReading.TextReader? = nil) async -> Task<Void, Never>? {
        guard !isRunning else { return nil }
        let output = LiveOutput(tv: tvOutput) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        self.output = output
        guard let reading = try? makeReading(output: output, textReader: textReader) else { return nil }
        self.reading = reading
        await applyPhoneGame()
        isRunning = true
        link = .streaming
        runningSince = Date()
        let task = Task { await reading.run(source) }
        runTask = task
        return task
    }

    func stop() {
        stopDemo()
        guard isRunning || isStarting else { return }
        userStopped = true
        AppDiagnosis.shared.note("session.stop")
        if let since = runningSince {
            let seconds = Int(Date().timeIntervalSince(since))
            defaults.set(seconds, forKey: Keys.lastSessionSeconds)
            AppTelemetry.record(.session(duration: seconds, game: nil, source: xboxSession != nil ? .xbox : .remoteplay,
                                         lines: sessionLines))
        }
        runningSince = nil
        playingPack = nil
        // Önce oturum (arka planda; kapanırken iş parçacığını bekler), sonra görevler.
        let session = session
        self.session = nil
        Task.detached { session?.stop() }
        xboxSession?.stop()
        xboxSession = nil
        runTask?.cancel()
        eventsTask?.cancel()
        let closing = tvLink, ending = reading
        tvLink = nil
        reading = nil
        // Önce ekran öğeleri kalkar (TV'ye screen-clear), sonra TV yolu kapanır.
        Task {
            await ending?.stop()
            await closing?.stop()
        }
        screenGame = nil
        recordedIDs = []
        tvConnected = false
        tvClients = 0
        output = nil
        isRunning = false
        lastFailure = nil
        link = .disconnected(.stopped)
        stack.removeAll()
        lastFrame = nil
        keepScreenAwake(false)
        if !ephemeral { saveHistory() }
    }

    /// Uygulama öne gelince: koptuysa yeniden bağlanır.
    func becameActive(afterBackground: Bool) {
        guard isRunning, afterBackground || link != .streaming, let reading else { return }
        if let xboxSession {
            // Bağlanmakta olan Xbox oturumu bozulmaz; yalnız arka plandan dönüşte ya da kopukken yeniden açılır.
            if case .disconnected = link { xboxSession.reconnectNow() } else if afterBackground { xboxSession.reconnectNow() }
        } else if let console {
            let old = session
            Task.detached { old?.stop() }
            openSession(console: console, reading: reading)
        } else {
            return
        }
        // Arka planda dinleyen sunucular durdurulmuş olabilir: TV yolu baştan kurulur (tek gönderici kalır).
        if afterBackground, let output {
            let old = tvLink
            tvLink = nil
            output.setTV(nil)
            Task {
                await old?.stop()
                await self.openTVLink(output: output)
                await self.reading?.layer?.resend()
            }
        }
    }

    func enteredBackground() {
        if !ephemeral { saveHistory() }
    }

    private func makeReading(output: SubtitleOutput, textReader: GameReading.TextReader? = nil) throws -> ReadingSession {
        var core = NinoSettings()
        core.translation.providers = TranslationEngines.configurations(for: settings, store: store)
        let secrets = TranslationEngines.secrets(for: settings, store: store)
        let directories = NinoDirectories(root: ephemeral ? FileManager.default.temporaryDirectory.appendingPathComponent("nino-\(UUID())") : folders.support)
        try directories.prepare()
        let providers = (providerOverride ?? core.makeProviders(secrets: secrets, onDevice: makeOnDeviceTranslationProvider()))
            .map { TimedProvider(base: $0) as TranslationProvider }
        let chain = ProviderChain(providers: providers, timeout: .seconds(3))
        let lookup: PackLookup? = settings.packsActive ? PackLookup(library: packs.enabled(excluding: disabledPacks)) { [weak self] title in
            Task { @MainActor in self?.packPlayed(title) }
        } : nil
        activeLookup = lookup
        let target = Languages.normalized(settings.targetLanguage)
        let translator = Translator(cache: TranslationCache(fileURL: directories.translationCacheFile), chain: chain, pack: lookup,
                                    sourceLanguage: settings.sourceLanguage, targetLanguage: target)
        let clock = GameReading.SystemClock()
        let base = textReader ?? GameReading.GuardedTextReader(primary: GameReading.VisionTextReader(), fallback: nil,
                                                               cpu: GameReading.CPUTextReader(), clock: clock)
        let reader = WatchedTextReader(base: base)
        let packText: (@Sendable (String) -> String?)? = lookup.map { l in { l.lookup($0) } }
        let elements = ElementTranslation(translator: translator, packLookup: packText, targetLanguage: target)
        let phone = GameReading.PhoneWatcher(textReader: textReader ?? GameReading.CPUTextReader(), clock: clock,
                                             memory: .init(directory: directories.root, language: target),
                                             translator: elements, rectangles: GameReading.VisionRectangleDetector())
        let decision = phoneDecision()
        var cfg = GameReading.Reader.Configuration()
        let r = settings.region
        cfg.region = GameReading.Region(GameReading.Box(left: r.left, top: r.top, right: r.right, bottom: r.bottom))
        cfg.fastDetection = settings.fastSubtitleDetection
        GameReading.GTA6Rules.apply(decision.on, packGame: packGameKey, to: &cfg)
        let gameReader = GameReading.Reader(textReader: reader, clock: clock, configuration: cfg, phone: phone,
                                            isInPack: { lookup?.lookup($0) != nil })
        var layerOptions = ScreenLayer.Options()
        layerOptions.cornersEnabled = settings.translateCorners && settings.sourceLanguage.hasPrefix("en")
        let layer = ScreenLayer(reader: gameReader, phone: phone, translator: elements, clock: clock, options: layerOptions,
                                send: { [weak self] event in await self?.sendToTV(event) },
                                onEvent: { [weak self] e in Task { @MainActor in self?.handle(e) } })
        var options = ReadingSession.Options()
        options.showSpeakerNames = settings.showSpeakerNames
        options.position = r.bottom < 0.5 ? .top : .bottom
        options.packLookup = packText
        return ReadingSession(reader: gameReader, translator: translator, output: output, clock: clock, options: options,
                              layer: layer, onEvent: { [weak self] e in Task { @MainActor in self?.handle(e) } })
    }

    // MARK: Telefon oyunu (GTA 6; NinoCore telefon-harita.md §1)

    /// Oyunun nereden bilindiği: ekrandan tanındıysa kesin, yalnız paketten tahminse tahmin.
    var phoneKnowledge: GameReading.PhoneGame.Knowledge {
        if let screenGame { return .certain(screenGame) }
        if let playingPack { return .packGuess(playingPack) }
        return .unknown
    }

    func phoneDecision() -> GameReading.PhoneGame.Decision {
        GameReading.PhoneGame.decide(cornersEnabled: settings.translateCorners, sourceLanguage: settings.sourceLanguage,
                                     targetLanguage: Languages.normalized(settings.targetLanguage), game: phoneKnowledge,
                                     lastGameWasPoolPriority: defaults.bool(forKey: Keys.lastGamePoolFirst))
    }

    /// Paketteki oyunun yer anahtarı için adı (bilinmiyorsa nil).
    private var packGameKey: String? { screenGame ?? playingPack }

    /// Telefon oyunu kararını verir ve okuyucuya, telefon izleyicisine, harita kartına uygular.
    func applyPhoneGame() async {
        let decision = phoneDecision()
        if let remember = decision.rememberPoolPriority { defaults.set(remember, forKey: Keys.lastGamePoolFirst) }
        guard let reading else { return }
        await reading.reader.setPhoneGame(decision.on, packGame: packGameKey)
        await reading.layer?.setReportedGame(nil)
        await reading.layer?.setPhoneGame(decision.on)
    }

    /// Telefon oyunu açık mı (testler).
    func phoneGameActive() async -> Bool { await reading?.layer?.phoneGame ?? false }

    /// Köşe turunun son menü aramasında okunan satırlar (testler).
    func lastMenuSearchLines() async -> [String] { await reading?.reader.lastMenuSearchLines.map(\.text) ?? [] }

    private func packPlayed(_ title: String) {
        guard playingPack != title else { return }
        playingPack = title
        Task { await applyPhoneGame() }
    }

    /// Testler: TV'ye giden ekran öğesi mesajlarını da görür.
    var screenSink: (@Sendable (NinoEvent) -> Void)?

    private func sendToTV(_ event: NinoEvent) async {
        screenSink?(event)
        await tvLink?.send(event)
    }

    // MARK: Cihaz içi çeviri

    enum OnDeviceStatus: Equatable { case ready, needsDownload, unsupported, unavailable }

    /// Apple'ın ücretsiz çevirisinin bu dil için durumu (iOS 26 öncesinde yok).
    @Published private(set) var onDeviceStatus: OnDeviceStatus = .ready

    func refreshTranslationStatus() async {
        guard #available(iOS 26.0, *) else { onDeviceStatus = .unavailable; return }
        let status = await LanguageAvailability().status(from: Locale.Language(identifier: settings.sourceLanguage),
                                                         to: Locale.Language(identifier: Languages.normalized(settings.targetLanguage)))
        switch status {
        case .installed: onDeviceStatus = .ready
        case .supported: onDeviceStatus = .needsDownload
        default: onDeviceStatus = .unsupported
        }
    }

    /// Anahtarı kayıtlı bir çevrimiçi motor açık mı.
    var onlineEngineActive: Bool {
        settings.onlineTranslation && (settings.onlineEngine == .local || TranslationEngines.key(settings.onlineEngine, store: store) != nil)
    }

    // MARK: Oyun paketleri

    @Published private(set) var packs = GamePackLibrary()
    @Published private(set) var playingPack: String?
    @Published var disabledPacks: [String] = [] {
        didSet { defaults.set(disabledPacks.sorted(), forKey: Keys.disabledPacks) }
    }

    /// Paketleri arka planda okur.
    func loadPacks() async {
        guard !packsLoading else { return }
        packsLoading = true
        defer { packsLoading = false }
        let folders = folders
        let lib = await Task.detached(priority: .utility) { GamePackLibrary.load(folders: folders) }.value
        packs = lib
        activeLookup?.setLibrary(lib.enabled(excluding: disabledPacks))
    }

    /// Paketleri yeniden okur (sunucudan yeni paket inince).
    func reloadPacks() async {
        let folders = folders
        let lib = await Task.detached(priority: .utility) { GamePackLibrary.load(folders: folders) }.value
        packs = lib
        activeLookup?.setLibrary(lib.enabled(excluding: disabledPacks))
    }

    /// "Paketleri şimdi güncelle".
    func updatePacksNow() async {
        if await GamePackLibrary.update(folders: folders, force: true) { await reloadPacks() }
    }

    func togglePack(_ id: String) {
        if let i = disabledPacks.firstIndex(of: id) { disabledPacks.remove(at: i) } else { disabledPacks.append(id) }
        activeLookup?.setLibrary(packs.enabled(excluding: disabledPacks))
    }

    private var packsLoading = false
    private var activeLookup: PackLookup?

    /// Oturum bekçisi: bağlanır, koparsa artan aralıkla (2, 4, 8, 16, sonra 30 sn) yeniden bağlanır. 8 sn hiç kare
    /// gelmezse oturumu yeniler; art arda 3 oturumda hiç kare gelmezse "görüntü yok" der ve durur. Uyuyan PS5 uyandırılır.
    private func openSession(console: PairedConsole, reading: ReadingSession) {
        guard let registered = Consoles.registered(console) else {
            link = .disconnected(.refused)
            lastFailure = .refused
            return
        }
        runTask?.cancel()
        eventsTask?.cancel()
        let host = console.host
        runTask = Task { [weak self] in
            var delay: TimeInterval = 2
            var silentSessions = 0
            var retry = 0
            while !Task.isCancelled {
                guard let self else { return }
                let session = RemotePlaySession(address: host, console: registered)
                self.session = session
                self.sessionAttempts += 1
                self.link = .connecting
                let source = FrameTap(session) { [weak self] frame in
                    AppDiagnosis.shared.frame(frame.image)
                    Task { @MainActor in self?.lastFrame = frame.image; self?.lastFrameAt = Date() }
                }
                let opened = Date()
                self.lastFrameAt = nil
                self.connectedAt = nil
                let quit = LatestBox<String>()
                let events = Task { @MainActor [weak self] in
                    for await event in session.events() {
                        switch event {
                        case .connected:
                            AppTelemetry.record(.ps5Connect(result: "ok", ms: Int(Date().timeIntervalSince(opened) * 1000), via: .lan))
                            AppDiagnosis.shared.note("ps5.connect")
                            self?.connectedAt = Date()
                            self?.link = .streaming
                            self?.lastFailure = nil
                        case let .quit(reason):
                            quit.set(reason)
                        case let .loginPINRequested(incorrect):
                            guard let self else { break }
                            if incorrect {
                                self.pinFailure = .loginPasscodeIncorrect
                                Task.detached { session.stop() }
                            } else if let pin = AppModel.validPasscode(self.store.load(String.self, for: Keys.loginPasscode)) {
                                try? session.sendLoginPIN(pin)
                            } else {
                                self.pinFailure = .loginPasscode
                                Task.detached { session.stop() }
                            }
                        case .log:
                            break
                        }
                    }
                }
                let watchdog = Task { @MainActor [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(2))
                        guard let self, self.link == .streaming else { continue }
                        let since = self.lastFrameAt ?? self.connectedAt ?? Date()
                        if Date().timeIntervalSince(since) > 8 {
                            self.watchdogFired = true
                            return
                        }
                    }
                }
                // Oturumun bitişi: kare akışı biter ya da kapanma olayı gelir. Kütüphane kapanırken kendi kilidinde
                // takılabildiği için (NinoRemotePlay'de bildirilen hata) akışın bitmesi beklenmez; kapanma olayı
                // gelince okuma durdurulur, takılan oturuma bir daha dokunulmaz.
                let runner = Task { await reading.run(source) }
                let runnerDone = LatestBox<Bool>()
                Task { await runner.value; runnerDone.set(true) }
                while !Task.isCancelled, runnerDone.get() == nil, quit.get() == nil, !self.watchdogFired {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                runner.cancel()
                watchdog.cancel()
                events.cancel()
                if quit.get() == nil || self.watchdogFired {
                    Task.detached { session.stop() }
                }
                self.watchdogFired = false
                if Task.isCancelled || self.userStopped { return }

                let gotFrames = self.lastFrameAt != nil
                silentSessions = gotFrames ? 0 : silentSessions + 1
                var reason = quit.get().map { Self.reason(fromQuit: $0, host: host) } ?? .network
                if let pin = self.pinFailure { reason = pin; self.pinFailure = nil }
                if silentSessions >= 3, self.link == .streaming { reason = .noPicture }
                let wasStreaming = self.link == .streaming
                self.link = .disconnected(reason)
                self.stack.removeAll()
                Task { await reading.reset() }
                let hub = self.tvLink?.hub
                Task { try? await hub?.clear(id: nil) }
                if case .other = reason {} else if reason != .stopped { self.lastFailure = reason }
                if wasStreaming, reason != .stopped {
                    AppDiagnosis.shared.note("ps5.drop", detail: reason.diagCause)
                    AppTelemetry.record(.ps5Drop(reason.code, after: Int(Date().timeIntervalSince(self.connectedAt ?? opened))))
                    if self.notifyDisconnect { self.onConnectionLost?() }
                } else if !wasStreaming {
                    retry += 1
                    AppDiagnosis.shared.note("ps5.retry", retry)
                    AppTelemetry.record(.ps5Connect(result: reason.code, ms: Int(Date().timeIntervalSince(opened) * 1000), via: .lan))
                }
                if Self.isPermanent(reason) { return }
                if reason == .asleep { try? RemotePlaySession.wake(address: host, console: registered) }
                if Date().timeIntervalSince(opened) >= 60 && gotFrames { delay = 2 }
                if reason == .inUse { delay = max(delay, 8) }
                try? await Task.sleep(for: .seconds(delay))
                delay = min(30, delay * 2)
            }
        }
    }

    /// Xbox ev yayını: oturum kendi yeniden denemesini yapar (5/15/45 sn, sonra durur); model yalnız durumu yazar.
    /// Kareler bütün yeniden bağlanmalar boyunca aynı akıştan gelir, okuma hattı bir kez kurulur.
    private func openXboxSession(_ xbox: XboxConsole, reading: ReadingSession) {
        runTask?.cancel()
        eventsTask?.cancel()
        let lowResolution = settings.xboxLowResolution
        let peerFactory: XboxSession.PeerFactory = xboxPeerOverride ?? { playAudio, sink in
            try WebRTCXboxPeer(playAudio: playAudio, lowResolution: lowResolution, log: XboxLog.write, sink: sink)
        }
        let session = XboxSession(console: xbox, cloud: XboxCloud(account: xboxAccount, web: xboxWeb),
                                  playAudio: settings.xboxAudioOnDevice, timing: xboxTiming, log: XboxLog.write,
                                  makePeer: peerFactory)
        xboxSession = session
        sessionAttempts += 1
        link = .connecting
        let source = FrameTap(session) { [weak self] frame in
            AppDiagnosis.shared.frame(frame.image)
            Task { @MainActor in self?.lastFrame = frame.image; self?.lastFrameAt = Date() }
        }
        runTask = Task { await reading.run(source) }
        eventsTask = Task { [weak self] in
            var opened = Date()
            for await status in session.statuses() {
                guard let self, !Task.isCancelled, self.xboxSession === session else { return }
                if status == .connecting { opened = Date() }
                self.apply(status, since: opened)
            }
        }
        session.start()
    }

    private func apply(_ status: XboxSession.Status, since opened: Date) {
        let wasStreaming = link == .streaming
        switch status {
        case .connecting:
            link = .connecting
        case .streaming:
            connectedAt = Date()
            link = .streaming
            lastFailure = nil
            AppDiagnosis.shared.note("ps5.connect")
            AppTelemetry.record(.ps5Connect(result: "ok", ms: Int(Date().timeIntervalSince(opened) * 1000), via: .xbox))
        case let .lost(problem, willRetry, _):
            let reason = Reason.other(XboxText.session(problem, willRetry: willRetry))
            link = .disconnected(reason)
            lastFailure = reason
            stack.removeAll()
            let hub = tvLink?.hub
            Task { try? await hub?.clear(id: nil) }
            if wasStreaming {
                AppDiagnosis.shared.note("ps5.drop")
                AppTelemetry.record(.ps5Drop(problem.rawValue, after: Int(Date().timeIntervalSince(connectedAt ?? opened))))
                if notifyDisconnect { onConnectionLost?() }
            } else {
                AppTelemetry.record(.ps5Connect(result: problem.rawValue, ms: Int(Date().timeIntervalSince(opened) * 1000), via: .xbox))
            }
        }
    }

    /// Son karenin geldiği ve oturumun bağlandığı an (görüntü bekçisi için).
    private var lastFrameAt: Date?
    private var connectedAt: Date?
    private var watchdogFired = false
    private var pinFailure: Reason?
    /// Bu çeviride kaç kez oturum açıldı (testler).
    private(set) var sessionAttempts = 0

    /// Remote Play kütüphanesinin kapanma nedeni metninden (bkz. kütüphanenin neden metinleri).
    static func reason(fromQuit text: String, host: String) -> Reason {
        let t = text.lowercased()
        if t == "stopped" { return .stopped }
        if t.contains("already in use") { return .inUse }
        if t.contains("registration") { return .refused }
        if t.contains("server shut down") { return .asleep }
        if t.contains("ctrl failed to connect") || t.contains("connection refused") { return .notFound(host) }
        if t.contains("remote has disconnected") { return .network }
        if t.contains("crashed") || t.contains("session request") { return .rejected(code: nil) }
        return .other(text)
    }

    /// Yeniden denenmeyen nedenler: oturum durur, model "çalışıyor" kalıp nedeni gösterir.
    static func isPermanent(_ r: Reason) -> Bool {
        switch r {
        case .refused, .noPicture, .loginPasscode, .loginPasscodeIncorrect: true
        default: false
        }
    }

    /// TV yolunu açar: sunucular, kayıtlı TV'ye bağlantı, görünüm ve "başladı" olayı.
    private func openTVLink(output: LiveOutput) async {
        let link = TVLink()
        link.onChange = { [weak self] count in
            Task { @MainActor in
                if let self, self.isRunning, count != self.tvClients {
                    AppDiagnosis.shared.note(count > self.tvClients ? "tv.connect" : "tv.drop", count, detail: "closed")
                }
                self?.tvClients = count
                self?.tvConnected = count > 0
            }
        }
        link.onTVAppVersion = { [weak self] version, host in
            Task { @MainActor in self?.tvAppReported(version: version, host: host) }
        }
        tvLink = link
        await link.start(tv: settings.output.showsOnPhone ? nil : tv, deviceName: "iPhone", version: AppInfo.version)
        await link.setSubtitlesOnTV(!settings.output.showsOnPhone)
        await link.send(.style(settings.style.ninoStyle))
        await link.send(.started)
        output.setTV(link.hub)
    }

    private func handle(_ e: ReadingEvent) {
        switch e {
        case let .shown(id, text, source, fromPack, latency):
            if let latency { AppDiagnosis.shared.translated(totalMs: latency) }
            guard !recordedIDs.contains(id) else { return }
            recordedIDs.insert(id)
            if recordedIDs.count > 200 { recordedIDs = Set(recordedIDs.sorted().suffix(100)) }
            record(id: id, source: source, translation: text, fromPack: fromPack)
        case .read, .cleared, .ocr, .stuck:
            break
        }
    }

    private func handle(_ e: ScreenLayerEvent) {
        switch e {
        case let .screenGame(name):
            guard screenGame != name else { return }
            screenGame = name
            Task { await applyPhoneGame() }
        case .elements:
            break
        }
    }

    private func record(id: Int, source: String, translation: String, fromPack: Bool) {
        sessionLines += 1
        if fromPack { sessionPackLines += 1 }
        recentLines.insert(RecentLine(id: id, source: source, translation: translation, fromPack: fromPack), at: 0)
        if recentLines.count > 30 { recentLines.removeLast(recentLines.count - 30) }
        history.add(source: source, translation: translation, origin: fromPack ? .pack : .engine)
    }

    private func handle(_ event: LiveOutput.Event) {
        switch event {
        case let .show(p):
            guard settings.output.showsOnPhone || !isRunning else { return }
            stack.show(id: p.id, text: p.text, source: p.source)
        case let .clear(id):
            stack.clear(id: id)
        case .tvFailed:
            break
        }
        scheduleStackTick()
    }

    private func scheduleStackTick() {
        stackTimer?.cancel()
        guard let next = stack.nextChange() else { return }
        stackTimer = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(max(0, next.timeIntervalSinceNow) * 1000) + 20))
            guard let self, !Task.isCancelled else { return }
            self.stack.tick()
            self.scheduleStackTick()
        }
    }

    /// "Deneme Altyazısı Gönder": 8 sn'lik deneme satırı TV'ye ve telefona.
    func sendTestSubtitle() {
        let text = L("tv.test.text")
        let payload = ShowPayload(id: Int.max - 1, text: text, durationMs: 8000)
        stack.show(id: payload.id, text: text, source: nil)
        stack.clear(id: payload.id, now: Date().addingTimeInterval(8 - SubtitleStack.readingTime(text)))
        scheduleStackTick()
        guard !settings.output.showsOnPhone else { return }
        if let link = tvLink {
            Task { await link.send(.style(settings.style.ninoStyle)); try? await link.hub.show(payload) }
            return
        }
        // Çeviri kapalıyken: TV yolu kısa süreliğine açılır (eski TV'lerin telefonu bulması birkaç saniye sürer).
        let link = TVLink()
        let tv = tv, style = settings.style.ninoStyle
        Task {
            await link.start(tv: tv, deviceName: "iPhone", version: AppInfo.version)
            await link.send(.style(style))
            try? await link.hub.show(payload)
            try? await Task.sleep(for: .seconds(12))
            await link.stop()
        }
    }

    /// Çevrimiçi motor anahtarını dener; çalışırsa kaydeder ve o motora geçer.
    func saveKey(_ key: String, for engine: TranslationEngine) async -> Bool {
        guard !key.isEmpty else { return false }
        guard await TranslationEngines.check(key: key, engine: engine, settings: settings) else { return false }
        store.save(key, for: TranslationEngines.keyAccount(engine))
        settings.onlineTranslation = true
        settings.onlineEngine = engine
        objectWillChange.send()
        return true
    }

    func removeKey(_ engine: TranslationEngine) {
        store.remove(TranslationEngines.keyAccount(engine))
        if settings.onlineEngine == engine { settings.onlineTranslation = false }
        objectWillChange.send()
    }

    func clearHistory() {
        history.removeAll()
        if !ephemeral { saveHistory() }
    }

    private func saveHistory() {
        let data = history.data()
        let url = folders.historyFile
        DispatchQueue.global(qos: .utility).async { try? data?.write(to: url, options: .atomic) }
    }

    // MARK: Ekranın gösterdikleri

    /// Konsolun adı ("PS5-002"; yoksa "PS5"/"Xbox").
    var consoleName: String {
        if isXbox { return (xboxConsole?.name).flatMap { $0.isEmpty ? nil : $0 } ?? "Xbox" }
        return (console?.name).flatMap { $0.isEmpty ? nil : $0 } ?? "PS5"
    }

    /// Bağlantı sorunu metni: çalışırken, akmıyorsa ve son neden varsa.
    var problemText: String? {
        guard isRunning, !isDemo, link != .streaming, let lastFailure else { return nil }
        return lastFailure.message ?? (isXbox ? lastFailure.detail : nil)
    }

    /// Tam ekranın sol üst durum metni.
    var consoleStatusText: String {
        switch link {
        case .streaming: L("status.connected")
        case .connecting: L("status.connecting")
        case let .disconnected(r):
            isRunning ? (r.message ?? (isXbox ? r.detail : nil) ?? L("status.reconnecting")) : L("status.disconnected")
        }
    }

    /// Sahnede şu an görünen satır.
    var currentLine: String? {
        if isDemo { return demoLine?.translation }
        if let last = stack.last?.text, !last.isEmpty { return last }
        return recentLines.first?.translation
    }
}

/// Microsoft jetonu değişince (actor içinden) modele haber veren kutu.
final class TokenRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [MicrosoftToken?] = []
    private var target: ((MicrosoftToken?) -> Void)?

    /// Bağlanmadan önce gelenler sırayla iletilir.
    var handler: ((MicrosoftToken?) -> Void)? {
        get { lock.withLock { target } }
        set {
            let waiting = lock.withLock { () -> [MicrosoftToken?] in
                target = newValue
                defer { queued = [] }
                return queued
            }
            waiting.forEach { newValue?($0) }
        }
    }

    func send(_ token: MicrosoftToken?) {
        let handler = lock.withLock { () -> ((MicrosoftToken?) -> Void)? in
            if target == nil { queued.append(token) }
            return target
        }
        handler?(token)
    }
}
