// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Darwin
import Foundation
import Security
import XCTest
@testable import NinoMacKit

// Samsung kurulumu (tv-kurulumu.md §9): sdb, TV yanıtları, giriş, CSR, PKCS#12, imza, kurulum akışı, hata eşlemesi.

final class SamsungSDBTests: XCTestCase {
    func testFirstCNXNHeaderMatchesTarif() {
        let m = ADBMessage(.cnxn, SDBFrame.version, SDBFrame.maxPayload, Data(SDBConnection.hostBanner.utf8))
        let hex = m.encoded().prefix(24).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, "434e584e" + "00000001" + "00100000" + "14000000" + "8b070000" + "bcb1a7b1")
        XCTAssertEqual(m.encoded().dropFirst(24), Data("host::sdb-net-client".utf8))
    }

    func testFrameChecksAndCapabilityParsing() throws {
        var bad = ADBMessage(.okay, 1, 2, Data([1, 2, 3])).encoded()
        bad[20] ^= 0xff
        XCTAssertThrowsError(try SDBFrame.decodeHeader(bad)) { XCTAssertEqual($0 as? SDBError, .badFrame("Invalid magic in frame")) }
        let cap = SDBConnection.parseCapability(Data(
            "8csecure_protocol:enabled\nplatform_version:6.5\nsdk_toolpath:/home/owner/share/tmp/sdk_tools\n".utf8))
        XCTAssertEqual(cap["platform_version"], "6.5")
        XCTAssertEqual(cap["sdk_toolpath"], "/home/owner/share/tmp/sdk_tools")
        XCTAssertEqual(cap["secure_protocol"], "enabled")
        let dup = SDBConnection.parseCapability(Data("xxa:1\na:2\nurl:http://x\n".utf8))
        XCTAssertEqual(dup["a"], "1")
        XCTAssertNil(dup["url"])
    }

    func testEndlessTokensFailInsteadOfLooping() async throws {
        let server = try FakeSDBServer()
        defer { server.stop() }
        server.tokenLoop = true
        let stream = try await NWADBConnector().connect(host: "127.0.0.1", port: server.port, timeout: 5)
        defer { stream.close() }
        do {
            _ = try await SDBConnection(stream: stream).handshake(key: try ADBKey.generate())
            XCTFail()
        } catch let e as SDBError {
            XCTAssertEqual(e, .protocolError("TV sdb anahtarını kabul etmedi (AUTH)"))
        }
    }

    func testHandshakeAuthShellAndSyncAgainstFakeServer() async throws {
        let server = try FakeSDBServer()
        defer { server.stop() }
        server.applist = [FakeSDBServer.applist(version: "0.9.7")]
        let key = try ADBKey.generate()
        let stream = try await NWADBConnector().connect(host: "127.0.0.1", port: server.port, timeout: 5)
        defer { stream.close() }
        let sdb = SDBConnection(stream: stream)
        let banner = try await sdb.handshake(key: key)
        XCTAssertEqual(banner, "device::tizen-fake")
        XCTAssertTrue(server.with { $0.signatureVerified }, "imza ham jetonun SHA-1'i üzerinden doğrulanmalı")
        let cap = try await sdb.capability()
        XCTAssertEqual(cap["platform_version"], "6.5")
        let applist = try await sdb.shell("0 vd_applist")
        XCTAssertEqual(SamsungOutputs.installedVersion(applist: applist), "0.9.7")
        let big = Data((0..<200_000).map { UInt8($0 % 251) })
        try await sdb.push(big, to: "/home/owner/share/tmp/sdk_tools/x.wgt", mtime: 1_700_000_000)
        XCTAssertEqual(server.with { $0.pushed["/home/owner/share/tmp/sdk_tools/x.wgt"] }, big)
        let duid = try await sdb.shell("0 getduid")
        XCTAssertEqual(SamsungOutputs.duid(from: duid), "CJCHTFRXVXQDQ")
        XCTAssertEqual(server.with { $0.services }, ["capability:", "shell:0 vd_applist", "sync:", "shell:0 getduid"])
        let header = try XCTUnwrap(server.with { $0.cnxnHeaders.first })
        XCTAssertEqual(header.prefix(24).map { String(format: "%02x", $0) }.joined(),
                       "434e584e000000010010000014000000" + "8b070000bcb1a7b1")
    }
}

final class SamsungOutputsTests: XCTestCase {
    func testApplistDuidAndVersions() {
        let sample = "\t-------------app_title  =  Nino----------------------------\n"
            + "\t-------------app_tizen_id  =  NinoTVApps.Nino----------------\n"
            + "\t-------------app_version  =  0.9.7-----------------------------\n"
            + "\t------------------------------------------------------------------------\n"
        XCTAssertEqual(SamsungOutputs.installedVersion(applist: sample), "0.9.7")
        let other = sample.replacingOccurrences(of: "NinoTVApps.Nino", with: "Other.App")
        XCTAssertNil(SamsungOutputs.installedVersion(applist: other))
        XCTAssertNil(SamsungOutputs.installedVersion(applist: ""))
        XCTAssertEqual(SamsungOutputs.duid(from: "CJCHTFRXVXQDQ\n"), "CJCHTFRXVXQDQ")
        XCTAssertNil(SamsungOutputs.duid(from: "error: closed"))
        XCTAssertNil(SamsungOutputs.duid(from: "short"))
        XCTAssertEqual(SamsungOutputs.safeDUID("AB/CD="), "AB_CD_")
        XCTAssertTrue(SamsungOutputs.isTooOld("2.4"))
        XCTAssertFalse(SamsungOutputs.isTooOld("3.0"))
        XCTAssertFalse(SamsungOutputs.isTooOld(""))
        XCTAssertTrue(SamsungOutputs.needsDeviceProfile("3.0"))
        XCTAssertTrue(SamsungOutputs.needsDeviceProfile("4.0"))
        XCTAssertFalse(SamsungOutputs.needsDeviceProfile("5.0"))
        XCTAssertFalse(SamsungOutputs.needsDeviceProfile("6.5"))
    }

    func testClassificationOfTarifExamples() {
        typealias C = SamsungOutputs.InstallClass
        let cases: [(String, C)] = [
            ("Push complete.\napp_id[NinoTVApps.Nino] installing[100]\nspend time for pkgcmd is [1234]ms\ncmd_ret:0", .success),
            ("Pull skipped or failed: x", .success),
            ("app_id[NinoTVApps.Nino] install failed[118, -12]\nreason: Check certificate error : :Package with the same id and different certificate has been already installed.:<-12>", .certificateMismatch),
            ("app_id[NinoTVApps.Nino] install failed[118, -11], reason: Author certificate not match :", .certificateMismatch),
            ("install failed[118, -12]\nreason: Check certificate error : :Invalid format of certificate in signature.:<-2>", .certificateInvalid),
            ("install failed[118, -12]\nreason: Check certificate error : :Certificate in signature is expired.:<-6>", .certificateInvalid),
            ("install failed[118, -12] Check certificate error : :Certificate in signature is not valid yet.:<-7>", .clockBehind),
            ("app_id[NinoTVApps.Nino] install failed[118, -22]\nreason: Security error : :Invalid function parameter was given:<2>", .packageBlocked),
            ("app_id[NinoTVApps.Nino] download failed[116]", .noSpace),
            ("install failed[118, -4]", .notEligible),
            ("Push complete.\ninstall failed: SDBError: connection reset by peer", .connectionLost),
            ("install failed[1]", .other),
        ]
        for (text, expected) in cases { XCTAssertEqual(SamsungOutputs.classify(text), expected, text) }
        XCTAssertEqual(C.certificateMismatch.code, "CertificateMismatch")
        XCTAssertEqual(C.clockBehind.code, "TvClockWrong")
        XCTAssertTrue(C.other.retriesAfterUninstall)
        XCTAssertFalse(C.certificateInvalid.retriesAfterUninstall)
        // Her kod kartta tanınır.
        for c in [C.connectionLost, .notEligible, .noSpace, .certificateInvalid, .clockBehind, .certificateMismatch,
                  .packageBlocked, .other] {
            XCTAssertEqual(TVInstallError.problem(forHelperCode: c.code).rawValue.isEmpty, false)
        }
        XCTAssertEqual(TVInstallError.problem(forHelperCode: "PackageBlocked"), .packageBlocked)
    }

    func testFailureDetail() {
        XCTAssertEqual(SamsungOutputs.failureDetail(""), "TV'den yanıt gelmedi")
        let d = SamsungOutputs.failureDetail("Push complete.\napp_id[x] install failed[118, -11], reason: Author certificate not match :\nreason: a\nreason: a\nerror b\nfail c")
        XCTAssertEqual(d, "app_id[x] install failed[118, -11], reason: Author certificate not match : | reason: a | error b")
        XCTAssertEqual(SamsungOutputs.failureDetail("a\nb\nc\nd"), "b | c | d")
        XCTAssertTrue(SamsungOutputs.failureDetail(String(repeating: "error ", count: 200)).hasSuffix("…"))
    }
}

final class SamsungLoginTests: XCTestCase {
    func testURLAndCallbackParsing() {
        XCTAssertEqual(SamsungLogin.url().absoluteString,
                       "https://account.samsung.com/accounts/be1dce529476c1a6d407c4c7578c31bd/signInGate?locale=&clientId=v285zxnl3h&redirect_uri=http%3A%2F%2Flocalhost%3A4794%2Fsignin%2Fcallback&state=accountcheckdogeneratedstatetext&tokenType=TOKEN")
        let body = Data("code=%7B%22access_token%22%3A%22TOK%22%2C%22userId%22%3A%22U1%22%2C%22inputEmailID%22%3A%22a%40b.c%22%2C%22token_type%22%3A%22bearer%22%7D&state=accountcheckdogeneratedstatetext".utf8)
        let (acc, _) = SamsungLogin.account(fromCallbackBody: body)
        XCTAssertEqual(acc, SamsungLogin.Account(accessToken: "TOK", userID: "U1", email: "a@b.c"))
        let (none, summary) = SamsungLogin.account(fromCallbackBody: Data("error=access_denied&state=x&code=".utf8))
        XCTAssertNil(none)
        XCTAssertEqual(summary, "error=access_denied, state=x, code")
        XCTAssertNil(SamsungLogin.account(fromCallbackBody: Data(String(decoding: body, as: UTF8.self).replacingOccurrences(of: "state=acc", with: "state=zz").utf8)).0)
    }

    private func freePort() -> UInt16 { freeLoopbackPort() }

    private func post(_ port: UInt16, path: String, body: String) async throws -> Int {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        req.httpMethod = "POST"
        req.httpBody = Data(body.utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (_, r) = try await URLSession(configuration: .ephemeral).data(for: req)
        return (r as? HTTPURLResponse)?.statusCode ?? 0
    }

    func testListenerAcceptsCallbackOnLoopback() async throws {
        let port = freePort()
        let listener = SocketLoginListener(port: port, loopbackOnly: true)
        let ready = LockedBox(false)
        let task = Task { try await listener.waitForAccount(timeout: 20, onReady: { ready.mutate { $0 = true } }) }
        try await samsungWait { ready.value }
        let notFound = try await post(port, path: "/other", body: "")
        XCTAssertEqual(notFound, 404)
        let bad = try await post(port, path: "/signin/callback", body: "state=accountcheckdogeneratedstatetext&code=")
        XCTAssertEqual(bad, 400)
        let code = "%7B%22access_token%22%3A%22T%22%2C%22userId%22%3A%22U%22%7D"
        let ok = try await post(port, path: "/signin/callback?x=1", body: "code=\(code)&state=accountcheckdogeneratedstatetext")
        XCTAssertEqual(ok, 200)
        let account = try await task.value
        XCTAssertEqual(account, SamsungLogin.Account(accessToken: "T", userID: "U", email: ""))
    }

    func testTimeoutCarriesSummaryAndBusyPortFails() async throws {
        let port = freePort()
        let listener = SocketLoginListener(port: port, loopbackOnly: true)
        let ready = LockedBox(false)
        let task = Task { try await listener.waitForAccount(timeout: 1.5, onReady: { ready.mutate { $0 = true } }) }
        try await samsungWait { ready.value }
        // Aynı port ikinci kez açılamaz.
        do {
            _ = try await SocketLoginListener(port: port, loopbackOnly: true).waitForAccount(timeout: 1, onReady: {})
            XCTFail()
        } catch let f as SamsungLogin.LoginError {
            guard case .portUnavailable = f else { return XCTFail("\(f)") }
        }
        _ = try await post(port, path: "/signin/callback", body: "error=denied&state=accountcheckdogeneratedstatetext")
        do { _ = try await task.value; XCTFail() } catch let f as SamsungLogin.LoginError {
            XCTAssertEqual(f, .timedOut(summary: "error=denied, state=accountcheckdogeneratedstatetext"))
        }
    }

    func testCancellationStopsListener() async throws {
        let listener = SocketLoginListener(port: freePort(), loopbackOnly: true)
        let task = Task { try await listener.waitForAccount(timeout: 60, onReady: {}) }
        try await Task.sleep(nanoseconds: 100_000_000)
        let started = Date()
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }
}

final class SamsungCryptoTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nino-samsung-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testCSRsAreValidPKCS10WithUppercaseURNs() throws {
        let key = try ADBKey.generate()
        let author = SamsungCSR.pem(try SamsungCSR.author(key: key.privateKey))
        let dist = SamsungCSR.pem(try SamsungCSR.distributor(key: key.privateKey, email: "a@b.c", duid: "CJCHTFRXVXQDQ"))
        let text = String(decoding: dist, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("-----BEGIN CERTIFICATE REQUEST-----\n"))
        XCTAssertTrue(text.split(separator: "\n").dropFirst().dropLast().allSatisfy { $0.count <= 64 })
        try author.write(to: dir.appendingPathComponent("author.csr"))
        try dist.write(to: dir.appendingPathComponent("distributor.csr"))
        let a = try OpenSSL.ok(["req", "-in", "author.csr", "-verify", "-noout", "-text"], in: dir)
        XCTAssertTrue(a.contains("CN") && a.contains("Nino"), a)
        let d = try OpenSSL.ok(["req", "-in", "distributor.csr", "-verify", "-noout", "-text"], in: dir)
        XCTAssertTrue(d.contains("URI:URN:tizen:packageid="), d)
        XCTAssertTrue(d.contains("URI:URN:tizen:deviceid=CJCHTFRXVXQDQ"), d)
        XCTAssertTrue(d.contains("TizenSDK"), d)
        XCTAssertTrue(d.contains("a@b.c"), d)
        // DER: SAN'daki URI'ler [6] IA5 (0x86) ve büyük harf.
        let san = SamsungCSR.distributorSAN(duid: "X")
        XCTAssertEqual(san[2], 0x86)
        XCTAssertNotNil(san.range(of: Data("URN:tizen:deviceid=X".utf8)))
    }

    func testPKCS12RoundTripAndOpenSSLInterop() throws {
        let ca = try TestCA(dir: dir.appendingPathComponent("ca"))
        let key = try ADBKey.generate()
        let leafPEM = try ca.issue(csrPEM: SamsungCSR.pem(try SamsungCSR.author(key: key.privateKey)), name: "leaf")
        let leaf = X509Info.certificates(fromPEMOrDER: leafPEM)[0]
        let p12 = try PKCS12.build(privateKeyPKCS1: key.pkcs1, certificates: [leaf, ca.intermediateDER], password: "ABCDEF0123")
        let back = try PKCS12.parse(p12, password: "ABCDEF0123")
        XCTAssertEqual(back.privateKey, key.pkcs1)
        XCTAssertEqual(back.certificates, [leaf, ca.intermediateDER])
        XCTAssertThrowsError(try PKCS12.parse(p12, password: "wrong"))

        // openssl bizim dosyamızı açabilmeli.
        try p12.write(to: dir.appendingPathComponent("ours.p12"))
        let info = try OpenSSL.ok(["pkcs12", "-in", "ours.p12", "-passin", "pass:ABCDEF0123", "-nodes", "-info"], in: dir)
        XCTAssertTrue(info.contains("3DES") || info.contains("des-ede3") || info.contains("pbeWithSHA1And3-KeyTripleDES-CBC"), info)
        XCTAssertTrue(info.contains("BEGIN CERTIFICATE"), info)

        // openssl'in yazdığı (3DES ve varsayılan) dosyaları biz açabilmeliyiz.
        try key.pem().write(to: dir.appendingPathComponent("leaf.key"), atomically: true, encoding: .utf8)
        try leafPEM.write(to: dir.appendingPathComponent("leaf.pem"))
        try FileManager.default.copyItem(at: ca.dir.appendingPathComponent("inter.pem"), to: dir.appendingPathComponent("inter.pem"))
        _ = try OpenSSL.ok(["pkcs12", "-export", "-inkey", "leaf.key", "-in", "leaf.pem", "-certfile", "inter.pem",
                            "-keypbe", "PBE-SHA1-3DES", "-certpbe", "PBE-SHA1-3DES", "-macalg", "sha1",
                            "-passout", "pass:5A5A", "-out", "legacy.p12"], in: dir)
        let legacy = try PKCS12.parse(try Data(contentsOf: dir.appendingPathComponent("legacy.p12")), password: "5A5A")
        XCTAssertEqual(legacy.privateKey, key.pkcs1)
        XCTAssertEqual(legacy.certificates.first, leaf)
        XCTAssertEqual(Set(legacy.certificates), Set([leaf, ca.intermediateDER]))
        if try OpenSSL.run(["pkcs12", "-export", "-inkey", "leaf.key", "-in", "leaf.pem", "-passout", "pass:x",
                            "-out", "modern.p12"], in: dir).code == 0 {
            let modern = try PKCS12.parse(try Data(contentsOf: dir.appendingPathComponent("modern.p12")), password: "x")
            XCTAssertEqual(modern.privateKey, key.pkcs1)
        }
    }

    /// Sertifikaları RC2-40 ile şifreli eski biçim; yaprak açık anahtardan da bulunur; gömülü PEM'lerin yeri.
    func testPKCS12RC2CertificatesLeafMatchAndBundledCAs() throws {
        let ca = try TestCA(dir: dir.appendingPathComponent("ca"))
        let key = try ADBKey.generate()
        let leafPEM = try ca.issue(csrPEM: SamsungCSR.pem(try SamsungCSR.author(key: key.privateKey)), name: "leaf")
        let leaf = X509Info.certificates(fromPEMOrDER: leafPEM)[0]
        try key.pem().write(to: dir.appendingPathComponent("leaf.key"), atomically: true, encoding: .utf8)
        try leafPEM.write(to: dir.appendingPathComponent("leaf.pem"))
        try FileManager.default.copyItem(at: ca.dir.appendingPathComponent("inter.pem"), to: dir.appendingPathComponent("inter.pem"))
        let r = try OpenSSL.run(["pkcs12", "-export", "-inkey", "leaf.key", "-in", "leaf.pem", "-certfile", "inter.pem",
                                 "-certpbe", "PBE-SHA1-RC2-40", "-keypbe", "PBE-SHA1-3DES", "-passout", "pass:rc2",
                                 "-out", "rc2.p12"], in: dir)
        if r.code == 0 {
            let c = try PKCS12.parse(try Data(contentsOf: dir.appendingPathComponent("rc2.p12")), password: "rc2")
            XCTAssertEqual(c.certificates.first, leaf)
            XCTAssertEqual(c.privateKey, key.pkcs1)
        }
        XCTAssertTrue(PKCS12.matches(certificate: leaf, privateKey: key.pkcs1))
        XCTAssertFalse(PKCS12.matches(certificate: ca.intermediateDER, privateKey: key.pkcs1))

        // Paket klasöründe samsung-ca/<ad>.pem ya da düz <ad>.pem; sıra sabit, eksikler atlanır.
        let bundleDir = dir.appendingPathComponent("B.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleDir.appendingPathComponent("samsung-ca"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: ca.dir.appendingPathComponent("inter.pem"),
                                         to: bundleDir.appendingPathComponent("samsung-ca/public2.pem"))
        try FileManager.default.copyItem(at: ca.dir.appendingPathComponent("decoy.pem"),
                                         to: bundleDir.appendingPathComponent("author_ca.pem"))
        let bundle = try XCTUnwrap(Bundle(url: bundleDir))
        XCTAssertEqual(SamsungIntermediates.bundled(in: bundle), [ca.decoyDER, ca.intermediateDER])
    }

    /// OpenSSL 3+ varsayılanı (PBES2: PBKDF2-HMAC-SHA256 + AES-256-CBC, SHA-256 MAC) da okunur.
    func testPKCS12ModernOpenSSLDefaults() throws {
        let brew = "/opt/homebrew/bin/openssl"
        guard FileManager.default.isExecutableFile(atPath: brew) else { throw XCTSkip("OpenSSL 3 yok") }
        func brewRun(_ args: [String]) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: brew)
            p.arguments = args
            p.currentDirectoryURL = dir
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try p.run(); p.waitUntilExit()
            XCTAssertEqual(p.terminationStatus, 0, args.joined(separator: " "))
        }
        try brewRun(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "k.pem", "-out", "c.pem", "-days", "30",
                     "-subj", "/CN=Modern"])
        try brewRun(["pkcs12", "-export", "-inkey", "k.pem", "-in", "c.pem", "-passout", "pass:P4ss", "-out", "m.p12"])
        let c = try PKCS12.parse(try Data(contentsOf: dir.appendingPathComponent("m.p12")), password: "P4ss")
        let key = try ADBKey(fileData: try Data(contentsOf: dir.appendingPathComponent("k.pem")))
        XCTAssertEqual(c.privateKey, key.pkcs1)
        XCTAssertEqual(X509Info(der: c.certificates[0])?.subjectCN, "Modern")
        XCTAssertThrowsError(try PKCS12.parse(try Data(contentsOf: dir.appendingPathComponent("m.p12")), password: "nope"))
    }

    func testIntermediatePickIsFirstMatchingNonSelfIssued() throws {
        let ca = try TestCA(dir: dir.appendingPathComponent("ca"))
        let key = try ADBKey.generate()
        let leaf = X509Info.certificates(fromPEMOrDER: try ca.issue(
            csrPEM: SamsungCSR.pem(try SamsungCSR.author(key: key.privateKey)), name: "leaf"))[0]
        XCTAssertEqual(SamsungIntermediates.pick(for: leaf, from: [ca.rootDER, ca.decoyDER, ca.intermediateDER]),
                       ca.intermediateDER)
        XCTAssertNil(SamsungIntermediates.pick(for: leaf, from: [ca.rootDER, ca.decoyDER]))
        XCTAssertEqual(SamsungIntermediates.fileNames, ["vd_tizen_dev_author_ca", "author_ca", "vd_tizen_dev_public2", "public2"])
        let info = try XCTUnwrap(X509Info(der: leaf))
        XCTAssertEqual(info.issuerCN, "Test Author CA Class")
        XCTAssertTrue(info.notAfter > Date())
    }

    func testCertificateClientRequestsAndErrors() async throws {
        let ca = try TestCA(dir: dir.appendingPathComponent("ca"))
        let transport = FakeCertificateTransport.issuing(ca)
        let lines = LockedBox<[String]>([])
        let client = SamsungCertificateClient(transport: transport, log: { l in lines.mutate { $0.append(l) } })
        let key = try ADBKey.generate()
        let account = SamsungLogin.Account(accessToken: "SECRET-TOKEN", userID: "U1", email: "a@b.c")
        let issued = try await client.request(account: account,
                                              authorCSR: SamsungCSR.pem(try SamsungCSR.author(key: key.privateKey)),
                                              distributorCSR: SamsungCSR.pem(try SamsungCSR.distributor(
                                                key: key.privateKey, email: "a@b.c", duid: "CJCHTFRXVXQDQ")))
        XCTAssertEqual(X509Info(der: issued.author)?.subjectCN, "Nino")
        XCTAssertEqual(X509Info(der: issued.distributor)?.subjectCN, "TizenSDK")
        XCTAssertEqual(String(decoding: issued.deviceProfile, as: UTF8.self), "<profile>device</profile>")
        let calls = transport.calls.value
        XCTAssertEqual(calls.map(\.url.absoluteString), ["https://svdca.samsungqbe.com/apis/v3/authors",
                                                         "https://svdca.samsungqbe.com/apis/v1/distributors",
                                                         "https://svdca.samsungqbe.com/apis/v3/distributors"])
        let distBody = calls[2].body
        let order = ["name=\"access_token\"", "name=\"user_id\"", "name=\"platform\"", "name=\"privilege_level\"",
                     "name=\"developer_type\"", "name=\"csr\"; filename=\"distributor.csr\""]
        let positions = order.map { distBody.range(of: $0)?.lowerBound }
        XCTAssertFalse(positions.contains(nil), distBody)
        XCTAssertEqual(positions.compactMap { $0 }, positions.compactMap { $0 }.sorted())
        XCTAssertTrue(distBody.contains("\r\n\r\nIndividual\r\n"))
        XCTAssertFalse(calls[0].body.contains("privilege_level"))
        XCTAssertTrue(calls[0].body.contains("filename=\"author.csr\""))
        XCTAssertTrue(calls[0].contentType.hasPrefix("multipart/form-data; boundary="))
        XCTAssertFalse(lines.value.joined().contains("SECRET-TOKEN"))
        XCTAssertEqual(lines.value.first?.hasPrefix("Sertifika sunucusu /apis/v3/authors: 200"), true)

        // 2xx dışı: JSON alanları.
        transport.reply = { _, _ in (403, "Forbidden", Data(#"{"code":401,"message":"token expired","x":"y"}"#.utf8)) }
        do { _ = try await client.request(account: account, authorCSR: Data(), distributorCSR: Data()); XCTFail() }
        catch let f as SamsungCertificateClient.Failure {
            XCTAssertEqual(f.message, "Samsung sertifika sunucusu /apis/v3/authors: 403 Forbidden code=401, message=token expired")
        }
        // 2xx ama sertifika yok.
        transport.reply = { _, _ in (200, "OK", Data("maintenance".utf8)) }
        do { _ = try await client.request(account: account, authorCSR: Data(), distributorCSR: Data()); XCTFail() }
        catch let f as SamsungCertificateClient.Failure {
            XCTAssertEqual(f.message, "Samsung yazar sertifikası vermedi: maintenance")
        }
        // Ağ hatası.
        transport.reply = { _, _ in throw URLError(.timedOut) }
        do { _ = try await client.request(account: account, authorCSR: Data(), distributorCSR: Data()); XCTFail() }
        catch let f as SamsungCertificateClient.Failure {
            XCTAssertTrue(f.message.hasPrefix("Samsung'un sertifika sunucusuna (svdca.samsungqbe.com) ulaşılamadı: "))
        }
    }
}

final class SamsungSignerTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nino-signer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testZipRoundTrip() throws {
        let data = SampleWidget.make()
        let zip = try WidgetZip(data: data)
        XCTAssertEqual(zip.entries.map(\.name), ["config.xml", "js/", "js/app.js", "index.html", "author-signature.xml"])
        XCTAssertEqual(zip.entries[2].method, 8)
        XCTAssertEqual(String(decoding: try WidgetZip.contents(zip.entries[3]), as: UTF8.self),
                       "<html><body>Nino & TV</body></html>")
        XCTAssertEqual(WidgetZip.crc32(Data("123456789".utf8)), 0xcbf4_3926)
    }

    func testSignedWidgetStructureCanonicalFormAndSignatures() throws {
        let ca = try TestCA(dir: dir.appendingPathComponent("ca"))
        let key = try ADBKey.generate()
        let leaf = X509Info.certificates(fromPEMOrDER: try ca.issue(
            csrPEM: SamsungCSR.pem(try SamsungCSR.author(key: key.privateKey)), name: "leaf"))[0]
        let id = WidgetSigner.Identity(key: key.privateKey, certificates: [leaf, ca.intermediateDER])
        let signed = try WidgetSigner.sign(package: SampleWidget.make(), author: id, distributor: id)
        let zip = try WidgetZip(data: signed)
        XCTAssertEqual(zip.entries.map(\.name), ["author-signature.xml", "signature1.xml", "config.xml", "js/", "js/app.js",
                                                 "index.html"])
        let file = dir.appendingPathComponent("signed.wgt")
        try signed.write(to: file)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-tq", file.path]
        unzip.standardOutput = Pipe()
        try unzip.run(); unzip.waitUntilExit()
        XCTAssertEqual(unzip.terminationStatus, 0)

        let files = try zip.entries.filter { WidgetSigner.isSigned($0.name) }.map { ($0.name, try WidgetZip.contents($0)) }
        let authorXML = try WidgetZip.contents(zip.entries[0])
        let distXML = try WidgetZip.contents(zip.entries[1])
        try verify(authorXML, role: .author, references: files.map(\.0), contents: Dictionary(uniqueKeysWithValues: files),
                   key: key.privateKey)
        var all = Dictionary(uniqueKeysWithValues: files)
        all["author-signature.xml"] = authorXML
        try verify(distXML, role: .distributor, references: ["author-signature.xml"] + files.map(\.0), contents: all,
                   key: key.privateKey)
        let text = String(decoding: authorXML, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("<Signature xmlns=\"http://www.w3.org/2000/09/xmldsig#\" Id=\"AuthorSignature\"><SignedInfo>"))
        XCTAssertFalse(text.contains("<?xml"))
        XCTAssertTrue(text.contains("<X509Certificate>\n"))
        XCTAssertEqual(text.components(separatedBy: "<X509Certificate>").count - 1, 2)
        let dist = String(decoding: distXML, as: UTF8.self)
        XCTAssertTrue(dist.contains("Target=\"#DistributorSignature\""))
        XCTAssertTrue(dist.contains("#role-distributor"))
    }

    /// Bağımsız denetim: XMLDocument'in kanonik biçimi bizim imzaladığımızla aynı; özetler ve RSA-SHA512 tutuyor.
    func verify(_ xml: Data, role: WidgetSigner.Role, references: [String], contents: [String: Data], key: SecKey) throws {
        let doc = try XMLDocument(data: xml)
        let root = try XCTUnwrap(doc.rootElement())
        let signedInfo = try XCTUnwrap(root.elements(forName: "SignedInfo").first)
        let object = try XCTUnwrap(root.elements(forName: "Object").first)
        let canonicalSI = signedInfo.canonicalXMLStringPreservingComments(false)
        let canonicalObject = object.canonicalXMLStringPreservingComments(false)
        let ours = WidgetSigner.signedInfo(role: role, files: references.map { ($0, contents[$0]!) })
        XCTAssertEqual(canonicalSI, ours.canonicalSignedInfo)
        XCTAssertTrue(canonicalObject.hasPrefix("<Object xmlns=\"http://www.w3.org/2000/09/xmldsig#\" Id=\"prop\">"),
                      canonicalObject)

        let refs = signedInfo.elements(forName: "Reference")
        XCTAssertEqual(refs.compactMap { $0.attribute(forName: "URI")?.stringValue }, references + ["#prop"])
        for r in refs {
            let uri = r.attribute(forName: "URI")!.stringValue!
            let value = r.elements(forName: "DigestValue").first!.stringValue!
            let bytes = uri == "#prop" ? Data(canonicalObject.utf8) : contents[uri]!
            XCTAssertEqual(value, WidgetSigner.digest(bytes), uri)
        }
        let sig = Data(base64Encoded: root.elements(forName: "SignatureValue").first!.stringValue!)!
        let pub = SecKeyCopyPublicKey(key)!
        XCTAssertTrue(SecKeyVerifySignature(pub, .rsaSignatureMessagePKCS1v15SHA512, Data(canonicalSI.utf8) as CFData,
                                            sig as CFData, nil))
    }

    /// Başka araçların yazdığı zip'ler (gerçek .wgt başka bir araçtan gelir) okunur ve imzalanır.
    func testSignsZipsFromOtherTools() throws {
        let key = try ADBKey.generate()
        _ = try OpenSSL.ok(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "k.pem", "-out", "c.pem",
                            "-days", "30", "-subj", "/CN=T"], in: dir)
        let id = WidgetSigner.Identity(key: key.privateKey, certificates: [try OpenSSL.der(fromPEMFile: dir.appendingPathComponent("c.pem"))])
        for tool in ["zip", "ditto"] {
            let source = try SampleWidget.makeWithTool(tool, in: dir)
            let signed = try WidgetSigner.sign(package: source, author: id, distributor: id)
            let zip = try WidgetZip(data: signed)
            XCTAssertEqual(Array(zip.entries.prefix(2).map(\.name)), ["author-signature.xml", "signature1.xml"], tool)
            let names = Set(zip.entries.map(\.name))
            XCTAssertTrue(names.isSuperset(of: ["config.xml", "js/app.js", "index.html"]), "\(tool): \(names)")
            XCTAssertEqual(zip.entries.filter { $0.name == "author-signature.xml" }.count, 1, tool)
            let app = try XCTUnwrap(zip.entries.first { $0.name == "js/app.js" })
            XCTAssertEqual(try WidgetZip.contents(app).count, 200 * 21, tool)
            let file = dir.appendingPathComponent("signed-\(tool).wgt")
            try signed.write(to: file)
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-tq", file.path]
            unzip.standardOutput = Pipe()
            try unzip.run(); unzip.waitUntilExit()
            XCTAssertEqual(unzip.terminationStatus, 0, tool)
        }
    }

    func testAttributeEscaping() {
        XCTAssertEqual(WidgetSigner.escapeAttribute("a&b<c\"d\te\nf\rg h"), "a&amp;b&lt;c&quot;d&#x9;e&#xA;f&#xD;g h")
    }
}

final class SamsungInstallerFlowTests: XCTestCase {
    var dir: URL!
    var ca: TestCA!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nino-sinstall-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        ca = try TestCA(dir: dir.appendingPathComponent("ca"))
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    var profiles: URL { dir.appendingPathComponent("support/samsung", isDirectory: true) }

    func fastTiming() -> SamsungTVInstaller.Timing {
        var t = SamsungTVInstaller.Timing()
        t.connectWaits = [0, 0.05, 0.05]
        t.duidWait = 0.01
        t.connect = 3
        t.sdb.read = 10
        return t
    }

    func writePackage() throws -> URL {
        let url = dir.appendingPathComponent("nino-tizen_0.9.8.wgt")
        try SampleWidget.make().write(to: url)
        return url
    }

    struct Run {
        var events: [String]
        var exit: Int32
        var log: String
    }

    func run(_ server: FakeSDBServer, login: SamsungLoginListening = FakeLogin(
        account: SamsungLogin.Account(accessToken: "SECRET-TOKEN", userID: "U1", email: "a@b.c")),
             transport: FakeCertificateTransport? = nil, intermediates: [Data]? = nil,
             host: String = "127.0.0.1", extra: [String] = []) async throws -> Run {
        let http = FakeHTTP()
        http.set("http://\(host):8001/api/v2/", 200, #"{"device":{"developerMode":"1","developerIP":"127.0.0.1"}}"#)
        let cas = intermediates ?? [ca.rootDER, ca.decoyDER, ca.intermediateDER]
        let ports = SamsungTVInstaller.Ports(connector: RedirectConnector(port: server.port), http: http,
                                             network: FakeNetwork(source: "127.0.0.1"), login: login,
                                             certificates: transport ?? FakeCertificateTransport.issuing(ca),
                                             intermediates: { cas }, tempFolder: dir)
        let helper = InProcessTVHelper(connector: RedirectConnector(port: server.port), ports: FakePorts(),
                                       network: FakeNetwork(), samsungPorts: ports, samsungTiming: fastTiming())
        let logFile = dir.appendingPathComponent("tvinstall.log")
        let events = LockedBox<[String]>([])
        let code = await helper.run(["samsung-install", "--host", host, "--package", try writePackage().path,
                                     "--version", "0.9.8", "--profiles", profiles.path, "--log", logFile.path]
                                    + extra + ["--exit-with-input"],
                                    emit: { e in events.mutate { $0.append(e) } }, log: { _ in })
        try? await Task.sleep(nanoseconds: 150_000_000) // günlük kuyruğu (iptalde de beklenir)
        if Task.isCancelled { Thread.sleep(forTimeInterval: 0.15) }
        let log = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
        return Run(events: events.value, exit: code, log: log)
    }

    func steps(_ r: Run) -> [String] {
        r.events.compactMap { TVHelperEvent.parse($0) }.map { e -> String in
            switch e {
            case let .progress(s): return s
            case .login: return "login"
            case let .done(v, i): return "done \(v) \(i)"
            case let .legacy(v): return "legacy \(v)"
            case let .error(c, _): return "error \(c)"
            default: return "?"
            }
        }
    }

    func testFreshInstallSignsInGetsCertificatesAndInstalls() async throws {
        let server = try FakeSDBServer()
        defer { server.stop() }
        server.installedVersion = "0.9.8"
        server.dropConnections = 1 // ilk deneme el sıkışmada kesilir
        let r = try await run(server)
        XCTAssertEqual(steps(r), ["reading", "signin", "login", "certificate", "signing", "installing", "done 0.9.8 true"])
        XCTAssertEqual(r.exit, 0)
        XCTAssertTrue(r.events.contains { $0.contains("signInGate") })

        let folder = profiles.appendingPathComponent("CJCHTFRXVXQDQ")
        for f in ["author.p12", "distributor.p12", "password.txt", "duid.txt", "device-profile.xml"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(f).path), f)
        }
        let password = try String(contentsOf: folder.appendingPathComponent("password.txt"), encoding: .utf8)
        XCTAssertEqual(password.count, 32)
        XCTAssertTrue(password.allSatisfy { "0123456789ABCDEF".contains($0) })
        let dist = try PKCS12.parse(try Data(contentsOf: folder.appendingPathComponent("distributor.p12")), password: password)
        XCTAssertEqual(dist.certificates.count, 2)
        XCTAssertEqual(dist.certificates[1], ca.intermediateDER)

        let pushed = server.with { $0.pushed }
        let wgtPath = try XCTUnwrap(pushed.keys.first { $0.hasSuffix(".wgt") })
        XCTAssertTrue(wgtPath.hasPrefix("/home/owner/share/tmp/sdk_tools/nino-"))
        let names = try WidgetZip(data: pushed[wgtPath]!).entries.map(\.name)
        XCTAssertEqual(names.prefix(2), ["author-signature.xml", "signature1.xml"])
        let services = server.with { $0.services }
        XCTAssertTrue(services.contains("shell:0 vd_appinstall NinoTVApps.Nino \(wgtPath)"))
        XCTAssertEqual(services.last, "shell:0 was_execute NinoTVApps.Nino")
        XCTAssertFalse(services.contains("shell:0 vd_appuninstall NinoTVApps"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(wgtPath.split(separator: "/").last.map(String.init)!).path))

        XCTAssertTrue(r.log.contains("--- Samsung TV'ye kurulum başladı (127.0.0.1); paket: nino-tizen_0.9.8.wgt"), r.log)
        XCTAssertTrue(r.log.contains("sdb bağlantısı kurulamadı (1/3)"), r.log)
        XCTAssertTrue(r.log.contains("TV: Tizen 6.5, sdk_toolpath /home/owner/share/tmp/sdk_tools"), r.log)
        XCTAssertTrue(r.log.contains("Kayıtlı sertifika: yok"), r.log)
        XCTAssertTrue(r.log.contains("Yeni sertifika:"), r.log)
        XCTAssertTrue(r.log.contains("Kurulum tamam."), r.log)
        XCTAssertFalse(r.log.contains("SECRET-TOKEN"))
        XCTAssertFalse(r.log.contains(password))
        XCTAssertFalse(r.events.joined().contains(password))

        // İkinci kurulum: kayıtlı profil geçerli, giriş yok.
        server.with { $0.applist = [FakeSDBServer.applist(version: "0.9.7")] }
        let again = try await run(server, login: FakeLogin(failure: .portUnavailable("should not be called")))
        XCTAssertEqual(steps(again), ["reading", "signing", "installing", "done 0.9.8 true"])
        XCTAssertTrue(again.log.contains("Kayıtlı sertifika: geçerli"), again.log)
    }

    // MARK: Sahadaki eski TV uygulaması

    static func legacyApplist(version: String) -> String {
        "\t-------------app_title  =  Nino----------------------------\n"
            + "\t-------------app_tizen_id  =  \(TVApp.legacySamsungID)----------------\n"
            + "\t-------------app_version  =  \(version)-----------------------------\n"
            + "\t------------------------------------------------------------------------\n"
    }

    func testLegacyApplistParsing() {
        let legacy = Self.legacyApplist(version: "0.4.2")
        XCTAssertNil(SamsungOutputs.installedVersion(applist: legacy))
        XCTAssertEqual(SamsungOutputs.legacyVersion(applist: legacy), "0.4.2")
        XCTAssertEqual(SamsungOutputs.legacyVersion(applist: legacy.replacingOccurrences(of: "0.4.2", with: "")), "")
        let both = FakeSDBServer.applist(version: "0.9.8") + legacy
        XCTAssertEqual(SamsungOutputs.installedVersion(applist: both), "0.9.8")
        XCTAssertEqual(SamsungOutputs.legacyVersion(applist: both), "0.4.2")
        XCTAssertNil(SamsungOutputs.legacyVersion(applist: FakeSDBServer.applist(version: "0.9.8")))
        XCTAssertEqual(LegacyNames.samsungTVPackageID + "." + TVApp.legacySamsungID.split(separator: ".").last!,
                       TVApp.legacySamsungID)
    }

    func testOnlyLegacyIsKeptWithoutInstalling() async throws {
        let server = try FakeSDBServer()
        defer { server.stop() }
        server.applist = [Self.legacyApplist(version: "0.4.2")]
        let r = try await run(server, login: FakeLogin(failure: .portUnavailable("should not be called")),
                              extra: ["--keep-legacy", "1"])
        XCTAssertEqual(steps(r), ["reading", "legacy 0.4.2"])
        let services = server.with { $0.services }
        XCTAssertFalse(services.contains { $0.contains("vd_appinstall") || $0.contains("vd_appuninstall") })
    }

    func testUpgradeInstallsNextToLegacyAndKeepsIt() async throws {
        let server = try FakeSDBServer()
        defer { server.stop() }
        server.installedVersion = "0.9.8"
        server.applist = [Self.legacyApplist(version: "0.4.2")]
        let r = try await run(server)
        XCTAssertEqual(steps(r).last, "done 0.9.8 true")
        let services = server.with { $0.services }
        XCTAssertFalse(services.contains { $0.contains("vd_appuninstall") && $0.contains(LegacyNames.samsungTVPackageID) })
        XCTAssertEqual(services.last, "shell:0 was_execute NinoTVApps.Nino")
        XCTAssertTrue(r.log.contains("yerinde kalır"), r.log)
    }

    func testCurrentVersionSkipsInstall() async throws {
        let server = try FakeSDBServer()
        defer { server.stop() }
        server.applist = [FakeSDBServer.applist(version: "0.10.0")]
        let r = try await run(server)
        XCTAssertEqual(steps(r), ["reading", "done 0.10.0 false"])
        XCTAssertTrue(r.log.contains("TV'de 0.10.0 sürümü var; kurulum gerekmedi."))
        XCTAssertFalse(server.with { $0.services }.contains { $0.contains("was_execute") })
    }

    func testMismatchUninstallsAndRetriesOnce() async throws {
        let server = try FakeSDBServer()
        defer { server.stop() }
        server.installedVersion = "0.9.8"
        server.installOutputs = [
            "app_id[NinoTVApps.Nino] install failed[118, -12]\nreason: Check certificate error : :Package with the same id and different certificate has been already installed.:<-12>",
            "app_id[NinoTVApps.Nino] installing[100]\ncmd_ret:0",
        ]
        let r = try await run(server)
        XCTAssertEqual(steps(r).suffix(4), ["installing", "uninstalling", "installing", "done 0.9.8 true"])
        let s = server.with { $0.services }
        XCTAssertTrue(s.contains("shell:0 vd_appuninstall NinoTVApps"))
        XCTAssertTrue(s.contains("shell:0 vd_appuninstall NinoTVApps.Nino"))

        server.with { $0.applist = [""]; $0.installOutputs = ["app_id[NinoTVApps.Nino] install failed[118, -22]\nreason: Security error : :Invalid function parameter was given:<2>"] }
        let blocked = try await run(server)
        XCTAssertEqual(steps(blocked).suffix(3), ["uninstalling", "installing", "error PackageBlocked"])
        XCTAssertEqual(blocked.exit, 1)
    }

    func testRejectedCertificateSetsProfileAside() async throws {
        let server = try FakeSDBServer()
        defer { server.stop() }
        server.installOutputs = ["install failed[118, -12]\nreason: Check certificate error : :Certificate in signature is expired.:<-6>"]
        let r = try await run(server)
        XCTAssertEqual(steps(r).last, "error CertificateRejected")
        XCTAssertFalse(steps(r).contains("uninstalling"))
        let items = try FileManager.default.contentsOfDirectory(atPath: profiles.path)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].hasPrefix("CJCHTFRXVXQDQ.rejected-"), "\(items)")
        let msg = TVHelperEvent.parse(r.events.last!)
        XCTAssertEqual(msg, .error(code: "CertificateRejected",
                                   message: "install failed[118, -12] | reason: Check certificate error : :Certificate in signature is expired.:<-6>"))
    }

    func testErrorsMapToHelperCodes() async throws {
        let server = try FakeSDBServer()
        defer { server.stop() }

        let badHost = try await run(server, host: "tv.local")
        XCTAssertEqual(TVHelperEvent.parse(badHost.events.last!), .error(code: "Unreachable", message: "geçersiz TV adresi: tv.local"))

        server.with { $0.dropConnections = 3 }
        let down = try await run(server)
        guard case let .error(code, message)? = TVHelperEvent.parse(down.events.last!) else { return XCTFail() }
        XCTAssertEqual(code, "Unreachable")
        XCTAssertTrue(message.hasPrefix("sdb 127.0.0.1:26101: "), message)
        XCTAssertTrue(message.hasSuffix("(bu bilgisayar 127.0.0.1, Host PC IP (TV ayarı) 127.0.0.1)"), message)

        server.with { $0.capability = "platform_version:2.4\n" }
        let old = try await run(server)
        XCTAssertEqual(TVHelperEvent.parse(old.events.last!), .error(code: "TooOld", message: "Tizen 2.4"))

        server.with { $0.capability = "platform_version:6.0\n"; $0.duid = "error: closed" }
        let noDUID = try await run(server)
        XCTAssertEqual(TVHelperEvent.parse(noDUID.events.last!),
                       .error(code: "Unreachable", message: "TV kimliği (DUID) alınamadı; son yanıt: error: closed"))

        server.with { $0.duid = "CJCHTFRXVXQDQ" }
        let busy = try await run(server, login: FakeLogin(failure: .portUnavailable("Address already in use")))
        XCTAssertEqual(TVHelperEvent.parse(busy.events.last!),
                       .error(code: "LoginFailed", message: "localhost:4794 giriş dönüşü için dinlenemedi (port başka bir Nino tarafından kullanılıyor olabilir): Address already in use"))
        let late = try await run(server, login: FakeLogin(failure: .timedOut(summary: "error=x, state")))
        XCTAssertEqual(TVHelperEvent.parse(late.events.last!),
                       .error(code: "LoginFailed", message: "Samsung girişi 10 dakikada bitmedi; dönüşte hesap yoktu (error=x, state)"))

        let noCA = try await run(server, intermediates: [ca.rootDER])
        guard case let .error(c2, m2)? = TVHelperEvent.parse(noCA.events.last!) else { return XCTFail() }
        XCTAssertEqual(c2, "CertificateFailed")
        XCTAssertTrue(m2.contains("Test Author CA Class"), m2)

        server.with { $0.dropOnInstall = true }
        let lost = try await run(server)
        XCTAssertEqual(steps(lost).suffix(2), ["installing", "error ConnectionLost"])
        XCTAssertFalse(steps(lost).contains("uninstalling"))
    }

    func testInstalledButVersionStillOld() async throws {
        let server = try FakeSDBServer()
        defer { server.stop() }
        server.applist = [FakeSDBServer.applist(version: "0.9.1")]
        let r = try await run(server)
        XCTAssertEqual(TVHelperEvent.parse(r.events.last!),
                       .error(code: "InstallFailed", message: "Kurulum bitti görünüyor ama TV hâlâ 0.9.1 sürümünü gösteriyor; beklenen 0.9.8"))
    }

    func testCancelDuringInstallEmitsNoError() async throws {
        let server = try FakeSDBServer()
        defer { server.stop() }
        server.stallOnInstall = true
        let task = Task { try await run(server) }
        try await samsungWait(15) { server.with { $0.services.contains { $0.hasPrefix("shell:0 vd_appinstall") } } }
        task.cancel()
        let r = try await task.value
        XCTAssertFalse(steps(r).contains { $0.hasPrefix("error") }, "\(steps(r))")
        XCTAssertTrue(r.log.contains("Kurulum iptal edildi."), r.log)
        XCTAssertFalse(r.log.contains("HATA"), r.log)
    }

    func testCancelDuringSignInEmitsNoError() async throws {
        let server = try FakeSDBServer()
        defer { server.stop() }
        let started = Date()
        let task = Task { try await run(server, login: FakeLogin(account: nil)) }
        try await Task.sleep(nanoseconds: 1_500_000_000)
        task.cancel()
        let r = try await task.value
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        XCTAssertFalse(steps(r).contains { $0.hasPrefix("error") }, "\(steps(r))")
        XCTAssertTrue(steps(r).contains("login"))
        XCTAssertTrue(r.log.contains("Kurulum iptal edildi."), r.log)
    }
}
