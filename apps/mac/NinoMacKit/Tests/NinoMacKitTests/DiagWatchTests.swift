// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import NinoCore
import XCTest
@testable import NinoMacKit

/// Otomatik teşhis bekçisi: `diag-scenarios.json` senaryoları sahte saatle oynatılır (saniyeler doğrudan zaman),
/// beklenen kural, sebep, önem ve tetik anı (`at`) tutmalı. Ayrıca susturma, öncelik, sınırlar, uzaktan ayar, iz.
final class DiagWatchTests: XCTestCase {
    struct File: Decodable {
        var scenarios: [Scenario]
    }

    struct Scenario: Decodable {
        var name: String
        var timeline: [[Item]]
        var dropCodes: [String]?
        var state: [String: Item]?
        var expect: [Expect]
    }

    struct Expect: Decodable {
        var at: Double
        var rule: String
        var cause: String
        var sev: String
    }

    enum Item: Decodable {
        case number(Double), text(String), flag(Bool)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let b = try? c.decode(Bool.self) { self = .flag(b) }
            else if let d = try? c.decode(Double.self) { self = .number(d) }
            else { self = .text(try c.decode(String.self)) }
        }
        var number: Double? { if case let .number(d) = self { return d }; return nil }
        var text: String? { if case let .text(s) = self { return s }; return nil }
    }

    static func scenarios() throws -> [Scenario] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "diag-scenarios", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).scenarios
    }

    /// Senaryoyu oynatır: her olaydan önce saat o ana ilerler (süreye bağlı kurallar arada tetiklenir); sonda saat son
    /// olayda durur ve bekleyen "tek kök" grubu bırakılır.
    static func play(_ s: Scenario, watch: DiagWatch = DiagWatch()) -> [DiagTrigger] {
        var w = watch
        if let st = s.state {
            if let l = st["frameLuma"]?.number { w.context.frameLuma = Int(l) }
            if case .flag(let b)? = st["frameSame"] { w.context.frameSame = b }
            if st["region"]?.text == "manual" { w.context.regionManual = true }
        }
        var drops = s.dropCodes ?? []
        var out: [DiagTrigger] = []
        var last = 0.0
        for item in s.timeline {
            guard let t = item.first?.number, let code = item.dropFirst().first?.text else { continue }
            let value = item.count > 2 ? item[2].number.map { Int($0) } : nil
            let dropCode = code == "tv.drop" && !drops.isEmpty ? drops.removeFirst() : nil
            guard let signal = DiagSignal(code: code, value: value, dropCode: dropCode) else {
                XCTFail("\(s.name): tanınmayan iz kodu \(code)")
                continue
            }
            out += w.record(signal, at: t)
            last = t
        }
        out += w.advance(to: last)
        out += w.flush()
        return out
    }

    func testScenariosFromFixture() throws {
        let list = try Self.scenarios()
        XCTAssertEqual(list.count, 9)
        for s in list {
            let got = Self.play(s)
            XCTAssertEqual(got.count, s.expect.count, "\(s.name): \(got.map { "\($0.rule.rawValue)@\($0.at)" })")
            for (g, e) in zip(got, s.expect) {
                XCTAssertEqual(g.rule.rawValue, e.rule, s.name)
                XCTAssertEqual(g.cause, e.cause, s.name)
                XCTAssertEqual(g.severity.rawValue, e.sev, s.name)
                XCTAssertEqual(g.at, e.at, s.name)
                // Olay kurulabilmeli ve izde serbest metin olmamalı.
                let event = try XCTUnwrap(TelemetryEvent.diag(rule: g.rule.rawValue, cause: g.cause, severity: g.severity,
                                                              state: g.state, trail: g.trail), s.name)
                XCTAssertEqual(event.fields["cause"]?.stringValue, e.cause, s.name)
                XCTAssertTrue(g.trail.allSatisfy { (-3600...0).contains($0.seconds) }, s.name)
            }
        }
    }

    func testTrailIsStructuredAndRelative() throws {
        let s = try XCTUnwrap(Self.scenarios().first { $0.expect.first?.rule == "ps5.no_return" && $0.expect.first?.cause == "network_lost" })
        let t = try XCTUnwrap(Self.play(s).first)
        // Halka son 10 dk: 0. saniyedeki session.start düştü; tetikten (781) sonraki adım (800) izde yok.
        XCTAssertEqual(t.trail.map(\.code), ["net.down", "ps5.drop", "ps5.retry", "ps5.retry"])
        XCTAssertEqual(t.trail.map(\.seconds), [-181, -180, -141, -81])
        XCTAssertEqual(t.trail.last?.value, 2)
        XCTAssertEqual(t.state["ps5"], .string("down"))
        XCTAssertEqual(t.state["net"], .string("none"))
        XCTAssertEqual(t.state["retries"], .int(2))
    }

    func testRemoteConfigTurnsRuleOffAndChangesThreshold() {
        var w = DiagWatch()
        w.apply(.init(off: ["ps5.no_return"], limits: ["tr.slow.p90Ms": 4000, "ps5NoReturnSec": 60]))
        XCTAssertEqual(w.limits.trSlowP90Ms, 4000)
        XCTAssertEqual(w.limits.ps5NoReturnSec, 60)
        _ = w.record(.sessionStart, at: 0)
        _ = w.record(.ps5Drop(nil), at: 100)
        XCTAssertTrue((w.advance(to: 1000) + w.flush()).isEmpty, "kapatılan kural gitmez")

        var on = DiagWatch()
        on.apply(.init(limits: ["ps5NoReturnSec": 60]))
        _ = on.record(.sessionStart, at: 0)
        _ = on.record(.ps5Drop(.standby), at: 100)
        let got = on.advance(to: 1000) + on.flush()
        XCTAssertEqual(got.map(\.at), [160])
        XCTAssertEqual(got.first?.cause, "ps5_standby")
    }

    func testSingleRootKeepsHighestPriority() {
        var w = DiagWatch()
        _ = w.record(.sessionStart, at: 0)
        _ = w.record(.ps5Drop(nil), at: 100)
        for i in 0..<10 { _ = w.record(.trError(http: 500), at: 200 + Double(i)) }
        let got = w.advance(to: 2000) + w.flush()
        XCTAssertEqual(got.map(\.rule), [.ps5NoReturn], "tr.errors aynı 5 dk'da: yalnız öncelikli gider")
        XCTAssertEqual(got.first?.trail.last?.code, "tr.errors")
    }

    func testDailyLimits() {
        var w = DiagWatch()
        var sent: [DiagTrigger] = []
        for k in 0..<4 {
            let base = Double(k) * 2000
            sent += w.record(.sessionStart, at: base)
            sent += w.record(.ps5Drop(nil), at: base + 100)
            sent += w.advance(to: base + 1000)
            sent += w.record(.sessionStop, at: base + 1500)
        }
        sent += w.flush()
        XCTAssertEqual(sent.count, 1, "aynı sorun günde en çok 1")
        // Ertesi gün sayaç sıfırlanır.
        sent += w.record(.sessionStart, at: 86_400 + 10)
        sent += w.record(.ps5Drop(nil), at: 86_400 + 100)
        sent += w.advance(to: 86_400 + 1000) + w.flush()
        XCTAssertEqual(sent.count, 2)
    }

    /// Otomatik bildirim ayarı: ortak havuz ya da otomatik bildirim kapalıysa tetik gitmez ve günlük sayaçtan düşmez;
    /// açılınca aynı gün yine bir kez gider. Olay yalnız teşhis özetidir (kayıt satırı yok).
    @MainActor
    func testAutoReportGateFollowsSettingsAndDailyLimit() throws {
        var s = MacSettings()
        XCTAssertTrue(LiveEngine.autoReportAllowed(s))
        s.sharePool = false
        XCTAssertFalse(LiveEngine.autoReportAllowed(s), "ortak havuz kapalıysa gitmez")
        s.sharePool = true
        s.autoReport = false
        XCTAssertFalse(LiveEngine.autoReportAllowed(s))

        var allowed = false
        var sent: [TelemetryEvent] = []
        let m = DiagMonitor(directory: nil, send: { sent.append($0) }, log: { _ in })
        m.allowed = { allowed }
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        func noReturn(_ start: Double) {
            m.record(.sessionStart, at: t0.addingTimeInterval(start))
            m.record(.ps5Drop(.kicked), at: t0.addingTimeInterval(start + 10))
            m.tick(at: t0.addingTimeInterval(start + 600))
            m.record(.sessionStop, at: t0.addingTimeInterval(start + 700))
        }
        noReturn(0)
        XCTAssertTrue(sent.isEmpty, "ayar kapalı")
        XCTAssertEqual(m.watch.quota.total, 0, "kapalıyken sayaçtan düşmez")
        allowed = true
        noReturn(1000)
        noReturn(2000)
        m.flush()
        XCTAssertEqual(sent.count, 1, "aynı sorun günde bir kez")
        let e = try XCTUnwrap(sent.first)
        XCTAssertEqual(e.fields["rule"]?.stringValue, "ps5.no_return")
        let text = String(describing: e.fields)
        XCTAssertFalse(text.contains(".log"), "kayıt dosyası taşımaz")
    }

    func testLaunchQuietAndNetworkQuiet() {
        var w = DiagWatch()
        _ = w.record(.appLaunch, at: 0)
        _ = w.record(.sessionStart, at: 1)
        for i in 0..<12 { _ = w.record(.trError(http: 429), at: 2 + Double(i)) }
        XCTAssertTrue(w.flush().isEmpty, "açılışın ilk 60 sn'si susar")

        var n = DiagWatch()
        _ = n.record(.sessionStart, at: 0)
        _ = n.record(.ps5Frame(fps: 30), at: 0)
        _ = n.record(.netDown, at: 10)
        XCTAssertTrue((n.advance(to: 2000) + n.flush()).isEmpty, "ağ yokken ağ dışı kural (ocr.silent) susar")
    }

    func testTVFlappingCountsResumeAndIgnoresBackgroundQuiet() {
        var w = DiagWatch()
        _ = w.record(.sessionStart, at: 0)
        _ = w.record(.appBackground, at: 50)
        _ = w.record(.appForeground, at: 100)
        _ = w.record(.tvDrop(code: nil, upSec: 30), at: 105)
        _ = w.record(.appForeground, at: 200)
        _ = w.record(.tvDrop(code: "other", upSec: 30), at: 204)
        _ = w.record(.appForeground, at: 300)
        _ = w.record(.tvDrop(code: nil, upSec: 30), at: 302)
        let got = w.flush()
        XCTAssertEqual(got.map(\.rule), [.tvFlapping])
        XCTAssertEqual(got.first?.cause, "resume")
        XCTAssertEqual(got.first?.at, 302)
    }

    func testMixedCausesAndOtherRules() {
        var w = DiagWatch()
        _ = w.record(.sessionStart, at: 0)
        _ = w.record(.tvDrop(code: "timeout", upSec: 1), at: 100)
        _ = w.record(.tvDrop(code: "closed", upSec: 1), at: 110)
        _ = w.record(.tvDrop(code: "replaced", upSec: 1), at: 120)
        XCTAssertEqual(w.flush().first?.cause, "mixed")

        var r = DiagWatch()
        _ = r.record(.memory(mb: 2000), at: 0)
        _ = r.record(.memory(mb: 2100), at: 60)
        let res = r.advance(to: 130) + r.flush()
        XCTAssertEqual(res.map(\.rule), [.appResources])
        XCTAssertEqual(res.first?.at, 120)
        XCTAssertEqual(res.first?.cause, "memory_high")

        var h = DiagWatch()
        let hang = h.record(.hang(blockedSec: 7, previousRun: true), at: 0) + h.flush()
        XCTAssertEqual(hang.map(\.rule), [.appHang])
        XCTAssertEqual(hang.first?.state["blockedSec"], .int(7))

        var o = DiagWatch()
        _ = o.record(.sessionStart, at: 0)
        _ = o.record(.ps5Connect, at: 1)
        _ = o.record(.ps5Frame(fps: 30), at: 2)
        _ = o.record(.ps5Frame(fps: 0), at: 100)
        let stalled = o.advance(to: 200) + o.flush()
        XCTAssertEqual(stalled.map(\.rule), [.ocrStalled])
        XCTAssertEqual(stalled.first?.cause, "frames_stopped")
        XCTAssertEqual(stalled.first?.at, 130)

        var s = DiagWatch()
        _ = s.record(.sessionStart, at: 0)
        for i in 0..<20 { _ = s.record(.line(ms: 5000, origin: .provider), at: 100 + Double(i)) }
        let slow = s.flush()
        XCTAssertEqual(slow.map(\.rule), [.trSlow])
        XCTAssertEqual(slow.first?.cause, "provider_slow")
        XCTAssertEqual(slow.first?.at, 119)

        var p = DiagWatch()
        for i in 0..<3 { _ = p.record(.packFail(id: "gta-vi", http: 503), at: Double(i) * 10) }
        let pack = p.flush()
        XCTAssertEqual(pack.map(\.rule), [.packDownload])
        XCTAssertEqual(pack.first?.cause, "http_5xx")
    }

    func testRingKeepsTenMinutesAndAtMost200() {
        var w = DiagWatch()
        for i in 0..<500 { _ = w.record(.ps5Retry(i), at: Double(i)) }
        XCTAssertEqual(w.ring.count, 200)
        _ = w.record(.ps5Connect, at: 2000)
        XCTAssertEqual(w.ring.count, 1, "10 dk'dan eski adımlar düşer")
    }

    // MARK: Canlı taraf (sahte taşıyıcı, geçici klasör)

    @MainActor
    func testMonitorSendsDiagEventAtTriggerTimeAndPersistsQuota() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nino-diag-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        var sent: [TelemetryEvent] = []
        var lines: [String] = []
        let m = DiagMonitor(directory: dir, send: { sent.append($0) }, log: { lines.append($0) })
        m.game = { "gta-vi" }
        m.tvInfo = { .init(brand: .androidtv, model: "TCL 98U95A", app: "4.0.0") }
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        m.record(.sessionStart, at: t0)
        m.record(.ps5Drop(.kicked), at: t0.addingTimeInterval(10))
        m.tick(at: t0.addingTimeInterval(200))
        XCTAssertEqual(lines, ["Otomatik teşhis: ps5.no_return (kicked); bildirim 5 dk içinde kuyruğa"])
        XCTAssertTrue(sent.isEmpty, "tek kök penceresi dolmadan gitmez")
        m.tick(at: t0.addingTimeInterval(500))
        let e = try XCTUnwrap(sent.first)
        XCTAssertEqual(e.time, 1_800_000_190)
        XCTAssertEqual(e.fields["sev"]?.stringValue, "error")
        XCTAssertEqual(e.fields["game"]?.stringValue, "gta-6") // asıl kimlik (GameIDs)
        guard case let .object(tv)? = e.fields["tv"] else { return XCTFail("tv yok") }
        XCTAssertEqual(tv["model"]?.stringValue, "TCL 98U95A")
        let again = DiagMonitor(directory: dir, send: { _ in }, log: { _ in })
        XCTAssertEqual(again.watch.quota.total, 1, "günlük sayaç diskten okunur")
    }

    func testReportingProviderStatusCodes() {
        XCTAssertEqual(ReportingProvider.status(ProviderFailure.quotaExhausted), 429)
        XCTAssertEqual(ReportingProvider.status(ProviderFailure.invalidKey), 401)
        XCTAssertEqual(ReportingProvider.status(ProviderFailure.network), 0)
        XCTAssertEqual(ReportingProvider.status(ProviderFailure.server(503)), 503)
        XCTAssertEqual(ReportingProvider.status(URLError(.timedOut)), 408)
        XCTAssertNil(ReportingProvider.status(ProviderFailure.notReady), "gönderilmeyen istek sayılmaz")
    }

    func testFrameProbeDetectsBlackAndFrozen() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.01, green: 0.01, blue: 0.01, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 36))
        let image = try XCTUnwrap(ctx.makeImage())
        var p = FrameProbe()
        let t = Date()
        let first = try XCTUnwrap(p.sample(image, at: t))
        XCTAssertLessThanOrEqual(first.luma, 16)
        XCTAssertFalse(first.same)
        XCTAssertNil(p.sample(image, at: t.addingTimeInterval(1)), "5 sn'de bir")
        _ = p.sample(image, at: t.addingTimeInterval(5))
        XCTAssertEqual(p.sample(image, at: t.addingTimeInterval(10))?.same, true)
    }
}
