// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CRemotePlay
import Foundation
import NinoCore
import XCTest
@testable import NinoRemotePlay

private func dummyConsole() -> RegisteredConsole {
    RegisteredConsole(hostID: "AABBCCDDEEFF", nickname: "PS5", isPS5: true, target: 1_000_100,
                      registKey: Array("0123abcd".utf8) + Array(repeating: 0, count: 8),
                      rpKey: Array(repeating: 7, count: 16), serverMAC: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
}

private func quitEvent() -> ChiakiEvent {
    var e = ChiakiEvent()
    e.type = CHIAKI_EVENT_QUIT
    e.quit.reason = CHIAKI_QUIT_REASON_STOPPED
    return e
}

final class SessionShutdownTests: XCTestCase {
    /// PS5 oturumu kendisi kapatınca kare akışı bitirilir; akışın bitiş işleyicisi
    /// stop() çağırır. Eskiden bu, kilit tutulurken olduğundan kilitlenirdi.
    func testQuitEventWithFrameStreamDoesNotDeadlock() {
        let session = RemotePlaySession(address: "127.0.0.1", console: dummyConsole())
        let frames = session.attachFrameStreamForTesting()
        let events = session.events()
        let handled = expectation(description: "QUIT işlendi")
        Thread.detachNewThread {
            CallbackThread.run { session.handle(quitEvent()) }
            handled.fulfill()
        }
        wait(for: [handled], timeout: 3)

        let ended = expectation(description: "akışlar bitti")
        Task {
            for await _ in frames {}
            var got: [RemotePlaySession.Event] = []
            for await e in events { got.append(e) }
            XCTAssertEqual(got, [.quit(reason: String(cString: chiaki_quit_reason_string(CHIAKI_QUIT_REASON_STOPPED)))])
            ended.fulfill()
        }
        wait(for: [ended], timeout: 3)
        session.stop() // ikinci kez: sorun çıkmamalı
    }

    /// Gerçek kütüphane iş parçacığıyla: 127.0.0.1'de PS5 yok, bağlantı reddedilir,
    /// kütüphane QUIT gönderir ve oturum kendi iş parçacığından kapanır. PS5'e bağlanmaz.
    func testLibraryQuitOnLocalhostShutsDownCleanly() {
        let session = RemotePlaySession(address: "127.0.0.1", console: dummyConsole())
        let events = session.events()
        let frames = session.frames()
        let ended = expectation(description: "oturum kapandı")
        Task {
            var sawQuit = false
            for await e in events { if case .quit = e { sawQuit = true } }
            for await _ in frames {}
            XCTAssertTrue(sawQuit)
            ended.fulfill()
        }
        wait(for: [ended], timeout: 20)
        // Kapanış arka kuyrukta biter; dışarıdan stop() da güvenli olmalı.
        session.stop()
    }

    /// Tüketen görev iptal edilince (iPhone'da görülen kilitlenme) kapanış takılmadan biter.
    func testCancellingFrameConsumerShutsDownCleanly() async {
        for _ in 0..<5 {
            let session = RemotePlaySession(address: "127.0.0.1", console: dummyConsole())
            let events = session.events()
            let frames = session.frames()
            let consumer = Task { for await _ in frames {} }
            consumer.cancel()
            await consumer.value
            // Olay akışı QUIT ile ya da kapanışla biter; ikisi de takılmamalı.
            let done = Task { for await _ in events {} }
            let finished = await withTaskGroup(of: Bool.self) { g in
                g.addTask { await done.value; return true }
                g.addTask { try? await Task.sleep(for: .seconds(10)); return false }
                let r = await g.next() ?? false
                g.cancelAll()
                return r
            }
            XCTAssertTrue(finished, "olay akışı bitmedi")
            session.stop()
        }
    }

    /// QUIT olayı ile akış iptali aynı anda: ikisi de bitmeli.
    func testQuitRacingWithCancellation() async {
        for _ in 0..<20 {
            let session = RemotePlaySession(address: "127.0.0.1", console: dummyConsole())
            let frames = session.attachFrameStreamForTesting()
            let consumer = Task { for await _ in frames {} }
            let quit = Task.detached { CallbackThread.run { session.handle(quitEvent()) } }
            consumer.cancel()
            await quit.value
            await consumer.value
            session.stop()
        }
    }

    func testStopFromConsumerWhileIdle() {
        let session = RemotePlaySession(address: "127.0.0.1", console: dummyConsole())
        session.stop()
        session.stop()
    }
}

final class LoginPINTests: XCTestCase {
    func testPINRequestBecomesEvent() async {
        let session = RemotePlaySession(address: "127.0.0.1", console: dummyConsole())
        let events = session.events()
        var e = ChiakiEvent()
        e.type = CHIAKI_EVENT_LOGIN_PIN_REQUEST
        e.login_pin_request.pin_incorrect = true
        CallbackThread.run { session.handle(e) }
        var first: RemotePlaySession.Event?
        for await ev in events { first = ev; break }
        XCTAssertEqual(first, .loginPINRequested(incorrect: true))
    }

    func testSendLoginPINValidation() {
        let session = RemotePlaySession(address: "127.0.0.1", console: dummyConsole())
        XCTAssertThrowsError(try session.sendLoginPIN("12")) {
            guard case RemotePlayError.badInput = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try session.sendLoginPIN("12a4"))
        XCTAssertThrowsError(try session.sendLoginPIN("1234")) {
            XCTAssertEqual($0 as? RemotePlayError, .notConnected)
        }
    }
}

final class FramePickerTests: XCTestCase {
    private func count(fps: Double, seconds: Double, options: RemotePlaySession.Options, jitter: Double = 0) -> Int {
        var picker = FramePicker(options: options)
        var n = 0
        let total = Int(fps * seconds)
        for i in 0..<total {
            let wobble = jitter * (i % 2 == 0 ? 1 : -1)
            if picker.shouldDeliver(at: Double(i) / fps + wobble) { n += 1 }
        }
        return n
    }

    func testTwentyPerSecondFrom30And60() {
        let o = RemotePlaySession.Options.twentyPerSecond
        XCTAssertEqual(o.maxFrameRate, 20)
        XCTAssertEqual(Double(count(fps: 30, seconds: 3, options: o)), 60, accuracy: 2)
        XCTAssertEqual(Double(count(fps: 60, seconds: 3, options: o)), 60, accuracy: 2)
        XCTAssertEqual(Double(count(fps: 60, seconds: 3, options: o, jitter: 0.001)), 60, accuracy: 2)
    }

    func testSlowSourceIsNotThrottled() {
        let o = RemotePlaySession.Options(maxFrameRate: 20)
        XCTAssertEqual(count(fps: 10, seconds: 3, options: o), 30)
    }

    func testRestartsAfterGap() {
        var p = FramePicker(options: .init(maxFrameRate: 20))
        XCTAssertTrue(p.shouldDeliver(at: 0))
        XCTAssertTrue(p.shouldDeliver(at: 5))   // uzun boşluk
        XCTAssertFalse(p.shouldDeliver(at: 5.02))
        XCTAssertTrue(p.shouldDeliver(at: 5.05))
    }

    func testStrideModeUnchanged() {
        let o = RemotePlaySession.Options(fps: 30, frameStride: 4)
        XCTAssertNil(o.maxFrameRate)
        XCTAssertEqual(count(fps: 30, seconds: 4, options: o), 30)
        XCTAssertNil(RemotePlaySession.Options(maxFrameRate: 0).maxFrameRate)
    }
}

final class RegistrationErrorTests: XCTestCase {
    func testWrongPINFromApplicationReason() {
        let lines = ["Regist connected to 192.168.0.20, sending request",
                     "Regist received HTTP code 403",
                     "Reported Application Reason: 0x80108b09 (Regist failed, probably invalid PIN)",
                     "Regist eventually failed"]
        let e = RegistrationError.parse(log: lines)
        XCTAssertEqual(e.reason, .wrongPIN)
        XCTAssertEqual(e.applicationReason, 0x8010_8B09)
        XCTAssertEqual(e.httpStatus, 403)
        XCTAssertEqual(e.log, lines)
        XCTAssertTrue(e.description.contains("0x80108b09"))
    }

    func testOtherReasons() {
        XCTAssertEqual(RegistrationError.parse(log: ["Reported Application Reason: 0x80108b02 (Invalid PSN ID)"]).reason, .invalidAccount)
        XCTAssertEqual(RegistrationError.parse(log: ["Reported Application Reason: 0x80108b10 (Remote is already in use)"]).reason, .consoleBusy)
        XCTAssertEqual(RegistrationError.parse(log: [
            "Regist failed to receive search response: Connection refused",
            "The console refused the registration search, keep its Link Device (PS5) or Add Device (PS4) screen with the code open while registering",
        ]).reason, .linkScreenNotOpen)
        XCTAssertEqual(RegistrationError.parse(log: ["Regist timed out waiting for search response", "Regist search failed"]).reason, .unreachable)
        XCTAssertEqual(RegistrationError.parse(log: ["Regist failed to getaddrinfo on yok.local"]).reason, .badAddress)
        XCTAssertEqual(RegistrationError.parse(log: [], timedOut: true).reason, .timeout)
        let unknown = RegistrationError.parse(log: ["Reported Application Reason: 0x80108bff (unknown)"])
        XCTAssertEqual(unknown.reason, .unknown)
        XCTAssertEqual(unknown.applicationReason, 0x8010_8BFF)
    }

    func testLogIsCapped() {
        let lines = (0..<100).map { "satır \($0)" }
        XCTAssertEqual(RegistrationError.parse(log: lines).log, Array(lines.suffix(30)))
    }
}

final class ManualConsoleTests: XCTestCase {
    func testManualConsoleInfo() {
        let c = ConsoleInfo(address: "192.168.0.20")
        XCTAssertEqual(c.hostID, "")
        XCTAssertTrue(c.isPS5)
        XCTAssertEqual(c.target, Int32(CHIAKI_TARGET_PS5_1.rawValue))
        XCTAssertNil(c.macAddress)
        XCTAssertEqual(ConsoleInfo(address: "x", isPS5: false).target, Int32(CHIAKI_TARGET_PS4_10.rawValue))
    }

    func testMACFromHostID() {
        let c = ConsoleInfo(hostID: "A1B2C3D4E5F6", address: "192.168.0.20")
        XCTAssertEqual(c.macAddress, [0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6])
        XCTAssertNil(ConsoleInfo(hostID: "ZZ", address: "x").macAddress)
        XCTAssertEqual(RegisteredConsole.hostID(fromMAC: [0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6]), "A1B2C3D4E5F6")
    }

    func testRegisteredConsolePublicInit() {
        let r = RegisteredConsole(hostID: "H", nickname: "N", isPS5: true, target: 1, registKey: [], rpKey: [], serverMAC: [])
        XCTAssertEqual(r.hostID, "H")
    }
}

final class UnicastDiscoveryTests: XCTestCase {
    /// 127.0.0.1'de PS5 yok: cevap gelmez, arama temiz biter.
    func testProbeLocalhostFindsNothing() async throws {
        let d = ConsoleDiscovery()
        let found = try await d.probe(host: "127.0.0.1", timeout: 1.5)
        XCTAssertNil(found)
    }

    func testRejectsBadHost() {
        let d = ConsoleDiscovery()
        XCTAssertThrowsError(try d.consoles(host: "fe80::1"))
        XCTAssertThrowsError(try d.consoles(host: "  "))
    }
}
