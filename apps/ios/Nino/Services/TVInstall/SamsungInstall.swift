// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// Samsung (Tizen): geliştirici modu açık TV'ye sdb (26101) ile bağlanma, TV'ye özel sertifikayla imzalanan .wgt'yi
// gönderme, vd_appinstall ile kurma ve was_execute ile açma. İlk kurulumda Samsung hesabıyla giriş gerekir.

enum SamsungProblem: Equatable, Sendable {
    /// Geliştirici modu kapalı ya da Host PC IP bu telefonun değil.
    case unreachable
    case loginFailed, certificateFailed, tooOld, installFailed, notEnoughSpace, certificateMismatch, certificateRejected,
         clockBehind, packageBlocked, connectionLost, packageMissing
}

struct SamsungFailure: Error, CustomStringConvertible {
    var problem: SamsungProblem
    var detail: String?
    var description: String { "\(problem)" + (detail.map { ": \($0)" } ?? "") }
}

// MARK: - Yanıtları okuma

enum SamsungReplies {
    enum Outcome: Equatable { case ok, connectionLost, notEnoughSpace, mismatch, rejected, notYetValid, blocked, incompatible, other }

    private static func has(_ text: String, _ token: String) -> Bool { text.range(of: token, options: .caseInsensitive) != nil }

    static func outcome(_ text: String) -> Outcome {
        let lost = has(text, "transport connection") || has(text, "connection reset by peer") || has(text, "broken pipe")
        let failed = lost || has(text, "install failed") || has(text, "val[fail]") || has(text, "not enough space")
            || has(text, "download failed[116]")
        guard failed else { return .ok }
        if lost { return .connectionLost }
        if ["install failed[118, -4]", "install failed[118, -19]", "install failed[118019]"].contains(where: { has(text, $0) }) {
            return .incompatible
        }
        if has(text, "download failed[116]") || has(text, "not enough space") { return .notEnoughSpace }
        let certCode = ["install failed[118, -12]", "install failed[118012]", "install failed[118, -11]", "install failed[118011]"]
            .contains { has(text, $0) }
        if certCode && has(text, "check certificate error") && !has(text, "same id and different certificate") {
            return has(text, "not valid yet") ? .notYetValid : .rejected
        }
        if certCode || has(text, "author certificate not match") { return .mismatch }
        if has(text, "install failed[118, -22]") || has(text, "install failed[118022]") { return .blocked }
        return .other
    }

    /// Eski kopyayı silmek işe yarayabilir mi?
    static func removalMayHelp(_ o: Outcome) -> Bool { [.mismatch, .blocked, .other].contains(o) }

    static func problem(_ o: Outcome) -> SamsungProblem {
        switch o {
        case .connectionLost: .connectionLost
        case .notEnoughSpace: .notEnoughSpace
        case .mismatch: .certificateMismatch
        case .rejected: .certificateRejected
        case .notYetValid: .clockBehind
        case .blocked: .packageBlocked
        default: .installFailed
        }
    }

    /// Hata satırlarından kısa özet.
    static func summary(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return "no answer from the TV" }
        var picked: [String] = []
        for l in lines where ["fail", "error", "reason", "not match", "space"].contains(where: { has(l, $0) }) && !picked.contains(l) {
            picked.append(l)
            if picked.count == 3 { break }
        }
        return TVInstallLog.short((picked.isEmpty ? Array(lines.suffix(3)) : picked).joined(separator: " | "), limit: 400)
    }

    /// `0 vd_applist` çıktısındaki Nino sürümü. Kayıtlar `----` satırlarıyla ayrılır, alanlar `ad = değer`.
    static func installedVersion(_ listing: String) -> String? {
        var record: [String: String] = [:]
        func ninoVersion() -> String? {
            let ids = [record["app_tizen_id"], record["app_id"]].compactMap { $0?.trimmingCharacters(in: .whitespaces).lowercased() }
            guard ids.contains(SamsungInstaller.appID.lowercased()) || ids.contains(SamsungInstaller.packageID.lowercased()),
                  let v = record["app_version"], !v.isEmpty else { return nil }
            return v
        }
        for raw in listing.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n") {
            if !raw.contains("="), raw.contains("----") {
                if let v = ninoVersion() { return v }
                record = [:]
                continue
            }
            guard let eq = raw.firstIndex(of: "=") else { continue }
            let key = raw[..<eq].trimmingCharacters(in: CharacterSet(charactersIn: " -\t")).lowercased()
            let value = raw[raw.index(after: eq)...].trimmingCharacters(in: CharacterSet(charactersIn: " -\t"))
            if !key.isEmpty { record[key] = value }
        }
        return ninoVersion()
    }
}

// MARK: - TV bilgisi (8001)

/// `http://TV:8001/api/v2/`: ad, model ve geliştirici modu (açık mı, Host PC IP'si).
struct SamsungTVInfo: Equatable, Sendable {
    var name: String?
    var model: String?
    var developerMode: Bool?
    var developerIP: String?

    static func parse(_ data: Data) -> SamsungTVInfo? {
        struct Reply: Decodable {
            struct Device: Decodable {
                var name: String?
                var modelName: String?
                var developerMode: String?
                var developerIP: String?
            }
            var device: Device
        }
        guard let d = try? JSONDecoder().decode(Reply.self, from: data).device else { return nil }
        func clean(_ v: String?) -> String? {
            guard let t = v?.replacingOccurrences(of: "&quot;", with: "\"").trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
            return t
        }
        let mode = clean(d.developerMode).map { ["1", "true"].contains($0.lowercased()) }
        let ip = clean(d.developerIP).flatMap { $0 == "0.0.0.0" ? nil : $0 }
        return SamsungTVInfo(name: clean(d.name), model: clean(d.modelName), developerMode: mode, developerIP: ip)
    }

    static func fetch(host: String, timeout: TimeInterval = 1.5) async -> SamsungTVInfo? {
        var c = URLComponents()
        c.scheme = "http"
        c.host = host
        c.port = 8001
        c.path = "/api/v2/"
        guard let url = c.url else { return nil }
        var r = URLRequest(url: url)
        r.timeoutInterval = timeout
        guard let (data, _) = try? await URLSession.shared.data(for: r) else { return nil }
        return parse(data)
    }
}

// MARK: - Samsung girişi

/// Samsung hesabıyla giriş: Samsung'un giriş kapısı sayfası hesap bilgisini `http://localhost:4794/signin/callback`'e
/// POST eder (Tizen Studio'nun kullandığı adres). Bu adresi uygulamadaki küçük dinleyici karşılar.
enum SamsungSignIn {
    static let callbackPort: UInt16 = 4794
    static let callbackPath = "/signin/callback"
    static let state = "accountcheckdogeneratedstatetext"

    /// Tizen Studio'nun giriş kapısı (istemci kimliği ve yol Samsung'un).
    static var pageURL: URL {
        let back = "http://localhost:\(callbackPort)\(callbackPath)"
        let query = [("locale", ""), ("clientId", "v285zxnl3h"), ("redirect_uri", back), ("state", state), ("tokenType", "TOKEN")]
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&")
        return URL(string: "https://account.samsung.com/accounts/be1dce529476c1a6d407c4c7578c31bd/signInGate?" + query)!
    }

    /// Gövde `code=<JSON>&state=…`; JSON'da access_token, userId, inputEmailID.
    static func account(fromForm body: String) -> SamsungAccount? {
        var fields: [String: String] = [:]
        for part in body.split(separator: "&") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            // "code" içindeki '+' boşluğa çevrilmez (JSON'un kendisi).
            fields[kv[0]] = kv[0] == "code" ? (kv[1].removingPercentEncoding ?? kv[1])
                : (kv[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? kv[1])
        }
        struct Code: Decodable {
            var access_token: String?
            var userId: String?
            var inputEmailID: String?
        }
        guard fields["state"] == state, let code = fields["code"],
              let decoded = try? JSONDecoder().decode(Code.self, from: Data(code.utf8)),
              let token = decoded.access_token, !token.isEmpty,
              let user = decoded.userId, !user.isEmpty else { return nil }
        return SamsungAccount(accessToken: token, userID: user, email: decoded.inputEmailID ?? "")
    }

    /// Yalnız 127.0.0.1'de dinler; `cancel()` beklemeyi bitirir.
    final class Listener: @unchecked Sendable {
        private let fd: LockedValue<Int32>
        let port: UInt16

        init(port: UInt16 = SamsungSignIn.callbackPort) throws {
            let s = socket(AF_INET, SOCK_STREAM, 0)
            guard s >= 0 else { throw SamsungFailure(problem: .loginFailed, detail: "socket") }
            var on: Int32 = 1
            setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            let ok = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            } == 0 && listen(s, 4) == 0
            guard ok else {
                let why = String(cString: strerror(errno))
                Darwin.close(s)
                throw SamsungFailure(problem: .loginFailed, detail: "localhost:\(port) could not be opened: \(why)")
            }
            var bound = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to: &bound) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(s, $0, &len) } }
            self.port = UInt16(bigEndian: bound.sin_port)
            fd = LockedValue(s)
        }

        func wait(timeout: TimeInterval) throws -> SamsungAccount {
            defer { cancel() }
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                let s = fd.get()
                guard s >= 0 else { throw SamsungFailure(problem: .loginFailed, detail: "sign-in cancelled") }
                var p = pollfd(fd: s, events: Int16(POLLIN), revents: 0)
                guard poll(&p, 1, 400) > 0 else { continue }
                let client = accept(s, nil, nil)
                guard client >= 0 else { continue }
                let channel = TCPChannel(acceptedDescriptor: client)
                channel.receiveTimeout = 10
                defer { channel.shutdown() }
                let (method, path, body) = Self.readRequest(channel)
                let isCallback = method == "POST" && path.hasPrefix(SamsungSignIn.callbackPath)
                let account = isCallback ? SamsungSignIn.account(fromForm: body) : nil
                Self.respond(channel, status: account != nil ? 200 : isCallback ? 400 : 404)
                if let account { return account }
            }
            throw SamsungFailure(problem: .loginFailed, detail: "sign-in not finished in \(Int(timeout / 60)) min")
        }

        func cancel() {
            let s = fd.swap(-1)
            if s >= 0 { Darwin.close(s) }
        }

        private static func readRequest(_ c: TCPChannel) -> (String, String, String) {
            var data = Bytes()
            var headerEnd: Int?
            while headerEnd == nil {
                guard let chunk = try? c.receive(upTo: 16_384), data.count < 1 << 20 else { return ("", "", "") }
                data += chunk
                if data.count >= 4 {
                    headerEnd = (0...(data.count - 4)).first { data[$0] == 13 && data[$0 + 1] == 10 && data[$0 + 2] == 13 && data[$0 + 3] == 10 }
                }
            }
            let head = String(decoding: data[..<headerEnd!], as: UTF8.self).components(separatedBy: "\r\n")
            let first = head[0].split(separator: " ").map(String.init)
            let length = head.compactMap { line -> Int? in
                guard line.lowercased().hasPrefix("content-length:") else { return nil }
                return Int(line.dropFirst(15).trimmingCharacters(in: .whitespaces))
            }.first ?? 0
            var body = Array(data[(headerEnd! + 4)...])
            while body.count < length, let more = try? c.receive(upTo: 16_384) { body += more }
            return (first.first ?? "", first.count > 1 ? first[1] : "", String(decoding: body, as: UTF8.self))
        }

        private static func respond(_ c: TCPChannel, status: Int) {
            let html = status == 200
                ? "<!doctype html><meta charset=utf-8><meta name=viewport content=\"width=device-width\"><title>Nino</title><body style=\"font-family:system-ui;padding:2em\"><h2>✓</h2><p>Nino</p>"
                : "Not found"
            let phrase = [200: "OK", 400: "Bad Request"][status] ?? "Not Found"
            let body = Bytes(html.utf8)
            let lines = ["HTTP/1.1 \(status) \(phrase)", "Content-Type: text/html; charset=utf-8", "Content-Length: \(body.count)",
                         "Connection: close", "", ""]
            try? c.send(Bytes(lines.joined(separator: "\r\n").utf8) + body)
        }
    }
}

// MARK: - sdb

/// sdb istemcisi (Samsung'un geliştirici modu, 26101).
final class SdbClient: WireLink {
    static let port: UInt16 = 26101
    private(set) var banner = ""

    /// Samsung'un sdbd'si yeni bağlantıyı bazen el sıkışmanın ortasında kapatır; üç kez denenir.
    static func connect(host: String, identity: AdbIdentity, port: UInt16 = port, timeout: TimeInterval = 8) throws -> SdbClient {
        var last: Error = WireError.connect("sdb")
        for attempt in 0..<3 {
            do {
                let tcp = try TCPChannel(host: host, port: port, timeout: timeout)
                let client = SdbClient(channel: tcp, verifySum: true, firstLocalID: 0x60)
                do {
                    try client.handshake(identity)
                    return client
                } catch {
                    client.close()
                    throw error
                }
            } catch {
                last = error
                if attempt < 2 { Thread.sleep(forTimeInterval: 0.4) }
            }
        }
        throw last
    }

    private func handshake(_ identity: AdbIdentity) throws {
        channel.receiveTimeout = 15
        try send(WireMessage(command: WireMessage.connect, arg0: 0x0100_0000, arg1: UInt32(maxPayload),
                             payload: Bytes("host::sdb-net-client".utf8)))
        while true {
            let m = try receive()
            switch m.command {
            case WireMessage.connect:
                if m.arg1 > 0 { maxPayload = min(maxPayload, Int(m.arg1)) }
                banner = String(decoding: m.payload, as: UTF8.self)
                channel.receiveTimeout = 120
                return
            case WireMessage.auth where m.arg0 == 1:
                try send(WireMessage(command: WireMessage.auth, arg0: 2, arg1: 0, payload: try identity.signSdbToken(m.payload)))
            case WireMessage.auth where m.arg0 == 3:
                try send(WireMessage(command: WireMessage.auth, arg0: 3, arg1: 0, payload: Bytes((identity.publicKeyLine + "\u{0}").utf8)))
            default:
                throw WireError.malformed("sdb: \(m.name) during handshake")
            }
        }
    }

    func shell(_ command: String) throws -> String { try run("shell:" + command) }

    /// `capability:` yanıtı: iki bayt uzunluk, sonra `anahtar:değer` satırları.
    func capabilities() throws -> [String: String] { Self.parseCapabilities(Bytes(try run("capability:").utf8)) }

    static func parseCapabilities(_ bytes: Bytes) -> [String: String] {
        guard bytes.count >= 2 else { return [:] }
        var out: [String: String] = [:]
        for line in String(decoding: bytes[2...], as: UTF8.self).split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]), value = String(line[line.index(after: colon)...])
            if !key.isEmpty, !value.isEmpty, !value.contains(":"), out[key] == nil { out[key] = value }
        }
        return out
    }
}

// MARK: - Kurulum

struct SamsungInstaller {
    static let appID = "NinoTVApps.Nino"
    static let packageID = "NinoTVApps"
    static let minimumTizen = "2.4"
    /// Bu sürüme kadarki Tizen'lerde cihaz profili ayrıca gönderilir.
    static let deviceProfileUpTo = "4.0"

    var host: String
    var files: TVInstallFiles
    var log: TVInstallLog
    /// Samsung girişi: hesabı döner (bloklar). nil: giriş yapılamaz (sessiz denetim).
    var signIn: (() throws -> SamsungAccount)?
    var stage: (InstallStage) -> Void = { _ in }
    var certificates: SamsungCertificateService
    var sdbPort: UInt16 = SdbClient.port

    init(host: String, files: TVInstallFiles, log: TVInstallLog, signIn: (() throws -> SamsungAccount)?) {
        self.host = host
        self.files = files
        self.log = log
        self.signIn = signIn
        certificates = SamsungCertificateService(log: log)
    }

    static func isTooOld(_ platform: String) -> Bool { !platform.isEmpty && VersionOrder.isNewer(minimumTizen, than: platform) }
    static func needsDeviceProfile(_ platform: String) -> Bool {
        !platform.isEmpty && !isTooOld(platform) && !VersionOrder.isNewer(platform, than: deviceProfileUpTo)
    }
    static func isDUID(_ text: String) -> Bool { text.range(of: #"^[A-Za-z0-9_\-+=/]{8,}$"#, options: .regularExpression) != nil }

    func profile(for duid: String) -> SamsungProfile {
        let safe = duid.replacingOccurrences(of: #"[^A-Za-z0-9_\-]"#, with: "_", options: .regularExpression)
        return SamsungProfile(folder: files.samsung.appendingPathComponent(safe, isDirectory: true))
    }

    private func connect() throws -> SdbClient {
        do {
            let client = try SdbClient.connect(host: host, identity: try AdbIdentity.stored(in: files.sdb), port: sdbPort)
            log.write("sdb connected (\(host):\(sdbPort)).")
            return client
        } catch {
            throw SamsungFailure(problem: .unreachable, detail: "sdb \(host):\(sdbPort): \(error)")
        }
    }

    func installedVersion() throws -> String? {
        let tv = try connect()
        defer { tv.close() }
        return readVersion(tv)
    }

    func install(wgt: () throws -> TVPackage) throws -> TVInstallOutcome {
        log.write("--- Samsung: \(host)")
        do {
            let outcome = try perform(wgt: wgt)
            log.write(outcome.installed ? "Installed \(outcome.version)." : "TV already has \(outcome.version).")
            return outcome
        } catch let failure as SamsungFailure {
            log.write("FAILED \(failure)")
            throw failure
        } catch let error as WireError {
            log.write("Connection lost: \(error)")
            throw SamsungFailure(problem: .connectionLost, detail: error.description)
        }
    }

    private func perform(wgt: () throws -> TVPackage) throws -> TVInstallOutcome {
        stage(.connecting)
        let tv = try connect()
        defer { tv.close() }
        stage(.reading)
        let caps = try tv.capabilities()
        let platform = caps["platform_version"]?.trimmingCharacters(in: .whitespaces) ?? ""
        let toolPath = caps["sdk_toolpath"].map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
            ?? "/opt/usr/apps/tmp"
        log.write("Tizen \(platform.isEmpty ? "?" : platform), sdk_toolpath \(toolPath)")
        if Self.isTooOld(platform) { throw SamsungFailure(problem: .tooOld, detail: "Tizen \(platform)") }

        let package: TVPackage
        do {
            package = try wgt()
        } catch {
            throw SamsungFailure(problem: .packageMissing, detail: "\(error)")
        }
        let onTV = readVersion(tv)
        if let onTV, !VersionOrder.isNewer(package.version, than: onTV) {
            launch(tv)
            return TVInstallOutcome(version: onTV, installed: false)
        }

        let duid = try readDUID(tv)
        log.write("DUID \(duid)")
        var profile = profile(for: duid)
        log.write("Saved certificate: \(profile.summary(duid))")
        if !profile.isUsable() || !profile.belongs(to: duid) {
            guard let signIn else { throw SamsungFailure(problem: .loginFailed, detail: "sign-in needed") }
            stage(.signIn)
            let account = try signIn()
            log.write("Signed in to Samsung; requesting certificates.")
            stage(.certificate)
            profile = try certificates.issue(duid: duid, account: account, into: profile)
            log.write("New certificate: \(profile.summary(duid))")
        }
        if Self.needsDeviceProfile(platform) { pushDeviceProfile(tv, profile, toolPath) }

        stage(.signing)
        let key = try profile.key()
        let signed = try WidgetSigner.sign(package.bytes,
                                           author: .init(key: key, chain: SamsungCertificateService.chain(for: try profile.author())),
                                           distributor: .init(key: key, chain: SamsungCertificateService.chain(for: try profile.distributor())))
        log.write("Signed the package (\(signed.count) bytes).")
        stage(.installing)
        do {
            try installRecovering(tv, signed, toolPath)
        } catch let failure as SamsungFailure {
            if failure.problem == .certificateRejected {
                profile.setAside()
                log.write("Set the saved certificate aside; the next try fetches a new one.")
            }
            throw failure
        }
        let after = readVersion(tv)
        if let after, VersionOrder.isNewer(package.version, than: after) {
            throw SamsungFailure(problem: .installFailed, detail: "the TV still has \(after) after installing \(package.version)")
        }
        launch(tv)
        return TVInstallOutcome(version: after ?? package.version, installed: true)
    }

    private func installOnce(_ tv: SdbClient, _ signed: Bytes, _ toolPath: String) -> String {
        let remote = "\(toolPath)/nino-\(UUID().uuidString.prefix(8).lowercased()).wgt"
        var out = ""
        do {
            try SyncProtocol.push(signed, to: remote, over: tv, mode: nil, doneCarriesLength: true)
            out += "pushed \(remote)\n"
            out += try tv.shell("0 vd_appinstall \(Self.appID) \(remote)")
        } catch {
            out += "\ninstall failed: \(error)\n"
        }
        return out
    }

    private func installRecovering(_ tv: SdbClient, _ signed: Bytes, _ toolPath: String) throws {
        let first = installOnce(tv, signed, toolPath)
        log.write("vd_appinstall:\n\(TVInstallLog.short(first, limit: 2000))")
        let o = SamsungReplies.outcome(first)
        if o == .ok { return }
        guard SamsungReplies.removalMayHelp(o) else {
            throw SamsungFailure(problem: SamsungReplies.problem(o), detail: SamsungReplies.summary(first))
        }
        stage(.uninstalling)
        for id in [Self.packageID, Self.appID] {
            log.write("vd_appuninstall \(id): \(TVInstallLog.short((try? tv.shell("0 vd_appuninstall \(id)")) ?? "?"))")
        }
        stage(.installing)
        let second = installOnce(tv, signed, toolPath)
        log.write("vd_appinstall (2):\n\(TVInstallLog.short(second, limit: 2000))")
        let o2 = SamsungReplies.outcome(second)
        if o2 != .ok { throw SamsungFailure(problem: SamsungReplies.problem(o2), detail: SamsungReplies.summary(second)) }
    }

    private func readVersion(_ tv: SdbClient) -> String? {
        guard let listing = try? tv.shell("0 vd_applist") else {
            log.write("vd_applist unreadable")
            return nil
        }
        let v = SamsungReplies.installedVersion(listing)
        log.write("vd_applist: \(v.map { "Nino \($0)" } ?? "no Nino")")
        return v
    }

    private func launch(_ tv: SdbClient) {
        stage(.launching)
        log.write("Launch: \(TVInstallLog.short((try? tv.shell("0 was_execute \(Self.appID)")) ?? "failed"))")
    }

    private func pushDeviceProfile(_ tv: SdbClient, _ profile: SamsungProfile, _ toolPath: String) {
        guard let data = try? Data(contentsOf: profile.deviceProfileFile) else { return }
        do {
            try SyncProtocol.push(Bytes(data), to: "\(toolPath)/device-profile.xml", over: tv, mode: nil, doneCarriesLength: true)
            log.write("Device profile sent.")
        } catch {
            log.write("Device profile not sent: \(error)")
        }
    }

    private func readDUID(_ tv: SdbClient) throws -> String {
        var last = ""
        for _ in 0..<3 {
            last = (try? tv.shell("0 getduid")) ?? ""
            let first = last.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if Self.isDUID(first) { return first }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw SamsungFailure(problem: .unreachable, detail: "TV id (DUID) unreadable: \(last.isEmpty ? "empty" : last)")
    }
}
