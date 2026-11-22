// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import NinoCore
import XCTest
@testable import NinoMacKit

/// Okuma atlandığında ya da yazı atıldığında nedeni `altyazi.log`'a gider; aynı neden art arda tek satır + özet.
final class SessionNotesTests: XCTestCase {
    final class Traces: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [LineTrace] = []
        func add(_ t: LineTrace) { lock.withLock { items.append(t) } }
        var notes: [String] { lock.withLock { items.compactMap { if case let .note(s) = $0 { return s }; return nil } } }
    }

    func testDroppedBlockIsLoggedOnceWithSummary() async throws {
        let clock = GameReading.ManualClock()
        var cfg = GameReading.Reader.Configuration()
        GameReading.GTA6Rules.apply(true, packGame: "gta-6", to: &cfg)
        cfg.plan = .always
        let line = GameReading.Line("bring the car keys", confidence: 0.95, box: GameReading.Box(left: 0.70, top: 0.55, right: 0.95, bottom: 0.62))
        let reader = GameReading.Reader(textReader: SpeakerShowTests.FixedReader(lines: [line]), clock: clock, configuration: cfg)
        let traces = Traces()
        let session = SubtitleSession(reader: reader, translator: SpeakerShowTests.ArabicTranslator(), output: SpeakerShowTests.Shows(),
                                      clock: clock) { e in if case let .trace(t) = e { traces.add(t) } }
        for _ in 0..<10 {
            await session.process(SpeakerShowTests.image())
            clock.advance(100)
        }
        XCTAssertEqual(traces.notes, ["atıldı: ortada değil \"bring the car keys\""])
        await session.stop()
        XCTAssertEqual(traces.notes.last, "özet: atıldı: ortada değil \"bring the car keys\" ×10, 0,9 sn")
        XCTAssertEqual(traces.notes.count, 2)
    }
}
