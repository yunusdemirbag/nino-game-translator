// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Android TV'ye ağ üzerinden (ADB, TCP 5555) TV uygulamasını kurar (tv-kurulumu.md §6). Tek bağlantı, TV onayı
/// en çok bir kez. Sonuç ve hatalar yardımcının olaylarıyla aynıdır (`TVHelperEvent`).
public struct AndroidTVInstaller: Sendable {
    public static let packageName = "com.ninotranslator.tv"
    public static let activity = "com.ninotranslator.tv/.MainActivity"
    public static let port: UInt16 = 5555
    /// APK'nın sync yolunda bırakıldığı yer.
    static let tempPath = "/data/local/tmp/nino-tv.apk"

    public struct Timing: Sendable {
        public var connect: TimeInterval = 5
        public var adb = ADBConnection.Timing()
        /// APK yazıldıktan sonra `pm`'in yanıtı için.
        public var install: TimeInterval = 180
        public var command: TimeInterval = 30
        public init() {}
    }

    let connector: ADBConnecting
    let log: @Sendable (String) -> Void
    let timing: Timing

    public init(connector: ADBConnecting, timing: Timing = Timing(), log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.connector = connector
        self.timing = timing
        self.log = log
    }

    /// Yardımcı hatası (kod `TVInstallError.problem(forHelperCode:)` ile eşleşir).
    public struct Failure: Error, Equatable, Sendable {
        public var code: String
        public var message: String
        public init(_ code: String, _ message: String) {
            self.code = code
            self.message = message
        }
    }

    /// Kurulumu yapar; `onApprove` TV onay kutusunu gösterdiğinde çağrılır.
    /// Dönen: (TV'deki sürüm, gerçekten kuruldu mu, eski uygulama mı). `keepLegacy`: yeni paket yokken eski kimlikli
    /// paket kuruluysa kurulmaz; eskisi açılır (`legacy`). Eski paket hiçbir zaman kaldırılmaz.
    public func install(host: String, package: URL, version: String, keyDir: URL, keepLegacy: Bool = false,
                        onApprove: @escaping @Sendable () -> Void) async throws -> (version: String, installed: Bool, legacy: Bool) {
        let apk: Data
        do { apk = try Data(contentsOf: package, options: .mappedIfSafe) } catch {
            throw Failure("InstallFailed", "APK: \(package.lastPathComponent)")
        }
        let key: ADBKey
        do { key = try ADBKey.loadOrCreate(in: keyDir, log: log) } catch {
            throw Failure("InstallFailed", "adbkey: \(error)")
        }

        let stream: ADBByteStream
        do { stream = try await connector.connect(host: host, port: Self.port, timeout: timing.connect) } catch {
            log("ADB: \(host):\(Self.port) bağlanılamadı (\(error)).")
            throw Failure("Unreachable", "\(host):\(Self.port)")
        }
        let adb = ADBConnection(stream: stream, timing: timing.adb)
        defer { stream.close() }

        do {
            // İş iptal edilirse (uygulama kapanıyor) soket kapanır; bekleyen okuma hemen biter.
            return try await withTaskCancellationHandler {
                let banner = try await adb.handshake(key: key, onApprovalNeeded: onApprove)
                log("ADB: \(host) bağlandı (\(banner.model ?? banner.systemType)).")
                return try await installOnConnection(adb, banner: banner, apk: apk, version: version, keepLegacy: keepLegacy)
            } onCancel: {
                stream.close()
            }
        } catch let f as Failure {
            throw f
        } catch let e as ADBError {
            log("ADB: \(e)")
            throw Self.failure(for: e, afterHandshake: await adb.banner != nil)
        } catch {
            throw Failure("InstallFailed", "\(type(of: error)): \(error)")
        }
    }

    static func failure(for e: ADBError, afterHandshake: Bool) -> Failure {
        switch e {
        case .notApproved: return Failure("NotApproved", "adb: auth")
        case .tlsRequired: return Failure("InstallFailed", "adb: STLS (wireless debugging pairing is not supported)")
        case .unreachable: return Failure("Unreachable", "adb: unreachable")
        case .timeout, .connectionClosed:
            let what = e == .timeout ? "timeout" : "connection closed"
            return afterHandshake ? Failure("ConnectionLost", "adb: \(what)") : Failure("Unreachable", "adb: \(what)")
        case let .openRefused(s): return Failure("InstallFailed", "adb: \(s) refused")
        case let .protocolError(m): return Failure("InstallFailed", m)
        }
    }

    func installOnConnection(_ adb: ADBConnection, banner: ADBBanner, apk: Data, version: String,
                             keepLegacy: Bool = false) async throws -> (version: String, installed: Bool, legacy: Bool) {
        let installed = Self.installedVersion(try await adb.shell("dumpsys package \(Self.packageName)", timeout: timing.command))
        log("ADB: TV'deki sürüm \(installed ?? "yok"), paket \(version).")
        if TVVersion.isCurrent(installed, bundled: version), let installed {
            await grantOverlay(adb)
            let pid = try await adb.shell("pidof \(Self.packageName)", timeout: timing.command)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if pid.isEmpty { try await start(adb) }
            return (installed, false, false)
        }
        if installed == nil, keepLegacy, let legacy = try await legacyVersion(adb) {
            log("ADB: yalnız eski TV uygulaması kurulu (\(legacy.isEmpty ? "sürüm yok" : legacy)); kurulmadı, eskisi açılıyor.")
            await grantOverlay(adb, package: Self.legacyPackage)
            let pid = try await adb.shell("pidof \(Self.legacyPackage)", timeout: timing.command)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if pid.isEmpty { try await startLegacy(adb) }
            return (legacy, false, true)
        }
        if installed != nil {
            let out = try await adb.shell("pm uninstall \(Self.packageName)", timeout: timing.install)
            log("ADB: pm uninstall: \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let result = try await installAPK(adb, banner: banner, apk: apk)
        if let problem = Self.installProblem(result) { throw problem }
        log("ADB: kuruldu (\(result.trimmingCharacters(in: .whitespacesAndNewlines))).")
        await grantOverlay(adb)
        try await start(adb)
        return (version, true, false)
    }

    /// Eski kimlikli paket (`LegacyNames`); yeni paket onun yanına kurulur, o kaldırılmaz.
    static var legacyPackage: String { TVApp.legacyAndroidPackage }

    /// Eski paket kuruluysa sürümü (okunamazsa boş), değilse nil.
    func legacyVersion(_ adb: ADBConnection) async throws -> String? {
        let list = try await adb.shell("pm list packages \(Self.legacyPackage)", timeout: timing.command)
        guard Self.listsPackage(list, Self.legacyPackage) else { return nil }
        let dump = try await adb.shell("dumpsys package \(Self.legacyPackage)", timeout: timing.command)
        return Self.installedVersion(dump) ?? ""
    }

    /// `pm list packages` çıktısında tam `package:<ad>` satırı var mı (önek eşleşmesi sayılmaz).
    static func listsPackage(_ output: String, _ name: String) -> Bool {
        output.split(whereSeparator: \.isNewline).contains { $0.trimmingCharacters(in: .whitespaces) == "package:\(name)" }
    }

    /// Eski uygulamanın etkinlik adı bilinmez: başlatıcı kategorisiyle açılır.
    func startLegacy(_ adb: ADBConnection) async throws {
        let out = try await adb.shell("monkey -p \(Self.legacyPackage) -c android.intent.category.LEANBACK_LAUNCHER 1",
                                      timeout: timing.command)
        if out.contains("No activities found") || out.contains("aborted") {
            let again = try await adb.shell("monkey -p \(Self.legacyPackage) -c android.intent.category.LAUNCHER 1",
                                            timeout: timing.command)
            log("ADB: eski uygulama açılışı: \(again.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))")
        }
    }

    /// `cmd package install -S` (Android 7+), olmazsa sync + `pm install`.
    func installAPK(_ adb: ADBConnection, banner: ADBBanner, apk: Data) async throws -> String {
        if banner.features.contains("cmd") {
            do {
                return String(decoding: try await adb.run("exec:cmd package install -r -S \(apk.count)", input: apk,
                                                          timeout: timing.install), as: UTF8.self)
            } catch ADBError.openRefused {
                log("ADB: exec:cmd açılmadı; sync ile denenecek.")
            }
        }
        try await adb.push(apk, to: Self.tempPath, timeout: timing.install)
        let out = try await adb.shell("pm install -r \(Self.tempPath)", timeout: timing.install)
        _ = try? await adb.shell("rm -f \(Self.tempPath)", timeout: timing.command)
        return out
    }

    func grantOverlay(_ adb: ADBConnection, package: String = AndroidTVInstaller.packageName) async {
        do {
            let out = try await adb.shell("appops set \(package) SYSTEM_ALERT_WINDOW allow", timeout: timing.command)
            let t = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { log("ADB: appops: \(t)") }
        } catch {
            log("ADB: katman izni verilemedi (\(error)); kurulum yine başarılı.")
        }
    }

    func start(_ adb: ADBConnection) async throws {
        let out = try await adb.shell("am start -n \(Self.activity)", timeout: timing.command)
        if out.contains("Error") { log("ADB: am start: \(out.trimmingCharacters(in: .whitespacesAndNewlines))") }
    }

    // MARK: Çıktı okuma

    /// `dumpsys package` çıktısındaki `versionName=`; paket yoksa nil.
    public static func installedVersion(_ dumpsys: String) -> String? {
        for line in dumpsys.split(whereSeparator: \.isNewline) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("versionName=") else { continue }
            let v = String(t.dropFirst("versionName=".count)).trimmingCharacters(in: .whitespaces)
            if !v.isEmpty, v != "null" { return v }
        }
        return nil
    }

    /// `pm`/`cmd package install` çıktısı başarısızsa hata.
    static func installProblem(_ output: String) -> Failure? {
        let t = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.split(whereSeparator: \.isNewline).contains(where: { $0.trimmingCharacters(in: .whitespaces) == "Success" }) {
            return nil
        }
        let reason = String((t.isEmpty ? "pm: no output" : t).prefix(500))
        let lower = t.lowercased()
        if lower.contains("insufficient_storage") || lower.contains("not enough space") || lower.contains("enospc") {
            return Failure("NotEnoughSpace", reason)
        }
        return Failure("InstallFailed", reason)
    }
}

/// Ağda TCP 5555'i açık cihazlar (`android-scan`). Yalnız kapı yoklanır; ADB el sıkışması yapılmaz (her cihaza
/// onay kutusu çıkmasın diye), bu yüzden model adı burada bilinmez.
public struct AndroidTVScanner: Sendable {
    let ports: TVPortProbe
    let network: NetworkInterfaceListing
    public var concurrency = 64
    public var timeout: TimeInterval = 0.7

    public init(ports: TVPortProbe, network: NetworkInterfaceListing) {
        self.ports = ports
        self.network = network
    }

    public func scan() async -> [String] {
        let homes = MacAddressPicker.homeNetworks(network.interfaces())
        let own = Set(homes.map(\.address))
        var addresses: [String] = []
        var seen = Set<String>()
        for h in homes {
            for a in IPv4.slash24(of: h.address, excluding: own) where seen.insert(a).inserted { addresses.append(a) }
        }
        let ports = self.ports, timeout = self.timeout
        let found = await withTaskGroup(of: String?.self) { group -> Set<String> in
            var out = Set<String>()
            var it = addresses.makeIterator()
            func addNext() -> Bool {
                guard let a = it.next() else { return false }
                group.addTask { await ports.isOpen(host: a, port: AndroidTVInstaller.port, timeout: timeout) ? a : nil }
                return true
            }
            for _ in 0..<concurrency where !addNext() { break }
            while let r = await group.next() {
                if let r { out.insert(r) }
                if Task.isCancelled { group.cancelAll(); break }
                _ = addNext()
            }
            return out
        }
        return addresses.filter { found.contains($0) }
    }
}
