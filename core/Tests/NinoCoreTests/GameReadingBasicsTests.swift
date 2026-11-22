// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

final class GameReadingBasicsTests: XCTestCase {
    // MARK: Kutu

    func testBoxMapsFromAreaToFrame() {
        let area = gbox(0.1, 0.6, 0.9, 1.0)
        let b = gbox(0.5, 0.5, 1, 1).mapped(into: area)
        XCTAssertEqual(b.left, 0.5, accuracy: 1e-9)
        XCTAssertEqual(b.top, 0.8, accuracy: 1e-9)
        XCTAssertEqual(b.right, 0.9, accuracy: 1e-9)
        XCTAssertEqual(b.local(in: area).left, 0.5, accuracy: 1e-9)
    }

    func testSentenceEnd() {
        XCTAssertTrue(GR.Text.endsSentence("\"Run.\""))
        XCTAssertTrue(GR.Text.endsSentence("Wait…"))
        XCTAssertFalse(GR.Text.endsSentence("We do not"))
    }

    // MARK: Kapı (§1)

    func testGateSkipsAndRecoversFromStuck() {
        var g = GR.FrameGate()
        XCTAssertEqual(g.enter(now: 0), .admitted(ticket: 1))
        XCTAssertEqual(g.enter(now: 100), .skipped)
        XCTAssertEqual(g.enter(now: 10_000), .skipped)
        XCTAssertEqual(g.enter(now: 45_000), .stuck(elapsedMs: 45_000))
        XCTAssertEqual(g.enter(now: 45_000), .admitted(ticket: 2))
        // Sıfırlamadan önceki 1 numaranın geç çıkışı kapıyı açmaz.
        XCTAssertFalse(g.exit(ticket: 1))
        XCTAssertEqual(g.enter(now: 45_100), .skipped)
        XCTAssertTrue(g.exit(ticket: 2))
        XCTAssertEqual(g.enter(now: 45_200), .admitted(ticket: 3))
    }

    func testGateFallbackLimit() {
        var g = GR.FrameGate()
        g.fallbackActive = true
        _ = g.enter(now: 0)
        XCTAssertEqual(g.enter(now: 8_999), .skipped)
        XCTAssertEqual(g.enter(now: 9_000), .stuck(elapsedMs: 9_000))
    }

    func testResetDoesNotLetOldTicketOpen() {
        var g = GR.FrameGate()
        _ = g.enter(now: 0)
        g.reset()
        XCTAssertEqual(g.enter(now: 1), .admitted(ticket: 2))
        XCTAssertFalse(g.exit(ticket: 1))
        XCTAssertTrue(g.isBusy)
    }

    // MARK: Bölge (§2)

    func testRegionPresets() {
        XCTAssertEqual(GR.Region().preset, .bottom)
        XCTAssertEqual(GR.Region(gbox(0.1405, 0.6195, 0.86, 0.97)).preset, .bottom)
        XCTAssertEqual(GR.Region(gbox(0.2, 0.6, 0.8, 0.9)).preset, .custom)
        XCTAssertEqual(GR.Region(preset: .top).preset, .top)
        XCTAssertEqual(GR.Region(preset: .fullFrame).box, .full)
    }

    func testRegionMinimumSizeAndNoOverflow() {
        var r = GR.Region(gbox(0.5, 0.5, 0.51, 0.52))
        XCTAssertEqual(r.box.width, 0.05, accuracy: 1e-9)
        XCTAssertEqual(r.box.height, 0.05, accuracy: 1e-9)
        r.move(dx: 0.9, dy: 0.9)
        XCTAssertEqual(r.box.right, 1, accuracy: 1e-9)
        XCTAssertEqual(r.box.bottom, 1, accuracy: 1e-9)
        r.resize(width: 0.5, height: 0.5)
        XCTAssertEqual(r.box.right, 1, accuracy: 1e-9)
        XCTAssertEqual(r.box.left, 0.5, accuracy: 1e-9)
        let s = GR.Region(preset: .bottom)
        XCTAssertEqual(s.sliderPosition, 62, accuracy: 1e-9)
        XCTAssertEqual(s.sliderHeight, 35, accuracy: 1e-9)
    }

    func testLearnedStripNarrowsReadingArea() {
        let r = GR.Region(preset: .bottom)
        XCTAssertEqual(r.readingArea(stripTop: 0.84).top, 0.79, accuracy: 1e-9)
        XCTAssertEqual(r.readingArea(stripTop: 0.50).top, 0.62, accuracy: 1e-9) // bölge üstünden yukarıda
        XCTAssertEqual(r.readingArea(stripTop: 0.98).top, 0.62, accuracy: 1e-9) // alta 0,06'dan yakın
        XCTAssertEqual(r.readingArea(stripTop: nil), r.box)
    }

    // MARK: Plan (§3)

    func testFingerprintChange() {
        let a = GR.Fingerprint.uniform(120)
        XCTAssertFalse(a.changed(from: .uniform(136)))
        XCTAssertTrue(a.changed(from: .uniform(137)))
        XCTAssertTrue(a.changed(from: GR.Fingerprint(values: [1, 2])))
        let b = a.setting(x: 0.05, y: 0.05, to: 200)
        XCTAssertTrue(b.changed(from: a))
        XCTAssertFalse(b.changed(from: a, within: gbox(0.3, 0.6, 0.7, 0.85)))
        XCTAssertTrue(a.setting(x: 0.5, y: 0.7, to: 180).changed(from: a, within: gbox(0.3, 0.6, 0.7, 0.85)))
    }

    func testPlanReusesUntilLimit() {
        var p = GR.ReadPlan.standard(fastDetection: true)
        let fp = GR.Fingerprint.uniform(50)
        XCTAssertEqual(p.decide(fp), .read(deep: true))
        p.record(empty: false)
        XCTAssertEqual(p.decide(fp), .reuse)
        XCTAssertEqual(p.decide(fp), .reuse)
        XCTAssertEqual(p.decide(fp), .read(deep: false))
        p.record(empty: false)
        XCTAssertEqual(p.decide(.uniform(90)), .read(deep: false))
    }

    func testPlanDeepOnlyEveryThirdEmpty() {
        var p = GR.ReadPlan(threshold: -1, reuseLimit: 0)
        var deeps: [Bool] = []
        for _ in 0..<7 {
            if case let .read(deep) = p.decide(.uniform(0)) { deeps.append(deep) }
            p.record(empty: true)
        }
        XCTAssertEqual(deeps, [true, false, false, true, false, false, true])
        p.record(empty: false)
        if case let .read(deep) = p.decide(.uniform(0)) { XCTAssertFalse(deep) }
    }

    func testAlwaysPlan() {
        var p = GR.ReadPlan.always
        for _ in 0..<3 {
            XCTAssertEqual(p.decide(.uniform(1)), .read(deep: true))
            p.record(empty: true)
        }
    }

    func testFingerprintFromImage() {
        let frame = GR.ImageFrame(solidImage(width: 320, height: 180, gray: 0.5))
        let fp = frame.fingerprint(of: gbox(0, 0.5, 1, 1))
        XCTAssertEqual(fp.values.count, 64 * 12)
        XCTAssertFalse(fp.changed(from: .uniform(fp.values[0])))
        XCTAssertEqual(frame.crop(gbox(0, 0, 0.5, 0.5), scale: 2)?.width, 320)
    }

    // MARK: OCR (§4)

    func testIconTextFix() {
        let cases = [
            ("13) Stand up", "L3 Stand up"),
            ("L3] Stand up", "L3 Stand up"),
            ("(R3 Focus", "R3 Focus"),
            ("We counted 13 crates today.", "We counted 13 crates today."),
            ("Hold ✕ ✕ to keep the lantern lit", "Hold ✕ to keep the lantern lit"),
            ("Press ○ ○ ○ quickly", "Press ○ quickly"),
            ("Use ← → to choose", "Use ← → to choose"),
            ("Hold L2 L2 to talk to the ferryman", "Hold L2 to talk to the ferryman"),
            ("Tap ✕ ✕ ✕ to row faster", "Tap ✕ to row faster"),
            ("Hold L1 R1 to brace", "Hold L1 R1 to brace"),
            ("(C1 Aim", "L1 Aim"),
        ]
        for (input, expected) in cases { XCTAssertEqual(GR.IconText.fix(input), expected, input) }
    }

    func testMergesFragmentsSplitAtIcon() {
        let lines = [gline("to continue", gbox(0.42, 0.805, 0.60, 0.85)), gline("Hold", gbox(0.30, 0.80, 0.36, 0.85))]
        let out = GR.OCR.mergeFragments(lines, aspect: 16.0 / 9.0) { _ in "●" }
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out[0].text.hasPrefix("Hold"))
        XCTAssertTrue(out[0].text.hasSuffix("to continue"))
        XCTAssertEqual(out[0].text, "Hold ● to continue")
        XCTAssertEqual(out[0].box, gbox(0.30, 0.80, 0.60, 0.85))
    }

    func testDoesNotMergeGiantSignLetters() {
        let sub = gline("The tide is coming in fast.", gbox(0.2, 0.80, 0.7, 0.85))
        let sign = gline("BAIT", gbox(0.72, 0.70, 0.80, 0.90))
        let out = GR.OCR.mergeFragments([sub, sign], aspect: 16.0 / 9.0) { _ in "●" }
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.first { $0.text.hasPrefix("The") }?.box, sub.box)
    }

    func testOCRDropsLowConfidenceAndSorts() async throws {
        let reader = ScriptedReader([[gline("Second", gbox(0.1, 0.6, 0.5, 0.7)), gline("noise", gbox(0.1, 0.1, 0.5, 0.2), conf: 0.49),
                                      gline("  First  ", gbox(0.1, 0.3, 0.5, 0.4))]])
        let ocr = GR.OCR(reader: reader)
        let lines = try await ocr.read(FakeFrame(1), area: .full, deep: false)
        XCTAssertEqual(lines.map(\.text), ["First", "Second"])
    }

    func testDeepReadUsesStripFirst() async throws {
        // İlk okuma boş; yalnız şerit (genişlik 2 × %40) "Go!" görüyor.
        let area = gbox(0.1, 0.6, 0.9, 1.0)
        let reader = ScriptedReader { call in
            if call.scale == 2, abs(call.area.width - 0.8 * 0.4) < 1e-9 { return [gline("Go!", gbox(0.4, 0.5, 0.6, 0.6))] }
            return []
        }
        let lines = try await GR.OCR(reader: reader).read(FakeFrame(1), area: area, deep: true)
        XCTAssertEqual(lines.map(\.text), ["Go!"])
        XCTAssertEqual(lines[0].box!.left, 0.3 + 0.4 * 0.4, accuracy: 1e-9)
        XCTAssertEqual(reader.callCount, 2)
    }

    func testDeepReadPrefersStripOverFull() async throws {
        let reader = ScriptedReader { call in
            if call.scale == 2 { return call.area.width < 0.5 ? [gline("Go!")] : [gline("G0!")] }
            return []
        }
        let lines = try await GR.OCR(reader: reader).read(FakeFrame(1), area: .full, deep: true)
        XCTAssertEqual(lines.map(\.text), ["Go!"])
    }

    func testDeepReadFallsBackToFullArea() async throws {
        let reader = ScriptedReader { call in call.scale == 2 && call.area.width > 0.5 ? [gline("Go!")] : [] }
        let lines = try await GR.OCR(reader: reader).read(FakeFrame(1), area: .full, deep: true)
        XCTAssertEqual(lines.map(\.text), ["Go!"])
        XCTAssertEqual(reader.callCount, 3)
    }

    func testNoDeepReadWhenFirstFindsText() async throws {
        let reader = ScriptedReader([[gline("Hold the rope.")]])
        _ = try await GR.OCR(reader: reader).read(FakeFrame(1), area: .full, deep: true)
        XCTAssertEqual(reader.callCount, 1)
    }

    // MARK: Bekçi (§4.6)

    func testWatchdogVerdicts() {
        typealias G = GR.GuardedTextReader
        XCTAssertEqual(G.verdict(holderElapsedMs: 7_999, mode: .primary, hasFallback: true), .busy)
        XCTAssertEqual(G.verdict(holderElapsedMs: 8_000, mode: .primary, hasFallback: true), .switchToFallback)
        XCTAssertEqual(G.verdict(holderElapsedMs: 8_000, mode: .primary, hasFallback: false), .switchToCPU)
        XCTAssertEqual(G.verdict(holderElapsedMs: 44_999, mode: .cpuOnly, hasFallback: false), .busy)
        XCTAssertEqual(G.verdict(holderElapsedMs: 45_000, mode: .cpuOnly, hasFallback: false), .stuck)
    }

    func testWatchdogSkipsBusyFrameAndSwitchesWhenHung() async throws {
        let clock = GR.ManualClock()
        let hang = HangingReader()
        let cpu = ScriptedReader { _ in [gline("cpu")] }
        let guarded = GR.GuardedTextReader(primary: hang, cpu: cpu, clock: clock) { ms in clock.advance(ms) }
        let first = Task { try await guarded.read(FakeFrame(1), area: .full, scale: 1) }
        await hang.waitUntilStarted()
        // Tutan okuma 4 sn bekleme sonunda 8 sn'den kısa: kare atlanır.
        do { _ = try await guarded.read(FakeFrame(2), area: .full, scale: 1); XCTFail("meşgul olmalıydı") }
        catch { XCTAssertEqual(error as? GR.WatchdogError, .busy) }
        // 4 sn daha: tutan okuma 8 sn'yi geçti → işlemciye geçilir.
        let lines = try await guarded.read(FakeFrame(3), area: .full, scale: 1)
        XCTAssertEqual(lines.map(\.text), ["cpu"])
        let mode = await guarded.mode
        XCTAssertEqual(mode, .cpuOnly)
        hang.release()
        _ = try? await first.value
    }
}

/// Bırakılana kadar dönmeyen okuyucu.
final class HangingReader: GameReading.TextReader, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false
    private var released = false

    func read(_ frame: GameReading.Frame, area: GameReading.Box, scale: Double) async throws -> [GameReading.Line] {
        await withCheckedContinuation { c in
            lock.lock()
            started = true
            if released { lock.unlock(); c.resume(); return }
            continuation = c
            lock.unlock()
        }
        return []
    }

    func waitUntilStarted() async {
        while true {
            if lock.withLock({ started }) { return }
            await Task.yield()
        }
    }

    func release() {
        lock.lock(); released = true; let c = continuation; continuation = nil; lock.unlock()
        c?.resume()
    }
}
