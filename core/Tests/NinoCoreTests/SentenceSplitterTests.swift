// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

final class SentenceSplitterTests: XCTestCase {
    private let splitter = SentenceSplitter()

    func testBasic() {
        XCTAssertEqual(splitter.split("Come here. Now! Are you deaf?"), ["Come here.", "Now!", "Are you deaf?"])
    }

    func testSingleSentenceAndEmpty() {
        XCTAssertEqual(splitter.split("  The ferry is late  "), ["The ferry is late"])
        XCTAssertEqual(splitter.split("   "), [])
    }

    func testEllipsis() {
        XCTAssertEqual(splitter.split("Wait... what?"), ["Wait... what?"])
        XCTAssertEqual(splitter.split("Wait... What?"), ["Wait...", "What?"])
        XCTAssertEqual(splitter.split("Wait… What?"), ["Wait…", "What?"])
    }

    func testAbbreviations() {
        XCTAssertEqual(splitter.split("Mr. Vale is here. Dr. Osk too."), ["Mr. Vale is here.", "Dr. Osk too."])
        XCTAssertEqual(splitter.split("Bring rope, nails, etc. Then go."), ["Bring rope, nails, etc. Then go."])
    }

    func testDecimals() {
        XCTAssertEqual(splitter.split("It is 3.5 meters. Climb."), ["It is 3.5 meters.", "Climb."])
    }

    func testMixedEndings() {
        XCTAssertEqual(splitter.split("You did what?! Unbelievable."), ["You did what?!", "Unbelievable."])
    }

    func testClosingQuotes() {
        XCTAssertEqual(splitter.split("He said \"Run.\" So I ran."), ["He said \"Run.\"", "So I ran."])
        XCTAssertEqual(splitter.split("“Stop.” Then silence."), ["“Stop.”", "Then silence."])
    }

    func testSpeakerDashes() {
        XCTAssertEqual(splitter.split("- Run! - Where?"), ["- Run!", "- Where?"])
    }
}
