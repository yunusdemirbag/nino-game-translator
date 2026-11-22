// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

final class NoiseFilterTests: XCTestCase {
    private let filter = NoiseFilter()
    private let inside = NormalizedRect(x: 0.3, y: 0.8, width: 0.4, height: 0.05)

    private func line(_ text: String, _ confidence: Float = 0.9, box: NormalizedRect? = nil) -> RecognizedLine {
        RecognizedLine(text: text, confidence: confidence, box: box ?? inside)
    }

    func testDropsLowConfidence() {
        XCTAssertTrue(filter.isNoise(line("Come here.", 0.2)))
        XCTAssertFalse(filter.isNoise(line("Come here.", 0.4)))
    }

    func testDropsSingleLettersAndSymbols() {
        for text in ["A", "3", ">>", "—", "", "   "] {
            XCTAssertTrue(filter.isNoise(line(text)), "\(text) gürültü olmalı")
        }
    }

    func testDropsMostlySymbols() {
        XCTAssertTrue(filter.isNoise(line("[X] 12/40")))
    }

    func testDropsUIWordsIgnoringCase() {
        XCTAssertTrue(filter.isNoise(line("OPTIONS")))
        XCTAssertTrue(filter.isNoise(line("Skip")))
        XCTAssertTrue(filter.isNoise(line("  pause ")))
        XCTAssertFalse(filter.isNoise(line("Skip the stew.")))
    }

    func testCustomUIWords() {
        let custom = NoiseFilter(ignoredPhrases: ["hold to skip"])
        XCTAssertTrue(custom.isNoise(line("Hold to Skip")))
        XCTAssertFalse(custom.isNoise(line("Options")))
    }

    func testKeepsShortRealLines() {
        for text in ["No.", "Go!", "Hm?"] {
            XCTAssertFalse(filter.isNoise(line(text)), "\(text) kalmalı")
        }
    }

    func testRegionDropsLinesOutside() {
        let top = NormalizedRect(x: 0.4, y: 0.05, width: 0.2, height: 0.04)
        let kept = filter.clean([line("Health 100", box: top), line("Come here.")], region: .defaultSubtitle)
        XCTAssertEqual(kept.map(\.text), ["Come here."])
    }

    func testJoinsTopToBottomAndCollapsesSpaces() {
        let upper = NormalizedRect(x: 0.3, y: 0.75, width: 0.4, height: 0.05)
        let lower = NormalizedRect(x: 0.3, y: 0.82, width: 0.4, height: 0.05)
        let text = filter.text(from: [
            line("is   late.", box: lower),
            line("A",  box: upper),
            line(" The ferry ", box: upper),
        ], region: .defaultSubtitle)
        XCTAssertEqual(text, "The ferry is late.")
    }

    func testEmptyWhenNothingLeft() {
        XCTAssertNil(filter.text(from: [line("A"), line("MENU")], region: .defaultSubtitle))
        XCTAssertNil(filter.text(from: [], region: .defaultSubtitle))
    }
}
