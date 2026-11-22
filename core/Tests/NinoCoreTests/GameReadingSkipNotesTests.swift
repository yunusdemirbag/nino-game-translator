// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

/// Menü bayrağının kalkması, devam satırı kuralı ve teşhis notları (oyun-okuma.md "Teşhis notları").
final class GameReadingSkipNotesTests: XCTestCase {
    static let menuLines = ["Map", "Game", "Store", "Help", "Photo Studio", "Settings"]

    /// Menü araması `menu()` doğruyken menüyü, değilse boş ekranı okur; ana okuma hep aynı altyazıyı.
    func makeReader(menu: @escaping () -> Bool, subtitle: String = "Stay close to me.")
        -> (GR.Reader, GR.ManualClock) {
        let clock = GR.ManualClock(0)
        let ocr = ScriptedReader(handler: { call in
            if call.area == GR.Corners.menuSearchBox {
                return menu() ? Self.menuLines.enumerated().map { i, t in gline(t, gbox(0.02, 0.1 + Double(i) * 0.05, 0.12, 0.13 + Double(i) * 0.05)) } : []
            }
            if call.area == GR.Corners.topLeftBox { return [] }
            return [gline(subtitle, gbox(0.3, 0.80, 0.7, 0.86))]
        })
        var cfg = GR.Reader.Configuration(gameKey: "test")
        cfg.region = GR.Region(preset: .fullFrame)
        cfg.plan = .always
        return (GR.Reader(textReader: ocr, clock: clock, configuration: cfg), clock)
    }

    func testMenuFlagClearsAfterTwoMissesNotAfterFiveSeconds() async {
        var inMenu = true
        let (reader, clock) = makeReader(menu: { inMenu })
        let frame = FakeFrame(0, fingerprint: .uniform(50))
        _ = await reader.readCorners(frame)
        var menuOpen = await reader.menuOpen
        XCTAssertTrue(menuOpen)
        var out = await reader.process(frame)
        XCTAssertTrue(out.notes.contains { $0.reason == .menu })
        // Menü kapandı, görüntü aynı (iz değişmedi): ilk ıskada bayrak kalır (okuma bir kez tutmamış olabilir).
        inMenu = false
        clock.advance(600)
        _ = await reader.readCorners(frame)
        menuOpen = await reader.menuOpen
        XCTAssertTrue(menuOpen, "tek ıska bayrağı kaldırmaz")
        clock.advance(600)
        _ = await reader.readCorners(frame)
        menuOpen = await reader.menuOpen
        XCTAssertFalse(menuOpen, "ikinci ıskada kalkar (5 sn beklenmez)")
        clock.advance(100)
        out = await reader.process(frame)
        XCTAssertTrue(out.events.contains { if case .subtitleStarted = $0 { return true }; return false })
    }

    func testMenuFlagClearsAtFirstMissWhenSceneChanged() async {
        var inMenu = true
        let (reader, clock) = makeReader(menu: { inMenu })
        _ = await reader.readCorners(FakeFrame(0, fingerprint: .uniform(50)))
        inMenu = false
        clock.advance(600)
        _ = await reader.readCorners(FakeFrame(1, fingerprint: .uniform(200)))
        let menuOpen = await reader.menuOpen
        XCTAssertFalse(menuOpen)
    }

    /// Menüde arama arada bir tutmazsa bayrak kalkmaz.
    func testIntermittentMissInsideMenuKeepsFlag() async {
        var n = 0
        let (reader, clock) = makeReader(menu: { n += 1; return n % 2 == 1 })
        let frame = FakeFrame(0, fingerprint: .uniform(50))
        for _ in 0..<20 {
            _ = await reader.readCorners(frame)
            let open = await reader.menuOpen
            XCTAssertTrue(open)
            let out = await reader.process(frame)
            XCTAssertFalse(out.events.contains { if case .subtitleStarted = $0 { return true }; return false })
            clock.advance(600)
        }
    }

    // MARK: Devam satırı (telefon oyunu, küçük harfli blok)

    func gta6Reader(_ script: [[GR.Line]]) -> (GR.Reader, GR.ManualClock) {
        let clock = GR.ManualClock(0)
        var cfg = GR.Reader.Configuration()
        GR.GTA6Rules.apply(true, packGame: "gta-6", to: &cfg)
        cfg.plan = .always
        return (GR.Reader(textReader: ScriptedReader(script), clock: clock, configuration: cfg), clock)
    }

    func texts(_ out: GR.Output) -> [String] {
        out.events.compactMap { e in
            switch e {
            case let .subtitleStarted(s), let .subtitleUpdated(s), let .subtitleCorrected(s): return s.text
            default: return nil
            }
        }
    }

    func testLowercaseContinuationOfOpenLineIsRead() async {
        let box = gbox(0.35, 0.55, 0.65, 0.62)
        let open = [gline("And after what we went through,", box)]
        let paid = [gline("we deserve to get paid.", box), gline("Uh-huh.", gbox(0.46, 0.64, 0.54, 0.70))]
        let (reader, clock) = gta6Reader([open, open, open, open,
                                          paid, paid, paid])
        var shown: [String] = []
        var notes: [GR.Output.Note] = []
        for i in 0..<7 { clock.advance(300); let out = await reader.process(FakeFrame(i)); shown += texts(out); notes += out.notes }
        XCTAssertEqual(shown, ["And after what we went through,", "we deserve to get paid.\nUh-huh."], "\(notes)")
    }

    /// Telefon açıkken (ya da ortada değilken) küçük harfli blok (telefon/mesaj kırıntısı) hemen atılır ve nedeni
    /// bildirilir. Telefon yokken ortadaki küçük harfli satır önce bekletilir, kararlıysa okunur; belirirken okunan
    /// kısmi son (`breakfast.`) kararlı olmadığı için okunmaz.
    func testLowercaseBlockRules() {
        let mid = gbox(0.35, 0.55, 0.65, 0.62)
        func ctx(_ now: Int, phone: Bool = false) -> GR.FilterChain.Context {
            var c = GR.FilterChain.Context(now: now, area: .full)
            c.cardsEnabled = true; c.phoneGame = true; c.questLine = nil; c.lowercaseWait = true
            if phone { c.phone = GR.PhoneContext(textSeenRecently: true) }
            return c
        }
        var chain = GR.FilterChain()
        var r = chain.run([gline("bring the car keys", gbox(0.35, 0.85, 0.65, 0.9))], ctx(0, phone: true))
        XCTAssertNil(r.text)
        XCTAssertEqual(r.notes.first?.reason, .lowercase)
        XCTAssertEqual(r.notes.first?.text, "bring the car keys")
        // Ortada değil: telefon oyununun orta şartı atar (sessiz süzgeç notu).
        chain = GR.FilterChain()
        r = chain.run([gline("bring the car keys", gbox(0.70, 0.55, 0.95, 0.62))], ctx(0))
        XCTAssertEqual(r.notes.first?.reason, .filtered("ortada değil"))
        // Telefon yok, ortada: bekletilir, yeniden okunur; 400 ms aynı okununca geçer.
        chain = GR.FilterChain()
        r = chain.run([gline("they'll have that here.", mid)], ctx(0))
        XCTAssertNil(r.text); XCTAssertTrue(r.rereadSoon); XCTAssertEqual(r.notes.first?.reason, .lowercaseWaiting)
        r = chain.run([gline("they'll have that here.", mid)], ctx(200))
        XCTAssertNil(r.text)
        r = chain.run([gline("they'll have that here.", mid)], ctx(450))
        XCTAssertEqual(r.text, "they'll have that here.")
        // Kısmi okuma tam satıra dönüşür: kısmi hiç geçmez, tam satır (büyük harfli) hemen geçer.
        chain = GR.FilterChain()
        XCTAssertNil(chain.run([gline("breakfast.", gbox(0.52, 0.55, 0.62, 0.62))], ctx(0)).text)
        XCTAssertEqual(chain.run([gline("Come on. Let's get some breakfast.", mid)], ctx(100)).text, "Come on. Let's get some breakfast.")
        // Ekrandaki satırın kendisi (küçük harfli devam satırı gösterildikten sonra) atılmaz.
        chain = GR.FilterChain()
        var c = ctx(0)
        c.currentText = "they'll have that here."
        XCTAssertEqual(chain.run([gline("they'll have that here.", mid)], c).text, "they'll have that here.")
    }

    /// Not satırı gerçekten atan adıma yazılır: sağ alt köşe satırları köşe adımında gider (sonraki adıma değil).
    func testSilentDropNamesTheRightStage() {
        var c = GR.FilterChain.Context(now: 0, area: .full)
        c.cardsEnabled = true; c.phoneGame = true; c.questLine = nil
        var chain = GR.FilterChain()
        let r = chain.run([gline("your next interest payment is due", gbox(0.70, 0.80, 0.95, 0.84))], c)
        XCTAssertNil(r.text)
        XCTAssertTrue(r.notes.contains { if case let .filtered(s) = $0.reason { return s.hasPrefix("sağ alt köşe") }; return false }, "\(r.notes)")
        XCTAssertFalse(r.notes.contains { $0.label.contains("açık zeminde") })
    }

    // MARK: Yalnız altyazı notları

    func testSubtitlesOnlyDropsAreReported() {
        let lines = [gline("Press ✕ to open", gbox(0.3, 0.70, 0.7, 0.75)), gline("We leave at dawn.", gbox(0.3, 0.85, 0.7, 0.9))]
        let f = GR.Filters.SubtitlesOnly.filterWithDrops(lines, area: .full, strip: nil)
        XCTAssertEqual(f.kept.map(\.text), ["We leave at dawn."])
        XCTAssertEqual(f.dropped.map(\.1), [.button])
        var chain = GR.FilterChain()
        var ctx = GR.FilterChain.Context(now: 0, area: .full)
        ctx.subtitlesOnly = true
        ctx.questLine = nil
        let r = chain.run(lines, ctx)
        XCTAssertEqual(r.notes.map(\.label), ["atıldı: yalnız-altyazı (tuş ipucu)"])
    }

    // MARK: Günlük

    func testJournalCollapsesRepeats() {
        var j = GR.SkipJournal()
        let menu = GR.Output.Note(.menu, text: "You know, if Cal were here, he- he'd know exactly what to do.")
        XCTAssertEqual(j.observe([menu], now: 0), ["atlandı: menü \"You know, if Cal were here, he- he'd know exactly what to d…\""])
        for t in stride(from: 100, through: 4_000, by: 100) { XCTAssertEqual(j.observe([menu], now: t), []) }
        // Kısa boşluk aynı akışı bölmez.
        XCTAssertEqual(j.observe([], now: 4_500), [])
        XCTAssertEqual(j.observe([menu], now: 4_600), [])
        // Neden değişti: önce özet, sonra yeni neden.
        XCTAssertEqual(j.observe([GR.Output.Note(.busy)], now: 4_700), ["özet: atlandı: menü \"You know, if Cal were here, he- he'd know exactly what to d…\" ×42, 4,6 sn", "atlandı: okuyucu meşgul"])
        // Uzun boşluk: tek kez görülen neden için özet yok.
        XCTAssertEqual(j.observe([], now: 9_000), [])
        XCTAssertEqual(j.flush(), [])
        // Uzun metin kısaltılır.
        XCTAssertEqual(GR.Output.Note(.stale, text: String(repeating: "a", count: 100)).text?.count, 60)
    }
}
