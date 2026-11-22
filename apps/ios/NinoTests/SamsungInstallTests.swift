// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CryptoKit
import XCTest
@testable import Nino

/// Samsung kurulumu: sdb çerçeveleri (toplamlı), imza, CSR, giriş dinleyicisi, yanıt okuma; sahte sdbd ile kurulum.
final class SamsungInstallTests: XCTestCase {
    func testCSRSignatureVerifiesAndCarriesDUID() throws {
        let key = try RSAPrivateKey.generate()
        let der = ASN1.unwrapPEM(try SamsungCSR.distributor(key, duid: "ABCD1234EFGH", email: "a@b.c"))
        let parts = try XCTUnwrap(try ASN1.parse(der).first).items
        XCTAssertEqual(parts.count, 3)
        let info = ASN1.node(0x30, parts[0].body)
        let signature = Array(parts[2].body.dropFirst())
        let pub = try XCTUnwrap(RSAVerify.publicKey(pkcs1: key.publicPKCS1))
        XCTAssertTrue(RSAVerify.check(pub, .rsaSignatureMessagePKCS1v15SHA256, message: info, signature: signature))
        XCTAssertNotNil(String(decoding: der, as: UTF8.self).range(of: "URN:tizen:deviceid=ABCD1234EFGH"))
    }

    func testWidgetSignatureIsVerifiable() throws {
        let key = try RSAPrivateKey.generate()
        let cert = try TVCertificate(try TVCertificate.selfSigned(key))
        let signer = WidgetSigner.Signer(key: key, chain: [cert])
        let signed = try WidgetSigner.sign(TestPack.wgt(version: "4.0.3"), author: signer, distributor: signer)
        let zip = try ZipArchive(signed)
        XCTAssertEqual(zip.entries.map(\.name), ["author-signature.xml", "signature1.xml", "config.xml", "index.html"])
        for name in ["author-signature.xml", "signature1.xml"] {
            let xml = String(decoding: try XCTUnwrap(zip.data(named: name)), as: UTF8.self)
            let info = try XCTUnwrap(firstCapture("(<SignedInfo>.*</SignedInfo>)", xml))
            let canonical = "<SignedInfo xmlns=\"\(WidgetSigner.dsig)\">" + info.dropFirst("<SignedInfo>".count)
            let value = try XCTUnwrap(firstCapture("<SignatureValue>([^<]+)</SignatureValue>", xml))
            let pub = try XCTUnwrap(RSAVerify.publicKey(pkcs1: key.publicPKCS1))
            XCTAssertTrue(RSAVerify.check(pub, .rsaSignatureMessagePKCS1v15SHA512, message: Bytes(canonical.utf8),
                                          signature: Bytes(Data(base64Encoded: value)!)), name)
            XCTAssertTrue(xml.contains(WidgetSigner.digest(Bytes("<html></html>".utf8))))
        }
        // Dağıtıcı imzası yazar imzasını da kapsar.
        let distributor = String(decoding: zip.data(named: "signature1.xml")!, as: UTF8.self)
        XCTAssertTrue(distributor.contains("URI=\"author-signature.xml\""))
        XCTAssertTrue(distributor.contains("role-distributor"))
    }

    func testRepliesAndListing() {
        XCTAssertEqual(SamsungReplies.outcome("spend time for wascmd is [1200]ms\ninstall completed"), .ok)
        XCTAssertEqual(SamsungReplies.outcome("install failed[118, -12], Check certificate error : not valid yet"), .notYetValid)
        XCTAssertEqual(SamsungReplies.outcome("install failed[118, -11] Author certificate not match"), .mismatch)
        XCTAssertEqual(SamsungReplies.outcome("install failed[118, -22]"), .blocked)
        XCTAssertEqual(SamsungReplies.outcome("download failed[116]"), .notEnoughSpace)
        let listing = """
        ------------------------------------
        --- app_tizen_id   = other.App ---
        --- app_version    = 1.0.0 ---
        ------------------------------------
        --- app_tizen_id   = NinoTVApps.Nino ---
        --- app_version    = 4.0.2 ---
        ------------------------------------
        """
        XCTAssertEqual(SamsungReplies.installedVersion(listing), "4.0.2")
        XCTAssertNil(SamsungReplies.installedVersion("---- app_tizen_id = x.y ----"))
        XCTAssertEqual(SdbClient.parseCapabilities(Bytes("00platform_version:6.5\nsdk_toolpath:/tmp\n".utf8))["platform_version"], "6.5")
        XCTAssertTrue(SamsungInstaller.isTooOld("2.3"))
        XCTAssertTrue(SamsungInstaller.needsDeviceProfile("3.0"))
        XCTAssertFalse(SamsungInstaller.needsDeviceProfile("6.0"))
        let info = SamsungTVInfo.parse(Data(#"{"device":{"name":"Salon","modelName":"QE55","developerMode":"1","developerIP":"192.168.1.9"}}"#.utf8))
        XCTAssertEqual(info, SamsungTVInfo(name: "Salon", model: "QE55", developerMode: true, developerIP: "192.168.1.9"))
    }

    func testSignInListenerReceivesAccount() throws {
        let listener = try SamsungSignIn.Listener(port: 0)
        let result = LockedValue<SamsungAccount?>(nil)
        let done = expectation(description: "account")
        Thread.detachNewThread {
            result.set(try? listener.wait(timeout: 20))
            done.fulfill()
        }
        let json = #"{"access_token":"tok+en","userId":"u1","inputEmailID":"me@example.com"}"#
        let body = "code=" + json.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! + "&state=" + SamsungSignIn.state
        var r = URLRequest(url: URL(string: "http://127.0.0.1:\(listener.port)/signin/callback")!)
        r.httpMethod = "POST"
        r.httpBody = Data(body.utf8)
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        _ = try? BlockingHTTP.send(r)
        wait(for: [done], timeout: 25)
        XCTAssertEqual(result.get(), SamsungAccount(accessToken: "tok+en", userID: "u1", email: "me@example.com"))
        XCTAssertNil(SamsungSignIn.account(fromForm: "code=%7B%7D&state=wrong"))
    }

    /// Sahte sdbd: kimlik doğrulama, capability, applist, getduid, sync ile gönderim, vd_appinstall, was_execute.
    func testInstallOverSdbWithSavedProfile() throws {
        let dir = TVTestFiles.scratch()
        let files = TVInstallFiles(root: dir)
        let identity = try AdbIdentity.stored(in: files.sdb)
        let installed = LockedValue<String?>("4.0.1")
        let device = FakeWireDevice(verifySum: true, banner: "device::")
        device.requireAuth = true
        device.signature = .rsaSignatureMessagePKCS1v15SHA1
        device.trustedKey.set(identity.key.publicRef)
        device.services = [
            .init(prefix: "capability:") { _, _ in "00platform_version:6.0\nsdk_toolpath:/home/owner/share/tmp/sdk_tools\n" },
            .init(prefix: "shell:0 vd_applist") { _, _ in
                installed.get().map { "------\n--- app_tizen_id = NinoTVApps.Nino ---\n--- app_version = \($0) ---\n------\n" } ?? "------\n"
            },
            .init(prefix: "shell:0 getduid") { _, _ in "DUID0123456789\n" },
            .init(prefix: "sync:") { _, _ in "OKAY\u{0}\u{0}\u{0}\u{0}" },
            .init(prefix: "shell:0 vd_appinstall") { _, _ in installed.set("4.0.3"); return "install completed\n" },
            .init(prefix: "shell:0 was_execute") { _, _ in "" },
        ]
        let server = try LoopbackServer { device.serve($0) }
        defer { server.stop() }

        var installer = SamsungInstaller(host: "127.0.0.1", files: files, log: TVInstallLog(file: files.logFile),
                                         signIn: { XCTFail("kayıtlı profil varken giriş istenmemeli"); throw SamsungFailure(problem: .loginFailed) })
        installer.sdbPort = server.port
        let key = try RSAPrivateKey.generate()
        let cert = try TVCertificate.selfSigned(key)
        try installer.profile(for: "DUID0123456789").save(key: key, author: cert, distributor: cert, deviceProfile: [], duid: "DUID0123456789")

        let outcome = try installer.install(wgt: { TVPackage(bytes: TestPack.wgt(version: "4.0.3"), version: "4.0.3", origin: "test") })
        XCTAssertEqual(outcome, TVInstallOutcome(version: "4.0.3", installed: true))
        let pushed = try XCTUnwrap(device.received.get().first { $0.key.hasSuffix(".wgt") })
        XCTAssertTrue(pushed.key.hasPrefix("/home/owner/share/tmp/sdk_tools/nino-"))
        XCTAssertNotNil(try ZipArchive(pushed.value).data(named: "signature1.xml"))
        XCTAssertTrue(device.seenServices.get().contains("shell:0 was_execute NinoTVApps.Nino"))

        // Güncel TV: yalnız açılır.
        let again = try installer.install(wgt: { TVPackage(bytes: TestPack.wgt(version: "4.0.3"), version: "4.0.3", origin: "test") })
        XCTAssertEqual(again, TVInstallOutcome(version: "4.0.3", installed: false))
    }

    func testProfileWithoutCertificateNeedsSignIn() throws {
        let dir = TVTestFiles.scratch()
        let files = TVInstallFiles(root: dir)
        let identity = try AdbIdentity.stored(in: files.sdb)
        let device = FakeWireDevice(verifySum: true, banner: "device::")
        device.requireAuth = true
        device.signature = .rsaSignatureMessagePKCS1v15SHA1
        device.trustedKey.set(identity.key.publicRef)
        device.services = [
            .init(prefix: "capability:") { _, _ in "00platform_version:6.0\n" },
            .init(prefix: "shell:0 vd_applist") { _, _ in "------\n" },
            .init(prefix: "shell:0 getduid") { _, _ in "DUID0123456789\n" },
        ]
        let server = try LoopbackServer { device.serve($0) }
        defer { server.stop() }
        var installer = SamsungInstaller(host: "127.0.0.1", files: files, log: TVInstallLog(file: files.logFile),
                                         signIn: { throw SamsungFailure(problem: .loginFailed, detail: "cancelled") })
        installer.sdbPort = server.port
        XCTAssertThrowsError(try installer.install(wgt: { TVPackage(bytes: TestPack.wgt(version: "4.0.3"), version: "4.0.3", origin: "t") })) {
            XCTAssertEqual(($0 as? SamsungFailure)?.problem, .loginFailed)
        }
    }
}
