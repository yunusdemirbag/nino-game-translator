// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import CoreGraphics
import Foundation
import NinoCore
import XCTest
@testable import NinoMacKit

/// Ekran öğeleri uçtan uca: çizilmiş telefon/harita/ek alan kareleri → okuma hattı (sahte okuyucular) → ScreenOverlays
/// → gerçek DisplayHub → 127.0.0.1'deki eski 8787 sunucusu (SSE: `screen`, `region`). Ağ dışarı çıkmaz, gerçek
/// kasa/ayar/klasöre dokunulmaz, ölçüm sahte taşıyıcıyla (gönderim yok).
@MainActor
final class SessionOverlaysTests: XCTestCase {
    /// Her şeyi "TR: …" diye çeviren sahte çevirmen.
    struct EchoTranslator: SubtitleTranslating {
        func translate(_ sentence: String) async -> SessionTranslation {
            SessionTranslation(text: "TR: " + sentence, origin: .engine)
        }
    }

    /// Alana göre satır veren okuyucu (satırlar kare oranında verilir, alan içine çevrilir).
    struct AreaReader: GameReading.TextReader {
        let lines: @Sendable (GameReading.Box) -> [GameReading.Line]
        func read(_ frame: GameReading.Frame, area: GameReading.Box, scale: Double) async throws -> [GameReading.Line] {
            lines(area).map { l in GameReading.Line(l.text, confidence: 0.95, box: l.box?.local(in: area)) }
        }
    }

    final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(String, String)] = []
        func add(_ name: String, _ data: String) { lock.withLock { items.append((name, data)) } }
        func data(_ name: String) -> [String] { lock.withLock { items.filter { $0.0 == name }.map(\.1) } }
    }

    final class FakeTelemetryTransport: TelemetryTransport, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var bodies: [Data] = []
        func send(_ body: Data, gzip: Bool, to url: URL) async throws -> TelemetryResponse {
            lock.withLock { bodies.append(body) }
            return TelemetryResponse(status: 503)
        }
        var count: Int { lock.withLock { bodies.count } }
    }

    nonisolated static func box(_ l: Double, _ t: Double, _ r: Double, _ b: Double) -> GameReading.Box {
        GameReading.Box(left: l, top: t, right: r, bottom: b)
    }

    /// 1280 × 720 kare; istenirse ortada açık ekranlı, koyu çerçeveli bir telefon.
    nonisolated static func frame(phone: Bool) -> CGImage {
        let w = 1280, h = 720
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func fill(_ b: GameReading.Box, _ g: (Double, Double, Double)) {
            ctx.setFillColor(CGColor(red: g.0 / 255, green: g.1 / 255, blue: g.2 / 255, alpha: 1))
            ctx.fill(CGRect(x: b.left * Double(w), y: (1 - b.bottom) * Double(h), width: b.width * Double(w), height: b.height * Double(h)))
        }
        fill(.full, (120, 140, 170))
        if phone {
            fill(box(0.405, 0.15, 0.595, 0.83), (18, 18, 22))
            fill(box(0.42, 0.18, 0.58, 0.80), (238, 238, 240))
        }
        return ctx.makeImage()!
    }

    struct Rig {
        let engine: LiveEngine
        let state: AppState
        let root: URL
        let events: Events
        let reader: Task<Void, Never>
        let telemetry: FakeTelemetryTransport
    }

    /// Bellek kasası, geçici klasör ve ayar alanı, 0 portları; kaynak ve okuyucular sahte.
    func makeRig(frames: ScriptedFrameSource, main: AreaReader, phone: AreaReader,
                 extraAreas: [ExtraArea] = []) async throws -> Rig {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("nino-overlays-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "nino-overlays-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
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
        settings.extraAreas = extraAreas
        let store = SettingsStore(defaults: defaults)
        store.save(settings)
        var env = LiveEngineEnvironment(
            identity: AppIdentity(flavor: .testing, defaultsDomain: suite, keychainService: "test", folderName: "test"),
            folder: DataFolder(support: root.appendingPathComponent("support"), logs: root.appendingPathComponent("logs")),
            // Dinleyen TV'nin portu kapalı bir port (bağlanamaz, yeniden dener); izlenen yol 8787 SSE.
            settingsStore: store, vault: vault, ports: DisplayLinks.Ports(ingress: 0, legacy: 0, tv: 9, randomFallback: false),
            appVersion: "4.1.0",
            poolBaseURL: URL(string: "http://127.0.0.1:9"), packsBaseURL: nil, poolTransport: nil,
            providerTransport: URLSession.shared, deviceProvider: { nil }, textReader: main,
            clock: GameReading.SystemClock(), checksTranslatorReadiness: false)
        env.phoneTextReader = phone
        let telemetry = FakeTelemetryTransport()
        env.telemetryTransport = telemetry
        env.makeSource = { _, callbacks in
            callbacks.status(.ps5(.streaming))
            return SessionSource(frames: frames)
        }
        env.makeTranslator = { _ in EchoTranslator() }
        let state = AppState()
        let engine = LiveEngine(state: state, environment: env)
        try await engine.links.startServers()
        // Eski 8787 izleyicisi (SSE) kareler başlamadan bağlanır.
        let port = try XCTUnwrap(engine.links.legacyPort)
        let events = Events()
        let url = URL(string: "http://127.0.0.1:\(port)/events?model=Deneme")!
        let reader = Task {
            guard let (bytes, _) = try? await URLSession.shared.bytes(from: url) else { return }
            var event = ""
            do {
                for try await line in bytes.lines {
                    if line.hasPrefix("event: ") { event = String(line.dropFirst(7)) }
                    if line.hasPrefix("data: ") { events.add(event, String(line.dropFirst(6))) }
                }
            } catch {}
        }
        try await Task.sleep(for: .milliseconds(300))
        return Rig(engine: engine, state: state, root: root, events: events, reader: reader, telemetry: telemetry)
    }

    func finish(_ rig: Rig) async {
        rig.engine.stopTranslation()
        await rig.engine.lastStop?.value
        // Kapanış mesajları (screen-clear, stopped) izleyiciye ulaşsın.
        try? await wait(3) { !rig.events.data("stopped").isEmpty }
        await rig.engine.links.stop()
        rig.reader.cancel()
        try? FileManager.default.removeItem(at: rig.root)
    }

    func wait(_ seconds: Double, until done: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, !done() { try await Task.sleep(for: .milliseconds(100)) }
    }

    // MARK: Uçtan uca

    func testPhonePanelAndExtraAreaReachTV() async throws {
        let quest = ExtraArea(id: "quest", name: "Görev", region: ExtraArea.questPreset)
        let questBox = LiveEngine.box(quest.region)
        let main = AreaReader { area in
            area == questBox ? [GameReading.Line("Find the healer", box: Self.box(0.70, 0.08, 0.90, 0.11))] : []
        }
        // Telefonda okunan sohbet: başlık + mesaj.
        let phone = AreaReader { _ in
            [GameReading.Line("Brian", box: Self.box(0.48, 0.19, 0.52, 0.21)),
             GameReading.Line("Are you coming tonight?", box: Self.box(0.43, 0.40, 0.55, 0.42))]
        }
        let frames = ScriptedFrameSource(steps: [.init(Self.frame(phone: true), repeats: 400)], interval: .milliseconds(40))
        let rig = try await makeRig(frames: frames, main: main, phone: phone, extraAreas: [quest])
        rig.engine.startTranslation()
        await rig.engine.lastStart?.value
        XCTAssertEqual(rig.state.translation, .on)

        try await wait(15) {
            rig.events.data("screen").contains { $0.contains("TR: Are you coming tonight?") }
                && rig.events.data("region").contains { $0.contains("TR: Find the healer") }
                && !rig.state.extraAreaTexts.isEmpty
        }
        XCTAssertTrue(rig.events.data("screen").contains { $0.contains("TR: Are you coming tonight?") },
                      "screen: \(rig.events.data("screen"))")
        XCTAssertTrue(rig.events.data("region").contains { $0.contains("TR: Find the healer") && $0.contains("quest") },
                      "region: \(rig.events.data("region"))")
        XCTAssertEqual(rig.state.extraAreaTexts.first?.text, "TR: Find the healer")
        XCTAssertEqual(rig.state.extraAreaTexts.first?.alignment, .trailing)
        // Telefon hafızası veri klasöründe.
        let memory = rig.root.appendingPathComponent("support/phone-memory-tr.json")
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: memory)) as? [String: String]
        XCTAssertEqual(saved?["are you coming tonight"], "TR: Are you coming tonight?")
        // Telefon okunduğu için oyun ekrandan GTA 6 olarak tanındı.
        XCTAssertEqual(rig.state.game?.name, "GTA 6")
        XCTAssertEqual(rig.state.game?.evidence, .screen)

        await finish(rig)
        XCTAssertTrue(rig.state.extraAreaTexts.isEmpty)
        // Ölçüm: açılış ve oturum kuyrukta (sahte taşıyıcı; gerçek gönderim yok), kanal "dev".
        let queued = await rig.engine.meter?.telemetry.queued ?? []
        XCTAssertTrue(queued.contains { $0.kind == .launch })
        XCTAssertTrue(queued.contains { $0.kind == .session && $0.fields["src"] == .string("remoteplay") }, "\(queued)")
        let context = await rig.engine.meter?.telemetry.options.context
        XCTAssertEqual(context?.channel, "dev")
        XCTAssertEqual(context?.platform, "mac")
    }

    func testMapCardReachesTV() async throws {
        let menu = GameReading.Corners.menuSearchBox
        let main = AreaReader { area in
            guard area == menu else { return [] }
            return [
                GameReading.Line("Recenter", box: Self.box(0.05, 0.90, 0.12, 0.92)),
                GameReading.Line("Close Menu", box: Self.box(0.05, 0.94, 0.15, 0.96)),
                GameReading.Line("BUY FLOWERS", box: Self.box(0.70, 0.40, 0.80, 0.42)),
                GameReading.Line("Lucia will appreciate this", box: Self.box(0.70, 0.43, 0.83, 0.45)),
                GameReading.Line("Have some flowers delivered to the", box: Self.box(0.70, 0.455, 0.90, 0.475)),
                GameReading.Line("house for Lucia.", box: Self.box(0.70, 0.48, 0.78, 0.50)),
            ]
        }
        let frames = ScriptedFrameSource(steps: [.init(Self.frame(phone: false), repeats: 400)], interval: .milliseconds(40))
        let rig = try await makeRig(frames: frames, main: main, phone: AreaReader { _ in [] })
        rig.engine.startTranslation()
        await rig.engine.lastStart?.value
        try await wait(15) { rig.events.data("screen").contains { $0.contains("Lucia will appreciate this") } }
        let screens = rig.events.data("screen")
        XCTAssertTrue(screens.contains { $0.contains("TR: Lucia will appreciate this") }, "screen: \(screens)")
        // Harita ekranı GTA 6'ya özgü: oyun ekrandan tanınır.
        XCTAssertEqual(rig.state.game?.name, "GTA 6")
        await finish(rig)
        XCTAssertFalse(rig.events.data("stopped").isEmpty, "durunca TV'deki örtüler kalkar")
    }

    /// GTA 6 duraklatma menüsü (22 Kasım 17:38): sol üst köşe menünün sol sütununu okuyordu, menü araması o turda
    /// yoktu ve "Harita Oyun Mağaza Yardım" TV'ye köşe olarak gitti (TV mesajı 17:38:05). Menü öğeleri çevrilmez.
    func testPauseMenuCornerIsNotTranslated() async throws {
        let topLeft = GameReading.Corners.topLeftBox
        let main = AreaReader { area in
            guard area == topLeft else { return [] }
            return ["Map", "Game", "Store", "Help"].enumerated().map { i, t in
                GameReading.Line(t, box: Self.box(0.03, 0.21 + Double(i) * 0.066, 0.13, 0.245 + Double(i) * 0.066))
            }
        }
        let frames = ScriptedFrameSource(steps: [.init(Self.frame(phone: false), repeats: 200)], interval: .milliseconds(40))
        let rig = try await makeRig(frames: frames, main: main, phone: AreaReader { _ in [] })
        rig.engine.startTranslation()
        await rig.engine.lastStart?.value
        try await Task.sleep(for: .seconds(5))
        let screens = rig.events.data("screen")
        XCTAssertFalse(screens.contains { $0.contains("TR: Map") }, "screen: \(screens)")
        await finish(rig)
    }

    // MARK: Parçalar

    func testScreenItemFlags() {
        var style = GameReading.ScreenElement.Style.darkFrost
        style.angle = -7.25
        style.backdrop = true
        style.card = true
        style.plain = true
        style.italic = true
        let e = GameReading.ScreenElement(kind: .phone, id: "02", box: Self.box(0.1, 0.2, 0.3, 0.4), text: "Bir\nİki", style: style)
        let item = ScreenOverlays.item(e)
        XCTAssertEqual(item.fill, "#1c1c24")
        XCTAssertEqual(item.ink, "#f2f2f5")
        XCTAssertEqual(item.alpha, 0.62)
        XCTAssertEqual(item.frost, true)
        XCTAssertEqual(item.side, true)
        XCTAssertEqual(item.angle, -7.25)
        XCTAssertEqual(item.backdrop, true)
        XCTAssertEqual(item.card, true)
        XCTAssertEqual(item.plain, true)
        XCTAssertEqual(item.italic, true)
        XCTAssertEqual(item.paragraphs, true)
        XCTAssertEqual(item.line, 0.03)
        let plain = ScreenOverlays.item(GameReading.ScreenElement(kind: .hint, id: "h", box: Self.box(0, 0, 1, 1), text: "x"))
        XCTAssertNil(plain.fill)
        XCTAssertNil(plain.alpha)
        XCTAssertNil(plain.angle)
        XCTAssertNil(plain.side)
        let payload = ScreenOverlays.payload([e])
        XCTAssertEqual(payload.durationMs, 120_000)
        XCTAssertEqual(payload.overlay, true)
    }

    /// Görev şeridi (GTA 6, 22 Kasım: "Limanlara git" orijinalin üstüne dar ve yarı saydam biniyordu): öğe orijinal
    /// satırların kutusunda, `plain` değil (TV kutu genişliğinde, opak çizer); vurgu `⟦…⟧` olduğu gibi gider.
    func testQuestStripCoversOriginal() throws {
        let lines = [GameReading.Line("Go to the docks", box: Self.box(0.4454, 0.9339, 0.5547, 0.9561))]
        let e = try XCTUnwrap(ScreenOverlays.cornerElement(.questStrip, lines: lines, translation: "⟦Limanlara⟧ git"))
        XCTAssertEqual(e.box, Self.box(0.4454, 0.9339, 0.5547, 0.9561))
        let item = ScreenOverlays.item(e)
        XCTAssertNil(item.plain)
        XCTAssertNil(item.fill)
        XCTAssertEqual(item.text, "⟦Limanlara⟧ git")
    }

    func testLocalNetworkVerdict() {
        XCTAssertEqual(LocalNetworkProbe.verdict(Array(repeating: EHOSTUNREACH, count: 4), ps5Answered: false), .blocked)
        XCTAssertEqual(LocalNetworkProbe.verdict([EHOSTUNREACH, EPERM, EHOSTUNREACH, EPERM, EPERM], ps5Answered: false), .blocked)
        XCTAssertEqual(LocalNetworkProbe.verdict(Array(repeating: EHOSTUNREACH, count: 3), ps5Answered: false), .unknown,
                       "en az 4 adres")
        XCTAssertEqual(LocalNetworkProbe.verdict([EHOSTUNREACH, nil, EHOSTUNREACH, EHOSTUNREACH], ps5Answered: false), .allowed)
        XCTAssertEqual(LocalNetworkProbe.verdict(Array(repeating: EHOSTUNREACH, count: 4), ps5Answered: true), .allowed)
        XCTAssertEqual(LocalNetworkProbe.verdict([EHOSTUNREACH, ENETDOWN, EHOSTUNREACH, EHOSTUNREACH], ps5Answered: false),
                       .unknown, "başka hata işaret değil")
        let a: UInt32 = 0xC0A8_0005 // 192.168.0.5
        let c = LocalNetworkProbe.candidates(address: a, mask: 0xFFFF_FF00, limit: 6)
        XCTAssertEqual(c.count, 6)
        XCTAssertFalse(c.contains(a))
        XCTAssertEqual(c.first, 0xC0A8_0001)
        XCTAssertTrue(LocalNetworkProbe.candidates(address: a, mask: 0xFFFF_FFFF).isEmpty)
    }

    func testIdentifySchedule() {
        var s = IdentifySchedule()
        let t0 = Date()
        XCTAssertFalse(s.isDue(.unknown, now: t0), "başlamadan yok")
        s.start(at: t0)
        XCTAssertFalse(s.isDue(.unknown, now: t0.addingTimeInterval(7)))
        XCTAssertTrue(s.isDue(.unknown, now: t0.addingTimeInterval(8)))
        var t = t0.addingTimeInterval(8)
        for _ in 0..<6 {
            XCTAssertTrue(s.isDue(.unknown, now: t))
            s.markAttempt(.unknown, at: t)
            XCTAssertFalse(s.isDue(.unknown, now: t.addingTimeInterval(59)))
            t = t.addingTimeInterval(60)
        }
        XCTAssertFalse(s.isDue(.unknown, now: t.addingTimeInterval(600)), "en çok 6")
        XCTAssertFalse(s.isDue(.none, now: t))
        s.noteScreenRecognized(at: t)
        XCTAssertFalse(s.isDue(.screen, now: t.addingTimeInterval(299)))
        XCTAssertTrue(s.isDue(.screen, now: t.addingTimeInterval(300)))
        s.markAttempt(.screen, at: t.addingTimeInterval(300))
        XCTAssertFalse(s.isDue(.screen, now: t.addingTimeInterval(1_400)))
        XCTAssertTrue(s.isDue(.screen, now: t.addingTimeInterval(1_500)))
    }

    struct FakeNetwork: NetworkClient {
        let reply: Data
        let seen: Events
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            seen.add(request.url?.path ?? "", String(decoding: request.httpBody ?? Data(), as: UTF8.self))
            return (reply, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    func testIdentifyClient() async throws {
        let seen = Events()
        let client = GameIdentifyClient(network: FakeNetwork(reply: Data(#"{"game":"Ghost of Yōtei"}"#.utf8), seen: seen),
                                        baseURL: URL(string: "http://127.0.0.1:9/")!, appVersion: "4.1.0",
                                        install: "8d0f5c9e-3b1a-4c2d-9e8f-7a6b5c4d3e2f")
        let big = Self.frame(phone: true)
        let jpeg = try XCTUnwrap(GameIdentifyClient.jpeg(big))
        XCTAssertLessThanOrEqual(jpeg.count, GameIdentifyClient.maxBytes)
        let image = try XCTUnwrap(NSBitmapImageRep(data: jpeg))
        XCTAssertEqual(image.pixelsWide, 768)
        let name = await client.identify(big)
        XCTAssertEqual(name, "Ghost of Yōtei")
        let body = try XCTUnwrap(seen.data("/v1/identify").first)
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(o["v"] as? Int, 1)
        XCTAssertEqual(o["platform"] as? String, "mac")
        XCTAssertEqual(o["app"] as? String, "4.1.0")
        XCTAssertNotNil(o["image"] as? String)
        XCTAssertNil(GameIdentifyClient.game(from: Data(#"{}"#.utf8)))
    }

    func testConsoleTitleID() {
        XCTAssertTrue(GameTracker.isGameTitleID("PPSA01234"))
        XCTAssertTrue(GameTracker.isGameTitleID("CUSA00419_00"))
        XCTAssertFalse(GameTracker.isGameTitleID("npxs40008"))
        XCTAssertFalse(GameTracker.isGameTitleID("HOME"))
        var g = GameTracker()
        g.startSession(at: Date())
        XCTAssertTrue(g.consoleReported(name: "Grand Theft Auto VI", titleID: "PPSA01234"))
        XCTAssertEqual(g.console?.titleID, "PPSA01234")
        XCTAssertEqual(g.evidence, .console)
        // Ana ekran: kimlik oyun biçiminde değil → oyun yok.
        XCTAssertTrue(g.consoleReported(name: "Home", titleID: "home-screen"))
        XCTAssertNil(g.console)
    }

    struct FailingReader: GameReading.TextReader {
        let fail: Bool
        struct Boom: Error {}
        func read(_ frame: GameReading.Frame, area: GameReading.Box, scale: Double) async throws -> [GameReading.Line] {
            if fail { throw Boom() }
            return []
        }
    }

    final class Flags: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [Bool] = []
        func add(_ b: Bool) { lock.withLock { list.append(b) } }
        var all: [Bool] { lock.withLock { list } }
    }

    func testReadingWatch() async {
        let flags = Flags()
        let frame = GameReading.ImageFrame(Self.frame(phone: false))
        let bad = ReadingWatch(base: FailingReader(fail: true), threshold: 3) { flags.add($0) }
        for _ in 0..<5 { _ = try? await bad.read(frame, area: .full, scale: 1) }
        XCTAssertEqual(flags.all, [true], "3 hatada bir kez açılır")
        XCTAssertTrue(bad.isFailing)
        let good = ReadingWatch(base: FailingReader(fail: false), threshold: 3) { flags.add($0) }
        _ = try? await good.read(frame, area: .full, scale: 1)
        XCTAssertEqual(flags.all, [true])
        XCTAssertNotNil(ReadingWatch.freeDiskGB())
    }

    struct WarmingReader: GameReading.TextReader {
        func read(_ frame: GameReading.Frame, area: GameReading.Box, scale: Double) async throws -> [GameReading.Line] {
            throw HelperOCRReader.HelperError.notWarm
        }
    }

    /// Yedek OCR ısınırken verdiği hata "macOS yazıyı okuyamıyor" uyarısına sayılmaz.
    func testHelperWarmUpIsNotReadingFailure() async {
        let flags = Flags()
        let frame = GameReading.ImageFrame(Self.frame(phone: false))
        let w = ReadingWatch(base: WarmingReader(), threshold: 2) { flags.add($0) }
        for _ in 0..<6 { _ = try? await w.read(frame, area: .full, scale: 1) }
        XCTAssertTrue(flags.all.isEmpty)
        XCTAssertFalse(w.isFailing)
    }

    final class RecordingDisplay: DisplayOutput, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var events: [NinoEvent] = []
        func show(_ payload: ShowPayload) async throws {}
        func clear(id: Int?) async throws {}
        func send(_ event: NinoEvent) async throws { lock.withLock { events.append(event) } }
        var screens: Int { lock.withLock { events.filter { if case .screen = $0 { return true }; return false }.count } }
    }

    /// Ekranı çevir sürerken katman TV'ye gitmez; bitince yeniden gönderilir.
    func testSuspendedDuringScreenTranslation() async throws {
        let clock = GameReading.ManualClock()
        let tr = OverlayTranslator(translator: EchoTranslator())
        let reader = GameReading.Reader(textReader: WarmingReader(), clock: clock)
        let out = RecordingDisplay()
        let o = ScreenOverlays(reader: reader, textReader: WarmingReader(), phone: nil, translator: tr, output: out, clock: clock)
        await o.setSuspended(true)
        let call = try XCTUnwrap(GameReading.Cards.call([
            GameReading.Line("Harbor Cabs", box: Self.box(0.6, 0.80, 0.8, 0.83)),
            GameReading.Line("Calling", box: Self.box(0.6, 0.84, 0.7, 0.87)),
        ]))
        await o.frame(Self.frame(phone: false), events: [.callCard(call)], skipped: false)
        let hidden = await o.elements
        XCTAssertEqual(hidden.count, 1)
        XCTAssertEqual(out.screens, 0, "ekranı çevir sürerken gönderilmez")
        await o.setSuspended(false)
        XCTAssertEqual(out.screens, 1, "bitince katman yeniden gönderilir")
    }

    func testDropCodes() {
        XCTAssertEqual(SessionMeter.dropCode(.asleep), "standby")
        XCTAssertEqual(SessionMeter.dropCode(.inUseElsewhere), "kicked")
        XCTAssertEqual(SessionMeter.dropCode(.network), "network_lost")
        XCTAssertEqual(SessionMeter.connectCode(.notFound(address: "192.168.0.20")), "ps5.discover.none")
        XCTAssertEqual(SessionMeter.connectCode(.other(detail: "x")), "ps5.other")
        XCTAssertEqual(LiveEngine.telemetryChannel(.development, version: "4.1.0"), "dev")
        XCTAssertEqual(LiveEngine.telemetryChannel(AppIdentity(flavor: .release, defaultsDomain: "x", keychainService: "x",
                                                               folderName: "x"), version: "4.1.0-beta.2"), "beta")
    }

    /// PS5 bağlandı → koptu: `ps5_connect` (ok) ve `ps5_drop` (kod), metin ya da adres yok.
    func testMeterPS5Events() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nino-tel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let t = Telemetry(options: .init(endpoint: URL(string: "http://127.0.0.1:9/v1/events")!, installID: UUID().uuidString,
                                         context: .current(app: "4.1.0", channel: "dev"), directory: dir, enabled: true),
                          transport: FakeTelemetryTransport())
        let m = SessionMeter(telemetry: t)
        let start = Date()
        m.sessionStarted(at: start)
        m.ps5Status(.connecting, before: nil, at: start)
        m.ps5Status(.streaming, before: .connecting, at: start.addingTimeInterval(2))
        m.ps5Status(.dropped(.notFound(address: "192.168.0.20")), before: .streaming, at: start.addingTimeInterval(62))
        m.lineShown(LiveLine(translated: "a", source: "b", origin: .engine, latencyMs: 420))
        m.sessionEnded(game: "gta-6", source: .remoteplay, at: start.addingTimeInterval(100))
        try await Task.sleep(for: .milliseconds(200))
        let q = await t.queued
        let connect = try XCTUnwrap(q.first { $0.kind == .ps5Connect })
        XCTAssertEqual(connect.fields["r"], .string("ok"))
        XCTAssertEqual(connect.fields["ms"], .int(2_000))
        let drop = try XCTUnwrap(q.first { $0.kind == .ps5Drop })
        XCTAssertEqual(drop.fields["code"], .string("timeout"))
        XCTAssertEqual(drop.fields["after"], .int(60))
        let session = try XCTUnwrap(q.first { $0.kind == .session })
        XCTAssertEqual(session.fields["lines"], .int(1))
        XCTAssertEqual(session.fields["game"], .string("gta-6"))
        let json = String(decoding: try JSONEncoder().encode(q), as: UTF8.self)
        XCTAssertFalse(json.contains("192.168"), "adres gitmez")
    }

    /// Anahtar önce denenir: geçersiz anahtar kaydedilmez, geçerli kaydedilir ve motor seçilir.
    func testKeyIsCheckedBeforeSaving() async throws {
        let suite = "nino-key-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nino-key-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var env = LiveEngineEnvironment(
            identity: AppIdentity(flavor: .testing, defaultsDomain: suite, keychainService: "test", folderName: "test"),
            folder: DataFolder(support: root, logs: root), settingsStore: SettingsStore(defaults: defaults), vault: MemoryVault(),
            ports: .ephemeral, appVersion: "4.1.0", poolBaseURL: nil, packsBaseURL: nil, poolTransport: nil,
            providerTransport: URLSession.shared, deviceProvider: { nil }, textReader: FailingReader(fail: false),
            clock: GameReading.SystemClock(), checksTranslatorReadiness: false)
        env.keyCheck = { _, key in key == "good" ? (.valid, "BATMAN: Ben Batman'im.") : (.invalidKey, nil) }
        let state = AppState()
        let engine = LiveEngine(state: state, environment: env)
        engine.saveGeminiKey("bad")
        XCTAssertEqual(state.setup.geminiTest, .testing)
        try await wait(5) { state.setup.geminiTest != .testing }
        XCTAssertFalse(state.setup.geminiKeySaved)
        XCTAssertFalse(state.settingsStatus.savedKeys.contains(.gemini))
        guard case .failed = state.setup.geminiTest else { return XCTFail("\(state.setup.geminiTest)") }
        engine.saveGeminiKey("  good ")
        try await wait(5) { state.setup.geminiKeySaved }
        XCTAssertTrue(state.settingsStatus.savedKeys.contains(.gemini))
        XCTAssertEqual(state.setup.geminiSample, "BATMAN: Ben Batman'im.")
        XCTAssertEqual(state.settingsStatus.engineTests[.gemini], .works(sample: "BATMAN: Ben Batman'im."))
        XCTAssertEqual(state.settings.onlineEngine, .gemini)
        XCTAssertTrue(state.settings.onlineTranslation)
        XCTAssertEqual(try engine.records.translationKey(.gemini), "good")
    }
}
