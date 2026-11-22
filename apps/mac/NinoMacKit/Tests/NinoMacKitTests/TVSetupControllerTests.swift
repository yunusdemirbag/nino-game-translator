// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore
import XCTest
@testable import NinoMacKit

@MainActor
final class TVSetupControllerTests: XCTestCase {
    private func make(_ f: TVFakes, helper: Bool = true, output: MacSettings.Output = .computer) -> (AppState, TVSetupController) {
        var s = MacSettings()
        s.output = output
        let state = AppState(settings: s)
        let c = TVSetupController(state: state, environment: f.environment(helper: helper))
        return (state, c)
    }

    /// LG TV: kayıt olur, uygulamayı açar (sonuç `launched`).
    private func lgSockets(_ f: TVFakes, launched: Bool) {
        f.sockets.factory = { url in
            let s = FakeSocket(url: url)
            s.onSend = { text, socket in
                let o = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
                if o["type"] as? String == "register" {
                    socket.push(#"{"type":"registered","payload":{"client-key":"LGKEY"}}"#)
                } else if let id = o["id"] as? String {
                    socket.push("{\"type\":\"response\",\"id\":\"\(id)\",\"payload\":{\"returnValue\":\(launched)}}")
                }
            }
            return s
        }
    }

    func testSearchFillsFoundTVs() async {
        let f = TVFakes()
        f.ssdp.reply = { req, _ in
            req.contains("lge-com") ? [SSDPResponse(headers: ["ST": TVDiscovery.lgSearchTarget], sender: "192.168.0.50")] : []
        }
        let (state, c) = make(f)
        c.searchTVs()
        XCTAssertEqual(state.setup.tvSearch, .searching)
        await waitUntil { state.setup.tvSearch == .finished }
        XCTAssertEqual(state.setup.foundTVs, [DiscoveredTV(name: "LG TV", host: "192.168.0.50", brand: .lg)])
    }

    func testPairLGSavesKeyAndShowsPassphraseCard() async throws {
        let f = TVFakes()
        lgSockets(f, launched: false)
        f.ports.set("192.168.0.50", 9991, true)
        let (state, c) = make(f)
        c.pairTV(DiscoveredTV(name: "Salon", host: "192.168.0.50", brand: .lg))
        await waitUntil { state.setup.tvApp != .none }
        XCTAssertEqual(state.setup.tvConnect, .idle)
        XCTAssertEqual(try f.records.tvKey(), "LGKEY")
        XCTAssertEqual(try f.records.tv(), TVRecord(name: "Salon", host: "192.168.0.50", brand: .lg))
        XCTAssertEqual(state.pairedTV, PairedTV(name: "Salon", host: "192.168.0.50", brand: .lg, hasKey: true))
        XCTAssertEqual(state.settings.output, .tv, "TV'm yok seçiliyken çıktı TV'ye geçer")
        XCTAssertEqual(state.setup.tvApp, .lgPassphrase(error: nil))
        XCTAssertGreaterThan(f.server.started, 0)
        // Uygulama açma iletisinde sunucu adresi.
        let launch = f.sockets.opened[0].sentObjects.first { $0["uri"] as? String == "ssap://system.launcher/launch" }
        let params = (launch?["payload"] as? [String: Any])?["params"] as? [String: Any]
        XCTAssertEqual(params?["server"] as? String, "http://192.168.0.10:8787")
        c.shutdown()
    }

    func testPairLGWithLaunchedAppAndDevModeOffHasNoCard() async throws {
        let f = TVFakes()
        lgSockets(f, launched: true)
        let (state, c) = make(f, output: .tv)
        c.pairTV(DiscoveredTV(name: "Salon", host: "192.168.0.50", brand: .lg))
        await waitUntil { state.pairedTV != nil }
        await waitUntil { state.setup.tvConnect == .idle }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.setup.tvApp, .none)
        XCTAssertEqual(state.tvInstall, .idle)
        c.shutdown()
    }

    func testPairSamsungRefused() async {
        let f = TVFakes()
        f.sockets.factory = { FakeSocket(url: $0, initial: [#"{"event":"ms.channel.unauthorized"}"#]) }
        let (state, c) = make(f)
        c.pairTV(DiscoveredTV(name: "S", host: "192.168.0.7", brand: .samsung))
        await waitUntil { if case .failed = state.setup.tvConnect { return true }; return false }
        XCTAssertEqual(state.setup.tvConnect, .failed(.samsungRefused))
        XCTAssertNil(try? f.records.tv())
        let lgFail = TVFakes()
        let (s2, c2) = make(lgFail)
        c2.pairTV(DiscoveredTV(name: "L", host: "192.168.0.50", brand: .lg))
        await waitUntil { if case .failed = s2.setup.tvConnect { return true }; return false }
        XCTAssertEqual(s2.setup.tvConnect, .failed(.noResponse))
    }

    func testSamsungEmptyTokenKeepsStoredToken() async throws {
        let f = TVFakes()
        try f.records.setTV(TVRecord(name: "S", host: "192.168.0.7", brand: .samsung))
        try f.records.setTVKey("OLDTOKEN")
        f.sockets.factory = { FakeSocket(url: $0, initial: [#"{"event":"ms.channel.connect","data":{}}"#]) }
        let (state, c) = make(f, helper: false)
        c.pairTV(DiscoveredTV(name: "S", host: "192.168.0.7", brand: .samsung))
        await waitUntil { state.setup.tvConnect == .idle && state.pairedTV != nil }
        XCTAssertEqual(try f.records.tvKey(), "OLDTOKEN")
        XCTAssertTrue(f.sockets.attempted[0].absoluteString.hasSuffix("&token=OLDTOKEN"))
        // Yardımcı yoksa Samsung kurulumu gizli.
        await waitUntil { state.setup.tvAppBundled == false }
        XCTAssertFalse(state.setup.tvAppBundled)
        c.shutdown()
    }

    func testSamsungWrongHostIPShowsCheckCardAndLogs() async throws {
        let f = TVFakes()
        try f.records.setTV(TVRecord(name: "S", host: "192.168.0.7", brand: .samsung))
        f.http.set("http://192.168.0.7:8001/api/v2/", 200, #"{"device":{"developerMode":"1","developerIP":"192.168.0.99","model":"22_X"}}"#)
        f.ports.set("192.168.0.7", 26101, true)
        let (state, c) = make(f)
        c.recheckTVApp()
        await waitUntil { if case let .samsungCheck(ch) = state.setup.tvApp { return ch.problem == .wrongAddress }; return false }
        guard case let .samsungCheck(card) = state.setup.tvApp else { return XCTFail() }
        XCTAssertEqual(card.tvHostIP, "192.168.0.99")
        XCTAssertEqual(card.macAddress, "192.168.0.10")
        XCTAssertEqual(card.modelYear, 2022)
        XCTAssertTrue(f.logSink.all.contains { $0.contains("kurulum denenmedi") })
        XCTAssertTrue(f.processes.allCalls.isEmpty, "adres sorununda kurulum denenmez")
        c.shutdown()
    }

    func testSamsungInstallWithSignInAndDone() async throws {
        let f = TVFakes()
        try f.records.setTV(TVRecord(name: "S", host: "192.168.0.7", brand: .samsung))
        f.http.set("http://192.168.0.7:8001/api/v2/", 200, #"{"device":{"developerMode":"1","developerIP":"192.168.0.10"}}"#)
        f.ports.set("192.168.0.7", 26101, true)
        f.processes.startHandler = { _ in FakeRunning(lines: [#"{"event":"login","url":"https://account.example/login"}"#,
                                                              #"{"event":"progress","step":"installing"}"#,
                                                              #"{"event":"done","version":"0.7.0","installed":true}"#]) }
        f.sockets.factory = { FakeSocket(url: $0, initial: [#"{"event":"ms.channel.connect","data":{"token":"T1"}}"#]) }
        let (state, c) = make(f)
        c.recheckTVApp()
        await waitUntil { state.setup.tvApp == .ready(version: "0.7.0", lgHoursLeft: nil) }
        XCTAssertEqual(state.tvInstall, .installed(version: "0.7.0"))
        XCTAssertEqual(try f.records.tvAppVersion(), "0.7.0")
        XCTAssertEqual(try f.records.tvKey(), "T1", "kurulunca uygulama açılır")
        let args = f.processes.allCalls[0].arguments
        XCTAssertEqual(args.first, "samsung-install")
        XCTAssertEqual(args.last, "--exit-with-input")
        c.shutdown()
    }

    func testSamsungUnreachableAfterCurrentInstallStaysReady() async throws {
        let f = TVFakes()
        try f.records.setTV(TVRecord(name: "S", host: "192.168.0.7", brand: .samsung))
        try f.records.setTVAppVersion("0.7.0")
        f.http.set("http://192.168.0.7:8001/api/v2/", 200, #"{"device":{"developerMode":"1"}}"#)
        f.ports.set("192.168.0.7", 26101, true)
        f.processes.startHandler = { _ in FakeRunning(lines: [#"{"event":"error","code":"Unreachable","message":"refused"}"#], exitCode: 1) }
        let (state, c) = make(f)
        c.recheckTVApp()
        await waitUntil { !f.processes.allCalls.isEmpty }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.setup.tvApp, .ready(version: "0.7.0", lgHoursLeft: nil))
        c.shutdown()
    }

    func testSamsungUnreachableShowsDroppedCard() async throws {
        let f = TVFakes()
        try f.records.setTV(TVRecord(name: "S", host: "192.168.0.7", brand: .samsung))
        f.http.set("http://192.168.0.7:8001/api/v2/", 200, #"{"device":{"developerMode":"1","developerIP":"192.168.0.10"}}"#)
        f.ports.set("192.168.0.7", 26101, true)
        f.processes.startHandler = { _ in FakeRunning(lines: [#"{"event":"error","code":"Unreachable","message":"reset"}"#], exitCode: 1) }
        let (state, c) = make(f)
        c.recheckTVApp()
        await waitUntil { if case let .samsungCheck(ch) = state.setup.tvApp { return ch.problem == .dropped(reason: "reset") }; return false }
        guard case let .samsungCheck(ch) = state.setup.tvApp else { return XCTFail() }
        XCTAssertEqual(ch.problem, .dropped(reason: "reset"))
        c.shutdown()
    }

    func testAndroidPairAndInstall() async throws {
        let f = TVFakes()
        f.processes.startHandler = { args in
            if args.first == "android-scan" { return FakeRunning(lines: [#"{"event":"found","hosts":["192.168.0.110"]}"#]) }
            return FakeRunning(lines: [#"{"event":"approve"}"#, #"{"event":"done","version":"0.7.0","installed":true}"#])
        }
        let (state, c) = make(f)
        c.pairTV(.androidTV)
        await waitUntil { state.setup.tvApp == .ready(version: "0.7.0", lgHoursLeft: nil) }
        XCTAssertEqual(try f.records.tv(), TVRecord(name: "Android TV", host: "192.168.0.110", brand: .androidTV))
        XCTAssertEqual(try f.records.tvAppVersion(), "0.7.0")
        XCTAssertEqual(state.pairedTV?.hasKey, true)
        let install = f.processes.allCalls.first { $0.arguments.first == "android-install" }
        XCTAssertEqual(install?.arguments[2], "192.168.0.110")
        XCTAssertTrue(install?.arguments.contains(f.folder.adbFolder.path) == true)
        c.shutdown()
    }

    func testAndroidWithoutDebuggingShowsCardAndCurrentConnectedAppIsReady() async throws {
        let f = TVFakes()
        try f.records.setTV(TVRecord(name: "Android TV", host: "", brand: .androidTV))
        f.processes.startHandler = { _ in FakeRunning(lines: [#"{"event":"found","hosts":[]}"#]) }
        let (state, c) = make(f)
        c.recheckTVApp()
        await waitUntil { state.setup.tvApp == .androidDebuggingOff }
        XCTAssertEqual(state.tvInstall, .searching)
        f.server.connected = ["0.7.1"]
        c.recheckTVApp()
        await waitUntil { state.setup.tvApp == .ready(version: "0.7.1", lgHoursLeft: nil) }
        c.shutdown()
    }

    func testLGPassphraseInstallAndKeyRejection() async throws {
        let f = TVFakes()
        try f.records.setTV(TVRecord(name: "Salon", host: "192.168.0.50", brand: .lg))
        lgSockets(f, launched: false)
        f.ports.set("192.168.0.50", 9922, true)
        f.http.set("http://192.168.0.50:9991/webos_rsa", 200, "ENC")
        f.processes.runHandler = { call in
            if call.executable == "ssh-keygen" {
                try? "DEVKEY".write(toFile: call.arguments.last!, atomically: false, encoding: .utf8)
                return TVProcessResult(exitCode: 0)
            }
            return TVProcessResult(exitCode: 255, stderr: Data("Permission denied".utf8))
        }
        let (state, c) = make(f)
        c.installTVApp(passphrase: " ABC123 ")
        await waitUntil { if case .lgPassphrase(let e) = state.setup.tvApp { return e != nil }; return false }
        XCTAssertNil(try f.records.tvDevKey(), "reddedilen anahtar silinir")
        XCTAssertTrue(f.processes.allCalls.contains { $0.executable == "ssh-keygen" && $0.arguments.contains("ABC123") })
        c.shutdown()
    }

    func testLGInstalledShowsReadyAndExtendsOnce() async throws {
        let f = TVFakes()
        try f.records.setTV(TVRecord(name: "Salon", host: "192.168.0.50", brand: .lg))
        try f.records.setTVDevKey("DEVKEY")
        lgSockets(f, launched: true)
        f.ports.set("192.168.0.50", 9922, true)
        f.processes.runHandler = { call in
            let cmd = call.arguments.last!
            if cmd.hasPrefix("cat /media/developer/apps") { return TVProcessResult(exitCode: 0, stdout: Data(#"{"version":"0.7.0"}"#.utf8)) }
            if cmd.contains("devmode_enabled") { return TVProcessResult(exitCode: 0, stdout: Data("TOK".utf8)) }
            return TVProcessResult(exitCode: 0)
        }
        f.http.set("https://developer.lge.com/secure/ResetDevModeSession.dev?sessionToken=TOK", 200, "success")
        f.http.set("https://developer.lge.com/secure/CheckDevModeSession.dev?sessionToken=TOK", 200, "998:00:00")
        let (state, c) = make(f)
        c.recheckTVApp()
        await waitUntil { state.setup.tvApp == .ready(version: "0.7.0", lgHoursLeft: 998) }
        XCTAssertNotNil(f.defaults.object(forKey: LGDeveloperMode.extensionDefaultsKey(host: "192.168.0.50")))
        // 20 saat dolmadan yeniden uzatılmaz.
        c.recheckTVApp()
        await waitUntil { state.setup.tvApp == .ready(version: "0.7.0", lgHoursLeft: nil) }
        c.shutdown()
        f.cleanUp()
    }

    func testRediscoverStoresNewAddress() async throws {
        let f = TVFakes()
        try f.records.setTV(TVRecord(name: "Salon", host: "192.168.0.50", brand: .lg))
        f.ssdp.reply = { _, _ in [SSDPResponse(headers: ["ST": TVDiscovery.lgSearchTarget], sender: "192.168.0.51")] }
        let (state, c) = make(f)
        let new = await c.rediscoverAddress()
        XCTAssertEqual(new?.host, "192.168.0.51")
        XCTAssertEqual(state.pairedTV?.host, "192.168.0.51")
        let again = await c.rediscoverAddress()
        XCTAssertNil(again, "30 sn dolmadan yeniden aranmaz")
    }

    func testSendTestSubtitle() async throws {
        let f = TVFakes()
        let (state, c) = make(f, output: .tv)
        c.sendTestSubtitle(style: NinoStyle(fontSize: 40))
        XCTAssertEqual(state.setup.test, .sending)
        await waitUntil { state.setup.test == .sent }
        let shown = await f.server.display.shown
        XCTAssertEqual(shown.count, 1)
        XCTAssertEqual(shown.first?.durationMs, 8000)
        XCTAssertEqual(shown.first?.box, NinoBox(left: 0.30, top: 0.90, right: 0.70, bottom: 0.97))
        let events = await f.server.display.events
        XCTAssertEqual(events, [.style(NinoStyle(fontSize: 40))])
        c.sendTestSubtitle()
        XCTAssertEqual(state.setup.test, .resending)
        await waitUntil { state.setup.test == .sent }
    }

    func testCardMirrorsInstallState() {
        let f = TVFakes()
        let (state, c) = make(f)
        c.setCard(.working)
        XCTAssertEqual(state.tvInstall, .installing(progress: nil))
        c.setCard(.androidApprove)
        XCTAssertEqual(state.tvInstall, .waitingForApproval)
        c.setCard(.failed(message: "x"))
        XCTAssertEqual(state.tvInstall, .failed(message: "x"))
        c.setCard(.none)
        XCTAssertEqual(state.tvInstall, .idle)
        c.shutdown()
    }
}
