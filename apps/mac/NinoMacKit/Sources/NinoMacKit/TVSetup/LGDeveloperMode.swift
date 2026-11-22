// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// LG geliştirici modu: Key Server'dan anahtar, ssh ile kurulum, süre uzatma (tv-kurulumu.md §5.1).
public struct LGDeveloperMode: Sendable {
    public struct Timing: Sendable {
        public var portProbe: TimeInterval = 2
        public var keyDownload: TimeInterval = 5
        public var sshCommand: TimeInterval = 30
        public var upload: TimeInterval = 120
        /// Kurulum yanıtı en çok bu kadar beklenir (TV tarafında saniyede bir bakılır).
        public var installWait: Int = 180
        public var verifyInterval: TimeInterval = 2
        public var verifyAfterInstalled: TimeInterval = 30
        public var verifyWithoutResult: TimeInterval = 60
        /// Son uzatmadan bu kadar geçtiyse yeniden uzatılır.
        public var extendAfter: TimeInterval = 20 * 3600
        public init() {}
    }

    public static let sshPort: UInt16 = 9922
    public static let rsaKeyPort: UInt16 = 9991
    static let appInfoPath = appInfoPath(appID: TVApp.lgID)
    static func appInfoPath(appID: String) -> String { "/media/developer/apps/usr/palm/applications/\(appID)/appinfo.json" }
    static let tempFolder = "/media/developer/temp"

    let http: TVHTTP
    let ports: TVPortProbe
    let processes: TVProcessRunning
    let clock: TVClock
    let log: TVInstallLog
    let timing: Timing
    let sshPath: URL
    let sshKeygenPath: URL
    /// Geçici anahtar dosyalarının klasörü.
    let tempDirectory: URL

    public init(http: TVHTTP, ports: TVPortProbe, processes: TVProcessRunning, clock: TVClock = SystemTVClock(),
                log: TVInstallLog, timing: Timing = Timing(),
                sshPath: URL = URL(fileURLWithPath: "/usr/bin/ssh"),
                sshKeygenPath: URL = URL(fileURLWithPath: "/usr/bin/ssh-keygen"),
                tempDirectory: URL = FileManager.default.temporaryDirectory) {
        self.http = http
        self.ports = ports
        self.processes = processes
        self.clock = clock
        self.log = log
        self.timing = timing
        self.sshPath = sshPath
        self.sshKeygenPath = sshKeygenPath
        self.tempDirectory = tempDirectory
    }

    // MARK: 1. Açık mı

    /// SSH (9922) ya da Key Server (9991) 2 sn içinde bağlantı kabul ediyorsa açık.
    public func isEnabled(host: String) async -> Bool {
        async let ssh = ports.isOpen(host: host, port: Self.sshPort, timeout: timing.portProbe)
        async let keyServer = ports.isOpen(host: host, port: Self.rsaKeyPort, timeout: timing.portProbe)
        let (a, b) = await (ssh, keyServer)
        return a || b
    }

    // MARK: 4. Anahtar

    /// Key Server'dan şifreli anahtarı indirir, Passphrase ile parolasını kaldırır. Dönen metin saklanacak anahtar.
    public func fetchKey(host: String, passphrase: String) async throws -> String {
        let url = URL(string: "http://\(host):\(Self.rsaKeyPort)/webos_rsa")!
        let response: TVHTTPResponse
        do {
            response = try await http.get(url, timeout: timing.keyDownload)
        } catch {
            log.write("LG Key Server: \(error)")
            throw TVInstallError(.keyServerOff)
        }
        guard response.status == 200, !response.body.isEmpty else {
            log.write("LG Key Server: HTTP \(response.status)")
            throw TVInstallError(.keyServerOff)
        }
        let file = try writePrivateFile(response.body)
        defer { try? FileManager.default.removeItem(at: file) }
        let result = try await processes.run(sshKeygenPath, arguments: ["-p", "-P", passphrase, "-N", "", "-f", file.path],
                                             input: nil, timeout: 15)
        guard result.exitCode == 0, !result.timedOut, let key = try? String(contentsOf: file, encoding: .utf8) else {
            log.write("LG ssh-keygen: exit \(result.exitCode) \(result.errorOutput.prefix(300))")
            throw TVInstallError(.wrongPassphrase)
        }
        return key
    }

    /// Yalnız sahibine açık (0600) geçici dosya.
    func writePrivateFile(_ data: Data) throws -> URL {
        let url = tempDirectory.appendingPathComponent("nino-lg-\(UUID().uuidString)")
        let fm = FileManager.default
        guard fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw TVInstallError(.installFailed, reason: "temp file")
        }
        try data.write(to: url)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    // MARK: 5. SSH

    static func sshArguments(host: String, keyFile: URL, command: String) -> [String] {
        // webOS geliştirici kipi eski RSA anahtarı ister; bilinen ana makine kaydı tutulmaz.
        let options: [(String, String)] = [
            ("BatchMode", "yes"), ("ConnectTimeout", "6"), ("IdentitiesOnly", "yes"),
            ("StrictHostKeyChecking", "no"), ("UserKnownHostsFile", "/dev/null"), ("LogLevel", "ERROR"),
            ("HostKeyAlgorithms", "+ssh-rsa"), ("PubkeyAcceptedAlgorithms", "+ssh-rsa"),
        ]
        return ["-i", keyFile.path, "-p", String(sshPort)]
            + options.flatMap { ["-o", "\($0.0)=\($0.1)"] }
            + ["prisoner@\(host)", command]
    }

    /// Tek ssh komutu; anahtar geçici 0600 dosyadan verilir, sonra silinir.
    func ssh(host: String, key: String, command: String, input: Data? = nil, timeout: TimeInterval) async throws -> TVProcessResult {
        let file = try writePrivateFile(Data(key.utf8))
        defer { try? FileManager.default.removeItem(at: file) }
        let r = try await processes.run(sshPath, arguments: Self.sshArguments(host: host, keyFile: file, command: command),
                                        input: input, timeout: timeout)
        if r.exitCode == 255 {
            let err = r.errorOutput
            log.write("LG ssh: 255 \(err.prefix(300))")
            if err.contains("Permission denied") { throw TVInstallError(.keyRejected) }
            throw TVInstallError(.unreachable)
        }
        return r
    }

    /// TV'deki uygulama sürümü (`appinfo.json`), yoksa nil.
    /// `appID`: eski kimlikli uygulamanın sürümü için (yeni uygulama onun yanına ayrı kimlikle kurulur).
    public func installedVersion(host: String, key: String, appID: String = TVApp.lgID) async throws -> String? {
        let r = try await ssh(host: host, key: key, command: "cat \(Self.appInfoPath(appID: appID)) 2>/dev/null",
                              timeout: timing.sshCommand)
        return Self.appVersion(inAppInfoJSON: r.output)
    }

    static func appVersion(inAppInfoJSON text: String) -> String? {
        guard let o = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let v = o["version"] as? String, !v.isEmpty else { return nil }
        return v
    }

    public enum InstallResult: Equatable, Sendable {
        /// TV'deki sürüm zaten güncel; kurulmadı.
        case alreadyCurrent(version: String)
        case installed(version: String)
    }

    /// Kurar ya da güncel olduğunu doğrular.
    public func install(host: String, key: String, package: TVAppPackage) async throws -> InstallResult {
        if let current = try await installedVersion(host: host, key: key), TVVersion.isCurrent(current, bundled: package.version) {
            log.write("LG: TV'de \(current) var, paket \(package.version); kurulmadı.")
            return .alreadyCurrent(version: current)
        }
        let remote = "\(Self.tempFolder)/\(package.fileName)"
        let data = try Data(contentsOf: package.url)
        let upload = "mkdir -p \(Self.tempFolder) && rm -f \(Self.tempFolder)/\(TVApp.lgID)_*.ipk \(Self.tempFolder)/nino.ipk && cat > \(Self.shellQuote(remote))"
        let up = try await ssh(host: host, key: key, command: upload, input: data, timeout: timing.upload)
        guard up.exitCode == 0 else {
            throw TVInstallError(.installFailed, reason: Self.clip(up.errorOutput))
        }
        log.write("LG: paket yüklendi (\(package.fileName), \(data.count) bayt).")

        let reply = try await ssh(host: host, key: key, command: Self.installScript(remotePackage: remote, wait: timing.installWait),
                                  timeout: TimeInterval(timing.installWait) + 30)
        let outcome = Self.parseInstallReply(reply.output)
        log.write("LG kurulum yanıtı: \(Self.clip(reply.output))")
        if case let .failure(text) = outcome {
            let problem: TVInstallError.Problem = TVInstallError.mentionsNoSpace(text) ? .noSpace : .installFailed
            throw TVInstallError(problem, reason: Self.clip(text))
        }

        let window = outcome == .success ? timing.verifyAfterInstalled : timing.verifyWithoutResult
        let deadline = clock.now().addingTimeInterval(window)
        while true {
            if let v = try? await installedVersion(host: host, key: key), TVVersion.isCurrent(v, bundled: package.version) {
                _ = try? await ssh(host: host, key: key, command: "rm -f \(Self.shellQuote(remote))", timeout: timing.sshCommand)
                return .installed(version: v)
            }
            if clock.now() >= deadline { break }
            try await clock.sleep(timing.verifyInterval)
        }
        let detail = TVSetupText.versionNotVisible(package.version, reply: Self.clip(reply.output, limit: 300))
        let problem: TVInstallError.Problem = TVInstallError.mentionsNoSpace(reply.output) ? .noSpace : .installFailed
        throw TVInstallError(problem, reason: detail)
    }

    /// TV'de çalışan betik: kurulum aboneliği uzun bir `sleep`'ten beslenir, yanıtlar geçici günlüğe yazılır;
    /// saniyede bir sonuç aranır, bulununca ya da süre dolunca yanıtlar okunur, süreç kapatılır.
    static func installScript(remotePackage: String, wait: Int) -> String {
        let payload = "{\"id\":\"com.ares.defaultName\",\"ipkUrl\":\"\(remotePackage)\",\"subscribe\":true}"
        let log = "\(tempFolder)/nino-install.log"
        return [
            "rm -f \(log)",
            "(sleep \(wait + 20)) | luna-send-pub -i 'luna://com.webos.appInstallService/dev/install' '\(payload)' > \(log) 2>&1 &",
            "P=$!",
            "i=0",
            "while [ $i -lt \(wait) ]; do if grep -qiE 'installed|success|failed|\"returnValue\": *false' \(log) 2>/dev/null; then break; fi; sleep 1; i=$((i+1)); done",
            "sleep 1",
            "cat \(log)",
            "kill $P 2>/dev/null",
            "rm -f \(log)",
        ].joined(separator: "; ")
    }

    enum InstallReply: Equatable {
        case success
        case failure(String)
        case unknown
    }

    /// Satırlar JSON'a birleştirilir; ilk hata ya da başarı belirleyicidir.
    static func parseInstallReply(_ text: String) -> InstallReply {
        var sawSuccess = false
        for object in jsonObjects(in: text) {
            if (object["returnValue"] as? Bool) == false {
                let msg = (object["errorText"] as? String) ?? (object["errorMessage"] as? String) ?? ""
                let code = object["errorCode"].map { "\($0)" }
                return .failure([msg, code.map { "(\($0))" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
            }
            if let details = object["details"] as? [String: Any] {
                let state = (details["state"] as? String ?? "").lowercased()
                if state.contains("failed") {
                    let reason = (details["reason"] as? String) ?? (details["errorText"] as? String) ?? state
                    let code = details["errorCode"].map { "\($0)" }
                    return .failure([reason, code.map { "(\($0))" }].compactMap { $0 }.joined(separator: " "))
                }
                if state.contains("installed") || state.hasPrefix("success") { sawSuccess = true }
            }
            if let state = (object["state"] as? String)?.lowercased(), state.contains("installed") || state.hasPrefix("success") {
                sawSuccess = true
            }
        }
        return sawSuccess ? .success : .unknown
    }

    /// Metindeki ardışık JSON nesneleri (satırlara bölünmüş olabilir).
    static func jsonObjects(in text: String) -> [[String: Any]] {
        var out: [[String: Any]] = []
        var depth = 0
        var current = ""
        var inString = false
        var escaped = false
        for ch in text {
            if depth == 0 && ch != "{" { continue }
            current.append(ch)
            if inString {
                if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
                continue
            }
            if ch == "\"" { inString = true } else if ch == "{" { depth += 1 } else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    if let o = (try? JSONSerialization.jsonObject(with: Data(current.utf8))) as? [String: Any] { out.append(o) }
                    current = ""
                }
            }
        }
        return out
    }

    // MARK: 7. Süre uzatma

    public struct Extension: Equatable, Sendable {
        /// Kalan süre (saat); okunamadıysa nil.
        public var hoursLeft: Int?
    }

    /// Süreyi uzatır. Başarısızlık sessizdir (nil).
    public func extendSession(host: String, key: String) async -> Extension? {
        guard let r = try? await ssh(host: host, key: key, command: "cat /var/luna/preferences/devmode_enabled",
                                     timeout: timing.sshCommand) else { return nil }
        let token = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.contains(where: \.isWhitespace),
              let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let reset = URL(string: "https://developer.lge.com/secure/ResetDevModeSession.dev?sessionToken=\(encoded)"),
              let check = URL(string: "https://developer.lge.com/secure/CheckDevModeSession.dev?sessionToken=\(encoded)")
        else { return nil }
        guard let rr = try? await http.get(reset, timeout: 10), rr.text.lowercased().contains("success") else {
            log.write("LG: geliştirici modu süresi uzatılamadı.")
            return nil
        }
        let hours = (try? await http.get(check, timeout: 10)).flatMap { Self.hoursLeft($0.text) }
        log.write("LG: geliştirici modu süresi uzatıldı\(hours.map { " (\($0) saat)" } ?? "").")
        return Extension(hoursLeft: hours)
    }

    /// Yanıttaki `ss:dd:sn` biçimli kalan sürenin saati.
    static func hoursLeft(_ text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "(\\d+):(\\d{2}):(\\d{2})") else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Int(ns.substring(with: m.range(at: 1)))
    }

    /// Son uzatmanın anı, TV adresine göre (küçük harf, boşluksuz) UserDefaults'ta.
    public static func extensionDefaultsKey(host: String) -> String {
        "lgDevModeExtended." + host.lowercased().filter { !$0.isWhitespace }
    }

    // MARK: Yardımcılar

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func clip(_ s: String, limit: Int = 500) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > limit ? String(t.prefix(limit)) : t
    }
}
