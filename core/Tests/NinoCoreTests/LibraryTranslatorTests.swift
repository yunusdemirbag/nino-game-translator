// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

final class LibraryTranslatorTests: XCTestCase {
    var dir: URL!
    let clock = PoolTestClock()

    override func setUpWithError() throws { dir = try makeLibraryTempDirectory("nino-libtr") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func library() throws -> LegacyLibrary {
        let packs = dir.appendingPathComponent("packs")
        try FileManager.default.createDirectory(at: packs, withIntermediateDirectories: true)
        try TestGzip.make(libraryJSON(["format": 2, "id": "gta-v", "title": "Grand Theft Auto V",
                                       "entries": [libraryKey("Stay low!"): "Alçakta kal!"]]))
            .write(to: packs.appendingPathComponent("gta-v.json.gz"))
        let modern = try TranslationPack(game: .init(id: "yeni"), lines: [.init(source: "Come here.", target: "Buraya gel.")])
        try modern.write(to: packs.appendingPathComponent("yeni.ninopack.json"))
        return LegacyLibrary(directories: [packs])
    }

    func make(provider: FakeProvider, transport: FakePoolTransport) throws -> (LibraryTranslator, PoolClient, PoolQueue) {
        let config = PoolConfiguration(baseURL: poolTestServer, appVersion: "1.0")
        let pool = PoolClient(configuration: config, transport: transport,
                              translations: PoolTranslations(root: dir, language: "tr"), install: "i", environment: clock.environment)
        let queue = PoolQueue(directory: dir.appendingPathComponent("pool"), configuration: config, transport: transport,
                              environment: clock.environment)
        let translator = Translator(chain: ProviderChain(providers: [provider]))
        return (LibraryTranslator(translator: translator, library: try library(), pool: pool, queue: queue), pool, queue)
    }

    func testOrderPackPoolTranslator() async throws {
        let provider = FakeProvider("p", .dictionary(["Who is that guy?": "O adam kim?"]))
        let transport = FakePoolTransport()
        let (lt, pool, queue) = try make(provider: provider, transport: transport)
        await pool.translations.add(key: LineKey.key("Who opened the east gate?")!, text: "Doğu kapısını kim açtı?")

        var r = await lt.translate("STAY LOW!")
        XCTAssertEqual(r.text, "Alçakta kal!")
        XCTAssertEqual(r.origin, .legacyPack("gta-v"))
        r = await lt.translate("Come here.")
        XCTAssertEqual(r.origin, .newPack("yeni"))
        r = await lt.translate("Who opened the east gate")
        XCTAssertEqual(r, LibraryTranslation(source: "Who opened the east gate", text: "Doğu kapısını kim açtı?", origin: .pool))
        r = await lt.translate("Who is that guy?")
        XCTAssertEqual(r.text, "O adam kim?")
        XCTAssertEqual(r.origin, .translator(.provider("p")))
        r = await lt.translate("Who is that guy?")
        XCTAssertEqual(r.origin, .translator(.cache))
        XCTAssertEqual(provider.calls, ["Who is that guy?"])

        // Bulunamayan satır kuyruğa önerildi; oyun ipucu paket kapsamından.
        let pending = await queue.pendingCount
        XCTAssertEqual(pending, 2)
        let text = try String(contentsOf: dir.appendingPathComponent("pool/pending.jsonl"), encoding: .utf8)
        XCTAssertTrue(text.contains("\"g\":\"yeni\""))
        XCTAssertEqual(transport.requests.count, 0) // arka plan sorusu kapalı
    }

    func testPoolFirstGameSkipsPacksAndAsks() async throws {
        let provider = FakeProvider("p", .dictionary(["Stay low!": "Yat!"]))
        let transport = FakePoolTransport { _ in (200, poolJSON(["ok": true, "translations": [["text": "Havuzdan: alçakta kal!"]]]), [:]) }
        let (lt, _, _) = try make(provider: provider, transport: transport)
        await lt.setKnownGame("Grand Theft Auto VI")
        let r = await lt.translate("Stay low!")
        XCTAssertEqual(r.origin, .pool)
        XCTAssertEqual(r.text, "Havuzdan: alçakta kal!")
        XCTAssertEqual(transport.paths(), ["/v1/translate"])
    }

    func testPoolFirstTimeoutFallsBackToTranslator() async throws {
        let provider = FakeProvider("p", .dictionary(["Stay low right now!": "Hemen eğil!"]))
        let transport = FakePoolTransport { _ in
            try await Task.sleep(for: .seconds(5))
            return (500, Data(), [:])
        }
        let (lt, pool, _) = try make(provider: provider, transport: transport)
        _ = pool
        await lt.setKnownGame("gta-6")
        let started = Date()
        let r = await lt.translate("Stay low right now!")
        XCTAssertEqual(r.origin, .translator(.provider("p")))
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testSelectedGameWithoutPackGoesToTranslator() async throws {
        let provider = FakeProvider("p", .dictionary(["Stay low!": "Eğil!"]))
        let (lt, _, _) = try make(provider: provider, transport: FakePoolTransport())
        await lt.selectGame("Elden Ring")
        let r = await lt.translate("Stay low!")
        XCTAssertEqual(r.origin, .translator(.provider("p")))
        await lt.selectGame("GTA 5")
        let again = await lt.translate("Stay low!")
        XCTAssertEqual(again.origin, .legacyPack("gta-v"))
    }

    func testNonEnglishSourceSkipsPoolAndPacks() async throws {
        let provider = FakeProvider("p", .dictionary(["Stay low!": "Runter!"]))
        let transport = FakePoolTransport()
        let config = PoolConfiguration(baseURL: poolTestServer, appVersion: "1.0")
        let pool = PoolClient(configuration: config, transport: transport,
                              translations: PoolTranslations(root: dir, language: "tr"), install: "i", environment: clock.environment)
        await pool.translations.add(key: LineKey.key("Stay low!")!, text: "Havuz")
        let queue = PoolQueue(directory: dir.appendingPathComponent("pool"), configuration: config, transport: transport,
                              environment: clock.environment)
        let lt = LibraryTranslator(translator: Translator(chain: ProviderChain(providers: [provider]), sourceLanguage: "de"),
                                   library: try library(), pool: pool, queue: queue, sourceLanguage: "de")
        let r = await lt.translate("Stay low!")
        XCTAssertEqual(r.origin, .translator(.provider("p")))
        let pending = await queue.pendingCount
        XCTAssertEqual(pending, 0)
    }

    func testPacksDisabled() async throws {
        let provider = FakeProvider("p", .dictionary(["Stay low!": "Eğil!"]))
        let (lt, _, _) = try make(provider: provider, transport: FakePoolTransport())
        await lt.setPacksEnabled(false)
        let r = await lt.translate("Stay low!")
        XCTAssertEqual(r.text, "Eğil!")
    }
}
