// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

final class GameReadingReaderTests: XCTestCase {
    typealias C = GameReading.FilterChain

    // MARK: Süzgeç sırası (§6)

    func ctx(_ now: Int = 0, area: GameReading.Box = .full) -> C.Context { C.Context(now: now, area: area) }

    func testOnlySubtitleIsTranslatedHintGoesToHints() {
        var c = C()
        var x = ctx()
        x.questLine = nil
        let r = c.run([gline("Let's head back now.", gbox(0.2, 0.6, 0.8, 0.7)), gline("R2 Swing", gbox(0.85, 0.9, 0.98, 0.95))], x)
        XCTAssertEqual(r.text, "Let's head back now.")
        XCTAssertEqual(r.hints.map(\.text), ["R2 Swing"])
    }

    func testQuestLineKeepsSpeakerAndContinuation() {
        var c = C()
        var x = ctx()
        x.questLine = 0.895
        let lines = [gline("BRENNA: Hold the door", gbox(0.3, 0.88, 0.7, 0.91)),
                     gline("before the storm hits.", gbox(0.32, 0.915, 0.68, 0.945)),
                     gline("Go to the stables now", gbox(0.35, 0.96, 0.65, 0.99))]
        let r = c.run(lines, x)
        XCTAssertEqual(r.text, "BRENNA: Hold the door\nbefore the storm hits.")
    }

    func testStaleLineDroppedOnlyBesideNewOne() {
        var c = C()
        let old = gline("Welcome to the old mill, traveler.", gbox(0.3, 0.6, 0.7, 0.65))
        XCTAssertEqual(c.run([old], ctx(0)).text, old.text)
        XCTAssertEqual(c.run([old], ctx(9_500)).text, old.text) // tek başına: dokunulmaz
        let new = gline("Who goes there?", gbox(0.3, 0.7, 0.7, 0.75))
        XCTAssertEqual(c.run([old, new], ctx(9_600)).text, "Who goes there?")
    }

    func testMenuFlagEmptiesReading() {
        var c = C()
        var x = ctx()
        x.menuOpen = true
        let r = c.run([gline("Let's head back now.", gbox(0.2, 0.6, 0.8, 0.7))], x)
        XCTAssertNil(r.text)
        XCTAssertEqual(r.emptied, "menu")
    }

    func testPhoneLinesAndCenterRule() {
        var c = C()
        var x = ctx()
        x.phoneGame = true
        x.questLine = nil
        x.phone = GameReading.PhoneContext(box: gbox(0.7, 0.3, 0.95, 0.8))
        let lines = [gline("Hey, you found Mira's map.", gbox(0.72, 0.5, 0.93, 0.55)),
                     gline("Sale today only, come inside.", gbox(0.05, 0.86, 0.3, 0.9)),
                     gline("Who sent you here?", gbox(0.35, 0.86, 0.65, 0.9))]
        XCTAssertEqual(c.run(lines, x).text, "Who sent you here?")
        XCTAssertEqual(GameReading.PhoneContext(box: gbox(0.7, 0.3, 0.95, 0.6)).maskBox!.bottom, 0.76, accuracy: 1e-9)
    }

    func testPhoneSeenTextIsDropped() {
        var c = C()
        var x = ctx()
        x.questLine = nil
        x.phone = GameReading.PhoneContext(recentTexts: ["See you at the pier tonight, bring cash"], textSeenRecently: true)
        let r = c.run([gline("See you at the pier", gbox(0.3, 0.85, 0.7, 0.9)), gline("You got it, boss.", gbox(0.3, 0.91, 0.7, 0.95))], x)
        XCTAssertEqual(r.text, "You got it, boss.")
    }

    func testMessageCardEmptiesReading() {
        var c = C()
        var x = ctx()
        x.cardsEnabled = true
        x.questLine = nil
        let lines = [gline("Donnie", gbox(0.7, 0.75, 0.8, 0.78)), gline("See you at the pier tonight.", gbox(0.7, 0.79, 0.95, 0.82))]
        let r = c.run(lines, x)
        XCTAssertNil(r.text)
        XCTAssertEqual(r.card?.name, "Donnie")
        // Kart 6 sn içinde tekrar okunursa (adsız) yine boş.
        XCTAssertNil(c.run([gline("See you at the pier tonight.", gbox(0.3, 0.85, 0.7, 0.9))], ctx(1_000).with { $0.cardsEnabled = true; $0.questLine = nil }).text)
    }

    func testCallCardEmptiesReading() {
        var c = C()
        var x = ctx()
        x.cardsEnabled = true
        x.questLine = nil
        let r = c.run([gline("Paradise Taxi", gbox(0.4, 0.8, 0.6, 0.83)), gline("Calling...", gbox(0.4, 0.84, 0.6, 0.87))], x)
        XCTAssertNil(r.text)
        XCTAssertEqual(r.call?.status, "aranıyor…")
        XCTAssertNil(c.run([gline("Paradise Taxi", gbox(0.4, 0.8, 0.6, 0.83))], ctx(2_000).with { $0.cardsEnabled = true; $0.questLine = nil }).text)
    }

    func testBoxIsCenteredInFrame() {
        var c = C()
        let area = gbox(0.14, 0.62, 0.86, 0.97)
        let r = c.run([gline("Let's head back now.", gbox(0.2, 0.6, 0.7, 0.7))], ctx(area: area))
        let b = r.box!
        XCTAssertEqual(b.left + b.right, 1, accuracy: 1e-9)
    }

    // MARK: Okuyucu (uçtan uca, sahte saat)

    func makeReader(_ script: [[GameReading.Line]], pack: Set<String> = [], store: GameReading.PlacementStore? = nil)
        -> (GameReading.Reader, GameReading.ManualClock) {
        let clock = GameReading.ManualClock()
        var cfg = GameReading.Reader.Configuration(gameKey: "test")
        cfg.plan = GameReading.ReadPlan(threshold: -1, reuseLimit: 0, deepEvery: 0)
        cfg.region = GameReading.Region(preset: .fullFrame)
        let reader = GameReading.Reader(textReader: ScriptedReader(script), clock: clock, configuration: cfg,
                                        placementStore: store, isInPack: { pack.contains($0) })
        return (reader, clock)
    }

    func subtitleEvents(_ events: [GameReading.Event]) -> [String] {
        events.compactMap {
            switch $0 {
            case let .subtitleStarted(s): return "başladı:" + s.text
            case let .subtitleUpdated(s): return "uzadı:" + s.text
            case let .subtitleCorrected(s): return "düzeldi:" + s.text
            case let .subtitleRestored(s): return "döndü:" + s.text
            case let .subtitleEnded(id): return "bitti:\(id)"
            default: return nil
            }
        }
    }

    func run(_ reader: GameReading.Reader, _ clock: GameReading.ManualClock, frames: Int, each ms: Int) async -> [String] {
        var all: [String] = []
        for i in 0..<frames {
            if i > 0 { clock.advance(ms) }
            all += subtitleEvents(await reader.process(FakeFrame(i)).events)
        }
        return all
    }

    let sub = gline("Hold the rope.", gbox(0.3, 0.85, 0.7, 0.9))

    func testStartsThenEnds() async {
        let (reader, clock) = makeReader([[sub], [sub], [], [], []])
        let events = await run(reader, clock, frames: 5, each: 400)
        XCTAssertEqual(events, ["başladı:Hold the rope.", "bitti:1"])
    }

    func testPartialLineWaitsThenGrowsIntoUpdate() async {
        let short = gline("Climb up", gbox(0.4, 0.85, 0.6, 0.9)), long = gline("Climb up the wall!", gbox(0.35, 0.85, 0.65, 0.9))
        let (reader, clock) = makeReader(Array(repeating: [short], count: 8) + [[long], [long]])
        let events = await run(reader, clock, frames: 10, each: 50)
        XCTAssertEqual(events, ["başladı:Climb up", "uzadı:Climb up the wall!"])
    }

    func testPartialReplacedBeforeSend() async {
        let short = gline("Climb up", gbox(0.4, 0.85, 0.6, 0.9)), long = gline("Climb up the wall!", gbox(0.35, 0.85, 0.65, 0.9))
        let (reader, clock) = makeReader([[short], [short]] + Array(repeating: [long], count: 8))
        let events = await run(reader, clock, frames: 10, each: 50)
        XCTAssertEqual(events, ["başladı:Climb up the wall!"])
    }

    func testRestoreEvent() async {
        let (reader, clock) = makeReader([[sub], [], [], [sub], [sub]])
        var all: [String] = []
        // Boş karelerde iz değişiyor (satırın yeri değişti): 800 ms sonra temizlenir.
        for (i, ms) in [0, 0, 800, 500, 0].enumerated() {
            clock.advance(ms)
            all += subtitleEvents(await reader.process(FakeFrame(i)).events)
        }
        XCTAssertEqual(all, ["başladı:Hold the rope.", "bitti:1", "döndü:Hold the rope."])
    }

    func testSubtitleCarriesSpeakerPartsAndBox() async {
        let l = gline("BRENNA: HOLD THE DOOR NOW.", gbox(0.3, 0.85, 0.7, 0.9))
        let (reader, _) = makeReader([[l]])
        let out = await reader.process(FakeFrame(1))
        guard case let .subtitleStarted(s)? = out.events.first else { return XCTFail("altyazı yok") }
        XCTAssertEqual(s.speaker, "BRENNA")
        XCTAssertEqual(s.parts.map(\.text), ["BRENNA: ", "Hold the door now."])
        XCTAssertEqual(s.box!.left + s.box!.right, 1, accuracy: 1e-9)
        XCTAssertTrue(out.didRead)
    }

    func testPackLineSkipsWaiting() async {
        let short = gline("Climb up", gbox(0.4, 0.85, 0.6, 0.9))
        let (reader, clock) = makeReader([[short], [short]], pack: ["Climb up"])
        let events = await run(reader, clock, frames: 2, each: 50)
        XCTAssertEqual(events, ["başladı:Climb up"])
    }

    func testGateSkipsWhileBusyAndPlanReuses() async {
        let clock = GameReading.ManualClock()
        let hang = HangingReader()
        var cfg = GameReading.Reader.Configuration()
        cfg.plan = .always
        let reader = GameReading.Reader(textReader: hang, clock: clock, configuration: cfg)
        let first = Task { await reader.process(FakeFrame(1)) }
        await hang.waitUntilStarted()
        let second = await reader.process(FakeFrame(2))
        XCTAssertTrue(second.skipped)
        clock.advance(45_000)
        let third = await reader.process(FakeFrame(3))
        XCTAssertTrue(third.stuck)
        hang.release()
        _ = await first.value
    }

    func testPlanReusesLastReading() async {
        let script = ScriptedReader([[sub]])
        let clock = GameReading.ManualClock()
        var cfg = GameReading.Reader.Configuration()
        cfg.region = GameReading.Region(preset: .fullFrame)
        let reader = GameReading.Reader(textReader: script, clock: clock, configuration: cfg)
        let a = await reader.process(FakeFrame(5))
        let b = await reader.process(FakeFrame(5))
        XCTAssertTrue(a.didRead)
        XCTAssertFalse(b.didRead)
        XCTAssertEqual(script.callCount, 1)
    }

    func testLearnsPlacementAndNarrowsArea() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = GameReading.PlacementStore(url: dir.appendingPathComponent("yer.json"))
        var script: [[GameReading.Line]] = []
        let texts = ["Hold the rope.", "Where did she go?", "We ride at dawn.", "Stay low now!", "I saw nothing at all.",
                     "Bring me the old map.", "They are coming for us.", "Quiet, both of you."]
        for t in texts { script += [[gline(t, gbox(0.3, 0.84, 0.7, 0.92))], []] }
        let (reader, clock) = makeReader(script, store: store)
        var learned = false
        for _ in 0..<16 {
            let out = await reader.process(FakeFrame(Int.random(in: 0...1000)))
            if out.events.contains(where: { if case .stripLearned = $0 { return true }; return false }) { learned = true; break }
            clock.advance(900)
        }
        XCTAssertTrue(learned)
        let area = await reader.readingArea
        XCTAssertEqual(area.top, 0.79, accuracy: 1e-9)
    }

    func testCornersDetectMenuAndTopLeft() async {
        let clock = GameReading.ManualClock()
        let reader = ScriptedReader { call in
            if call.area == GameReading.Corners.topLeftBox {
                return [gline("BROTHER HALLOWAY", gbox(0.05, 0.1, 0.6, 0.16)), gline("WHO KEEPS THE LANTERN", gbox(0.05, 0.18, 0.7, 0.24))]
            }
            if call.area == GameReading.Corners.menuSearchBox { return [gline("Map", gbox(0.1, 0.1, 0.2, 0.13)), gline("Store", gbox(0.1, 0.2, 0.2, 0.23))] }
            return []
        }
        let r = GameReading.Reader(textReader: reader, clock: clock)
        let events = await r.readCorners(FakeFrame(1))
        XCTAssertTrue(events.contains { if case let .corner(.topLeft, lines) = $0 { return lines.count == 2 }; return false })
        XCTAssertTrue(events.contains { if case .menuOpened = $0 { return true }; return false })
        let open = await r.menuOpen
        XCTAssertTrue(open)
        let early = await r.readCorners(FakeFrame(1))
        XCTAssertEqual(early, []) // aralık dolmadı
        clock.advance(600)
        let next = await r.readCorners(FakeFrame(1))
        XCTAssertTrue(next.contains { if case let .corner(.topLeft, lines) = $0 { return lines.isEmpty }; return false }) // menü açık
    }

    func testElementsBoard() {
        var b = GameReading.ElementsBoard()
        b.set(.init(kind: .hint, id: "a", box: .full, text: "x"))
        b.set(.init(kind: .corner, id: "top-left", box: .full, text: "y"))
        b.set(.init(kind: .hint, id: "a", box: .full, text: "z"))
        XCTAssertEqual(b.list.map(\.text), ["y", "z"])
        b.removeAll(kind: .hint)
        XCTAssertEqual(b.event, .screenElements([.init(kind: .corner, id: "top-left", box: .full, text: "y")]))
    }
}

extension GameReading.FilterChain.Context {
    func with(_ change: (inout Self) -> Void) -> Self { var c = self; change(&c); return c }
}
