// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Network
import Security
import XCTest
@testable import NinoMacKit

// Uygulama içi TV yardımcısı: ADB çerçeveleme, anahtar, el sıkışma, kurulum akışı.
// Gerçek TV'ye bağlanılmaz: bellek içi boru ve 127.0.0.1'de sahte ADB cihazı.

// MARK: Bellek içi çift yönlü boru

final class MemoryPipeEnd: ADBByteStream, @unchecked Sendable {
    private let lock = NSLock()
    private var inbox = Data()
    private var closed = false
    private var waiter: CheckedContinuation<Void, Never>?
    weak var peer: MemoryPipeEnd?

    static func pair() -> (MemoryPipeEnd, MemoryPipeEnd) {
        let a = MemoryPipeEnd(), b = MemoryPipeEnd()
        a.peer = b
        b.peer = a
        return (a, b)
    }

    fileprivate func deliver(_ d: Data) {
        let w: CheckedContinuation<Void, Never>? = lock.withLock {
            inbox.append(d)
            defer { waiter = nil }
            return waiter
        }
        w?.resume()
    }

    fileprivate func peerClosed() {
        let w: CheckedContinuation<Void, Never>? = lock.withLock {
            closed = true
            defer { waiter = nil }
            return waiter
        }
        w?.resume()
    }

    func write(_ data: Data) async throws {
        if lock.withLock({ closed }) { throw ADBError.connectionClosed("closed") }
        peer?.deliver(data)
    }

    func read(max: Int, timeout: TimeInterval) async throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let (chunk, isClosed): (Data?, Bool) = lock.withLock {
                if !inbox.isEmpty {
                    let n = min(max, inbox.count)
                    let c = inbox.prefix(n)
                    inbox.removeFirst(n)
                    return (Data(c), closed)
                }
                return (nil, closed)
            }
            if let chunk { return chunk }
            if isClosed { throw ADBError.connectionClosed("eof") }
            if Date() >= deadline { close(); throw ADBError.timeout }
            // Kısa uykuyla bekle (yeni veri ya da kapanma uyandırır).
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                let ready: Bool = lock.withLock {
                    if !inbox.isEmpty || closed { return true }
                    waiter = c
                    return false
                }
                if ready { c.resume() } else {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) { [weak self] in
                        guard let self else { return }
                        let w: CheckedContinuation<Void, Never>? = self.lock.withLock {
                            defer { self.waiter = nil }
                            return self.waiter
                        }
                        w?.resume()
                    }
                }
            }
        }
    }

    func close() {
        let first: Bool = lock.withLock {
            if closed { return false }
            closed = true
            return true
        }
        peerClosed()
        if first { peer?.peerClosed() }
    }
}

// MARK: Sahte Android TV (adbd)

final class FakeADBDevice: @unchecked Sendable {
    private let lock = NSLock()
    var knownKeys: [Data] = []             // Android biçimli açık anahtarlar
    var approveNewKeys = true
    var features = "cmd,shell_v2"
    var maxData: UInt32 = 4096
    var installedVersion: String?
    /// Eski kimlikli paketin sürümü (kurulu değilse nil).
    var legacyVersion: String?
    var legacyRunning = false
    var installOutput = "Success\n"
    var running = false
    var replyWithSTLS = false

    private(set) var commands: [String] = []
    private(set) var receivedAPK = Data()
    private(set) var pushedPath: String?
    private(set) var approvalPrompts = 0
    private(set) var largestWrite = 0

    func log(_ s: String) { lock.withLock { commands.append(s) } }
    var commandList: [String] { lock.withLock { commands } }

    private struct Stream {
        var service: String
        var clientID: UInt32
        var input = Data()
        var expect: Int?
        var pendingOut: [Data] = []
        var closeAfterSend = false
        var waitingOkay = false
    }

    /// Cihaz tarafı döngüsü: bağlantı kapanana dek çerçeveleri işler.
    func serve(_ io: ADBByteStream) async {
        var buffer = Data()
        var streams: [UInt32: Stream] = [:]
        var nextID: UInt32 = 100
        var token = Data()
        var authorized = false

        func send(_ m: ADBMessage) async { try? await io.write(m.encoded()) }
        func newToken() -> Data { Data((0..<20).map { _ in UInt8.random(in: 0...255) }) }
        func online() async {
            authorized = true
            await send(ADBMessage(.cnxn, ADBMessage.version, maxData,
                                  Data("device::ro.product.model=FakeTV;features=\(features)\u{0}".utf8)))
        }
        func flush(_ id: UInt32) async {
            guard var s = streams[id], !s.waitingOkay else { return }
            if !s.pendingOut.isEmpty {
                let d = s.pendingOut.removeFirst()
                s.waitingOkay = true
                streams[id] = s
                await send(ADBMessage(.wrte, id, s.clientID, d))
            } else if s.closeAfterSend {
                streams[id] = nil
                await send(ADBMessage(.clse, id, s.clientID))
            }
        }
        func respond(_ id: UInt32, _ text: String) async {
            streams[id]?.pendingOut = text.isEmpty ? [] : [Data(text.utf8)]
            streams[id]?.closeAfterSend = true
            await flush(id)
        }

        while true {
            do {
                while buffer.count < 24 { buffer.append(try await io.read(max: 65536, timeout: 30)) }
                let h = try ADBMessage.decodeHeader(buffer.prefix(24))
                while buffer.count < 24 + Int(h.length) { buffer.append(try await io.read(max: 65536, timeout: 30)) }
                let data = Data(buffer[buffer.startIndex + 24 ..< buffer.startIndex + 24 + Int(h.length)])
                buffer.removeFirst(24 + Int(h.length))
                XCTAssertEqual(h.checksum, ADBMessage.checksum(data))
                let m = ADBMessage(rawCommand: h.command, arg0: h.arg0, arg1: h.arg1, data: data)
                lock.withLock { largestWrite = max(largestWrite, m.kind == .wrte ? data.count : 0) }

                switch m.kind {
                case .cnxn:
                    if replyWithSTLS { await send(ADBMessage(.stls, 1, 0)); continue }
                    token = newToken()
                    await send(ADBMessage(.auth, 1, 0, token))
                case .auth where m.arg0 == 2:
                    if knownKeys.contains(where: { Self.verify(publicKey: $0, token: token, signature: m.data) }) {
                        await online()
                    } else {
                        token = newToken()
                        await send(ADBMessage(.auth, 1, 0, token))
                    }
                case .auth where m.arg0 == 3:
                    lock.withLock { approvalPrompts += 1 }
                    let text = String(decoding: m.data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\u{0}"))
                    let b64 = String(text.split(separator: " ").first ?? "")
                    if approveNewKeys, let key = Data(base64Encoded: b64) {
                        knownKeys.append(key)
                        await online()
                    }
                case .open where authorized:
                    let service = String(decoding: m.data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\u{0}"))
                    log(service)
                    let id = nextID
                    nextID += 1
                    if service.hasPrefix("exec:cmd") && !features.contains("cmd") {
                        await send(ADBMessage(.clse, 0, m.arg0))
                        continue
                    }
                    streams[id] = Stream(service: service, clientID: m.arg0)
                    await send(ADBMessage(.okay, id, m.arg0))
                    if service.hasPrefix("shell:") {
                        await respond(id, shellOutput(String(service.dropFirst(6))))
                    } else if service.hasPrefix("exec:cmd package install") {
                        streams[id]?.expect = Int(service.split(separator: " ").last ?? "") ?? 0
                    }
                case .okay:
                    guard streams[m.arg1] != nil else { continue }
                    streams[m.arg1]?.waitingOkay = false
                    await flush(m.arg1)
                case .wrte:
                    let id = m.arg1
                    guard var s = streams[id] else { continue }
                    s.input.append(m.data)
                    streams[id] = s
                    await send(ADBMessage(.okay, id, s.clientID))
                    if let n = s.expect, s.input.count >= n {
                        lock.withLock { receivedAPK = s.input }
                        if installOutput.contains("Success") { installedVersion = "0.7.0" }
                        streams[id]?.expect = nil
                        await respond(id, installOutput)
                    } else if s.service == "sync:" {
                        await handleSync(id, &streams, send: send)
                    }
                case .clse:
                    streams[m.arg1] = nil
                default:
                    continue
                }
            } catch {
                io.close()
                return
            }
        }
    }

    private func handleSync(_ id: UInt32, _ streams: inout [UInt32: Stream],
                            send: (ADBMessage) async -> Void) async {
        guard var s = streams[id] else { return }
        var d = s.input
        var file = Data()
        var done = false
        while d.count >= 8 {
            let tag = String(decoding: d.prefix(4), as: UTF8.self)
            let len = Int(d.readLE32(at: 4))
            if tag == "DONE" || tag == "QUIT" { done = tag == "DONE"; d.removeFirst(8); break }
            guard d.count >= 8 + len else { return }
            let body = d.dropFirst(8).prefix(len)
            if tag == "SEND" { lock.withLock { pushedPath = String(decoding: body, as: UTF8.self) } }
            if tag == "DATA" { file.append(body) }
            d.removeFirst(8 + len)
        }
        if done {
            lock.withLock { receivedAPK = file }
            s.input = Data()
            streams[id] = s
            var okay = Data("OKAY".utf8); okay.appendLE(0)
            await send(ADBMessage(.wrte, id, s.clientID, okay))
            streams[id]?.waitingOkay = true
        }
    }

    func shellOutput(_ cmd: String) -> String {
        let legacy = TVApp.legacyAndroidPackage
        if cmd == "pm list packages \(legacy)" { return legacyVersion == nil ? "" : "package:\(legacy)x\npackage:\(legacy)\n" }
        if cmd == "dumpsys package \(legacy)" {
            guard let v = legacyVersion else { return "" }
            return "Packages:\r\n  Package [\(legacy)] (abc):\r\n    versionName=\(v)\r\n"
        }
        if cmd == "pidof \(legacy)" { return legacyRunning ? "999\n" : "" }
        if cmd.hasPrefix("monkey -p \(legacy)") { legacyRunning = true; return "Events injected: 1\n" }
        if cmd.hasPrefix("dumpsys package") {
            guard let v = installedVersion else { return "" }
            return "Packages:\r\n  Package [com.ninotranslator.tv] (abc):\r\n    versionCode=7 minSdk=21\r\n    versionName=\(v)\r\n"
        }
        if cmd.hasPrefix("pidof") { return running ? "1234\n" : "" }
        if cmd.hasPrefix("pm uninstall") { installedVersion = nil; return "Success\n" }
        if cmd.hasPrefix("pm install") {
            if installOutput.contains("Success") { installedVersion = "0.7.0" }
            return installOutput
        }
        if cmd.hasPrefix("am start") { running = true; return "Starting: Intent { cmp=com.ninotranslator.tv/.MainActivity }\n" }
        return ""
    }

    /// adbd gibi: imza, jetonun SHA-1 özeti sayıldığı PKCS#1 v1.5 imzası mı.
    static func verify(publicKey android: Data, token: Data, signature: Data) -> Bool {
        guard android.count == 524 else { return false }
        let n = Data(android[8..<264].reversed())
        let e = android.readLE32(at: 520)
        var eBytes = Data()
        var v = e
        while v > 0 { eBytes.insert(UInt8(v & 0xff), at: 0); v >>= 8 }
        func int(_ d: Data) -> Data { ASN1.tlv(0x02, (d.first ?? 0) & 0x80 != 0 ? Data([0]) + d : d) }
        let der = ASN1.tlv(0x30, int(n) + int(eBytes))
        let attrs: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, nil) else { return false }
        return SecKeyVerifySignature(key, .rsaSignatureDigestPKCS1v15SHA1, token as CFData, signature as CFData, nil)
    }
}

final class FakeADBConnector: ADBConnecting, @unchecked Sendable {
    let device: FakeADBDevice
    var reachable = true
    private(set) var hosts: [String] = []
    init(_ device: FakeADBDevice) { self.device = device }

    func connect(host: String, port: UInt16, timeout: TimeInterval) async throws -> ADBByteStream {
        hosts.append("\(host):\(port)")
        guard reachable else { throw ADBError.unreachable("refused") }
        let (client, server) = MemoryPipeEnd.pair()
        let device = self.device
        Task.detached { await device.serve(server) }
        return client
    }
}

// MARK: Testler

final class TVHelperADBTests: XCTestCase {
    /// `adb keygen` ile üretilmiş, yalnız bu test için atılabilir anahtar ve onun `.pub` satırı (ad kısmı atıldı).
    static let vectorPEM = """
    -----BEGIN PRIVATE KEY-----
    MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDWxlFlQBQBHNr1
    8V7URcHns2v6wZ8wClXxMR2C2tUqTJAjf662pPFWxDX8/TAEaHEGRId+7AibeIjA
    YUPd7fKLL2Qb7BWpPf9/cL6mmJKBEJOWWibDDVTTwXIIanQCZAympBNhm27Xws1P
    VY3QrCMkaV0LOS73Dy/2WXIA5DDa2qJBD1jZPwU5nXSjXgNqhOsHD7CmIsnpd4sF
    Wyx0/5DdU+SZ9fXs1bzd0iW58j4ae8FlQULje1Jek5hy+tnW7DBj+Re1xzNGc2YU
    5zAER7exJ5s9IOhKp2im7suCCzxQk741MNmTzvq2RyE1N6FcVyXkXhQA7AlJGWou
    FC36p60fAgMBAAECggEAHI1b18qHfkhgQY73jN/DMfLT2Y+xAnl1SG2/nxxJd2ib
    RuTcDLLr1J2cEch1ADkEQZGNs81cLZL+Fxk3JQNTmbZQqDef/5Ja643JAqvI2jii
    bjwI6ChXDRmr97tzNbgoSGUKoJDB0RQ4KCJXCpU/zMDnGi1ddYHC3gyxD7ZGWmm1
    AZVLkBYG45XaqAFgA+kBJ9Fb9LTjBkLfV4yHkWNxt6+nXDWZp4NsnNI//YVIR5RB
    qRoYu9yEmJd8I2Qgf8WtfMvqsPReT/k+z1htheZ8G5xqZbAi5JbpqxSmnSgMBRq8
    8Povg6U6sUojTBlR/zF/jmLlmAhlGROze82t9kCxEQKBgQDzeyV7QVr9pw3NmDLM
    g9t/WbLCcTOenEfoNcLGCs/HLStG+gvEGSCFMUXZ/AgCKL7ovoTlyljaBXFhummS
    HyDSgpc4C5YYaeVBHxHkRc4b+NeXa/683RFFAFPTLnDSFQLPZnKSZo6uhy7oYSIq
    w5YRJsZE36FatnRil/Xunku/cQKBgQDh0VHr5ET3DlDEATjCawvwq5H5PPmjLhoQ
    1pAYjVQWZ0rcPnePgvX9HvwEDcyuP53Pi/XTu8q7x3MzkOC8Ncin5akN9iy4EMvx
    fkB1tUckgpH6yxRfNYd/uQxtUiiftJZhzn1iwfsp+0SSu9MdDSfIPsMqFmBRl0dE
    N93+Xg8NjwKBgFHDcPrLH7s+diwsiCKVxQgnHxic2zDQWnVoWFgZGV1Rlc7n+TuJ
    FJqlyUdCk43mEPYnxIlGQkA0w7aF2x3uxh7rK8zuVyErrokH3gJCTsyl7AA1i/3w
    XvRE/+FTHx/tXlw3kxIGzrNdQitXMxoZRDPOSZanYpAL5VmWnkfbcKSBAoGAHx0+
    UmhjcD8Stc8NSQyC2qhpNpRGOUuy37sQo7FlcqjM0cfxpV6AEl5gjxZvq1qsndpF
    BuWLK5BxuRsvO/+VJD0qq/fNdZcq4p1ouE8//DHZd1rf9bZkcx7GLZHycv7o8ZUI
    BcGAn+o1KpqinhAf+SFctsHah6N2eFnSRqgjHtUCgYAT2c1l+LZOB8dJWyaKHxF/
    tpSrOkGKM3OW1r+TV+KiMlA+jpErdhWPnTKx4cHUg5+QRHzhd4Blc1v93xK2M4Xn
    TXI4tV3rzjmFLSamtk87Bp/BZtQKk/u9QeCfCPPrB528NJkq2rvfgdX9Ju4BrgVp
    bVoT7ztgRfj4LTAnGdkhtw==
    -----END PRIVATE KEY-----

    """
    static let vectorPub = "QAAAACFxCDwfraf6LRQuahlJCewAFF7kJVdcoTc1IUe2+s6T2TA1vpNQPAuCy+6maKdK6CA9myext0cEMOcUZnNGM8e1F/ljMOzW2fpymJNeUnvjQkFlwXsaPvK5JdLdvNXs9fWZ5FPdkP90LFsFi3fpySKmsA8H64RqA16jdJ05BT/ZWA9BotraMOQAcln2Lw/3LjkLXWkkI6zQjVVPzcLXbpthE6SmDGQCdGoIcsHTVA3DJlqWkxCBkpimvnB//z2pFewbZC+L8u3dQ2HAiHibCOx+h0QGcWgEMP38NcRW8aS2rn8jkEwq1dqCHTHxVQown8H6a7PnwUXUXvH12hwBFEBlUcbWREXvcMR/QNYV+iw6r0lHRgo6ogRML4DIMDiFdLIkaYOkjlkgEfXYH6vPzG9fRPjwXwSMc7jStl+fD5n7wBn7gkQZ9BVFfoE4yebGbbXndNbB9E6VFsvXmAT5vsGgka97Q02/nFlIwPruEO9BqycW20zyLTNRDqEblaR/Hm1POqvR7Zys4tvRw9dFn3AWioj+NZqw+y7pUJR7DlmSLIdoxa1samhd7LBjS0LgD4EbJbvTEtgEM+knYDJ6i/I0vxb4NLTl4qdWPuF96EEawN0DUkel+c3rBQwAQlFND0Ca5u36qWL5l0yanqqa8t5S/BnKz3eI2ezYBx5tINnD8Jt0jQEAAQA="

    private var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("nino-adb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temp)
    }

    private func writeAPK(_ size: Int = 10_000) throws -> (URL, Data) {
        let data = Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let url = temp.appendingPathComponent("nino-androidtv_0.7.0.apk")
        try data.write(to: url)
        return (url, data)
    }

    private var keyDir: URL { temp.appendingPathComponent("adb", isDirectory: true) }

    private func fastTiming() -> AndroidTVInstaller.Timing {
        var t = AndroidTVInstaller.Timing()
        t.adb.frame = 5
        t.adb.approval = 5
        t.install = 5
        t.command = 5
        return t
    }

    private func parse(_ lines: [String]) -> [TVHelperEvent] { lines.compactMap(TVHelperEvent.parse) }

    // MARK: Anahtar

    func testPublicKeyMatchesAdbKeygenVector() throws {
        let key = try ADBKey(fileData: Data(Self.vectorPEM.utf8))
        XCTAssertEqual(try key.androidPublicKey().base64EncodedString(), Self.vectorPub)
        XCTAssertEqual(try key.androidPublicKey().count, 524)
    }

    func testKeyFileRoundTripAndReuse() throws {
        let a = try ADBKey.loadOrCreate(in: keyDir)
        let file = keyDir.appendingPathComponent("adbkey")
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertTrue(try String(contentsOf: file).hasPrefix("-----BEGIN PRIVATE KEY-----"))
        let b = try ADBKey.loadOrCreate(in: keyDir)
        XCTAssertEqual(try a.androidPublicKey(), try b.androidPublicKey())
        XCTAssertTrue(FileManager.default.fileExists(atPath: keyDir.appendingPathComponent("adbkey.pub").path))
    }

    func testExistingLegacyKeyFileIsUsed() throws {
        try FileManager.default.createDirectory(at: keyDir, withIntermediateDirectories: true)
        try Data(Self.vectorPEM.utf8).write(to: keyDir.appendingPathComponent("adbkey"))
        let key = try ADBKey.loadOrCreate(in: keyDir)
        XCTAssertEqual(try key.androidPublicKey().base64EncodedString(), Self.vectorPub)
    }

    func testPKCS1PEMIsAccepted() throws {
        let key = try ADBKey(fileData: Data(Self.vectorPEM.utf8))
        let pem = "-----BEGIN RSA PRIVATE KEY-----\n"
            + key.pkcs1.base64EncodedString(options: .lineLength64Characters) + "\n-----END RSA PRIVATE KEY-----\n"
        XCTAssertEqual(try ADBKey(fileData: Data(pem.utf8)).androidPublicKey().base64EncodedString(), Self.vectorPub)
    }

    func testSignatureVerifiesAsSHA1Digest() throws {
        let key = try ADBKey(fileData: Data(Self.vectorPEM.utf8))
        let token = Data((0..<20).map { UInt8($0) })
        let sig = try key.sign(token: token)
        XCTAssertEqual(sig.count, 256)
        XCTAssertTrue(FakeADBDevice.verify(publicKey: try key.androidPublicKey(), token: token, signature: sig))
    }

    // MARK: Çerçeve

    func testMessageFraming() throws {
        let m = ADBMessage(.open, 1, 0, ADBMessage.service("shell:id"))
        let d = m.encoded()
        XCTAssertEqual(d.count, 24 + 9)
        XCTAssertEqual(Array(d.prefix(4)), Array("OPEN".utf8))
        let h = try ADBMessage.decodeHeader(d.prefix(24))
        XCTAssertEqual(h.command, ADBMessage.Command.open.rawValue)
        XCTAssertEqual(h.arg0, 1)
        XCTAssertEqual(h.length, 9)
        XCTAssertEqual(h.checksum, ADBMessage.checksum(Data("shell:id\u{0}".utf8)))
        XCTAssertEqual(d.readLE32(at: 20), ADBMessage.Command.open.rawValue ^ 0xffff_ffff)
        var bad = d.prefix(24)
        bad[bad.startIndex + 20] ^= 0xff
        XCTAssertThrowsError(try ADBMessage.decodeHeader(bad))
        XCTAssertEqual(Array(ADBMessage(.cnxn, 0, 0).encoded().prefix(4)), Array("CNXN".utf8))
    }

    func testBannerParsing() {
        let b = ADBBanner(Data("device::ro.product.name=x;ro.product.model=98U95A;features=cmd,shell_v2\u{0}".utf8))
        XCTAssertEqual(b.systemType, "device")
        XCTAssertEqual(b.model, "98U95A")
        XCTAssertTrue(b.features.contains("cmd"))
    }

    func testVersionAndInstallOutputParsing() {
        XCTAssertEqual(AndroidTVInstaller.installedVersion("  versionCode=3\n    versionName=0.6.2\n"), "0.6.2")
        XCTAssertNil(AndroidTVInstaller.installedVersion("Unable to find package: com.ninotranslator.tv\n"))
        XCTAssertNil(AndroidTVInstaller.installProblem("Performing Streamed Install\nSuccess\n"))
        XCTAssertEqual(AndroidTVInstaller.installProblem("Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]")?.code, "NotEnoughSpace")
        XCTAssertEqual(AndroidTVInstaller.installProblem("Failure [INSTALL_FAILED_OLDER_SDK]")?.code, "InstallFailed")
        XCTAssertEqual(AndroidTVInstaller.installProblem("")?.code, "InstallFailed")
    }

    // MARK: El sıkışma

    func testHandshakeWithKnownKeyNeedsNoApproval() async throws {
        let device = FakeADBDevice()
        let key = try ADBKey(fileData: Data(Self.vectorPEM.utf8))
        device.knownKeys = [try key.androidPublicKey()]
        let stream = try await FakeADBConnector(device).connect(host: "tv", port: 5555, timeout: 1)
        let adb = ADBConnection(stream: stream)
        let asked = LockedBox(false)
        let banner = try await adb.handshake(key: key, onApprovalNeeded: { asked.mutate { $0 = true } })
        XCTAssertEqual(banner.model, "FakeTV")
        XCTAssertFalse(asked.value)
        XCTAssertEqual(device.approvalPrompts, 0)
        let out = try await adb.shell("pidof x")
        XCTAssertEqual(out, "")
        XCTAssertEqual(device.commandList, ["shell:pidof x"])
        await adb.close()
    }

    func testHandshakeUnknownKeySendsPublicKeyAndWaits() async throws {
        let device = FakeADBDevice()
        let key = try ADBKey.generate()
        let stream = try await FakeADBConnector(device).connect(host: "tv", port: 5555, timeout: 1)
        let adb = ADBConnection(stream: stream)
        let asked = LockedBox(0)
        _ = try await adb.handshake(key: key, onApprovalNeeded: { asked.mutate { $0 += 1 } })
        XCTAssertEqual(asked.value, 1)
        XCTAssertEqual(device.approvalPrompts, 1)
        XCTAssertEqual(device.knownKeys, [try key.androidPublicKey()])
        let negotiated = await adb.maxData
        XCTAssertEqual(negotiated, 4096)
        await adb.close()
    }

    func testNotApprovedTimesOut() async throws {
        let device = FakeADBDevice()
        device.approveNewKeys = false
        let stream = try await FakeADBConnector(device).connect(host: "tv", port: 5555, timeout: 1)
        var t = ADBConnection.Timing()
        t.approval = 0.3
        let adb = ADBConnection(stream: stream, timing: t)
        do {
            _ = try await adb.handshake(key: try ADBKey.generate())
            XCTFail("onay olmadan bağlanmamalı")
        } catch let e as ADBError {
            XCTAssertEqual(e, .notApproved)
        }
    }

    func testTLSRequestFailsClearly() async throws {
        let device = FakeADBDevice()
        device.replyWithSTLS = true
        let stream = try await FakeADBConnector(device).connect(host: "tv", port: 5555, timeout: 1)
        let adb = ADBConnection(stream: stream)
        do {
            _ = try await adb.handshake(key: try ADBKey.generate())
            XCTFail()
        } catch let e as ADBError {
            XCTAssertEqual(e, .tlsRequired)
        }
    }

    // MARK: Kurulum (uygulama içi yardımcı, aynı JSON olaylar)

    private func runHelper(_ device: FakeADBDevice, connector: FakeADBConnector? = nil, apk: URL,
                           keepLegacy: Bool = false) async -> (Int32, [String]) {
        let helper = InProcessTVHelper(connector: connector ?? FakeADBConnector(device), ports: FakePorts(),
                                       network: FakeNetwork(), androidTiming: fastTiming())
        let lines = LockedBox<[String]>([])
        let code = await helper.run(TVHelperClient.androidInstallArguments(host: "192.168.0.110", package: apk,
                                                                           version: "0.7.0", keyDir: keyDir,
                                                                           keepLegacy: keepLegacy)
                                    + ["--exit-with-input"],
                                    emit: { l in lines.mutate { $0.append(l) } }, log: { _ in })
        return (code, lines.value)
    }

    func testFreshInstallViaCmdPackage() async throws {
        let device = FakeADBDevice()
        let (apk, bytes) = try writeAPK(20_000)
        let (code, lines) = await runHelper(device, apk: apk)
        XCTAssertEqual(code, 0)
        XCTAssertEqual(parse(lines), [.approve, .done(version: "0.7.0", installed: true)])
        XCTAssertEqual(device.receivedAPK, bytes)
        XCTAssertLessThanOrEqual(device.largestWrite, 4096)
        XCTAssertEqual(device.commandList, [
            "shell:dumpsys package com.ninotranslator.tv",
            "exec:cmd package install -r -S 20000",
            "shell:appops set com.ninotranslator.tv SYSTEM_ALERT_WINDOW allow",
            "shell:am start -n com.ninotranslator.tv/.MainActivity",
        ])
        // İkinci kez: anahtar dosyadan, TV onay sormaz; sürüm güncel → kurulmaz, uygulama zaten çalışıyor.
        let (code2, lines2) = await runHelper(device, apk: apk)
        XCTAssertEqual(code2, 0)
        XCTAssertEqual(parse(lines2), [.done(version: "0.7.0", installed: false)])
        XCTAssertEqual(device.approvalPrompts, 1)
    }

    // MARK: Sahadaki eski TV uygulaması

    func testOnlyLegacyInstalledOpensLegacyWithoutInstalling() async throws {
        let device = FakeADBDevice()
        device.legacyVersion = "0.5.1"
        let (apk, _) = try writeAPK()
        let legacy = TVApp.legacyAndroidPackage
        let (code, lines) = await runHelper(device, apk: apk, keepLegacy: true)
        XCTAssertEqual(code, 0)
        XCTAssertEqual(parse(lines), [.approve, .legacy(version: "0.5.1")])
        XCTAssertTrue(device.receivedAPK.isEmpty, "eski uygulama varken yenisi kendiliğinden kurulmaz")
        XCTAssertEqual(device.commandList, [
            "shell:dumpsys package com.ninotranslator.tv",
            "shell:pm list packages \(legacy)",
            "shell:dumpsys package \(legacy)",
            "shell:appops set \(legacy) SYSTEM_ALERT_WINDOW allow",
            "shell:pidof \(legacy)",
            "shell:monkey -p \(legacy) -c android.intent.category.LEANBACK_LAUNCHER 1",
        ])
        XCTAssertTrue(device.legacyRunning)
        XCTAssertFalse(device.commandList.contains { $0.contains("uninstall") })

        // Kullanıcı yenisini istedi: eskinin yanına kurulur, eski kaldırılmaz, açılan yenisidir.
        let (_, upgrade) = await runHelper(device, apk: apk, keepLegacy: false)
        XCTAssertEqual(parse(upgrade).last, .done(version: "0.7.0", installed: true))
        XCTAssertEqual(device.commandList.last, "shell:am start -n com.ninotranslator.tv/.MainActivity")
        XCTAssertFalse(device.commandList.contains { $0.contains("uninstall") })
        XCTAssertEqual(device.legacyVersion, "0.5.1")
    }

    func testBothInstalledOpensNew() async throws {
        let device = FakeADBDevice()
        device.installedVersion = "0.7.0"
        device.legacyVersion = "0.5.1"
        let (apk, _) = try writeAPK()
        let (_, lines) = await runHelper(device, apk: apk, keepLegacy: true)
        XCTAssertEqual(parse(lines).last, .done(version: "0.7.0", installed: false))
        XCTAssertEqual(device.commandList.last, "shell:am start -n com.ninotranslator.tv/.MainActivity")
        XCTAssertFalse(device.commandList.contains { $0.contains(TVApp.legacyAndroidPackage) })
    }

    func testNeitherInstalledInstallsNew() async throws {
        let device = FakeADBDevice()
        let (apk, _) = try writeAPK()
        let (_, lines) = await runHelper(device, apk: apk, keepLegacy: true)
        XCTAssertEqual(parse(lines).last, .done(version: "0.7.0", installed: true))
        XCTAssertTrue(device.commandList.contains("shell:pm list packages \(TVApp.legacyAndroidPackage)"))
        XCTAssertFalse(device.commandList.contains { $0.hasPrefix("shell:monkey") })
    }

    func testPackageListMatchIsExact() {
        let name = TVApp.legacyAndroidPackage
        XCTAssertFalse(AndroidTVInstaller.listsPackage("package:\(name)x\n", name))
        XCTAssertTrue(AndroidTVInstaller.listsPackage("package:\(name)x\r\npackage:\(name)\r\n", name))
    }

    func testOlderVersionIsUninstalledFirst() async throws {
        let device = FakeADBDevice()
        device.installedVersion = "0.6.9"
        let (apk, _) = try writeAPK()
        let (_, lines) = await runHelper(device, apk: apk)
        XCTAssertEqual(parse(lines).last, .done(version: "0.7.0", installed: true))
        XCTAssertEqual(device.commandList.prefix(3), [
            "shell:dumpsys package com.ninotranslator.tv",
            "shell:pm uninstall com.ninotranslator.tv",
            "exec:cmd package install -r -S 10000",
        ])
    }

    func testNewerOnTVIsKeptAndStartedIfNotRunning() async throws {
        let device = FakeADBDevice()
        device.installedVersion = "0.10.0"
        let (apk, _) = try writeAPK()
        let (_, lines) = await runHelper(device, apk: apk)
        XCTAssertEqual(parse(lines).last, .done(version: "0.10.0", installed: false))
        XCTAssertEqual(device.commandList, [
            "shell:dumpsys package com.ninotranslator.tv",
            "shell:appops set com.ninotranslator.tv SYSTEM_ALERT_WINDOW allow",
            "shell:pidof com.ninotranslator.tv",
            "shell:am start -n com.ninotranslator.tv/.MainActivity",
        ])
    }

    func testOldDeviceFallsBackToSyncAndPmInstall() async throws {
        let device = FakeADBDevice()
        device.features = "shell_v2"
        let (apk, bytes) = try writeAPK(150_000)
        let (_, lines) = await runHelper(device, apk: apk)
        XCTAssertEqual(parse(lines).last, .done(version: "0.7.0", installed: true))
        XCTAssertEqual(device.receivedAPK, bytes)
        XCTAssertEqual(device.pushedPath, "/data/local/tmp/nino-tv.apk,420")
        XCTAssertTrue(device.commandList.contains("sync:"))
        XCTAssertTrue(device.commandList.contains("shell:pm install -r /data/local/tmp/nino-tv.apk"))
    }

    func testNoSpaceAndUnreachableAndNotApprovedCodes() async throws {
        let (apk, _) = try writeAPK()
        let full = FakeADBDevice()
        full.installOutput = "Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]\n"
        var events = parse(await runHelper(full, apk: apk).1)
        guard case let .error(code, message)? = events.last else { return XCTFail() }
        XCTAssertEqual(code, "NotEnoughSpace")
        XCTAssertTrue(message.contains("INSUFFICIENT_STORAGE"))
        XCTAssertEqual(TVInstallError.problem(forHelperCode: code), .noSpace)

        let off = FakeADBDevice()
        let connector = FakeADBConnector(off)
        connector.reachable = false
        events = parse(await runHelper(off, connector: connector, apk: apk).1)
        guard case let .error(code2, _)? = events.last else { return XCTFail() }
        XCTAssertEqual(code2, "Unreachable")
    }

    func testThroughHelperClientWithInProcessRunner() async throws {
        let device = FakeADBDevice()
        let (apk, _) = try writeAPK()
        let helper = InProcessTVHelper(connector: FakeADBConnector(device), ports: FakePorts(), network: FakeNetwork(),
                                       androidTiming: fastTiming())
        let runner = InProcessHelperProcessRunner(helper: helper, fallback: FakeProcesses())
        let client = TVHelperClient(executable: InProcessTVHelper.executableURL, processes: runner, log: .discard)
        XCTAssertTrue(client.isAvailable)
        let seen = LockedBox<[TVHelperEvent]>([])
        let outcome = try await client.run(TVHelperClient.androidInstallArguments(host: "192.168.0.110", package: apk,
                                                                                  version: "0.7.0", keyDir: keyDir),
                                           onEvent: { e in seen.mutate { $0.append(e) } })
        XCTAssertEqual(outcome, .done(version: "0.7.0", installed: true))
        XCTAssertEqual(seen.value, [.approve])

        // samsung-install: IP olmayan adres temiz bir "ulaşılamadı" hatası verir (tv-kurulumu.md §9.2).
        do {
            _ = try await client.run(TVHelperClient.samsungInstallArguments(host: "h", package: apk, version: "1",
                                                                            profiles: temp, log: nil), onEvent: { _ in })
            XCTFail()
        } catch let e as TVInstallError {
            XCTAssertEqual(e.problem, .unreachable)
        }
    }

    func testAndroidScanFindsOpenPorts() async {
        let ports = FakePorts()
        ports.set("192.168.0.110", 5555, true)
        ports.set("192.168.0.40", 5555, true)
        ports.set("192.168.0.41", 8001, true)
        let helper = InProcessTVHelper(connector: FakeADBConnector(FakeADBDevice()), ports: ports,
                                       network: FakeNetwork([NetworkInterface(name: "en0", address: "192.168.0.10")]))
        let runner = InProcessHelperProcessRunner(helper: helper, fallback: FakeProcesses())
        let client = TVHelperClient(executable: InProcessTVHelper.executableURL, processes: runner, log: .discard)
        let hosts = await client.androidScan()
        XCTAssertEqual(hosts, ["192.168.0.40", "192.168.0.110"])
    }

    func testCancellingStopsTheHelper() async throws {
        let device = FakeADBDevice()
        device.approveNewKeys = false // onay sonsuza dek beklenir
        let (apk, _) = try writeAPK()
        var timing = fastTiming()
        timing.adb.approval = 60
        let helper = InProcessTVHelper(connector: FakeADBConnector(device), ports: FakePorts(), network: FakeNetwork(),
                                       androidTiming: timing)
        let runner = InProcessHelperProcessRunner(helper: helper, fallback: FakeProcesses())
        let client = TVHelperClient(executable: InProcessTVHelper.executableURL, processes: runner, log: .discard)
        let started = Date()
        let task = Task {
            try await client.run(TVHelperClient.androidInstallArguments(host: "h", package: apk, version: "0.7.0",
                                                                        keyDir: self.keyDir), onEvent: { _ in })
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        _ = try? await task.value
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    // MARK: Gerçek TCP (127.0.0.1, rastgele port)

    func testLoopbackTCPHandshakeAndShell() async throws {
        let device = FakeADBDevice()
        let key = try ADBKey(fileData: Data(Self.vectorPEM.utf8))
        device.knownKeys = [try key.androidPublicKey()]
        let listener = try NWListener(using: .tcp, on: .any)
        let queue = DispatchQueue(label: "test.adb.listener")
        listener.newConnectionHandler = { conn in
            conn.start(queue: queue)
            let stream = NWADBStream(connection: conn, queue: queue)
            Task.detached { await device.serve(stream) }
        }
        let ready = LockedBox<UInt16?>(nil)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.mutate { $0 = listener.port?.rawValue } }
        }
        listener.start(queue: queue)
        defer { listener.cancel() }
        for _ in 0..<100 where ready.value == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        let port = try XCTUnwrap(ready.value)
        XCTAssertNotEqual(port, 5555)

        let stream = try await NWADBConnector().connect(host: "127.0.0.1", port: port, timeout: 3)
        let adb = ADBConnection(stream: stream)
        let banner = try await adb.handshake(key: key)
        XCTAssertEqual(banner.model, "FakeTV")
        device.installedVersion = "0.7.0"
        let out = try await adb.shell("dumpsys package com.ninotranslator.tv")
        XCTAssertEqual(AndroidTVInstaller.installedVersion(out), "0.7.0")
        XCTAssertFalse(out.contains("\r"))
        await adb.close()
    }
}
