// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore
import XCTest
@testable import NinoMacKit

/// Sahadaki eski kimlikli TV uygulaması (tv-kurulumu.md, "Eski TV uygulaması"): yalnız eski kurulu → eski açılır;
/// ikisi de kurulu → yeni açılır; hiçbiri → kurulum kartı. Eski kimlikler yalnız `LegacyNames`'ten okunur.
@MainActor
final class TVLegacyAppTests: XCTestCase {
    private func make(_ f: TVFakes) -> (AppState, TVSetupController) {
        var s = MacSettings()
        s.output = .tv
        let state = AppState(settings: s)
        return (state, TVSetupController(state: state, environment: f.environment()))
    }

    // MARK: LG

    /// Sahte LG TV: `installed` kimlikleri listApps'te görünür ve yalnız onlar açılır.
    private func lgTV(_ f: TVFakes, installed: [String], listsApps: Bool = true) {
        f.sockets.factory = { url in
            let s = FakeSocket(url: url)
            s.onSend = { text, socket in
                let o = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
                if o["type"] as? String == "register" {
                    socket.push(#"{"type":"registered","payload":{"client-key":"LGKEY"}}"#)
                    return
                }
                guard let id = o["id"] as? String else { return }
                var payload: [String: Any] = ["returnValue": true]
                switch o["uri"] as? String {
                case "ssap://com.webos.applicationManager/listApps":
                    if listsApps { payload["apps"] = (installed + ["netflix"]).map { ["id": $0] } }
                case "ssap://system.launcher/launch":
                    let app = (o["payload"] as? [String: Any])?["id"] as? String ?? ""
                    payload["returnValue"] = installed.contains(app)
                case "ssap://com.webos.applicationManager/getForegroundAppInfo":
                    payload["appId"] = "com.webos.app.hdmi2"
                default:
                    break
                }
                let data = (try? JSONSerialization.data(withJSONObject: ["type": "response", "id": id, "payload": payload])) ?? Data()
                socket.push(String(decoding: data, as: UTF8.self))
            }
            return s
        }
    }

    private func launchedIDs(_ f: TVFakes) -> [String] {
        f.sockets.opened.flatMap(\.sentObjects)
            .filter { $0["uri"] as? String == "ssap://system.launcher/launch" }
            .compactMap { ($0["payload"] as? [String: Any])?["id"] as? String }
    }

    func testLGOnlyLegacyOpensLegacyAndKeepAliveUsesIt() async throws {
        let f = TVFakes()
        lgTV(f, installed: [TVApp.legacyLGID])
        let (state, c) = make(f)
        c.pairTV(DiscoveredTV(name: "Salon", host: "192.168.0.50", brand: .lg))
        await waitUntil { state.setup.tvApp != .none }
        XCTAssertEqual(state.setup.tvApp, .legacyApp(version: ""), "eski çalışır; kurulum zorlanmaz")
        XCTAssertEqual(state.tvInstall, .installed(version: nil))
        XCTAssertEqual(launchedIDs(f), [TVApp.legacyLGID], "listApps'te yeni yok: doğrudan eski açılır")
        // Açık tutma: TV kendi girişine geçince aynı (eski) kimlik açılır.
        await c.keepAliveTick()
        XCTAssertEqual(launchedIDs(f).last, TVApp.legacyLGID)
        XCTAssertEqual(launchedIDs(f).filter { $0 == TVApp.lgID }, [])
        c.shutdown()
        f.cleanUp()
    }

    /// LG'de her launch uygulamayı yeniden başlatır (ekran kapanıp açılır): TV uygulaması bize bağlıyken açık tutma
    /// hiç launch göndermez — ne SSAP soketi yeniden kurulunca ne TV kendi girişinde görünürken. Bağlantı yoksa açar.
    func testLGKeepAliveDoesNotRelaunchWhileTVAppConnected() async throws {
        let f = TVFakes()
        lgTV(f, installed: [TVApp.lgID])
        let (state, c) = make(f)
        c.pairTV(DiscoveredTV(name: "Salon", host: "192.168.0.50", brand: .lg))
        await waitUntil { state.setup.tvConnect == .idle && state.pairedTV != nil }
        try await Task.sleep(nanoseconds: 50_000_000)
        let before = launchedIDs(f).count
        f.server.connected = ["4.5.0"]
        await c.keepAliveTick()                       // soket canlı, ön plan TV girişi
        f.sockets.opened.forEach { $0.close() }       // soket koptu
        await c.keepAliveTick()                       // yeniden kurulur
        await c.keepAliveTick()
        XCTAssertEqual(launchedIDs(f).count, before, "bağlantı canlıyken launch tekrar edilmez")
        f.server.connected = []
        await c.keepAliveTick()
        XCTAssertGreaterThan(launchedIDs(f).count, before, "bağlantı yoksa uygulama açılır")
        c.shutdown()
        f.cleanUp()
    }

    func testLGPairReplacingAnotherTVKeepsLegacyState() async throws {
        let f = TVFakes()
        try f.records.setTV(TVRecord(name: "Eski", host: "192.168.0.60", brand: .lg))
        try f.records.setTVDevKey("DEVKEY")
        lgTV(f, installed: [TVApp.legacyLGID])
        let (state, c) = make(f)
        c.pairTV(DiscoveredTV(name: "Salon", host: "192.168.0.50", brand: .lg))
        await waitUntil { state.setup.tvApp != .none }
        XCTAssertEqual(state.setup.tvApp, .legacyApp(version: ""))
        XCTAssertFalse(f.processes.allCalls.contains { $0.executable == "ssh" }, "eski varken kendiliğinden kurulmaz")
        c.shutdown()
        f.cleanUp()
    }

    func testLGWithoutAppListTriesNewThenLegacy() async throws {
        let f = TVFakes()
        lgTV(f, installed: [TVApp.legacyLGID], listsApps: false)
        let (state, c) = make(f)
        c.pairTV(DiscoveredTV(name: "Salon", host: "192.168.0.50", brand: .lg))
        await waitUntil { state.setup.tvApp != .none }
        XCTAssertEqual(launchedIDs(f), [TVApp.lgID, TVApp.legacyLGID])
        XCTAssertEqual(state.setup.tvApp, .legacyApp(version: ""))
        c.shutdown()
        f.cleanUp()
    }

    func testLGBothInstalledOpensNew() async throws {
        let f = TVFakes()
        lgTV(f, installed: [TVApp.lgID, TVApp.legacyLGID])
        let (state, c) = make(f)
        c.pairTV(DiscoveredTV(name: "Salon", host: "192.168.0.50", brand: .lg))
        await waitUntil { state.setup.tvConnect == .idle && state.pairedTV != nil }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(launchedIDs(f), [TVApp.lgID])
        XCTAssertEqual(state.setup.tvApp, .none, "yeni uygulama açıldı, geliştirici modu kapalı: kart yok")
        c.shutdown()
        f.cleanUp()
    }

    func testLGNeitherInstalledShowsInstallCardAndUpgradeFromLegacyDoesToo() async throws {
        let f = TVFakes()
        lgTV(f, installed: [])
        let (state, c) = make(f)
        c.pairTV(DiscoveredTV(name: "Salon", host: "192.168.0.50", brand: .lg))
        await waitUntil { state.setup.tvApp != .none }
        XCTAssertEqual(state.setup.tvApp, .lgDeveloperModeOff(passphraseError: nil))
        c.shutdown()

        // Eski uygulama kartından "Yeni Sürümü Kur": kurulum kartları çıkar.
        let g = TVFakes()
        lgTV(g, installed: [TVApp.legacyLGID])
        let (s2, c2) = make(g)
        c2.pairTV(DiscoveredTV(name: "Salon", host: "192.168.0.50", brand: .lg))
        await waitUntil { s2.setup.tvApp == .legacyApp(version: "") }
        c2.upgradeLegacyTVApp()
        await waitUntil { s2.setup.tvApp == .lgDeveloperModeOff(passphraseError: nil) }
        XCTAssertEqual(s2.setup.tvApp, .lgDeveloperModeOff(passphraseError: nil))
        c2.shutdown()
        f.cleanUp()
        g.cleanUp()
    }

    // MARK: Samsung

    private func samsungTV(_ f: TVFakes, new: Int, legacy: Int) {
        f.http.set("http://192.168.0.7:8001/api/v2/", 200, #"{"device":{"developerMode":"0"}}"#)
        f.http.set("http://192.168.0.7:8001/api/v2/applications/\(TVApp.samsungID)", new, "{}")
        f.http.set("http://192.168.0.7:8001/api/v2/applications/\(TVApp.legacySamsungID)", legacy, "{}")
        f.sockets.factory = { FakeSocket(url: $0, initial: [#"{"event":"ms.channel.connect","data":{"token":"T1"}}"#]) }
    }

    private func samsungLaunchedIDs(_ f: TVFakes) -> [String] {
        f.sockets.opened.flatMap(\.sentObjects).compactMap { o in
            ((o["params"] as? [String: Any])?["data"] as? [String: Any])?["appId"] as? String
        }
    }

    func testSamsungOnlyLegacyOpensLegacyAndShowsLegacyCard() async throws {
        let f = TVFakes()
        samsungTV(f, new: 404, legacy: 200)
        let (state, c) = make(f)
        c.pairTV(DiscoveredTV(name: "S", host: "192.168.0.7", brand: .samsung))
        await waitUntil { state.setup.tvApp == .legacyApp(version: "") }
        XCTAssertEqual(samsungLaunchedIDs(f), [TVApp.legacySamsungID])
        XCTAssertTrue(f.processes.allCalls.isEmpty, "geliştirici modu kapalı: yardımcı çalışmaz")
        // Açık tutma da (30 sn sonra, TV bağlanmamışken) yine eskiyi açar; kesin bilgi değişmez.
        try await f.clock.sleep(31)
        await c.samsungKeepAlive(try XCTUnwrap(c.savedTV()))
        XCTAssertEqual(samsungLaunchedIDs(f), [TVApp.legacySamsungID, TVApp.legacySamsungID])
        c.shutdown()
        f.cleanUp()
    }

    func testSamsungBothInstalledOpensNew() async throws {
        let f = TVFakes()
        samsungTV(f, new: 200, legacy: 200)
        let (state, c) = make(f)
        c.pairTV(DiscoveredTV(name: "S", host: "192.168.0.7", brand: .samsung))
        await waitUntil { if case .samsungCheck(let ch) = state.setup.tvApp { return ch.problem == .developerModeOff }; return false }
        XCTAssertEqual(samsungLaunchedIDs(f), [TVApp.samsungID])
        c.shutdown()
        f.cleanUp()
    }

    func testSamsungNeitherInstalledShowsCheckCard() async throws {
        let f = TVFakes()
        samsungTV(f, new: 404, legacy: 404)
        let (state, c) = make(f)
        c.pairTV(DiscoveredTV(name: "S", host: "192.168.0.7", brand: .samsung))
        await waitUntil { if case .samsungCheck(let ch) = state.setup.tvApp { return ch.problem == .developerModeOff }; return false }
        guard case .samsungCheck = state.setup.tvApp else { return XCTFail("\(state.setup.tvApp)") }
        XCTAssertEqual(samsungLaunchedIDs(f), [TVApp.samsungID])
        c.shutdown()
        f.cleanUp()
    }

    func testSamsungUnknownQueryTriesLegacyWhenNewDoesNotConnect() async throws {
        let f = TVFakes()
        f.sockets.factory = { FakeSocket(url: $0, initial: [#"{"event":"ms.channel.connect","data":{"token":"T1"}}"#]) }
        try f.records.setTV(TVRecord(name: "S", host: "192.168.0.7", brand: .samsung))
        let (_, c) = make(f)
        let tv = try XCTUnwrap(c.savedTV())
        await c.samsungKeepAlive(tv)
        try await f.clock.sleep(31)
        await c.samsungKeepAlive(tv)
        XCTAssertEqual(samsungLaunchedIDs(f), [TVApp.samsungID, TVApp.legacySamsungID])
        c.shutdown()
        f.cleanUp()
    }

    func testSamsungHelperReportsLegacyAndUpgradeInstallsNew() async throws {
        let f = TVFakes()
        try f.records.setTV(TVRecord(name: "S", host: "192.168.0.7", brand: .samsung))
        f.http.set("http://192.168.0.7:8001/api/v2/", 200, #"{"device":{"developerMode":"1","developerIP":"192.168.0.10"}}"#)
        f.ports.set("192.168.0.7", 26101, true)
        f.sockets.factory = { FakeSocket(url: $0, initial: [#"{"event":"ms.channel.connect","data":{"token":"T1"}}"#]) }
        f.processes.startHandler = { args in
            args.contains("--keep-legacy") ? FakeRunning(lines: [#"{"event":"legacy","version":"0.4.2"}"#])
                : FakeRunning(lines: [#"{"event":"done","version":"0.7.0","installed":true}"#])
        }
        let (state, c) = make(f)
        c.recheckTVApp()
        await waitUntil { state.setup.tvApp == .legacyApp(version: "0.4.2") }
        XCTAssertNil(try f.records.tvAppVersion(), "eski sürüm yeni uygulamanın sürümü sayılmaz")
        c.upgradeLegacyTVApp()
        await waitUntil { state.setup.tvApp == .ready(version: "0.7.0", lgHoursLeft: nil) }
        XCTAssertFalse(f.processes.allCalls.last!.arguments.contains("--keep-legacy"))
        XCTAssertEqual(samsungLaunchedIDs(f).last, TVApp.samsungID, "kurulumdan sonra açma önceliği yenide")
        c.shutdown()
        f.cleanUp()
    }

    // MARK: Android TV

    func testAndroidLegacyOutcomeShowsLegacyCard() async throws {
        let f = TVFakes()
        try f.records.setTV(TVRecord(name: "Android TV", host: "192.168.0.110", brand: .androidTV))
        f.ports.set("192.168.0.110", 5555, true)
        f.processes.startHandler = { _ in FakeRunning(lines: [#"{"event":"legacy","version":"0.5.1"}"#]) }
        let (state, c) = make(f)
        c.recheckTVApp()
        await waitUntil { state.setup.tvApp == .legacyApp(version: "0.5.1") }
        let args = f.processes.allCalls.first { $0.arguments.first == "android-install" }?.arguments ?? []
        XCTAssertTrue(args.contains("--keep-legacy"))
        XCTAssertNil(try f.records.tvAppVersion())
        c.shutdown()
        f.cleanUp()
    }

    func testLegacyIDsComeFromEncodedNames() {
        XCTAssertEqual(TVApp.lgIDs, [TVApp.lgID, LegacyNames.tvPackage])
        XCTAssertEqual(TVApp.samsungIDs, [TVApp.samsungID, LegacyNames.samsungTVAppID])
        XCTAssertTrue(TVApp.legacyLGID.hasPrefix("com.") && TVApp.legacyLGID.hasSuffix(".tv"))
        XCTAssertNotEqual(TVApp.legacyLGID, TVApp.lgID)
        XCTAssertFalse(LegacyNames.samsungTVPackageID.isEmpty)
        XCTAssertFalse(LegacyNames.samsungTVPackageID.contains("."))
    }
}

/// Deneme altyazısı arayüz diline değil çevirinin hedef diline göre.
final class TVTestLineLanguageTests: XCTestCase {
    func testTestLineFollowsTargetLanguage() {
        XCTAssertTrue(TVSetupController.testLine(language: "tr").hasPrefix("Bu bir test"))
        XCTAssertTrue(TVSetupController.testLine(language: "en").hasPrefix("Test subtitle"))
    }
}
