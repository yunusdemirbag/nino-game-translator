// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Darwin
import Foundation
import Security
import XCTest
@testable import NinoMacKit

// Samsung testleri için yardımcılar: 127.0.0.1'de sahte sdbd, openssl ile yerel sertifikalar, sahte sertifika
// sunucusu ve giriş. Gerçek Samsung hesabına, sunucusuna ya da TV'ye bağlanılmaz.

// MARK: openssl (yalnız yerel dosyalar)

enum OpenSSL {
    static var path: String? {
        ["/usr/bin/openssl", "/opt/homebrew/bin/openssl"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @discardableResult
    static func run(_ args: [String], in dir: URL, input: Data? = nil) throws -> (code: Int32, out: String) {
        guard let path else { throw XCTSkip("openssl yok") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.currentDirectoryURL = dir
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        let inp = Pipe()
        p.standardInput = inp
        try p.run()
        if let input { inp.fileHandleForWriting.write(input) }
        try? inp.fileHandleForWriting.close()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func ok(_ args: [String], in dir: URL, input: Data? = nil, file: StaticString = #filePath,
                   line: UInt = #line) throws -> String {
        let r = try run(args, in: dir, input: input)
        XCTAssertEqual(r.code, 0, r.out, file: file, line: line)
        return r.out
    }

    static func der(fromPEMFile url: URL) throws -> Data {
        X509Info.certificates(fromPEMOrDER: try Data(contentsOf: url)).first!
    }
}

/// openssl ile kurulan küçük bir CA zinciri: kök → ara; ayrıca konusu aranın aynısı, kendini vermiş bir tuzak.
final class TestCA {
    let dir: URL
    let rootDER: Data
    let intermediateDER: Data
    let decoyDER: Data

    init(dir: URL) throws {
        self.dir = dir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = dir.appendingPathComponent("ca.ext")
        try "basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n".write(to: ext, atomically: true,
                                                                                          encoding: .utf8)
        _ = try OpenSSL.ok(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "root.key", "-out", "root.pem",
                            "-days", "3650", "-subj", "/CN=Test Root Class"], in: dir)
        _ = try OpenSSL.ok(["req", "-newkey", "rsa:2048", "-nodes", "-keyout", "inter.key", "-out", "inter.csr",
                            "-subj", "/CN=Test Author CA Class"], in: dir)
        _ = try OpenSSL.ok(["x509", "-req", "-in", "inter.csr", "-CA", "root.pem", "-CAkey", "root.key",
                            "-CAcreateserial", "-out", "inter.pem", "-days", "3650", "-extfile", "ca.ext"], in: dir)
        _ = try OpenSSL.ok(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "decoy.key", "-out", "decoy.pem",
                            "-days", "3650", "-subj", "/CN=Test Author CA Class"], in: dir)
        rootDER = try OpenSSL.der(fromPEMFile: dir.appendingPathComponent("root.pem"))
        intermediateDER = try OpenSSL.der(fromPEMFile: dir.appendingPathComponent("inter.pem"))
        decoyDER = try OpenSSL.der(fromPEMFile: dir.appendingPathComponent("decoy.pem"))
    }

    /// CSR'ı (PEM) ara sertifikayla imzalar; yaprak PEM metni. openssl CSR'ı okuyabilmeli.
    func issue(csrPEM: Data, days: Int = 365, name: String) throws -> Data {
        let csr = dir.appendingPathComponent("\(name).csr")
        try csrPEM.write(to: csr)
        _ = try OpenSSL.ok(["x509", "-req", "-in", csr.lastPathComponent, "-CA", "inter.pem", "-CAkey", "inter.key",
                            "-CAcreateserial", "-out", "\(name).pem", "-days", "\(days)"], in: dir)
        return try Data(contentsOf: dir.appendingPathComponent("\(name).pem"))
    }
}

// MARK: Sahte sertifika sunucusu

final class FakeCertificateTransport: SamsungCertificateTransport, @unchecked Sendable {
    struct Call {
        var url: URL
        var body: String
        var contentType: String
    }
    let calls = LockedBox<[Call]>([])
    var reply: (URL, Data) throws -> (Int, String, Data)

    init(reply: @escaping (URL, Data) throws -> (Int, String, Data)) { self.reply = reply }

    func post(_ url: URL, body: Data, contentType: String, timeout: TimeInterval) async throws
        -> (status: Int, reason: String, body: Data) {
        calls.mutate { $0.append(Call(url: url, body: String(decoding: body, as: UTF8.self), contentType: contentType)) }
        let r = try reply(url, body)
        return (r.0, r.1, r.2)
    }

    /// Gövdedeki CSR PEM'i.
    static func csr(in body: Data) -> Data {
        let t = String(decoding: body, as: UTF8.self)
        let b = t.range(of: "-----BEGIN CERTIFICATE REQUEST-----")!
        let e = t.range(of: "-----END CERTIFICATE REQUEST-----")!
        return Data((String(t[b.lowerBound..<e.upperBound]) + "\n").utf8)
    }

    /// Ara sertifikayla imzalayan sunucu (v1 dağıtıcı: cihaz profili XML'i).
    static func issuing(_ ca: TestCA) -> FakeCertificateTransport {
        FakeCertificateTransport { url, body in
            switch url.path {
            case SamsungCertificateClient.profilePath:
                return (200, "OK", Data("<profile>device</profile>".utf8))
            default:
                let pem = try ca.issue(csrPEM: csr(in: body), name: url.path.contains("authors") ? "author" : "dist")
                return (200, "OK", pem)
            }
        }
    }
}

/// Hesabı hemen veren (ya da hiç vermeyen) sahte giriş.
struct FakeLogin: SamsungLoginListening {
    var account: SamsungLogin.Account?
    var failure: SamsungLogin.LoginError?
    func waitForAccount(timeout: TimeInterval, onReady: @escaping @Sendable () -> Void) async throws -> SamsungLogin.Account {
        if let failure { throw failure }
        onReady()
        if let account { return account }
        try await Task.sleep(nanoseconds: 60_000_000_000)
        throw SamsungLogin.LoginError.timedOut(summary: nil)
    }
}

/// Bağlantıyı istenen porta değil sahte sunucunun portuna yönlendirir.
struct RedirectConnector: ADBConnecting {
    let port: UInt16
    let base = NWADBConnector()
    func connect(host: String, port _: UInt16, timeout: TimeInterval) async throws -> ADBByteStream {
        try await base.connect(host: "127.0.0.1", port: port, timeout: timeout)
    }
}

// MARK: Sahte sdbd (127.0.0.1)

final class FakeSDBServer: @unchecked Sendable {
    let port: UInt16
    private let fd: Int32
    private let lock = NSLock()

    // Senaryo
    var requireAuth = true
    var capability = "8csecure_protocol:enabled\nplatform_version:6.5\nsdk_toolpath:/home/owner/share/tmp/sdk_tools\n"
    var duid = "CJCHTFRXVXQDQ"
    /// Sırayla verilen vd_applist yanıtları (son yanıt kalıcı).
    var applist: [String] = [""]
    var installOutputs: [String] = ["app_id[NinoTVApps.Nino] installing[100]\nspend time for pkgcmd is [1234]ms\ncmd_ret:0"]
    /// İlk N bağlantıyı CNXN'den sonra keser (sdbd'nin el sıkışma ortasında kesmesi).
    var dropConnections = 0
    /// Kurulum komutunda bağlantıyı keser.
    var dropOnInstall = false
    /// Kurulum komutuna hiç yanıt vermez (iptal testi).
    var stallOnInstall = false
    /// İmzadan ve açık anahtardan sonra da jeton gönderir (anahtarı kabul etmeyen TV).
    var tokenLoop = false
    /// Kurulumdan sonra applist'e yeni sürüm eklenir.
    var installedVersion: String?

    // Gözlem
    private(set) var services: [String] = []
    private(set) var pushed: [String: Data] = [:]
    private(set) var signatureVerified = false
    private(set) var connections = 0
    private(set) var cnxnHeaders: [Data] = []

    init() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, 4)
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_addr.s_addr = inet_addr("127.0.0.1")
        a.sin_port = 0
        let r = withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard r == 0, listen(fd, 8) == 0 else { throw XCTSkip("127.0.0.1 dinlenemedi") }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        self.fd = fd
        port = UInt16(bigEndian: a.sin_port)
        let t = Thread { [weak self] in self?.acceptLoop() }
        t.start()
    }

    func stop() { Darwin.close(fd) }

    func with<T>(_ f: (FakeSDBServer) -> T) -> T { lock.withLock { f(self) } }

    private func acceptLoop() {
        while true {
            let c = accept(fd, nil, nil)
            if c < 0 { return }
            var one: Int32 = 1
            setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, 4)
            let t = Thread { [weak self] in
                self?.serve(c)
                Darwin.close(c)
            }
            t.start()
        }
    }

    // Çerçeve G/Ç
    private func readExact(_ c: Int32, _ n: Int) -> Data? {
        var out = Data()
        var buf = [UInt8](repeating: 0, count: max(1, n))
        while out.count < n {
            let r = recv(c, &buf, n - out.count, 0)
            if r <= 0 { return nil }
            out.append(buf, count: r)
        }
        return out
    }

    private func readFrame(_ c: Int32) -> (ADBMessage, Data)? {
        guard let h = readExact(c, 24) else { return nil }
        let len = Int(h.readLE32(at: 12))
        guard let d = len > 0 ? readExact(c, len) : Data() else { return nil }
        return (ADBMessage(rawCommand: h.readLE32(at: 0), arg0: h.readLE32(at: 4), arg1: h.readLE32(at: 8), data: d), h)
    }

    private func send(_ c: Int32, _ m: ADBMessage) {
        let d = m.encoded()
        d.withUnsafeBytes { _ = Darwin.send(c, $0.baseAddress, d.count, 0) }
    }

    private func serve(_ c: Int32) {
        let drop = lock.withLock { () -> Bool in
            connections += 1
            if dropConnections > 0 { dropConnections -= 1; return true }
            return false
        }
        guard let (cnxn, header) = readFrame(c), cnxn.kind == .cnxn else { return }
        lock.withLock { cnxnHeaders.append(header + cnxn.data) }
        if drop { return }
        if lock.withLock({ tokenLoop }) {
            for _ in 0..<5 {
                send(c, ADBMessage(.auth, 1, 0, Data(repeating: 9, count: 20)))
                guard readFrame(c) != nil else { return }
            }
            return
        }
        if lock.withLock({ requireAuth }) {
            let token = Data((0..<20).map { _ in UInt8.random(in: 0...255) })
            send(c, ADBMessage(.auth, 1, 0, token))
            guard let (sig, _) = readFrame(c), sig.kind == .auth, sig.arg0 == 2 else { return }
            send(c, ADBMessage(.auth, 3, 0))
            guard let (pub, _) = readFrame(c), pub.kind == .auth, pub.arg0 == 3 else { return }
            let ok = Self.verify(signature: sig.data, token: token, publicKeyLine: pub.data)
            lock.withLock { signatureVerified = ok }
            guard ok else { return }
        }
        send(c, ADBMessage(.cnxn, 0x0100_0000, 4096, Data("device::tizen-fake".utf8)))
        var nextRemote: UInt32 = 1000
        while let (m, _) = readFrame(c) {
            guard m.kind == .open else { continue }
            let service = String(decoding: m.data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\u{0}"))
            lock.withLock { services.append(service) }
            let local = m.arg0, remote = nextRemote
            nextRemote += 1
            send(c, ADBMessage(.okay, remote, local))
            if service == "sync:" {
                guard handleSync(c, local: local, remote: remote) else { return }
                continue
            }
            if service.hasPrefix("shell:0 vd_appinstall"), lock.withLock({ dropOnInstall }) { return }
            if service.hasPrefix("shell:0 vd_appinstall"), lock.withLock({ stallOnInstall }) {
                _ = readFrame(c) // istemci kapatana dek bekle
                return
            }
            let out = output(for: service)
            var offset = 0
            let bytes = Data(out.utf8)
            while offset < bytes.count {
                let end = min(offset + 4096, bytes.count)
                send(c, ADBMessage(.wrte, remote, local, Data(bytes[offset..<end])))
                guard let (ack, _) = readFrame(c), ack.kind == .okay else { return }
                offset = end
            }
            send(c, ADBMessage(.clse, remote, local))
            guard let (cl, _) = readFrame(c), cl.kind == .clse else { return }
        }
    }

    private func output(for service: String) -> String {
        lock.withLock {
            if service == "capability:" { return "\u{0}\u{0}" + capability }
            if service == "shell:0 getduid" { return duid + "\n" }
            if service == "shell:0 vd_applist" {
                let r = applist.first ?? ""
                if applist.count > 1 { applist.removeFirst() }
                return r
            }
            if service.hasPrefix("shell:0 vd_appinstall") {
                let r = installOutputs.first ?? ""
                if installOutputs.count > 1 { installOutputs.removeFirst() }
                if r.contains("cmd_ret:0"), let v = installedVersion { applist = [Self.applist(version: v)] }
                return r
            }
            if service.hasPrefix("shell:0 vd_appuninstall") { return "uninstalled\n" }
            if service.hasPrefix("shell:0 was_execute") { return "launched\n" }
            return ""
        }
    }

    /// SEND/DATA/DONE paketlerini toplar, OKAY yanıtı verir.
    private func handleSync(_ c: Int32, local: UInt32, remote: UInt32) -> Bool {
        var buf = Data()
        var path = ""
        var file = Data()
        while true {
            guard let (m, _) = readFrame(c) else { return false }
            if m.kind == .clse { return true }
            guard m.kind == .wrte else { continue }
            buf.append(m.data)
            send(c, ADBMessage(.okay, remote, local))
            while buf.count >= 8 {
                let id = String(decoding: buf.prefix(4), as: UTF8.self)
                let len = Int(buf.readLE32(at: 4))
                guard buf.count >= 8 + len else { break }
                let payload = Data(buf[(buf.startIndex + 8)..<(buf.startIndex + 8 + len)])
                buf.removeFirst(8 + len)
                switch id {
                case "SEND": path = String(decoding: payload, as: UTF8.self)
                case "DATA": file.append(payload)
                case "DONE":
                    lock.withLock { pushed[path] = file }
                    var ok = Data("OKAY".utf8); ok.appendLE(0)
                    send(c, ADBMessage(.wrte, remote, local, ok))
                    guard let (ack, _) = readFrame(c), ack.kind == .okay else { return false }
                default: break
                }
            }
        }
    }

    static func applist(version: String) -> String {
        "\t-------------app_title  =  Nino----------------------------\n"
            + "\t-------------app_tizen_id  =  NinoTVApps.Nino----------------\n"
            + "\t-------------app_version  =  \(version)-----------------------------\n"
            + "\t------------------------------------------------------------------------\n"
    }

    /// AUTH imzasını, istemcinin gönderdiği `android_pubkey` ile ham jeton üzerinden (SHA-1) doğrular.
    static func verify(signature: Data, token: Data, publicKeyLine: Data) -> Bool {
        let line = String(decoding: publicKeyLine, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\u{0}"))
        guard let b64 = line.split(separator: " ").first, let blob = Data(base64Encoded: String(b64)), blob.count == 524
        else { return false }
        let modulus = Data(blob[8..<264].reversed())
        let e = blob.readLE32(at: 520)
        var eBytes = withUnsafeBytes(of: e.bigEndian) { Data($0) }
        while eBytes.first == 0 { eBytes.removeFirst() }
        func int(_ d: Data) -> Data { DER.tlv(0x02, d.first.map { $0 & 0x80 != 0 } == true ? Data([0]) + d : d) }
        let der = DER.sequence(int(modulus), int(eBytes))
        let attrs: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, nil) else { return false }
        return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA1, token as CFData, signature as CFData, nil)
    }
}

/// Boş bir 127.0.0.1 portu (bağlanıp bırakılır).
func freeLoopbackPort() -> UInt16 {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    defer { Darwin.close(fd) }
    var a = sockaddr_in()
    a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    a.sin_family = sa_family_t(AF_INET)
    a.sin_addr.s_addr = inet_addr("127.0.0.1")
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &a) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { p -> Int32 in
            _ = bind(fd, p, len)
            return getsockname(fd, p, &len)
        }
    }
    return UInt16(bigEndian: a.sin_port)
}

/// Koşul tutana dek (en çok `seconds`) bekler.
func samsungWait(_ seconds: TimeInterval = 5, _ cond: () -> Bool) async throws {
    let end = Date().addingTimeInterval(seconds)
    while !cond() {
        if Date() > end { throw XCTSkip("bekleme süresi doldu") }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
}

// MARK: Örnek .wgt

enum SampleWidget {
    /// Aynı içerik, başka bir araçla (`/usr/bin/zip` ya da `ditto`) paketlenmiş.
    static func makeWithTool(_ tool: String, in dir: URL) throws -> Data {
        let src = dir.appendingPathComponent("src-\(tool)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: src.appendingPathComponent("js"), withIntermediateDirectories: true)
        for e in try WidgetZip(data: make()).entries where !e.isDirectory {
            try WidgetZip.contents(e).write(to: src.appendingPathComponent(e.name))
        }
        let out = dir.appendingPathComponent("\(tool).wgt")
        let p = Process()
        if tool == "zip" {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            p.arguments = ["-qr", out.path, "."]
            p.currentDirectoryURL = src
        } else {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-c", "-k", src.path, out.path]
        }
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw XCTSkip("\(tool) çalışmadı") }
        return try Data(contentsOf: out)
    }

    /// config.xml + index.html + bir klasör + eski bir imza (atılmalı).
    static func make() -> Data {
        let config = """
        <?xml version="1.0" encoding="UTF-8"?><widget xmlns="http://www.w3.org/ns/widgets" \
        xmlns:tizen="http://tizen.org/ns/widgets" id="http://nino/tv" version="0.9.8">\
        <tizen:application id="NinoTVApps.Nino" package="NinoTVApps" required_version="3.0"/></widget>
        """
        return WidgetZip(entries: [
            WidgetZip.entry(name: "config.xml", contents: Data(config.utf8)),
            WidgetZip.entry(name: "js/", contents: Data()),
            WidgetZip.entry(name: "js/app.js", contents: Data(String(repeating: "console.log('nino');\n", count: 200).utf8)),
            WidgetZip.entry(name: "index.html", contents: Data("<html><body>Nino & TV</body></html>".utf8)),
            WidgetZip.entry(name: "author-signature.xml", contents: Data("<old/>".utf8)),
        ]).encoded()
    }
}
