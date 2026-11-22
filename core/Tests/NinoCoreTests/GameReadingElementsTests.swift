// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

/// Sahte çevirmen: `TR: x`; pakette bilinenler hemen.
final class FakeElementTranslator: GameReading.ElementTranslator, @unchecked Sendable {
    var pack: [String: String] = [:]
    private let lock = NSLock()
    private(set) var requests: [[String]] = []
    var fails = false
    init(pack: [String: String] = [:]) { self.pack = pack }
    func known(_ text: String) -> String? { pack[text] }
    func translate(_ texts: [String]) async throws -> [String] {
        try record(texts)
        return texts.map { "TR: " + $0 }
    }
    private func record(_ texts: [String]) throws {
        lock.lock(); defer { lock.unlock() }
        requests.append(texts)
        if fails { throw URLError(.timedOut) }
    }
}

final class GameReadingElementsTests: XCTestCase {
    // MARK: Kartlar (§14)

    func card(_ name: String, _ body: [String], left: Double = 0.7, top: Double = 0.75) -> [GameReading.Line] {
        [gline(name, gbox(left, top, left + 0.2, top + 0.03))] +
            body.enumerated().map { gline($0.element, gbox(left, top + 0.035 + 0.035 * Double($0.offset), left + 0.25, top + 0.065 + 0.035 * Double($0.offset))) }
    }

    func testCardRecognition() {
        typealias C = GameReading.Cards
        XCTAssertEqual(C.card(card("Donnie", ["See you at the pier tonight."]))?.name, "Donnie")
        XCTAssertNil(C.card(card("TOMAS: Move.", ["Quick, before the guards turn."])))
        XCTAssertNil(C.card(card("Okay.", ["Let's grab a drink later."])))
        XCTAssertNil(C.card([gline("Lucia", gbox(0.7, 0.8, 0.8, 0.83))]))
        XCTAssertNotNil(C.card(card("Chuck's Gun Shop", ["Your order is ready for pickup."])))
        XCTAssertNotNil(C.card(card("Brian", ["Thanks!"])))
        XCTAssertNil(C.card(card("Brian", ["Thanks!"], left: 0.3)))
        XCTAssertTrue(C.isList(card("Donnie", ["Hey what's up...", "Brian", "See you there..."])))
        XCTAssertEqual(C.tidy(card("✓✓ Donnie", ["See you at the pier.", "→ Cal"])).map(\.text), ["Donnie", "See you at the pier."])
    }

    func testCallCards() {
        typealias C = GameReading.Cards
        XCTAssertEqual(C.call(card("Harbor Cabs", ["Calling..."]))?.status, "aranıyor…")
        XCTAssertEqual(C.call(card("Harbor Cabs", ["Incoming call"]))?.status, "seni arıyor…")
        XCTAssertEqual(C.call(card("Harbor Cabs", ["Call ended."]))?.status, "arama bitti")
        XCTAssertEqual(C.call(card("Harbor Cabs", ["00:05"]))?.status, "")
        XCTAssertNil(C.call(card("Harbor Cabs", ["We should split the reward now."])))
        let el = C.layout(C.call(card("Harbor Cabs", ["Calling"]))!)
        XCTAssertEqual(el?.text, "Harbor Cabs aranıyor…")
        XCTAssertEqual(el?.style.italic, true)
        XCTAssertNil(C.layout(C.call(card("Harbor Cabs", ["00:05"]))!))
    }

    func testCardRepeats() {
        XCTAssertTrue(GameReading.Cards.repeats("See you at the pier", card: "See you at the pier tonight."))
        XCTAssertFalse(GameReading.Cards.repeats("Who lit the fire?", card: "See you at the pier tonight."))
        XCTAssertFalse(GameReading.Cards.repeats("Thanks a lot", card: "Thanks!"))
    }

    func testCardPresenter() {
        var p = GameReading.CardPresenter()
        let c = GameReading.Cards.card(card("Donnie", ["b Bucked You $50 for the job."]))!
        XCTAssertEqual(p.observe(c, phoneSeenRecently: false, now: 0), .none)
        XCTAssertEqual(p.observe(c, phoneSeenRecently: false, now: 100), .translate("Bucked You $50 for the job."))
        p.translated(name: "Donnie", message: "Bucked You $50 for the job.", translation: "TR")
        XCTAssertEqual(p.observe(c, phoneSeenRecently: false, now: 200), .none)
        XCTAssertEqual(p.observe(nil, phoneSeenRecently: false, now: 3_100), .none)
        XCTAssertEqual(p.observe(nil, phoneSeenRecently: false, now: 3_200), .remove)
        var q = GameReading.CardPresenter()
        XCTAssertEqual(q.observe(c, phoneSeenRecently: true, now: 0), .none)
        let layout = GameReading.Cards.layout(c, translation: "İş için 50 $ yolladım.")!
        XCTAssertEqual(layout.style.background, "#eef0f5")
        XCTAssertTrue(layout.text.hasPrefix("Donnie: "))
        XCTAssertLessThan(layout.box.bottom, c.box!.top)
    }

    // MARK: Köşeler (§12)

    typealias K = GameReading.Corners

    func testCornerPlacesAndInterval() {
        XCTAssertEqual(K.intervalMs(menuOpen: true), 600)
        XCTAssertEqual(K.intervalMs(menuOpen: false), 1_500)
        XCTAssertEqual(K.places(round: 0, questLine: 0.9, menuSeenRecently: false).map(\.0), [.topLeft, .questStrip, .menuSearch])
        XCTAssertEqual(K.places(round: 1, questLine: nil, menuSeenRecently: false).map(\.0), [.topLeft])
        XCTAssertEqual(K.places(round: 1, questLine: nil, menuSeenRecently: true).map(\.0), [.topLeft, .menuSearch])
        XCTAssertEqual(K.menuScale(pixelWidth: 2560), 0.5)
    }

    func testMenuScreen() {
        XCTAssertTrue(K.isMenuScreen(["SELA & IVO MAP BRIEF PROGRESS"]))
        XCTAssertTrue(K.isMenuScreen(["ii Map", "Game", "Store"]))
        XCTAssertFalse(K.isMenuScreen(["We need a better map.", "Game on."]))
        XCTAssertTrue(K.isMenuScreen(["SPEED", "ACCELERATION", "ASPHALT HANDLING"]))
    }

    func testMenuLineCleaning() {
        let cases = [("⊙ Store", "Store"), ("0] Photo Studio", "Photo Studio"), ("1 Help", "Help"), ("i Settings", "Settings"),
                     ("ii Map", "Map"), ("Go Home", "Go Home"), ("i Ayarlar", "Ayarlar"), ("Chapter 1", "Chapter 1")]
        for (i, o) in cases { XCTAssertEqual(K.cleanMenuLine(i), o, i) }
        XCTAssertEqual(K.menuLineTurkish("Settings"), "Ayarlar")
        XCTAssertEqual(K.menuLineTurkish("CHAPTER 1"), "Bölüm 1")
        XCTAssertNil(K.menuLineTurkish("Open the hatch"))
    }

    func testMenuGroups() {
        let left = ["Map", "Game", "Store", "Help"].enumerated().map { gline($0.element, gbox(0.05, 0.2 + 0.06 * Double($0.offset), 0.15, 0.24 + 0.06 * Double($0.offset))) }
        let right = ["GONE FISHING", "Retry Checkpoint", "Restart Mission"].enumerated()
            .map { gline($0.element, gbox(0.6 + 0.02 * Double($0.offset), 0.2 + 0.06 * Double($0.offset), 0.9, 0.24 + 0.06 * Double($0.offset))) }
        let groups = K.menuGroups(left + right)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.count).sorted(), [3, 4])
    }

    func testTopLeftBox() {
        let lines = [gline("BROTHER HALLOWAY", gbox(0.03, 0.05, 0.25, 0.08)), gline("WHO KEEPS THE LANTERN", gbox(0.03, 0.09, 0.30, 0.12))]
        XCTAssertEqual(K.topLeftLines(lines).count, 2)
        XCTAssertEqual(K.topLeftLines([gline("grizzlies", gbox(0.03, 0.05, 0.12, 0.08))]), [])
        XCTAssertEqual(K.topLeftLines([gline("◆ Escape the mine", gbox(0.03, 0.05, 0.25, 0.08))]).count, 1)
        XCTAssertTrue(K.isMapList([gline("STORY"), gline("Find the ranch")]))
        XCTAssertTrue(K.isMapList([gline("◆ Ranch"), gline("◆ Mine")]))
        let el = K.topLeftElement(box: gbox(0.03, 0.05, 0.30, 0.12), lineHeight: 0.03, header: "KARDEŞ HALLOWAY", body: "Feneri tutan")
        XCTAssertEqual(el.text, "KARDEŞ HALLOWAY · Feneri tutan")
        XCTAssertEqual(el.box.top, 0.132, accuracy: 1e-9)
        XCTAssertEqual(el.style.background, "#1c1c24")
    }

    func testQuestStripFilter() {
        let lines = [gline("Go to Mira's cabin", gbox(0.38, 0.93, 0.62, 0.96)), gline("BRENNA: Run!", gbox(0.4, 0.93, 0.6, 0.96)),
                     gline("PHOTO MODE", gbox(0.85, 0.93, 0.97, 0.96)), gline("Let's head back now.", gbox(0.3, 0.93, 0.7, 0.96))]
        let kept = K.questStripLines(lines, subtitle: "Let's head back now.", subtitleBox: nil)
        XCTAssertEqual(kept.map(\.text), ["Go to Mira's cabin"])
    }

    func testCornerTracker() {
        var t = GameReading.CornerTracker(place: .topLeft)
        let s = "Pull the lever to lower the bridge"
        XCTAssertEqual(t.observe(s, menuOpen: false, now: 0), .none)
        XCTAssertEqual(t.observe(s, menuOpen: false, now: 1_500), .translate(s))
        t.translated(source: s, translation: "TR")
        XCTAssertEqual(t.observe(s, menuOpen: false, now: 3_000), .none)
        for i in 1...3 { XCTAssertEqual(t.observe(nil, menuOpen: false, now: 3_000 + i * 1_500), .none) }
        XCTAssertEqual(t.observe(nil, menuOpen: false, now: 9_000), .remove)
        XCTAssertEqual(t.observe(s, menuOpen: false, now: 10_500), .none)
        XCTAssertEqual(t.observe(s, menuOpen: false, now: 12_000), .show(source: s, translation: "TR"))
        // Küçük harfsiz tabela ve kısa yazı çevrilmez.
        var u = GameReading.CornerTracker(place: .topLeft)
        _ = u.observe("YARD SALE TODAY ONLY", menuOpen: false, now: 0)
        XCTAssertEqual(u.observe("YARD SALE TODAY ONLY", menuOpen: false, now: 1), .none)
        // PS5'in Türkçe ekranı: 15 sn sessizlik.
        var v = GameReading.CornerTracker(place: .questStrip)
        XCTAssertEqual(v.observe("Ayarları değiştir", menuOpen: true, now: 0), .none)
        XCTAssertEqual(v.observe("Open the door", menuOpen: true, now: 1_000), .none)
        XCTAssertEqual(v.observe("Open the door", menuOpen: true, now: 15_001), .translate("Open the door"))
    }

    // MARK: İpuçları (§13)

    func testHints() {
        XCTAssertTrue(GameReading.Hints.isTranslatable("Hold L1 to open the crafting wheel"))
        XCTAssertFalse(GameReading.Hints.isTranslatable("✕ Select ○ Back"))
        XCTAssertFalse(GameReading.Hints.isTranslatable("R2 Swing"))
        XCTAssertEqual(GameReading.Hints.key("Hold R1 to show the list"), GameReading.Hints.key("Hold (R1) to show the list"))

        var h = GameReading.Hints()
        let l = gline("Hold L1 to open the crafting wheel", gbox(0.35, 0.7, 0.65, 0.74))
        let below = gline("Press ✕ to ask the guard", gbox(0.35, 0.95, 0.65, 0.98))
        let first = h.observe([l, below], questLine: 0.9, menuOpen: false)
        XCTAssertEqual(first.translate, l)
        XCTAssertNil(h.observe([l], questLine: 0.9, menuOpen: false).translate) // çeviri sürüyor
        let el = h.translated(l, turkish: "Üretim çarkını açmak için L1'i basılı tut")!
        XCTAssertLessThan(el.box.bottom, l.box!.top)
        XCTAssertEqual(el.box.midX, 0.5, accuracy: 0.01)
        XCTAssertNil(h.observe([l], questLine: 0.9, menuOpen: false).translate) // anahtar değişmedi
        let again = h.translated(l, turkish: "Üretim çarkını açmak için L1'i basılı tut")!
        XCTAssertEqual(again.box, el.box)
        XCTAssertEqual(h.observe([l], questLine: 0.9, menuOpen: true).removed, ["hold to open the crafting wheel"])
    }

    // MARK: Ekranı çevir grupları (§16)

    func testScreenGroups() {
        typealias G = GameReading.ScreenGroups
        let gs = G.groups([gline("OBJECTIVE", gbox(0.1, 0.1, 0.3, 0.13)), gline("Reach the tower before", gbox(0.1, 0.14, 0.4, 0.17)),
                           gline("the storm hits.", gbox(0.1, 0.18, 0.38, 0.21)), gline("Far away text here", gbox(0.6, 0.6, 0.9, 0.63))])
        XCTAssertEqual(gs.count, 2)
        XCTAssertEqual(G.parts(gs[0].lines.map(\.text)), ["OBJECTIVE", "Reach the tower before the storm hits."])
        let p = G.protectIcons("Hold ✕ to jump")!
        XCTAssertEqual(p.text, "Hold [1] to jump")
        XCTAssertEqual(G.restoreIcons("Zıplamak için [1] basılı tut", icons: p.icons), "Zıplamak için ✕ basılı tut")
        XCTAssertEqual(G.restoreIcons("Zıplamak için basılı tut", icons: p.icons), "✕ Zıplamak için basılı tut")
        XCTAssertNil(G.protectIcons("✕ ○"))
        XCTAssertEqual(G.durationMs(letters: 10), 12_000)
        XCTAssertEqual(G.durationMs(letters: 200), 18_000)
        XCTAssertEqual(G.durationMs(letters: 2_000), 60_000)
    }

    // MARK: Ek alanlar (§11)

    let quest = GameReading.ExtraArea(id: "q", name: "Görev", box: GameReading.ExtraArea.Preset.quest.box)

    func makeAreas(_ script: [[GameReading.Line]], pack: [String: String] = [:]) -> (GameReading.ExtraAreaReader, ScriptedReader, FakeElementTranslator, GameReading.ManualClock) {
        let reader = ScriptedReader(script)
        let tr = FakeElementTranslator(pack: pack)
        let clock = GameReading.ManualClock()
        return (GameReading.ExtraAreaReader(ocr: GameReading.OCR(reader: reader), translator: tr, clock: clock), reader, tr, clock)
    }

    func shownTexts(_ c: [GameReading.ExtraAreaReader.Change]) -> [String] {
        c.compactMap { if case let .show(e) = $0 { return e.text }; return nil }
    }

    func testAreaNeedsTwoRoundsAndReadsOnce() async {
        let (areas, reader, tr, clock) = makeAreas([[gline("Find the healer", gbox(0.1, 0.1, 0.8, 0.2))]])
        let r1 = await areas.round(FakeFrame(10), areas: [quest])
        XCTAssertEqual(shownTexts(r1), [])
        clock.advance(1_000)
        let r2 = await areas.round(FakeFrame(10), areas: [quest])
        XCTAssertEqual(shownTexts(r2), ["TR: Find the healer"])
        if case let .show(e) = r2[0] { XCTAssertTrue(e.box.left >= quest.box.left && e.box.bottom <= quest.box.bottom) }
        for _ in 0..<2 { clock.advance(1_000); _ = await areas.round(FakeFrame(10), areas: [quest]) }
        XCTAssertEqual(reader.callCount, 1)
        XCTAssertEqual(tr.requests.count, 1)
    }

    func testAreaRoundIntervalIsOneSecond() async {
        let (areas, reader, _, clock) = makeAreas([[gline("Find the healer")], [gline("x")]])
        _ = await areas.round(FakeFrame(10), areas: [quest])
        clock.advance(999)
        _ = await areas.round(FakeFrame(20), areas: [quest])
        XCTAssertEqual(reader.callCount, 1)
    }

    func testAreaMovingBackgroundTranslatesOnce() async {
        let l = gline("Talk to Brenna", gbox(0.1, 0.1, 0.8, 0.2))
        let (areas, reader, tr, clock) = makeAreas(Array(repeating: [l], count: 5))
        var sent: [String] = []
        for f in [10, 60, 110, 160, 210] {
            sent += shownTexts(await areas.round(FakeFrame(f), areas: [quest]))
            clock.advance(1_000)
        }
        XCTAssertEqual(reader.callCount, 5)
        XCTAssertEqual(tr.requests.count, 1)
        XCTAssertEqual(sent, ["TR: Talk to Brenna"])
    }

    func testAreaChangesAndClears() async {
        let a = gline("Talk to Brenna", gbox(0.1, 0.1, 0.8, 0.2)), b = gline("Meet Brenna at the pier", gbox(0.1, 0.1, 0.8, 0.2))
        let (areas, _, _, clock) = makeAreas([[a], [b], []])
        var all: [GameReading.ExtraAreaReader.Change] = []
        for f in [10, 10, 90, 90, 200, 200] {
            all += await areas.round(FakeFrame(f), areas: [quest])
            clock.advance(1_000)
        }
        XCTAssertEqual(shownTexts(all), ["TR: Talk to Brenna", "TR: Meet Brenna at the pier"])
        XCTAssertEqual(all.last, .remove(id: "q"))
    }

    func testAreaIgnoresHintsAndNumbers() async {
        let (areas, _, tr, clock) = makeAreas(Array(repeating: [gline("R2 Swing"), gline("23m")], count: 2))
        var all: [GameReading.ExtraAreaReader.Change] = []
        for f in [10, 20] { all += await areas.round(FakeFrame(f), areas: [quest]); clock.advance(1_000) }
        XCTAssertEqual(all, [])
        XCTAssertEqual(tr.requests.count, 0)
    }

    func testAreaUsesPackFirst() async {
        let lines = [gline("New message", gbox(0.1, 0.1, 0.5, 0.15)), gline("Ring me back when you can.", gbox(0.1, 0.16, 0.8, 0.21))]
        let (areas, _, tr, clock) = makeAreas([lines, lines], pack: ["New message": "Yeni mesaj"])
        var all: [GameReading.ExtraAreaReader.Change] = []
        for f in [10, 20] { all += await areas.round(FakeFrame(f), areas: [quest]); clock.advance(1_000) }
        XCTAssertEqual(shownTexts(all), ["Yeni mesaj\nTR: Ring me back when you can."])
        XCTAssertEqual(tr.requests, [["Ring me back when you can."]])
    }

    func testAreaSameTextNewPlaceIsResent() async {
        let a = gline("Talk to Brenna", gbox(0.1, 0.1, 0.8, 0.2)), moved = gline("Talk to Brenna", gbox(0.1, 0.5, 0.8, 0.6))
        let (areas, _, tr, clock) = makeAreas([[a], [a], [moved], [moved]])
        var all: [GameReading.ExtraAreaReader.Change] = []
        for f in [10, 20, 30, 40] { all += await areas.round(FakeFrame(f), areas: [quest]); clock.advance(1_000) }
        XCTAssertEqual(shownTexts(all), ["TR: Talk to Brenna", "TR: Talk to Brenna"])
        XCTAssertEqual(tr.requests.count, 1)
    }

    func testAreaDecodingWithoutBoxGetsQuestPreset() throws {
        let a = try JSONDecoder().decode(GameReading.ExtraArea.self, from: Data(#"{"id":"x","name":"Eski"}"#.utf8))
        XCTAssertEqual(a.box, GameReading.ExtraArea.Preset.quest.box)
    }

    // MARK: Yığın ve sarma (§17)

    func testStackTimings() {
        var s = GameReading.SubtitleStack()
        s.show("Kapıyı aç.", durationMs: 4_000, at: 0)
        XCTAssertEqual(s.visible(at: 3.9), ["Kapıyı aç."])
        XCTAssertEqual(s.visible(at: 4), [])

        s.show("Evet.", durationMs: 100, at: 10)
        XCTAssertEqual(s.visible(at: 11.1), ["Evet."])
        XCTAssertEqual(s.visible(at: 11.2), [])

        s.show("Evet.", durationMs: 0, at: 20)
        XCTAssertEqual(s.visible(at: 22.29), ["Evet."])
        XCTAssertEqual(s.visible(at: 22.31), [])
    }

    func testStackRaisesPreviousLines() {
        var s = GameReading.SubtitleStack()
        s.show("Birinci", durationMs: 8_000, at: 0)
        s.show("İkinci", durationMs: 8_000, at: 0.5)
        s.show("Üçüncü", durationMs: 8_000, at: 1)
        XCTAssertEqual(s.visible(at: 1), ["Birinci", "İkinci", "Üçüncü"])
        s.show("Dördüncü", durationMs: 8_000, at: 1.5)
        XCTAssertEqual(s.visible(at: 1.5), ["İkinci", "Üçüncü", "Dördüncü"])

        var off = GameReading.SubtitleStack()
        off.stackAbove = false
        off.show("Birinci", durationMs: 8_000, at: 0)
        off.show("İkinci", durationMs: 8_000, at: 0.5)
        XCTAssertEqual(off.visible(at: 0.5), ["İkinci"])

        var late = GameReading.SubtitleStack()
        late.show("Birinci", durationMs: 8_000, at: 0)
        late.show("İkinci", durationMs: 8_000, at: 2)
        XCTAssertEqual(late.visible(at: 2), ["İkinci"])
    }

    func testStackFadesPrevious() {
        var s = GameReading.SubtitleStack()
        s.show("Birinci", durationMs: 8_000, at: 0)
        s.show("İkinci", durationMs: 8_000, at: 1)
        XCTAssertEqual(s.aboveOpacity(at: 2.4), 1)
        XCTAssertLessThan(s.aboveOpacity(at: 2.6), 1)
        XCTAssertEqual(s.visible(at: 2.9), ["İkinci"])
        XCTAssertEqual(s.visible(at: 8.99), ["İkinci"])
        XCTAssertEqual(s.visible(at: 9), [])
    }

    func testStackSameLineReplaceAndParagraph() {
        var s = GameReading.SubtitleStack()
        s.show("Kapı", durationMs: 8_000, at: 0)
        s.show("Kapı artık kıpırdamıyor.", durationMs: 8_000, at: 0.5)
        XCTAssertEqual(s.visible(at: 0.5), ["Kapı artık kıpırdamıyor."])

        var r = GameReading.SubtitleStack()
        r.show("Birinci", durationMs: 8_000, at: 0)
        r.show("Vaktimiz yok", durationMs: 8_000, at: 0.5)
        r.show("Buna ayıracak vaktimiz yok, ufaklık.", durationMs: 8_000, at: 0.8, replace: true)
        XCTAssertEqual(r.visible(at: 0.8), ["Birinci", "Buna ayıracak vaktimiz yok, ufaklık."])

        var p = GameReading.SubtitleStack()
        p.show("Birinci", durationMs: 8_000, at: 0)
        p.show("GÖREV\n• Feneri bul", durationMs: 8_000, at: 0.5, paragraph: true)
        XCTAssertEqual(p.visible(at: 0.5), ["GÖREV\n• Feneri bul"])
    }

    func testStackClear() {
        var s = GameReading.SubtitleStack()
        s.show("Kapıyı aç.", durationMs: 15_000, at: 0)
        s.clear(at: 1)
        XCTAssertEqual(s.visible(at: 2.5), ["Kapıyı aç."])
        XCTAssertEqual(s.visible(at: 2.61), [])

        var t = GameReading.SubtitleStack()
        t.show("Birinci", durationMs: 8_000, at: 0)
        t.show("İkinci", durationMs: 15_000, at: 1)
        t.clear(at: 4)
        XCTAssertEqual(t.visible(at: 4), [])

        var u = GameReading.SubtitleStack()
        u.show("Birinci", durationMs: 8_000, at: 0)
        u.show("İkinci", durationMs: 8_000, at: 0.5)
        u.removeAll()
        XCTAssertEqual(u.visible(at: 0.5), [])
    }

    func testSameLine() {
        typealias S = GameReading.SubtitleStack
        XCTAssertTrue(S.sameLine("Kapıyı aç!", "kapıyı aç."))
        XCTAssertTrue(S.sameLine("Kapı", "Kapı artık…"))
        XCTAssertFalse(S.sameLine("Evet", "Hayır"))
        XCTAssertTrue(S.sameLine("أين المخيم؟", "أين المخيم"))
        XCTAssertTrue(S.sameLine("سيلا، انتظر", "سيلا انتظر"))
        XCTAssertTrue(S.sameLine("Kapıyı aç!", "Kapıyıaç"))
        XCTAssertTrue(S.sameLine("Kapıyı a", "Kapıyı aç!"))
        XCTAssertFalse(S.sameLine("No!", "Not now!"))
    }

    func testWrap() {
        let short = GameReading.Wrap.wrap("Gitmeliyiz, hemen.")
        XCTAssertEqual(short.lines, ["Gitmeliyiz, hemen."])
        XCTAssertEqual(short.scale, 1)
        let long = GameReading.Wrap.wrap("BRENNA: Bu gece sırtı aşmamız lazım yoksa şafak sökmeden bizi yakalarlar.")
        XCTAssertEqual(long.lines.count, 2)
        XCTAssertTrue(long.lines[0].hasPrefix("BRENNA: Bu"))
        let huge = GameReading.Wrap.wrap(String(repeating: "kelime ", count: 30).trimmingCharacters(in: .whitespaces))
        XCTAssertEqual(huge.lines.count, 3)
        XCTAssertEqual(huge.scale, 0.75)
        XCTAssertEqual(GameReading.Wrap.wrap("Bir\nİki").lines, ["Bir", "İki"])
    }

    // MARK: Buzlu zemin ve aydınlık (§15, §4.7)

    func testFrostAndBrightness() throws {
        let img = solidImage(width: 1280, height: 720, gray: 0.5)
        // Renk alanı dönüşümü değeri biraz oynatır; sıralama ve aralık önemli.
        let mid = GameReading.sceneBrightness(img)!
        XCTAssertEqual(mid, 0.55, accuracy: 0.08)
        XCTAssertLessThan(GameReading.sceneBrightness(solidImage(width: 320, height: 180, gray: 0.1))!, mid)
        XCTAssertGreaterThan(GameReading.sceneBrightness(solidImage(width: 320, height: 180, gray: 0.9))!, mid)
        XCTAssertEqual(GameReading.Frost.expanded(gbox(0.01, 0.9, 0.5, 0.99)), gbox(0, 0.865, 0.54, 1))
        let b64 = try XCTUnwrap(GameReading.Frost.background(img, box: gbox(0.3, 0.8, 0.7, 0.9)))
        let data = try XCTUnwrap(Data(base64Encoded: b64))
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8]) // JPEG
    }
}
