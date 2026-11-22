// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

final class StabilizerTests: XCTestCase {
    private func feed(_ s: inout Stabilizer, _ texts: [String?]) -> [[StabilizerEvent]] {
        texts.map { s.observe($0) }
    }

    func testStartsAfterStableFrames() {
        var s = Stabilizer()
        let events = feed(&s, ["Come here.", "Come here.", "Come here."])
        XCTAssertEqual(events[0], [])
        XCTAssertEqual(events[1], [])
        XCTAssertEqual(events[2], [.stabilized(text: "Come here.", frame: 3)])
    }

    func testEmitsOnlyOnceWhileOnScreen() {
        var s = Stabilizer()
        let all = feed(&s, Array(repeating: "Come here.", count: 10)).flatMap { $0 }
        XCTAssertEqual(all.count, 1)
    }

    func testOCRWobbleDoesNotReset() {
        var s = Stabilizer()
        let events = feed(&s, ["Hello there, traveler", "Hel1o there, traveler", "Hello there, traveler"])
        XCTAssertEqual(events[2], [.stabilized(text: "Hello there, traveler", frame: 3)])
    }

    func testSingleEmptyFrameDoesNotEnd() {
        var s = Stabilizer()
        let all = feed(&s, ["Come here.", "Come here.", "Come here.", nil, "Come here.", nil, "Come here."]).flatMap { $0 }
        XCTAssertEqual(all, [.stabilized(text: "Come here.", frame: 3)])
    }

    func testEndsAfterMissingFrames() {
        var s = Stabilizer()
        let events = feed(&s, ["Come here.", "Come here.", "Come here.", nil, nil])
        XCTAssertEqual(events[3], [])
        XCTAssertEqual(events[4], [.disappeared(text: "Come here.")])
    }

    func testEmptyFrameDoesNotResetCandidate() {
        var s = Stabilizer()
        let events = feed(&s, ["Come here.", nil, "Come here.", "Come here."])
        XCTAssertEqual(events[3], [.stabilized(text: "Come here.", frame: 4)])
    }

    func testCandidateDroppedAfterMissingFrames() {
        var s = Stabilizer()
        let all = feed(&s, ["Come here.", "Come here.", nil, nil, "Come here."]).flatMap { $0 }
        XCTAssertEqual(all, [])
    }

    func testChangingTextEndsOldThenStartsNew() {
        var s = Stabilizer()
        let events = feed(&s, ["Come here.", "Come here.", "Come here.",
                               "Leave me alone.", "Leave me alone.", "Leave me alone."])
        XCTAssertEqual(events[4], [.disappeared(text: "Come here.")])
        XCTAssertEqual(events[5], [.stabilized(text: "Leave me alone.", frame: 6)])
    }

    func testEndAndStartInSameFrameKeepsOrder() {
        var s = Stabilizer(stableFrames: 2, missingFrames: 2)
        let events = feed(&s, ["Come here.", "Come here.", "Leave me alone.", "Leave me alone."])
        XCTAssertEqual(events[3], [.disappeared(text: "Come here."), .stabilized(text: "Leave me alone.", frame: 4)])
    }

    func testTypewriterTextStartsOnceWhenDone() {
        var s = Stabilizer()
        let frames: [String?] = ["Th", "The fe", "The ferry", "The ferry is", "The ferry is late.",
                                 "The ferry is late.", "The ferry is late."]
        let all = feed(&s, frames).flatMap { $0 }
        XCTAssertEqual(all, [.stabilized(text: "The ferry is late.", frame: 7)])
    }

    func testReturningTextStartsAgain() {
        var s = Stabilizer()
        let all = feed(&s, ["Run!", "Run!", "Run!", nil, nil, "Run!", "Run!", "Run!"]).flatMap { $0 }
        XCTAssertEqual(all, [.stabilized(text: "Run!", frame: 3), .disappeared(text: "Run!"),
                             .stabilized(text: "Run!", frame: 8)])
    }

    func testUsesLatestReadingWhenStabilized() {
        var s = Stabilizer()
        let events = feed(&s, ["Hel1o there, traveler", "Hello there, traveler", "Hello there, traveler"])
        XCTAssertEqual(events[2], [.stabilized(text: "Hello there, traveler", frame: 3)])
    }
}

final class StabilizerGrowthTests: XCTestCase {
    func testAppendedShortSentenceIsNewSubtitle() {
        var s = Stabilizer()
        let a = "Hello there, my friend.", b = "Hello there, my friend. Go."
        let all = (Array(repeating: a, count: 3) + Array(repeating: b, count: 5)).flatMap { s.observe($0) }
        XCTAssertEqual(all, [.stabilized(text: a, frame: 3), .disappeared(text: a), .stabilized(text: b, frame: 6)])
    }

    func testSlowTypewriterEmitsOnlyFullText() {
        var s = Stabilizer()
        let full = "The ferry leaves at dawn, so get some sleep."
        var frames: [String] = []
        var n = 2
        while n < full.count { frames.append(String(full.prefix(n))); n += 2 }
        frames += Array(repeating: full, count: 3)
        let all = frames.flatMap { s.observe($0) }
        XCTAssertEqual(all, [.stabilized(text: full, frame: frames.count)])
    }

    func testSubstitutionWobbleStillSame() {
        XCTAssertTrue(TextSimilarity.isSame("Hello there, traveler", "Hel1o there, traveler", threshold: 0.85))
        XCTAssertFalse(TextSimilarity.isSame("Hello there, my friend.", "Hello there, my friend. Go.", threshold: 0.85))
    }
}
