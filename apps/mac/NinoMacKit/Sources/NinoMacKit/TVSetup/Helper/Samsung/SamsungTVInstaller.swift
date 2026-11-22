// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// `samsung-install`: geliştirici modu açık Samsung (Tizen) TV'ye `.wgt` paketini ağ üzerinden kurar
/// (tv-kurulumu.md §9). Olaylar yardımcınınkiyle aynıdır (`progress`, `login`, `done`, `error`).
public struct SamsungTVInstaller: Sendable {
    public static let port: UInt16 = 26101
    public typealias Failure = AndroidTVInstaller.Failure

    public struct Timing: Sendable {
        public var connect: TimeInterval = 10
        public var sdb = SDBConnection.Timing()
        /// Bağlantı denemelerinden önceki beklemeler (masaüstü: 0, 2, 5 sn).
        public var connectWaits: [TimeInterval] = [0, 2, 5]
        public var duidWait: TimeInterval = 0.5
        public var login: TimeInterval = 600
        public var certificate: TimeInterval = 60
        public var deviceInfo: TimeInterval = 2
        public init() {}
    }

    /// Dışarıyla konuşan her şey (testte sahte).
    public struct Ports: Sendable {
        public var connector: ADBConnecting
        public var http: TVHTTP
        public var network: NetworkInterfaceListing
        public var login: SamsungLoginListening
        public var certificates: SamsungCertificateTransport
        public var intermediates: @Sendable () -> [Data]
        public var now: @Sendable () -> Date
        public var tempFolder: URL

        public init(connector: ADBConnecting, http: TVHTTP, network: NetworkInterfaceListing,
                    login: SamsungLoginListening = SocketLoginListener(),
                    certificates: SamsungCertificateTransport = URLSessionCertificateTransport(),
                    intermediates: @escaping @Sendable () -> [Data] = { SamsungIntermediates.bundled() },
                    now: @escaping @Sendable () -> Date = Date.init,
                    tempFolder: URL = FileManager.default.temporaryDirectory) {
            self.connector = connector
            self.http = http
            self.network = network
            self.login = login
            self.certificates = certificates
            self.intermediates = intermediates
            self.now = now
            self.tempFolder = tempFolder
        }
    }

    public enum Event: Equatable, Sendable {
        case progress(String)
        case login(URL)
    }

    let ports: Ports
    let timing: Timing
    let log: @Sendable (String) -> Void

    public init(ports: Ports, timing: Timing = Timing(), log: @escaping @Sendable (String) -> Void) {
        self.ports = ports
        self.timing = timing
        self.log = log
    }

    // MARK: Akış

    /// Kurulum; dönen (TV'deki sürüm, gerçekten kuruldu mu, eski uygulama mı). Hatalar `Failure`; iptal
    /// `CancellationError`. `keepLegacy`: yeni uygulama yokken eski kimlikli uygulama kuruluysa kurulmaz, eskinin
    /// sürümü döner (`legacy`). Yeni uygulama eskinin yanına kurulur; eski hiçbir zaman kaldırılmaz.
    public func install(host: String, package: URL, version: String, profiles: URL, keyDir: URL, keepLegacy: Bool = false,
                        emit: @escaping @Sendable (Event) -> Void) async throws -> (version: String, installed: Bool, legacy: Bool) {
        log("--- Samsung TV'ye kurulum başladı (\(host)); paket: \(package.lastPathComponent)")
        do {
            let r = try await run(host: host, package: package, version: version, profiles: profiles, keyDir: keyDir,
                                  keepLegacy: keepLegacy, emit: emit)
            if r.legacy {
                log("TV'de yalnız eski TV uygulaması var (\(r.version.isEmpty ? "sürüm yok" : r.version)); kurulmadı, eskisi açılacak.")
            } else {
                log(r.installed ? "Kurulum tamam." : "TV'de \(r.version) sürümü var; kurulum gerekmedi.")
            }
            return r
        } catch let f as Failure where !Task.isCancelled {
            log("HATA \(f.code): \(f.message)")
            throw f
        } catch {
            if error is CancellationError || Task.isCancelled {
                log("Kurulum iptal edildi.")
                throw CancellationError()
            }
            let f = Failure("InstallFailed", "\(type(of: error)): \(error)")
            log("HATA \(f.code): \(f.message)")
            throw f
        }
    }

    struct Context {
        var host: String
        var local: String?
        var developerIP: String?
    }

    func run(host: String, package: URL, version: String, profiles: URL, keyDir: URL, keepLegacy: Bool = false,
             emit: @escaping @Sendable (Event) -> Void) async throws -> (version: String, installed: Bool, legacy: Bool) {
        guard IPv4.parse(host) != nil || Self.isIPv6(host) else { throw Failure("Unreachable", "geçersiz TV adresi: \(host)") }
        let wgt: Data
        do { wgt = try Data(contentsOf: package) } catch {
            throw Failure("InstallFailed", "paket okunamadı: \(package.lastPathComponent)")
        }
        let ctx = await context(host)
        let key: ADBKey
        do { key = try ADBKey.loadOrCreate(in: keyDir, log: { m in log(m) }) } catch {
            throw Failure("InstallFailed", "sdb anahtarı: \(error)")
        }

        let current = StreamBox()
        var (sdb, first) = try await connect(ctx, key: key)
        current.set(first)
        defer { current.close() }
        return try await withTaskCancellationHandler {
            emit(.progress("reading"))
            let cap = try await guarded { try await sdb.capability() }
            let platform = cap["platform_version"]?.trimmingCharacters(in: .whitespaces)
            var toolPath = cap["sdk_toolpath"]?.trimmingCharacters(in: .whitespaces) ?? ""
            if toolPath.isEmpty { toolPath = SamsungOutputs.defaultToolPath }
            log("TV: Tizen \(platform.flatMap { $0.isEmpty ? nil : $0 } ?? "?"), sdk_toolpath \(toolPath)")
            if SamsungOutputs.isTooOld(platform) { throw Failure("TooOld", "Tizen \(platform ?? "")") }
            if SamsungOutputs.isExperimental(platform) { log("2017–2018 TV'si, destek deneysel.") }

            let (before, legacy) = try await appVersions(sdb)
            if TVVersion.isCurrent(before, bundled: version), let before { return (before, false, false) }
            if before == nil, keepLegacy, let legacy { return (legacy, false, true) }
            if let legacy { log("Eski TV uygulaması (\(legacy.isEmpty ? "sürüm yok" : legacy)) yerinde kalır; yenisi yanına kurulur.") }

            let duid = try await readDUID(sdb)
            let (loaded, status) = SamsungProfile.load(profiles: profiles, duid: duid, now: ports.now(), log: { log($0) })
            var profile = status == .valid ? loaded : nil
            if profile == nil {
                emit(.progress("signin"))
                let account = try await signIn(emit: emit)
                emit(.progress("certificate"))
                profile = try await obtainCertificates(account: account, duid: duid, profiles: profiles)
                // Giriş dakikalar sürebilir; boşta kalan sdb bağlantısını TV kesmiş olabilir.
                current.close()
                (sdb, first) = try await connect(ctx, key: key)
                current.set(first)
            }
            guard let profile else { throw Failure("LoginFailed", "giriş gerekiyor") }

            if SamsungOutputs.needsDeviceProfile(platform) { await pushDeviceProfile(sdb, profile: profile, toolPath: toolPath) }

            emit(.progress("signing"))
            let signed = try signedCopy(wgt, profile: profile)
            defer { remove(signed) }
            let signedData = try Data(contentsOf: signed)

            emit(.progress("installing"))
            var output = await attempt(sdb, data: signedData, toolPath: toolPath)
            var kind = output.lost ? .connectionLost : SamsungOutputs.classify(output.text)
            log("vd_appinstall: \(output.text)")
            if kind.retriesAfterUninstall {
                emit(.progress("uninstalling"))
                for id in [SamsungOutputs.packageID, SamsungOutputs.appID] {
                    let out = (try? await sdb.shell("0 vd_appuninstall \(id)")) ?? "(yanıt yok)"
                    log("vd_appuninstall \(id): \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
                emit(.progress("installing"))
                output = await attempt(sdb, data: signedData, toolPath: toolPath)
                kind = output.lost ? .connectionLost : SamsungOutputs.classify(output.text)
                log("vd_appinstall (2): \(output.text)")
            }
            if kind != .success {
                if kind == .certificateInvalid, let moved = SamsungProfile.setAside(profile.folder, now: ports.now()) {
                    log("TV sertifikayı reddetti; profil kenara kondu: \(moved.lastPathComponent)")
                }
                throw Failure(kind.code, SamsungOutputs.failureDetail(output.text))
            }

            let after = try await appVersions(sdb).current
            if let after, TVVersion(after) < TVVersion(version) {
                throw Failure("InstallFailed", "Kurulum bitti görünüyor ama TV hâlâ \(after) sürümünü gösteriyor; beklenen \(version)")
            }
            do {
                let out = try await sdb.shell("0 was_execute \(SamsungOutputs.appID)")
                log("was_execute: \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
            } catch {
                log("Uygulama açılamadı: \(error)")
            }
            return (after ?? version, true, false)
        } onCancel: {
            current.cancel()
        }
    }

    /// İptal edilince açık sdb akışını kapatır (iptalden sonra açılan akış da hemen kapanır).
    final class StreamBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stream: ADBByteStream?
        private var cancelled = false
        func set(_ s: ADBByteStream) {
            let close = lock.withLock { () -> Bool in stream = s; return cancelled }
            if close { s.close() }
        }
        func close() { lock.withLock { stream }?.close() }
        func cancel() { lock.withLock { () -> ADBByteStream? in cancelled = true; return stream }?.close() }
    }

    static func isIPv6(_ s: String) -> Bool {
        var a = in6_addr()
        return s.contains(":") && inet_pton(AF_INET6, s, &a) == 1
    }

    /// sdb hatası: bağlantı kaybı `ConnectionLost`, öbürü olduğu gibi (beklenmeyen hata).
    func guarded<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch let e as SDBError where e.isTransportLoss {
            if Task.isCancelled { throw CancellationError() }
            throw Failure("ConnectionLost", "sdb: \(e)")
        }
    }

    // MARK: Bağlanma (§9.2, §9.3)

    func context(_ host: String) async -> Context {
        let local = ports.network.sourceAddress(toward: host, port: Self.port)
        var mode: String?
        var devIP: String?
        if let url = URL(string: "http://\(host):8001/api/v2/"),
           let r = try? await ports.http.get(url, timeout: timing.deviceInfo),
           let o = (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any],
           let device = o["device"] as? [String: Any] {
            mode = Self.text(device["developerMode"])
            devIP = Self.text(device["developerIP"]).flatMap { $0.isEmpty || $0 == "0.0.0.0" ? nil : $0 }
        }
        log("TV'ye bağlanılan yerel adres (LocalEndPoint): \(local ?? "?"); TV'deki Host PC IP (developerIP): "
            + "\(devIP ?? "?"); geliştirici modu: \(mode ?? "?")")
        if let local, let devIP, local != devIP {
            log("UYARI: Host PC IP (TV ayarı: \(devIP)) bu bilgisayarın adresinden (\(local)) farklı; bağlantı yine denenecek.")
        }
        return Context(host: host, local: local, developerIP: devIP)
    }

    static func text(_ v: Any?) -> String? {
        switch v {
        case nil, is NSNull: return nil
        case let s as String: return s
        case let v?:
            if let d = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed]) {
                return String(decoding: d, as: UTF8.self)
            }
            return "\(v)"
        }
    }

    func connect(_ ctx: Context, key: ADBKey) async throws -> (SDBConnection, ADBByteStream) {
        var last = ""
        let n = timing.connectWaits.count
        for (i, wait) in timing.connectWaits.enumerated() {
            if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            try Task.checkCancellation()
            var stream: ADBByteStream?
            do {
                let s = try await ports.connector.connect(host: ctx.host, port: Self.port, timeout: timing.connect)
                stream = s
                let sdb = SDBConnection(stream: s, timing: timing.sdb)
                let banner = try await withTaskCancellationHandler {
                    try await sdb.handshake(key: key)
                } onCancel: { s.close() }
                log("sdb: \(ctx.host) bağlandı (\(banner)).")
                return (sdb, s)
            } catch {
                stream?.close()
                if Task.isCancelled { throw CancellationError() }
                last = Self.message(error)
                log("sdb bağlantısı kurulamadı (\(i + 1)/\(n)): \(last)")
            }
        }
        throw Failure("Unreachable", "sdb \(ctx.host):\(Self.port): \(last) (bu bilgisayar \(ctx.local ?? "?"), "
                      + "Host PC IP (TV ayarı) \(ctx.developerIP ?? "?"))")
    }

    static func message(_ e: Error) -> String {
        if let s = e as? SDBError { return s.description }
        if let a = e as? ADBError {
            switch a {
            case let .unreachable(m): return m
            default: return "\(a)"
            }
        }
        return "\(e)"
    }

    // MARK: TV bilgisi (§9.4)

    /// Yeni uygulamanın sürümü ve (varsa) eski kimlikli uygulamanınki.
    func appVersions(_ sdb: SDBConnection) async throws -> (current: String?, legacy: String?) {
        let out = try await guarded { try await sdb.shell("0 vd_applist") }
        let v = SamsungOutputs.installedVersion(applist: out)
        let legacy = SamsungOutputs.legacyVersion(applist: out)
        log("vd_applist: " + (v.map { "Nino \($0)" } ?? "Nino yok (\(out.count) karakter)")
            + (legacy.map { ", eski uygulama \($0.isEmpty ? "var" : $0)" } ?? ""))
        return (v, legacy)
    }

    func readDUID(_ sdb: SDBConnection) async throws -> String {
        var last = ""
        for i in 0..<3 {
            if i > 0 { try await Task.sleep(nanoseconds: UInt64(timing.duidWait * 1_000_000_000)) }
            last = try await guarded { try await sdb.shell("0 getduid") }
            if let d = SamsungOutputs.duid(from: last) { return d }
            log("getduid (\(i + 1)/3): \(last.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let t = last.trimmingCharacters(in: .whitespacesAndNewlines)
        throw Failure("Unreachable", "TV kimliği (DUID) alınamadı; son yanıt: \(t.isEmpty ? "boş" : t)")
    }

    // MARK: Giriş ve sertifika (§9.6, §9.7)

    func signIn(emit: @escaping @Sendable (Event) -> Void) async throws -> SamsungLogin.Account {
        let url = SamsungLogin.url()
        do {
            return try await ports.login.waitForAccount(timeout: timing.login, onReady: { emit(.login(url)) })
        } catch let f as SamsungLogin.LoginError {
            switch f {
            case let .portUnavailable(m):
                throw Failure("LoginFailed", "localhost:\(SamsungLogin.port) giriş dönüşü için dinlenemedi "
                              + "(port başka bir Nino tarafından kullanılıyor olabilir): \(m)")
            case let .timedOut(summary):
                var m = "Samsung girişi 10 dakikada bitmedi"
                if let summary { m += "; dönüşte hesap yoktu (\(summary))" }
                throw Failure("LoginFailed", m)
            }
        }
    }

    func obtainCertificates(account: SamsungLogin.Account, duid: String, profiles: URL) async throws -> SamsungProfile {
        let key: ADBKey
        do { key = try ADBKey.generate() } catch { throw Failure("CertificateFailed", "anahtar üretilemedi: \(error)") }
        let authorCSR: Data, distributorCSR: Data
        do {
            authorCSR = SamsungCSR.pem(try SamsungCSR.author(key: key.privateKey))
            distributorCSR = SamsungCSR.pem(try SamsungCSR.distributor(key: key.privateKey, email: account.email, duid: duid))
        } catch { throw Failure("CertificateFailed", "sertifika isteği hazırlanamadı: \(error)") }
        let client = SamsungCertificateClient(transport: ports.certificates, timeout: timing.certificate, log: log)
        let issued: SamsungCertificateClient.Issued
        do {
            issued = try await client.request(account: account, authorCSR: authorCSR, distributorCSR: distributorCSR)
        } catch let f as SamsungCertificateClient.Failure {
            throw Failure("CertificateFailed", f.message)
        }
        // Gömülü ara sertifikalar; Samsung yanıtta zinciri de verdiyse onlar da aday (gömülüler önce).
        let cas = ports.intermediates() + issued.extraAuthor + issued.extraDistributor
        if ports.intermediates().isEmpty { log("UYARI: gömülü Samsung ara sertifikası yok (samsung-ca/*.pem).") }
        func chain(_ leaf: Data, _ what: String) throws -> [Data] {
            guard let ca = SamsungIntermediates.pick(for: leaf, from: cas) else {
                let issuer = X509Info(der: leaf)?.issuerCN ?? "?"
                throw Failure("CertificateFailed", "Samsung \(what) sertifikasını veren ara sertifika (\(issuer)) "
                              + "Nino'nun içinde bulunamadı")
            }
            return [leaf, ca]
        }
        let authorChain = try chain(issued.author, "yazar")
        let distChain = try chain(issued.distributor, "dağıtıcı")
        let profile: SamsungProfile
        do {
            profile = try SamsungProfile.save(profiles: profiles, duid: duid, keyPKCS1: key.pkcs1, authorChain: authorChain,
                                              distributorChain: distChain, deviceProfile: issued.deviceProfile)
        } catch { throw Failure("CertificateFailed", "sertifika kaydedilemedi: \(error)") }
        let ai = X509Info(der: issued.author), di = X509Info(der: issued.distributor)
        log("Yeni sertifika: yazar \(SamsungProfile.range(ai)) UTC, dağıtıcı \(SamsungProfile.range(di)) UTC, "
            + "dağıtıcıyı veren \(di?.issuerCN ?? "?")")
        return profile
    }

    // MARK: Cihaz profili, imza, kurma (§9.8–§9.10)

    func pushDeviceProfile(_ sdb: SDBConnection, profile: SamsungProfile, toolPath: String) async {
        let file = profile.folder.appendingPathComponent(SamsungProfile.deviceProfileFile)
        guard let data = try? Data(contentsOf: file) else {
            log("Cihaz profili yok (\(file.lastPathComponent)); kurulum yine denenecek.")
            return
        }
        do {
            try await sdb.push(data, to: "\(toolPath)/device-profile.xml", mtime: UInt32(ports.now().timeIntervalSince1970))
            log("Cihaz profili gönderildi.")
        } catch {
            log("Cihaz profili gönderilemedi (\(error)); kurulum yine denenecek.")
        }
    }

    func signedCopy(_ wgt: Data, profile: SamsungProfile) throws -> URL {
        let fm = FileManager.default
        let tmp = ports.tempFolder
        let cutoff = ports.now().addingTimeInterval(-600)
        if let items = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for u in items where u.lastPathComponent.hasPrefix("nino-") && u.pathExtension == "wgt" {
                let m = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let m, m < cutoff { try? fm.removeItem(at: u) }
            }
        }
        let out = tmp.appendingPathComponent("nino-\(Self.hex(8)).wgt")
        do {
            let signed = try WidgetSigner.sign(package: wgt, author: try profile.authorIdentity(),
                                               distributor: try profile.distributorIdentity())
            try signed.write(to: out)
        } catch {
            try? fm.removeItem(at: out)
            throw Failure("InstallFailed", "paket imzalanamadı: \(error)")
        }
        return out
    }

    func remove(_ url: URL) {
        for _ in 0..<3 {
            if (try? FileManager.default.removeItem(at: url)) != nil || !FileManager.default.fileExists(atPath: url.path) {
                return
            }
        }
    }

    static func hex(_ n: Int) -> String {
        PKCS12.random((n + 1) / 2).map { String(format: "%02x", $0) }.joined().prefix(n).description
    }

    /// Bir kurulum denemesi: gönder, kur; çıktı tek metin ("Push complete." + komut çıktısı).
    func attempt(_ sdb: SDBConnection, data: Data, toolPath: String) async -> (text: String, lost: Bool) {
        let remote = "\(toolPath)/nino-\(Self.hex(8)).wgt"
        var text = ""
        do {
            try await sdb.push(data, to: remote, mtime: UInt32(ports.now().timeIntervalSince1970))
            text = "Push complete.\n"
            text += try await sdb.shell("0 vd_appinstall \(SamsungOutputs.appID) \(remote)")
            return (text, false)
        } catch {
            if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
            text += "install failed: \(type(of: error)): \(Self.message(error))"
            return (text, (error as? SDBError)?.isTransportLoss ?? false)
        }
    }
}
