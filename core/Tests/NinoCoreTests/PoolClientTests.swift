// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

final class PoolClientTests: XCTestCase {
    var dir: URL!
    let clock = PoolTestClock()

    override func setUpWithError() throws { dir = try makeLibraryTempDirectory("nino-poolclient") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func makeClient(_ t: FakePoolTransport, url: URL? = poolTestServer, enabled: Bool = true) -> PoolClient {
        PoolClient(configuration: PoolConfiguration(baseURL: url, enabled: enabled, appVersion: "2.0"), transport: t,
                   translations: PoolTranslations(root: dir, language: "tr"), install: "inst", environment: clock.environment)
    }

    func query(_ r: URLRequest) -> [String: String] {
        var out: [String: String] = [:]
        for item in URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [] { out[item.name] = item.value }
        return out
    }

    func testResolveURL() {
        XCTAssertNil(PoolConfiguration.resolveURL([nil, "", "$(NINO_POOL)", "ftp://x", "https://"]))
        XCTAssertEqual(PoolConfiguration.resolveURL(["$(X)", "http://a.test/"])?.host, "a.test")
    }

    func testNoAddressNoTraffic() async {
        let t = FakePoolTransport()
        let c = makeClient(t, url: nil)
        await c.refreshConfig()
        _ = await c.sync(game: "gta-v")
        _ = await c.ask("Stay low right now!", game: nil)
        XCTAssertEqual(t.requests.count, 0)
        let first = await c.isPoolFirst(game: "gta-6", language: "tr")
        XCTAssertFalse(first)
    }

    func testPoolFirstRules() async {
        let t = FakePoolTransport { _ in
            (200, poolJSON(["ok": true, "poolFirst": ["games": ["gta-vi"], "langs": ["tr"], "deadlineMs": 50]]), [:])
        }
        let c = makeClient(t)
        var first = await c.isPoolFirst(game: "Grand Theft Auto VI", language: "tr")
        XCTAssertTrue(first) // varsayılan liste
        first = await c.isPoolFirst(game: "gta-v", language: "tr")
        XCTAssertFalse(first)
        first = await c.isPoolFirst(game: "gta-vi-enhanced", language: "tr-TR")
        XCTAssertTrue(first)
        first = await c.isPoolFirst(game: "gta-vi", language: "de")
        XCTAssertFalse(first)
        await c.refreshConfig()
        let deadline = await c.poolFirstDeadline
        XCTAssertEqual(deadline, .milliseconds(100)) // 100'e sıkıştırılır
        let chosen = await c.chooseGame(["Elden Ring", "GTA VI"])
        XCTAssertEqual(chosen, "gta-6") // asıl kimlik
        // 10 dk dolmadan yeniden okunmaz.
        await c.refreshConfig()
        XCTAssertEqual(t.requests.count, 1)
    }

    func testSyncPagesAndCursor() async throws {
        let k1 = LineKey.key("Stay low!")!, k2 = LineKey.key("Who goes there?")!
        let t = FakePoolTransport { r in
            let q = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)!.queryItems!
            if q.contains(where: { $0.name == "after" }) {
                return (200, poolJSON(["ok": true, "items": [[LineKey.hex(k2), "O kim?", 2000, 1]], "next": NSNull()]), [:])
            }
            return (200, poolJSON(["ok": true, "items": [[LineKey.hex(k1), "Eğil!", 1000], ["bozuk"]],
                                   "next": ["since": 1000, "after": LineKey.hex(k1)]]), [:])
        }
        let c = makeClient(t)
        let added = await c.sync(game: "GTA V")
        XCTAssertEqual(added, 2)
        XCTAssertEqual(t.requests.count, 2)
        XCTAssertEqual(query(t.requests[0]), ["lang": "tr", "since": "0", "game": "gta-v"])
        XCTAssertEqual(query(t.requests[1])["after"], LineKey.hex(k1))

        let store = c.translations
        let hit = await store.lookup("stay low")
        XCTAssertEqual(hit, "Eğil!")
        let cursor = await store.cursor(for: "gta-v")
        XCTAssertEqual(cursor.since, 2000)
        XCTAssertEqual(cursor.after, "")
        // Çok yakında yeniden indirilmez.
        _ = await c.sync(game: "GTA V")
        XCTAssertEqual(t.requests.count, 2)

        // Diskte eski biçimle aynı dosya; yeniden açınca okunur.
        let file = dir.appendingPathComponent("translations/translations-tr.json")
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        XCTAssertEqual(saved["language"] as? String, "tr")
        XCTAssertEqual((saved["texts"] as? [String: String])?[LineKey.hex(k2)], "O kim?")
        let reopened = PoolTranslations(root: dir, language: "tr")
        let count = await reopened.count
        XCTAssertEqual(count, 2)
    }

    func testReadsCapitalizedFolderToo() async throws {
        let folder = dir.appendingPathComponent("Translations")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try poolJSON(["language": "tr", "texts": [libraryKey("Hello there"): "Merhaba"], "cursors": [:]])
            .write(to: folder.appendingPathComponent("translations-tr.json"))
        let store = PoolTranslations(root: dir, language: "tr")
        let hit = await store.lookup("Hello there!")
        XCTAssertEqual(hit, "Merhaba")
    }

    func testAskStoresAndDeduplicates() async throws {
        let t = FakePoolTransport { r in
            try await Task.sleep(for: .milliseconds(50))
            return (200, poolJSON(["ok": true, "translations": [["text": "Eğil!", "tier": 1]], "game": "GTA VI"]), [:])
        }
        let c = makeClient(t)
        await c.noteSeen("Earlier line here.")
        async let a = c.ask("Stay low right now!", game: "Mafia")
        async let b = c.ask("Stay low, right now!", game: "Mafia")
        let (x, y) = await (a, b)
        XCTAssertEqual(x, "Eğil!")
        XCTAssertEqual(y, "Eğil!")
        XCTAssertEqual(t.requests.count, 1)
        let body = poolBody(t.requests[0])
        XCTAssertEqual(body["lines"] as? [String], ["Stay low right now!"])
        XCTAssertEqual(body["context"] as? [String], ["Earlier line here."])
        XCTAssertEqual(body["game"] as? String, "mafia")
        XCTAssertEqual(body["install"] as? String, "inst")
        // Depoda olduğu için yeniden sorulmaz; sunucunun söylediği oyun havuz öncelikli yapar.
        _ = await c.ask("Stay low right now!", game: nil)
        XCTAssertEqual(t.requests.count, 1)
        let first = await c.isPoolFirst(game: "unknown", language: "tr")
        XCTAssertTrue(first)
    }

    func testDeadlineReturnsNilButLateAnswerIsStored() async throws {
        let t = FakePoolTransport { _ in
            try await Task.sleep(for: .milliseconds(300))
            return (200, poolJSON(["ok": true, "translations": [["text": "Geç geldi."]]]), [:])
        }
        let c = makeClient(t)
        let quick = await c.ask("This answer arrives late.", game: nil, deadline: .milliseconds(20))
        XCTAssertNil(quick)
        var stored: String?
        for _ in 0..<100 where stored == nil { // yük altında da kararlı: 5 sn'ye kadar bekle
            try await Task.sleep(for: .milliseconds(50))
            stored = await c.translations.lookup("This answer arrives late.")
        }
        XCTAssertEqual(stored, "Geç geldi.")
    }

    func testFilteredLinesAreNotAsked() async {
        let t = FakePoolTransport()
        let c = makeClient(t)
        _ = await c.ask("PHOTO MODE SELECT", game: nil)
        _ = await c.ask("Stay low!", game: nil) // havuz kapalı değil ama 404
        XCTAssertEqual(t.paths(), ["/v1/translate"])
    }

    func testDisabledPoolStillAsksForPoolFirstGame() async {
        let t = FakePoolTransport { _ in (200, poolJSON(["ok": true, "translations": [["text": "Tamam."]]]), [:]) }
        let c = makeClient(t, enabled: false)
        let off = await c.ask("Stay low right now!", game: nil)
        XCTAssertNil(off)
        let on = await c.ask("Stay low right now!", game: "gta-6", poolFirst: true)
        XCTAssertEqual(on, "Tamam.")
    }

    func testPing() async {
        let t = FakePoolTransport()
        let c = makeClient(t)
        await c.ping(game: "GTA V")
        XCTAssertEqual(t.paths(), ["/v1/ping"])
        XCTAssertEqual(query(t.requests[0]), ["install": "inst", "platform": "mac", "app": "2.0", "game": "gta-v", "lang": "tr"])
    }

    func testInstallID() throws {
        let file = dir.appendingPathComponent("translations/install")
        let first = InstallID.load(at: file)
        XCTAssertEqual(InstallID.load(at: file), first)
        XCTAssertEqual(first, first.lowercased())
        try Data("bozuk".utf8).write(to: file)
        XCTAssertNotEqual(InstallID.load(at: file), "bozuk")
    }
}

final class PackUpdaterTests: XCTestCase {
    var dir: URL!
    let clock = PoolTestClock()

    override func setUpWithError() throws { dir = try makeLibraryTempDirectory("nino-updater") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    var packs: URL { dir.appendingPathComponent("packs") }
    var status: URL { dir.appendingPathComponent("packs-remote.json") }

    func packData(_ text: String) -> Data {
        TestGzip.make(libraryJSON(["format": 1, "id": "oyun", "entries": [libraryKey("Stay low!"): text]]))
    }

    func makeUpdater(_ t: FakePoolTransport, url: URL? = poolTestServer) -> PackUpdater {
        PackUpdater(packsDirectory: packs, statusFile: status,
                    configuration: PoolConfiguration(baseURL: url, appVersion: "1.0"), transport: t, environment: clock.environment)
    }

    final class Server: @unchecked Sendable {
        var list: [[String: Any]] = []
        var files: [String: Data] = [:]
        var corrupt = false
        func handle(_ r: URLRequest) -> (Int, Data, [String: String]) {
            let path = r.url!.path
            if path == "/v1/packs" { return (200, poolJSON(["packs": list]), [:]) }
            let id = String(path.dropFirst("/v1/packs/".count))
            guard let d = files[id] else { return (404, Data(), [:]) }
            return (200, corrupt ? d + Data([0]) : d, [:])
        }
    }

    func testDownloadVerifyKeepAndRemove() async throws {
        let server = Server()
        let v1 = packData("Eğil!")
        server.files["oyun"] = v1
        server.list = [["id": "oyun", "title": "Oyun", "version": 1, "sha256": PackUpdater.sha256(v1)],
                       ["id": "Bad ID", "title": "x", "version": 1, "sha256": PackUpdater.sha256(v1)],
                       ["id": "kisa-sha", "title": "x", "version": 1, "sha256": "abc"]]
        let t = FakePoolTransport { r in server.handle(r) }
        let u = makeUpdater(t)

        var due = await u.isDue(.launch)
        XCTAssertTrue(due)
        var r = await u.check()
        XCTAssertEqual(r.downloaded, ["oyun"])
        XCTAssertTrue(r.changed)
        let library = LegacyLibrary(directories: [packs])
        XCTAssertEqual(library.exact("Stay low!")?.text, "Eğil!")
        XCTAssertFalse(FileManager.default.fileExists(atPath: packs.appendingPathComponent(".oyun.download").path))

        // Taze: bakılmaz; yeni oyun için 10 dk sonra bakılır.
        due = await u.isDue(.launch)
        XCTAssertFalse(due)
        clock.advance(601)
        due = await u.isDue(.newGame)
        XCTAssertTrue(due)

        // Aynı sürüm: dokunulmaz.
        r = await u.check()
        XCTAssertEqual(r, PackUpdater.Result())

        // Sunucudan kalkınca silinir.
        server.list = []
        r = await u.check()
        XCTAssertEqual(r.removed, ["oyun"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: packs.appendingPathComponent("oyun.json.gz").path))
    }

    func testBadChecksumKeepsOldAndRetries() async throws {
        let server = Server()
        let v1 = packData("Bir"), v2 = packData("İki")
        server.files["oyun"] = v1
        server.list = [["id": "oyun", "title": "Oyun", "version": 1, "sha256": PackUpdater.sha256(v1)]]
        let u = makeUpdater(FakePoolTransport { r in server.handle(r) })
        _ = await u.check()
        let checked = await u.status().checked

        server.files["oyun"] = v2
        server.list = [["id": "oyun", "title": "Oyun", "version": 2, "sha256": PackUpdater.sha256(v2)]]
        server.corrupt = true
        clock.advance(100)
        let r = await u.check()
        XCTAssertEqual(r.failed, ["oyun"])
        let s = await u.status()
        XCTAssertEqual(s.packs.first?.version, -1)
        XCTAssertEqual(s.checked, checked) // son bakış ilerlemez
        XCTAssertEqual(try Data(contentsOf: packs.appendingPathComponent("oyun.json.gz")), v1)
        let due = await u.isDue(.launch)
        XCTAssertTrue(due) // inemeyen var: taze olsa da bakılır

        server.corrupt = false
        let again = await u.check()
        XCTAssertEqual(again.downloaded, ["oyun"])
        XCTAssertEqual(try Data(contentsOf: packs.appendingPathComponent("oyun.json.gz")), v2)
    }

    func testUserFileIsNeverOverwritten() async throws {
        try FileManager.default.createDirectory(at: packs, withIntermediateDirectories: true)
        let mine = packData("Benim çevirim")
        try mine.write(to: packs.appendingPathComponent("oyun.json.gz"))
        let server = Server()
        let v1 = packData("Sunucu")
        server.files["oyun"] = v1
        server.list = [["id": "oyun", "title": "Oyun", "version": 1, "sha256": PackUpdater.sha256(v1)]]
        let u = makeUpdater(FakePoolTransport { r in server.handle(r) })
        let r = await u.check()
        XCTAssertEqual(r.userFiles, ["oyun"])
        XCTAssertEqual(try Data(contentsOf: packs.appendingPathComponent("oyun.json.gz")), mine)
        let removed = await u.removeDownloaded()
        XCTAssertEqual(removed, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: packs.appendingPathComponent("oyun.json.gz").path))
    }

    func testNoAddressMeansOff() async {
        let t = FakePoolTransport()
        let u = makeUpdater(t, url: nil)
        let due = await u.isDue(.launch)
        XCTAssertFalse(due)
        let r = await u.check()
        XCTAssertTrue(r.listFailed)
        XCTAssertEqual(t.requests.count, 0)
    }
}
