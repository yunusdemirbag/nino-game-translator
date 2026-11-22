// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

#if canImport(Vision)
import CoreGraphics
import ImageIO
import XCTest
@testable import NinoCore

/// Kullanıcının GTA 6 kareleri (23 Kasım 00:29, Mac deneme-4, 1280 genişlik): sağ altta BuckMe bildirimi, sağ üstte
/// "Map updated", ortada Lucia seçim menüsü. Okuma alanı kullanıcınınki (x 0,066–0,98, y 0,567–1).
final class GTA6NotificationTests: XCTestCase {
    static let region = GR.Region(GR.Box(left: 0.0658, top: 0.5668, right: 0.9816, bottom: 1))

    static func image(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Resources/gta6-buckme"))
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
    }

    /// Kareleri gerçek zamanlarıyla (her kare bir sonrakine dek, 100 ms adımla) okur; olayları zamanıyla verir.
    static func replay(_ names: [(Int, String)]) async throws -> [(Int, GR.Event)] {
        let frames = try names.map { ($0.0, try image($0.1)) }
        let clock = GR.ManualClock(frames[0].0)
        var cfg = GR.Reader.Configuration()
        GR.GTA6Rules.apply(true, packGame: "gta-6", to: &cfg)
        cfg.region = region
        let reader = GR.Reader(textReader: GR.VisionTextReader(), clock: clock, configuration: cfg)
        var out: [(Int, GR.Event)] = []
        let end = frames.last!.0 + 1_000
        while clock.nowMs < end {
            let i = frames.lastIndex { $0.0 <= clock.nowMs } ?? 0
            for e in await reader.process(GR.ImageFrame(frames[i].1)).events { out.append((clock.nowMs, e)) }
            clock.advance(100)
        }
        if out.isEmpty { throw XCTSkip("Vision bu ortamda yazı okumadı") }
        return out
    }

    /// BuckMe uygulama bildirimi mesaj kartı olarak okunur (adında iki büyük harf olduğundan atılıyordu); ad çevrilmez,
    /// ikinci bildirim birincinin yerine geçer.
    func testBuckMeNotificationIsAMessageCard() async throws {
        let events = try await Self.replay([(13_394, "bm-00-29-13-394"), (15_457, "bm-00-29-15-457"), (19_500, "bm-00-29-19-500")])
        var presenter = GR.CardPresenter()
        var asked: [String] = []
        for (t, e) in events {
            guard case let .messageCard(card) = e else { continue }
            XCTAssertEqual(card.name, "BuckMe")
            if case let .translate(body) = presenter.observe(card, phoneSeenRecently: false, now: t) {
                asked.append(body)
                presenter.translated(name: card.name, message: card.body, translation: "TR " + body)
                let el = try XCTUnwrap(GR.Cards.layout(card, translation: "TR " + body))
                XCTAssertTrue(el.text.hasPrefix("BuckMe: TR "), el.text)
            }
        }
        XCTAssertEqual(asked.count, 2, "\(asked)")
        XCTAssertTrue(asked.first?.hasPrefix("Your new FAMILY SAVINGS goal is $100,000.") == true, "\(asked)")
        XCTAssertTrue(asked.last?.hasPrefix("A quick Buck, from us to you:") == true, "\(asked)")
    }

    func testAppNameRule() {
        XCTAssertTrue(GR.Cards.isAppName("BuckMe"))
        XCTAssertTrue(GR.Cards.isAppName("LifeInvader"))
        XCTAssertFalse(GR.Cards.isAppName("BUCKME"))
        XCTAssertFalse(GR.Cards.isAppName("Jason"), "tek büyük harfli ad isName'in işi")
        XCTAssertFalse(GR.Cards.isAppName("Your new"))
        XCTAssertFalse(GR.Cards.isAppName("ABCDe"))
    }

    /// Lucia seçim menüsü (ortada, x 0,55–0,67): üç satır da çevrilir (iki sözcüklüler de); çeviri yazının üstüne
    /// oturur, baştaki tuş simgesi görünür kalır. `LUCIA` okuma alanının üstünde kalır (okunmaz).
    func testLuciaChoiceMenuIsTranslated() async throws {
        let events = try await Self.replay([(3_106, "bm-00-29-03-106"), (5_206, "bm-00-29-05-206")])
        var hints = GR.Hints()
        var asked: [String] = []
        var shown: [String: GR.ScreenElement] = [:]
        for (_, e) in events {
            guard case let .hints(lines) = e else { continue }
            let (next, removed) = hints.observe(lines, questLine: 0.86, menuOpen: false)
            for k in removed { shown[k] = nil }
            if let line = next {
                asked.append(line.text)
                if let el = hints.translated(line, turkish: "TR " + line.text) { shown[el.id] = el }
            }
        }
        XCTAssertEqual(Set(asked), ["SPLIT UP & TAKE", "SLOW DOWN", "PULL OVER"], "\(asked)")
        XCTAssertEqual(shown.count, 3)
        for el in shown.values {
            // Simge sütunu (x ≈ 0,550–0,563) açık kalır; yazı (≈ 0,571'den) örtülür.
            XCTAssertGreaterThan(el.box.left, 0.560, el.text)
            XCTAssertLessThan(el.box.left, 0.572, el.text)
            XCTAssertTrue((0.58...0.70).contains(el.box.midY), el.text)
        }
    }

    func testChoiceRowRules() {
        let rows = GR.Hints.choiceRows([
            GR.Line("A SPLIT UP & TAKE F", confidence: 1, box: GR.Box(left: 0.55, top: 0.586, right: 0.673, bottom: 0.614)),
            GR.Line("• SLOW DOWN", confidence: 1, box: GR.Box(left: 0.55, top: 0.625, right: 0.648, bottom: 0.653)),
            GR.Line("× PULL OVER", confidence: 1, box: GR.Box(left: 0.55, top: 0.662, right: 0.645, bottom: 0.691)),
        ])
        XCTAssertEqual(rows.map(\.line.text), ["SPLIT UP & TAKE", "SLOW DOWN", "PULL OVER"])
        XCTAssertTrue(GR.Filters.isHint("A SPLIT UP & TAKE F"))
        // Tek satır menü değildir; simgesiz büyük harfli satırlar da.
        XCTAssertEqual(GR.Hints.choiceRows([GR.Line("• SLOW DOWN", confidence: 1, box: GR.Box(left: 0.55, top: 0.625, right: 0.648, bottom: 0.653))]).count, 0)
        XCTAssertEqual(GR.Hints.choiceRows([
            GR.Line("SLOW DOWN", confidence: 1, box: GR.Box(left: 0.55, top: 0.625, right: 0.648, bottom: 0.653)),
            GR.Line("PULL OVER", confidence: 1, box: GR.Box(left: 0.55, top: 0.662, right: 0.645, bottom: 0.691)),
        ]).count, 0)
        XCTAssertFalse(GR.Filters.isHint("I know it's you & me."))
    }

    /// Sağ üstteki "Map updated" bildirimi menü araması satırlarından bulunur (köşe öğesi "top-right").
    func testMapUpdatedNotice() async throws {
        for (name, ok) in [("bm-00-29-13-394", true), ("bm-00-29-15-457", true), ("bm-00-29-05-206", false)] {
            let img = try Self.image(name)
            var cfg = GR.Reader.Configuration()
            GR.GTA6Rules.apply(true, packGame: "gta-6", to: &cfg)
            let reader = GR.Reader(textReader: GR.VisionTextReader(), clock: GR.ManualClock(0), configuration: cfg)
            _ = await reader.readCorners(GR.ImageFrame(img))
            let lines = await reader.lastMenuSearchLines
            if lines.isEmpty { throw XCTSkip("Vision bu ortamda yazı okumadı") }
            let notice = GR.Corners.topRightNotice(lines)
            guard ok else { XCTAssertNil(notice, "\(name): \(notice?.text ?? "")"); continue }
            let n = try XCTUnwrap(notice, name)
            XCTAssertEqual(n.text, "Map updated", name)
            let e = GR.Corners.topRightElement(box: try XCTUnwrap(n.box), translation: "Harita güncellendi")
            XCTAssertEqual(e.id, "top-right")
            // Oyundaki yazı (1920 karede): x 0,871–0,957, y 0,255–0,290. Vision kutusu sağdaki tuş simgesini (0,965–0,98)
            // de kapsar; öğe onu da örter.
            XCTAssertLessThanOrEqual(e.box.left, 0.871, name)
            XCTAssertLessThanOrEqual(e.box.right, 0.995, name)
            XCTAssertLessThanOrEqual(e.box.top, 0.255, name)
            XCTAssertGreaterThanOrEqual(e.box.bottom, 0.289, name)
        }
        // Para ve tuş satırları bildirim değildir.
        XCTAssertNil(GR.Corners.topRightNotice([GR.Line("$9,335 b", confidence: 1, box: GR.Box(left: 0.91, top: 0.12, right: 0.98, bottom: 0.15))]))
    }
}
#endif
