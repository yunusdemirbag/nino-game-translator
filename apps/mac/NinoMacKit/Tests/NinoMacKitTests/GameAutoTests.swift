// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import NinoCore
import XCTest
@testable import NinoMacKit

/// Oyun sorulmaz: son oynanan hemen etkin, ekran işaretleri ve paket isabetleri arka planda doğrular ya da geçer.
@MainActor
final class GameAutoTests: XCTestCase {
    /// Her okumada aynı satırları veren okuyucu.
    struct LinesReader: GameReading.TextReader {
        var lines: [GameReading.Line]
        func read(_ frame: GameReading.Frame, area: GameReading.Box, scale: Double) async throws -> [GameReading.Line] { lines }
    }

    /// GTA 6 duraklatma menüsü karesinin (NinoCore `gta6-menu/pause-chapter2.jpg`) hızlı okumadaki satırları.
    static let pauseMenuLines: [GameReading.Line] = [
        "CHAPTER 2", "SLAM DUNK", "111 Map", "Retry Checkpoint", ") Game", "Restart Mission", "Quit Mission",
        "CJ Photo Studio", "Settings", "PHOTO STUDlO O SELECT Q BACK O'",
    ].map { GameReading.Line($0, confidence: 0.6) }

    static func image() -> CGImage {
        let ctx = CGContext(data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 36))
        return ctx.makeImage()!
    }

    struct Rig {
        let engine: LiveEngine
        let state: AppState
        let defaults: UserDefaults
        let root: URL
    }

    func makeRig(quick: [GameReading.Line]?, lastGame: String? = nil, pinned: String? = nil,
                 clock: GameReading.Clock = GameReading.SystemClock()) throws -> Rig {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nino-game-\(UUID().uuidString)", isDirectory: true)
        let suite = "nino-game-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        var settings = MacSettings()
        settings.output = .computer
        settings.videoSource = .window
        settings.askGame = true // eski kayıtta açık olsa bile soru çıkmaz
        SettingsStore(defaults: defaults).save(settings)
        if let lastGame { defaults.set(["": lastGame], forKey: "lastGames") }
        if let pinned { defaults.set(["": pinned], forKey: "pinnedGames") } // eski sürümlerin elle seçimi
        var env = LiveEngineEnvironment(
            identity: AppIdentity(flavor: .testing, defaultsDomain: suite, keychainService: "test", folderName: "test"),
            folder: DataFolder(support: root, logs: root), settingsStore: SettingsStore(defaults: defaults), vault: MemoryVault(),
            ports: .ephemeral, appVersion: "4.1.0", poolBaseURL: nil, packsBaseURL: nil, poolTransport: nil,
            providerTransport: URLSession.shared, deviceProvider: { nil }, textReader: LinesReader(lines: []),
            clock: clock, checksTranslatorReadiness: false)
        env.phoneTextReader = LinesReader(lines: [])
        env.quickTextReader = quick.map { LinesReader(lines: $0) }
        let image = Self.image()
        env.makeSource = { _, _ in
            SessionSource(frames: ScriptedFrameSource(steps: [.init(image, repeats: 400)], interval: .milliseconds(33)))
        }
        env.makeTranslator = { _ in SessionEndToEndTests.DictionaryTranslator(table: [:]) }
        let state = AppState()
        return Rig(engine: LiveEngine(state: state, environment: env), state: state, defaults: defaults, root: root)
    }

    func finish(_ rig: Rig) async {
        rig.engine.stopTranslation()
        await rig.engine.lastStop?.value
        await rig.engine.links.stop()
    }

    func phoneOn(_ rig: Rig) async -> Bool { await rig.engine.session?.overlays?.isPhoneGame ?? false }

    // MARK: Başlarken son oyun etkin

    func testStartMakesGTA6ActiveWhenNothingRemembered() async throws {
        let rig = try makeRig(quick: nil)
        rig.engine.startTranslation()
        await rig.engine.lastStart?.value
        XCTAssertEqual(rig.state.translation, .on)
        XCTAssertEqual(rig.state.game?.name, "GTA 6")
        XCTAssertEqual(rig.state.game?.id, "gta-6")
        XCTAssertEqual(rig.state.game?.evidence, .lastPlayed)
        XCTAssertFalse(rig.engine.games.isConfirmed)
        let phone = await phoneOn(rig)
        XCTAssertTrue(phone, "telefon ve harita okuması başlarken açık")
        await finish(rig)
    }

    func testStartMakesLastPlayedActive() async throws {
        let rig = try makeRig(quick: nil, lastGame: "Mafia: The Old Country")
        rig.engine.startTranslation()
        await rig.engine.lastStart?.value
        XCTAssertEqual(rig.state.game?.name, "Mafia: The Old Country")
        XCTAssertEqual(rig.state.game?.evidence, .lastPlayed)
        XCTAssertEqual(rig.state.sheetsStatus.lastPlayedGame, "Mafia: The Old Country")
        // Tahmin kesin sayılmaz: telefon kapanmaz.
        let phone = await phoneOn(rig)
        XCTAssertTrue(phone)
        await finish(rig)
    }

    // MARK: İlk karelerde tanıma

    func testFirstFramesRecognizeGTA6WithinThreeSecondsAndSwitchSilently() async throws {
        let rig = try makeRig(quick: Self.pauseMenuLines, lastGame: "Mafia: The Old Country")
        let started = Date()
        rig.engine.startTranslation()
        await rig.engine.lastStart?.value
        while rig.state.game?.evidence != .screen, Date().timeIntervalSince(started) < 5 {
            try await Task.sleep(for: .milliseconds(20))
        }
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(rig.state.game?.name, "GTA 6")
        XCTAssertEqual(rig.state.game?.evidence, .screen)
        XCTAssertLessThanOrEqual(elapsed, 3, "ekrandan tanıma 3 sn içinde")
        // PS5 adına göre hatırlanır; hızlı okuma durur.
        XCTAssertEqual((rig.defaults.dictionary(forKey: "lastGames") as? [String: String])?[""], "GTA 6")
        XCTAssertFalse(rig.engine.quickSense?.isRunning ?? true)
        let phone = await phoneOn(rig)
        XCTAssertTrue(phone)
        await finish(rig)
        let log = (try? String(contentsOf: rig.root.appendingPathComponent("altyazi.log"), encoding: .utf8)) ?? ""
        XCTAssertTrue(log.contains("Mafia: The Old Country yerine geçildi"), log)
    }

    // MARK: Oyun bilinmezken

    func testUnconfirmedGuessIsDroppedButPhoneStaysOnAndNoQuestion() async throws {
        let rig = try makeRig(quick: nil, lastGame: "Mafia: The Old Country")
        rig.engine.startTranslation()
        await rig.engine.lastStart?.value
        rig.engine.checkSeed(nowMs: (rig.engine.seedSinceMs ?? 0) + LiveEngine.seedTimeoutMs)
        XCTAssertNil(rig.state.game)
        XCTAssertNil(rig.engine.games.current)
        XCTAssertTrue(rig.engine.phoneDecision(rig.state.settings).on, "oyun bilinmezken telefon/harita açık")
        try await Task.sleep(for: .milliseconds(100))
        let phone = await phoneOn(rig)
        XCTAssertTrue(phone)
        await finish(rig)
    }

    // MARK: Elle seçim yok

    /// Eski sürümde elle seçilmiş oyun kayıtta dursa da kullanılmaz: oyun hep kendiliğinden (son oynanan tahmini).
    func testLegacyPinnedGameIsIgnored() async throws {
        let rig = try makeRig(quick: nil, lastGame: "GTA 6", pinned: "Red Dead Redemption 2")
        rig.engine.startTranslation()
        await rig.engine.lastStart?.value
        XCTAssertEqual(rig.state.game?.name, "GTA 6")
        XCTAssertEqual(rig.state.game?.evidence, .lastPlayed)
        XCTAssertEqual((rig.defaults.dictionary(forKey: "pinnedGames") as? [String: String])?[""],
                       "Red Dead Redemption 2", "eski kayıt silinmez, yalnız okunmaz")
        await finish(rig)
    }

    // MARK: Paket isabetleri

    func testPackHitsConfirmOrSwitchGuess() {
        var g = GameTracker()
        g.startSession(at: Date())
        g.seed("GTA 6")
        XCTAssertEqual(g.evidence, .lastPlayed)
        // Tahminle aynı paketten tek isabet doğrular.
        XCTAssertTrue(g.vote(packID: "gta-6", title: "Grand Theft Auto VI"))
        XCTAssertEqual(g.evidence, .pack)
        XCTAssertTrue(g.isConfirmed)

        g.startSession(at: Date())
        g.seed("GTA 6")
        // Başka oyun: tek isabet yetmez, aynı paketten 3 isabet geçirir.
        XCTAssertFalse(g.vote(packID: "old-west", title: "Old West"))
        XCTAssertFalse(g.vote(packID: "old-west", title: "Old West"))
        XCTAssertEqual(g.current?.name, "GTA 6")
        XCTAssertTrue(g.vote(packID: "old-west", title: "Old West"))
        XCTAssertEqual(g.current?.name, "Old West")
    }

    // MARK: Satır anahtarı (sahte paket)

    /// Paket İngilizce metin taşımaz: okunan satırın anahtarı bir pakette bulunursa o oyun.
    func testLineKeysInAnotherPackSwitchFromGTA6Guess() async throws {
        let rig = try makeRig(quick: nil)
        let lines = ["We ride at dawn, boys.", "Hold the line, they are coming from the hill.", "Get the horses ready.",
                     "That is no way to talk to a lady.", "Put that bottle down and listen."]
        var entries: [String: String] = [:]
        for (i, l) in lines.enumerated() { entries[LineKey.hex(try XCTUnwrap(LineKey.key(l)))] = "Satır \(i)" }
        let pack: [String: Any] = ["format": 2, "id": "old-west", "title": "Old West", "entries": entries]
        let folder = rig.engine.env.folder.packsFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: pack).write(to: folder.appendingPathComponent("old-west.json"))
        await rig.engine.reloadLibrary()
        rig.engine.startTranslation()
        await rig.engine.lastStart?.value
        XCTAssertEqual(rig.state.game?.name, "GTA 6")
        // Havuz öncelikli tahminde çevirmen pakete bakmaz; gösterilen satırlar yine oy verir.
        rig.engine.noteShownLine(LiveLine(translated: "x", source: "Some line that is in no pack.", origin: .engine))
        rig.engine.noteShownLine(LiveLine(translated: "x", source: lines[0], origin: .pool))
        rig.engine.noteShownLine(LiveLine(translated: "x", source: lines[1], origin: .engine))
        XCTAssertEqual(rig.state.game?.name, "GTA 6", "iki isabet geçmeye yetmez")
        rig.engine.noteShownLine(LiveLine(translated: "x", source: lines[2], origin: .engine))
        XCTAssertEqual(rig.state.game?.name, "Old West")
        XCTAssertEqual(rig.state.game?.evidence, .pack)
        XCTAssertEqual((rig.defaults.dictionary(forKey: "lastGames") as? [String: String])?[""], "Old West")
        await finish(rig)
    }

    /// Yalnız özel adlar (imza yok) başka oyuna geçirmez; tahmini doğrular.
    func testNamesOnlyConfirmButNeverSwitch() async throws {
        let rig = try makeRig(quick: [GameReading.Line("Arthur, Dutch, come here", confidence: 0.9)],
                              lastGame: "GTA 6")
        rig.engine.quickSense?.setMarkers(GameReading.GameMarkers(packNames: [(id: "old-west", name: "Old West",
                                                                               names: ["arthur", "dutch"])]))
        rig.engine.startTranslation()
        await rig.engine.lastStart?.value
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(rig.state.game?.name, "GTA 6")
        XCTAssertEqual(rig.state.game?.evidence, .lastPlayed)
        rig.engine.noteShownLine(LiveLine(translated: "x", source: "Jason, wait. Lucia is here.", origin: .pool))
        XCTAssertEqual(rig.state.game?.evidence, .screen, "GTA 6 adları tahmini doğrular")
        await finish(rig)
    }
}
