// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import XCTest
@testable import NinoCore

/// Sahte çevirmen: havuz sözlüğü, havuz cevapları ve cihaz çevirisi; çağrıları sayar.
final class FakePhoneTranslator: GR.PhoneTranslator, @unchecked Sendable {
    private let lock = NSLock()
    var targetLanguage = "tr"
    var reportsToPool = true
    var asksPool = true
    var knownTexts: [String: String] = [:]
    var poolAnswers: [String: String] = [:]
    var device: @Sendable (String) -> String = { "TR " + $0 }
    private(set) var reported: [[String]] = []
    private(set) var poolCalls: [(texts: [String], context: [String])] = []
    private(set) var deviceCalls: [String] = []

    func known(_ text: String) async -> String? { lock.withLock { knownTexts[text] } }
    func report(_ texts: [String]) async { lock.withLock { reported.append(texts) } }
    func askPool(_ texts: [String], context: [String]) async -> [String?] {
        lock.withLock {
            poolCalls.append((texts, context))
            return texts.map { poolAnswers[$0] }
        }
    }
    func translateOnDevice(_ text: String) async throws -> String {
        lock.withLock { deviceCalls.append(text) }
        return device(text)
    }
    var deviceCount: Int { lock.lock(); defer { lock.unlock() }; return deviceCalls.count }
}

/// Bölgelere göre renk veren sahte renk kaynağı.
struct FakeColors: GR.PhoneColorSource {
    var regions: [(GR.Box, GR.RGB)]
    var background: GR.RGB
    func color(x: Double, y: Double) -> GR.RGB? {
        regions.last { $0.0.contains(x: x, y: y) }?.1 ?? background
    }
}

func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("nino-phone-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

final class PhoneMemoryTests: XCTestCase {
    func testFileRoundTripLegacyKeysAndLanguages() throws {
        let dir = tempDir()
        // Eski dosya: düz nesne; anahtar sadeleştirilmemiş olsa da okunur, değer olmayanlar atlanır.
        let legacy = #"{"Hey, you there?": "Hey, orada mısın?", "bozuk": 3, "": "x"}"#
        try legacy.data(using: .utf8)!.write(to: dir.appendingPathComponent("phone-memory-tr.json"))
        var m = GR.PhoneMemory(directory: dir, language: "tr")
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m.lookup("hey you there"), "Hey, orada mısın?")
        m.store("Are you high right now?", "Kafan mı güzel şu an?")
        m.save()
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("phone-memory-tr.json"))) as! [String: String]
        XCTAssertEqual(raw["are you high right now"], "Kafan mı güzel şu an?")
        // Dil değişince o dilin dosyası.
        m.switchLanguage("ar")
        XCTAssertNil(m.lookup("Are you high right now?"))
        m.switchLanguage("tr")
        XCTAssertNotNil(m.lookup("Are you high right now?"))
    }

    func testCapacityAndPartialLookup() {
        var m = GR.PhoneMemory(directory: nil, language: "tr", capacity: 2)
        m.store("one", "bir"); m.store("two", "iki"); m.store("three", "üç")
        XCTAssertNil(m.lookup("one"), "en eski silinir")
        XCTAssertEqual(m.count, 2)
        var p = GR.PhoneMemory(directory: nil, language: "tr")
        p.store("Here r the spots man. These wrecks should be a good place", "İşte yerler. Bu enkazlar iyi bir yer olur")
        XCTAssertEqual(p.lookup("These wrecks should be a good place"), "İşte yerler. Bu enkazlar iyi bir yer olur")
        XCTAssertNil(p.lookup("a good place"), "kısa mesajda yalnız aynısı")
        p.store("Okay", "Tamam", device: true)
        XCTAssertEqual(p.sessionTranslation("okay"), "Tamam")
    }

    func testTranslationFlowPoolThenDevice() async {
        let t = FakePhoneTranslator()
        t.poolAnswers = ["Where are you?": "Neredesin? &amp; ✕"]
        let ctx = ["a", "b", "c", "d", "e"]
        let r = await GR.PhoneTranslation.translate(["Where are you?", "Come home now", "Bring beer"], context: ctx, with: t)
        XCTAssertEqual(t.reported, [["Where are you?", "Come home now", "Bring beer"]])
        XCTAssertEqual(t.poolCalls.count, 1)
        XCTAssertEqual(t.poolCalls[0].context, ["b", "c", "d", "e"])
        XCTAssertEqual(r.translations["Where are you?"], "Neredesin? &")
        XCTAssertEqual(r.translations["Come home now"], "TR Come home now")
        XCTAssertEqual(r.device, ["Come home now", "Bring beer"])
        XCTAssertEqual(Set(t.deviceCalls), ["Come home now", "Bring beer"])
    }
}

final class PhoneLayoutTests: XCTestCase {
    // Telefon sağ yarıda → panel solunda.
    let phone = GR.PhoneLocation(box: gbox(0.52, 0.15, 0.70, 0.85))

    func chatItems() -> [GR.PhonePanelItem] {
        [
            .init(source: "Are you coming tonight?", translation: "Bu gece geliyor musun?",
                  message: .init(text: "Are you coming tonight?", box: gbox(0.53, 0.50, 0.63, 0.52), lineHeight: 0.02)),
            .init(source: "Yeah, on my way", translation: "Evet, yoldayım",
                  message: .init(text: "Yeah, on my way", box: gbox(0.62, 0.56, 0.69, 0.58), lineHeight: 0.02)),
        ]
    }

    func colors() -> FakeColors {
        FakeColors(regions: [
            (gbox(0.52, 0.15, 0.70, 0.85), GR.RGB(252, 252, 252)),            // sohbet zemini
            (gbox(0.525, 0.495, 0.635, 0.525), GR.RGB(233, 233, 236)),        // gelen balon #e9e9ec
            (gbox(0.615, 0.555, 0.695, 0.585), GR.RGB(200, 219, 244)),        // giden mavi balon
        ], background: GR.RGB(40, 50, 60))
    }

    func testBubbleColor() {
        let c = GR.PhoneLayout.bubbleColor(gbox(0.53, 0.50, 0.63, 0.52), colors: colors())
        XCTAssertEqual(c.hex, "#e9e9ec")
        XCTAssertEqual(GR.PhoneLayout.ink(on: c), "#2c2c2e")
        XCTAssertEqual(GR.PhoneLayout.bubbleColor(gbox(0.53, 0.50, 0.63, 0.52), colors: nil), GR.PhoneLayout.fallbackBubble)
        var tilted = phone; tilted.slope = 0.1
        let cover = try! XCTUnwrap(GR.PhoneLayout.cover(chatItems()[0], phone: tilted, colors: colors(), id: "c"))
        XCTAssertEqual(cover.box.left, 0.53 - 0.0035, accuracy: 1e-9)
        XCTAssertEqual(cover.box.top, 0.50 - 0.004, accuracy: 1e-9)
        XCTAssertEqual(cover.style.angle, -10.1, accuracy: 0.05)
        XCTAssertEqual(cover.style.background, "#e9e9ec")
    }

    func testChatPanel() throws {
        let els = GR.PhoneLayout.chat(chatItems(), header: "Brian", phone: phone, colors: colors())
        XCTAssertEqual(els.map(\.id), ["00-zemin", "01-baslik", "02", "03"])
        let back = els[0]
        XCTAssertTrue(back.style.backdrop)
        XCTAssertEqual(back.box.top, phone.box.top)
        XCTAssertEqual(back.box.bottom, phone.box.bottom)
        XCTAssertEqual(back.box.right, 0.52 - 0.035, accuracy: 1e-9)
        XCTAssertEqual(back.box.width, 0.27, accuracy: 1e-9)
        XCTAssertEqual(back.style.opacity, 0.6)
        XCTAssertEqual(els[1].text, "Brian")
        let incoming = els[2], outgoing = els[3]
        XCTAssertEqual(incoming.box.top, 0.5, accuracy: 1e-9)
        XCTAssertEqual(incoming.box.left, back.box.left + 0.012, accuracy: 1e-9)
        XCTAssertEqual(outgoing.box.right, back.box.right - 0.012, accuracy: 1e-9)
        XCTAssertEqual(incoming.style.background, "#f8f8f9")
        XCTAssertEqual(outgoing.style.background, "#acccfe")
        XCTAssertEqual(incoming.style.opacity, 0.95)
        XCTAssertTrue(incoming.style.bubble)
        XCTAssertEqual(incoming.style.lineHeight, 0.02 * 0.97, accuracy: 1e-9)
    }

    func testBlueishLightPutsClearBlueRight() {
        // Mavimsi ışıkta gelen balon da hafif mavi; belirgin mavi giden sayılır.
        var c = colors()
        c.regions[1].1 = GR.RGB(220, 228, 240)
        c.regions[2] = (gbox(0.555, 0.555, 0.635, 0.585), GR.RGB(150, 190, 250))
        var items = chatItems()
        items[1].message.box = gbox(0.56, 0.56, 0.63, 0.58)   // girintisi az
        let els = GR.PhoneLayout.chat(items, header: nil, phone: phone, colors: c)
        let back = els[0]
        XCTAssertEqual(els[1].box.left, back.box.left + 0.012, accuracy: 1e-9)
        XCTAssertEqual(els[2].box.right, back.box.right - 0.012, accuracy: 1e-9)
    }

    func testBubbleShiftsAboveLogo() {
        var items = chatItems()
        items[1].message.box = gbox(0.62, 0.83, 0.69, 0.85)
        let els = GR.PhoneLayout.chat(items, header: nil, phone: phone, colors: colors())
        XCTAssertLessThanOrEqual(els.filter { !$0.style.backdrop }.map(\.box.bottom).max()!, 0.85 - 0.012 - 0.03 + 1e-9)
    }

    func testNotWorthShowing() {
        XCTAssertFalse(GR.PhoneLayout.worthShowing(source: "BuckMe", translation: "BuckMe mi?"))
        XCTAssertFalse(GR.PhoneLayout.worthShowing(source: "Lucia", translation: "Lucia"))
        XCTAssertTrue(GR.PhoneLayout.worthShowing(source: "Come home", translation: "Eve gel"))
        let items = [GR.PhonePanelItem(source: "Lucia", translation: "Lucia",
                                       message: .init(text: "Lucia", box: gbox(0.53, 0.5, 0.6, 0.52), lineHeight: 0.02))]
        XCTAssertEqual(GR.PhoneLayout.chat(items, header: "x", phone: phone, colors: nil), [])
    }

    func testAppBubbles() {
        let items = [
            GR.PhonePanelItem(source: "Checking Account", translation: "Cari Hesap",
                              message: .init(text: "Checking Account", box: gbox(0.54, 0.30, 0.64, 0.32), lineHeight: 0.017)),
            GR.PhonePanelItem(source: "$4,900 to next goal", translation: "Sonraki hedefe $4.900",
                              message: .init(text: "$4,900 to next goal", box: gbox(0.54, 0.33, 0.66, 0.35), lineHeight: 0.017)),
        ]
        let header = FakeColors(regions: [(gbox(0.5, 0.10, 0.72, 0.21), GR.RGB(30, 160, 90))], background: GR.RGB(250, 250, 250))
        let els = GR.PhoneLayout.app(items, phone: phone, colors: header)
        XCTAssertEqual(els.count, 2)
        XCTAssertEqual(els[0].style.background, "#1ea05a")
        XCTAssertEqual(els[0].style.textColor, "#ffffff")
        // Telefonun solunda: sağa (telefona) yaslı.
        XCTAssertEqual(els[0].box.right, 0.52 - 0.035, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(els[1].box.top, els[0].box.bottom)
        // Beyaz haber uygulaması: arka plan kovası ve koyulaştırılmış yazı rengi.
        let news = FakeColors(regions: [(gbox(0.54, 0.30, 0.64, 0.32), GR.RGB(20, 40, 200))], background: GR.RGB(250, 250, 250))
        let (fill, ink) = GR.PhoneLayout.appColors(items, phone: phone, colors: news)
        XCTAssertEqual(fill.hex, "#fafafa")
        XCTAssertEqual(ink, GR.RGB(12, 24, 120).hex)
    }
}

final class MapCardFlowTests: XCTestCase {
    func flowerCard(top: Double = 0.40, title: String = "BUY FLOWERS") -> [GR.Line] {
        [
            gline("Recenter", gbox(0.05, 0.90, 0.12, 0.92)), gline("Close Menu", gbox(0.15, 0.90, 0.25, 0.92)),
            gline(title, gbox(0.70, top, 0.80, top + 0.02)),
            gline("Lucia will appreciate this", gbox(0.70, top + 0.03, 0.83, top + 0.05)),
            gline("Have some flowers delivered to the", gbox(0.70, top + 0.055, 0.90, top + 0.075)),
            gline("house for Lucia.", gbox(0.70, top + 0.08, 0.78, top + 0.10)),
        ]
    }

    func testPresenterSteps() throws {
        var p = GR.MapCardPresenter()
        let card = try XCTUnwrap(GR.MapCardFinder.find(flowerCard()))
        // t=0 kart → çeviri işi
        let s0 = p.observe(card, frame: nil, menuOpen: true)
        guard case let .translate(job)? = s0.first else { return XCTFail("\(s0)") }
        // t=600 aynı kart çeviri sürerken → bir şey yok
        XCTAssertEqual(p.observe(card, frame: nil, menuOpen: true), [])
        // t=900 çeviri bitti → gösterilir
        let s1 = p.finished(job, title: "ÇİÇEK AL", sentences: ["Lucia bunu takdir eder", "Eve Lucia için çiçek gönder."], menuOpen: true)
        guard case let .show(e)? = s1.first else { return XCTFail() }
        XCTAssertEqual(e.text.components(separatedBy: "\n").count, 3)
        XCTAssertTrue(e.style.card)
        XCTAssertLessThanOrEqual(e.box.top, card.box.top, "kartın üstüne oturur")
        XCTAssertGreaterThanOrEqual(e.box.bottom, card.box.bottom)
        // Başka kart seçilir → eski kalkar, yenisi çevrilir.
        let other = try XCTUnwrap(GR.MapCardFinder.find(flowerCard(top: 0.55, title: "MEET CAL")))
        let s2 = p.observe(other, frame: nil, menuOpen: true)
        XCTAssertEqual(s2.first, .remove)
        guard case let .translate(job2)? = s2.last else { return XCTFail() }
        // Çeviri sürerken ilk kart yeniden seçilir: hafızada, hemen gösterilir.
        let s3 = p.observe(card, frame: nil, menuOpen: true)
        guard case .show? = s3.first else { return XCTFail("\(s3)") }
        // Süren çeviri biter: kart değiştiği için sonucu gösterilmez.
        let s4 = p.finished(job2, title: "CAL İLE BULUŞ", sentences: ["a", "b."], menuOpen: true)
        XCTAssertEqual(s4, [])
        // Harita kapanır → kalkar.
        XCTAssertEqual(p.observe(nil, frame: nil, menuOpen: false), [.remove])
    }

    func testPendingOnlyLatest() throws {
        var p = GR.MapCardPresenter()
        let a = try XCTUnwrap(GR.MapCardFinder.find(flowerCard(top: 0.30, title: "AAA")))
        let b = try XCTUnwrap(GR.MapCardFinder.find(flowerCard(top: 0.45, title: "BBB")))
        let c = try XCTUnwrap(GR.MapCardFinder.find(flowerCard(top: 0.60, title: "CCC")))
        guard case let .translate(ja)? = p.observe(a, frame: nil, menuOpen: true).first else { return XCTFail() }
        XCTAssertEqual(p.observe(b, frame: nil, menuOpen: true), [])
        XCTAssertEqual(p.observe(c, frame: nil, menuOpen: true), [])
        let s = p.finished(ja, title: "A", sentences: ["x."], menuOpen: true)
        guard case let .translate(jc)? = s.first else { return XCTFail("\(s)") }
        XCTAssertEqual(jc.card.title, "CCC", "yalnız en sonuncusu bekler; süren işin sonucu gösterilmez")
    }

    func testHiddenCards() {
        var p = GR.MapCardPresenter()
        func card(_ title: String?, _ s: [String], _ b: GR.Box) -> GR.MapCard { .init(title: title, sentences: s, box: b, lineHeight: 0.02, left: b.left) }
        XCTAssertEqual(p.observe(card("ÇİÇEK", ["Çiçek al lütfen şimdi."], gbox(0.7, 0.4, 0.9, 0.5)), frame: nil, menuOpen: true), [])
        XCTAssertEqual(p.observe(card(nil, ["Go get it now"], gbox(0.5, 0.4, 0.9, 0.5)), frame: nil, menuOpen: true), [], "başlıksız < 6 sözcük")
        XCTAssertEqual(p.observe(card(nil, ["You have a new trophy unlocked today friend"], gbox(0.65, 0.1, 0.95, 0.2)), frame: nil, menuOpen: true), [], "PS5 bildirimi")
        XCTAssertEqual(p.observe(card("TAB", ["Some tab strip text here"], gbox(0.4, 0.02, 0.9, 0.06)), frame: nil, menuOpen: true), [], "sekme şeridi")
        XCTAssertEqual(p.observe(card("X", [], gbox(0.7, 0.4, 0.9, 0.5)), frame: nil, menuOpen: true), [])
    }

    func testWatcherTranslatesOnceAndKeepsVenueTitle() async throws {
        let t = FakePhoneTranslator()
        t.asksPool = false
        t.device = { s in
            switch s {
            case "Buy Flowers": return "çiçek al"
            case "Lucia will appreciate this": return "Lucia bunu takdir eder"
            default: return "Eve Lucia için narkotik gönder."
            }
        }
        let w = GR.MapCardWatcher(translator: t, clock: GR.ManualClock())
        let notGame = await w.observe(flowerCard(), image: nil, menuOpen: true)
        XCTAssertEqual(notGame, [], "telefon oyunu değilken kart yok")
        _ = await w.setPhoneGame(true)
        let c1 = await w.observe(flowerCard(), image: nil, menuOpen: true)
        guard case let .set(e)? = c1.first else { return XCTFail("\(c1)") }
        XCTAssertEqual(e.text, "ÇİÇEK AL\nLucia bunu takdir eder\nEve Lucia için uyuşturucu gönder.")
        XCTAssertEqual(e.kind, .map)
        XCTAssertEqual(t.deviceCount, 3)
        // Aynı kart yeniden okununca çevirmen çağrılmaz.
        let again = await w.observe(flowerCard(), image: nil, menuOpen: true)
        XCTAssertEqual(again, [])
        XCTAssertEqual(t.deviceCount, 3)
        let closed = await w.menuClosed()
        XCTAssertEqual(closed, [.remove])
        // Mekân başlığı çevrilmez.
        let venue = [gline("Recenter", gbox(0.05, 0.90, 0.12, 0.92)), gline("3D View", gbox(0.15, 0.90, 0.25, 0.92)),
                     gline("RIDEOUT CUSTOMS", gbox(0.70, 0.40, 0.82, 0.42)),
                     gline("Customize your car at this shop today", gbox(0.70, 0.43, 0.90, 0.45))]
        let c2 = await w.observe(venue, image: nil, menuOpen: true)
        guard case let .set(v)? = c2.last else { return XCTFail("\(c2)") }
        XCTAssertTrue(v.text.hasPrefix("RIDEOUT CUSTOMS\n"))
        XCTAssertFalse(t.deviceCalls.contains("Rideout Customs"))
        // Harita tuşları 10 sn'dir görülmedi: menüdeki başka yazı kart sayılmaz.
        let w2 = GR.MapCardWatcher(translator: t, clock: GR.ManualClock())
        _ = await w2.setPhoneGame(true)
        let noMap = await w2.observe(Array(flowerCard().dropFirst(2)), image: nil, menuOpen: true)
        XCTAssertEqual(noMap, [])
    }

    func testLayoutCoversCard() throws {
        let card = try XCTUnwrap(GR.MapCardFinder.find(flowerCard()))
        let e = GR.MapCardLayout.element(card, title: "ÇİÇEK AL", sentences: ["Kısa.", "Kısa iki."], imageFrame: nil)
        // Görüntüden çerçeve yoksa yazı kutusu her yandan ~0,6 satır paylı örtülür: altına/üstüne kaydırılmaz.
        let pad = 0.6 * min(max(card.lineHeight, 0.024), 0.03)
        XCTAssertEqual(e.box.top, card.box.top - pad, accuracy: 1e-9)
        XCTAssertEqual(e.box.left, card.box.left - pad, accuracy: 1e-9)
        XCTAssertEqual(e.box.right, card.box.right + pad, accuracy: 1e-9)
        XCTAssertEqual(e.box.bottom, card.box.bottom + pad, accuracy: 1e-9)
        XCTAssertEqual(e.style.lineHeight, min(max(card.lineHeight, 0.024), 0.034) * 0.9, accuracy: 1e-9)
        // Görüntüdeki çerçeve (paneli) + 0,003 pay; ama yazı kutusunu solda en çok 0,014, üstte 0,02, sağda/altta
        // 0,035 aşar (koyu haritada yürüyüş sınıra gider).
        let f = GR.Box(left: 0.684, top: 0.379, right: 0.95, bottom: 0.55)
        let framed = GR.MapCardLayout.element(card, title: "ÇİÇEK AL", sentences: ["Kısa."], imageFrame: f)
        XCTAssertEqual(framed.box.left, card.box.left - 0.017, accuracy: 1e-9)
        XCTAssertEqual(framed.box.top, card.box.top - 0.023, accuracy: 1e-9)
        XCTAssertEqual(framed.box.right, card.box.right + 0.038, accuracy: 1e-9)
        XCTAssertEqual(framed.box.bottom, card.box.bottom + 0.038, accuracy: 1e-9)
        // Uzun Türkçe: yazı küçülmez, kutu aşağı uzar; üstü yine kartın üstü.
        let long = String(repeating: "Çok uzun bir Türkçe cümle ", count: 12)
        let big = GR.MapCardLayout.element(card, title: "ÇİÇEK AL", sentences: [long], stats: ["GÜVENLİK: DÜŞÜK"], imageFrame: nil)
        XCTAssertEqual(big.box.top, e.box.top, accuracy: 1e-9)
        XCTAssertEqual(big.style.lineHeight, e.style.lineHeight, accuracy: 1e-9)
        XCTAssertGreaterThan(big.box.bottom, e.box.bottom + 0.05)
        XCTAssertTrue(big.text.hasSuffix("\nGÜVENLİK: DÜŞÜK"))
    }

    func testFrameFromImage() {
        var px = GR.PhonePixels(width: 640, height: 360, fill: GR.RGB(200, 210, 190))
        px.fill(gbox(0.67, 0.36, 0.93, 0.53), GR.RGB(20, 20, 26))
        let f = GR.MapCardFinder.frame(around: gbox(0.70, 0.40, 0.90, 0.50), pixels: px)
        XCTAssertEqual(f?.left ?? 0, 0.67, accuracy: 0.006)
        XCTAssertEqual(f?.right ?? 0, 0.93, accuracy: 0.006)
        XCTAssertEqual(f?.bottom ?? 0, 0.53, accuracy: 0.006)
        XCTAssertEqual(f?.top ?? 0, 0.36, accuracy: 0.006)
        // Koyu harita: sınıra kadar gidilir → paylı yazı kutusu.
        let dark = GR.MapCardFinder.frame(around: gbox(0.70, 0.40, 0.90, 0.50), pixels: GR.PhonePixels(width: 640, height: 360, fill: GR.RGB(10, 10, 10)))
        XCTAssertEqual(dark?.left ?? 0, 0.685, accuracy: 1e-9)
        XCTAssertEqual(dark?.top ?? 0, 0.38, accuracy: 1e-9)
        XCTAssertEqual(dark?.right ?? 0, 0.92, accuracy: 1e-9)
        XCTAssertEqual(dark?.bottom ?? 0, 0.52, accuracy: 1e-9)
    }
}

final class PhoneWatcherTests: XCTestCase {
    /// 1280 × 720 kare; telefon (0,42–0,58 × 0,18–0,80) ya da boş sahne.
    func frame(phone: Bool) -> GR.ImageFrame {
        let w = 1280, h = 720
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func fill(_ b: GR.Box, _ g: (Double, Double, Double)) {
            ctx.setFillColor(CGColor(red: g.0 / 255, green: g.1 / 255, blue: g.2 / 255, alpha: 1))
            ctx.fill(CGRect(x: b.left * Double(w), y: (1 - b.bottom) * Double(h), width: b.width * Double(w), height: b.height * Double(h)))
        }
        fill(.full, (120, 140, 170))
        if phone {
            fill(gbox(0.405, 0.15, 0.595, 0.83), (18, 18, 22))
            fill(gbox(0.42, 0.18, 0.58, 0.80), (238, 238, 240))
        }
        return GR.ImageFrame(ctx.makeImage()!)
    }

    /// Telefonda okunan sohbet (kare oranında); okuyucu alan içine çevirir.
    func chatReader(_ lines: @escaping () -> [GR.Line]) -> ScriptedReader {
        ScriptedReader { call in lines().map { l in GR.Line(l.text, confidence: 0.95, box: l.box!.local(in: call.area)) } }
    }

    let chat: [GR.Line] = [
        gline("Brian", gbox(0.48, 0.19, 0.52, 0.21)),
        gline("Are you coming tonight?", gbox(0.43, 0.40, 0.55, 0.42)),
    ]

    func testRoundsConfirmTranslateRememberAndRemove() async throws {
        let clock = GR.ManualClock()
        let dir = tempDir()
        let t = FakePhoneTranslator(); t.asksPool = false
        let w = GR.PhoneWatcher(textReader: chatReader { self.chat }, clock: clock,
                                memory: .init(directory: dir, language: "tr"), translator: t)
        _ = await w.setPhoneGame(true)
        // t=0: bilinmeyen mesaj ilk kez görüldü → çeviriye gitmez, panel boş.
        let u0 = await w.round(frame(phone: true))
        XCTAssertEqual(u0?.elements, nil)
        XCTAssertEqual(u0?.phoneTextSeen, true)
        XCTAssertEqual(t.deviceCount, 0)
        // t=300: aralık (0,6 sn) dolmadı.
        clock.advance(300)
        let early = await w.round(frame(phone: true))
        XCTAssertNil(early)
        // t=600: aynı metin ikinci kez → çevrilir, panel kurulur.
        clock.advance(300)
        let u1Raw = await w.round(frame(phone: true))
        let u1 = try XCTUnwrap(u1Raw?.elements)
        XCTAssertEqual(u1.map(\.id), ["00-zemin", "01-baslik", "02"])
        XCTAssertEqual(u1.last?.text, "TR Are you coming tonight?")
        XCTAssertEqual(t.deviceCount, 1)
        // Hafıza dosyaya yazıldı.
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("phone-memory-tr.json"))) as! [String: String]
        XCTAssertEqual(saved["are you coming tonight"], "TR Are you coming tonight?")
        // t=1600: aynı okuma → değişiklik yok.
        clock.advance(1_000)
        let same = await w.round(frame(phone: true))
        XCTAssertNil(same?.elements)
        // t=2600: telefon yok; 1,2 sn dolmadı.
        clock.advance(1_000)
        let gone1 = await w.round(frame(phone: false))
        XCTAssertNil(gone1)
        // t=3600: 1,2 sn geçti → panel kalkar.
        clock.advance(1_000)
        let gone2 = await w.round(frame(phone: false))
        XCTAssertEqual(gone2, .remove)

        // Yeni açılış: hafızadaki mesaj ilk okumada gösterilir.
        let t2 = FakePhoneTranslator()
        let w2 = GR.PhoneWatcher(textReader: chatReader { self.chat }, clock: clock,
                                 memory: .init(directory: dir, language: "tr"), translator: t2)
        _ = await w2.setPhoneGame(true)
        let firstRaw = await w2.round(frame(phone: true))
        let first = try XCTUnwrap(firstRaw?.elements)
        XCTAssertEqual(first.last?.text, "TR Are you coming tonight?")
        XCTAssertEqual(t2.deviceCount, 0)
    }

    func testFailedTranslationRemovesShownPanel() async throws {
        let clock = GR.ManualClock()
        let t = FakePhoneTranslator(); t.asksPool = false
        t.knownTexts = ["Are you coming tonight?": "Geliyor musun?"]
        var lines = chat
        let w = GR.PhoneWatcher(textReader: chatReader { lines }, clock: clock, memory: .init(directory: nil, language: "tr"), translator: t)
        _ = await w.setPhoneGame(true)
        // t=0 bilinen mesaj → panel.
        let first = await w.round(frame(phone: true))
        XCTAssertEqual(first?.elements?.count, 3)
        // Sohbet değişir, yeni mesaj bilinmiyor ve çevrilemiyor (iki okuma onayından sonra).
        t.device = { _ in "" }
        lines = [gline("Cal", gbox(0.48, 0.19, 0.52, 0.21)), gline("Meet me at the dock now.", gbox(0.43, 0.40, 0.55, 0.42))]
        clock.advance(1_000)
        let u1 = await w.round(frame(phone: true))
        XCTAssertEqual(u1?.elements, [], "sohbet değişti: panel hemen kalkar")
        clock.advance(1_000)
        let u2 = await w.round(frame(phone: true))
        XCTAssertNil(u2?.elements ?? nil)
        let shown = await w.isPanelShown
        XCTAssertFalse(shown)
        let lang = await w.switchLanguage("ar")
        XCTAssertNil(lang, "panel yokken kaldırılacak bir şey yok")
    }

    func testMenuPausesAndPhoneGameOff() async throws {
        let clock = GR.ManualClock()
        let t = FakePhoneTranslator()
        t.knownTexts = ["Are you coming tonight?": "Geliyor musun?"]
        let w = GR.PhoneWatcher(textReader: chatReader { self.chat }, clock: clock, memory: .init(directory: nil, language: "tr"), translator: t)
        let off = await w.round(frame(phone: true))
        XCTAssertNil(off, "telefon oyunu değil")
        _ = await w.setPhoneGame(true)
        let shownRaw = await w.round(frame(phone: true))
        let shown = try XCTUnwrap(shownRaw?.elements)
        XCTAssertEqual(shown.last?.text, "Geliyor musun?", "bilinenler onay beklemez")
        // t=1000 menü açıldı → panel kalkar, 8 sn telefon aranmaz.
        clock.advance(1_000)
        await w.noteMenu(at: clock.nowMs)
        let paused = await w.round(frame(phone: true))
        XCTAssertEqual(paused, .remove)
        clock.advance(7_000)
        let still = await w.round(frame(phone: true))
        XCTAssertNil(still)
        clock.advance(1_500)
        let back = await w.round(frame(phone: true))
        XCTAssertNotNil(back?.elements)
        let offAgain = await w.setPhoneGame(false)
        XCTAssertEqual(offAgain, .remove)
    }

    func testContextForSubtitleLine() async {
        let clock = GR.ManualClock()
        let w = GR.PhoneWatcher(textReader: ScriptedReader(), clock: clock, memory: .init(directory: nil, language: "tr"), translator: nil)
        let none = await w.context(for: frame(phone: true), now: 0)
        XCTAssertNil(none.box)
        _ = await w.setPhoneGame(true)
        let c = await w.context(for: frame(phone: true), now: 0)
        XCTAssertEqual(c.box?.midX ?? 0, 0.5, accuracy: 0.02)
        XCTAssertTrue(c.seenWithin10s)
        XCTAssertTrue(c.isAppText("Trip Details"))
        // 5 sn içinde aynı yerde sayılır, sonra bırakılır.
        let held = await w.context(for: frame(phone: false), now: 4_000)
        XCTAssertNotNil(held.box)
        let dropped = await w.context(for: frame(phone: false), now: 6_000)
        XCTAssertNil(dropped.box)
        XCTAssertTrue(dropped.seenWithin10s)
    }

    func testTrackingNeedsTwoMeasurements() async throws {
        let clock = GR.ManualClock()
        let t = FakePhoneTranslator()
        t.knownTexts = ["Are you coming tonight?": "Geliyor musun?"]
        let w = GR.PhoneWatcher(textReader: chatReader { self.chat }, clock: clock, memory: .init(directory: nil, language: "tr"), translator: t)
        _ = await w.setPhoneGame(true)
        let elsRaw = await w.round(frame(phone: true))
        let els = try XCTUnwrap(elsRaw?.elements)
        let n1 = await w.applyShift(dx: 0.02, dy: 0)
        XCTAssertNil(n1, "tek ölçüm gürültü")
        let n2Raw = await w.applyShift(dx: 0.024, dy: 0)
        let n2 = try XCTUnwrap(n2Raw?.elements)
        XCTAssertEqual(n2[0].box.left - els[0].box.left, 0.022, accuracy: 1e-9)
        let big = await w.applyShift(dx: 0.2, dy: 0)
        XCTAssertNil(big, "0,08'den büyük sıçrama kaydırılmaz")
    }
}

final class PhoneCallAndReaderTests: XCTestCase {
    func testCallPresenter() throws {
        var p = GR.CallPresenter()
        let lines = [gline("Harbor Cabs", gbox(0.70, 0.78, 0.82, 0.80)), gline("Calling...", gbox(0.70, 0.81, 0.78, 0.83))]
        let call = try XCTUnwrap(GR.Cards.call(lines))
        guard case let .set(e) = p.observe(call, now: 0) else { return XCTFail() }
        XCTAssertEqual(e.text, "Harbor Cabs aranıyor…")
        XCTAssertTrue(e.style.italic)
        XCTAssertLessThan(e.box.bottom, 0.78)
        XCTAssertEqual(p.observe(call, now: 500), .none)
        XCTAssertEqual(p.observe(nil, now: 2_000), .none)
        XCTAssertEqual(p.observe(nil, now: 3_600), .remove)
        let talk = try XCTUnwrap(GR.Cards.call([lines[0], gline("00:05", gbox(0.70, 0.81, 0.74, 0.83))]))
        _ = p.observe(call, now: 4_000)
        XCTAssertEqual(p.observe(talk, now: 4_500), .remove, "konuşma sürüyor: gösterilmez")
    }

    func testReaderKeepsMenuLinesAndMapOpensMenu() async {
        let clock = GR.ManualClock()
        let reader = ScriptedReader { call in
            call.area == GR.Corners.menuSearchBox ? [gline("Recenter", gbox(0.1, 0.9, 0.2, 0.93)), gline("Add Marker", gbox(0.3, 0.9, 0.4, 0.93))] : []
        }
        let plain = GR.Reader(textReader: reader, clock: clock)
        let e1 = await plain.readCorners(FakeFrame(1))
        XCTAssertFalse(e1.contains { if case .menuOpened = $0 { return true }; return false }, "varsayılan davranış aynı")
        let kept = await plain.lastMenuSearchLines
        XCTAssertEqual(kept.map(\.text), ["Recenter", "Add Marker"])
        XCTAssertEqual(GR.ScreenGame.detect(kept.map(\.text)), "GTA 6")

        var cfg = GR.Reader.Configuration()
        GR.GTA6Rules.apply(true, packGame: nil, to: &cfg)
        let gta = GR.Reader(textReader: reader, clock: clock, configuration: cfg)
        let e2 = await gta.readCorners(FakeFrame(1))
        XCTAssertTrue(e2.contains { if case .menuOpened = $0 { return true }; return false })
        await plain.setPhoneGame(true, packGame: nil)
        let c = await plain.configuration
        XCTAssertTrue(c.mapScreenCountsAsMenu && c.poolPriority)
        XCTAssertEqual(c.gameKey, "gta-6")
        let ev = await plain.markMenuOpen()
        XCTAssertEqual(ev, .menuOpened(untilMs: clock.nowMs + 5_000))
        let open = await plain.menuOpen
        XCTAssertTrue(open)
    }

    func testPanelPlanScrollAndNewMessages() {
        var p = GR.PhonePanel()
        let phone = GR.PhoneLocation(box: gbox(0.40, 0.15, 0.60, 0.85))
        func reading(_ msgs: [(String, Double)], header: String = "Brian") -> GR.PhoneScreenReading {
            .init(kind: .chat, header: header, headerBox: nil,
                  messages: msgs.map { .init(text: $0.0, box: gbox(0.41, $0.1, 0.55, $0.1 + 0.02), lineHeight: 0.02) })
        }
        let known: [String: String] = ["Hi there.": "Selam.", "Where are you?": "Neredesin?", "On my way!": "Yoldayım!"]
        let lookup: (String) -> String? = { known[$0] }
        // İlk okuma: hepsi biliniyor → kur.
        let r1 = reading([("Hi there.", 0.40), ("Where are you?", 0.45)])
        guard case .build = p.plan(r1, phone: phone, inMemory: { _ in false }, lookup: lookup) else { return XCTFail() }
        _ = p.commit(r1, phone: phone, lookup: lookup, colors: nil)
        // Aynı mesajlar biraz kaymış (0,01): yeniden kurulmaz.
        XCTAssertEqual(p.plan(reading([("Hi there.", 0.41), ("Where are you?", 0.46)]), phone: phone, inMemory: { _ in false }, lookup: lookup), .keep)
        // Yeni mesaj ilk kez: panel korunur.
        let r3 = reading([("Hi there.", 0.41), ("Where are you?", 0.46), ("On my way!", 0.51)])
        XCTAssertEqual(p.plan(r3, phone: phone, inMemory: { _ in false }, lookup: lookup), .keep)
        // İkinci okumada da var → güncellenir.
        let r4 = reading([("Hi there.", 0.40), ("Where are you?", 0.45), ("On my way!", 0.50)])
        guard case .build = p.plan(r4, phone: phone, inMemory: { _ in false }, lookup: lookup) else { return XCTFail() }
        _ = p.commit(r4, phone: phone, lookup: lookup, colors: nil)
        // Kaydırma: aynı mesajlar 0,1 yukarıda → panel hemen kalkar.
        _ = p.plan(reading([("Hi there.", 0.30), ("Where are you?", 0.35), ("On my way!", 0.40)]), phone: phone, inMemory: { _ in false }, lookup: lookup)
        XCTAssertNil(p.shown)
        // Sohbet değişti → önce kalkar.
        let q = GR.PhonePanel()
        var q2 = q
        let a = reading([("Hi there.", 0.40)])
        _ = q2.plan(a, phone: phone, inMemory: { _ in false }, lookup: lookup)
        _ = q2.commit(a, phone: phone, lookup: lookup, colors: nil)
        guard case let .build(_, _, _, _, removeFirst) = q2.plan(reading([("Where are you?", 0.40)], header: "Cal"), phone: phone,
                                                                inMemory: { _ in false }, lookup: lookup) else { return XCTFail() }
        XCTAssertTrue(removeFirst)
    }

    func testPartialMessagesDropped() {
        let phone = GR.PhoneLocation(box: gbox(0.40, 0.15, 0.60, 0.85))
        let r = GR.PhoneScreenReading(kind: .chat, header: "Brian", headerBox: nil, messages: [
            .init(text: "and then we left", box: gbox(0.41, 0.23, 0.55, 0.25), lineHeight: 0.02),
            .init(text: "Middle message.", box: gbox(0.41, 0.40, 0.55, 0.42), lineHeight: 0.02),
            .init(text: "This one goes on and on and is cut at the", box: gbox(0.41, 0.75, 0.55, 0.81), lineHeight: 0.02, lineCount: 3),
        ])
        let d = GR.PhonePanel.dropPartial(r, phone: phone, inMemory: { _ in false })
        XCTAssertEqual(d.messages.map(\.text), ["Middle message."])
        // Üstte kırpılmış balon hafızada olsa da atılır (okumadan okumaya girip çıkmasın).
        let kept = GR.PhonePanel.dropPartial(r, phone: phone, inMemory: { $0.hasPrefix("and") })
        XCTAssertEqual(kept.messages.first?.text, "Middle message.")
    }
}
