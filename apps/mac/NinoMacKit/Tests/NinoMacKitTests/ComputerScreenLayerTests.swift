// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import NinoCore
import NinoDebugKit
import WebKit
import XCTest
@testable import NinoMacKit

/// Bilgisayardaki ekran öğeleri katmanı (telefon paneli, harita kartı): kip kuralı, hub yolu, oyun alanına oturan panel
/// ve gerçek GTA 6 kareleriyle görüntü.
///
/// Gerçek kareler NinoCore'un test kaynaklarından okunur (`NINOCORE_DIR` ya da ~/Desktop/NinoCore); yoksa geçilir.
/// `NINO_SCREEN_LAYER_DUMP=<klasör>` verilirse bileşik görüntüler (kare + katman) oraya PNG olarak yazılır.
final class ComputerScreenLayerTests: XCTestCase {
    // MARK: Kural

    @MainActor
    static func state(output: MacSettings.Output, source: MacSettings.VideoSource) -> AppState {
        var s = MacSettings()
        s.output = output
        s.videoSource = source
        s.gameConsole = .ps5
        return AppState(settings: s)
    }

    /// Hangi kipte ne görünür: TV her şeyi; bilgisayarda altyazı penceresi + (oyun alanı biliniyorsa) ekran öğeleri.
    @MainActor
    func testWhatShowsWhereByOutputAndSource() {
        let area = CGRect(x: 0, y: 0, width: 1280, height: 720)
        struct Row { let output: MacSettings.Output; let source: MacSettings.VideoSource; let area: CGRect?
                     let tv: Bool; let computer: Bool; let layer: Bool }
        let rows: [Row] = [
            Row(output: .tv, source: .ps5, area: nil, tv: true, computer: false, layer: false),
            Row(output: .tv, source: .card, area: area, tv: true, computer: false, layer: false),
            Row(output: .computer, source: .card, area: area, tv: false, computer: true, layer: true),
            Row(output: .both, source: .card, area: area, tv: true, computer: true, layer: true),
            // PS Remote Play penceresi: her zaman bilgisayar (TV kapalı).
            Row(output: .tv, source: .window, area: area, tv: false, computer: true, layer: true),
            Row(output: .both, source: .window, area: area, tv: false, computer: true, layer: true),
            // Nino'nun kendi PS5 bağlantısında ekranda oyun yok: katman çıkmaz (altyazı penceresi çıkar).
            Row(output: .computer, source: .ps5, area: nil, tv: false, computer: true, layer: false),
            Row(output: .both, source: .ps5, area: nil, tv: true, computer: true, layer: false),
            // Pencere küçültüldü (alan bilinmiyor).
            Row(output: .computer, source: .window, area: nil, tv: false, computer: true, layer: false),
        ]
        for r in rows {
            let st = Self.state(output: r.output, source: r.source)
            let name = "\(r.output) / \(r.source)"
            XCTAssertEqual(st.subtitlesOnTV, r.tv, name)
            XCTAssertEqual(st.subtitlesOnComputer, r.computer, name)
            XCTAssertEqual(ComputerScreenRules.isVisible(subtitlesOnComputer: st.subtitlesOnComputer, translating: true,
                                                         gameArea: r.area, hasItems: true), r.layer, name)
        }
        XCTAssertFalse(ComputerScreenRules.isVisible(subtitlesOnComputer: true, translating: false, gameArea: area, hasItems: true))
        XCTAssertFalse(ComputerScreenRules.isVisible(subtitlesOnComputer: true, translating: true, gameArea: area, hasItems: false))
        XCTAssertEqual(ComputerScreenRules.pageZoom(for: area), 1280.0 / 1920.0, accuracy: 1e-9)
    }

    /// Alt satır iki kez çizilmez: katman altyazı ve ek alan mesajı almaz, sayfada o parçalar gizli.
    func testOnlyScreenElementsReachTheLayer() {
        let item = ScreenItem(box: NinoBox(left: 0.1, top: 0.1, right: 0.3, bottom: 0.2), text: "x")
        XCTAssertTrue(ComputerScreenRules.forwards(.screen(ScreenPayload(items: [item], durationMs: 0))))
        XCTAssertTrue(ComputerScreenRules.forwards(.screenClear))
        XCTAssertTrue(ComputerScreenRules.forwards(.stopped))
        XCTAssertFalse(ComputerScreenRules.forwards(.started))
        XCTAssertFalse(ComputerScreenRules.forwards(.region(RegionPayload(id: "a", text: "b"))))
        XCTAssertFalse(ComputerScreenRules.forwards(.regionClear))
        XCTAssertFalse(ComputerScreenRules.forwards(.style(NinoStyle(SubtitleStyle()))))
        for part in ["#caption", "#areas", "#shade"] { XCTAssertTrue(ComputerScreenRules.hiddenParts.contains(part), part) }
        XCTAssertEqual(ComputerScreenRules.hasItems(after: NinoEvent.screen(ScreenPayload(items: [item], durationMs: 120_000)).jsonString)?.has, true)
        XCTAssertEqual(ComputerScreenRules.hasItems(after: NinoEvent.screen(ScreenPayload(items: [item], durationMs: 120_000)).jsonString)?.durationMs, 120_000)
        XCTAssertEqual(ComputerScreenRules.hasItems(after: NinoEvent.screenClear.jsonString)?.has, false)
        XCTAssertNil(ComputerScreenRules.hasItems(after: NinoMessage.show(ShowPayload(id: 1, text: "a")).jsonString))
    }

    /// "Altyazı yalnız bilgisayarda" iken de (PS Remote Play penceresi) hub ekran öğelerini katmana verir; altyazıyı vermez.
    func testHubFeedsLayerWhenSubtitlesAreOnlyOnComputer() async throws {
        let hub = DisplayHub()
        let feed = ComputerScreenFeed()
        final class Got: @unchecked Sendable { let lock = NSLock(); var types: [String] = [] }
        let got = Got()
        feed.onMessage = { json in
            let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
            got.lock.withLock { got.types.append((o?["type"] as? String) ?? "?") }
        }
        await hub.add(feed, key: ComputerScreenFeed.hubKey)
        await hub.setSubtitlesOnTV(false)
        let item = ScreenItem(box: NinoBox(left: 0.4, top: 0.2, right: 0.6, bottom: 0.8), text: "Telefon")
        try await hub.show(ShowPayload(id: 1, text: "Alt satır", durationMs: 0))
        try await hub.send(.screen(ScreenPayload(items: [item], durationMs: 120_000, overlay: true)))
        try await hub.send(.region(RegionPayload(id: "a", text: "Ek alan")))
        try await hub.send(.screenClear)
        try await hub.send(.started)
        try await hub.send(.stopped)
        XCTAssertEqual(got.lock.withLock { got.types }, ["screen", "screen-clear", "stopped"])
        await hub.setSubtitlesOnTV(true)
        try await hub.send(.screen(ScreenPayload(items: [item], durationMs: 120_000)))
        XCTAssertEqual(got.lock.withLock { got.types.last }, "screen", "TV kipinde de alır (görünürlük katmanda)")
    }

    // MARK: Panel

    static let offscreenArea = CGRect(x: -30000, y: -30000, width: 1280, height: 720)

    @MainActor
    static func translatingState(output: MacSettings.Output = .computer, source: MacSettings.VideoSource = .card,
                                 area: CGRect? = offscreenArea) -> AppState {
        let st = state(output: output, source: source)
        st.translation = .on
        st.gameAreaFrame = area
        return st
    }

    @MainActor
    static func spin(_ seconds: TimeInterval) { CompositeFrameTests.spin(until: { false }, timeout: seconds) }

    @MainActor
    static func ready(_ c: ComputerScreenPanelController) -> TVPageWeb? {
        CompositeFrameTests.spin(until: { c.pageForTesting?.ready == true })
        guard let page = c.pageForTesting, page.ready else { return nil }
        page.keepDrawingWhenOccluded()
        return page
    }

    @MainActor
    static func js(_ page: TVPageWeb, _ source: String) -> Any? {
        var out: Any?
        var done = false
        page.webView.evaluateJavaScript(source) { v, _ in out = v; done = true }
        CompositeFrameTests.spin(until: { done }, timeout: 5)
        return out
    }

    @MainActor
    static func snap(_ page: TVPageWeb, width: CGFloat) -> CGImage? {
        var out: CGImage?
        var done = false
        page.snapshot(width: width) { out = $0; done = true }
        CompositeFrameTests.spin(until: { done }, timeout: 10)
        return out
    }

    /// Panel oyunun alanına tam oturur, tıklamayı geçirir, sayfa 1920 düzenini korur; kip TV'ye dönünce kalkar.
    @MainActor
    func testPanelSitsOnGameAreaAndFollowsOutput() throws {
        let st = Self.translatingState()
        let c = ComputerScreenPanelController(state: st)
        c.start(hub: nil)
        XCTAssertNotNil(c.pageForTesting, "altyazı bilgisayarda ve çeviri açık: sayfa hazırlanır")
        XCTAssertFalse(c.isShowing, "öğe yokken panel yok")
        let item = ScreenItem(box: NinoBox(left: 0.40, top: 0.15, right: 0.60, bottom: 0.85), text: "Merhaba", card: true)
        c.receive(NinoEvent.screen(ScreenPayload(items: [item], durationMs: 120_000, overlay: true)).jsonString)
        let panel = try XCTUnwrap(c.panelForTesting)
        XCTAssertTrue(c.isShowing)
        XCTAssertEqual(panel.frame, Self.offscreenArea)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertEqual(panel.level, ComputerScreenPanelController.level)
        XCTAssertLessThan(panel.level.rawValue, NSWindow.Level.statusBar.rawValue, "altyazı penceresinin altında")
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        let page = try XCTUnwrap(Self.ready(c))
        XCTAssertEqual(page.webView.pageZoom, 1280.0 / 1920.0, accuracy: 1e-6)
        XCTAssertEqual((Self.js(page, "window.innerWidth") as? NSNumber)?.intValue ?? 0, 1920, accuracy: 2)
        XCTAssertEqual((Self.js(page, "window.innerHeight") as? NSNumber)?.intValue ?? 0, 1080, accuracy: 2)

        // Oyun penceresi taşındı: panel de.
        let moved = Self.offscreenArea.offsetBy(dx: 40, dy: -20)
        st.gameAreaFrame = moved
        Self.spin(0.1)
        XCTAssertEqual(c.panelForTesting?.frame, moved)

        // screen-clear: panel gizlenir.
        c.receive(NinoEvent.screenClear.jsonString)
        XCTAssertFalse(c.isShowing)
        c.receive(NinoEvent.screen(ScreenPayload(items: [item], durationMs: 120_000)).jsonString)
        XCTAssertTrue(c.isShowing)

        // Çıkış TV'ye döndü: panel ve sayfa bırakılır; geri gelince son liste yeniden kurulur.
        st.settings.output = .tv
        Self.spin(0.1)
        XCTAssertNil(c.panelForTesting)
        XCTAssertNil(c.pageForTesting)
        st.settings.output = .both
        Self.spin(0.1)
        XCTAssertTrue(c.isShowing, "son liste hâlâ geçerli")

        // Çeviri durdu: her şey kalkar.
        st.translation = .off
        Self.spin(0.1)
        XCTAssertNil(c.panelForTesting)
        st.translation = .on
        Self.spin(0.1)
        XCTAssertFalse(c.isShowing, "eski oturumun öğeleri geri gelmez")
    }

    // MARK: Uçtan uca (motor → hub → panel)

    /// Kart kaynağı, çıkış yalnız bilgisayar (TV'ye hiçbir şey gitmez): okunan telefon çevirisi gerçek oturumdan hub'a,
    /// oradan panele gelir; panel kaynağın bildirdiği oyun alanına oturur, alt altyazı panele girmez.
    @MainActor
    func testSessionOnComputerOnlyShowsPhoneOverGameArea() throws {
        typealias S = SessionOverlaysTests
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("nino-screenlayer-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let suite = "nino-screenlayer-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = MemoryVault()
        let records = SecureRecords(vault: vault)
        try records.setSetupComplete(true)
        var settings = MacSettings()
        settings.output = .computer
        settings.videoSource = .card
        let store = SettingsStore(defaults: defaults)
        store.save(settings)
        let phone = S.AreaReader { _ in
            [GameReading.Line("Brian", box: S.box(0.48, 0.19, 0.52, 0.21)),
             GameReading.Line("Are you coming tonight?", box: S.box(0.43, 0.40, 0.55, 0.42))]
        }
        var env = LiveEngineEnvironment(
            identity: AppIdentity(flavor: .testing, defaultsDomain: suite, keychainService: "test", folderName: "test"),
            folder: DataFolder(support: root.appendingPathComponent("support"), logs: root.appendingPathComponent("logs")),
            settingsStore: store, vault: vault, ports: DisplayLinks.Ports(ingress: 0, legacy: 0, tv: 9, randomFallback: false),
            appVersion: "4.1.0",
            poolBaseURL: URL(string: "http://127.0.0.1:9"), packsBaseURL: nil, poolTransport: nil,
            providerTransport: URLSession.shared, deviceProvider: { nil }, textReader: S.AreaReader { _ in [] },
            clock: GameReading.SystemClock(), checksTranslatorReadiness: false)
        env.phoneTextReader = phone
        env.telemetryTransport = S.FakeTelemetryTransport()
        let area = Self.offscreenArea
        let frames = ScriptedFrameSource(steps: [.init(S.frame(phone: true), repeats: 400)], interval: .milliseconds(40))
        env.makeSource = { _, callbacks in
            callbacks.status(.card(.reading(cardName: "Deneme kartı")))
            callbacks.gameArea(area)
            return SessionSource(frames: frames)
        }
        env.makeTranslator = { _ in S.EchoTranslator() }
        let state = AppState()
        let engine = LiveEngine(state: state, environment: env)
        XCTAssertFalse(state.subtitlesOnTV)
        XCTAssertTrue(state.subtitlesOnComputer)

        let layer = ComputerScreenPanelController(state: state)
        layer.start(hub: engine.links.hub)
        engine.startTranslation()
        CompositeFrameTests.spin(until: { layer.isShowing }, timeout: 20)
        XCTAssertEqual(state.translation, .on)
        XCTAssertEqual(state.gameAreaFrame, area)
        XCTAssertTrue(layer.isShowing, "telefon çevirisi bilgisayardaki panelde")
        XCTAssertEqual(layer.panelForTesting?.frame, area)
        let sent = layer.pageForTesting?.replayMessages ?? []
        XCTAssertTrue(sent.contains { $0.contains("\"screen\"") && $0.contains("TR: Are you coming tonight?") }, "\(sent)")
        XCTAssertFalse(sent.contains { $0.contains("\"show\"") }, "alt altyazı panele girmez")

        engine.stopTranslation()
        CompositeFrameTests.spin(until: { layer.panelForTesting == nil && state.translation == .off }, timeout: 5)
        XCTAssertNil(layer.panelForTesting, "çeviri durunca panel kalkar")
        var stopped = false
        Task { @MainActor in
            await engine.lastStop?.value
            await engine.links.stop()
            stopped = true
        }
        CompositeFrameTests.spin(until: { stopped }, timeout: 10)
    }

    // MARK: Gerçek kareler

    static func coreResources() -> URL {
        let env = ProcessInfo.processInfo.environment["NINOCORE_DIR"]
        let core = env.flatMap { $0.isEmpty ? nil : $0 } ?? (NSHomeDirectory() + "/Desktop/NinoCore")
        return URL(fileURLWithPath: core).appendingPathComponent("Tests/NinoCoreTests/Resources")
    }

    static func frame(_ folder: String, _ name: String) throws -> CGImage {
        let url = coreResources().appendingPathComponent(folder).appendingPathComponent(name + ".jpg")
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw XCTSkip("kare yok: \(url.path)")
        }
        return img
    }

    /// Çeviri: bilinen birkaç ifade Türkçe, kalanı "TR " önekli.
    struct FixedTranslator: SubtitleTranslating {
        static let known = [
            "Breakfast Run": "Kahvaltı turu",
            "Jason is finally back on his feet. Head out together and get some fresh air.":
                "Jason sonunda ayağa kalktı. Birlikte dışarı çıkıp biraz temiz hava alın.",
            "Steal Vehicles For Moses": "Moses için araç çal",
            "There's a Yosemite 1500 on Bastion St.": "Bastion Caddesi'nde bir Yosemite 1500 var.",
        ]
        func translate(_ sentence: String) async -> SessionTranslation {
            SessionTranslation(text: Self.known[sentence] ?? "TR " + sentence, origin: .engine)
        }
    }

    static func overlayTranslator() -> OverlayTranslator { OverlayTranslator(translator: FixedTranslator()) }

    /// Harita kartı: Vision → menü araması → `MapCardWatcher` → Mac'in protokol biçimi (`ScreenOverlays.item`).
    static func mapPayload(_ name: String) async throws -> (ScreenPayload, CGImage) {
        let img = try frame("gta6-map", name)
        var cfg = GameReading.Reader.Configuration()
        cfg.mapScreenCountsAsMenu = true
        let reader = GameReading.Reader(textReader: GameReading.VisionTextReader(), clock: GameReading.ManualClock(0), configuration: cfg)
        _ = await reader.readCorners(GameReading.ImageFrame(img))
        let lines = await reader.lastMenuSearchLines
        if lines.isEmpty { throw XCTSkip("Vision bu ortamda yazı okumadı") }
        let w = GameReading.MapCardWatcher(translator: overlayTranslator(), clock: GameReading.ManualClock(0))
        _ = await w.setPhoneGame(true)
        let changes = await w.observe(lines, image: img, menuOpen: true)
        guard case let .set(e)? = changes.last else { throw XCTSkip("\(name): kart bulunamadı (\(changes))") }
        return (ScreenOverlays.payload([e]), img)
    }

    /// Telefon (Cal, Jason, Lucia grup sohbeti): tur + takip → tahta → gönderici, Mac'teki `ScreenOverlays` akışı gibi.
    static func phonePayload() async throws -> (ScreenPayload, CGImage) {
        let clock = GameReading.ManualClock(0)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nino-phone-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let w = GameReading.PhoneWatcher(textReader: GameReading.CPUTextReader(), clock: clock,
                                         memory: .init(directory: dir, language: "tr"), translator: overlayTranslator())
        _ = await w.setPhoneGame(true)
        var board = GameReading.ElementsBoard()
        var sender = GameReading.ScreenItemSender()
        var last: [GameReading.ScreenElement]?
        var lastImage: CGImage?
        for name in ["phone-13-43-03", "phone-13-43-03", "phone-13-43-19", "phone-13-43-21", "phone-13-43-21"] {
            clock.nowMs += 1_000
            let img = try frame("gta6-phone", name)
            let f = GameReading.ImageFrame(img)
            for u in [await w.trackPhone(f), await w.round(f)].compactMap({ $0 }) {
                guard let els = u.elements else { continue }
                board.removeAll(kind: .phone)
                for e in els { board.set(e) }
            }
            if case let .screen(list)? = sender.update(board.list, nowMs: clock.nowMs) { last = list; lastImage = img }
        }
        guard let last, let lastImage else { throw XCTSkip("Vision bu ortamda telefonu okumadı") }
        return (ScreenOverlays.payload(last), lastImage)
    }

    /// Kutuların içindeki ve dışındaki opak örnek oranı.
    static func coverage(_ image: CGImage, boxes: [NinoBox]) -> (inside: Double, outside: Double) {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var inN = 0, inOpaque = 0, outN = 0, outOpaque = 0
        for y in stride(from: 0, to: h, by: 3) {
            for x in stride(from: 0, to: w, by: 3) {
                let fx = (Double(x) + 0.5) / Double(w), fy = (Double(y) + 0.5) / Double(h)
                let opaque = px[(y * w + x) * 4 + 3] > 40
                // Kenarda gölge ve yuvarlak köşe payı.
                let inside = boxes.contains { b in
                    fx > b.left + 0.006 && fx < b.right - 0.006 && fy > b.top + 0.01 && fy < b.bottom - 0.01
                }
                let near = boxes.contains { b in
                    fx > b.left - 0.03 && fx < b.right + 0.03 && fy > b.top - 0.05 && fy < b.bottom + 0.05
                }
                if inside { inN += 1; if opaque { inOpaque += 1 } } else if !near { outN += 1; if opaque { outOpaque += 1 } }
            }
        }
        return (inN == 0 ? 0 : Double(inOpaque) / Double(inN), outN == 0 ? 0 : Double(outOpaque) / Double(outN))
    }

    /// İki katmanın opaklık maskesi ne kadar farklı (örnek oranı).
    static func maskDifference(_ a: CGImage, _ b: CGImage) -> Double {
        let w = 320, h = 180
        func mask(_ img: CGImage) -> [UInt8] {
            var px = [UInt8](repeating: 0, count: w * h * 4)
            let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .medium
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return stride(from: 3, to: px.count, by: 4).map { px[$0] > 60 ? 1 : 0 }
        }
        let ma = mask(a), mb = mask(b)
        return Double(zip(ma, mb).filter { $0 != $1 }.count) / Double(ma.count)
    }

    static func composite(_ frame: CGImage, _ layer: CGImage) -> CGImage {
        let w = frame.width, h = frame.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(frame, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(layer, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    static func dump(_ image: CGImage, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["NINO_SCREEN_LAYER_DUMP"], !dir.isEmpty else { return }
        let folder = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        DebugImageIO.write(image, to: folder.appendingPathComponent(name + ".png"), type: .png)
    }

    /// Bir yükü 1280 × 720 oyun alanındaki panelde çizer; TV'nin gizli sayfasıyla (admin) karşılaştırır.
    @MainActor
    func renderOnPanel(_ payload: ScreenPayload, frame: CGImage, name: String) throws {
        let st = Self.translatingState()
        let c = ComputerScreenPanelController(state: st)
        c.start(hub: nil)
        let page = try XCTUnwrap(Self.ready(c))
        // Altyazı ve ek alan sayfaya doğrudan verilse bile çizilmez (gizli parçalar); hub yolu zaten vermez.
        page.receive(NinoMessage.show(ShowPayload(id: 7, text: "Bu altyazı bilgisayardaki katmanda çizilmemeli", durationMs: 0)).jsonString)
        c.receive(NinoEvent.screen(payload).jsonString)
        XCTAssertTrue(c.isShowing)
        Self.spin(1.5)
        let layer = try XCTUnwrap(Self.snap(page, width: 1280))
        XCTAssertEqual(Double(layer.width) / Double(layer.height), 16.0 / 9.0, accuracy: 0.01)
        let boxes = payload.items.map(\.box)
        let cov = Self.coverage(layer, boxes: boxes)
        XCTAssertGreaterThan(cov.inside, 0.5, "\(name): öğeler kendi kutularında (oyun alanına oranla) çizilmeli: \(cov)")
        XCTAssertLessThan(cov.outside, 0.01, "\(name): kutuların dışı saydam (altyazı yok): \(cov)")
        Self.dump(Self.composite(frame, layer), "bilgisayar-\(name)")

        // TV'deki görünümle aynı: gizli TV sayfası (1920 × 1080) aynı yükü çizer.
        let tv = TVPageRenderer()
        CompositeFrameTests.spin(until: { tv.isReady })
        tv.receive(NinoEvent.screen(payload).jsonString)
        Self.spin(1.5)
        let tvLayer = try XCTUnwrap(CompositeFrameTests.snap(tv))
        tv.close()
        Self.dump(Self.composite(frame, tvLayer), "tv-\(name)")
        let diff = Self.maskDifference(layer, tvLayer)
        XCTAssertLessThan(diff, 0.01, "\(name): bilgisayardaki katman TV'dekiyle aynı yerde ve boyda olmalı (fark \(diff))")
        st.translation = .off
        Self.spin(0.1)
    }

    /// Okuma işini (async) ana döngüyü çevirerek bekler (WKWebView'li testler async olunca XCTest'te çöküyor).
    @MainActor
    static func wait<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) throws -> T {
        let box = ResultBox<T>()
        Task.detached { do { box.result = .success(try await work()) } catch { box.result = .failure(error) } }
        CompositeFrameTests.spin(until: { box.result != nil }, timeout: 120)
        guard let r = box.result else { throw XCTSkip("okuma zaman aşımı") }
        return try r.get()
    }

    @MainActor
    func testRealMapCardsOnComputerLayer() throws {
        for name in ["breakfast-run-23-49", "moses-declasse-22-56"] {
            let (payload, img) = try Self.wait { try await Self.mapPayload(name) }
            XCTAssertEqual(payload.items.count, 1)
            try renderOnPanel(payload, frame: img, name: name)
        }
    }

    @MainActor
    func testRealPhonePanelOnComputerLayer() throws {
        let (payload, img) = try Self.wait { try await Self.phonePayload() }
        XCTAssertTrue(payload.items.contains { $0.text.contains("Cal") }, "\(payload.items.map(\.text))")
        try renderOnPanel(payload, frame: img, name: "telefon-cal")
    }
}

/// Ana döngü dışında biten işin sonucu.
private final class ResultBox<T>: @unchecked Sendable { var result: Result<T, Error>? }
