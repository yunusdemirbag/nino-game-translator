// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import Foundation
import NinoCore

/// Altyazı sunucusu (Output tarafı). TV kurulumu yalnız bu arayüzü görür.
public protocol TVSubtitleServer: Sendable {
    /// Kapalıysa açar.
    func ensureRunning() async throws
    /// TV uygulamasının bağlandığı port (`server` parametresi).
    func port() async -> UInt16
    /// Şu an bağlı TV uygulamalarının sürümleri (sürüm bildirmeyen için nil).
    func connectedTVApps() async -> [String?]
    /// Altyazının gittiği çıkış (NinoCore `DisplayHub`).
    var output: any DisplayOutput { get }
    /// En son görülen altyazının yeri (deneme altyazısı oraya konur); bilinmiyorsa nil.
    func lastSubtitleBox() async -> NinoBox?
}

/// TV kurulumunun bütün bağımlılıkları.
public struct TVSetupEnvironment: Sendable {
    public var http: TVHTTP
    public var ports: TVPortProbe
    public var ssdp: SSDPTransport
    public var sockets: TVWebSocketConnecting
    public var network: NetworkInterfaceListing
    public var processes: TVProcessRunning
    public var clock: TVClock
    public var log: TVInstallLog
    public var records: SecureRecords
    public var packages: TVAppPackages
    /// Gömülü yardımcının yeri (yoksa Samsung kurulumu gizli, Android kurulumu "kurulamadı").
    public var helperExecutable: URL?
    public var folder: DataFolder
    public var server: TVSubtitleServer
    /// LG süre uzatmasının anı (TV adresine göre).
    public var defaults: UserDefaults
    public var appStoreBuild: Bool
    /// Adresi tarayıcıda öne getirerek açar.
    public var openURL: @Sendable (URL) -> Bool
    public var timing: Timing

    public struct Timing: Sendable {
        public var poll: TimeInterval = 3
        public var lgKeepAlive: TimeInterval = 5
        public var samsungKeepAlive: TimeInterval = 30
        public var keeperTick: TimeInterval = 5
        public var testWait: TimeInterval = 10
        public var testPoll: TimeInterval = 0.5
        public var discovery = TVDiscovery.Timing()
        public var lg = LGSSAPClient.Timing()
        public var lgDeveloper = LGDeveloperMode.Timing()
        public var samsung = SamsungRemote.Timing()
        public init() {}
    }

    public init(http: TVHTTP, ports: TVPortProbe, ssdp: SSDPTransport, sockets: TVWebSocketConnecting,
                network: NetworkInterfaceListing, processes: TVProcessRunning, clock: TVClock, log: TVInstallLog,
                records: SecureRecords, packages: TVAppPackages, helperExecutable: URL?, folder: DataFolder,
                server: TVSubtitleServer, defaults: UserDefaults, appStoreBuild: Bool,
                openURL: @escaping @Sendable (URL) -> Bool, timing: Timing = Timing()) {
        self.http = http
        self.ports = ports
        self.ssdp = ssdp
        self.sockets = sockets
        self.network = network
        self.processes = processes
        self.clock = clock
        self.log = log
        self.records = records
        self.packages = packages
        self.helperExecutable = helperExecutable
        self.folder = folder
        self.server = server
        self.defaults = defaults
        self.appStoreBuild = appStoreBuild
        self.openURL = openURL
        self.timing = timing
    }

    /// Uygulamanın gerçek kapıları.
    public static func live(records: SecureRecords, folder: DataFolder, server: TVSubtitleServer,
                            bundle: Bundle = .main, defaults: UserDefaults = .standard) -> TVSetupEnvironment {
        // Yardımcı uygulamanın içinde çalışır (Helper/InProcessTVHelper); ayrı ikili dosya gerekmez.
        // Samsung kurulumu orada yoksa (supportsSamsung) .wgt yok sayılır; .wgt yoksa da Samsung kartı gizli kalır.
        let processes = InProcessHelperProcessRunner(fallback: FoundationProcessRunner())
        var packages = TVAppPackages.scan(folder: bundle.resourceURL?.appendingPathComponent("tv-app", isDirectory: true))
        if !InProcessTVHelper.supportsSamsung { packages.samsung = nil }
        return TVSetupEnvironment(
            http: URLSessionTVHTTP(), ports: NWPortProbe(), ssdp: BSDSSDPTransport(), sockets: URLSessionTVWebSockets(),
            network: SystemNetworkInterfaces(), processes: processes, clock: SystemTVClock(),
            log: TVInstallLog.file(folder.tvInstallLog), records: records, packages: packages,
            helperExecutable: InProcessTVHelper.executableURL, folder: folder, server: server, defaults: defaults,
            appStoreBuild: bundle.appStoreReceiptURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
            openURL: { url in
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.open(url, configuration: config)
                return true
            })
    }
}

/// TV adımının ve TV uygulamasının iş mantığı (tv-kurulumu.md, kurulum.md §7–§8).
///
/// `AppState`'e yazar; motor (`AppEngine`) eylemleri buraya iletir.
@MainActor
public final class TVSetupController {
    public private(set) weak var state: AppState?
    let env: TVSetupEnvironment
    let discovery: TVDiscovery
    let lgDev: LGDeveloperMode
    let helper: TVHelperClient

    private var searchTask: Task<Void, Never>?
    private var pairTask: Task<Void, Never>?
    private var appTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var keeperTask: Task<Void, Never>?
    private var typeCodeTask: Task<Void, Never>?
    private var testTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    /// LG eşleşmede/denetimde uygulama açılabildi mi (nil: bilinmiyor).
    private var lgAppLaunched: Bool?
    private var lgKeeper: LGSSAPClient?
    private var lastSamsungKeepAlive: Date?
    private var readdress = TVReaddressPolicy()
    /// Samsung'da "Yine de dene" bir kez adresi yok sayar.
    private var samsungIgnoreAddressOnce = false
    /// Samsung "koptu" hâlinde kapının son görülen durumu.
    private var samsungDroppedGateOpen: Bool?
    private var lastSamsungLogLine: String?
    private var samsungSignInURL: URL?
    /// Başarılı denetimden sonra kendiliğinden tekrarı önler (TVAppCheckGate.swift).
    private var checkGate = TVAppCheckGate()

    // Sahadaki eski kimlikli TV uygulaması (tv-kurulumu.md, "Eski TV uygulaması"). Açma sırası önce yeni kimlik.
    // Eski uygulama kuruluyken yenisi kendiliğinden kurulmaz; kart önerir (`legacyApp`).
    /// Kullanıcı "Yeni Sürümü Kur" dedi: bu oturumda eski uygulama varken de yenisi kurulur.
    private var upgradeLegacy = false
    /// LG: son açılan uygulama eski kimlikli mi.
    private var lgLaunchedLegacy = false
    /// Samsung: açılacak kimlik; `samsungAppConfirmed` değilse tahmindir ve açılmazsa öbürü denenir.
    private var samsungAppID: String?
    private var samsungAppConfirmed = false
    private var samsungLastLaunchedID: String?

    public init(state: AppState, environment: TVSetupEnvironment) {
        self.state = state
        env = environment
        discovery = TVDiscovery(http: env.http, ssdp: env.ssdp, network: env.network, timing: env.timing.discovery)
        lgDev = LGDeveloperMode(http: env.http, ports: env.ports, processes: env.processes, clock: env.clock,
                                log: env.log, timing: env.timing.lgDeveloper)
        helper = TVHelperClient(executable: env.helperExecutable, processes: env.processes, log: env.log)
        if let tv = try? env.records.pairedTV() { state.pairedTV = tv }
        state.setup.tvAppBundled = true
    }

    deinit {
        guard let token = wakeObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(token)
    }

    /// Bütün işleri durdurur (uygulama kapanırken).
    public func shutdown() {
        for t in [searchTask, pairTask, appTask, pollTask, keeperTask, typeCodeTask, testTask] { t?.cancel() }
        let k = lgKeeper
        lgKeeper = nil
        Task { await k?.close() }
    }

    // MARK: Yardımcılar

    var macAddress: String? { MacAddressPicker.pick(tvHost: state?.pairedTV?.host, network: env.network) }

    func serverURL() async -> String {
        let port = await env.server.port()
        return TVApp.serverURL(macAddress: macAddress, port: port)
    }

    func savedTV() -> TVRecord? { try? env.records.tv() }

    /// Kart ve onun düz özeti (`tvInstall`).
    func setCard(_ card: TVAppCard) {
        guard let state else { return }
        state.setup.tvApp = card
        switch card {
        case .none, .lgDeveloperModeOff, .lgPassphrase, .samsungCheck, .samsungSignIn: state.tvInstall = .idle
        case .working: state.tvInstall = .installing(progress: nil)
        case let .ready(v, _): state.tvInstall = .installed(version: v)
        case let .legacyApp(v): state.tvInstall = .installed(version: v.isEmpty ? nil : v)
        case let .failed(m): state.tvInstall = .failed(message: m)
        case .androidDebuggingOff: state.tvInstall = .searching
        case .androidApprove: state.tvInstall = .waitingForApproval
        }
        updatePolling(for: card)
    }

    func installMessage(_ e: TVInstallError, brand: PairedTV.Brand) -> String {
        TVSetupText.installMessage(e, brand: brand, logPath: env.log.path, appStoreBuild: env.appStoreBuild)
    }

    // MARK: 1. TV bulma

    public func searchTVs() {
        guard let state else { return }
        searchTask?.cancel()
        state.setup.tvSearch = .searching
        state.setup.foundTVs = []
        let discovery = discovery
        searchTask = Task { [weak self] in
            let found = await discovery.searchAll()
            guard !Task.isCancelled, let self, let state = self.state else { return }
            state.setup.foundTVs = found
            state.setup.tvSearch = .finished
        }
    }

    /// Kayıtlı TV'ye bağlanılamadı: (en çok 30 sn'de bir) aynı marka yeniden aranır, yeni adres saklanır.
    /// Dönen değer yeni kayıt (değiştiyse).
    @discardableResult
    public func rediscoverAddress() async -> TVRecord? {
        guard let saved = savedTV(), saved.brand != .androidTV, readdress.shouldSearch(now: env.clock.now()) else { return nil }
        let found = await discovery.search(saved.brand)
        guard let new = TVReaddressPolicy.newAddress(saved: saved, found: found) else { return nil }
        let record = TVRecord(name: saved.name, host: new.host, brand: saved.brand)
        env.log.write("TV adresi değişti: \(saved.host) → \(new.host)")
        try? saveTV(record)
        return record
    }

    // MARK: 2. Eşleştirme

    public func pairTV(_ tv: DiscoveredTV) {
        guard let state else { return }
        pairTask?.cancel()
        appTask?.cancel()
        state.setup.tvConnect = .connecting(brand: tv.brand)
        setCard(.none)
        pairTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.pair(tv)
            } catch is CancellationError {
                return
            } catch let e as TVPairingError {
                self.state?.setup.tvConnect = .failed(Self.connectFailure(e, brand: tv.brand))
            } catch {
                self.state?.setup.tvConnect = .failed(.noResponse)
            }
        }
    }

    static func connectFailure(_ e: TVPairingError, brand: PairedTV.Brand) -> TVConnectFailure {
        guard brand == .samsung else { return .noResponse }
        switch e {
        case .refused: return .samsungRefused
        case .timedOut: return .samsungNotAccepted
        case .unreachable: return .noResponse
        }
    }

    func pair(_ tv: DiscoveredTV) async throws {
        try? await env.server.ensureRunning()
        let storedKey = (try? env.records.tvKey()) ?? nil
        let sameTV = savedTV().map { $0.brand == tv.brand && $0.host == tv.host } ?? false
        let key = sameTV ? storedKey : nil
        let server = await serverURL()
        if !sameTV { forgetLaunchedApps() }
        var newKey: String?
        switch tv.brand {
        case .lg:
            let client = lgClient(tv.host)
            newKey = try await client.connect(clientKey: key)
            lgAppLaunched = await lgLaunch(client, server: server)
            await lgKeeper?.close()
            lgKeeper = client
        case .samsung:
            let remote = SamsungRemote(host: tv.host, sockets: env.sockets, clock: env.clock, timing: env.timing.samsung)
            newKey = try await remote.connect(token: key)
            let appID = await samsungAppToLaunch(host: tv.host)
            if (try? await remote.launchApp(server: server, appID: appID)) != nil { samsungLastLaunchedID = appID }
            await remote.close()
            lastSamsungKeepAlive = env.clock.now()
        case .androidTV:
            break
        }
        try Task.checkCancellation()
        try saveTV(TVRecord(name: tv.name, host: tv.host, brand: tv.brand))
        if let newKey { try? env.records.setTVKey(newKey) }
        guard let state else { return }
        state.pairedTV = try? env.records.pairedTV()
        if state.settings.output == .computer { state.settings.output = .tv }
        state.setup.tvConnect = .idle
        env.log.write("TV eşleşti: \(tv.brand.rawValue) \(tv.name) \(tv.host)")
        switch tv.brand {
        case .lg: await checkApp(force: true)                     // LG'de beklenerek
        case .samsung, .androidTV: startCheck(force: true)       // arka planda
        }
    }

    /// TV kaydı. Marka ya da (Android dışında) adres değiştiyse saklı sürüm silinir.
    func saveTV(_ record: TVRecord) throws {
        let old = savedTV()
        let version = (try? env.records.tvAppVersion()) ?? nil
        try env.records.setTV(record)
        if record.brand == .androidTV, old?.brand == .androidTV, let version {
            try? env.records.setTVAppVersion(version)
        }
        state?.pairedTV = try? env.records.pairedTV()
    }

    // MARK: 3. TV uygulaması kartı

    /// Kendiliğinden denetim (adım açılınca, ekranın yoklaması): yakın zamanda doğrulanan TV'de yükleyici çalışmaz;
    /// Samsung denetim kartında yoklamayı denetleyicinin kendisi yapar (`pollOnce`).
    public func recheckTVApp() { recheckTVApp(force: false) }

    /// `force`: kullanıcı istedi ("Tekrar Dene"); kapı yok sayılır.
    public func recheckTVApp(force: Bool) {
        if !force, case let .samsungCheck(c)? = state?.setup.tvApp, c.problem != .checking, pollTask != nil { return }
        startCheck(force: force)
    }

    /// Eski uygulama kartındaki "Yeni Sürümü Kur": bu oturumda eski uygulama varken de yenisi kurulur (eskisi yerinde
    /// kalır). LG'de gerekirse geliştirici modu ve parola kartları çıkar.
    public func upgradeLegacyTVApp() {
        upgradeLegacy = true
        env.log.write("Eski TV uygulaması için yeni sürüm kurulumu istendi (eskisi kaldırılmaz).")
        recheckTVApp(force: true)
    }

    /// Hangi uygulamanın açılacağı bilgisi (TV değişince).
    func forgetLaunchedApps() {
        upgradeLegacy = false
        lgLaunchedLegacy = false
        samsungAppID = nil
        samsungAppConfirmed = false
        samsungLastLaunchedID = nil
    }

    /// Süren denetim (testler bekler).
    var appTaskForTests: Task<Void, Never>? { appTask }

    func startCheck(force: Bool) {
        appTask?.cancel()
        appTask = Task { [weak self] in await self?.checkApp(force: force) }
    }

    func gateKey(_ tv: TVRecord, _ package: TVAppPackage) -> TVAppCheckGate.Key {
        TVAppCheckGate.Key(brand: tv.brand, host: tv.host, bundled: package.version)
    }

    func checkApp(force: Bool = false) async {
        guard let tv = savedTV() else { setCard(.none); return }
        guard let package = env.packages.package(for: tv.brand),
              tv.brand != .samsung || helper.isAvailable else {
            state?.setup.tvAppBundled = false
            setCard(.none)
            return
        }
        state?.setup.tvAppBundled = true
        switch tv.brand {
        case .lg: await lgFlow(tv, package: package, passphrase: nil, force: force)
        case .samsung: await samsungFlow(tv, package: package, force: force)
        case .androidTV: await androidFlow(tv, package: package)
        }
    }

    /// LG "TV'ye Kur" (Passphrase ile); öbür markalarda yeniden denetim.
    public func installTVApp(passphrase: String?) {
        guard let tv = savedTV(), tv.brand == .lg, let p = passphrase?.trimmingCharacters(in: .whitespacesAndNewlines),
              !p.isEmpty, let package = env.packages.lg else {
            recheckTVApp(force: true)
            return
        }
        appTask?.cancel()
        appTask = Task { [weak self] in await self?.lgFlow(tv, package: package, passphrase: p) }
    }

    // MARK: LG (§5.1)

    func lgFlow(_ tv: TVRecord, package: TVAppPackage, passphrase: String?, force: Bool = true) async {
        let host = tv.host
        let gate = gateKey(tv, package)
        if !force, passphrase == nil,
           let v = checkGate.freshVersion(gate, recorded: nil, requireRecorded: false, now: env.clock.now()) {
            setCard(.ready(version: v, lgHoursLeft: nil))
            return
        }
        if lgAppLaunched == nil { lgAppLaunched = await lgLaunchOnce(tv) }
        var key = (try? env.records.tvDevKey()) ?? nil
        let legacyRunning = (lgAppLaunched ?? false) && lgLaunchedLegacy
        if legacyRunning, !upgradeLegacy, passphrase == nil {
            let version = await lgLegacyVersion(host: host, key: key)
            // Eski uygulama da geliştirici modunda çalışır: süre yine uzatılır.
            if let key, await lgDev.isEnabled(host: host) { _ = await lgExtendIfDue(host: host, key: key) }
            guard !Task.isCancelled else { return }
            setCard(.legacyApp(version: version))
            return
        }
        // Yalnız yeni uygulama açıldıysa kurulum kartı gizlenir; eski açıldıysa (kullanıcı yenisini istedi) gösterilir.
        let launched = (lgAppLaunched ?? false) && !lgLaunchedLegacy

        if let passphrase {
            setCard(.working)
            do {
                let k = try await lgDev.fetchKey(host: host, passphrase: passphrase)
                try? env.records.setTVDevKey(k)
                key = k
            } catch let e as TVInstallError {
                let message = installMessage(e, brand: .lg)
                let enabled = await lgDev.isEnabled(host: host)
                setCard(enabled ? .lgPassphrase(error: message) : .lgDeveloperModeOff(passphraseError: message))
                return
            } catch {
                setCard(.lgPassphrase(error: installMessage(TVInstallError(.installFailed, reason: "\(error)"), brand: .lg)))
                return
            }
        } else {
            let enabled = await lgDev.isEnabled(host: host)
            guard !Task.isCancelled else { return }
            if !enabled {
                setCard(launched ? .none : .lgDeveloperModeOff(passphraseError: nil))
                return
            }
            if key == nil {
                setCard(launched ? .none : .lgPassphrase(error: nil))
                return
            }
        }
        guard let key else { return }
        if !launched { setCard(.working) }
        do {
            let result = try await lgDev.install(host: host, key: key, package: package)
            guard !Task.isCancelled else { return }
            let version: String
            switch result {
            case let .alreadyCurrent(v): version = v
            case let .installed(v):
                version = v
                env.log.write("LG: TV uygulaması kuruldu (\(v)).")
                lgAppLaunched = await lgLaunchOnce(tv, fresh: true)
            }
            let hours = await lgExtendIfDue(host: host, key: key)
            checkGate.confirm(gate, version: version, now: env.clock.now())
            setCard(.ready(version: version, lgHoursLeft: hours))
        } catch let e as TVInstallError {
            if e.problem == .keyRejected {
                try? env.records.vault.remove(VaultAccount.tvDevKey.rawValue)
                setCard(.lgPassphrase(error: installMessage(e, brand: .lg)))
            } else {
                setCard(.failed(message: installMessage(e, brand: .lg)))
            }
        } catch is CancellationError {
            return
        } catch {
            setCard(.failed(message: installMessage(TVInstallError(.installFailed, reason: "\(error)"), brand: .lg)))
        }
    }

    /// Bekçi varsa ona "yeniden bağlan" denir; yoksa eşleşmedeki gibi açma iletisi. `fresh`: yeni uygulama
    /// kuruldu, sıra yeniden yeni kimlikten başlar.
    func lgLaunchOnce(_ tv: TVRecord, fresh: Bool = false) async -> Bool {
        let server = await serverURL()
        if let k = lgKeeper, await k.isConnected {
            if fresh { await k.forgetLaunchedApp() }
            let ok = await lgLaunch(k, server: server)
            let stillConnected = await k.isConnected
            if ok || stillConnected { return ok }
        }
        let key = (try? env.records.tvKey()) ?? nil
        let client = lgClient(tv.host)
        guard (try? await client.connect(clientKey: key)) != nil else { return false }
        let ok = await lgLaunch(client, server: server)
        await lgKeeper?.close()
        lgKeeper = client
        return ok
    }

    /// `listApps`'i yanıtsız bırakan TV'ye bir daha sorulmaz (yanıtsız istek bağlantıyı kapatır).
    private var lgListAppsBroken: Set<String> = []

    func lgClient(_ host: String) -> LGSSAPClient {
        LGSSAPClient(host: host, sockets: env.sockets, timing: env.timing.lg, queryApps: !lgListAppsBroken.contains(host))
    }

    /// Yeni, olmazsa eski uygulamayı açar ve açılanı not eder.
    func lgLaunch(_ client: LGSSAPClient, server: String) async -> Bool {
        let id = try? await client.launchNino(server: server)
        if await client.listAppsFailed, lgListAppsBroken.insert(client.host).inserted {
            env.log.write("LG: listApps yanıtlanmadı; bu TV'de açma yalnız launch yanıtına bakar.")
        }
        return recordLGLaunch(id)
    }

    /// Açılan LG kimliğini not eder; açıldıysa `true`.
    func recordLGLaunch(_ id: String?) -> Bool {
        lgLaunchedLegacy = id == TVApp.legacyLGID
        if lgLaunchedLegacy { env.log.write("LG: yeni TV uygulaması açılamadı; eski TV uygulaması açıldı.") }
        return id != nil
    }

    /// Eski LG uygulamasının sürümü (geliştirici anahtarı ve SSH varsa); okunamazsa boş.
    func lgLegacyVersion(host: String, key: String?) async -> String {
        guard let key, await env.ports.isOpen(host: host, port: LGDeveloperMode.sshPort, timeout: 2) else { return "" }
        return ((try? await lgDev.installedVersion(host: host, key: key, appID: TVApp.legacyLGID)) ?? nil) ?? ""
    }

    /// 1000 saatlik süre: son uzatmadan 20 saatten fazla geçtiyse uzatılır. Dönen değer kalan saat.
    func lgExtendIfDue(host: String, key: String) async -> Int? {
        let k = LGDeveloperMode.extensionDefaultsKey(host: host)
        let now = env.clock.now()
        if let last = env.defaults.object(forKey: k) as? Date, now.timeIntervalSince(last) <= env.timing.lgDeveloper.extendAfter {
            return nil
        }
        guard let ext = await lgDev.extendSession(host: host, key: key) else { return nil }
        env.defaults.set(now, forKey: k)
        return ext.hoursLeft
    }

    // MARK: Samsung (§5.2)

    func inspectSamsung(host: String) async -> SamsungInspection {
        let http = env.http
        async let info: SamsungDeviceInfo? = {
            guard let url = TVDiscovery.samsungInfoURL(host),
                  let r = try? await http.get(url, timeout: 2), r.status == 200 else { return nil }
            return SamsungDeviceInfo.parse(r.body)
        }()
        async let gate = env.ports.isOpen(host: host, port: 26101, timeout: 2)
        let mac = MacAddressPicker.pick(tvHost: host, network: env.network)
        return SamsungInspection(info: await info, installGateOpen: await gate, macAddress: mac)
    }

    func checkCard(_ i: SamsungInspection, problem: SamsungCheck.Problem) -> SamsungCheck {
        var previous: SamsungCheck.TypeCodeResult?
        if case let .samsungCheck(c)? = state?.setup.tvApp { previous = c.typeCode }
        return SamsungCheck(problem: problem, developerMode: i.info?.developerMode ?? (i.tvResponds ? i.developerModeOn : nil),
                            tvHostIP: i.hostIP, macAddress: i.macAddress ?? "", installGateOpen: i.installGateOpen,
                            modelYear: i.info?.modelYear, typeCode: previous, logPath: env.log.path)
    }

    static func cardProblem(_ step: SamsungMissingStep) -> SamsungCheck.Problem? {
        switch step {
        case .tvNotResponding: return .noAnswer
        case .developerModeOff: return .developerModeOff
        case .hostLoopback: return .loopback
        case .hostLeadingZeros: return .leadingZeros
        case .hostReversed: return .reversed
        case .hostWrong: return .wrongAddress
        case .notRestarted: return .notRestarted
        case .none: return nil
        }
    }

    func samsungKnownCurrent(_ package: TVAppPackage) -> String? {
        let v = (try? env.records.tvAppVersion()) ?? nil
        return TVVersion.isCurrent(v, bundled: package.version) ? v : nil
    }

    func samsungFlow(_ tv: TVRecord, package: TVAppPackage, force: Bool = true) async {
        let gate = gateKey(tv, package)
        if !force, let v = checkGate.freshVersion(gate, recorded: samsungKnownCurrent(package), requireRecorded: true,
                                                  now: env.clock.now()) {
            setCard(.ready(version: v, lgHoursLeft: nil))
            return
        }
        if state?.setup.tvApp == TVAppCard.none { setCard(.samsungCheck(SamsungCheck(problem: .checking, macAddress: macAddress ?? ""))) }
        let inspection = await inspectSamsung(host: tv.host)
        guard !Task.isCancelled else { return }
        let step = inspection.missingStep
        let current = samsungKnownCurrent(package)
        let ignoreAddress = samsungIgnoreAddressOnce
        samsungIgnoreAddressOnce = false

        if let problem = Self.cardProblem(step), !(step.isAddressProblem && ignoreAddress) {
            if step.isAddressProblem {
                let line = "Host PC IP (TV ayarı) \(inspection.hostIP ?? "-"), bu Mac'in TV'ye giden adresi \(inspection.macAddress ?? "-"); kurulum denenmedi."
                if line != lastSamsungLogLine { env.log.write(line); lastSamsungLogLine = line }
            }
            if let current {
                setCard(.ready(version: current, lgHoursLeft: nil))
            } else if !upgradeLegacy, await samsungLegacyOnly(host: tv.host) {
                setCard(.legacyApp(version: ""))
            } else {
                setCard(.samsungCheck(checkCard(inspection, problem: problem)))
            }
            return
        }
        if step.isAddressProblem && ignoreAddress {
            env.log.write("Samsung: Yine de dene; Host PC IP (TV ayarı: \(inspection.hostIP ?? "-")) yok sayıldı.")
        }

        if let current { setCard(.ready(version: current, lgHoursLeft: nil)) } else { setCard(.working) }
        let args = TVHelperClient.samsungInstallArguments(host: tv.host, package: package.url, version: package.version,
                                                          profiles: env.folder.samsungFolder, log: env.folder.tvInstallLog,
                                                          keepLegacy: !upgradeLegacy)
        let events = HelperEventRelay()
        let relay = Task { [weak self] in
            for await e in events.stream { await self?.handleSamsungEvent(e) }
        }
        defer { relay.cancel() }
        do {
            let outcome = try await helper.run(args, onEvent: { events.send($0) })
            events.finish()
            await relay.value
            if case let .legacy(version) = outcome {
                samsungConfirm(TVApp.legacySamsungID)
                samsungSignInURL = nil
                setCard(.legacyApp(version: version))
                return
            }
            guard case let .done(version, installed) = outcome else { return }
            let v = version.isEmpty ? package.version : version
            samsungConfirm(TVApp.samsungID)
            try? env.records.setTVAppVersion(v)
            checkGate.confirm(gate, version: v, now: env.clock.now())
            env.log.write("Samsung: TV uygulaması \(v) doğrulandı; \(Int(TVAppCheckGate.quietPeriod / 3600)) saat kendiliğinden yeniden denetlenmez.")
            samsungSignInURL = nil
            setCard(.ready(version: v, lgHoursLeft: nil))
            if installed { await samsungLaunch(tv) }
        } catch let e as TVInstallError {
            events.finish()
            samsungSignInURL = nil
            if e.problem == .unreachable {
                if let current { setCard(.ready(version: current, lgHoursLeft: nil)); return }
                if !upgradeLegacy, await samsungLegacyOnly(host: tv.host) { setCard(.legacyApp(version: "")); return }
                samsungDroppedGateOpen = inspection.installGateOpen
                setCard(.samsungCheck(checkCard(inspection, problem: .dropped(reason: e.reason))))
                return
            }
            setCard(.failed(message: installMessage(e, brand: .samsung)))
        } catch {
            events.finish()
        }
    }

    func handleSamsungEvent(_ e: TVHelperEvent) {
        switch e {
        case let .login(url):
            samsungSignInURL = url
            if !env.openURL(url) { env.log.write("Samsung giriş sayfası açılamadı: \(url.absoluteString)") }
            setCard(.samsungSignIn(url: url.absoluteString))
        case let .progress(step):
            if TVHelperEvent.workingSteps.contains(step), state?.setup.tvApp != .working,
               !(step == "signin" && samsungSignInURL != nil) {
                setCard(.working)
            }
        default:
            break
        }
    }

    public func samsungTryAnyway() {
        samsungIgnoreAddressOnce = true
        recheckTVApp(force: true)
    }

    public func reopenSamsungSignIn() {
        guard let url = samsungSignInURL ?? {
            if case let .samsungSignIn(s)? = state?.setup.tvApp { return URL(string: s) }
            return nil
        }() else { return }
        if !env.openURL(url) { env.log.write("Samsung giriş sayfası açılamadı: \(url.absoluteString)") }
    }

    /// "TV'ye 1 2 3 4 5 yaz".
    public func samsungTypeDeveloperCode() {
        guard let tv = savedTV(), tv.brand == .samsung else { return }
        setTypeCode(.sending)
        typeCodeTask?.cancel()
        typeCodeTask = Task { [weak self] in
            guard let self else { return }
            let remote = SamsungRemote(host: tv.host, sockets: self.env.sockets, clock: self.env.clock, timing: self.env.timing.samsung)
            let key = (try? self.env.records.tvKey()) ?? nil
            do {
                let token = try await remote.connect(token: key)
                try? self.env.records.setTVKey(token)
                try await remote.typeDeveloperCode()
                await remote.close()
                self.env.log.write("Samsung: 1 2 3 4 5 gönderildi.")
                self.setTypeCode(.sent)
            } catch {
                await remote.close()
                self.env.log.write("Samsung: 1 2 3 4 5 gönderilemedi: \(error)")
                self.setTypeCode(.unreachable)
            }
        }
    }

    func setTypeCode(_ r: SamsungCheck.TypeCodeResult) {
        guard case var .samsungCheck(c)? = state?.setup.tvApp else { return }
        c.typeCode = r
        state?.setup.tvApp = .samsungCheck(c)
    }

    func samsungLaunch(_ tv: TVRecord) async {
        let remote = SamsungRemote(host: tv.host, sockets: env.sockets, clock: env.clock, timing: env.timing.samsung)
        let key = (try? env.records.tvKey()) ?? nil
        if let token = try? await remote.connect(token: key) {
            try? env.records.setTVKey(token)
            let appID = await samsungAppToLaunch(host: tv.host)
            if (try? await remote.launchApp(server: await serverURL(), appID: appID)) != nil { samsungLastLaunchedID = appID }
        }
        await remote.close()
        lastSamsungKeepAlive = env.clock.now()
    }

    @discardableResult
    func samsungConfirm(_ id: String) -> String {
        samsungAppID = id
        samsungAppConfirmed = true
        return id
    }

    /// Açılacak Samsung kimliği. Kesin bilgi: yardımcının `vd_applist` sonucu, kayıtlı yeni sürüm, uzak sorgu
    /// (`SamsungAppQuery`). Bilgi yoksa tahmin (önce yeni); açılmazsa açık tutma bir sonraki turda öbürünü dener.
    func samsungAppToLaunch(host: String) async -> String {
        if samsungAppConfirmed, let id = samsungAppID { return id }
        if let saved = savedTV(), saved.brand == .samsung, saved.host == host, ((try? env.records.tvAppVersion()) ?? nil) != nil {
            return samsungConfirm(TVApp.samsungID)
        }
        let new = await SamsungAppQuery.isInstalled(env.http, host: host, appID: TVApp.samsungID)
        if new == true { return samsungConfirm(TVApp.samsungID) }
        let old = await SamsungAppQuery.isInstalled(env.http, host: host, appID: TVApp.legacySamsungID)
        if old == true, new == false { return samsungConfirm(TVApp.legacySamsungID) }
        if old == true || (new == false && old == nil) {
            samsungAppID = TVApp.legacySamsungID
        } else if old == false {
            samsungAppID = TVApp.samsungID
        }
        return samsungAppID ?? TVApp.samsungID
    }

    /// TV'de yalnız eski Samsung uygulaması olduğu kesin mi.
    func samsungLegacyOnly(host: String) async -> Bool {
        let id = await samsungAppToLaunch(host: host)
        return samsungAppConfirmed && id == TVApp.legacySamsungID
    }

    // MARK: Android TV (§6)

    func androidFlow(_ tv: TVRecord, package: TVAppPackage) async {
        let current = (try? env.records.tvAppVersion()) ?? nil
        let connected = await env.server.connectedTVApps()
        if connected.contains(where: { TVVersion.isCurrent($0, bundled: package.version) }) {
            setCard(.ready(version: connected.compactMap { $0 }.first ?? package.version, lgHoursLeft: nil))
            return
        }
        var host: String?
        if !tv.host.isEmpty, await env.ports.isOpen(host: tv.host, port: 5555, timeout: 2) { host = tv.host }
        guard !Task.isCancelled else { return }
        if host == nil {
            if TVVersion.isCurrent(current, bundled: package.version), let current {
                setCard(.ready(version: current, lgHoursLeft: nil))
                return
            }
            host = await helper.androidScan().first
        }
        guard !Task.isCancelled else { return }
        guard let host else {
            setCard(.androidDebuggingOff)
            return
        }
        setCard(.working)
        try? FileManager.default.createDirectory(at: env.folder.adbFolder, withIntermediateDirectories: true)
        let args = TVHelperClient.androidInstallArguments(host: host, package: package.url, version: package.version,
                                                          keyDir: env.folder.adbFolder, keepLegacy: !upgradeLegacy)
        let events = HelperEventRelay()
        let relay = Task { [weak self] in
            for await e in events.stream {
                if case .approve = e { self?.setCard(.androidApprove) }
            }
        }
        defer { relay.cancel() }
        do {
            let outcome = try await helper.run(args, onEvent: { events.send($0) })
            events.finish()
            await relay.value
            if case let .legacy(version) = outcome {
                try? saveTV(TVRecord(name: tv.name, host: host, brand: .androidTV))
                env.log.write("Android TV: yalnız eski TV uygulaması kurulu; o açıldı, yenisi kurulmadı.")
                setCard(.legacyApp(version: version))
                return
            }
            guard case let .done(version, _) = outcome else { return }
            let v = version.isEmpty ? package.version : version
            try? saveTV(TVRecord(name: tv.name, host: host, brand: .androidTV))
            try? env.records.setTVAppVersion(v)
            setCard(.ready(version: v, lgHoursLeft: nil))
        } catch let e as TVInstallError {
            events.finish()
            setCard(.failed(message: installMessage(e, brand: .androidTV)))
        } catch {
            events.finish()
        }
    }

    // MARK: Kendiliğinden ilerleme

    /// "Geliştirici modu kapalı" hâlinde 3 sn'de bir; Samsung "koptu" ve "adres yanlış" hâllerinde 3 sn'de bir.
    func updatePolling(for card: TVAppCard) {
        let wanted: Bool
        switch card {
        case .lgDeveloperModeOff, .androidDebuggingOff: wanted = true
        case let .samsungCheck(c): wanted = c.problem != .checking
        default: wanted = false
        }
        if !wanted { pollTask?.cancel(); pollTask = nil; return }
        guard pollTask == nil else { return }
        let interval = env.timing.poll
        let clock = env.clock
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await clock.sleep(interval)
                guard !Task.isCancelled, let self else { return }
                await self.pollOnce()
            }
        }
    }

    func pollOnce() async {
        guard let tv = savedTV(), let card = state?.setup.tvApp else { return }
        switch card {
        case .lgDeveloperModeOff:
            if await lgDev.isEnabled(host: tv.host) { startCheck(force: false) }
        case .androidDebuggingOff:
            startCheck(force: false)
        case let .samsungCheck(c):
            let i = await inspectSamsung(host: tv.host)
            if case .dropped = c.problem {
                // Yalnız denetim: eksik adım belli olduysa ya da kapı kapalıyken açıldıysa yeniden kurulum.
                let wasOpen = samsungDroppedGateOpen ?? c.installGateOpen
                samsungDroppedGateOpen = i.installGateOpen
                if let p = Self.cardProblem(i.missingStep) {
                    setCard(.samsungCheck(checkCard(i, problem: p)))
                } else if !wasOpen && i.installGateOpen {
                    startCheck(force: false)
                }
            } else if let p = Self.cardProblem(i.missingStep) {
                let updated = checkCard(i, problem: p)
                if updated != c { setCard(.samsungCheck(updated)) }
            } else {
                startCheck(force: false)
            }
        default:
            break
        }
    }

    // MARK: 4. TV uygulamasını açık tutma (§4)

    public func startKeepingAppOpen() {
        guard keeperTask == nil else { return }
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemDidWake() }
            }
        }
        let clock = env.clock
        let tick = env.timing.keeperTick
        keeperTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.keepAliveTick()
                try? await clock.sleep(tick)
            }
        }
    }

    public func stopKeepingAppOpen() {
        keeperTask?.cancel()
        keeperTask = nil
    }

    /// Mac uykudan uyanınca bağlantı hemen yenilenir.
    public func systemDidWake() {
        let k = lgKeeper
        lgKeeper = nil
        lastSamsungKeepAlive = nil
        Task { [weak self] in
            await k?.close()
            await self?.keepAliveTick()
        }
    }

    func keepAliveTick() async {
        guard let tv = savedTV() else { return }
        switch tv.brand {
        case .lg: await lgKeepAlive(tv)
        case .samsung: await samsungKeepAlive(tv)
        case .androidTV: break
        }
    }

    func lgKeepAlive(_ tv: TVRecord) async {
        let server = await serverURL()
        if let k = lgKeeper, await k.isConnected {
            do {
                let fg = try await k.foregroundAppID()
                if LGSSAPClient.isTVOwnInput(fg), await env.server.connectedTVApps().isEmpty {
                    env.log.write("LG: TV kendi girişine geçti (\(fg ?? "")); uygulama yeniden açılıyor.")
                    _ = try await k.launchApp(server: server)
                }
            } catch {
                await k.close()
                lgKeeper = nil
            }
            return
        }
        let client = lgClient(tv.host)
        let key = (try? env.records.tvKey()) ?? nil
        do {
            let newKey = try await client.connect(clientKey: key)
            try? env.records.setTVKey(newKey)
            // Uygulamayı açmak (launch) TV'de onu yeniden başlatır: bağlantı canlıyken (TV uygulaması bize bağlı)
            // tekrar edilmez. Yalnız TV uygulaması bağlı değilse açılır. (Kopan SSAP soketi her turda yeniden
            // kurulduğunda ekran dakikada bir kapanıp açılıyordu.)
            if await env.server.connectedTVApps().isEmpty {
                lgAppLaunched = await lgLaunch(client, server: server)
            }
            lgKeeper = client
        } catch {
            await client.close()
            await rediscoverAddress()
        }
    }

    func samsungKeepAlive(_ tv: TVRecord) async {
        guard await env.server.connectedTVApps().isEmpty else { return }
        let now = env.clock.now()
        if let last = lastSamsungKeepAlive, now.timeIntervalSince(last) < env.timing.samsungKeepAlive { return }
        lastSamsungKeepAlive = now
        // Tahminle açılan uygulama 30 sn'de bağlanmadıysa öbür kimlik denenir (kesin bilgi varsa değişmez).
        if !samsungAppConfirmed, let last = samsungLastLaunchedID {
            samsungAppID = last == TVApp.samsungID ? TVApp.legacySamsungID : TVApp.samsungID
        }
        let remote = SamsungRemote(host: tv.host, sockets: env.sockets, clock: env.clock, timing: env.timing.samsung)
        let key = (try? env.records.tvKey()) ?? nil
        do {
            let token = try await remote.connect(token: key)
            try? env.records.setTVKey(token)
            let appID = await samsungAppToLaunch(host: tv.host)
            try await remote.launchApp(server: await serverURL(), appID: appID)
            samsungLastLaunchedID = appID
        } catch {
            await rediscoverAddress()
        }
        await remote.close()
    }

    // MARK: 5. Deneme altyazısı (kurulum.md §8)

    public static let testDurationMs = 8000

    /// Altyazı kutusu: en son görülen yer; yoksa yatayda %30–%70, bölgenin altından 0,10 ile 0,03 yukarıda.
    public static func testBox(last: NinoBox?, regionBottom: Double = 1) -> NinoBox {
        if let last { return last }
        return NinoBox(left: 0.30, top: regionBottom - 0.10, right: 0.70, bottom: regionBottom - 0.03)
    }

    public func sendTestSubtitle(style: NinoStyle? = nil) {
        guard let state else { return }
        state.setup.test = (state.setup.test == .notSeen || state.setup.test == .sent) ? .resending : .sending
        testTask?.cancel()
        let toTV = state.subtitlesOnTV
        testTask = Task { [weak self] in
            guard let self else { return }
            await self.deliverTestSubtitle(toTV: toTV, style: style)
            guard !Task.isCancelled else { return }
            self.state?.setup.test = .sent
        }
    }

    /// Deneme altyazısı TV'de çevirinin hedef dilinde görünür (Mac'in arayüz dili İngilizce olsa da).
    nonisolated static func testLine(language: String) -> String {
        NinoL10n.string("tv.test.line", table: TVSetupText.table, language: language)
    }

    func deliverTestSubtitle(toTV: Bool, style: NinoStyle?) async {
        let server = env.server
        try? await server.ensureRunning()
        if toTV, await server.connectedTVApps().isEmpty, let tv = savedTV() {
            switch tv.brand {
            case .lg: _ = await lgLaunchOnce(tv)
            case .samsung: await samsungLaunch(tv)
            case .androidTV: await checkApp()
            }
            let deadline = env.clock.now().addingTimeInterval(env.timing.testWait)
            while env.clock.now() < deadline, await server.connectedTVApps().isEmpty, !Task.isCancelled {
                try? await env.clock.sleep(env.timing.testPoll)
            }
        }
        let box = Self.testBox(last: await server.lastSubtitleBox())
        if let style { try? await server.output.send(.style(style)) }
        let payload = ShowPayload(id: Int(env.clock.now().timeIntervalSince1970) % 1_000_000,
                                  text: Self.testLine(language: state?.settings.targetLanguage ?? "en"), durationMs: Self.testDurationMs, box: box)
        do {
            try await server.output.show(payload)
        } catch {
            env.log.write("Deneme altyazısı gönderilemedi: \(error)")
        }
    }
}

/// Yardımcının senkron olay geri çağrısını ana iş parçacığına sırayla taşır.
final class HelperEventRelay: @unchecked Sendable {
    let stream: AsyncStream<TVHelperEvent>
    private let continuation: AsyncStream<TVHelperEvent>.Continuation

    init() { (stream, continuation) = AsyncStream<TVHelperEvent>.makeStream() }
    func send(_ e: TVHelperEvent) { continuation.yield(e) }
    func finish() { continuation.finish() }
}
