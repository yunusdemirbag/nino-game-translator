// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import NinoCore
import XCTest
@testable import Nino

/// TV uygulaması sürüm denetimi, dil paketi indirme isteği ve Xbox 720p / yayın başlatma hatası.
@MainActor
final class UpdateAndXboxTests: XCTestCase {
    private func model() -> AppModel {
        let suite = "nino-update-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let folders = AppFolders(support: FileManager.default.temporaryDirectory, logs: FileManager.default.temporaryDirectory)
        return AppModel(store: MemoryStore(), defaults: defaults, folders: folders, ephemeral: true)
    }

    // MARK: TV uygulaması sürümü

    func testUpdateOfferWhenTVAppIsOlder() async {
        let m = model()
        _ = await m.pairTV(PairedTV(name: "Salon", host: "", brand: .androidTV))
        m.tvPackageVersions = [.androidTV: "4.5.0", .lg: "4.5.0"]
        XCTAssertNil(m.tvUpdateOffer, "TV'deki sürüm bilinmiyor")
        m.tvAppReported(version: "0.1.0-beta.37", host: "192.168.0.110")
        XCTAssertEqual(m.tvUpdateOffer, TVUpdateOffer(brand: .androidTV, installed: "0.1.0-beta.37", available: "4.5.0"))
        m.tvAppReported(version: "4.5.0", host: "192.168.0.110")
        XCTAssertNil(m.tvUpdateOffer, "güncel TV'de kart yok")
        m.tvAppReported(version: "4.6.0", host: "192.168.0.110")
        XCTAssertNil(m.tvUpdateOffer, "TV daha yeniyse kart yok")
    }

    /// Eski TV uygulaması 8787'ye bağlanırken sürümünü bildirir; TV yolu bunu modele iletir.
    func testLegacyTVReportsItsVersion() async throws {
        let link = TVLink(legacyPort: 0, ingressPort: 0)
        let seen = LatestBox<String>()
        link.onTVAppVersion = { version, _ in seen.set(version) }
        await link.start(tv: nil, deviceName: "iPhone", version: "4.5.0")
        let url = URL(string: "http://127.0.0.1:\(link.legacyPort)/events?model=Deneme&app=0.1.0-beta.37")!
        let reader = Task { _ = try? await URLSession.shared.bytes(from: url) }
        let deadline = Date().addingTimeInterval(5)
        while seen.get() == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(seen.get(), "0.1.0-beta.37")
        reader.cancel()
        await link.stop()
    }

    func testPackageLocalVersionPicksNewest() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nino-tvpkg-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var store = TVPackageStore(cache: dir)
        store.bundled = nil
        XCTAssertNil(store.localVersion(.lg), "paket yoksa sürüm yok")
    }

    // MARK: Dil paketi

    func testLanguagePackRequest() {
        var r = LanguagePackRequest()
        XCTAssertFalse(r.busy)
        r.start(source: "en", target: "tr")
        XCTAssertTrue(r.busy)
        XCTAssertEqual(r.attempt, 1)
        r.start(source: "en", target: "ar")
        XCTAssertEqual(r.target, "tr", "indirme sürerken ikinci basış yok sayılır")
        r.finish()
        XCTAssertFalse(r.busy)
        r.start(source: "en", target: "tr")
        XCTAssertEqual(r.attempt, 2, "yeniden basınca yeni istek (sistem penceresi yeniden açılır)")
    }

    // MARK: Xbox

    func testXboxResolutionSetting() throws {
        XCTAssertTrue(XboxChannelMessages.screenSize(lowResolution: true) == (1280, 720))
        XCTAssertTrue(XboxChannelMessages.screenSize(lowResolution: false) == (1920, 1080))
        let text = XboxChannelMessages.clientMessages(width: 1280, height: 720).joined()
        XCTAssertTrue(text.contains("1280") && text.contains("720"))

        var s = AppSettings()
        XCTAssertFalse(s.xboxLowResolution)
        s.xboxLowResolution = true
        let data = try JSONEncoder().encode(s)
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: data).xboxLowResolution)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"xboxAudioOnDevice":false}"#.utf8))
        XCTAssertFalse(old.xboxLowResolution, "eski kayıtta yoksa kapalı")
    }

    func testStartStreamingSessionFailureHasItsOwnAdvice() {
        XCTAssertEqual(XboxSessionPlan.refusal(#"{"code":"StartStreamingSessionFailed"}"#), .startFailed)
        XCTAssertEqual(XboxSessionPlan.refusal("Console is busy"), .busy)
        XCTAssertEqual(XboxSessionPlan.refusal(nil), .unreachable)
        let text = XboxText.session(.startFailed, willRetry: false)
        XCTAssertEqual(text, L("xbox.session.startfailed"))
        XCTAssertNotEqual(text, L("xbox.session.gaveup"))
    }
}
