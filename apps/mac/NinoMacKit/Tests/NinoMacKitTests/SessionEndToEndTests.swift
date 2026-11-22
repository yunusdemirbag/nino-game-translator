// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

#if canImport(Vision) && canImport(CoreText)
import CoreGraphics
import CoreText
import Foundation
import NinoCore
import XCTest
@testable import NinoMacKit

/// Uçtan uca: çizilmiş altyazılı kareler → gerçek okuyucu (Vision) → sahte çevirmen → gerçek DisplayHub →
/// 127.0.0.1'de gerçek TV sunucusu (NinoDisplayServer) ve eski 8787 SSE istemcisi. Ağ dışarı çıkmaz,
/// gerçek kasa/ayar/klasöre dokunulmaz, portlar sistemin seçtiği.
@MainActor
final class SessionEndToEndTests: XCTestCase {
    struct DictionaryTranslator: SubtitleTranslating {
        let table: [String: String]
        func translate(_ sentence: String) async -> SessionTranslation {
            func key(_ t: String) -> String { String(t.lowercased().filter { $0.isLetter || $0 == " " }) }
            if let hit = table.first(where: { key($0.key) == key(sentence) }) {
                return SessionTranslation(text: hit.value, origin: .engine)
            }
            return SessionTranslation(text: sentence, origin: .untranslated, failed: true)
        }
    }

    final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ s: String) { lock.withLock { items.append(s) } }
        var all: [String] { lock.withLock { items } }
    }

    static func frame(_ text: String?, width: Int = 1280, height: Int = 720) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let text {
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 44, nil)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1)]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
            let w = CTLineGetTypographicBounds(line, nil, nil, nil)
            ctx.textPosition = CGPoint(x: (Double(width) - w) / 2, y: Double(height) * 0.12)
            CTLineDraw(line, ctx)
        }
        return ctx.makeImage()!
    }

    func testFramesReachTVAndLegacyViewer() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("nino-e2e-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let folder = DataFolder(support: root.appendingPathComponent("support"), logs: root.appendingPathComponent("logs"))
        let suite = "nino-e2e-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // "TV": NinoCore'un gerçek TV sunucusu, yalnız 127.0.0.1, Bonjour yayını yok.
        let tv = NinoDisplayServer(options: .init(name: "Deneme TV", port: 0, advertise: false))
        let tvShows = Collected()
        tv.onChange = { p in if let p { tvShows.add(p.text) } }
        let tvPort = try await tv.start()
        defer { tv.stop() }

        // Kasa: PSN hesabı, PS5 kaydı ve dinleyen TV (Android TV).
        let vault = MemoryVault()
        let records = SecureRecords(vault: vault)
        try records.setAccountID(Data(repeating: 7, count: 8))
        try records.setConsole(ConsoleRecord(host: "192.168.0.20", name: "PS5-Deneme",
                                             registKey: Data(repeating: 0x31, count: 16), morning: Data(repeating: 2, count: 16)))
        try records.setTV(TVRecord(name: "Deneme TV", host: "127.0.0.1", brand: .androidTV))
        try records.setSetupComplete(true)

        var settings = MacSettings()
        settings.output = .tv
        settings.videoSource = .ps5
        let store = SettingsStore(defaults: defaults)
        store.save(settings)

        let lines = ["Hold the gate, boy.", "We go home now."]
        let source = ScriptedFrameSource(steps: [
            .init(Self.frame(nil), repeats: 4),
            .init(Self.frame(lines[0]), repeats: 25),
            .init(Self.frame(nil), repeats: 25),
            .init(Self.frame(lines[1]), repeats: 25),
            .init(Self.frame(nil), repeats: 200),
        ], interval: .milliseconds(40))
        let translator = DictionaryTranslator(table: [lines[0]: "Kapıyı tut, evlat.", lines[1]: "Şimdi eve gidiyoruz."])

        var env = LiveEngineEnvironment(
            identity: AppIdentity(flavor: .testing, defaultsDomain: suite, keychainService: "test", folderName: "test"),
            folder: folder, settingsStore: store, vault: vault,
            ports: DisplayLinks.Ports(ingress: 0, legacy: 0, tv: tvPort, randomFallback: false),
            appVersion: "4.1.0", poolBaseURL: nil, packsBaseURL: nil, poolTransport: nil,
            providerTransport: URLSession.shared, deviceProvider: { nil },
            textReader: GameReading.VisionTextReader(), clock: GameReading.SystemClock(),
            checksTranslatorReadiness: false)
        env.makeSource = { _, callbacks in
            callbacks.status(.ps5(.streaming))
            return SessionSource(frames: source)
        }
        env.makeTranslator = { _ in translator }

        let state = AppState()
        let engine = LiveEngine(state: state, environment: env)
        XCTAssertTrue(state.isSetupComplete)
        XCTAssertEqual(state.translation, .off, "kendiliğinden başlamamalı")
        XCTAssertTrue(state.canStart)

        engine.startTranslation()
        await engine.lastStart?.value
        XCTAssertEqual(state.translation, .on)

        // Eski 8787 izleyicisi (SSE).
        let legacyPort = try XCTUnwrap(engine.links.legacyPort)
        let sse = Collected()
        let url = URL(string: "http://127.0.0.1:\(legacyPort)/events?model=Deneme")!
        let reader = Task {
            guard let (bytes, _) = try? await URLSession.shared.bytes(from: url) else { return }
            var event = ""
            do {
                for try await line in bytes.lines {
                    if line.hasPrefix("event: ") { event = String(line.dropFirst(7)) }
                    if line.hasPrefix("data: "), event == "subtitle" { sse.add(String(line.dropFirst(6))) }
                }
            } catch {}
        }
        defer { reader.cancel() }

        // İki altyazı da TV'ye ve eski izleyiciye gitmeli.
        let deadline = Date().addingTimeInterval(30)
        func done() -> Bool {
            let want = ["Kapıyı tut, evlat.", "Şimdi eve gidiyoruz."]
            return want.allSatisfy { w in tvShows.all.contains(w) } && want.allSatisfy { w in sse.all.contains { $0.contains(w) } }
        }
        while Date() < deadline, !done() { try await Task.sleep(for: .milliseconds(100)) }

        if tvShows.all.isEmpty, sse.all.isEmpty, state.history.isEmpty {
            throw XCTSkip("Vision bu ortamda yazı okumadı")
        }
        XCTAssertTrue(tvShows.all.contains("Kapıyı tut, evlat."), "TV: \(tvShows.all)")
        XCTAssertTrue(tvShows.all.contains("Şimdi eve gidiyoruz."), "TV: \(tvShows.all)")
        XCTAssertTrue(sse.all.contains { $0.contains("Kapıyı tut, evlat.") }, "8787: \(sse.all)")
        XCTAssertTrue(sse.all.contains { $0.contains("Şimdi eve gidiyoruz.") }, "8787: \(sse.all)")
        XCTAssertGreaterThanOrEqual(state.connectedDisplays, 1)
        XCTAssertEqual(state.history.first?.translated, "Şimdi eve gidiyoruz.")
        XCTAssertTrue(state.history.contains { $0.translated == "Kapıyı tut, evlat." })

        engine.stopTranslation()
        await engine.lastStop?.value
        XCTAssertEqual(state.translation, .off)
        await engine.links.stop()

        // Geçmiş ve altyazı günlüğü geçici klasöre yazıldı.
        HistoryStore(folder: folder).flush()
        XCTAssertFalse(HistoryStore(folder: folder).load().isEmpty)
        engine.subtitleLog.flush()
        let log = try String(contentsOf: folder.subtitleLog, encoding: .utf8)
        XCTAssertTrue(log.contains("Kapıyı tut"), log)
        try Self.assertLineJourney(log, source: "Hold the gate", translated: "Kapıyı tut, evlat.", origin: "cihaz")
    }

    /// Günlükte bir satırın yolculuğu aynı #n ile sırayla: okundu → çeviri → gösterildi → kalktı.
    static func assertLineJourney(_ log: String, source: String, translated: String, origin: String,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        let rows = log.split(separator: "\n").map(String.init)
        let readRow = try XCTUnwrap(rows.firstIndex { $0.contains(" okundu ") && $0.contains(source) }, log, file: file, line: line)
        let id = try XCTUnwrap(rows[readRow].range(of: #"#\d+"#, options: .regularExpression).map { String(rows[readRow][$0]) },
                               file: file, line: line)
        func index(_ needle: String, after start: Int) -> Int? {
            rows.indices.first { $0 > start && rows[$0].contains("\(id) \(needle)") }
        }
        let tr = try XCTUnwrap(index("çeviri: \(origin) ", after: readRow), log, file: file, line: line)
        XCTAssertTrue(rows[tr].contains(translated) && rows[tr].contains(" ms "), rows[tr], file: file, line: line)
        let shown = try XCTUnwrap(index("gösterildi (TV ", after: tr), log, file: file, line: line)
        let gone = try XCTUnwrap(index("kalktı", after: shown), log, file: file, line: line)
        XCTAssertNotNil(rows[gone].range(of: #"kalktı \(\d+ ms\)"#, options: .regularExpression), rows[gone], file: file, line: line)
    }

    func testDevelopmentIdentityNeverStartsByItself() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("nino-dev-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let suite = "nino-dev-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Date().timeIntervalSince1970, forKey: DefaultsKey.resumeAfterRelaunch)
        defaults.set(true, forKey: DefaultsKey.adminMode)
        let vault = MemoryVault()
        try SecureRecords(vault: vault).setSetupComplete(true)
        let made = Collected()
        var env = LiveEngineEnvironment(
            identity: .development, folder: DataFolder(support: root, logs: root), settingsStore: SettingsStore(defaults: defaults),
            vault: vault, ports: .ephemeral, appVersion: "4.1.0", poolBaseURL: nil, packsBaseURL: nil, poolTransport: nil,
            providerTransport: URLSession.shared, deviceProvider: { nil }, textReader: GameReading.VisionTextReader(),
            clock: GameReading.SystemClock(), checksTranslatorReadiness: false)
        env.makeSource = { _, _ in made.add("x"); return SessionSource(frames: IdleFrameSource()) }
        let state = AppState()
        let engine = LiveEngine(state: state, environment: env)
        XCTAssertEqual(state.translation, .off)
        XCTAssertNil(engine.lastStart)
        XCTAssertTrue(made.all.isEmpty)
        XCTAssertFalse(engine.links.isRunning, "deneme yapısı açılışta port tutmamalı")
        XCTAssertNil(defaults.object(forKey: DefaultsKey.resumeAfterRelaunch))
    }

    func testGameTrackerVotes() {
        var g = GameTracker()
        g.startSession(at: Date())
        // Karışık oylar: 5 gerekir.
        XCTAssertFalse(g.vote(packID: "elden-ring", title: "Elden Ring"))
        for _ in 0..<4 { XCTAssertFalse(g.vote(packID: "god-of-war", title: "God of War")) }
        XCTAssertFalse(g.vote(packID: LegacyLibrary.generalPackID, title: nil))
        XCTAssertTrue(g.vote(packID: "god-of-war", title: "God of War"))
        XCTAssertEqual(g.current?.name, "God of War")
        XCTAssertEqual(g.evidence, .pack)
        // Hepsi aynı paketse 3 isabet yeter.
        g.startSession(at: Date())
        XCTAssertFalse(g.vote(packID: "god-of-war", title: "God of War"))
        XCTAssertFalse(g.vote(packID: "god-of-war", title: "God of War"))
        XCTAssertTrue(g.vote(packID: "god-of-war", title: "God of War"))
        XCTAssertEqual(g.current?.name, "God of War")
        XCTAssertEqual(g.evidence, .pack)
        XCTAssertFalse(g.isCertain)
        g.choose("Elden Ring")
        XCTAssertEqual(g.evidence, .user)
        // Konsol başka oyun bildirirse elle seçim silinir; konsol önce gelir.
        g.consoleReported(name: "Ghost of Yōtei")
        XCTAssertEqual(g.current?.name, "Ghost of Yōtei")
        XCTAssertNil(g.user)
    }

    /// Bellek kasası, geçici klasör, 0 portları; kaynak sahte.
    func makeEngine(source: @escaping @Sendable () -> SessionSource, made: Collected) throws -> (LiveEngine, AppState, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nino-race-\(UUID().uuidString)", isDirectory: true)
        let suite = "nino-race-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        var settings = MacSettings()
        settings.output = .computer
        settings.videoSource = .window
        SettingsStore(defaults: defaults).save(settings)
        var env = LiveEngineEnvironment(
            identity: AppIdentity(flavor: .testing, defaultsDomain: suite, keychainService: "test", folderName: "test"),
            folder: DataFolder(support: root, logs: root), settingsStore: SettingsStore(defaults: defaults), vault: MemoryVault(),
            ports: .ephemeral, appVersion: "4.1.0", poolBaseURL: nil, packsBaseURL: nil, poolTransport: nil,
            providerTransport: URLSession.shared, deviceProvider: { nil }, textReader: GameReading.VisionTextReader(),
            clock: GameReading.SystemClock(), checksTranslatorReadiness: false)
        env.makeSource = { _, _ in made.add("source"); return source() }
        env.makeTranslator = { _ in DictionaryTranslator(table: [:]) }
        let state = AppState()
        return (LiveEngine(state: state, environment: env), state, root)
    }

    func testStopWhileStartingOpensNoSource() async throws {
        let made = Collected()
        let (engine, state, root) = try makeEngine(source: { SessionSource(frames: IdleFrameSource()) }, made: made)
        defer { try? FileManager.default.removeItem(at: root) }
        engine.startTranslation()
        XCTAssertEqual(state.translation, .starting)
        engine.stopTranslation()
        await engine.lastStart?.value
        await engine.lastStop?.value
        XCTAssertEqual(state.translation, .off)
        XCTAssertTrue(made.all.isEmpty, "durdurulan başlatma kaynak açmamalı")
        await engine.links.stop()
    }

    func testStopThenStartEndsOn() async throws {
        let made = Collected()
        let (engine, state, root) = try makeEngine(source: { SessionSource(frames: IdleFrameSource()) }, made: made)
        defer { try? FileManager.default.removeItem(at: root) }
        engine.startTranslation()
        await engine.lastStart?.value
        XCTAssertEqual(state.translation, .on)
        engine.stopTranslation()
        engine.startTranslation()
        await engine.lastStart?.value
        XCTAssertEqual(state.translation, .on)
        XCTAssertEqual(made.all.count, 2)
        XCTAssertTrue(engine.links.isRunning)
        engine.stopTranslation()
        await engine.lastStop?.value
        await engine.links.stop()
    }

    func testStyleMapping() {
        var s = SubtitleStyle()
        s.fontSize = 52
        s.theme = .cinema
        let n = NinoStyle(s)
        XCTAssertEqual(n.fontSize, 52)
        XCTAssertEqual(n.theme, "cinema")
        XCTAssertEqual(n.placement, "cover")
    }
}
#endif
