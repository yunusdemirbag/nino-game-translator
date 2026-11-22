// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import XCTest
@testable import NinoCore

/// Sahte sunucu: gelen gövdeleri açıp saklar, sıradaki cevabı verir.
final class FakeTelemetryServer: TelemetryTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _bodies: [[String: Any]] = []
    private var _gzipped: [Bool] = []
    var replies: [TelemetryResponse] = []
    var failNetwork = false

    var bodies: [[String: Any]] { lock.withLock { _bodies } }
    var gzipped: [Bool] { lock.withLock { _gzipped } }

    func send(_ body: Data, gzip: Bool, to url: URL) async throws -> TelemetryResponse {
        let raw = gzip ? try Gzip.decompress(body) : body
        let json = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
        return try lock.withLock {
            if failNetwork { throw URLError(.notConnectedToInternet) }
            _bodies.append(json)
            _gzipped.append(gzip)
            return replies.isEmpty ? Self.ok() : replies.removeFirst()
        }
    }

    static func ok(_ extra: String = "") -> TelemetryResponse {
        TelemetryResponse(status: 200, body: Data(#"{"ok":true,"accepted":1,"dropped":0\#(extra),"config":{"enabled":true,"sample":1,"maxPerDay":1000,"flushSeconds":600}}"#.utf8))
    }
}

final class TestClock: @unchecked Sendable {
    var now: TimeInterval = 1_763_300_000
    func date() -> Date { Date(timeIntervalSince1970: now) }
}

final class TelemetryTests: XCTestCase {
    private var dir: URL!
    private let install = "8D0F5C9E-3B1A-4C2D-9E8F-7A6B5C4D3E2F"

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nino-telemetry-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func make(_ server: FakeTelemetryServer, clock: TestClock = TestClock(), enabled: Bool = true) -> Telemetry {
        var options = Telemetry.Options(
            endpoint: URL(string: "https://pool.example/v1/events")!, installID: install,
            context: TelemetryContext(platform: "mac", app: "4.0.0", os: "macOS 27.0", device: "Mac16,1", tv: "androidtv"),
            directory: dir, enabled: enabled)
        options.flushThreshold = 10_000
        return Telemetry(options: options, transport: server, clock: { clock.date() })
    }

    // MARK: - Histogram

    func testHistogramBucketsMatchTheRecipe() {
        XCTAssertEqual(LatencyHistogram.edges.count, 18)
        XCTAssertEqual(LatencyHistogram.bucket(of: 0), 0)
        XCTAssertEqual(LatencyHistogram.bucket(of: 5), 0)
        XCTAssertEqual(LatencyHistogram.bucket(of: 6), 1)
        XCTAssertEqual(LatencyHistogram.bucket(of: 10_000), 17)
        XCTAssertEqual(LatencyHistogram.bucket(of: 10_001), 18)

        var h = LatencyHistogram()
        for v in [40, 45, 60, 140] { h.record(v) }
        XCTAssertEqual(h.jsonValue, .object(["n": .int(4), "sum": .int(285), "max": .int(140),
                                            "h": .array([0, 0, 0, 0, 2, 1, 0, 1].map { .int($0) })]))
        // Sunucuyla aynı yüzdelik: 100 değer 100–150 kovasında → p50 = 125; en büyük 130 ise p100 = 130.
        var flat = LatencyHistogram()
        for _ in 0..<99 { flat.record(120) }
        flat.record(150)
        XCTAssertEqual(flat.percentile(0.5), 125)
        XCTAssertNil(LatencyHistogram().percentile(0.5))
    }

    func testSessionTimingsKeepProviderNamesAndRejectBadMetrics() {
        var t = SessionTimings()
        t.recordProvider("DeepL", ms: 400)
        t.record("ocr", ms: 30)
        t.record("Bad Name", ms: 1)
        t.record(SessionTimings.Metric.total, ms: 800)
        XCTAssertEqual(Set(t.histograms.keys), ["tr.provider", "tr.provider:deepl", "ocr", "tr.total"])
        for i in 0..<40 { t.record("m\(i)", ms: 1) }
        XCTAssertEqual(t.histograms.count, SessionTimings.maxMetrics)
    }

    // MARK: - Olaylar ve gizlilik

    func testEventsEncodeFlatWithRecipeFields() throws {
        var timings = SessionTimings()
        timings.record("ocr", ms: 40)
        let events: [TelemetryEvent] = [
            .launch(ms: 640),
            .crash(code: "SIGSEGV", where: "ReadingPipeline.process", version: "3.9.0", uptime: 1820),
            .ps5Connect(result: "ok", ms: 2840, via: .lan),
            .tvConnect(result: "ok", ms: 420, brand: .androidtv, proto: .nino),
            .error("tr.provider.http", http: 429, count: 3)!,
            .ps5Drop(TelemetryCode.Drop.networkLost, after: 2950),
            .tvDrop("timeout", brand: .androidtv, after: 3050),
            .session(duration: 3580, game: "gta-vi", source: .remoteplay, lines: 412, timings: timings),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let keys = try events.map { e -> [String] in
            let o = try JSONSerialization.jsonObject(with: encoder.encode(e)) as! [String: Any]
            return o.keys.sorted()
        }
        // Örnek gövde (nino-pool/test/fixtures/events-v1.json) ile aynı alanlar.
        XCTAssertEqual(keys, [
            ["k", "ms", "t"],
            ["code", "k", "t", "up", "ver", "where"],
            ["k", "ms", "r", "t", "via"],
            ["brand", "k", "ms", "proto", "r", "t"],
            ["code", "http", "k", "n", "t"],
            ["after", "code", "k", "t"],
            ["after", "brand", "code", "k", "t"],
            ["dur", "game", "h", "k", "lines", "src", "t"],
        ])
        let back = try JSONDecoder().decode([TelemetryEvent].self, from: encoder.encode(events))
        XCTAssertEqual(back, events)
    }

    func testFreeTextNeverBecomesACode() {
        XCTAssertNil(TelemetryEvent.error("Dosya bulunamadı: /Users/yunus/Desktop/a.txt"))
        XCTAssertNil(TelemetryEvent.error("connection refused 192.168.0.110"))
        XCTAssertNotNil(TelemetryEvent.error(TelemetryCode.ps5AuthExpired))
        let crash = TelemetryEvent.crash(code: "*** -[NSArray objectAtIndex:]: index 3", where: "/Users/yunus/Nino/App.swift:12", version: "4.0.0")
        XCTAssertEqual(crash.fields["code"], .string("unclean_exit"))
        XCTAssertNil(crash.fields["where"])
        let bad = TelemetryEvent.ps5Connect(result: "Hata oldu", ms: 10, via: .lan)
        XCTAssertEqual(bad.fields["r"], .string(TelemetryCode.ps5Other))
        XCTAssertNil(TelemetryEvent.session(duration: 1, game: "../etc", source: .capture, lines: 0).fields["game"])
    }

    func testTVEventsCarryModelAndAppVersionOnlyWhenClean() {
        let drop = TelemetryEvent.tvDrop(TelemetryCode.Drop.writeError, brand: .androidtv, after: 900,
                                         model: "TCL 98U95A", tvApp: "4.0.0")
        XCTAssertEqual(drop.fields["model"], .string("TCL 98U95A"))
        XCTAssertEqual(drop.fields["tvApp"], .string("4.0.0"))
        XCTAssertEqual(drop.fields["code"], .string("write_error"))
        let named = TelemetryEvent.tvConnect(result: "ok", ms: 10, brand: .lg, proto: .nino, model: "Yunus'un TV'si", tvApp: "x y")
        XCTAssertNil(named.fields["model"])
        XCTAssertNil(named.fields["tvApp"])
    }

    func testDiagnosisCarriesOnlyCodesAndNumbers() throws {
        let e = try XCTUnwrap(TelemetryEvent.diag(
            rule: "ps5.no_return", cause: "network_lost", severity: .error,
            state: ["net": .string("wifi"), "memMB": .int(410), "msg": .string("bağlantı reddedildi /Users/yunus"), "bad key": .int(1)],
            trail: [.init(-240, "net.change", 1), .init(-30, "net.down"), .init(5, "gelecek"), .init(-10, "Hata: /Users/x")],
            tv: (brand: .androidtv, model: "TCL 98U95A", app: "4.0.0"), game: "gta-vi", versions: ["core": "1.0.0", "a b": "1"]))
        XCTAssertEqual(e.kind, .diag)
        XCTAssertEqual(e.fields["state"], .object(["net": .string("wifi"), "memMB": .int(410)]))
        XCTAssertEqual(e.fields["trail"], .array([.array([.int(-240), .string("net.change"), .int(1)]), .array([.int(-30), .string("net.down")])]))
        XCTAssertEqual(e.fields["tv"], .object(["brand": .string("androidtv"), "model": .string("TCL 98U95A"), "app": .string("4.0.0")]))
        XCTAssertEqual(e.fields["ver"], .object(["core": .string("1.0.0")]))
        XCTAssertNil(TelemetryEvent.diag(rule: "Kötü Kural", cause: "x"))
        XCTAssertEqual(TelemetryEvent.diag(rule: "tr.slow", cause: "çok yavaş!")?.fields["cause"], .string("unknown"))
    }

    func testDiagnosisIsExemptFromTheDailyCapAndConfigDecodes() async throws {
        let server = FakeTelemetryServer()
        let t = make(server)
        await t.applyRemoteConfig(TelemetryRemoteConfig(maxPerDay: 1))
        await t.record(.launch())
        await t.record(.launch()) // sınır doldu
        await t.record(try XCTUnwrap(TelemetryEvent.diag(rule: "tr.slow", cause: "pool_slow")))
        let kinds = await t.queued.map(\.kind)
        XCTAssertEqual(kinds, [.launch, .diag])
        let json = Data(#"{"enabled":true,"sample":1,"maxPerDay":1000,"flushSeconds":600,"diag":{"off":["ocr.silent"],"limits":{"tr.slow.p90Ms":4000}}}"#.utf8)
        let config = try JSONDecoder().decode(TelemetryRemoteConfig.self, from: json)
        XCTAssertTrue(config.diag?.isOff("ocr.silent") ?? false)
        XCTAssertEqual(config.diag?.limit("tr.slow.p90Ms", default: 3000), 4000)
        let old = try JSONDecoder().decode(TelemetryRemoteConfig.self, from: Data(#"{"enabled":true,"sample":1,"maxPerDay":1000,"flushSeconds":600}"#.utf8))
        XCTAssertNil(old.diag)
    }

    func testGzipRoundTripsWithTheExistingDecompressor() throws {
        let text = Data(String(repeating: "Nino ölçüm 🎮 ", count: 500).utf8)
        let packed = try XCTUnwrap(TelemetryGzip.compress(text))
        XCTAssertTrue(Gzip.isGzip(packed))
        XCTAssertLessThan(packed.count, text.count / 4)
        XCTAssertEqual(try Gzip.decompress(packed), text)
        XCTAssertEqual(try Gzip.decompress(XCTUnwrap(TelemetryGzip.compress(Data("{}".utf8)))), Data("{}".utf8))
        XCTAssertEqual(TelemetryGzip.crc32(Array("123456789".utf8)), 0xCBF4_3926)
    }

    func testSamplingIsStablePerInstall() {
        XCTAssertTrue(TelemetryRemoteConfig.isSampled(install: install, sample: 1))
        XCTAssertFalse(TelemetryRemoteConfig.isSampled(install: install, sample: 0))
        let ids = (0..<2000).map { _ in UUID().uuidString }
        let picked = ids.filter { TelemetryRemoteConfig.isSampled(install: $0, sample: 0.25) }.count
        XCTAssertTrue((350...650).contains(picked), "\(picked)")
        XCTAssertEqual(TelemetryRemoteConfig.isSampled(install: install, sample: 0.5),
                       TelemetryRemoteConfig.isSampled(install: install.lowercased(), sample: 0.5))
    }

    // MARK: - Kuyruk ve gönderim

    func testFlushSendsGzippedBatchWithContextAndClearsQueue() async throws {
        let server = FakeTelemetryServer()
        let t = make(server)
        await t.record(.launch())
        await t.record(.ps5Connect(result: "ok", ms: 2000, via: .lan))
        let result = await t.flush()
        XCTAssertEqual(result, .sent(2))
        let queued = await t.queuedCount
        XCTAssertEqual(queued, 0)
        XCTAssertEqual(server.gzipped, [true])
        let body = try XCTUnwrap(server.bodies.first)
        XCTAssertEqual(body["v"] as? Int, 1)
        XCTAssertEqual(body["install"] as? String, install.lowercased())
        XCTAssertNotNil(UUID(uuidString: body["batch"] as? String ?? ""))
        let ctx = try XCTUnwrap(body["ctx"] as? [String: String])
        XCTAssertEqual(ctx, ["platform": "mac", "app": "4.0.0", "os": "macOS 27.0", "device": "Mac16,1", "tv": "androidtv", "channel": "release"])
        let events = try XCTUnwrap(body["events"] as? [[String: Any]])
        XCTAssertEqual(events.map { $0["k"] as? String }, ["launch", "ps5_connect"])
        XCTAssertEqual(events.first?["t"] as? Int, 1_763_300_000)
        let empty = await t.flush()
        XCTAssertEqual(empty, .empty)
    }

    func testRetryKeepsTheSameBatchIdAndWaits() async throws {
        let server = FakeTelemetryServer()
        let clock = TestClock()
        let t = make(server, clock: clock)
        server.replies = [TelemetryResponse(status: 429, retryAfter: 120)]
        await t.record(.launch())
        let first = await t.flush()
        XCTAssertEqual(first, .retryLater(120))
        // Bekleme bitmeden denenmez; arada gelen olay sonraki parçaya kalır.
        await t.record(.error("ocr.failed")!)
        let early = await t.flush()
        XCTAssertEqual(early, .waiting)
        clock.now += 121
        let second = await t.flush()
        XCTAssertEqual(second, .sent(1))
        XCTAssertEqual(server.bodies.count, 2)
        XCTAssertEqual(server.bodies[0]["batch"] as? String, server.bodies[1]["batch"] as? String)
        let third = await t.flush()
        XCTAssertEqual(third, .sent(1))
        XCTAssertNotEqual(server.bodies[2]["batch"] as? String, server.bodies[1]["batch"] as? String)

        // Ağ yok: artan aralıkla bekler, olay kaybolmaz.
        server.failNetwork = true
        await t.record(.launch())
        let offline = await t.flush(force: true)
        XCTAssertEqual(offline, .retryLater(60))
        let again = await t.flush(force: true)
        XCTAssertEqual(again, .retryLater(120))
        let kept = await t.queuedCount
        XCTAssertEqual(kept, 1)
    }

    func testBadRequestDropsAndTooLargeSplits() async {
        let server = FakeTelemetryServer()
        let t = make(server)
        server.replies = [TelemetryResponse(status: 400)]
        await t.record(.launch())
        let dropped = await t.flush()
        XCTAssertEqual(dropped, .dropped(1))

        for _ in 0..<4 { await t.record(.launch()) }
        server.replies = [TelemetryResponse(status: 413)]
        let split = await t.flush()
        XCTAssertEqual(split, .split)
        let half = await t.flush()
        XCTAssertEqual(half, .sent(2))
        let rest = await t.flush()
        XCTAssertEqual(rest, .sent(2))
    }

    func testNotFoundKeepsTheBatchUntilTheServerExists() async {
        let server = FakeTelemetryServer()
        let clock = TestClock()
        let t = make(server, clock: clock)
        server.replies = [TelemetryResponse(status: 404), TelemetryResponse(status: 503, retryAfter: 3600)]
        await t.record(.launch())
        let missing = await t.flush()
        XCTAssertEqual(missing, .retryLater(60))
        let notReady = await t.flush(force: true)
        XCTAssertEqual(notReady, .retryLater(3600))
        clock.now += 3601
        let sent = await t.flush()
        XCTAssertEqual(sent, .sent(1))
        XCTAssertEqual(Set(server.bodies.compactMap { $0["batch"] as? String }).count, 1)
    }

    /// Yerel havuz sunucusuna gerçek gönderim (Apple gzip'i + Workers açıcı + D1). Yalnız
    /// `NINO_POOL_URL=http://localhost:8799` verilince çalışır (`npm --prefix nino-pool run dev -- --port 8799`).
    func testRealServerAcceptsAndDeduplicates() async throws {
        guard let base = ProcessInfo.processInfo.environment["NINO_POOL_URL"], let root = URL(string: base) else {
            throw XCTSkip("NINO_POOL_URL yok")
        }
        final class Recorder: TelemetryTransport, @unchecked Sendable {
            let inner = URLSessionTelemetryTransport()
            var last: (Data, Bool)?
            func send(_ body: Data, gzip: Bool, to url: URL) async throws -> TelemetryResponse {
                last = (body, gzip)
                return try await inner.send(body, gzip: gzip, to: url)
            }
        }
        let recorder = Recorder()
        var options = Telemetry.Options(endpoint: root.appendingPathComponent("v1/events"), installID: UUID().uuidString,
                                        context: .current(app: "4.0.0-test", channel: "beta"), directory: dir, enabled: true)
        options.flushThreshold = 10_000
        let t = Telemetry(options: options, transport: recorder)
        var timings = SessionTimings()
        timings.record(SessionTimings.Metric.total, ms: 640)
        await t.record(.launch(ms: 500))
        await t.record(.ps5Connect(result: "ok", ms: 2500, via: .lan))
        await t.record(.session(duration: 120, game: "gta-vi", source: .remoteplay, lines: 5, timings: timings))
        let result = await t.flush()
        XCTAssertEqual(result, .sent(3))
        let (body, gzip) = try XCTUnwrap(recorder.last)
        XCTAssertTrue(gzip)
        let again = try await recorder.inner.send(body, gzip: true, to: options.endpoint)
        XCTAssertEqual(again.status, 200)
        let reply = try JSONSerialization.jsonObject(with: again.body) as? [String: Any]
        XCTAssertEqual(reply?["duplicate"] as? Bool, true)
    }

    func testQueueSurvivesRestart() async {
        let server = FakeTelemetryServer()
        let a = make(server)
        await a.record(.launch())
        await a.record(.error("tr.pool.unreachable")!)
        let b = make(server)
        let count = await b.queuedCount
        XCTAssertEqual(count, 2)
    }

    func testTurningOffDeletesEverythingAndStopsSending() async {
        let server = FakeTelemetryServer()
        let t = make(server)
        await t.appLaunched()
        await t.record(.launch())
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("queue.json").path))
        await t.setEnabled(false)
        await t.record(.launch())
        let count = await t.queuedCount
        XCTAssertEqual(count, 0)
        let result = await t.flush()
        XCTAssertEqual(result, .disabled)
        XCTAssertTrue(server.bodies.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("queue.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("running.json").path))

        // Kapalı başlatılan istemci eski kuyruğu da siler.
        let on = make(server)
        await on.record(.launch())
        _ = make(server, enabled: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("queue.json").path))
    }

    func testServerCanDisableAndLowerTheSample() async {
        let server = FakeTelemetryServer()
        let t = make(server)
        server.replies = [TelemetryResponse(status: 200, body: Data(#"{"ok":true,"config":{"enabled":true,"sample":0,"maxPerDay":1000,"flushSeconds":600}}"#.utf8))]
        await t.record(.launch())
        _ = await t.flush()
        var timings = SessionTimings()
        timings.record("ocr", ms: 30)
        await t.record(.session(duration: 60, game: "gta-vi", source: .remoteplay, lines: 3, timings: timings))
        let queued = await t.queued
        XCTAssertNil(queued.last?.fields["h"]) // örneklem dışında: süreler gitmez, oturum sayılır
        XCTAssertNotNil(queued.last?.fields["dur"])

        await t.applyRemoteConfig(TelemetryRemoteConfig(enabled: false))
        let active = await t.isActive
        XCTAssertFalse(active)
        let count = await t.queuedCount
        XCTAssertEqual(count, 0)
    }

    func testDailyCapKeepsCrashesAndErrorsAreCoalesced() async {
        let server = FakeTelemetryServer()
        let clock = TestClock()
        let t = make(server, clock: clock)
        await t.applyRemoteConfig(TelemetryRemoteConfig(maxPerDay: 3))
        await t.record(.error("ocr.failed")!)
        await t.record(.error("ocr.failed")!)
        await t.record(.error("tr.provider.http", http: 429)!)
        await t.record(.error("tr.provider.http", http: 500)!)
        await t.record(.launch()) // sınır doldu
        await t.record(.crash(code: "SIGABRT", version: "4.0.0")) // çökme yine girer
        let queued = await t.queued
        XCTAssertEqual(queued.map(\.kind), [.error, .error, .error, .crash])
        XCTAssertEqual(queued[0].fields["n"], .int(2))
        clock.now += 86400 // ertesi gün sayaç sıfırlanır
        await t.record(.launch())
        let next = await t.queuedCount
        XCTAssertEqual(next, 5)
    }

    func testUncleanExitIsReportedOnNextLaunch() async throws {
        let server = FakeTelemetryServer()
        let clock = TestClock()
        let first = make(server, clock: clock)
        await first.appLaunched(launchMs: 500)
        clock.now += 900
        await first.crashMarker.touch(now: Int(clock.now))
        // Uygulama burada çöktü: işaret silinmedi.
        let second = make(server, clock: clock)
        await second.appLaunched()
        let queued = await second.queued
        let crash = try XCTUnwrap(queued.first { $0.kind == .crash })
        XCTAssertEqual(crash.fields["code"], .string("unclean_exit"))
        XCTAssertEqual(crash.fields["ver"], .string("4.0.0"))
        XCTAssertEqual(crash.fields["up"], .int(900))

        // Düzgün kapanışta çökme yok.
        await second.appWillTerminate()
        let third = make(server, clock: clock)
        await third.appLaunched()
        let crashes = await third.queued.filter { $0.kind == .crash }.count
        XCTAssertEqual(crashes, 1)
    }
}
