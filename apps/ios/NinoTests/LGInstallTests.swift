// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CryptoKit
import XCTest
@testable import Nino

/// LG: Key Server anahtarının çözülmesi, kurulum komutları (sahte kabukla), süre uzatma ve SSH parçaları.
final class LGInstallTests: XCTestCase {
    func testLegacyPEMDecryptsWithPassphrase() throws {
        let pem = try TVCryptoTests.fixture("lg-webos-rsa", "pem")
        let der = try LGInstaller.decodeKey(Bytes(pem), passphrase: "abc123")   // küçük harf de denenir
        XCTAssertEqual(Bytes(Insecure.SHA1.hash(data: der)).hexString.prefix(16), "eaca3b5a0b8a5649")
        XCTAssertNoThrow(try RSAPrivateKey(pkcs1: der))
        XCTAssertThrowsError(try LGInstaller.decodeKey(Bytes(pem), passphrase: "WRONG1")) {
            XCTAssertEqual(($0 as? LGFailure)?.problem, .wrongPassphrase)
        }
        XCTAssertThrowsError(try LGInstaller.decodeKey(Bytes("<html>".utf8), passphrase: "X")) {
            XCTAssertEqual(($0 as? LGFailure)?.problem, .keyServerOff)
        }
        XCTAssertEqual(LegacyPEM.bytesToKey(password: Bytes("a".utf8), salt: Bytes(repeating: 1, count: 8), length: 24).count, 24)
    }

    func testRepliesAndHelpers() {
        XCTAssertEqual(LGInstaller.parseReplies("{\"returnValue\":true}\n{\"details\":{\"state\":\"installed\"}}\n"), .installed)
        XCTAssertEqual(LGInstaller.parseReplies("{\"returnValue\":false,\"errorText\":\"no space left\",\"errorCode\":-5}"),
                       .failed("no space left (errorCode -5)"))
        XCTAssertEqual(LGInstaller.parseReplies("{\"returnValue\":true,\n\"details\":{\"state\":\"installing\"}}"), .pending)
        XCTAssertTrue(LGInstaller.isStorageProblem("ENOSPC"))
        XCTAssertEqual(LGInstaller.version(fromAppInfo: "{ \"id\": \"com.ninotranslator.tv\", \"version\" : \"4.0.3\" }"), "4.0.3")
        XCTAssertEqual(LGInstaller.remainingHours("{\"result\":\"success\",\"errorMsg\":\"999:58:40\"}"), 999)
        XCTAssertTrue(LGInstaller.installCommand(remote: "/media/developer/temp/x.ipk", wait: 60).contains("ipkUrl\":\"/media/developer/temp/x.ipk"))
        let files = TVInstallFiles(root: TVTestFiles.scratch())
        XCTAssertEqual(files.lgKeyFile(host: " 192.168.1.5:80 ").lastPathComponent, "192.168.1.5_80.key")
    }

    func testInstallUploadsVerifiesAndLaunches() throws {
        let shell = FakeLGShell(version: "4.0.1")
        var installer = LGInstaller(shell: shell, log: TVInstallLog(file: TVTestFiles.scratch().appendingPathComponent("l.log")))
        installer.pollInterval = 0.05
        let ipk = TVPackage(bytes: Bytes(repeating: 3, count: 2048), version: "4.0.3", origin: "test")
        XCTAssertEqual(try installer.install(ipk: ipk), TVInstallOutcome(version: "4.0.3", installed: true))
        XCTAssertEqual(shell.uploaded.get(), ipk.bytes)
        XCTAssertTrue(shell.commands.get().contains(LGInstaller.launchCommand))
        XCTAssertEqual(try installer.install(ipk: ipk), TVInstallOutcome(version: "4.0.3", installed: false))
    }

    func testInstallFailureIsReported() throws {
        let shell = FakeLGShell(version: nil)
        shell.installReply = "{\"returnValue\":false,\"errorText\":\"not enough storage\"}"
        let installer = LGInstaller(shell: shell, log: TVInstallLog(file: TVTestFiles.scratch().appendingPathComponent("l.log")))
        XCTAssertThrowsError(try installer.install(ipk: TVPackage(bytes: [1], version: "4.0.3", origin: "t"))) {
            XCTAssertEqual(($0 as? LGFailure)?.problem, .notEnoughSpace)
        }
    }

    func testSessionRenewalOncePerDay() throws {
        let defaults = UserDefaults(suiteName: "tvinstall-\(UUID().uuidString)")!
        let shell = FakeLGShell(version: "4.0.3")
        var installer = LGInstaller(shell: shell, log: TVInstallLog(file: TVTestFiles.scratch().appendingPathComponent("l.log")))
        let asked = LockedValue<[String]>([])
        installer.fetch = { url in
            asked.set(asked.get() + [url.absoluteString])
            return Data(url.path.contains("Reset") ? "{\"result\":\"success\"}".utf8 : "{\"errorMsg\":\"999:59:59\"}".utf8)
        }
        let now = Date()
        XCTAssertEqual(LGSessionRenewal.renewIfDue(host: "192.168.1.5", defaults: defaults, now: now) { try? installer.renewSession() }, 999)
        XCTAssertTrue(asked.get().first?.contains("sessionToken=TOKEN123") == true)
        XCTAssertNil(LGSessionRenewal.renewIfDue(host: "192.168.1.5", defaults: defaults, now: now.addingTimeInterval(3600)) { 1 })
        XCTAssertEqual(LGSessionRenewal.renewIfDue(host: "192.168.1.5", defaults: defaults, now: now.addingTimeInterval(21 * 3600)) { 5 }, 5)
        XCTAssertNotNil(defaults.object(forKey: "lgSessionRenewedAt.192.168.1.5"))
    }

    // MARK: SSH parçaları

    func testSSHPacketsRoundTripWithCipherAndMac() throws {
        for mac in ["hmac-sha2-256", "hmac-sha2-512-etm@openssh.com", "hmac-sha1"] {
            let (a, b) = MemoryPipe.pair()
            let client = SSHPacketCodec(channel: a, reader: ChannelReader(a))
            let server = SSHPacketCodec(channel: b, reader: ChannelReader(b))
            try client.send([1, 2, 3])
            XCTAssertEqual(try server.receive(), [1, 2, 3])
            var k = SSHWriter()
            k.mpint(Bytes.random(32))
            let keys = SSHKeyDerivation(hash: .sha256, sharedMpint: k.bytes, exchangeHash: .random(32), sessionID: .random(32))
            try SSHKeyDerivation.install(keys, codec: client, client: true, cipherOut: "aes128-ctr", cipherIn: "aes256-ctr", macOut: mac, macIn: mac)
            try SSHKeyDerivation.install(keys, codec: server, client: false, cipherOut: "aes256-ctr", cipherIn: "aes128-ctr", macOut: mac, macIn: mac)
            for size in [0, 1, 15, 16, 17, 5000, 40_000] {
                let payload = Bytes((0..<size).map { UInt8(truncatingIfNeeded: $0) })
                try client.send(payload)
                XCTAssertEqual(try server.receive(), payload, "\(mac) \(size)")
                try server.send(payload.reversed())
                XCTAssertEqual(try client.receive(), payload.reversed(), "\(mac) \(size)")
            }
        }
    }

    func testSSHHostSignatureAndEncoding() throws {
        let host = Curve25519.Signing.PrivateKey()
        var blob = SSHWriter()
        blob.string("ssh-ed25519")
        blob.string(Bytes(host.publicKey.rawRepresentation))
        let data = Bytes.random(32)
        var sig = SSHWriter()
        sig.string("ssh-ed25519")
        sig.string(Bytes(try host.signature(for: data)))
        XCTAssertNoThrow(try SSHHostKey.verify(hostKey: blob.bytes, signature: sig.bytes, data: data, negotiated: "ssh-ed25519"))
        XCTAssertThrowsError(try SSHHostKey.verify(hostKey: blob.bytes, signature: sig.bytes, data: .random(32), negotiated: "ssh-ed25519"))

        var w = SSHWriter()
        w.mpint([0x80, 1])
        w.mpint([0, 0, 5])
        XCTAssertEqual(w.bytes, [0, 0, 0, 3, 0, 0x80, 1, 0, 0, 0, 1, 5])
        var r = SSHReader(w.bytes)
        XCTAssertEqual(try r.mpint(), [0x80, 1])
        XCTAssertEqual(try r.mpint(), [5])
        // Oakley grup 14 üreteci 2 ile küçük bir denetim: 2^x · 2^y = 2^(x+y)
        let p = SSHAlgorithms.group14
        let gx = BigNum(2).power(BigNum(12_345), modulus: p)
        let gy = BigNum(2).power(BigNum(67_890), modulus: p)
        XCTAssertEqual((gx * gy) % p, BigNum(2).power(BigNum(80_235), modulus: p))
    }
}

/// Bellekte iki uçlu akış.
final class MemoryPipe: ByteChannel {
    private let inbox = LockedValue<Bytes>([])
    weak var peer: MemoryPipe?
    var receiveTimeout: TimeInterval = 2

    static func pair() -> (MemoryPipe, MemoryPipe) {
        let a = MemoryPipe(), b = MemoryPipe()
        a.peer = b
        b.peer = a
        return (a, b)
    }

    func receive(upTo max: Int) throws -> Bytes {
        let bytes = inbox.get()
        guard !bytes.isEmpty else { throw WireError.timeout }
        let n = min(max, bytes.count)
        inbox.set(Array(bytes[n...]))
        return Array(bytes[0..<n])
    }

    func send(_ bytes: Bytes) throws { peer?.inbox.set((peer?.inbox.get() ?? []) + bytes) }
    func shutdown() {}
}

/// LG geliştirici modunun sahte kabuğu.
final class FakeLGShell: LGShell {
    let version: LockedValue<String?>
    let uploaded = LockedValue<Bytes?>(nil)
    let commands = LockedValue<[String]>([])
    var installReply = "{\"returnValue\":true}\n{\"details\":{\"state\":\"installed\"}}"

    init(version: String?) { self.version = LockedValue(version) }

    func run(_ command: String, input: Bytes?) throws -> (status: Int, output: String) {
        commands.set(commands.get() + [command])
        if command.hasPrefix("cat \(LGInstaller.appInfoPath)") {
            return (0, version.get().map { "{\"id\":\"com.ninotranslator.tv\",\"version\":\"\($0)\"}" } ?? "cat: no such file")
        }
        if command.contains("cat > ") {
            uploaded.set(input)
            return (0, "")
        }
        if command.hasPrefix("wc -c") { return (0, "\(uploaded.get()?.count ?? 0)\n") }
        if command.contains("appInstallService/dev/install") {
            if installReply.contains("installed"), let name = command.split(separator: "_").dropLast().last {
                version.set(String(name))
            }
            return (0, installReply)
        }
        if command.hasPrefix("cat \(LGInstaller.sessionTokenPath)") { return (0, "TOKEN123\n") }
        return (0, "{\"returnValue\":true}")
    }
}
