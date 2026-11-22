// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

final class GameReadingDispatchTests: XCTestCase {
    typealias Q = GameReading.TranslationQueue
    typealias A = Q.Action

    // MARK: Bekletme (§8.3, §8.4)

    func testCompleteLineGoesAtOnce() {
        var g = GameReading.SendGate()
        XCTAssertEqual(g.onTranslate("Hold the rope.", box: nil, now: 0).map(\.text), ["Hold the rope."])
    }

    func testPartialLineWaitsThreeHundredMs() {
        var g = GameReading.SendGate()
        XCTAssertEqual(g.onTranslate("Climb up", box: nil, now: 50).count, 0)
        var sent: [String] = []
        var t = 50
        while t < 400 { t += 50; sent += g.onNone("Climb up", box: nil, now: t).map(\.text) }
        XCTAssertEqual(sent, ["Climb up"])
    }

    func testBrokenLineWaitsEightHundredMs() {
        var g = GameReading.SendGate()
        XCTAssertTrue(g.onTranslate("Gtt to th3 gate.", box: nil, now: 0).isEmpty)
        XCTAssertTrue(g.onNone(nil, box: nil, now: 799).isEmpty)
        XCTAssertEqual(g.onNone(nil, box: nil, now: 800).count, 1)
    }

    func testBetterReadingReplacesPending() {
        // `Climb up` ×2, `Climb up the wall!` → istenen yalnız `Climb up the wall!`.
        var g = GameReading.SendGate()
        var sent: [String] = []
        sent += g.onTranslate("Climb up", box: nil, now: 50).map(\.text)
        sent += g.onTranslate("Climb up the wall!", box: nil, now: 100).map(\.text)
        var t = 100
        while t < 500 { t += 50; sent += g.onNone("Climb up the wall!", box: nil, now: t).map(\.text) }
        XCTAssertEqual(sent, ["Climb up the wall!"])
    }

    func testPackLineSkipsWait() {
        var g = GameReading.SendGate(isInPack: { $0 == "Climb up" })
        XCTAssertEqual(g.onTranslate("Climb up", box: nil, now: 0).map(\.inPack), [true])
    }

    func testRecentRereadIsIgnored() {
        var g = GameReading.SendGate()
        _ = g.onTranslate("Lead the mule back to the stable.", box: nil, now: 0)
        XCTAssertTrue(g.onTranslate("Lead the mule back to the", box: nil, now: 500).isEmpty)
        XCTAssertNil(g.pending)
    }

    func testKeepsMissingCleanLines() {
        let g = GameReading.SendGate()
        XCTAssertEqual(g.keepMissingLines(new: "We made camp.", old: "We made camp.\nNobody followed us!"), "We made camp.\nNobody followed us!")
    }

    func testClearSendsPendingUnlessBroken() {
        var g = GameReading.SendGate()
        _ = g.onTranslate("Climb up", box: nil, now: 0)
        XCTAssertEqual(g.onClearOrRestore(now: 10).map(\.text), ["Climb up"])
        _ = g.onTranslate("Gtt th3 gate", box: nil, now: 20)
        XCTAssertTrue(g.onClearOrRestore(now: 30).isEmpty)
    }

    // MARK: Sıra (§8.5–8.8)

    func req(_ id: Int, _ text: String, pack: String? = nil) -> Q.Request { Q.Request(id: id, text: text, packTranslation: pack) }

    func translated(_ actions: [A]) -> [String] {
        actions.compactMap { if case let .translate(r) = $0 { return r.text }; return nil }
    }

    func shown(_ actions: [A]) -> [String] {
        actions.compactMap { if case let .show(_, t, _, _, _) = $0 { return t }; return nil }
    }

    func testOneTranslationAtATimeThenNext() {
        var q = Q()
        var all: [A] = []
        all += q.enqueue(req(1, "Hold the rope."), now: 0)
        all += q.enqueue(req(2, "Run!"), now: 100)
        XCTAssertEqual(translated(all), ["Hold the rope."])
        all += q.finished(id: 1, translation: "TR: Hold the rope.", now: 200)
        all += q.finished(id: 2, translation: "TR: Run!", now: 300)
        XCTAssertEqual(translated(all), ["Hold the rope.", "Run!"])
        XCTAssertEqual(shown(all), ["TR: Hold the rope.", "TR: Run!"])
    }

    func testOldestWaitingIsDropped() {
        var q = Q()
        var all: [A] = []
        for (i, t) in ["Hold the rope.", "Run!", "Stay low!", "Now!"].enumerated() { all += q.enqueue(req(i + 1, t), now: i * 100) }
        all += q.finished(id: 1, translation: "TR", now: 500)
        all += q.finished(id: 3, translation: "TR", now: 600)
        XCTAssertEqual(translated(all), ["Hold the rope.", "Stay low!", "Now!"])
    }

    func testDurationsAfterLateArrival() {
        var q = Q()
        var all: [A] = []
        all += q.enqueue(req(1, "Hold the rope."), now: 0)
        all += q.enqueue(req(2, "Run!"), now: 50)
        all += q.enqueue(req(3, "Stay low!"), now: 100)
        all += q.finished(id: 1, translation: "TR: Hold the rope.", now: 2_100)
        all += q.finished(id: 2, translation: "TR: Run!", now: 2_150)
        all += q.finished(id: 3, translation: "TR: Stay low!", now: 2_200)
        let durations = all.compactMap { a -> Int? in if case let .show(_, _, d, _, _) = a { return d }; return nil }
        XCTAssertEqual(durations, [2_000 + 60 * 18, 2_000 + 60 * 8, 15_000])
    }

    func testLateResultIsNotShown() {
        var q = Q()
        var all: [A] = []
        all += q.enqueue(req(1, "Hold the rope."), now: 0)
        all += q.enqueue(req(2, "Run!"), now: 50)
        all += q.finished(id: 1, translation: "TR: Hold the rope.", now: 2_650)
        all += q.finished(id: 2, translation: "TR: Run!", now: 2_700)
        XCTAssertEqual(shown(all), ["TR: Run!"])
    }

    func testRemovedLineShortDuration() {
        var q = Q()
        _ = q.enqueue(req(1, "Hold the rope."), now: 0)
        q.lineRemoved(id: 1, now: 850)
        let a = q.finished(id: 1, translation: "TR: Hold the rope.", now: 900)
        XCTAssertEqual(a, [.show(id: 1, text: "TR: Hold the rope.", durationMs: 2_000 + 18 * 60, replace: false, fromPack: false)])
        var late = Q()
        _ = late.enqueue(req(1, "Hold the rope."), now: 0)
        late.lineRemoved(id: 1, now: 850)
        XCTAssertEqual(shown(late.finished(id: 1, translation: "TR", now: 850 + 2_600)), [])
    }

    func testExtensionReplacesRunningTranslation() {
        var q = Q()
        var all: [A] = []
        all += q.enqueue(req(1, "Climb up"), now: 0)
        all += q.enqueue(req(2, "Climb up the wall!"), now: 100)
        XCTAssertEqual(translated(all), ["Climb up", "Climb up the wall!"])
        all += q.finished(id: 1, translation: "TR: Climb up", now: 200)
        all += q.finished(id: 2, translation: "TR: Climb up the wall!", now: 300)
        XCTAssertEqual(shown(all), ["TR: Climb up the wall!"])
    }

    func testReplaceFlag() {
        var q = Q()
        var flags: [Bool] = []
        for (i, t) in ["Climb up", "Climb up the wall!", "Stay low now!"].enumerated() {
            let a = q.enqueue(req(i + 1, t), now: i * 100) + q.finished(id: i + 1, translation: "TR: " + t, now: i * 100 + 10)
            flags += a.compactMap { if case let .show(_, _, _, r, _) = $0 { return r }; return nil }
        }
        XCTAssertEqual(flags, [false, true, false])
    }

    func testCancelsStaleTranslationAfterLateWindow() {
        var q = Q()
        _ = q.enqueue(req(1, "Hold the rope."), now: 0)
        _ = q.enqueue(req(2, "Run!"), now: 50)
        XCTAssertEqual(q.tick(now: 2_000), [])
        XCTAssertEqual(q.tick(now: 2_600), [.cancel(id: 1), .translate(req(2, "Run!"))])
        XCTAssertEqual(shown(q.finished(id: 2, translation: "TR: Run!", now: 2_700)), ["TR: Run!"])
    }

    func testOnScreenTranslationIsNeverCancelled() {
        var q = Q()
        _ = q.enqueue(req(1, "Hold the rope."), now: 0)
        XCTAssertEqual(q.tick(now: 10_000), [])
    }

    func testPackLineShowsAtOnceAndDropsSlowOnes() {
        var q = Q()
        var all: [A] = []
        all += q.enqueue(req(1, "Hold the rope."), now: 0)
        all += q.enqueue(req(2, "Stay low!", pack: "Alçakta kal!"), now: 100)
        all += q.finished(id: 1, translation: "TR: Hold the rope.", now: 300)
        XCTAssertEqual(shown(all), ["Alçakta kal!"])
    }

    func testPackHiddenOnlyForTurkishSource() {
        var q = Q()
        XCTAssertEqual(shown(q.enqueue(req(1, "Hey, Lu...", pack: "Hey, Lu..."), now: 0)), ["Hey, Lu..."])
        XCTAssertEqual(shown(q.enqueue(req(2, "Bağlantı kesildi.", pack: "Bağlantı kesildi."), now: 10)), [])
    }

    func testAlreadyTargetLanguageClearsOldTranslation() {
        var q = Q()
        var all = q.enqueue(req(1, "You doing okay?"), now: 0)
        all += q.finished(id: 1, translation: "İyi misin?", now: 10)
        all += q.enqueue(req(2, "Uzaktan Oynatma ile oturum açıldı"), now: 20)
        XCTAssertEqual(shown(all), ["İyi misin?"])
        XCTAssertTrue(all.contains(.hide(id: 1)))
        XCTAssertTrue(Q.looksTurkish("Uzaktan Oynatma ile oturum açıldı"))
        XCTAssertFalse(Q.looksTurkish("Okay, sure. Better than waiting herı"))
    }

    func testTranslationEqualToSourceIsNotShown() {
        var q = Q()
        let a = q.enqueue(req(1, "Kullanıcı Değiştir Bildirimler Açık"), now: 0)
        XCTAssertTrue(a.contains(.alreadyTarget(id: 1)))
        var p = Q(isTargetLanguage: { _ in false })
        _ = p.enqueue(req(1, "Add user"), now: 0)
        XCTAssertEqual(shown(p.finished(id: 1, translation: "Kullanıcı ekle", now: 10)), ["Kullanıcı ekle"])
        _ = p.enqueue(req(2, "OK"), now: 20)
        XCTAssertEqual(shown(p.finished(id: 2, translation: "OK", now: 30)), [])
    }

    func testBaselineRule() {
        var q = Q()
        let off = Q.Request(id: 1, text: "Choose a base color and pick two patterns.", offBaseline: true)
        XCTAssertEqual(q.enqueue(off, now: 0), [.proposeToPool(text: off.text)])
        let packOff = Q.Request(id: 2, text: "How bright the compass looks on screen.", packTranslation: "Pusulanın ekrandaki parlaklığı.", offBaseline: true)
        XCTAssertEqual(shown(q.enqueue(packOff, now: 10)), ["Pusulanın ekrandaki parlaklığı."])
        let chest = Q.Request(id: 3, text: "Chest.", packTranslation: "Sandık.", offBaseline: true)
        XCTAssertEqual(shown(q.enqueue(chest, now: 20)), [])
    }

    func testFailureOnScreenAsksToForget() {
        var q = Q()
        _ = q.enqueue(req(1, "Hold the rope."), now: 0)
        XCTAssertEqual(q.finished(id: 1, translation: nil, now: 10), [.failed(id: 1)])
    }

    // MARK: Konuşan adı (§10)

    typealias Sp = GameReading.Speaker

    func testSpeakerSplit() {
        XCTAssertEqual(Sp.split("BRENNA: Hold the door.")?.name, "BRENNA")
        XCTAssertEqual(Sp.split("BRENNA: Hold the door.")?.body, "Hold the door.")
        XCTAssertEqual(Sp.split("Ivo: I know a shortcut.")?.body, "I know a shortcut.")
        XCTAssertEqual(Sp.split("Mr. Kade：Go away.")?.name, "Mr. Kade")
        XCTAssertEqual(Sp.split("Mr. Kade：Go away.")?.body, "Go away.")
        XCTAssertEqual(Sp.split("OLD WOMAN : Hm.")?.name, "OLD WOMAN")
        XCTAssertEqual(Sp.split("BRENNA:We go.")?.body, "We go.")
        XCTAssertEqual(Sp.split("Brenna:\nHold the door.")?.body, "Hold the door.")
        for t in ["08:15 by the old pier.", "Wait for me at 08:15.", "HTTPS://example.com", "Ratio 16:9", "Tip: the well is dry.",
                  "Listen to me: stay back!", "Some Other Name Too: words", "Maximilianus Wolfensteinberg: Hi.", "BRENNA:"] {
            XCTAssertNil(Sp.split(t), t)
        }
    }

    func testSpeakerCompose() {
        XCTAssertEqual(Sp.compose(translation: "Kapıyı tut.", source: "BRENNA: Hold the door.", showNames: true), "BRENNA: Kapıyı tut.")
        XCTAssertEqual(Sp.compose(translation: "Kapıyı tut.", source: "BRENNA: Hold the door.", showNames: false), "Kapıyı tut.")
        XCTAssertEqual(Sp.compose(translation: "BRENNA: Kapıyı tut.", source: "BRENNA: Hold the door.", showNames: true), "BRENNA: Kapıyı tut.")
        XCTAssertEqual(Sp.compose(translation: "BRENNA: Evet.\nIVO: Hayır.", source: "BRENNA: Yes.\nIVO: No.", showNames: false), "Evet.\nHayır.")
        XCTAssertEqual(Sp.compose(translation: "Hedef: Deniz fenerine ulaş.", source: "Objective: Reach the lighthouse.", showNames: false), "Hedef: Deniz fenerine ulaş.")
    }

    func testParts() {
        func render(_ t: String) -> [String] { Sp.parts(t).map { ($0.translate ? "+" : "=") + $0.text } }
        XCTAssertEqual(render("Let's head\nhome, kid."), ["+Let's head home, kid."])
        XCTAssertEqual(render("SELA: Brother, look!"), ["=SELA: ", "+Brother, look!"])
        XCTAssertEqual(render("Brenna: Stay low.\nIvo: Right, sister."), ["=Brenna: ", "+Stay low.", "=\n", "=Ivo: ", "+Right, sister."])
        XCTAssertEqual(render("Old Woman: Who's there?"), ["=Old Woman: ", "+Who's there?"])
        XCTAssertEqual(render("Objective: Find the well."), ["+Objective: Find the well."])
        XCTAssertEqual(render("Kid! What was that? Ask Mr. Vale."), ["+Kid!", "= ", "+What was that?", "= ", "+Ask Mr. Vale."])
        XCTAssertEqual(render("Hold on... who was that?"), ["+Hold on... who was that?"])
        XCTAssertEqual(render("- Run!\n- Where?"), ["=- ", "+Run!", "=\n", "=- ", "+Where?"])
        XCTAssertEqual(render("Ask J. Vale now."), ["+Ask J. Vale now."])
    }

    func testCapitals() {
        let t = "THE BRIDGE IS FALLING, SELA. I SEE IT."
        XCTAssertEqual(Sp.fixCapitals(t), "The bridge is falling, sela. I see it.")
        XCTAssertEqual(Sp.fixCapitals(t, knownNames: ["sela"]), "The bridge is falling, Sela. I see it.")
        XCTAssertEqual(Sp.fixCapitals("RUN, OLD MAN!", knownNames: Sp.names(fromLabelsIn: "OLD MAN: Hm.")), "Run, Old Man!")
        XCTAssertEqual(Sp.fixCapitals("BOY!"), "BOY!")
        XCTAssertEqual(Sp.fixCapitals("Already fine."), "Already fine.")
    }

    // MARK: Altyazı yeri (§9)

    func testPlacementStripAndLines() {
        var p = GameReading.Placement()
        XCTAssertEqual(p.questLine, 0.895)
        XCTAssertFalse(p.record(gbox(0.2, 0.5, 0.8, 0.6)))
        for _ in 0..<7 { p.record(gbox(0.2, 0.84, 0.8, 0.92)) }
        XCTAssertNil(p.strip)
        XCTAssertEqual(p.questLine, 0.895)
        for _ in 0..<3 { p.record(gbox(0.2, 0.84, 0.8, 0.92)) }
        XCTAssertEqual(p.readTop!, 0.79, accuracy: 1e-9)
        XCTAssertNil(p.baseline)
        XCTAssertNil(p.questLine) // 0,92 + 0,08 ≥ 0,97: altyazı en dipte
        XCTAssertEqual(p.questLine(poolPriority: true), 0.935)
        p.record(gbox(0.2, 0.84, 0.8, 0.92)); p.record(gbox(0.2, 0.84, 0.8, 0.92))
        XCTAssertEqual(p.baseline!, 0.85, accuracy: 1e-9)
    }

    func testPlacementQuestLineFormula() {
        var p = GameReading.Placement()
        for _ in 0..<10 { p.record(gbox(0.2, 0.82, 0.8, 0.86)) }
        XCTAssertEqual(p.questLine!, 0.90, accuracy: 1e-9)
    }

    func testScatteredBottomsHaveNoBaseline() {
        var p = GameReading.Placement()
        for i in 0..<14 { p.record(gbox(0.2, 0.70, 0.8, 0.80 + 0.014 * Double(i))) }
        XCTAssertNil(p.baseline)
        XCTAssertEqual(GameReading.Placement(samples: Array(repeating: .init(top: 0.8, bottom: 0.9), count: 70)).samples.count, 60)
    }

    func testPlacementStoreWritesJSON() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("yer.json")
        let store = GameReading.PlacementStore(url: url)
        var learned = false
        for _ in 0..<8 { learned = store.record(gbox(0.2, 0.84, 0.8, 0.92), game: "oyun") || learned }
        XCTAssertTrue(learned)
        let again = GameReading.PlacementStore(url: url)
        XCTAssertEqual(again.placement(for: "oyun").samples.count, 8)
        XCTAssertEqual(again.placement(for: "başka").samples.count, 0)
        XCTAssertEqual(GameReading.Placement.gameKey(poolPriority: true, packGame: "x"), "gta-6")
        XCTAssertEqual(GameReading.Placement.gameKey(poolPriority: false, packGame: nil), "genel")
    }
}
