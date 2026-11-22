// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import ImageIO
import XCTest
@testable import NinoCore


/// TV'ye giden öğe listesi: yenileme ve harita kartının kalkma histerezisi.
final class ScreenItemSenderTests: XCTestCase {
    private func card(_ text: String) -> GR.ScreenElement {
        GR.ScreenElement(kind: .map, id: "kart", box: GR.Box(left: 0.5, top: 0.6, right: 0.8, bottom: 0.7), text: text)
    }

    private let area = GR.Box(left: 0.55, top: 0.42, right: 0.80, bottom: 0.58)
    private var dark: GR.PhonePixels { GR.PhonePixels(width: 640, height: 360, fill: GR.RGB(40, 40, 50)) }
    private var light: GR.PhonePixels { GR.PhonePixels(width: 640, height: 360, fill: GR.RGB(210, 215, 220)) }

    func testRefreshBeforeTVExpiry() {
        var s = GR.ScreenItemSender()
        let half = s.settings.refreshAfterMs
        XCTAssertLessThan(half, GR.ScreenElement.layerDurationMs, "TV süresi dolmadan yenilenmeli")
        XCTAssertEqual(s.update([card("A")], nowMs: 1_000), .screen([card("A")]))
        XCTAssertNil(s.update([card("A")], nowMs: 2_000), "değişmeyen liste yeniden gönderilmez")
        XCTAssertNil(s.refresh(nowMs: 1_000 + half - 1))
        XCTAssertEqual(s.refresh(nowMs: 1_000 + half), .screen([card("A")]))
        XCTAssertNil(s.refresh(nowMs: 1_000 + half + 10))
        var empty = GR.ScreenItemSender()
        XCTAssertNil(empty.refresh(nowMs: 1_000_000), "boş liste yenilenmez")
    }

    func testMapCardHysteresis() {
        var s = GR.ScreenItemSender()
        let src = ["map:kart": area]
        XCTAssertEqual(s.update([card("A")], nowMs: 0, observed: [.map], pixels: dark, sources: src), .screen([card("A")]))
        // Okuma kartı kaçırdı ama bölge aynı: kalkmaz, ne kadar sürerse sürsün.
        for t in stride(from: 600, through: 10_000, by: 600) {
            XCTAssertNil(s.update([], nowMs: t, observed: [.map], pixels: dark), "t=\(t)")
        }
        XCTAssertTrue(s.isShowing(.map))
        XCTAssertTrue(s.isHolding(.map))
        // Bölge değişti: 3 kaçırma ve ≥ 4 sn sonra kalkar.
        var s2 = GR.ScreenItemSender()
        _ = s2.update([card("A")], nowMs: 0, observed: [.map], pixels: dark, sources: src)
        XCTAssertNil(s2.update([], nowMs: 600, observed: [.map], pixels: light))
        XCTAssertNil(s2.update([], nowMs: 1_200, observed: [.map], pixels: light))
        XCTAssertNil(s2.update([], nowMs: 1_800, observed: [.map], pixels: light), "3 kaçırma ama 4 sn dolmadı")
        XCTAssertNil(s2.update([], nowMs: 3_000), "gözlem yoksa kaçırma sayılmaz")
        XCTAssertEqual(s2.update([], nowMs: 4_000, observed: [.map], pixels: light), .clear)
        // Başka kart gelince hemen değişir.
        var s3 = GR.ScreenItemSender()
        _ = s3.update([card("A")], nowMs: 0, observed: [.map], pixels: dark, sources: src)
        XCTAssertNil(s3.update([], nowMs: 600, observed: [.map], pixels: dark))
        XCTAssertEqual(s3.update([card("B")], nowMs: 1_200, observed: [.map], pixels: dark, sources: src), .screen([card("B")]))
        // Menü kapandı: hemen kalkar.
        XCTAssertNil(s3.update([], nowMs: 1_800, observed: [.map], pixels: dark))
        XCTAssertEqual(s3.update([], nowMs: 1_900, drop: [.map]), .clear)
        XCTAssertFalse(s3.isShowing(.map))
        // Tutulmayan türler hemen kalkar.
        var s4 = GR.ScreenItemSender()
        let hint = GR.ScreenElement(kind: .hint, id: "h", box: area, text: "x")
        _ = s4.update([hint], nowMs: 0)
        XCTAssertEqual(s4.update([], nowMs: 100), .clear)
        // Sıfırlama.
        XCTAssertNil(s4.reset())
        _ = s4.update([hint], nowMs: 0)
        XCTAssertEqual(s4.reset(), .clear)
    }

    func testMapButtonsWithKeyGlyphs() {
        // Gerçek okuma (13:16:05): tuş simgeleri harf gibi okunuyor.
        XCTAssertTrue(GR.MapScreen.isMapScreen(["JASON & LUCIA MAP BRIEF PROGRESS R1", "RECENTER L3", "VIEW R3",
                                                "ADD MARKER C", "SET DESTINATION ×"]))
        XCTAssertTrue(GR.MapScreen.isMapScreen(["RECENTER L3", "ADD MARKER •"]))
        XCTAssertFalse(GR.MapScreen.isMapScreen(["RECENTER L3", "Pawn shop that buys collectibles, like"]))
        XCTAssertFalse(GR.MapScreen.isMapScreen(["ADD MARKER NOW", "RECENTER"]), "uzun ek sözcük tuş değil")
        // iOS'un okuması.
        XCTAssertTrue(GR.MapScreen.isMapScreen(["2D VIEW R3", "SET DESTINATION 8"]))
        XCTAssertTrue(GR.MapScreen.isMapScreen(["CLOSE MENU (X)", "ADD MARKER ○"]))
        XCTAssertEqual(GR.ScreenGame.detect(["RECENTER L3", "2D VIEW R3", "ADD MARKER C", "SET DESTINATION 8"]), GR.ScreenGame.gta6)
        // Gerçek son sözcük atılmaz.
        XCTAssertEqual(GR.MapScreen.buttonName("JASON & LUCIA MAP BRIEF PROGRESS R1"), "jason & lucia map brief progress")
        XCTAssertEqual(GR.MapScreen.buttonName("EXIT"), "exit")
        XCTAssertEqual(GR.MapScreen.buttonName("BRIEF"), "brief")
        XCTAssertEqual(GR.MapScreen.buttonName("EXIT ○"), "exit")
        XCTAssertTrue(GR.PhoneScreen.containsMapButton([GR.Line("RECENTER L3")]))
    }
}

#if canImport(Vision)
/// Kullanıcının GTA 6 harita kareleri (22 Kasım, 1280 genişlik): AVERY PAWN kartı ~10 sn sonra TV'den düşüyordu.
final class MapCardFramesTests: XCTestCase {
    struct Step { var name: String; var messages: [GR.ScreenItemSender.Message]; var mapScreen: Bool }

    static func image(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Resources/gta6-map"))
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
    }

    /// Mac'teki `ScreenOverlays` akışı: köşe turu → menü araması → harita kartı izleyici → öğe listesi → gönderici.
    final class Replay {
        let clock = GR.ManualClock(0)
        let reader: GR.Reader
        let watcher: GR.MapCardWatcher
        let translator = FakePhoneTranslator()
        var board = GR.ElementsBoard()
        var sender = GR.ScreenItemSender()

        init() {
            var cfg = GR.Reader.Configuration()
            cfg.mapScreenCountsAsMenu = true
            reader = GR.Reader(textReader: GR.VisionTextReader(), clock: clock, configuration: cfg)
            translator.asksPool = false
            watcher = GR.MapCardWatcher(translator: translator, clock: clock)
        }

        func frame(_ name: String, atMs t: Int) async throws -> Step {
            clock.nowMs = t
            let img = try MapCardFramesTests.image(name)
            _ = await reader.readCorners(GR.ImageFrame(img))
            var out: [GR.ScreenItemSender.Message] = []
            let lines = await reader.lastMenuSearchLines
            if await reader.lastMenuSearchAt >= t {
                for c in await watcher.observe(lines, image: img, menuOpen: await reader.menuOpen) {
                    switch c {
                    case let .set(e): board.set(e)
                    case .remove: board.remove(kind: .map, id: "kart")
                    }
                }
                let px = GR.PhonePixels.from(img, width: 640, height: 360)
                var src: [String: GR.Box] = [:]
                if let a = await watcher.shownArea { src["map:kart"] = a }
                if let m = sender.update(board.list, nowMs: t, observed: [.map], pixels: px, sources: src) { out.append(m) }
            }
            return Step(name: name, messages: out, mapScreen: GR.MapScreen.isMapScreen(lines.map(\.text)))
        }
    }

    static let frames: [(String, Int)] = [
        ("map-13-15-51", 51_194), ("map-13-15-53", 53_236), ("map-13-15-55", 55_299), ("map-13-15-57", 57_334),
        ("map-13-15-59", 59_336), ("map-13-16-01", 61_337), ("map-13-16-03", 63_339), ("map-13-16-05", 65_342),
        ("map-13-16-07", 67_344), ("map-13-16-09", 69_347), ("map-13-16-11", 71_448),
    ]

    func testAveryPawnStaysAndCardsChangeInOrder() async throws {
        let r = Replay()
        _ = await r.watcher.setPhoneGame(true)
        var steps: [Step] = []
        for (name, t) in Self.frames { steps.append(try await r.frame(name, atMs: t)) }
        guard steps.contains(where: { $0.mapScreen }) else { throw XCTSkip("Vision bu ortamda yazı okumadı") }
        XCTAssertEqual(steps.filter { !$0.mapScreen }.map(\.name), [], "tuş simgeli satırlarla da harita ekranı")
        // Gönderilen kart başlıkları sırayla; arada `screen-clear` yok.
        var titles: [String] = []
        for s in steps {
            for m in s.messages {
                guard case let .screen(list) = m, let e = list.first(where: { $0.kind == .map }) else {
                    return XCTFail("\(s.name): kart kalktı (\(m))")
                }
                let title = String(e.text.split(separator: "\n").first ?? "")
                if titles.last != title { titles.append(title) }
            }
        }
        XCTAssertEqual(titles, ["PAY 'N' SPRAY - PORT GELLHORN", "WHS - PORT GELLHORN", "AVERY PAWN"])
        XCTAssertTrue(r.sender.isShowing(.map))
        XCTAssertEqual(r.sender.sent.first?.text.hasPrefix("AVERY PAWN\n"), true)
        // AVERY PAWN bir kez çevrilir (mekân başlığı çevrilmez; 2 cümle).
        let avery = r.translator.deviceCalls.filter { $0.contains("collectibles") }
        XCTAssertEqual(avery.count, 2, "\(r.translator.deviceCalls)")

        // Kart gerçekten kapandı (aynı haritada kart yok): 3 kaçırma ve ≥ 4 sn sonra kalkar.
        var closed: [Int] = []
        for k in 1...4 {
            let s = try await r.frame("map-13-15-53", atMs: 71_448 + k * 1_500)
            if s.messages.contains(.clear) { closed.append(k) }
        }
        XCTAssertEqual(closed, [3])
        XCTAssertFalse(r.sender.isShowing(.map))
    }

    /// Tuş simgeleri harf/rakam gibi okunsa da harita ekranı ve GTA 6 tanınır (gerçek Vision).
    func testMapScreenAndGameFromRealFrames() async throws {
        let ocr = GR.OCR(reader: GR.VisionTextReader())
        var read = 0
        for name in ["gta6-harita-buckme", "map-13-16-01", "map-13-16-05", "map-13-16-11"] {
            let img = try Self.image(name)
            let box = GR.Corners.menuSearchBox
            let raw = try await ocr.read(GR.ImageFrame(img), area: box, deep: false,
                                         scale: GR.Corners.menuScale(pixelWidth: img.width))
            let texts = raw.map { GR.Filters.cleanJunk($0.text) }.filter { !$0.isEmpty }
            guard !texts.isEmpty else { continue }
            read += 1
            XCTAssertTrue(GR.MapScreen.isMapScreen(texts), "\(name): \(texts)")
            XCTAssertEqual(GR.ScreenGame.detect(texts), GR.ScreenGame.gta6, name)
        }
        if read == 0 { throw XCTSkip("Vision bu ortamda yazı okumadı") }
    }

    /// Aynı kartın karelerinde bölge imzası "değişmedi", kartın kalktığı karede "değişti" der.
    func testLookDifferenceOnRealFrames() throws {
        let area = GR.Box(left: 0.545, top: 0.426, right: 0.788, bottom: 0.581)
        func look(_ n: String) throws -> [Double] {
            GR.ScreenItemSender.look(try XCTUnwrap(GR.PhonePixels.from(try MapCardFramesTests.image(n), width: 640, height: 360)), area)
        }
        let base = try look("map-13-15-57")
        let threshold = GR.ScreenItemSender.Settings().changeThreshold
        for n in ["map-13-16-01", "map-13-16-05", "map-13-16-11"] {
            XCTAssertLessThan(GR.ScreenItemSender.difference(base, try look(n)), threshold, n)
        }
        XCTAssertGreaterThan(GR.ScreenItemSender.difference(base, try look("map-13-15-53")), threshold * 2)
    }
}
#endif
