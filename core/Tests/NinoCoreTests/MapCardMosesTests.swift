// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

#if canImport(Vision)
import CoreGraphics
import ImageIO
import XCTest
@testable import NinoCore

/// Kullanıcının GTA 6 kareleri (22 Kasım 22:56, 1280 genişlik): Robberies › Steal Vehicles for Moses, önce
/// Declasse Yosemite 1500 sonra Karin Futo kartı. Karelerde hata ayıklama sürümünün çizdiği cyan okuma kutusu ve
/// sarı kesikli alan vardır (gerçek oyunda yoktur). Bindirme kayıktı: pinin "1.62 km" yazısı başlığa yapışıp kutuyu
/// kartın ~0,05 soluna taşıyordu, üst şerit (görev adı) örtülmüyordu, kart değişince eski kart ~0,6 sn kalıyordu.
final class MapCardMosesTests: XCTestCase {
    /// Kartın koyu paneli (kareden piksel taramasıyla ölçüldü: parlaklık < 130 olan bölge).
    static let declassePanel = GR.Box(left: 0.537, top: 0.425, right: 0.815, bottom: 0.577)
    static let karinPanel = GR.Box(left: 0.537, top: 0.410, right: 0.815, bottom: 0.594)

    static func image(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Resources/gta6-map"))
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
    }

    static func read(_ name: String) async throws -> (lines: [GR.Line], image: CGImage) {
        let img = try image(name)
        var cfg = GR.Reader.Configuration()
        cfg.mapScreenCountsAsMenu = true
        let reader = GR.Reader(textReader: GR.VisionTextReader(), clock: GR.ManualClock(0), configuration: cfg)
        _ = await reader.readCorners(GR.ImageFrame(img))
        let lines = await reader.lastMenuSearchLines
        if lines.isEmpty { throw XCTSkip("Vision bu ortamda yazı okumadı") }
        return (lines, img)
    }

    static func translator() -> FakePhoneTranslator {
        let t = FakePhoneTranslator()
        t.asksPool = false
        t.device = { s in
            switch s {
            case "Steal Vehicles For Moses": return "Moses için araç çal"
            case "There's a Yosemite 1500 on Bastion St.": return "Bastion Caddesi'nde bir Yosemite 1500 var."
            case "There's a Karin Futo stored in a lockup in the Draper Island Docks.":
                return "Draper Adası Rıhtımı'ndaki bir depoda bir Karin Futo saklanıyor."
            default: return s
            }
        }
        return t
    }

    /// Kutu paneli tam örter ve en çok 0,01 taşar.
    func assertCovers(_ box: GR.Box, _ panel: GR.Box, grownDown: Bool = false, _ name: String) {
        XCTAssertLessThanOrEqual(box.left, panel.left, name)
        XCTAssertLessThanOrEqual(box.top, panel.top, name)
        XCTAssertGreaterThanOrEqual(box.right, panel.right, name)
        XCTAssertGreaterThanOrEqual(box.bottom, panel.bottom, name)
        XCTAssertGreaterThanOrEqual(box.left, panel.left - 0.01, name)
        XCTAssertGreaterThanOrEqual(box.top, panel.top - 0.01, name)
        XCTAssertLessThanOrEqual(box.right, panel.right + 0.01, name)
        if !grownDown { XCTAssertLessThanOrEqual(box.bottom, panel.bottom + 0.01, name) }
    }

    func testCardsCoverPanelWithHeader() async throws {
        let (dl, di) = try await Self.read("moses-declasse-22-56")
        let (kl, ki) = try await Self.read("moses-karin-22-56")
        let d = try XCTUnwrap(GR.MapCardFinder.find(dl))
        let k = try XCTUnwrap(GR.MapCardFinder.find(kl))
        XCTAssertEqual(d.header, "STEAL VEHICLES FOR MOSES")
        XCTAssertEqual(d.title, "DECLASSE YOSEMITE 1500", "pinin uzaklığı başlığa girmez")
        XCTAssertEqual(d.sentences, ["There's a Yosemite 1500 on Bastion St."])
        XCTAssertEqual(k.header, "STEAL VEHICLES FOR MOSES")
        XCTAssertEqual(k.title, "KARIN FUTO")
        XCTAssertEqual(k.sentences, ["There's a Karin Futo stored in a lockup in the Draper Island Docks."])
        // Pinin "1.62 km" / "2.61 km" yazısı (sağ ucu ~0,519) kart kutusuna girmez.
        XCTAssertGreaterThan(d.box.left, 0.53)
        XCTAssertGreaterThan(k.box.left, 0.53)

        let w = GR.MapCardWatcher(translator: Self.translator(), clock: GR.ManualClock(0))
        _ = await w.setPhoneGame(true)
        let c1 = await w.observe(dl, image: di, menuOpen: true)
        guard case let .set(e1)? = c1.last else { return XCTFail("\(c1)") }
                assertCovers(e1.box, Self.declassePanel, "Declasse")
        XCTAssertEqual(e1.text, "MOSES İÇİN ARAÇ ÇAL\nDECLASSE YOSEMITE 1500\nBastion Caddesi'nde bir Yosemite 1500 var.")
        let c2 = await w.observe(kl, image: ki, menuOpen: true)
        guard case let .set(e2)? = c2.last else { return XCTFail("\(c2)") }
                assertCovers(e2.box, Self.karinPanel, "Karin")
        XCTAssertTrue(e2.text.hasPrefix("MOSES İÇİN ARAÇ ÇAL\nKARIN FUTO\n"), e2.text)
        // Yazı küçülmez; uzun çeviride kutu aşağı uzar.
        let px = try XCTUnwrap(GR.PhonePixels.from(ki, width: 640, height: 360))
        let frame = GR.MapCardFinder.frame(around: k.box, pixels: px)
        let long = GR.MapCardLayout.element(k, title: "KARIN FUTO", sentences: [String(repeating: "Çok uzun bir Türkçe cümle ", count: 8)],
                                            header: "MOSES İÇİN ARAÇ ÇAL", imageFrame: frame)
        XCTAssertEqual(long.style.lineHeight, e2.style.lineHeight, accuracy: 1e-9)
        XCTAssertEqual(long.box.top, e2.box.top, accuracy: 1e-9)
        XCTAssertGreaterThan(long.box.bottom, e2.box.bottom + 0.02)
        assertCovers(long.box, Self.karinPanel, grownDown: true, "Karin uzun")
    }

    /// Kart değişince eski kart çeviri beklenmeden kalkar ve gönderici onu tutmaz.
    func testSwitchRemovesOldCardAtOnce() async throws {
        let (dl, di) = try await Self.read("moses-declasse-22-56")
        let (kl, ki) = try await Self.read("moses-karin-22-56")
        let t = Self.translator()
        let w = GR.MapCardWatcher(translator: t, clock: GR.ManualClock(0))
        _ = await w.setPhoneGame(true)
        guard case let .set(old)? = await w.observe(dl, image: di, menuOpen: true).last else { return XCTFail() }
        var sender = GR.ScreenItemSender()
        XCTAssertEqual(sender.update([old], nowMs: 0, observed: [.map]), .screen([old]))
        let calls = t.deviceCount
        let quick = await w.see(kl, image: ki, menuOpen: true)
        XCTAssertEqual(quick.changes, [.remove])
        XCTAssertTrue(quick.switched)
        XCTAssertEqual(t.deviceCount, calls, "kaldırma çeviriyi beklemez")
        XCTAssertEqual(sender.update([], nowMs: 600, observed: [.map], drop: quick.switched ? [.map] : []), .clear,
                       "eski kart TV'den hemen kalkar")
        let rest = await w.finish()
        guard case let .set(new)? = rest.last else { return XCTFail("\(rest)") }
        XCTAssertTrue(new.text.contains("KARIN FUTO"))
        // Geri dönüş (hafızada): kaldırma ve yeni kart aynı anda, çevirisiz.
        let back = await w.see(dl, image: di, menuOpen: true)
        XCTAssertEqual(back.changes.count, 2)
        XCTAssertEqual(back.changes.first, .remove)
        guard case .set? = back.changes.last else { return XCTFail("\(back)") }
        // Aynı kartın okuması tek turda kaçarsa (kart yok) bu bir değişim değildir: gönderici tutmaya devam eder.
        let miss = await w.see(dl.filter { !$0.text.contains("Bastion") }, image: di, menuOpen: true)
        XCTAssertFalse(miss.switched)
    }
}

/// Kullanıcının GTA 6 karesi (22 Kasım 23:49, 1280 genişlik): duraklatma menüsünün MAP sekmesi, sol üstte görev kartı
/// `BREAKFAST RUN` (portre + iki cümle satırı). Kart ekranın solunda olduğundan aday sayılmıyordu (x > 0,30 süzgeci).
final class MapCardLeftTests: XCTestCase {
    /// Kartın koyu paneli (kareden ölçüldü; üstteki pembe çizgi hariç).
    static let panel = GR.Box(left: 0.082, top: 0.105, right: 0.345, bottom: 0.242)

    func testLeftCardIsFoundAndCovered() async throws {
        let (lines, img) = try await MapCardMosesTests.read("breakfast-run-23-49")
        let card = try XCTUnwrap(GR.MapCardFinder.find(lines))
        XCTAssertEqual(card.title, "BREAKFAST RUN")
        XCTAssertEqual(card.sentences, ["Jason is finally back on his feet. Head out together and get some fresh air."])
        XCTAssertNil(card.header, "üst sekme şeridi (JASON & LUCIA / MAP …) karta karışmaz")
        let t = MapCardMosesTests.translator()
        t.device = { s in s == "Breakfast Run" ? "Kahvaltı turu" : "TR " + s }
        let w = GR.MapCardWatcher(translator: t, clock: GR.ManualClock(0))
        _ = await w.setPhoneGame(true)
        let changes = await w.observe(lines, image: img, menuOpen: true)
        guard case let .set(e)? = changes.last else { return XCTFail("\(changes)") }
        XCTAssertEqual(e.text, "KAHVALTI TURU\nTR Jason is finally back on his feet. Head out together and get some fresh air.")
        XCTAssertFalse(e.text.contains("LUCIA"))
        let p = Self.panel
        XCTAssertLessThanOrEqual(e.box.left, p.left); XCTAssertGreaterThanOrEqual(e.box.left, p.left - 0.01)
        XCTAssertLessThanOrEqual(e.box.top, p.top); XCTAssertGreaterThanOrEqual(e.box.top, p.top - 0.01)
        XCTAssertGreaterThanOrEqual(e.box.right, p.right); XCTAssertLessThanOrEqual(e.box.right, p.right + 0.01)
        XCTAssertGreaterThanOrEqual(e.box.bottom, p.bottom); XCTAssertLessThanOrEqual(e.box.bottom, p.bottom + 0.01)
        XCTAssertGreaterThan(e.box.top, 0.07, "üst sekme şeridini örtmez")
    }

    /// Soldaki menü listesi (Robberies › Steal Vehicles for Moses › `Declasse Yosemite 1500`) kart sayılmaz.
    func testLeftMenuListIsNotACard() async throws {
        let (lines, _) = try await MapCardMosesTests.read("moses-declasse-22-56")
        let menuOnly = lines.filter { ($0.box?.left ?? 1) < 0.30 || ($0.box?.left ?? 0) > 0.85 }
        XCTAssertTrue(menuOnly.contains { $0.text.contains("Declasse Yosemite") })
        XCTAssertNil(GR.MapCardFinder.find(menuOnly))
    }
}
#endif
