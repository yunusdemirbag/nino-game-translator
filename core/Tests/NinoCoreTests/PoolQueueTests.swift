// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

final class PoolFilterTests: XCTestCase {
    func testTable() {
        let f = PoolFilter()
        XCTAssertTrue(f.accepts("Stay low!"))
        XCTAssertFalse(f.accepts("Take out the"))
        XCTAssertFalse(f.accepts("PHOTO MODE SELECT"))
        XCTAssertFalse(f.accepts("Lutfen Bekleyin, Oyun Yukleniyor."))
        XCTAssertFalse(f.accepts("Your friend signed in to the network."))
        XCTAssertTrue(f.accepts("Designed in the city."))
    }

    func testOtherRules() {
        let f = PoolFilter()
        XCTAssertFalse(f.accepts("and the boat sank slowly."))      // küçük harfle başlıyor
        XCTAssertFalse(f.accepts("100/100 HP 25% 40/40 +"))       // harf yarıdan az
        XCTAssertFalse(f.accepts("Bu çok güzel değil mi?"))       // Türkçe harf
        XCTAssertFalse(f.accepts(String(repeating: "Hello there. ", count: 50)))
        XCTAssertFalse(f.accepts("   "))
        XCTAssertEqual(f.prepare("Stay\u{200B}  low\n now!"), "Stay low now!")
        XCTAssertFalse(PoolFilter(isGarbage: { _ in true }).accepts("Stay low!"))
    }
}

final class PoolQueueTests: XCTestCase {
    var dir: URL!
    let clock = PoolTestClock()

    override func setUpWithError() throws { dir = try makeLibraryTempDirectory("nino-pool") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    var poolDir: URL { dir.appendingPathComponent("pool") }

    func makeQueue(_ transport: FakePoolTransport, app: String = "1.0", enabled: Bool = true, legacy: URL? = nil) -> PoolQueue {
        PoolQueue(directory: poolDir, configuration: PoolConfiguration(baseURL: poolTestServer, enabled: enabled, appVersion: app),
                  transport: transport, environment: clock.environment, legacyQueueFile: legacy)
    }

    func okHandler() -> FakePoolTransport.Handler {
        { r in (200, poolJSON(["ok": true, "batch": poolBody(r)["batch"] as! String]), [:]) }
    }

    func testRecordWritesPendingLine() async throws {
        let q = makeQueue(FakePoolTransport())
        let recorded = await q.record("Stay low!", game: "Mafia: The Old Country")
        let rejected = await q.record("Take out the")
        XCTAssertTrue(recorded)
        XCTAssertFalse(rejected)
        let text = try String(contentsOf: poolDir.appendingPathComponent("pending.jsonl"), encoding: .utf8)
        let row = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.split(separator: "\n")[0].utf8)) as? [String: Any])
        XCTAssertEqual(row["t"] as? String, "Stay low!")
        XCTAssertEqual(row["g"] as? String, "mafia-the-old-country")
        XCTAssertEqual(row["s"] as? Int, 1)
        XCTAssertEqual(row["a"] as? Int, 1_763_300_000)
        let install = await q.install
        XCTAssertNotNil(UUID(uuidString: install))
    }

    func testDisabledPoolRecordsNothing() async {
        let q = makeQueue(FakePoolTransport(), enabled: false)
        let ok = await q.record("Stay low!")
        XCTAssertFalse(ok)
    }

    func testFreezeMergesDuplicatesAndSends() async throws {
        let transport = FakePoolTransport(okHandler())
        let q = makeQueue(transport)
        await q.record("Stay low!", game: "gta-v")
        clock.advance(10)
        await q.record("Stay low!", game: "gta-v")
        await q.record("Who goes there?", game: "gta-v")
        let notDue = await q.freezeIsDue()
        XCTAssertFalse(notDue)
        clock.advance(120)
        let result = await q.run()
        XCTAssertEqual(result.sent, 1)

        let r = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(r.url?.path, "/v1/batches")
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.value(forHTTPHeaderField: "User-Agent"), "nino-pool/1 (mac; 1.0)")
        let body = poolBody(r)
        XCTAssertEqual(body["upTo"] as? Int, 3)
        XCTAssertEqual(body["platform"] as? String, "mac")
        let lines = try XCTUnwrap(body["lines"] as? [[String: Any]])
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0]["count"] as? Int, 2)
        XCTAssertEqual(lines[0]["first"] as? Int, 1_763_300_000)
        XCTAssertEqual(lines[0]["last"] as? Int, 1_763_300_010)
        let outbox = await q.outboxFiles()
        let pending = await q.pendingCount
        XCTAssertEqual(outbox, [])
        XCTAssertEqual(pending, 0)
        // Gövde anahtarları sıralı, `/` kaçışlanmaz.
        XCTAssertTrue(String(decoding: r.httpBody!, as: UTF8.self).hasPrefix("{\"app\":"))
    }

    func testBatchesHoldAtMost200DistinctLines() async throws {
        let q = makeQueue(FakePoolTransport())
        for i in 0..<450 { await q.record("Queue test line \(i) waits here.") }
        await q.freeze()
        let files = await q.outboxFiles()
        XCTAssertEqual(files.count, 3)
        XCTAssertTrue(files[0].hasPrefix("001763300000000-0000-"))
        let first = try JSONSerialization.jsonObject(with: Data(contentsOf: poolDir.appendingPathComponent("outbox").appendingPathComponent(files[0]))) as! [String: Any]
        XCTAssertEqual((first["lines"] as? [Any])?.count, 200)
        XCTAssertEqual(first["upTo"] as? Int, 200)
        let state = await q.state
        XCTAssertEqual(state.frozenThrough, 450)
    }

    func testResponses() async throws {
        let transport = FakePoolTransport()
        let q = makeQueue(transport)
        await q.record("Stay low right now!")
        await q.record("Who goes there at this hour?")
        await q.freeze()

        // Yanlış kimlik: parça kalır, hata sayılır, bekleme başlar.
        transport.setHandler { _ in (200, poolJSON(["ok": true, "batch": "baska"]), [:]) }
        var r = await q.sendRound()
        XCTAssertTrue(r.failed)
        var state = await q.state
        XCTAssertEqual(state.failures, 1)
        XCTAssertEqual(state.nextAttempt, clock.now.timeIntervalSince1970 + 30)
        // Bekleme sürerken denenmez.
        r = await q.sendRound()
        XCTAssertEqual(transport.requests.count, 1)

        // 429: Retry-After kadar beklenir.
        clock.advance(31)
        transport.setHandler { _ in (429, Data(), ["Retry-After": "120"]) }
        r = await q.sendRound()
        XCTAssertTrue(r.serverBusy)
        state = await q.state
        XCTAssertEqual(state.serverRetryAt, clock.now.timeIntervalSince1970 + 120)

        // 413: ikiye bölünür.
        clock.advance(121)
        transport.setHandler { _ in (413, Data(), [:]) }
        r = await q.sendRound()
        XCTAssertEqual(r.split, 1)
        var files = await q.outboxFiles()
        XCTAssertEqual(files.count, 2)

        // 413 tek satır ve 422: kenara.
        r = await q.sendRound()
        XCTAssertEqual(r.parked, 2)
        files = await q.outboxFiles()
        let parked = await q.parkedFiles()
        XCTAssertEqual(files, [])
        XCTAssertEqual(parked.count, 2)
    }

    func testRejectedLinesAreLogged() async throws {
        let transport = FakePoolTransport { r in
            (200, poolJSON(["ok": true, "batch": poolBody(r)["batch"] as! String, "rejected": [["i": 0, "reason": "spam"]]]), [:])
        }
        let q = makeQueue(transport)
        await q.record("Stay low right now!")
        await q.freeze()
        _ = await q.sendRound()
        let log = try String(contentsOf: poolDir.appendingPathComponent("rejected.jsonl"), encoding: .utf8)
        XCTAssertEqual(log, "{\"reason\":\"spam\",\"text\":\"Stay low right now!\"}\n")
    }

    func testBackoffGrowsAndNetworkResets() async {
        let transport = FakePoolTransport { _ in throw URLError(.notConnectedToInternet) }
        let q = makeQueue(transport)
        await q.record("Stay low right now!")
        await q.freeze()
        for expected in [30.0, 60, 120] {
            _ = await q.sendRound()
            let s = await q.state
            XCTAssertEqual(s.nextAttempt - clock.now.timeIntervalSince1970, expected)
            clock.advance(expected)
        }
        await q.networkRestored()
        let s = await q.state
        XCTAssertEqual(s.failures, 0)
        XCTAssertEqual(s.nextAttempt, 0)
    }

    func testReopenRepairsState() async throws {
        do {
            let q = makeQueue(FakePoolTransport())
            await q.record("Stay low right now!")
            await q.record("Who goes there at this hour?")
            await q.freeze()
            await q.record("A third line appears here.")
        }
        // Yarım satır ve eski frozenThrough.
        let pending = poolDir.appendingPathComponent("pending.jsonl")
        let handle = try FileHandle(forWritingTo: pending)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"s\":9,\"t\":\"yar".utf8))
        try handle.close()
        var state = try JSONSerialization.jsonObject(with: Data(contentsOf: poolDir.appendingPathComponent("state.json"))) as! [String: Any]
        state["frozenThrough"] = 0
        try poolJSON(state).write(to: poolDir.appendingPathComponent("state.json"))
        let install = state["install"] as! String

        let q = makeQueue(FakePoolTransport())
        let s = await q.state
        XCTAssertEqual(s.frozenThrough, 2)
        XCTAssertEqual(s.install, install) // aynı kimlik sürer
        let count = await q.pendingCount
        XCTAssertEqual(count, 1)
        XCTAssertTrue(try String(contentsOf: pending, encoding: .utf8).hasSuffix("}\n"))
        let next = await q.record("A fourth line appears here.")
        XCTAssertTrue(next)
    }

    func testBrokenStateIsSetAside() async throws {
        try FileManager.default.createDirectory(at: poolDir, withIntermediateDirectories: true)
        try Data("bozuk".utf8).write(to: poolDir.appendingPathComponent("state.json"))
        _ = makeQueue(FakePoolTransport())
        let names = try FileManager.default.contentsOfDirectory(atPath: poolDir.path)
        XCTAssertTrue(names.contains("state.broken-1763300000.json"))
    }

    func testNewVersionRetriesParked() async throws {
        do {
            let q = makeQueue(FakePoolTransport { _ in (400, Data(), [:]) })
            await q.record("Stay low right now!")
            await q.freeze()
            _ = await q.sendRound()
            let parked = await q.parkedFiles()
            XCTAssertEqual(parked.count, 1)
        }
        let q = makeQueue(FakePoolTransport(), app: "1.1")
        let outbox = await q.outboxFiles()
        XCTAssertEqual(outbox.count, 1)
    }

    func testClearRemovesEverything() async {
        let q = makeQueue(FakePoolTransport())
        await q.record("Stay low right now!")
        await q.freeze()
        await q.record("Who goes there at this hour?")
        await q.clear()
        let outbox = await q.outboxFiles()
        let pending = await q.pendingCount
        XCTAssertEqual(outbox, [])
        XCTAssertEqual(pending, 0)
    }

    func testLegacyQueueImportedOnce() async throws {
        let legacy = dir.appendingPathComponent("pool.json")
        let install = "ABCDEF00-0000-4000-8000-000000000001"
        try poolJSON(["install": install, "queue": [["text": "Old line from before.", "game": "GTA V"]], "sent": []]).write(to: legacy)
        let q = makeQueue(FakePoolTransport(), legacy: legacy)
        let count = await q.pendingCount
        let s = await q.state
        XCTAssertEqual(count, 1)
        XCTAssertEqual(s.install, install.lowercased())
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("pool.json.imported").path))
    }

    func testRetryAfterParsing() {
        let now = Date(timeIntervalSince1970: 1_763_300_000)
        XCTAssertEqual(PoolQueue.retryAfter(nil, now: now), 60)
        XCTAssertEqual(PoolQueue.retryAfter("0", now: now), 1)
        XCTAssertEqual(PoolQueue.retryAfter("999999", now: now), 86_400)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        XCTAssertEqual(PoolQueue.retryAfter(f.string(from: now.addingTimeInterval(300)), now: now), 300, accuracy: 1)
    }
}
