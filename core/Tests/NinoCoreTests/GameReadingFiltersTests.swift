// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

final class GameReadingFiltersTests: XCTestCase {
    typealias F = GameReading.Filters

    func testLetterless() {
        XCTAssertFalse(F.hasEnoughLetters("91 / 200"))
        XCTAssertFalse(F.hasEnoughLetters("12:45"))
        XCTAssertTrue(F.hasEnoughLetters("Go!"))
    }

    func testHints() {
        let yes = ["PHOTO MODE L2 + R2", "PHOTO MODE [R1] + [L3]", "PHOTO MODE ■ FILTER", "A e SNACKS", "B : LIE DOWN",
                   GR.IconText.fix("13) Stand up"), "Hold L2 to talk to the ferryman", "Press ✕ to climb",
                   "X Accept", "BACK ○", "Gently pull R2 to brake", "R1 Block"]
        let no = ["Pass me the R2.", "FIND SHELTER!", "I am FREEZING", "Hey, you found Mira's map.", "Let's head back now."]
        for t in yes { XCTAssertTrue(F.isHint(t), t) }
        for t in no { XCTAssertFalse(F.isHint(t), t) }
    }

    func testDirections() {
        let yes = ["Turn left", "Turn Right", "Keep left", "Make a U-turn", "U-Turn Left", "Turn left 400 ft", "Keep Right.",
                   "Turn Right 310 ft 355 ft", "Keep Left 0 ft 2 ft", "U-Turn Left 5 ft"]
        let no = ["Turn left past the mill, then stop.", "Keep walking, the camp is close.", "Turn it down!"]
        for t in yes { XCTAssertTrue(F.isDirection(t), t) }
        for t in no { XCTAssertFalse(F.isDirection(t), t) }
    }

    func testJunkCleaning() {
        let cases: [(String, String)] = [
            ("Beyond the frozen pass, Mira ok$7e rode, praying the bridge would still stand.", "Beyond the frozen pass, Mira rode, praying the bridge would still stand."),
            ("Beyond the frozen pass4xqz O rode, Praying the bridge.", "Beyond the frozen pass O rode, Praying the bridge."),
            ("She came 7q, at noon.", "She came, at noon."),
            ("?! Who told you to follow me?", "Who told you to follow me?"),
            ("Who told you to follow me ?!", "Who told you to follow me?!"),
            ("Grab the rope, Tomas. ?!", "Grab the rope, Tomas."),
            ("Hurry, ?! the captain is waiting.", "Hurry, the captain is waiting."),
            (". Grab the rope.", "Grab the rope."),
            ("| Grab the rope, Tomas.", "Grab the rope, Tomas."),
            ("Grab the rope, Tomas. |", "Grab the rope, Tomas."),
            ("Drop it. l", "Drop it."),
            ("l can't see them, Captain Vey.", "I can't see them, Captain Vey."),
            ("| can't swim.", "I can't swim."),
            ("l'm sure, l heard it.", "I'm sure, I heard it."),
            ("|'ll wait here.", "I'll wait here."),
            ("Mara and l've met once.", "Mara and I've met once."),
            ("What did l do?", "What did I do?"),
            ("Is that you, |?", "Is that you, I?"),
            ("Not now, l!", "Not now, I!"),
            ("Drop it. l.", "Drop it."),
            ("7? The trail goes cold here.", "The trail goes cold here."),
            ("200. Nora and Felix...", "Nora and Felix..."),
            ("41m VESNA: Over there! Find shelter!", "VESNA: Over there! Find shelter!"),
            ("300 riders came", "300 riders came"),
        ]
        for (i, o) in cases { XCTAssertEqual(F.cleanJunk(i), o, i) }
        let unchanged = ["Plug in the PS5 cable.", "Move the R2-D2 toy.", "That costs $750.", "Meet me at 4:30pm.",
                         "The 3rd tower is 250m away.", "Runs at 120fps, 8K.", "Combo x3!", "Back in 1999.", "I won't — hold on…",
                         "\"Mira!\" he shouted.", "Mk3 pistol, 1.2kg.", "L2 + R2 Iron Stance", "Huh?! The lights went out alone!",
                         "- Now? - Later.", "Hold on... what?", "We... we can't stay.", "\"Go!\" she yelled.", "So, you're Tomas?",
                         "... and then it rained.", "Hold on ... what?", "You said no!", "Drop it, you said.", "Press R to reload."]
        for t in unchanged { XCTAssertEqual(F.cleanJunk(t), t, t) }
    }

    func testScoreAndJunkLook() {
        XCTAssertGreaterThan(F.score("VESNA: Hold this ridge!"), F.score("- VESNAiQwürr'k!"))
        XCTAssertGreaterThan(F.score("We drink at MacGregor's tonight."), 0)
        XCTAssertLessThan(F.score("S tay the[rnl Behind the wall."), F.score("Stay behind the wall."))
        XCTAssertGreaterThan(F.score("Run to the tower now."), F.score("Rnn to the tower now."))
        for t in ["Hmm!", "Shh!", "Brr!", "Psst!", "Mmm!"] { XCTAssertGreaterThan(F.score(t), 0, t) }
        XCTAssertTrue(F.looksLikeJunk("- Vrk) so, we hqve. dmn, I r"))
        XCTAssertTrue(F.looksLikeJunk("Rnn vexqolpit."))
        XCTAssertFalse(F.looksLikeJunk("Go to market."))
    }

    func testItemLabels() {
        for t in ["PingMe", "Gallery", "LEATHER BOOTS", "BREAD", "STORE IN CHEST (2/8) □ EQUIP ✕ CLOSE ○", "FRESH FISH, BEST PRICE", "GET YOURS TODAY ONLY!"] {
            XCTAssertTrue(F.isItemLabel(t), t)
        }
        for t in ["Fine.", "FIND SHELTER!", "TOMAS: ...", "WHY?", "Let's head back now."] { XCTAssertFalse(F.isItemLabel(t), t) }
    }

    func testBothEdges() {
        XCTAssertTrue(F.touchesBothEdges(gline("vex trail and copper is lanterned a morrow fiel gate shun orbit plenk", gbox(0, 0.5, 1, 0.6))))
        XCTAssertFalse(F.touchesBothEdges(gline("Brenna, we have to reach the ferry before the tide rolls over the causeway!", gbox(0.06, 0.5, 0.94, 0.6))))
        XCTAssertFalse(F.touchesBothEdges(gline("before the tide rolls over the causeway", gbox(0, 0.5, 0.7, 0.6))))
    }

    func testSameRowMerge() {
        let out = F.mergeSameRow([gline("Hold the door.", gbox(0.32, 0.50, 0.70, 0.56), conf: 0.9),
                                  gline("Brenna:", gbox(0.20, 0.505, 0.30, 0.555), conf: 0.7),
                                  gline("Second line", gbox(0.3, 0.6, 0.6, 0.66))])
        XCTAssertEqual(out.map(\.text), ["Brenna: Hold the door.", "Second line"])
        XCTAssertEqual(out[0].confidence, 0.7)
    }

    // §5.9 tablosu. "Alt yarı" alanı: sol 0,06, üst 0,56, sağ 0,98, alt 1.
    let half = gbox(0.06, 0.56, 0.98, 1)

    func testGiantLines() {
        func kept(_ lines: [GameReading.Line], _ area: GameReading.Box) -> [String] {
            let l = F.dropGiantLines(lines, area: area)
            return F.isGiantBlock(l, area: area) ? [] : l.map(\.text)
        }
        XCTAssertEqual(kept([gline("You shouldn't have followed me.", gbox(0.1, 0.60, 0.9, 0.69)), gline("Nobody ever listens.", gbox(0.1, 0.70, 0.9, 0.79))], half).count, 2)
        XCTAssertEqual(kept([gline("Welcome to Ravenmoor", gbox(0.1, 0.05, 0.9, 0.35)), gline("Where are we headed?", gbox(0.1, 0.80, 0.9, 0.88))], half), ["Where are we headed?"])
        XCTAssertEqual(kept([gline("We did it! KO", gbox(0.1, 0.30, 0.9, 0.50)), gline("What now? 00071000", gbox(0.1, 0.60, 0.9, 0.80))], half).count, 2)
        XCTAssertEqual(kept([gline("Ferry Tickets", gbox(0.1, 0.60, 0.9, 0.80))], half), [])
        XCTAssertEqual(kept([gline("Welcome to the Ashfall Isles, traveler.", gbox(0.1, 0.10, 0.9, 0.45))], half), [])
        XCTAssertEqual(kept([gline("Stay behind me.", gbox(0.1, 0.2, 0.9, 0.7))], gbox(0.2, 0.85, 0.8, 0.95)), ["Stay behind me."])
        XCTAssertEqual(kept([gline("Stay behind me.", gbox(0.1, 0.2, 0.9, 0.7))], .full), [])
        XCTAssertEqual(kept([gline("No signal here.")], half), ["No signal here."])
        let seven = (0..<7).map { gline("Line \($0) here.", gbox(0.1, 0.12 * Double($0), 0.9, 0.12 * Double($0) + 0.09)) }
        XCTAssertTrue(F.isGiantBlock(seven, area: half))
        XCTAssertFalse(F.isGiantBlock(Array(seven.prefix(3)), area: half))
        XCTAssertTrue(F.isGiantBlock([gline("Top of a poster", gbox(0.1, 0.05, 0.9, 0.15)), gline("bottom of a poster", gbox(0.1, 0.65, 0.9, 0.75))], area: half))
    }

    // §5.10 tablosu. Alan: sol 0, üst 0,6, sağ 1, alt 1. Boy 0,07.
    let lower = gbox(0, 0.6, 1, 1)
    func row(_ t: String, _ l: Double, _ top: Double, _ r: Double) -> GameReading.Line { gline(t, gbox(l, top, r, top + 0.07)) }

    func testBlockSelection() {
        let menu = ["MAP", "HELP", "PROGRESS", "PLAYER", "STORY", "ONLINE", "SOCIAL CLUB", "SETTINGS"].enumerated()
            .map { row($0.element, 0.05, 0.05 + 0.1 * Double($0.offset), 0.25) } + [row("PHOTO MODE", 0.85, 0.9, 0.97)]
        XCTAssertEqual(F.selectBlock(menu, area: lower), [])

        let b2 = F.selectBlock([row("The bridge will fall if we wait too long.", 0.25, 0.7, 0.75), row("9", 0.02, 0.7, 0.04),
                                row("PHOTO MODE", 0.85, 0.9, 0.97)], area: lower)
        XCTAssertEqual(b2.map(\.text), ["The bridge will fall if we wait too long."])
        XCTAssertEqual(b2[0].box, gbox(0.25, 0.7, 0.75, 0.77))

        let b3 = F.selectBlock([row("Ivo and Sela... neither came back.", 0.3, 0.6, 0.7), row("We have to go.", 0.4, 0.68, 0.6)], area: lower)
        XCTAssertEqual(b3.map(\.text), ["Ivo and Sela... neither came back.", "We have to go."])

        let b4 = F.selectBlock([row("Smuggler: I don't trust this one.", 0.05, 0.8, 0.5)], area: lower)
        XCTAssertEqual(b4.count, 1)

        let unboxed = [gline("MAP"), gline("HELP")]
        XCTAssertEqual(F.selectBlock(unboxed, area: lower), unboxed)
    }

    func testCentering() {
        XCTAssertEqual(F.centered(gbox(0.25, 0.8, 0.70, 0.85)), gbox(0.25, 0.8, 0.75, 0.85))
        XCTAssertEqual(F.centered(gbox(0.85, 0.9, 0.98, 0.95)), gbox(0.85, 0.9, 0.98, 0.95))
    }
}
