// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import ImageIO
import XCTest
@testable import NinoCore

/// Oyunu ekrandan hızlı tanıma: tarif imzaları, paketlerden çıkan adlar, ilk saniyeler.
final class GameMarkersTests: XCTestCase {
    private func frame(_ folder: String, _ name: String) throws -> CGImage {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Resources/\(folder)"))
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
    }

    // MARK: İmzalar (yazılı satırlarla)

    func testPauseMenuSignature() {
        let m = GR.GameMarkers()
        let lines = [gline("CHAPTER 2", gbox(0.9, 0.12, 0.98, 0.15)), gline("SLAM DUNK"), gline("Retry Checkpoint"),
                     gline("Restart Mission"), gline("Quit Mission"), gline("CJ Photo Studio"), gline("Settings"),
                     gline("PHOTO STUDlO O SELECT Q BACK O'")]
        XCTAssertEqual(m.signature(lines)?.id, "gta-6")
        // Photo Studio olmadan genel görev menüsü başka oyunda da olabilir: tanınmaz.
        XCTAssertNil(m.signature([gline("Retry Checkpoint"), gline("Restart Mission"), gline("Quit Mission"), gline("Settings"),
                                  gline("Help")]))
    }

    func testMapTopBarNeedsTopArea() {
        let m = GR.GameMarkers()
        XCTAssertEqual(m.signature([gline("JASON & LUCIA MAP BRIEF PROGRESS", gbox(0.37, 0.03, 0.63, 0.06))])?.id, "gta-6")
        // Aynı sözcükler ekranın ortasında (altyazı) imza sayılmaz.
        XCTAssertNil(m.signature([gline("Jason and Lucia, brief me on the progress on the map", gbox(0.3, 0.85, 0.7, 0.9))]))
    }

    func testGenericMenuIsNotGTA() {
        let m = GR.GameMarkers()
        XCTAssertNil(m.signature([gline("Options"), gline("Map"), gline("Progress"), gline("Quit Game")]))
        XCTAssertNil(m.signature([gline("Jason, wait for me!")]))
    }

    // MARK: Paketlerden adlar (eski paket: yalnız Türkçe metin, özet anahtarı)

    private func legacy(_ id: String, _ title: String, _ lines: [String]) -> LegacyPack {
        var entries: [UInt64: String] = [:]
        for (i, t) in lines.enumerated() { entries[UInt64(i + 1) + UInt64(id.count) * 10_000] = t }
        return LegacyPack(id: id, title: title, entries: entries)
    }

    func testPackNamesAreDistinctive() {
        let west = legacy("old-west", "Old West", [
            "Bunu Arthur'a söyle, Dutch bekliyor.", "Sen de, Arthur, gel buraya.", "Ama Dutch haklı.",
            "Yarın Arthur ile Hosea gidecek.", "Peki, Dutch bekler.", "Hadi Arthur.", "Bak, Dutch, Bay Strauss geldi.",
            "Evet Bay Strauss.", "Hosea nerede, Bay Strauss?", "Hey, Hosea!", "Hosea, gel.", "O Hosea ve Strauss.", "Bu da Hosea.",
        ])
        let city = legacy("old-city", "Old City", [
            "Bunu Enzo'ya söyle, Bay Torrisi.", "Sen de, Enzo, gel.", "Ama Bay Torrisi haklı.", "Yarın Enzo gidecek.",
            "Hadi Enzo.", "Evet Bay Torrisi.", "Bak, Bay Torrisi.", "Hey, Luca.", "Luca, gel.", "Peki Luca.", "Bu Luca.", "Ve Luca da.",
        ])
        let names = GR.GameMarkers.packNames(LegacyLibrary(packs: [.legacy(west), .legacy(city)]))
        let w = try? XCTUnwrap(names.first { $0.id == "old-west" })
        XCTAssertEqual(Set(w?.names ?? []), ["arthur", "dutch", "hosea", "strauss"])
        let c = names.first { $0.id == "old-city" }
        XCTAssertEqual(Set(c?.names ?? []), ["enzo", "torrisi", "luca"])
        // "Bay" her iki pakette sık: ayırt edici değil.
        XCTAssertFalse(names.contains { $0.names.contains("bay") })

        let m = GR.GameMarkers(library: LegacyLibrary(packs: [.legacy(west), .legacy(city)]))
        let sense = GR.QuickGameSense(markers: m, reader: ScriptedReader(), clock: GR.ManualClock(0))
        sense.start()
        XCTAssertNil(sense.observeLines([gline("ARTHUR: Come on.")]), "tek ad yetmez")
        let v = sense.observeLines([gline("DUTCH: We need money.")])
        XCTAssertEqual(v?.id, "old-west")
        XCTAssertEqual(v?.strong, false, "yalnız adlar: zayıf")
    }

    func testNamesTieIsNotCertain() {
        let m = GR.GameMarkers(recipes: [], packNames: [(id: "a", name: "A", names: ["arthur", "dutch"]),
                                                        (id: "b", name: "B", names: ["enzo", "luca"])])
        let sense = GR.QuickGameSense(markers: m, reader: ScriptedReader(), clock: GR.ManualClock(0))
        sense.start()
        XCTAssertNil(sense.observeLines([gline("Arthur and Enzo"), gline("Dutch, Luca")]))
    }

    // MARK: Zamanlama

    func testFirstTenSecondsEveryFrameThenSlower() {
        let clock = GR.ManualClock(0)
        let sense = GR.QuickGameSense(reader: ScriptedReader(), clock: clock)
        XCTAssertFalse(sense.claim(), "başlamadan okunmaz")
        sense.start()
        // Remote Play bağlanırken 20 sn kare gelmez: pencere ilk karede başlar.
        clock.advance(20_000)
        XCTAssertTrue(sense.claim())
        XCTAssertFalse(sense.claim(), "okuma sürerken kare atlanır")
        _ = sense.observeLines([])
        // `read` bitmeden yeni okuma yok; sahte okumayı bitir.
        let done = expectation(description: "read")
        Task { _ = await sense.read(GR.ImageFrame(solidImage(width: 8, height: 8, gray: 0))); done.fulfill() }
        wait(for: [done], timeout: 2)
        clock.advance(33)
        XCTAssertTrue(sense.claim(), "ilk 10 sn'de her kare")
        let done2 = expectation(description: "read2")
        Task { _ = await sense.read(GR.ImageFrame(solidImage(width: 8, height: 8, gray: 0))); done2.fulfill() }
        wait(for: [done2], timeout: 2)
        clock.advance(10_000)
        XCTAssertTrue(sense.claim())
        let done3 = expectation(description: "read3")
        Task { _ = await sense.read(GR.ImageFrame(solidImage(width: 8, height: 8, gray: 0))); done3.fulfill() }
        wait(for: [done3], timeout: 2)
        clock.advance(1_000)
        XCTAssertFalse(sense.claim(), "10 sn'den sonra 5 sn arayla")
        clock.advance(4_000)
        XCTAssertTrue(sense.claim())
        sense.stop()
    }

    // MARK: Gerçek kareler (hızlı Vision)

    /// Sahte saatle kareler 33 ms arayla gelir; tanıma ilk karelerde, 3 sn içinde olmalı.
    private func recognitionMs(_ images: [CGImage]) async -> (ms: Int, verdict: GR.GameMarkers.Verdict)? {
        let clock = GR.ManualClock(0)
        let sense = GR.QuickGameSense(reader: GR.QuickTextReader(), clock: clock)
        sense.start()
        for i in 0..<90 {
            if let v = await sense.observe(GR.ImageFrame(images[i % images.count])) { return (clock.nowMs, v) }
            clock.advance(33)
        }
        return nil
    }

    func testRealFramesRecognizedWithinThreeSeconds() async throws {
        let cases: [(String, String)] = [("gta6-menu", "pause-chapter2"), ("gta6-map", "map-13-15-51"),
                                         ("gta6-map", "map-13-16-11"), ("gta6-map", "liquor-14-18-08")]
        for (folder, name) in cases {
            let image = try frame(folder, name)
            guard let r = await recognitionMs([image]) else {
                let lines = try await GR.QuickTextReader().read(GR.ImageFrame(image), area: gbox(0, 0, 1, 1), scale: 1)
                if lines.isEmpty { throw XCTSkip("Vision bu ortamda yazı okumadı") }
                XCTFail("\(name) tanınmadı: \(lines.map(\.text))")
                continue
            }
            XCTAssertEqual(r.verdict.id, "gta-6", name)
            XCTAssertTrue(r.verdict.strong, name)
            XCTAssertLessThanOrEqual(r.ms, 3_000, name)
        }
    }

    /// Yalnız oyun içi kareler (altyazı, araba): yazı işareti yok, yanlış oyun da tanınmaz.
    func testGameplayFramesDoNotGuessWrongGame() async throws {
        let images = try ["sub-14-20-44-287", "sub-14-20-53-746"].map { try frame("gta6-subtitle", $0) }
        if let r = await recognitionMs(images) { XCTAssertEqual(r.verdict.id, "gta-6") }
    }

    // MARK: Telefon kararı

    func testPhoneStaysOnWhenGameUnknown() {
        typealias P = GR.PhoneGame
        XCTAssertTrue(P.decide(cornersEnabled: true, sourceLanguage: "en", targetLanguage: "de", game: .unknown,
                               lastGameWasPoolPriority: false).on)
        XCTAssertTrue(P.decide(cornersEnabled: true, sourceLanguage: "en", targetLanguage: "tr", game: .unknown,
                               lastGameWasPoolPriority: false).on)
        XCTAssertFalse(P.decide(cornersEnabled: false, sourceLanguage: "en", targetLanguage: "tr", game: .unknown,
                                lastGameWasPoolPriority: true).on)
    }
}
