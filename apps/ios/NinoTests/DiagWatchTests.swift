// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import NinoCore
import XCTest
@testable import Nino

/// Otomatik teşhis bekçisi: ortak senaryolar (Fixtures/diag-scenarios.json) ve ek kurallar.
final class DiagWatchTests: XCTestCase {
    private struct Scenario: Decodable {
        var name: String
        var timeline: [[Step]]
        var dropCodes: [String]?
        var state: [String: TelemetryValue]?
        var expect: [Expect]
    }

    private enum Step: Decodable {
        case number(Double), code(String)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let n = try? c.decode(Double.self) { self = .number(n) } else { self = .code(try c.decode(String.self)) }
        }
        var number: Double? { if case let .number(n) = self { n } else { nil } }
        var code: String? { if case let .code(s) = self { s } else { nil } }
    }

    private struct Expect: Decodable {
        var at: Double
        var rule: String
        var cause: String
        var sev: String
    }

    /// Senaryoyu oynatır: her olay kendi saniyesinde, aradaki her saniye `tick`; son olaydan sonra durur.
    private func play(_ s: Scenario) -> [DiagReport] {
        let watch = DiagWatch(launchedAt: 0)
        watch.today = { "2026-11-22" }
        let state = s.state ?? [:]
        watch.context = { state }
        var drops = s.dropCodes ?? []
        var reports: [DiagReport] = []
        let events = s.timeline.map { (t: $0[0].number ?? 0, code: $0[1].code ?? "", value: $0.count > 2 ? $0[2].number.map { Int($0) } : nil) }
        let end = Int(events.map(\.t).max() ?? 0)
        var i = 0
        for second in 0...end {
            while i < events.count, events[i].t <= Double(second) {
                let e = events[i]
                var detail: String?
                if e.code == "tv.drop", !drops.isEmpty { detail = drops.removeFirst() }
                reports += watch.note(e.code, e.value, at: e.t, detail: detail)
                i += 1
            }
            reports += watch.tick(at: Double(second))
        }
        return reports
    }

    func testSharedScenarios() throws {
        let url = try XCTUnwrap(Bundle(for: DiagWatchTests.self).url(forResource: "diag-scenarios", withExtension: "json"))
        struct File: Decodable { var scenarios: [Scenario] }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(file.scenarios.count, 9)
        for s in file.scenarios {
            let got = play(s)
            XCTAssertEqual(got.map(\.rule), s.expect.map(\.rule), s.name)
            XCTAssertEqual(got.map(\.cause), s.expect.map(\.cause), s.name)
            XCTAssertEqual(got.map(\.severity.rawValue), s.expect.map(\.sev), s.name)
            for (g, e) in zip(got, s.expect) {
                XCTAssertEqual(g.at, e.at, accuracy: 0, s.name)
            }
        }
    }

    func testReportBecomesCleanTelemetryEvent() throws {
        let w = DiagWatch(launchedAt: 0)
        w.context = { ["net": .string("wifi"), "memMB": .int(410)] }
        w.note("session.start", at: 100)
        w.note("ps5.drop", at: 200)
        var reports: [DiagReport] = []
        for t in stride(from: 200.0, through: 400, by: 1) { reports += w.tick(at: t) }
        let r = try XCTUnwrap(reports.first)
        XCTAssertEqual(r.at, 380)
        XCTAssertEqual(r.trail.map(\.code), ["session.start", "ps5.drop"])
        XCTAssertEqual(r.trail.map(\.seconds), [-280, -180])
        let event = try XCTUnwrap(TelemetryEvent.diag(rule: r.rule, cause: r.cause, severity: r.severity, state: r.state, trail: r.trail))
        XCTAssertEqual(event.kind, .diag)
    }

    func testRemoteConfigTurnsRuleOffAndChangesLimit() {
        let w = DiagWatch(config: .init(off: ["tr.errors"], limits: ["ps5NoReturnSec": 60]), launchedAt: 0)
        w.note("session.start", at: 100)
        for t in 0..<12 { w.note(t < 8 ? "tr.error" : "tr.ok", t < 8 ? 429 : nil, at: 120 + Double(t)) }
        w.note("ps5.drop", at: 200)
        var reports: [DiagReport] = []
        for t in stride(from: 200.0, through: 300, by: 1) { reports += w.tick(at: t) }
        XCTAssertEqual(reports.map(\.rule), ["ps5.no_return"])
        XCTAssertEqual(reports.first?.at, 260)
    }

    func testDailyLimits() {
        let w = DiagWatch(launchedAt: 0)
        w.today = { "2026-11-22" }
        var sent = 0
        // Beş oturum, her birinde geri gelmeyen bir PS5 kopması; günde aynı kural en çok 2 kez.
        for t in stride(from: 0.0, through: 11_000, by: 1) {
            let phase = (Int(t) - 1000) % 2000
            if t >= 1000, phase == 0 { w.note("session.start", at: t) }
            if t >= 1000, phase == 10 { w.note("ps5.drop", at: t) }
            if t >= 1000, phase == 300 { w.note("session.stop", at: t) }
            sent += w.tick(at: t).count
        }
        XCTAssertEqual(sent, 2)
    }

    func testOnlyMostImportantRuleWithinFiveMinutes() {
        let w = DiagWatch(launchedAt: 0)
        w.note("session.start", at: 100)
        XCTAssertEqual(w.hang(blockedSec: 6, at: 200).map(\.rule), ["app.hang"])
        for t in 0..<12 { XCTAssertTrue(w.note(t < 8 ? "tr.error" : "tr.ok", t < 8 ? 500 : nil, at: 210 + Double(t)).isEmpty) }
        // Ayrı tetik 5 dakika sonra gider.
        var later: [DiagReport] = []
        for t in 0..<12 { later += w.note(t < 8 ? "tr.error" : "tr.ok", t < 8 ? 500 : nil, at: 600 + Double(t)) }
        XCTAssertEqual(later.map(\.cause), ["server"])
    }

    func testResourcesAndPacks() {
        let w = DiagWatch(launchedAt: 0)
        XCTAssertTrue(w.resources(memMB: 900, thermal: "nominal", at: 100).isEmpty)
        XCTAssertEqual(w.resources(memMB: 950, thermal: "nominal", at: 220).map(\.cause), ["memory_high"])
        XCTAssertTrue(w.packResult("gta-vi", ok: false, http: 503, at: 1000).isEmpty)
        XCTAssertTrue(w.packResult("gta-vi", ok: false, http: 503, at: 2000).isEmpty)
        XCTAssertEqual(w.packResult("gta-vi", ok: false, http: 503, at: 3000).map(\.cause), ["http_5xx"])
    }

    func testSlowTranslationCause() {
        let w = DiagWatch(launchedAt: 0)
        w.note("session.start", at: 100)
        var reports: [DiagReport] = []
        for n in 0..<20 {
            w.providerRequest(ms: 3500, failure: nil, at: 200 + Double(n))
            reports += w.translated(totalMs: 3800, at: 200 + Double(n))
        }
        XCTAssertEqual(reports.map(\.rule), ["tr.slow"])
        XCTAssertEqual(reports.first?.cause, "provider_slow")
    }

    /// Uygulama askıya alınıp dönünce (arka plan olayı gelmeden) saat boşluğu bildirime yol açmaz.
    func testSuspensionGapIsQuiet() {
        let w = DiagWatch(launchedAt: 0)
        w.note("session.start", at: 100)
        w.note("ps5.connect", at: 110)
        w.note("ps5.frame", 30, at: 120)
        w.note("ps5.drop", at: 130)
        w.note("ps5.connect", at: 131)
        var reports: [DiagReport] = []
        for t in stride(from: 131.0, through: 140, by: 1) { reports += w.tick(at: t) }
        // 10 dakika askıda kaldı; dönüşte kareler hemen gelir.
        for t in stride(from: 740.0, through: 745, by: 1) {
            reports += w.tick(at: t)
            w.frame(at: t)
        }
        XCTAssertEqual(reports, [])
    }

    func testTrailMergesRepeatedLineCodes() throws {
        let w = DiagWatch(launchedAt: 0)
        w.note("session.start", at: 100)
        for n in 0..<30 { w.note("ocr.text", at: 110 + Double(n)) }
        w.note("ps5.drop", at: 150)
        var reports: [DiagReport] = []
        for t in stride(from: 150.0, through: 330, by: 1) { reports += w.tick(at: t) }
        let trail = try XCTUnwrap(reports.first?.trail)
        XCTAssertEqual(trail.map(\.code), ["session.start", "ocr.text", "ps5.drop"])
        XCTAssertEqual(trail[1].value, 30)
    }
}
