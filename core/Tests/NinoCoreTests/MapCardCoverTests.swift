// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

#if canImport(Vision)
import CoreGraphics
import ImageIO
import XCTest
@testable import NinoCore

/// Kullanıcının GTA 6 karesi (22 Kasım 17:18, 1280 genişlik): mağaza haritası, UNCLE JACK'S LIQUOR kartı ve
/// "Go to the docks" görev şeridi (`docks` pembe). Çeviriler orijinalin üstüne dar/kayık biniyordu, kart iki okuma
/// arasında titriyordu.
final class MapCardCoverTests: XCTestCase {
    static func image() throws -> CGImage {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "liquor-14-18-08", withExtension: "jpg", subdirectory: "Resources/gta6-map"))
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
    }

    func read() async throws -> (corners: [GR.Event], menu: [GR.Line], image: CGImage) {
        let img = try Self.image()
        var cfg = GR.Reader.Configuration()
        cfg.mapScreenCountsAsMenu = true
        let reader = GR.Reader(textReader: GR.VisionTextReader(), clock: GR.ManualClock(0), configuration: cfg)
        let events = await reader.readCorners(GR.ImageFrame(img))
        let lines = await reader.lastMenuSearchLines
        if lines.isEmpty { throw XCTSkip("Vision bu ortamda yazı okumadı") }
        return (events, lines, img)
    }

    /// Kart kutusu kartın kendi sınırına oturur (başlık + açıklama + alt satırlar); alt satırlar da çevrilir.
    func testCardCoversWholeCardFromRealFrame() async throws {
        let (_, lines, img) = try await read()
        let card = try XCTUnwrap(GR.MapCardFinder.find(lines))
        XCTAssertEqual(card.title, "UNCLE JACK'S LIQUOR - PORT GELLHORN")
        XCTAssertEqual(card.sentences, ["Liquor store selling beer, snacks, and smokes."], "harita yer adı cümleye yapışmaz")
        XCTAssertEqual(card.stats.map(\.label), ["FEATURES", "SECURITY", "TAKE VALUE"])
        XCTAssertEqual(card.stats.first { $0.label == "SECURITY" }?.value, "LOW")
        XCTAssertEqual(card.stats.first { $0.label == "TAKE VALUE" }?.value?.hasPrefix("$100"), true)

        let t = FakePhoneTranslator()
        t.asksPool = false
        t.device = { s in
            switch s {
            case "Liquor store selling beer, snacks, and smokes.": return "Bira, atıştırmalık ve sigara satan içki dükkânı."
            case "Features": return "Özellikler"
            case "Security": return "Güvenlik"
            case "Low": return "Düşük"
            case "Take Value": return "Kazanç"
            default: return s
            }
        }
        let w = GR.MapCardWatcher(translator: t, clock: GR.ManualClock(0))
        _ = await w.setPhoneGame(true)
        let changes = await w.observe(lines, image: img, menuOpen: true)
        guard case let .set(e)? = changes.last else { return XCTFail("\(changes)") }
        // Oyundaki kart (1920 karede ölçüldü): sol 0,537, üst 0,363, sağ 0,816, alt 0,637.
        XCTAssertLessThanOrEqual(e.box.left, 0.537)
        XCTAssertLessThanOrEqual(e.box.top, 0.363)
        XCTAssertGreaterThanOrEqual(e.box.right, 0.80)
        XCTAssertGreaterThanOrEqual(e.box.bottom, 0.625, "TAKE VALUE satırı da örtülür")
        XCTAssertLessThan(e.box.bottom, 0.70, "kartın altına taşmaz")
        XCTAssertGreaterThan(e.box.left, 0.525, "soldaki yer adına (sağ ucu 0,536) taşmaz")
        XCTAssertLessThan(e.box.right, 0.83)
        XCTAssertEqual(e.text, "UNCLE JACK'S LIQUOR - PORT GELLHORN\nBira, atıştırmalık ve sigara satan içki dükkânı.\n"
                       + "ÖZELLİKLER\nGÜVENLİK: DÜŞÜK\nKAZANÇ: " + (card.stats[2].value ?? ""))
        // Kartın alt satırlarıyla çakışan bir şey kalmaz: her alt satır kutunun içinde.
        for l in lines where ["SECURITY", "LOW", "TAKE VALUE"].contains(l.text) {
            let b = try XCTUnwrap(l.box)
            XCTAssertTrue(e.box.left <= b.left && e.box.right >= b.right && e.box.top <= b.top && e.box.bottom >= b.bottom, l.text)
        }
    }

    /// Görev şeridi: kutu orijinal metnin tamamı; `docks` pembe okunur, çeviride karşılığı işaretlenir.
    func testQuestStripAccentFromRealFrame() async throws {
        let (events, _, img) = try await read()
        var strip: [GR.Line] = []
        for e in events { if case let .corner(.questStrip, l) = e { strip = l } }
        let line = try XCTUnwrap(strip.first)
        XCTAssertTrue(line.text.lowercased().hasSuffix("docks"), line.text)
        let box = try XCTUnwrap(line.box)
        // Oyundaki şerit (1920 karede ölçüldü): 0,447–0,553.
        XCTAssertLessThanOrEqual(box.left, 0.448)
        XCTAssertGreaterThanOrEqual(box.right, 0.552)
        XCTAssertEqual(GR.Accent.phrases(line, image: img), ["docks"])
        XCTAssertEqual(GR.Accent.mark("Limanlara git", term: "Limanlar"), "⟦Limanlara⟧ git")
    }

    func testAccentMarking() {
        XCTAssertEqual(GR.Accent.mark("Limanlara git.", term: "liman"), "⟦Limanlara⟧ git.")
        XCTAssertEqual(GR.Accent.mark("Lucia'yı motele götür", term: "Motel"), "Lucia'yı ⟦motele⟧ götür")
        XCTAssertEqual(GR.Accent.mark("\"Rıhtıma\" git", term: "rıhtım"), "\"⟦Rıhtıma⟧\" git")
        XCTAssertNil(GR.Accent.mark("Limanlara git", term: "rıhtımlar"), "karşılık yoksa vurgusuz")
        XCTAssertNil(GR.Accent.mark("Eve git", term: "ev de"), "kısa sözcük tam eşleşmeli")
        XCTAssertFalse(GR.Accent.isAccent(GR.RGB(255, 255, 255)))
        XCTAssertFalse(GR.Accent.isAccent(GR.RGB(230, 40, 30)), "kırmızı vurgu sayılmaz")
        XCTAssertTrue(GR.Accent.isAccent(GR.RGB(255, 95, 178)))
    }

    /// Canlıda iki okuma 0,6 sn'de bir gidip geliyordu: yer adı yapışık (A) ve temiz (B). İkisi de aynı karta iner.
    func testAlternatingReadingsGiveOneCard() throws {
        let buttons = [gline("RECENTER L3", gbox(0.905, 0.755, 0.98, 0.783)), gline("ADD MARKER", gbox(0.891, 0.853, 0.961, 0.878))]
        let title = gline("UNCLE JACK'S LIQUOR - PORT GELLHORN", gbox(0.545, 0.377, 0.805, 0.414))
        let stats = [gline("322 m FEATURES", gbox(0.484, 0.503, 0.595, 0.530)), gline("SECURITY", gbox(0.545, 0.549, 0.594, 0.575)),
                     gline("LOW", gbox(0.778, 0.550, 0.802, 0.572)), gline("TAKE VALUE", gbox(0.545, 0.597, 0.605, 0.619)),
                     gline("$100 - $1,000", gbox(0.734, 0.591, 0.798, 0.619))]
        let a = buttons + [title, gline("Port Gellhorn Liquor store selling beer, snacks, and", gbox(0.372, 0.414, 0.783, 0.461)),
                           gline("smokes.", gbox(0.547, 0.465, 0.600, 0.485))] + stats
        let b = buttons + [title, gline("Port Gellhorn", gbox(0.371, 0.412, 0.536, 0.459)),
                           gline("Liquor store selling beer, snacks, and", gbox(0.547, 0.420, 0.783, 0.455)),
                           gline("smokes.", gbox(0.547, 0.465, 0.600, 0.485))] + stats
        let ca = try XCTUnwrap(GR.MapCardFinder.find(a)), cb = try XCTUnwrap(GR.MapCardFinder.find(b))
        XCTAssertEqual(ca.sentences, ["Liquor store selling beer, snacks, and smokes."])
        XCTAssertEqual(ca.fullText, cb.fullText)
        XCTAssertEqual(ca.key, cb.key)
        XCTAssertEqual(ca.stats, cb.stats)

        // Okuma yine de ikiye bölünürse: gösterilen kart üst üste 3 kez görülmeyen okumaya geçmez.
        var p = GR.MapCardPresenter()
        var other = ca
        other.sentences = ["Liquor store selling cold beer and cigars."]
        guard case let .translate(job)? = p.observe(ca, frame: nil, menuOpen: true).first else { return XCTFail() }
        _ = p.finished(job, title: ca.title, sentences: ["Bira satan dükkân."], menuOpen: true)
        for _ in 0..<5 {
            XCTAssertEqual(p.observe(other, frame: nil, menuOpen: true), [])
            XCTAssertEqual(p.observe(ca, frame: nil, menuOpen: true), [])
        }
        // Alt satırı eksik okunan kart, eksiksiz okununca yenilenir (`LOW` sonradan okundu); tersi olmaz.
        var q = GR.MapCardPresenter()
        var partial = ca
        partial.stats[1].value = nil
        guard case let .translate(j1)? = q.observe(partial, frame: nil, menuOpen: true).first else { return XCTFail() }
        _ = q.finished(j1, title: ca.title, sentences: ["Bira satan dükkân."], stats: ["ÖZELLİKLER", "GÜVENLİK", "KAZANÇ: $100 - $1,000"], menuOpen: true)
        guard case let .translate(j2)? = q.observe(ca, frame: nil, menuOpen: true).first else { return XCTFail("eksik alt satır kaldı") }
        let full = q.finished(j2, title: ca.title, sentences: ["Bira satan dükkân."],
                              stats: ["ÖZELLİKLER", "GÜVENLİK: DÜŞÜK", "KAZANÇ: $100 - $1,000"], menuOpen: true)
        guard case let .show(e)? = full.first else { return XCTFail("\(full)") }
        XCTAssertTrue(e.text.contains("GÜVENLİK: DÜŞÜK"))
        XCTAssertEqual(q.observe(partial, frame: nil, menuOpen: true), [], "eksik okuma eksiksizin yerine geçmez")

        // Gerçekten değişen okuma üçüncü kez üst üste görülünce geçer.
        XCTAssertEqual(p.observe(other, frame: nil, menuOpen: true), [])
        XCTAssertEqual(p.observe(other, frame: nil, menuOpen: true), [])
        guard case .translate? = p.observe(other, frame: nil, menuOpen: true).first else { return XCTFail() }
    }
}
#endif

#if canImport(Vision)
/// GTA 6 duraklatma menüsü (22 Kasım 17:38): sol sütun `Map / Game / Store / Help / Photo Studio / Settings` köşe
/// olarak çevrilip TV'ye gidiyordu ("Harita Oyun Mağaza Yardım"). Menüler çevrilmez.
final class PauseMenuCornerTests: XCTestCase {
    func testPauseMenuIsNotACorner() async throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "pause-menu-17-38", withExtension: "jpg", subdirectory: "Resources/gta6-map"))
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let clock = GR.ManualClock(0)
        let reader = GR.Reader(textReader: GR.VisionTextReader(), clock: clock, configuration: GR.Reader.Configuration())
        var read = false
        for k in 0..<4 {
            clock.nowMs = k * 2_000
            for e in await reader.readCorners(GR.ImageFrame(img)) {
                // İlk turda köşe menüden önce okunur; menü aynı turda tanınır ve Mac bayrak açıkken köşeyi çevirmez.
                if case let .corner(.topLeft, lines) = e, k > 0 { XCTAssertEqual(lines.map(\.text), [], "tur \(k)") }
                if case .menuOpened = e { read = true }
            }
        }
        if !read { throw XCTSkip("Vision bu ortamda yazı okumadı") }
        let open = await reader.menuOpen
        XCTAssertTrue(open)
        // Menü sözcükleri tek başına da köşe sayılmaz (menü bayrağı henüz kurulmamışken).
        // Canlıda (1920 kare) sol üst kutu `Map / Game / Store / Help`'i okudu; menü araması 3 turda bir.
        XCTAssertTrue(GR.Corners.isMenuScreen(["Map", "• Game", "• Store", "+ Help"]))
    }

    /// Menü araması bu turda yokken sol üst köşe duraklatma menüsünün sütununu okur: köşe boş döner.
    func testMenuColumnWithoutMenuSearch() async {
        let reader = ScriptedReader { call in
            guard call.area == GR.Corners.topLeftBox else { return [] }
            return ["Map", "• Game", "• Store", "+ Help"].enumerated().map { i, t in
                gline(t, gbox(0.05, 0.45 + Double(i) * 0.14, 0.3, 0.51 + Double(i) * 0.14))
            }
        }
        let clock = GR.ManualClock(0)
        let r = GR.Reader(textReader: reader, clock: clock)
        var corners = 0
        for k in 0..<3 {
            clock.nowMs = k * 2_000
            for e in await r.readCorners(FakeFrame(1)) {
                if case let .corner(.topLeft, lines) = e { corners += 1; XCTAssertEqual(lines.map(\.text), [], "tur \(k)") }
            }
        }
        XCTAssertEqual(corners, 3)
        let open = await r.menuOpen
        XCTAssertFalse(open, "menü araması menü bulmadı; yine de köşe boş")
    }
}
#endif
