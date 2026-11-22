// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore
import XCTest
@testable import NinoMacKit

/// Elle ilerletilen saat (uykuları anında biter, zamanı ilerletmez).
final class SteppingTVClock: TVClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { lock.withLock { current } }
    func advance(_ s: TimeInterval) { lock.withLock { current = current.addingTimeInterval(s) } }
    func sleep(_ seconds: TimeInterval) async throws {
        try Task.checkCancellation()
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

@MainActor
final class TVLinkTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func drop(_ host: String = "192.168.0.40", at: TimeInterval, reason: DisplayLinkEvent.Reason = .writeStalled,
                      after: TimeInterval = 120) -> DisplayLinkEvent {
        DisplayLinkEvent(kind: reason.isTimeout ? .timedOut : .disconnected, route: .legacySSE, host: host,
                         connectionID: UUID().uuidString, model: "Samsung QE55Q80C", appVersion: "4.0.3",
                         at: t0.addingTimeInterval(at), duration: after, reason: reason)
    }

    private func connect(_ host: String = "192.168.0.40", at: TimeInterval) -> DisplayLinkEvent {
        DisplayLinkEvent(kind: .connected, route: .legacySSE, host: host, connectionID: UUID().uuidString,
                         model: "Samsung QE55Q80C", appVersion: "4.0.3", at: t0.addingTimeInterval(at))
    }

    // Tekrarlayan kopma artık otomatik teşhisin `tv.flapping` kuralı: DiagWatchTests ve aşağıdaki motor testi.

    // MARK: Ölçüm

    func testMeterSendsConnectAndDropWithCodesButNoAddress() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nino-tvlink-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let t = Telemetry(options: .init(endpoint: URL(string: "http://127.0.0.1:9/v1/events")!, installID: UUID().uuidString,
                                         context: .current(app: "4.1.0", channel: "dev"), directory: dir, enabled: true),
                          transport: SessionOverlaysTests.FakeTelemetryTransport())
        let m = SessionMeter(telemetry: t)
        m.sessionStarted(at: t0)
        m.tvLink(connect(at: 2), brand: .samsung, wokeAt: nil)
        m.tvLink(drop(at: 300, reason: .writeStalled), brand: .samsung, wokeAt: nil)
        m.tvLink(drop(at: 400, reason: .peerClosed), brand: .samsung, wokeAt: nil)
        m.tvLink(drop(at: 500, reason: .writeFailed), brand: .samsung, wokeAt: nil)
        m.tvLink(drop(at: 600, reason: .heartbeatTimeout), brand: .samsung, wokeAt: t0.addingTimeInterval(580))
        m.tvLink(drop(at: 700, reason: .serverStopped), brand: .samsung, wokeAt: nil)
        try await Task.sleep(for: .milliseconds(200))
        let q = await t.queued
        let c = try XCTUnwrap(q.first { $0.kind == .tvConnect })
        XCTAssertEqual(c.fields["ms"], .int(2_000))
        XCTAssertEqual(c.fields["proto"], .string("legacy"))
        XCTAssertEqual(c.fields["model"], .string("Samsung QE55Q80C"))
        XCTAssertEqual(c.fields["tvApp"], .string("4.0.3"))
        let drops = q.filter { $0.kind == .tvDrop }
        XCTAssertEqual(drops.map { $0.fields["code"] }, ["timeout", "closed", "write_error", "resume"].map { .string($0) },
                       "sunucu durdu sayılmaz")
        XCTAssertEqual(drops.first?.fields["after"], .int(120))
        let json = String(decoding: try JSONEncoder().encode(q), as: UTF8.self)
        XCTAssertFalse(json.contains("192.168"), "adres gitmez")
    }

    // MARK: Günlük ve sağlık

    func testLogLineHasEventAddressRouteDurationReason() {
        let line = TVLinkText.logLine(drop(at: 0, reason: .writeStalled, after: 61.6))
        XCTAssertEqual(line, #"TV zaman aşımı: adres 192.168.0.40, yol sse-8787, süre 62 sn, neden write-stalled, model "Samsung QE55Q80C", TV uygulaması 4.0.3"#)
        XCTAssertTrue(TVLinkText.logLine(connect(at: 0)).hasPrefix("TV bağlandı: adres 192.168.0.40, yol sse-8787"))
    }

    func testHealthCauseAndText() {
        XCTAssertEqual(TVLinkText.cause(.replaced, at: t0, wokeAt: nil), .closed)
        XCTAssertEqual(TVLinkText.cause(.heartbeatTimeout, at: t0, wokeAt: nil), .timeout)
        XCTAssertEqual(TVLinkText.cause(.readFailed, at: t0, wokeAt: nil), .network)
        XCTAssertEqual(TVLinkText.cause(.peerClosed, at: t0.addingTimeInterval(30), wokeAt: t0), .resume)
        let note = TVDropNote(date: t0, cause: .timeout)
        let tr = HealthText.lastTVDrop(note, Locale(identifier: "tr_TR"), now: t0)
        let en = HealthText.lastTVDrop(note, Locale(identifier: "en_US"), now: t0)
        XCTAssertTrue(tr?.contains("TV sustu, veri almayı bıraktı") == true, tr ?? "")
        XCTAssertTrue(en?.contains("the TV went quiet") == true, en ?? "")
        XCTAssertNil(HealthText.lastTVDrop(nil, Locale(identifier: "tr_TR"), now: t0))
    }

    func testNewStringsExistInAll12Languages() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NinoMacKit/Resources/Sheets.xcstrings")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        let langs = ["ar", "bn", "en", "fil", "hi", "id", "ms", "nl", "th", "tr", "ur", "vi"]
        var keys = ["sheets.health.tv.lastDrop %@ %@"]
        keys += TVDropNote.Cause.allCases.map { "sheets.health.tv.dropCause.\($0.rawValue)" }
        for k in keys {
            let loc = try XCTUnwrap((strings[k] as? [String: Any])?["localizations"] as? [String: Any], k)
            XCTAssertEqual(loc.keys.sorted(), langs, k)
        }
    }

    // MARK: Motor: olay → günlük + sağlık

    func testEngineLogsEventsAndRecordsLastDropWhileTranslating() async throws {
        let suite = "nino-tvlink-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nino-tvlink-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let env = LiveEngineEnvironment(
            identity: AppIdentity(flavor: .testing, defaultsDomain: suite, keychainService: "test", folderName: "test"),
            folder: DataFolder(support: root, logs: root), settingsStore: SettingsStore(defaults: defaults), vault: MemoryVault(),
            ports: .ephemeral, appVersion: "4.1.0", poolBaseURL: nil, packsBaseURL: nil, poolTransport: nil,
            providerTransport: URLSession.shared, deviceProvider: { nil }, textReader: SessionOverlaysTests.FailingReader(fail: false),
            clock: GameReading.SystemClock(), checksTranslatorReadiness: false)
        let state = AppState()
        let engine = LiveEngine(state: state, environment: env)
        engine.tvLinkEvent(connect(at: 0))
        XCTAssertNil(state.health.lastTVDrop, "çeviri kapalıyken yalnız günlük")
        state.translation = .on
        engine.diag.record(.sessionStart, at: t0)
        var sent: [TelemetryEvent] = []
        engine.diag.send = { sent.append($0) }
        engine.tvLinkEvent(drop(at: 100, reason: .serverStopped))
        XCTAssertNil(state.health.lastTVDrop, "bu tarafın kapatması kopma sayılmaz")
        engine.tvLinkEvent(drop(at: 200, reason: .writeStalled))
        XCTAssertEqual(state.health.lastTVDrop, TVDropNote(date: t0.addingTimeInterval(200), cause: .timeout))
        XCTAssertEqual(state.sheetsStatus.healthMetrics.tvDrops, 1)
        engine.tvLinkEvent(drop("192.168.0.41", at: 300, reason: .peerClosed))
        engine.tvLinkEvent(drop(at: 400, reason: .peerClosed))
        engine.diag.flush()
        state.translation = .off
        // 3. kopmada tv.flapping (yerel kapatma sayılmaz; TV'ler birlikte sayılır), çoğunluk sebebi `closed`.
        XCTAssertEqual(sent.count, 1)
        let e = try XCTUnwrap(sent.first)
        XCTAssertEqual(e.kind, .diag)
        XCTAssertEqual(e.fields["rule"]?.stringValue, "tv.flapping")
        XCTAssertEqual(e.fields["cause"]?.stringValue, "closed")
        XCTAssertEqual(e.time, Int(t0.timeIntervalSince1970) + 400)
        let body = String(decoding: try JSONEncoder().encode(e), as: UTF8.self)
        XCTAssertFalse(body.contains("192.168"), "teşhiste adres yok: \(body)")
        XCTAssertTrue(body.contains("[-200,\"tv.drop\",120]"), body)
        engine.subtitleLog.flush()
        let log = try String(contentsOf: env.folder.subtitleLog, encoding: .utf8)
        XCTAssertTrue(log.contains("TV bağlandı: adres 192.168.0.40, yol sse-8787"))
        XCTAssertTrue(log.contains("TV zaman aşımı: adres 192.168.0.40, yol sse-8787, süre 120 sn, neden write-stalled"))
        XCTAssertTrue(log.contains("neden server-stopped"))
        XCTAssertTrue(log.contains("Otomatik teşhis: tv.flapping (closed)"), log)
    }

    /// Oturumdan önce bağlanan TV'nin `tv_connect`'i oturum başında gider; eşi olmayan kopma gönderilmez.
    /// Kapanışta "tek kök" penceresinde bekleyen teşhis kaybolmaz: zorunlu gönderimden önce kuyruğa girer.
    func testTerminateQueuesPendingDiag() async throws {
        let suite = "nino-tvlink-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nino-tvlink-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var env = LiveEngineEnvironment(
            identity: AppIdentity(flavor: .testing, defaultsDomain: suite, keychainService: "test", folderName: "test"),
            folder: DataFolder(support: root, logs: root), settingsStore: SettingsStore(defaults: defaults), vault: MemoryVault(),
            ports: .ephemeral, appVersion: "4.1.0", poolBaseURL: URL(string: "http://127.0.0.1:9"), packsBaseURL: nil,
            poolTransport: nil, providerTransport: URLSession.shared, deviceProvider: { nil },
            textReader: SessionOverlaysTests.FailingReader(fail: false), clock: GameReading.SystemClock(),
            checksTranslatorReadiness: false)
        env.telemetryTransport = SessionOverlaysTests.FakeTelemetryTransport()
        let engine = LiveEngine(state: AppState(), environment: env)
        engine.diag.record(.hang(blockedSec: 9, previousRun: true))
        XCTAssertEqual(engine.diag.watch.pending.count, 1)
        engine.appWillTerminate()
        let q = try await XCTUnwrap(engine.meter?.telemetry).queued
        let d = try XCTUnwrap(q.first { $0.kind == .diag })
        XCTAssertEqual(d.fields["rule"]?.stringValue, "app.hang")
    }

    func testEngineNeverSendsUnpairedDrops() async throws {
        let suite = "nino-tvlink-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nino-tvlink-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var env = LiveEngineEnvironment(
            identity: AppIdentity(flavor: .testing, defaultsDomain: suite, keychainService: "test", folderName: "test"),
            folder: DataFolder(support: root, logs: root), settingsStore: SettingsStore(defaults: defaults), vault: MemoryVault(),
            ports: .ephemeral, appVersion: "4.1.0", poolBaseURL: URL(string: "http://127.0.0.1:9"), packsBaseURL: nil,
            poolTransport: nil, providerTransport: URLSession.shared, deviceProvider: { nil },
            textReader: SessionOverlaysTests.FailingReader(fail: false), clock: GameReading.SystemClock(),
            checksTranslatorReadiness: false)
        env.telemetryTransport = SessionOverlaysTests.FakeTelemetryTransport()
        let state = AppState()
        let engine = LiveEngine(state: state, environment: env)
        let early = connect(at: 0)
        engine.tvLinkEvent(early)
        let gone = connect("192.168.0.41", at: 1)
        engine.tvLinkEvent(gone)
        state.translation = .on
        engine.meter?.sessionStarted()
        engine.tvLinksSessionStarted()
        var d = drop(at: 50, reason: .peerClosed)
        d.connectionID = early.connectionID
        engine.tvLinkEvent(d)
        engine.tvLinkEvent(drop("192.168.0.42", at: 60, reason: .peerClosed))
        try await Task.sleep(for: .milliseconds(200))
        let q = try await XCTUnwrap(engine.meter?.telemetry).queued
        XCTAssertEqual(q.filter { $0.kind == .tvConnect }.count, 2, "oturumdan önce bağlanan iki TV")
        XCTAssertEqual(q.filter { $0.kind == .tvDrop }.count, 1, "eşi olmayan kopma gitmez")
        state.translation = .off
    }

    /// Bekçi bir saat boyunca Samsung TV'yi açık tutmaya çalışır ama TV uygulamasını yeniden kurmayı/denetlemeyi denemez.
    func testSamsungKeeperNeverRunsInstallerForAnHour() async throws {
        let f = TVFakes()
        defer { f.cleanUp() }
        try f.records.setTV(TVRecord(name: "S", host: "192.168.0.7", brand: .samsung))
        try f.records.setTVAppVersion("0.7.0")
        f.sockets.factory = { FakeSocket(url: $0, initial: [#"{"event":"ms.channel.connect","data":{"token":"T1"}}"#]) }
        f.processes.startHandler = { _ in FakeRunning(lines: [#"{"event":"done","version":"0.7.0","installed":false}"#]) }
        let state = AppState()
        let c = TVSetupController(state: state, environment: f.environment())
        let start = f.clock.now()
        c.startKeepingAppOpen()
        let deadline = Date().addingTimeInterval(60)
        while f.clock.now().timeIntervalSince(start) < 3600, Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
        c.stopKeepingAppOpen()
        XCTAssertGreaterThanOrEqual(f.clock.now().timeIntervalSince(start), 3600)
        XCTAssertEqual(samsungRuns(f), 0)
        XCTAssertGreaterThan(f.sockets.opened.count, 0, "bekçi uygulamayı açtı")
        c.shutdown()
    }

    /// Gerçek yerel soket: DisplayLinks eski sunucunun olaylarını iletir.
    func testDisplayLinksForwardsLegacyEvents() async throws {
        let links = DisplayLinks(ports: .ephemeral, appVersion: "4.1.0")
        let seen = Recorder()
        links.onLinkEvent = { seen.add($0) }
        await links.startServers()
        let port = try XCTUnwrap(links.legacyPort)
        let session = URLSession(configuration: .ephemeral)
        let task = Task {
            guard let (bytes, _) = try? await session.bytes(from: URL(string: "http://127.0.0.1:\(port)/events?model=LG&app=4.0.3")!)
            else { return }
            for try await _ in bytes.lines {}
        }
        for _ in 0..<150 where seen.all.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(seen.all.first?.kind, .connected)
        XCTAssertEqual(seen.all.first?.appVersion, "4.0.3")
        task.cancel()
        session.invalidateAndCancel()
        for _ in 0..<150 where seen.all.count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(seen.all.count, 2)
        XCTAssertNotEqual(seen.all.last?.kind, .connected)
        await links.stop()
    }

    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [DisplayLinkEvent] = []
        func add(_ e: DisplayLinkEvent) { lock.withLock { items.append(e) } }
        var all: [DisplayLinkEvent] { lock.withLock { items } }
    }

    // MARK: Samsung / LG denetimi tekrarlanmaz

    private func samsungRig(_ f: TVFakes, clock: SteppingTVClock) throws -> (AppState, TVSetupController) {
        try f.records.setTV(TVRecord(name: "S", host: "192.168.0.7", brand: .samsung))
        f.http.set("http://192.168.0.7:8001/api/v2/", 200, #"{"device":{"developerMode":"1","developerIP":"192.168.0.10"}}"#)
        f.http.set("http://192.168.0.8:8001/api/v2/", 200, #"{"device":{"developerMode":"1","developerIP":"192.168.0.10"}}"#)
        f.ports.set("192.168.0.7", 26101, true)
        f.ports.set("192.168.0.8", 26101, true)
        f.processes.startHandler = { _ in FakeRunning(lines: [#"{"event":"done","version":"0.7.0","installed":false}"#]) }
        var env = f.environment()
        env.clock = clock
        let state = AppState()
        return (state, TVSetupController(state: state, environment: env))
    }

    private func samsungRuns(_ f: TVFakes) -> Int {
        f.processes.allCalls.filter { $0.arguments.first == "samsung-install" }.count
    }

    func testSamsungCheckDoesNotRepeatForAnHourAfterNoInstallNeeded() async throws {
        let f = TVFakes()
        defer { f.cleanUp() }
        let clock = SteppingTVClock()
        let (state, c) = try samsungRig(f, clock: clock)
        c.recheckTVApp()
        await waitUntil { state.setup.tvApp == .ready(version: "0.7.0", lgHoursLeft: nil) }
        XCTAssertEqual(samsungRuns(f), 1)
        // Bir saat boyunca 30 sn'de bir kendiliğinden denetim (eski günlükteki gibi).
        for _ in 0..<120 {
            clock.advance(30)
            c.recheckTVApp()
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        await c.appTaskForTests?.value
        XCTAssertEqual(samsungRuns(f), 1, "kurulum gerekmedi sonrası tekrar yok")
        XCTAssertEqual(state.setup.tvApp, .ready(version: "0.7.0", lgHoursLeft: nil))

        // Kullanıcı "Tekrar Dene": çalışır.
        c.recheckTVApp(force: true)
        await waitUntil { self.samsungRuns(f) == 2 }
        await c.appTaskForTests?.value
        XCTAssertEqual(samsungRuns(f), 2)

        // Susma süresi bitince kendiliğinden yeniden.
        clock.advance(TVAppCheckGate.quietPeriod + 1)
        c.recheckTVApp()
        await waitUntil { self.samsungRuns(f) == 3 }
        await c.appTaskForTests?.value
        XCTAssertEqual(samsungRuns(f), 3)

        // TV adresi değişince (kayıtlı sürüm silinir) hemen.
        try f.records.setTV(TVRecord(name: "S", host: "192.168.0.8", brand: .samsung))
        c.recheckTVApp()
        await waitUntil { self.samsungRuns(f) == 4 }
        XCTAssertEqual(samsungRuns(f), 4)
        c.shutdown()
    }

    func testGateRules() {
        var g = TVAppCheckGate()
        let key = TVAppCheckGate.Key(brand: .samsung, host: "192.168.0.7", bundled: "0.7.0")
        XCTAssertNil(g.freshVersion(key, recorded: "0.7.0", requireRecorded: true, now: t0), "ilk denetim çalışır")
        g.confirm(key, version: "0.7.0", now: t0)
        XCTAssertEqual(g.freshVersion(key, recorded: "0.7.0", requireRecorded: true, now: t0.addingTimeInterval(3600)), "0.7.0")
        XCTAssertNil(g.freshVersion(key, recorded: nil, requireRecorded: true, now: t0), "kurulu sürüm bilinmiyor")
        XCTAssertNil(g.freshVersion(TVAppCheckGate.Key(brand: .samsung, host: "192.168.0.7", bundled: "0.8.0"),
                                    recorded: "0.7.0", requireRecorded: true, now: t0), "paket sürümü değişti")
        XCTAssertNil(g.freshVersion(TVAppCheckGate.Key(brand: .lg, host: "192.168.0.7", bundled: "0.7.0"),
                                    recorded: nil, requireRecorded: false, now: t0), "marka değişti")
        XCTAssertNil(g.freshVersion(key, recorded: "0.7.0", requireRecorded: true,
                                    now: t0.addingTimeInterval(TVAppCheckGate.quietPeriod)), "birkaç saat sonra yeniden")
    }
}
