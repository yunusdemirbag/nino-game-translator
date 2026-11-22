// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CommonCrypto
import CryptoKit
import Foundation

// LG (webOS) geliştirici modu: anahtar TV'deki Key Server'dan (9991) bir kez alınır ve TV ekranındaki parolayla çözülür;
// paket 9922'deki SSH'ye "cat > dosya" ile yüklenir, appInstallService ile kurulur, applicationManager ile açılır.
// Geliştirici modunun 1000 saatlik süresi LG'nin sunucusundan günde bir kez yenilenir.

enum LGProblem: Equatable, Sendable {
    case unreachable, keyServerOff, wrongPassphrase, keyRefused, notEnoughSpace, installFailed, connectionLost, packageMissing
}

struct LGFailure: Error, CustomStringConvertible {
    var problem: LGProblem
    var detail: String?
    var description: String { "\(problem)" + (detail.map { ": \($0)" } ?? "") }
}

/// Key Server'ın verdiği eski biçim (Proc-Type: 4,ENCRYPTED) parolalı PEM'i çözer.
enum LegacyPEM {
    static func isEncrypted(_ pem: String) -> Bool { pem.contains("Proc-Type: 4,ENCRYPTED") }

    /// Parolasız PKCS#1 DER döner; parola yanlışsa `wrongPassphrase`.
    static func decrypt(_ pem: String, passphrase: String) throws -> Bytes {
        guard let dek = firstCapture(#"DEK-Info:\s*([A-Za-z0-9-]+),([0-9A-Fa-f]+)"#, pem),
              let ivHex = pem.range(of: #"DEK-Info:\s*[A-Za-z0-9-]+,([0-9A-Fa-f]+)"#, options: .regularExpression)
                .map({ String(pem[$0]).split(separator: ",").last.map(String.init) ?? "" }),
              let iv = Bytes(hex: ivHex) else {
            throw LGFailure(problem: .installFailed, detail: "PEM header unreadable")
        }
        let body = pem.components(separatedBy: "\n").filter { !$0.hasPrefix("-----") && !$0.contains(":") }.joined()
        guard let encrypted = Data(base64Encoded: body.filter { !$0.isWhitespace }).map(Bytes.init) else {
            throw LGFailure(problem: .installFailed, detail: "PEM body unreadable")
        }
        let (algorithm, keyLength, blockSize): (CCAlgorithm, Int, Int) = switch dek.uppercased() {
        case "AES-128-CBC": (CCAlgorithm(kCCAlgorithmAES), 16, 16)
        case "AES-192-CBC": (CCAlgorithm(kCCAlgorithmAES), 24, 16)
        case "AES-256-CBC": (CCAlgorithm(kCCAlgorithmAES), 32, 16)
        case "DES-EDE3-CBC": (CCAlgorithm(kCCAlgorithm3DES), 24, 8)
        default: throw LGFailure(problem: .installFailed, detail: "unsupported cipher \(dek)")
        }
        guard iv.count == blockSize else { throw LGFailure(problem: .installFailed, detail: "bad IV") }
        let key = bytesToKey(password: Bytes(passphrase.utf8), salt: Array(iv.prefix(8)), length: keyLength)
        var out = Bytes(repeating: 0, count: encrypted.count + blockSize)
        var moved = 0
        let options = CCOptions(kCCOptionPKCS7Padding)
        let status = CCCrypt(CCOperation(kCCDecrypt), algorithm, options, key, key.count, iv, encrypted, encrypted.count,
                             &out, out.count, &moved)
        // Yanlış parolada dolgu çoğunlukla bozuk çıkar; tutarsa da sonuç tek bir DER dizisi olmalı.
        guard status == kCCSuccess else { throw LGFailure(problem: .wrongPassphrase) }
        let plain = Array(out.prefix(moved))
        guard isSingleSequence(plain) else { throw LGFailure(problem: .wrongPassphrase) }
        return plain
    }

    /// OpenSSL EVP_BytesToKey (MD5, tek tur).
    static func bytesToKey(password: Bytes, salt: Bytes, length: Int) -> Bytes {
        var out = Bytes(), block = Bytes()
        while out.count < length {
            block = Bytes(Insecure.MD5.hash(data: block + password + salt))
            out += block
        }
        return Array(out.prefix(length))
    }

    private static func isSingleSequence(_ der: Bytes) -> Bool {
        guard let items = try? ASN1.parse(der), items.count == 1, items[0].tag == 0x30 else { return false }
        return true
    }
}

/// TV'de komut çalıştırır (SSH; testlerde sahtesi).
protocol LGShell {
    func run(_ command: String, input: Bytes?) throws -> (status: Int, output: String)
}

/// Her komut ayrı SSH bağlantısıyla (geliştirici modunun sunucusu uzun oturumları kesebiliyor).
struct LGSSHShell: LGShell {
    var host: String
    var key: RSAPrivateKey
    var port: UInt16 = LGInstaller.sshPort

    func run(_ command: String, input: Bytes?) throws -> (status: Int, output: String) {
        let session: SSHSession
        do {
            session = try SSHSession.connect(host: host, port: port, user: "prisoner", key: key)
        } catch let f as SSHFailure {
            throw LGFailure(problem: f.kind == .auth ? .keyRefused : .unreachable, detail: f.description)
        }
        defer { session.close() }
        do {
            let r = try session.exec(command, input: input)
            return (r.status ?? -1, r.text)
        } catch {
            throw LGFailure(problem: .connectionLost, detail: "\(error)")
        }
    }
}

struct LGInstaller {
    static let sshPort: UInt16 = 9922
    static let keyServerPort: UInt16 = 9991
    static let appID = "com.ninotranslator.tv"
    static let tempDir = "/media/developer/temp"
    static let appInfoPath = "/media/developer/apps/usr/palm/applications/\(appID)/appinfo.json"
    static let sessionTokenPath = "/var/luna/preferences/devmode_enabled"

    var shell: LGShell
    var log: TVInstallLog
    var stage: (InstallStage) -> Void = { _ in }
    var pollInterval: TimeInterval = 2
    var installWait = 180
    var verifyWait: TimeInterval?
    /// LG'nin sunucusuna istek (testlerde değiştirilir).
    var fetch: (URL) throws -> Data = { try BlockingHTTP.get($0, timeout: 10) }

    // MARK: Yardımcılar (testli)

    static func keyURL(_ host: String) -> URL? {
        var c = URLComponents()
        c.scheme = "http"
        c.host = host
        c.port = Int(keyServerPort)
        c.path = "/webos_rsa"
        return c.url
    }

    static func version(fromAppInfo text: String) -> String? { firstCapture(#""version"\s*:\s*"([^"]+)""#, text) }

    /// Kalan süre yanıtında `999:58:40` biçiminde; saat kısmı.
    static func remainingHours(_ text: String) -> Int? {
        firstCapture(#"(\d{1,4}):\d{2}:\d{2}"#, text).flatMap { Int($0) }
    }

    /// Key Server yanıtından parolasız RSA anahtarı (PKCS#1 DER).
    static func decodeKey(_ response: Bytes, passphrase: String) throws -> Bytes {
        let text = String(decoding: response, as: UTF8.self)
        guard text.contains("PRIVATE KEY") else { throw LGFailure(problem: .keyServerOff, detail: "Key Server sent something else") }
        if LegacyPEM.isEncrypted(text) {
            let typed = passphrase.trimmingCharacters(in: .whitespaces)
            do {
                return try LegacyPEM.decrypt(text, passphrase: typed)
            } catch let f as LGFailure where f.problem == .wrongPassphrase && typed != typed.uppercased() {
                return try LegacyPEM.decrypt(text, passphrase: typed.uppercased())
            }
        }
        guard let key = try? RSAPrivateKey(pem: response) else {
            throw LGFailure(problem: .keyServerOff, detail: "key format not supported")
        }
        return try key.pkcs1()
    }

    /// Kurulum komutu. luna-send'in abonelik yanıtları bir dosyaya akar; dosyada sonuç görünene, luna-send bitene ya da
    /// `wait` saniye dolana dek beklenir, sonra dosya basılır. (luna-send'in girdisi açık kalsın diye önüne `sleep` konur.)
    static func installCommand(remote: String, wait: Int) -> String {
        let out = "\(tempDir)/nino-ipk-reply.txt"
        let request = "{\"id\":\"com.ares.defaultName\",\"ipkUrl\":\"\(remote)\",\"subscribe\":true}"
        let finished = "grep -qi -e '\"state\" *: *\"installed' -e '\"state\" *: *\"success' -e '\"returnValue\" *: *false' -e 'failed' \(out)"
        return """
        rm -f \(out)
        sleep \(wait + 30) </dev/null 2>/dev/null | /usr/bin/luna-send-pub -i 'luna://com.webos.appInstallService/dev/install' '\(request)' >\(out) 2>&1 &
        P=$!
        t=0
        until [ $t -ge \(wait) ] || \(finished) 2>/dev/null || ! kill -0 $P 2>/dev/null; do sleep 1; t=$((t+1)); done
        cat \(out)
        kill $P 2>/dev/null
        rm -f \(out)
        """
    }

    static let launchCommand = "/usr/bin/luna-send-pub -n 1 'luna://com.webos.applicationManager/launch' '{\"id\":\"\(appID)\"}'"

    enum Reply: Equatable {
        case pending, installed
        case failed(String)
    }

    /// luna-send'in yanıtları: her biri bir JSON nesnesi, bazen birkaç satıra bölünmüş.
    static func parseReplies(_ output: String) -> Reply {
        func text(_ v: Any?) -> String? {
            if let s = v as? String { return s }
            if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.stringValue }
            return nil
        }
        func describe(_ message: String?, _ code: String?) -> String {
            let m = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let code else { return m }
            return m.isEmpty ? "(errorCode \(code))" : "\(m) (errorCode \(code))"
        }
        var buffer = ""
        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let piece = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if buffer.isEmpty && !piece.hasPrefix("{") { continue }
            buffer += piece
            guard let object = (try? JSONSerialization.jsonObject(with: Data(buffer.utf8))) as? [String: Any] else { continue }
            buffer = ""
            let details = object["details"] as? [String: Any] ?? [:]
            let state = ((details["state"] as? String) ?? "").lowercased()
            if object["returnValue"] as? Bool == false {
                return .failed(describe(text(object["errorText"]) ?? text(object["errorMessage"]), text(object["errorCode"])))
            }
            if state.contains("failed") {
                return .failed(describe(text(details["reason"]) ?? text(details["errorText"]) ?? state,
                                        text(details["errorCode"]) ?? text(object["errorCode"])))
            }
            if state.contains("installed") || state.hasPrefix("success") { return .installed }
        }
        return .pending
    }

    /// TV'nin "yer yok" anlamına gelen yanıtları.
    static func isStorageProblem(_ text: String) -> Bool {
        let t = text.lowercased()
        let phrases = ["no space", "enospc", "out of space", "disk full", "disk is full", "storage full", "storage is full",
                       "not enough space", "not enough free space", "not enough storage", "insufficient space",
                       "insufficient storage", "insufficient free"]
        return phrases.contains { t.contains($0) }
    }

    // MARK: Akış

    func installedVersion() throws -> String? { Self.version(fromAppInfo: try shell.run("cat \(Self.appInfoPath)", input: nil).output) }

    func install(ipk: TVPackage) throws -> TVInstallOutcome {
        log.write("--- LG: package \(ipk.version)")
        do {
            stage(.connecting)
            let onTV = try installedVersion()
            log.write("Nino on the TV: \(onTV ?? "none")")
            if let onTV, !VersionOrder.isNewer(ipk.version, than: onTV) {
                launch()
                return TVInstallOutcome(version: onTV, installed: false)
            }
            stage(.installing)
            try upload(ipk)
            log.write("Installed \(ipk.version).")
            launch()
            return TVInstallOutcome(version: ipk.version, installed: true)
        } catch let f as LGFailure {
            log.write("FAILED \(f)")
            throw f
        } catch {
            log.write("Connection lost: \(error)")
            throw LGFailure(problem: .connectionLost, detail: "\(error)")
        }
    }

    private func upload(_ ipk: TVPackage) throws {
        let remote = "\(Self.tempDir)/\(Self.appID)_\(ipk.version)_all.ipk"
        let put = try shell.run("mkdir -p \(Self.tempDir) && rm -f \(Self.tempDir)/\(Self.appID)_*.ipk && cat > '\(remote)'", input: ipk.bytes)
        if put.status != 0 { throw failure("upload exit \(put.status): \(TVInstallLog.short(put.output))", put.output) }
        let sizeReply = try shell.run("wc -c < '\(remote)'", input: nil).output
        if let size = Int(sizeReply.filter(\.isNumber)), size != ipk.bytes.count {
            throw LGFailure(problem: .installFailed, detail: "package arrived incomplete: \(size)/\(ipk.bytes.count) bytes")
        }
        let reply = try shell.run(Self.installCommand(remote: remote, wait: installWait), input: nil)
        log.write("Install reply (\(reply.status)):\n\(TVInstallLog.short(reply.output, limit: 2000))")
        let parsed = Self.parseReplies(reply.output)
        if case .failed(let why) = parsed {
            remove(remote)
            throw failure(why.isEmpty ? "install failed: \(TVInstallLog.short(reply.output))" : why, reply.output)
        }
        let limit = verifyWait ?? (parsed == .installed ? 30 : 60)
        let start = Date()
        repeat {
            if try installedVersion() == ipk.version {
                remove(remote)
                return
            }
            Thread.sleep(forTimeInterval: pollInterval)
        } while Date().timeIntervalSince(start) < limit
        // Yanıt gelmediyse paket silinmez: kurulum TV'de sürüyor olabilir.
        if parsed == .installed { remove(remote) }
        throw LGFailure(problem: .installFailed, detail: "\(ipk.version) did not appear on the TV: \(TVInstallLog.short(reply.output))")
    }

    private func launch() {
        stage(.launching)
        do {
            log.write("Launch: \(TVInstallLog.short(try shell.run(Self.launchCommand, input: nil).output))")
        } catch {
            log.write("Launch failed (install still done): \(error)")
        }
    }

    private func remove(_ remote: String) {
        _ = try? shell.run("rm -f '\(remote)'", input: nil)
    }

    private func failure(_ detail: String, _ evidence: String) -> LGFailure {
        LGFailure(problem: Self.isStorageProblem(evidence) || Self.isStorageProblem(detail) ? .notEnoughSpace : .installFailed, detail: detail)
    }

    /// Geliştirici modu süresini baştan başlatır (TV'deki EXTEND gibi); kalan saati döner.
    func renewSession() throws -> Int? {
        let token = try shell.run("cat \(Self.sessionTokenPath)", input: nil).output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.rangeOfCharacter(from: .whitespaces) == nil,
              let encoded = token.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        guard let reset = URL(string: "https://developer.lge.com/secure/ResetDevModeSession.dev?sessionToken=\(encoded)"),
              let check = URL(string: "https://developer.lge.com/secure/CheckDevModeSession.dev?sessionToken=\(encoded)"),
              String(decoding: try fetch(reset), as: UTF8.self).localizedCaseInsensitiveContains("success") else { return nil }
        return Self.remainingHours(String(decoding: try fetch(check), as: UTF8.self))
    }
}

/// LG geliştirici modu süresinin günde bir uzatılması (UserDefaults `lgSessionRenewedAt.<adres>`).
enum LGSessionRenewal {
    static let interval: TimeInterval = 20 * 3600

    static func key(_ host: String) -> String { "lgSessionRenewedAt.\(host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())" }

    /// Zamanı geldiyse uzatır; uzatıldıysa kalan saati döner.
    @discardableResult
    static func renewIfDue(host: String, defaults: UserDefaults, now: Date = Date(), renew: () -> Int?) -> Int? {
        if let last = defaults.object(forKey: key(host)) as? Date, now.timeIntervalSince(last) < interval { return nil }
        guard let hours = renew() else { return nil }
        defaults.set(now, forKey: key(host))
        return hours
    }
}

/// Kayıtlı LG anahtarları (`tv/lg/<adres>.key`, yedeğe girmez).
struct LGKeyStore {
    let files: TVInstallFiles

    func load(_ host: String) -> Bytes? { (try? Data(contentsOf: files.lgKeyFile(host: host))).map(Bytes.init) }

    func save(_ host: String, _ key: Bytes) {
        var folder = files.lg
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        try? Data(key).write(to: files.lgKeyFile(host: host), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func remove(_ host: String) { try? FileManager.default.removeItem(at: files.lgKeyFile(host: host)) }
}
