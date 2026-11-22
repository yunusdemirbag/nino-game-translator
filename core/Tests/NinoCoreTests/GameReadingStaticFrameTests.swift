// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

/// Sabit görüntüde altyazı kaçmasın (plan §3): süre sınırı ve altyazı bandının duyarlı eşiği.
final class GameReadingStaticFrameTests: XCTestCase {
    static let lines = ["Stay close to me.", "We leave at dawn.", "Do you hear that?", "Keep your voice down.", "Get to the boat now."]

    func makeReader(linesEvery: Int)
        -> (GR.Reader, GR.ManualClock, ScriptedReader) {
        let clock = GR.ManualClock()
        let ocr = ScriptedReader(handler: { _ in
            let i = min(Self.lines.count - 1, clock.nowMs / linesEvery)
            return [gline(Self.lines[i], gbox(0.3, 0.80, 0.7, 0.86))]
        })
        var cfg = GR.Reader.Configuration(gameKey: "test")
        cfg.region = GR.Region(preset: .fullFrame)
        let reader = GR.Reader(textReader: ocr, clock: clock, configuration: cfg)
        return (reader, clock, ocr)
    }

    /// Arka plan ve iz tamamen aynı (en kötü durum), altyazı satırı 3 sn'de bir değişiyor: her satır ≤ 1,5 sn içinde okunur.
    func testEveryNewLineIsReadWithinLimitOnStaticFrame() async {
        let every = 3_000
        let (reader, clock, ocr) = makeReader(linesEvery: every)
        var startedAt: [String: Int] = [:]
        var frames = 0
        while clock.nowMs < every * Self.lines.count {
            let out = await reader.process(FakeFrame(0, fingerprint: .uniform(50)))
            frames += 1
            for e in out.events {
                if case let .subtitleStarted(s) = e, startedAt[s.text] == nil { startedAt[s.text] = clock.nowMs }
                if case let .subtitleCorrected(s) = e, startedAt[s.text] == nil { startedAt[s.text] = clock.nowMs }
                if case let .subtitleUpdated(s) = e, startedAt[s.text] == nil { startedAt[s.text] = clock.nowMs }
            }
            clock.advance(100)
        }
        for (i, line) in Self.lines.enumerated() {
            guard let at = startedAt[line] else { return XCTFail("okunmadı: \(line)") }
            XCTAssertLessThanOrEqual(at - i * every, 1_500, line)
        }
        // Görüntü sabitken her kare okunmaz.
        XCTAssertLessThan(ocr.callCount, frames / 5)
    }

    /// Yalnız altyazı bandında 16'nın altında bir değişim okumayı tetikler; bandın dışındaki aynı değişim tetiklemez.
    func testSmallChangeInsideBandTriggersRead() async {
        let clock = GR.ManualClock()
        let ocr = ScriptedReader(handler: { _ in [gline("Stay close to me.", gbox(0.3, 0.80, 0.7, 0.86))] })
        var cfg = GR.Reader.Configuration(gameKey: "test")
        cfg.region = GR.Region(preset: .fullFrame)
        let reader = GR.Reader(textReader: ocr, clock: clock, configuration: cfg)
        let base = GR.Fingerprint.uniform(50)
        _ = await reader.process(FakeFrame(0, fingerprint: base))
        XCTAssertEqual(ocr.callCount, 1)
        clock.advance(100)
        _ = await reader.process(FakeFrame(0, fingerprint: base))
        XCTAssertEqual(ocr.callCount, 1)
        // Bandın dışında (üstte) 12'lik fark: yeniden kullanılır.
        clock.advance(100)
        var out = await reader.process(FakeFrame(0, fingerprint: base.setting(x: 0.5, y: 0.1, to: 62)))
        XCTAssertFalse(out.didRead)
        // Bantta (satırın yerinde) 12'lik fark: okunur.
        clock.advance(100)
        out = await reader.process(FakeFrame(0, fingerprint: base.setting(x: 0.5, y: 0.83, to: 62)))
        XCTAssertTrue(out.didRead)
    }

    /// Yavaş solma: kare kare fark eşiğin altında, ama son okumaya göre birikince okunur.
    func testSlowFadeAccumulatesAgainstLastRead() {
        var p = GR.ReadPlan(reuseLimit: 1_000, bandThreshold: 16, maxReuseMs: 0)
        XCTAssertEqual(p.decide(.uniform(50), now: 0), .read(deep: true))
        p.record(empty: true)
        var reads = 0
        for step in 1...6 {
            if case .read = p.decide(.uniform(UInt8(50 + step * 5)), now: step * 100) { reads += 1; p.record(empty: false) }
        }
        XCTAssertGreaterThanOrEqual(reads, 1)
    }

    func testPlanTimeLimit() {
        var p = GR.ReadPlan.standard(fastDetection: false)
        let fp = GR.Fingerprint.uniform(50)
        XCTAssertEqual(p.decide(fp, now: 0), .read(deep: true))
        p.record(empty: false)
        XCTAssertEqual(p.decide(fp, now: 1_000), .reuse)
        XCTAssertEqual(p.decide(fp, now: 1_499), .reuse)
        XCTAssertEqual(p.decide(fp, now: 1_500), .read(deep: false))
        p.record(empty: false)
        XCTAssertEqual(p.decide(fp, now: 1_600), .reuse)
    }
}
