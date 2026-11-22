// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

final class TextSimilarityTests: XCTestCase {
    func testKeyNormalizes() {
        XCTAssertEqual(TextSimilarity.key("  Hello,   THERE! "), "hello there")
    }

    func testOneCharWobbleIsSimilar() {
        XCTAssertGreaterThanOrEqual(TextSimilarity.ratio("Hello there, traveler", "Hel1o there, traveler"), 0.85)
    }

    func testDifferentLinesAreNotSimilar() {
        XCTAssertLessThan(TextSimilarity.ratio("Come here.", "Leave me alone."), 0.85)
        XCTAssertLessThan(TextSimilarity.ratio("No.", "Go."), 0.85)
    }

    func testIdentical() {
        XCTAssertEqual(TextSimilarity.ratio("Run!", "run"), 1.0)
        XCTAssertEqual(TextSimilarity.ratio("", ""), 1.0)
    }
}
