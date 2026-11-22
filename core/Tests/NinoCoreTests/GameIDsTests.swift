// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

final class GameIDsTests: XCTestCase {
    func testAliasesBecomeCanonical() {
        for raw in ["grand-theft-auto-vi", "GTA-VI", "gta6", "gtavi", "pool-gta-6", "gta--6", "gta-6",
                    "Grand Theft Auto VI", "GTA VI", "GTA 6"] {
            XCTAssertEqual(GameIDs.canonical(raw), "gta-6", raw)
        }
        for raw in ["grand-theft-auto-v", "gta-5", "gta5", "gtav", "pool-gta-5", "pool-gta-v", "gta-v",
                    "Grand Theft Auto V", "GTA 5", "GTA V"] {
            XCTAssertEqual(GameIDs.canonical(raw), "gta-v", raw)
        }
        // Sunucu tablosunun tamamı.
        for (alias, target) in GameIDs.aliases { XCTAssertEqual(GameIDs.canonical(alias), target, alias) }
        XCTAssertEqual(GameIDs.canonical("Death Stranding 2: On the Beach"), "death-stranding-2")
        XCTAssertEqual(GameIDs.canonical("Mafia: The Old Country"), "mafia-the-old-country")
        XCTAssertEqual(GameIDs.canonical("!!!"), "")
        XCTAssertNil(GameIDs.id(""))
        // Paket kimliği üretimi (GameName.id) değişmez.
        XCTAssertEqual(GameName.id("Grand Theft Auto VI"), "grand-theft-auto-vi")
    }

    func testSameGameAndNames() {
        XCTAssertTrue(GameIDs.sameGame("pool-gta-6", "GTA 6"))
        XCTAssertTrue(GameIDs.sameGame("Grand Theft Auto VI", "gta6"))
        XCTAssertFalse(GameIDs.sameGame("gta-6", "gta-v"))
        XCTAssertFalse(GameIDs.sameGame("", ""))
        XCTAssertEqual(GameIDs.displayName("pool-gta-6"), "GTA 6")
        XCTAssertEqual(GameIDs.displayName("Grand Theft Auto V"), "GTA 5")
        XCTAssertEqual(GameIDs.displayName("Benim Oyunum"), "Benim Oyunum")
        XCTAssertNil(GameIDs.knownName("benim-oyunum"))
    }

    func testPoolFirstMatchesAliasOnlyList() {
        var remote = PoolRemoteConfig()
        remote.poolFirstGames = ["grand-theft-auto-vi"]
        XCTAssertTrue(remote.isPoolFirstGame("gta-6"))
        XCTAssertTrue(remote.isPoolFirstGame("pool-gta-6"))
        XCTAssertFalse(remote.isPoolFirstGame("gta-v"))
        XCTAssertTrue(GameReading.PhoneGame.isPoolPriority("pool-gta-6"))
    }

    func testProviderAndTelemetrySendCanonical() throws {
        let p = NinoPoolProvider(config: .init(baseURL: URL(string: "https://pool.example.test")!, install: "u", app: "1.0"),
                                 transport: ProvidersFakeTransport(.http(200, "{}")))
        let r = p.makeRequest(lines: ["Run!"], context: [], language: "tr", game: "Grand Theft Auto VI")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(r.httpBody)) as? [String: Any])
        XCTAssertEqual(body["game"] as? String, "gta-6")

        XCTAssertEqual(TelemetryEvent.session(duration: 1, game: "grand-theft-auto-vi", source: .remoteplay, lines: 1).fields["game"],
                       .string("gta-6"))
        XCTAssertEqual(TelemetryEvent.diag(rule: "x.y", cause: "c", game: "pool-gta-v")?.fields["game"], .string("gta-v"))
    }

    func testPlacementFallsBackToAliasKey() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nino-placement-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let old = GameReading.Placement(samples: (0..<8).map { _ in .init(top: 0.85, bottom: 0.95) })
        try JSONEncoder().encode(["pool-gta-6": old]).write(to: url)
        let store = GameReading.PlacementStore(url: url)
        XCTAssertEqual(store.placement(for: "gta-6"), old)
        XCTAssertEqual(store.placement(for: "gta-v"), GameReading.Placement())
    }
}

extension PoolClientTests {
    func testServerGetsCanonicalGame() async throws {
        let t = FakePoolTransport { _ in (200, poolJSON(["ok": true, "translations": [["text": "Eğil!", "tier": 1]], "game": "gtavi"]), [:]) }
        let c = makeClient(t)
        _ = await c.ask("Stay low right now!", game: "Grand Theft Auto VI")
        XCTAssertEqual(poolBody(t.requests[0])["game"] as? String, "gta-6")
        await c.ping(game: "pool-gta-6")
        XCTAssertEqual(query(t.requests[1])["game"], "gta-6")
        _ = await c.sync(game: "grand-theft-auto-v", force: true)
        XCTAssertEqual(query(t.requests[2])["game"], "gta-v")
        let chosen = await c.chooseGame(["pool-gta-6"])
        XCTAssertEqual(chosen, "gta-6")
    }
}

extension PoolQueueTests {
    func testBatchCarriesCanonicalGame() async throws {
        let transport = FakePoolTransport(okHandler())
        let q = makeQueue(transport)
        await q.record("Stay low!", game: "Grand Theft Auto VI")
        await q.record("Who goes there?", game: "pool-gta-6")
        clock.advance(120)
        _ = await q.run()
        let lines = try XCTUnwrap(poolBody(try XCTUnwrap(transport.requests.first))["lines"] as? [[String: Any]])
        XCTAssertEqual(lines.compactMap { $0["game"] as? String }, ["gta-6", "gta-6"])
    }
}
