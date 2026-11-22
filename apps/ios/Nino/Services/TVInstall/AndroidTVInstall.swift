// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CryptoKit
import Foundation

// Android TV / Google TV: adb ile bağlanma (RSA kimlik doğrulama, kablosuz hata ayıklamada TLS), eşleme kodu ile
// eşleme (TLS 1.3 + SPAKE2 + AES-128-GCM), APK kurma, katman izni ve açma.

enum AndroidTVProblem: Equatable, Sendable {
    case unreachable, notApproved, notPaired, pairingFailed
    /// TV'deki kopya başka anahtarla imzalı ya da daha yeni; kullanıcı onaylarsa kaldırılıp kurulur.
    case replaceNeeded
    case notEnoughSpace, installFailed, connectionLost, packageMissing
}

struct AndroidTVFailure: Error, CustomStringConvertible {
    var problem: AndroidTVProblem
    var detail: String?
    var fromPlay = false
    var description: String { "\(problem)" + (detail.map { ": \($0)" } ?? "") }
}

// MARK: - Bağlantı

/// adb istemcisi.
final class AdbClient: WireLink {
    static let defaultPort: UInt16 = 5555
    private var bridge: LoopbackBridge?
    private(set) var usesTLS = false

    /// - Parameters:
    ///   - approvalNeeded: TV bu telefonu ilk kez görüyor ve ekranda onay sorusu çıkacak. Hata atarsa vazgeçilir
    ///     (sessiz sürüm denetimi TV'de pencere açmasın diye).
    static func connect(host: String, port: UInt16, identity: AdbIdentity, approvalNeeded: () throws -> Void = {},
                        approvalTimeout: TimeInterval = 90, connectTimeout: TimeInterval = 6) throws -> AdbClient {
        let tcp: TCPChannel
        do {
            tcp = try TCPChannel(host: host, port: port, timeout: connectTimeout)
        } catch {
            throw AndroidTVFailure(problem: .unreachable, detail: "\(host):\(port): \(error)")
        }
        let client = AdbClient(channel: tcp, verifySum: false)
        do {
            try client.handshake(identity, approvalNeeded, approvalTimeout)
            return client
        } catch {
            client.close()
            throw error
        }
    }

    private func handshake(_ identity: AdbIdentity, _ approvalNeeded: () throws -> Void, _ approvalTimeout: TimeInterval) throws {
        channel.receiveTimeout = 10
        let offered: UInt32 = 256 * 1024
        try send(WireMessage(command: WireMessage.connect, arg0: 0x0100_0001, arg1: offered, payload: Bytes("host::\u{0}".utf8)))
        var signed = false
        var askedUser = false
        while true {
            let m: WireMessage
            do {
                m = try WireMessage.read(from: reader, verifySum: false, maxPayload: 1 << 20)
            } catch {
                let problem: AndroidTVProblem = usesTLS ? .notPaired : askedUser ? .notApproved : .unreachable
                throw AndroidTVFailure(problem: problem, detail: "\(error)")
            }
            switch m.command {
            case WireMessage.connect:
                maxPayload = Int(min(offered, m.arg1 == 0 ? 4096 : m.arg1))
                channel.receiveTimeout = 120
                return
            case WireMessage.startTLS:
                // Kablosuz hata ayıklama: TV yalnız eşlemede öğrendiği anahtarın sertifikasını kabul eder.
                try send(WireMessage(command: WireMessage.startTLS, arg0: 0x0100_0000, arg1: 0))
                do {
                    let tlsIdentity = try TLSClientIdentity.make(key: identity.key, certificateFile: identity.certificateFile)
                    let bridge = try LoopbackBridge(upstream: channel, prefetched: reader.drain())
                    let tls = try TLSChannel(host: "127.0.0.1", port: bridge.port, identity: tlsIdentity)
                    tls.receiveTimeout = 10
                    self.bridge = bridge
                    replaceChannel(tls)
                    usesTLS = true
                } catch {
                    throw AndroidTVFailure(problem: .notPaired, detail: "TLS: \(error)")
                }
            case WireMessage.auth where m.arg0 == 1 && !signed:
                signed = true
                try send(WireMessage(command: WireMessage.auth, arg0: 2, arg1: 0, payload: try identity.signAdbToken(m.payload)))
            case WireMessage.auth where m.arg0 == 1:
                // İmza tanınmadı: açık anahtar gönderilir, TV kullanıcıya sorar.
                if askedUser { throw AndroidTVFailure(problem: .notApproved, detail: "the TV asked for the key again") }
                try approvalNeeded()
                try send(WireMessage(command: WireMessage.auth, arg0: 3, arg1: 0, payload: Bytes((identity.publicKeyLine + "\u{0}").utf8)))
                askedUser = true
                channel.receiveTimeout = approvalTimeout
            default:
                throw AndroidTVFailure(problem: .unreachable, detail: "unexpected \(m.name) during handshake")
            }
        }
    }

    func shell(_ command: String) throws -> String { try run("shell:" + command) }

    override func close() {
        super.close()
        bridge?.close()
    }
}

// MARK: - Eşleme

/// "Cihazı eşleme kodu ile eşle" (AOSP pairing_connection): TLS 1.3, dışa aktarılan anahtar + kod ile SPAKE2,
/// sonra AES-128-GCM ile şifreli PeerInfo alışverişi.
enum AdbPairing {
    static let exporterLabel = Bytes("adb-label\u{0}".utf8)
    static let peerInfoSize = 8192
    static let spakeMessage: UInt8 = 0
    static let peerInfo: UInt8 = 1

    static func pair(host: String, port: UInt16, code: String, identity: AdbIdentity) throws {
        let tls: TLSChannel
        do {
            let tlsIdentity = try TLSClientIdentity.make(key: identity.key, certificateFile: identity.certificateFile)
            tls = try TLSChannel(host: host, port: port, identity: tlsIdentity, timeout: 10)
        } catch {
            throw AndroidTVFailure(problem: .pairingFailed, detail: "TLS: \(error)")
        }
        defer { tls.shutdown() }
        tls.receiveTimeout = 15
        guard let exported = tls.exportKeyingMaterial(label: exporterLabel, length: 64) else {
            throw AndroidTVFailure(problem: .pairingFailed, detail: "TLS exporter unavailable")
        }
        let reader = ChannelReader(tls)
        let spake = Spake2(role: .alice, password: Bytes(code.trimmingCharacters(in: .whitespaces).utf8) + exported)
        try tls.send(frame(spakeMessage, spake.message))
        let theirs = try readFrame(reader, type: spakeMessage)
        guard let keyMaterial = spake.finish(theirs) else {
            throw AndroidTVFailure(problem: .pairingFailed, detail: "invalid SPAKE2 message")
        }
        var cipher = PairingCipher(keyMaterial: keyMaterial)
        try tls.send(frame(peerInfo, try cipher.seal(peerInfoBlock(identity.publicKeyLine))))
        let answer = try readFrame(reader, type: peerInfo)
        guard cipher.open(answer) != nil else {
            throw AndroidTVFailure(problem: .pairingFailed, detail: "wrong pairing code")
        }
    }

    /// PeerInfo: tür (0 = RSA açık anahtar) ve 8191 baytlık sıfırla doldurulmuş veri.
    static func peerInfoBlock(_ line: String) -> Bytes {
        var block = Bytes(repeating: 0, count: peerInfoSize)
        let data = Bytes(line.utf8).prefix(peerInfoSize - 1)
        block.replaceSubrange(1..<(1 + data.count), with: data)
        return block
    }

    /// Başlık: sürüm (1), tür, büyük-endian veri boyu.
    static func frame(_ type: UInt8, _ payload: Bytes) -> Bytes { [1, type] + be32Bytes(UInt32(payload.count)) + payload }

    static func readFrame(_ reader: ChannelReader, type: UInt8) throws -> Bytes {
        let head: Bytes
        do {
            head = try reader.read(exactly: 6)
        } catch {
            throw AndroidTVFailure(problem: .pairingFailed, detail: "the TV ended pairing: \(error)")
        }
        let length = Int(head.be32(at: 2))
        guard head[0] == 1, head[1] == type, length <= peerInfoSize * 2 else {
            throw AndroidTVFailure(problem: .pairingFailed, detail: "unexpected pairing packet \(head[0])/\(head[1])/\(length)")
        }
        return try reader.read(exactly: length)
    }

    /// HKDF-SHA256 ("adb pairing_auth aes-128-gcm key") ile 16 baytlık anahtar; her yönde 0'dan sayan 12 baytlık nonce.
    struct PairingCipher {
        let key: SymmetricKey
        private var sent: UInt64 = 0
        private var received: UInt64 = 0

        init(keyMaterial: Bytes) {
            key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: keyMaterial), salt: Data(),
                                         info: Data("adb pairing_auth aes-128-gcm key".utf8), outputByteCount: 16)
        }

        private static func nonce(_ counter: UInt64) -> AES.GCM.Nonce {
            let bytes = (0..<12).map { $0 < 8 ? UInt8(truncatingIfNeeded: counter >> UInt64(8 * $0)) : 0 }
            return try! AES.GCM.Nonce(data: bytes)
        }

        mutating func seal(_ plain: Bytes) throws -> Bytes {
            let box = try AES.GCM.seal(plain, using: key, nonce: Self.nonce(sent))
            sent += 1
            return Bytes(box.ciphertext) + Bytes(box.tag)
        }

        mutating func open(_ sealed: Bytes) -> Bytes? {
            guard sealed.count >= 16 else { return nil }
            let n = Self.nonce(received)
            received += 1
            guard let box = try? AES.GCM.SealedBox(nonce: n, ciphertext: sealed.dropLast(16), tag: sealed.suffix(16)),
                  let plain = try? AES.GCM.open(box, using: key) else { return nil }
            return Bytes(plain)
        }
    }
}

// MARK: - Kurulum

/// TV uygulamasını (com.ninotranslator.tv) adb ile kurar ve açar.
struct AndroidTVInstaller {
    static let packageID = "com.ninotranslator.tv"
    static let remoteAPK = "/data/local/tmp/nino-tv.apk"
    static let playPage = URL(string: "https://play.google.com/store/apps/details?id=\(packageID)")!

    struct Pairing: Sendable {
        var port: UInt16
        var code: String
    }

    var host: String
    var port: UInt16
    var identity: () throws -> AdbIdentity
    var pairing: Pairing?
    var log: TVInstallLog
    var stage: (InstallStage) -> Void = { _ in }
    /// Nino TV Google Play'de herkese açık mı (açıksa ve TV'de Play varsa önce Play denenir).
    var playListed: () -> Bool = { AndroidTVInstaller.isListedOnPlay() }
    var playWait: TimeInterval = 240
    var playPoll: TimeInterval = 3
    var approvalTimeout: TimeInterval = 90

    // MARK: Yardımcılar (testli)

    static func version(fromDumpsys text: String) -> String? { firstMatch(#"versionName=(\S+)"#, text) }
    static func installedFromPlay(_ dumpsys: String) -> Bool {
        firstMatch(#"installerPackageName=(\S+)"#, dumpsys) == "com.android.vending"
    }
    static func needsReplace(_ output: String) -> Bool {
        output.contains("INSTALL_FAILED_UPDATE_INCOMPATIBLE") || output.contains("INSTALL_FAILED_VERSION_DOWNGRADE")
    }
    static func isStorageProblem(_ output: String) -> Bool {
        output.contains("INSTALL_FAILED_INSUFFICIENT_STORAGE") || output.range(of: "no space left", options: .caseInsensitive) != nil
    }
    /// `cmd package install` desteklenmiyorsa ne "Success" ne "Failure" yazar.
    static func streamingUnsupported(_ output: String) -> Bool { !output.contains("Success") && !output.contains("Failure") }
    static func looksFailed(_ output: String) -> Bool {
        ["error", "exception", "unknown", "not allowed", "security"].contains { output.range(of: $0, options: .caseInsensitive) != nil }
    }
    static func hasPlayStore(_ listing: String) -> Bool {
        listing.split(whereSeparator: \.isNewline).contains { $0.trimmingCharacters(in: .whitespaces) == "package:com.android.vending" }
    }

    /// "192.168.1.5:37123" → (adres, port); port yoksa `defaultPort` (0 verilirse port zorunlu).
    static func split(_ text: String, defaultPort: UInt16 = AdbClient.defaultPort) -> (host: String, port: UInt16)? {
        let value = normalizedDigits(text).trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        guard let colon = value.lastIndex(of: ":") else {
            return defaultPort == 0 ? nil : (value, defaultPort)
        }
        let host = value[..<colon].trimmingCharacters(in: .whitespaces)
        guard let port = UInt16(value[value.index(after: colon)...].trimmingCharacters(in: .whitespaces)), port > 0,
              !host.isEmpty else { return nil }
        return (host, port)
    }

    static func isListedOnPlay(timeout: TimeInterval = 5) -> Bool {
        var r = URLRequest(url: playPage)
        r.timeoutInterval = timeout
        return (try? BlockingHTTP.send(r)) != nil
    }

    private static func firstMatch(_ pattern: String, _ text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    // MARK: Akış

    /// TV'deki sürüm (kurmadan). TV onay sorarsa vazgeçilir: sessiz denetim TV'de pencere açmaz.
    func installedVersion() throws -> String? {
        let adb = try AdbClient.connect(host: host, port: port, identity: try identity(), approvalNeeded: {
            throw AndroidTVFailure(problem: .notApproved, detail: "approval needed")
        })
        defer { adb.close() }
        return Self.version(fromDumpsys: try adb.shell("dumpsys package \(Self.packageID)"))
    }

    /// Uygulama yoksa ya da paketten eskiyse kurar, sonra açar. Paket ancak TV okunduktan sonra istenir: paket
    /// bulunamazsa ve TV'de Nino varsa yine izin verilip açılır.
    func install(package: () throws -> TVPackage, allowReplace: Bool = false) throws -> TVInstallOutcome {
        log.write("--- Android TV: \(host):\(port)" + (pairing.map { ", pairing port \($0.port)" } ?? ""))
        do {
            let outcome = try perform(package: package, allowReplace: allowReplace)
            log.write(outcome.installed ? "Installed \(outcome.version)." : "TV already has \(outcome.version).")
            return outcome
        } catch let failure as AndroidTVFailure {
            log.write("FAILED \(failure)")
            throw failure
        } catch {
            log.write("Connection lost: \(error)")
            throw AndroidTVFailure(problem: .connectionLost, detail: "\(error)")
        }
    }

    private func perform(package source: () throws -> TVPackage, allowReplace: Bool) throws -> TVInstallOutcome {
        let id = try identity()
        if let pairing {
            stage(.pairing)
            try AdbPairing.pair(host: host, port: pairing.port, code: pairing.code, identity: id)
            log.write("Paired (port \(pairing.port)).")
        }
        stage(.connecting)
        let adb = try AdbClient.connect(host: host, port: port, identity: id, approvalNeeded: {
            log.write("The TV sees this phone for the first time; waiting for approval.")
            stage(.approveOnTV)
        }, approvalTimeout: approvalTimeout)
        defer { adb.close() }
        log.write("adb connected (\(adb.usesTLS ? "TLS" : "plain"), max \(adb.maxPayload) bytes).")

        stage(.reading)
        let dumpsys = try adb.shell("dumpsys package \(Self.packageID)")
        let onTV = Self.version(fromDumpsys: dumpsys)
        let fromPlay = Self.installedFromPlay(dumpsys)
        log.write("Nino on the TV: \(onTV ?? "none")\(fromPlay ? " (Google Play)" : "")")
        var package: TVPackage?
        var missing = ""
        do { package = try source() } catch { missing = "\(error)" }
        if let onTV, package.map({ !VersionOrder.isNewer($0.version, than: onTV) }) ?? true {
            if package == nil { log.write("No TV package on this phone (\(missing)); keeping the TV's copy.") }
            allowOverlay(adb)
            launch(adb)
            return TVInstallOutcome(version: onTV, installed: false)
        }
        if let viaPlay = try installFromPlay(adb, before: onTV, fromPlay: fromPlay) { return viaPlay }
        guard let package else { throw AndroidTVFailure(problem: .packageMissing, detail: missing) }
        log.write("Installing package \(package.version) (\(package.origin)).")

        stage(.installing)
        let bytes = package.bytes
        var output = try installAPK(adb, bytes)
        if Self.needsReplace(output) {
            guard allowReplace else {
                throw AndroidTVFailure(problem: .replaceNeeded, detail: TVInstallLog.short(output), fromPlay: fromPlay)
            }
            stage(.uninstalling)
            let removed = (try? adb.shell("pm uninstall \(Self.packageID)")) ?? "?"
            log.write("Removed the TV's copy (user agreed): \(TVInstallLog.short(removed))")
            stage(.installing)
            output = try installAPK(adb, bytes)
        }
        guard output.contains("Success") else {
            let text = TVInstallLog.short(output)
            throw AndroidTVFailure(problem: Self.isStorageProblem(output) ? .notEnoughSpace : .installFailed,
                                   detail: text.isEmpty ? "no answer from the TV" : text)
        }
        allowOverlay(adb)
        let after = Self.version(fromDumpsys: (try? adb.shell("dumpsys package \(Self.packageID)")) ?? "")
        launch(adb)
        return TVInstallOutcome(version: after ?? package.version, installed: true)
    }

    /// Nino TV Play'deyse ve TV'de Play Store varsa Play sayfası açılır; kullanıcı kumandayla kurar. Belli sürede
    /// kurulmazsa nil döner ve APK ile devam edilir.
    private func installFromPlay(_ adb: AdbClient, before: String?, fromPlay: Bool) throws -> TVInstallOutcome? {
        guard playListed() else { return nil }
        if !fromPlay, !Self.hasPlayStore((try? adb.shell("pm list packages com.android.vending")) ?? "") {
            log.write("No Play Store on the TV; installing the APK.")
            return nil
        }
        let opened = try adb.shell("am start -a android.intent.action.VIEW -d market://details?id=\(Self.packageID)")
        log.write("Opening Play: \(TVInstallLog.short(opened))")
        if opened.range(of: "error", options: .caseInsensitive) != nil { return nil }
        stage(.waitingForPlay)
        let deadline = Date().addingTimeInterval(playWait)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: playPoll)
            if let now = Self.version(fromDumpsys: try adb.shell("dumpsys package \(Self.packageID)")), now != before {
                log.write("Installed from Play: \(now)")
                allowOverlay(adb)
                launch(adb)
                return TVInstallOutcome(version: now, installed: true)
            }
        }
        log.write("Not installed from Play within \(Int(playWait)) s; installing the APK.")
        return nil
    }

    /// Android 7+: APK paket yöneticisine akıtılır; desteklenmiyorsa TV'ye gönderilip `pm install` ile kurulur.
    private func installAPK(_ adb: AdbClient, _ apk: Bytes) throws -> String {
        let streamed: String
        do {
            streamed = try adb.run("exec:cmd package install -r -S \(apk.count)", input: apk)
        } catch let failure as AndroidTVFailure {
            throw failure
        } catch {
            streamed = "exec: \(error)"
        }
        log.write("cmd package install: \(TVInstallLog.short(streamed))")
        guard Self.streamingUnsupported(streamed) else { return streamed }
        try SyncProtocol.push(apk, to: Self.remoteAPK, over: adb, mode: 0o644, doneCarriesLength: false)
        let output = try adb.shell("pm install -r \(Self.remoteAPK)")
        log.write("pm install: \(TVInstallLog.short(output))")
        _ = try? adb.shell("rm -f \(Self.remoteAPK)")
        return output
    }

    /// Katman izni ("diğer uygulamaların üstünde göster"); TCL gibi TV'lerde HDMI görüntüsünün üstüne çizmek için
    /// gerekir. Verilemezse kurulum yine başarılıdır.
    private func allowOverlay(_ adb: AdbClient) {
        var out = (try? adb.shell("appops set \(Self.packageID) SYSTEM_ALERT_WINDOW allow")) ?? "error"
        if Self.looksFailed(out) {
            out = (try? adb.shell("pm grant \(Self.packageID) android.permission.SYSTEM_ALERT_WINDOW")) ?? "error"
        }
        log.write("Overlay permission: " + (Self.looksFailed(out) ? "not granted (\(TVInstallLog.short(out)))" : "granted"))
    }

    private func launch(_ adb: AdbClient) {
        stage(.launching)
        var out = (try? adb.shell("am start -n \(Self.packageID)/.MainActivity")) ?? "error"
        if out.range(of: "error", options: .caseInsensitive) != nil {
            out = (try? adb.shell("monkey -p \(Self.packageID) -c android.intent.category.LEANBACK_LAUNCHER 1")) ?? "error"
        }
        log.write("Launch: \(TVInstallLog.short(out))")
    }
}

/// Arapça/Farsça rakamları Latin rakama çevirir (elle yazılan adreslerde).
func normalizedDigits(_ text: String) -> String {
    String(text.map { c -> Character in
        if c.isASCII { return c }
        if let v = c.wholeNumberValue, (0...9).contains(v) { return Character(String(v)) }
        if c == "٫" || c == "،" { return "." }
        return c
    })
}
