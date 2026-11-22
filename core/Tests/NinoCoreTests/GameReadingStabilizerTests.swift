// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

final class GameReadingStabilizerTests: XCTestCase {
    typealias S = GameReading.Similarity
    typealias R = GameReading.Stabilizer.Reaction

    /// Saat yazılmayan adımlarda saat ilerlemez.
    struct Run {
        var s = GameReading.Stabilizer()
        var now = 0
        mutating func feed(_ text: String?, after ms: Int = 0, box: GameReading.Box? = nil, fp: GameReading.Fingerprint? = nil) -> R {
            now += ms
            return s.observe(text, box: box, fingerprint: fp, now: now)
        }
        mutating func feed(_ texts: [String?], each ms: Int = 0) -> [R] { texts.map { feed($0, after: ms) } }
    }

    // MARK: Benzerlik (§7.3, §7.4)

    func testExtension() {
        XCTAssertTrue(S.isExtension("We can not stay long.", of: "We can not"))
        XCTAssertFalse(S.isExtension("We can not", of: "We can not stay long."))
        XCTAssertFalse(S.isExtension("We can not", of: "We can not"))
        XCTAssertTrue(S.isExtension("Then we sail east.", of: "Then"))
        XCTAssertFalse(S.isExtension("Then we sail east.", of: "east"))
        XCTAssertTrue(S.isExtension("Then we sail east.", of: "sail east"))
    }

    func testSameSubtitleFullLines() {
        XCTAssertFalse(S.isSameSubtitle("we need to climb the ridge", sentLines: ["We need to climb the ridge before the snow comes in"]))
        XCTAssertTrue(S.isSameSubtitle("we need to climb the ridge", sentLines: ["We need to climb the ridge", "before the snow comes in"]))
    }

    func testMeaningMarkers() {
        XCTAssertTrue(S.addsMeaningMarker("I couldn't find the key for you today.", to: "I could find the key for you today."))
        XCTAssertFalse(S.addsMeaningMarker("I could find the key for you today.", to: "I couldn't find the key for you today."))
        XCTAssertTrue(S.addsMeaningMarker("She told me she would never leave the village.", to: "She told me she would leave the village."))
        XCTAssertTrue(S.addsMeaningMarker("Wait for me by the mill at 9.", to: "Wait for me by the mill at 8."))
        XCTAssertTrue(S.addsMeaningMarker("I n0t going", to: "I going"))
        XCTAssertFalse(S.addsMeaningMarker("Hell0 there", to: "Hello there"))
    }

    func testRereadKinds() {
        XCTAssertTrue(S.isReread("Lead the mule back to the", of: "Lead the mule back to the stable."))
        XCTAssertFalse(S.isReread("You scared me!", of: "Oh my word, you scared me!"))
        XCTAssertTrue(S.isReread("Head to Harbor", of: "Head to Old Harbor."))
        XCTAssertTrue(S.isComplete("Hold the rope."))
        XCTAssertFalse(S.isComplete("hold the rope"))
        XCTAssertFalse(S.isComplete("Lead the mule back to the"))
        XCTAssertTrue(S.isRelated("Lead the mule", "Lead the mule back to the stable."))
        XCTAssertFalse(S.isRelated("And you mind your manners!", "r ners! fair!"))
        XCTAssertTrue(S.isBroken("Gtt to th3 gate"))
        XCTAssertTrue(S.isBroken("You kn@w it"))
        XCTAssertFalse(S.isBroken("I can't — wait…"))
    }

    // MARK: Sabitleyici (§7.5)

    func testNeedsTwoReadingsWithoutSentenceEnd() {
        var r = Run()
        XCTAssertEqual(r.feed(["We can not stay long", "We can not stay long", "We can not stay long"]), [.none, .translate("We can not stay long"), .none])
    }

    func testSentenceEndGoesOnFirstReading() {
        for t in ["We can not stay long.", "Wait!", "Who are you?", "I know…", "\"Run.\""] {
            var r = Run()
            XCTAssertEqual(r.feed([t, t]), [.translate(t), .none], t)
        }
    }

    func testJunkLikeNeedsTimeToo() {
        var r = Run()
        XCTAssertEqual(r.feed(["Rnn vexqolpit.", "Go to market."]), [.none, .translate("Go to market.")])

        var j = Run()
        let junk = "- Vrk) so, we hqve. dmn, I r"
        XCTAssertEqual(j.feed(Array(repeating: junk, count: 5), each: 100), Array(repeating: .none, count: 5))
        XCTAssertEqual(j.feed(junk, after: 700), .translate(junk))
    }

    func testOCRWobbleIsSameLine() {
        var r = Run()
        let out = r.feed(["The boat will sink soon", "The boat will sink soon", "The boal will sink soon", "The boal will sink soon"])
        XCTAssertEqual(out, [.none, .translate("The boat will sink soon"), .none, .none])
    }

    func testWorseRereadIgnoredBetterLineSent() {
        var r = Run()
        let a = "Beyond the frozen pass, Mira ok$7e rode, praying the bridge would still stand."
        let b = "Beyond the frozen pass%xqz O rode, Praying the bridge would still stand."
        XCTAssertEqual(r.feed([a, b, b, "Beyond the frozen pass, she rode."]), [.translate(a), .none, .none, .translate("Beyond the frozen pass, she rode.")])
    }

    func testWorseRereadByScore() {
        let good = "Look, I only stopped by to ask if there's anythin' you need from me."
        let bad = "Look, I stopped by to ask if there anythinl you need, ya."
        var r = Run()
        XCTAssertEqual(r.feed([good, bad, good, bad]), [.translate(good), .none, .none, .none])
        var q = Run()
        XCTAssertEqual(q.feed([bad, good, bad]), [.translate(bad), .translate(good), .none])
    }

    func testCounterNeverStabilizesBetweenEmpties() {
        var r = Run()
        let out = r.feed((0..<20).map { $0 % 2 == 0 ? "24 / 120" : nil })
        XCTAssertFalse(out.contains { if case .translate = $0 { return true }; return false })
    }

    func testGrowingLine() {
        var r = Run()
        let full = "We can not stay long in this cold."
        XCTAssertEqual(r.feed(["We can", "We can not stay", full, full]), [.none, .none, .translate(full), .none])
    }

    func testClearsAfterEightHundredMs() {
        var r = Run()
        _ = r.feed(["Hello there", "Hello there"])
        XCTAssertEqual(r.feed(nil), .none)
        XCTAssertEqual(r.feed(nil, after: 799), .none)
        XCTAssertEqual(r.feed(nil, after: 1), .clear)
        XCTAssertEqual(r.feed(nil), .none)
    }

    func testFlickeringLineIsKept() {
        var r = Run()
        XCTAssertEqual(r.feed(["Hold the rope", "Hold the rope"]), [.none, .translate("Hold the rope")])
        for _ in 0..<3 {
            for _ in 0..<10 { XCTAssertEqual(r.feed(nil, after: 50), .none) }
            for _ in 0..<4 { XCTAssertEqual(r.feed("Hold the rope", after: 50), .none) }
        }
    }

    func testRestoreWithinWindow() {
        var r = Run()
        XCTAssertEqual(r.feed("Hold the rope."), .translate("Hold the rope."))
        XCTAssertEqual(r.feed(nil), .none)
        XCTAssertEqual(r.feed(nil, after: 800), .clear)
        XCTAssertEqual(r.feed("Hold the rope", after: 1_500), .none)
        XCTAssertEqual(r.feed("Hold the rope"), .restore("Hold the rope."))
        XCTAssertEqual(r.feed("Hold the rope."), .none)
    }

    func testNoRestoreAfterWindow() {
        var r = Run()
        _ = r.feed("Hold the rope.")
        _ = r.feed(nil)
        XCTAssertEqual(r.feed(nil, after: 800), .clear)
        XCTAssertEqual(r.feed("Hold the rope.", after: 1_501), .translate("Hold the rope."))
    }

    func testAlternatingLinesRestore() {
        var r = Run()
        XCTAssertEqual(r.feed("Hold the rope."), .translate("Hold the rope."))
        XCTAssertEqual(r.feed("Run!", after: 100), .translate("Run!"))
        XCTAssertEqual(r.feed("Hold the rope.", after: 100), .restore("Hold the rope."))
        XCTAssertEqual(r.feed("Run!", after: 100), .restore("Run!"))
    }

    func testChangedLinesAreNew() {
        let pairs = [("Who sent you here?", "Who sent you here, kid?"),
                     ("Who sent you here, kid?", "Who sent you here?"),
                     ("I could find the key for you today.", "I couldn't find the key for you today."),
                     ("She told me she would leave the village.", "She told me she would never leave the village."),
                     ("Wait for me by the mill at 8.", "Wait for me by the mill at 9.")]
        for (a, b) in pairs {
            var r = Run()
            XCTAssertEqual(r.feed(a), .translate(a), a)
            XCTAssertEqual(r.feed(b, after: 50), .translate(b), b)
        }
    }

    func testRetryAfterFailure() {
        var r = Run()
        _ = r.feed(["Hold the rope", "Hold the rope"])
        r.s.forget(now: r.now)
        for _ in 0..<19 { XCTAssertEqual(r.feed("Hold the rope", after: 50), .none) }
        XCTAssertEqual(r.feed("Hold the rope", after: 50), .translate("Hold the rope"))

        var q = Run()
        _ = q.feed(["Hold the rope", "Hold the rope"])
        q.s.forget(now: q.now)
        XCTAssertEqual(q.feed("Run!"), .translate("Run!"))
    }

    func testReset() {
        var a = GameReading.Stabilizer()
        XCTAssertEqual(a.reset(), .none)
        var r = Run()
        _ = r.feed(["Hello there", "Hello there"])
        XCTAssertEqual(r.s.reset(), .clear)
        XCTAssertEqual(r.s.reset(), .none)
    }

    // Yer değişmeden tutma: satır 0,3–0,7 / 0,6–0,85; iz her yerde 120.
    let lineBox = gbox(0.3, 0.6, 0.7, 0.85)
    let fp = GameReading.Fingerprint.uniform(120)

    func testHoldsWhileOnlyOutsideChanges() {
        var r = Run()
        XCTAssertEqual(r.feed("Hold the rope.", box: lineBox, fp: fp), .translate("Hold the rope."))
        let outside = fp.setting(x: 0.05, y: 0.1, to: 250)
        for _ in 0..<60 { XCTAssertEqual(r.feed(nil, after: 50, fp: outside), .none) }
        XCTAssertEqual(r.feed("Hold the rope.", after: 50, box: lineBox, fp: fp), .none)
    }

    func testClearsWhenLineAreaChanges() {
        var r = Run()
        _ = r.feed("Hold the rope.", box: lineBox, fp: fp)
        let inside = fp.setting(x: 0.5, y: 0.7, to: 180)
        XCTAssertEqual(r.feed(nil, fp: inside), .none)
        XCTAssertEqual(r.feed(nil, after: 799, fp: inside), .none)
        XCTAssertEqual(r.feed(nil, after: 1, fp: inside), .clear)
    }

    func testHoldsAtMostFourSeconds() {
        var r = Run()
        _ = r.feed("Hold the rope.", box: lineBox, fp: fp)
        XCTAssertEqual(r.feed(nil, fp: fp), .none)
        XCTAssertEqual(r.feed(nil, after: 3_999, fp: fp), .none)
        XCTAssertEqual(r.feed(nil, after: 1, fp: fp), .clear)
    }

    func testPrefixJunkKeepsScreen() {
        var r = Run()
        let line = "VESNA: Said you wanted to earn your keep."
        XCTAssertEqual(r.feed(line), .translate(line))
        XCTAssertEqual(r.feed("VESMA. TRl VESNA: Said you wanted to earn your keep."), .none)
    }
}
