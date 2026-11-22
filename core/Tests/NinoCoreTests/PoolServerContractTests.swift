// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

/// İstemcinin havuz sunucusuna (nino-pool) giden istekleri sunucunun doğrulama kurallarına uyuyor mu.
/// Kurallar sunucu kodundan: `validate.js` (checkBatch/checkLine), `translate.js` (handleTranslate,
/// listTranslations), `stats.js` (handlePing/touchInstall), `key.js` (canon/lineKey).
final class PoolServerContractTests: XCTestCase {
    static let uuid = try! NSRegularExpression(pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
                                               options: [.caseInsensitive])
    static let gameID = try! NSRegularExpression(pattern: "^[a-z0-9][a-z0-9._-]{0,63}$")
    static let serverLanguages: Set<String> = ["tr", "ar", "hi", "id", "th", "vi", "ur", "bn", "ms", "tl", "nl"]
    static let install = "8d0f5c9e-3b1a-4c2d-9e8f-7a6b5c4d3e2f"

    var dir: URL!
    let clock = PoolTestClock()

    override func setUpWithError() throws { dir = try makeLibraryTempDirectory("nino-contract") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    static func matches(_ re: NSRegularExpression, _ s: String?) -> Bool {
        guard let s else { return false }
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    static func query(_ r: URLRequest) -> [String: String] {
        var out: [String: String] = [:]
        for item in URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [] { out[item.name] = item.value }
        return out
    }

    func makeClient(_ t: FakePoolTransport, language: String = "tr") -> PoolClient {
        PoolClient(configuration: PoolConfiguration(baseURL: poolTestServer, enabled: true, appVersion: "4.1.0"), transport: t,
                   translations: PoolTranslations(root: dir, language: language), install: Self.install,
                   environment: clock.environment)
    }

    // MARK: key.js

    /// Sunucunun `canon`/`lineKey` çıktısı (node ile `nino-pool/src/key.js`'ten alındı): bütün işaretler (Mn, Mc, Me) atılır.
    func testLineKeyMatchesServerForAllMarks() {
        let server: [(String, String, String)] = [
            ("काम करो", "कम कर", "dd3b718c4750360d"),
            ("a\u{20DD}b", "ab", "fb8e20fc2e4c3f24"),
            ("ok\u{0301}ay", "okay", "6a581ee901185606"),
        ]
        for (input, canon, key) in server {
            XCTAssertEqual(LineKey.canon(input), canon, input)
            XCTAssertEqual(LineKey.key(input).map(LineKey.hex), key, input)
        }
    }

    // MARK: POST /v1/batches

    func testBatchBodyPassesServerValidation() async throws {
        let t = FakePoolTransport { r in
            let b = poolBody(r)
            return (200, poolJSON(["ok": true, "batch": b["batch"] as? String ?? "", "accepted": 2, "rejected": []]), [:])
        }
        let queue = PoolQueue(directory: dir.appendingPathComponent("pool"),
                              configuration: PoolConfiguration(baseURL: poolTestServer, enabled: true, appVersion: "4.1.0"),
                              transport: t, environment: clock.environment)
        await queue.record("Stay low right now, partner!", game: "Grand Theft Auto VI")
        await queue.record("Who goes there in the dark?")
        await queue.freeze()
        let result = await queue.sendRound()
        XCTAssertEqual(result.sent, 1)
        let request = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/batches")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertLessThanOrEqual(request.httpBody?.count ?? .max, 512 * 1024)
        let body = poolBody(request)
        XCTAssertEqual(body["v"] as? Int, 1)
        XCTAssertTrue(Self.matches(Self.uuid, body["batch"] as? String))
        XCTAssertTrue(Self.matches(Self.uuid, body["install"] as? String))
        XCTAssertEqual(body["platform"] as? String, "mac")
        XCTAssertLessThanOrEqual((body["app"] as? String)?.count ?? 99, 40)
        let lines = try XCTUnwrap(body["lines"] as? [[String: Any]])
        XCTAssertEqual(lines.count, 2)
        XCTAssertLessThanOrEqual(lines.count, 500)
        for line in lines {
            let text = try XCTUnwrap(line["text"] as? String)
            XCTAssertLessThanOrEqual(text.unicodeScalars.count, 500)
            if let game = line["game"] { XCTAssertTrue(Self.matches(Self.gameID, game as? String), "\(game)") }
            if let session = line["session"] { XCTAssertTrue(Self.matches(Self.uuid, session as? String)) }
            let count = try XCTUnwrap(line["count"] as? NSNumber)
            XCTAssertEqual(count.doubleValue, count.doubleValue.rounded())
            XCTAssertGreaterThanOrEqual(count.intValue, 1)
            XCTAssertNotNil(line["first"] as? Int)
            XCTAssertNotNil(line["last"] as? Int)
        }
        XCTAssertEqual(lines.first?["game"] as? String, "gta-6") // asıl kimlik (GameIDs)
    }

    // MARK: POST /v1/translate

    func testTranslateBodyPassesServerValidation() async throws {
        let t = FakePoolTransport { _ in
            (200, poolJSON(["ok": true, "game": "gta-vi", "translations": [["text": "Eğil!", "tier": 1]]]), [:])
        }
        let c = makeClient(t)
        await c.noteSeen("We have to go now.")
        let answer = await c.ask("Stay low right now!", game: "Mafia: The Old Country")
        XCTAssertEqual(answer, "Eğil!")
        let r = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.url?.path, "/v1/translate")
        XCTAssertLessThanOrEqual(r.httpBody?.count ?? .max, 64 * 1024)
        let b = poolBody(r)
        XCTAssertEqual(b["v"] as? Int, 1)
        XCTAssertTrue(Self.matches(Self.uuid, b["install"] as? String))
        XCTAssertTrue(Self.serverLanguages.contains(b["lang"] as? String ?? ""))
        XCTAssertTrue(Self.matches(Self.gameID, b["game"] as? String))
        XCTAssertEqual(b["game"] as? String, "mafia-the-old-country")
        let lines = try XCTUnwrap(b["lines"] as? [String])
        XCTAssertTrue((1...12).contains(lines.count))
        XCTAssertTrue(lines.allSatisfy { $0.unicodeScalars.count <= 300 })
        XCTAssertLessThanOrEqual((b["context"] as? [String])?.count ?? 99, 4)
        XCTAssertEqual(b["platform"] as? String, "mac")
    }

    /// Sunucu 300 kod noktasından uzun satırı çevirmez (`text: null`); istemci hiç sormaz.
    func testOverlongLineIsNotAsked() async {
        let t = FakePoolTransport()
        let c = makeClient(t)
        let long = String(repeating: "Run to the car and drive. ", count: 13)
        XCTAssertGreaterThan(long.trimmingCharacters(in: .whitespaces).unicodeScalars.count, 300)
        let answer = await c.ask(long, game: nil)
        XCTAssertNil(answer)
        XCTAssertEqual(t.requests.count, 0)
    }

    /// Sunucu cevabındaki `text: null` (çevrilemedi) ve `limited` istemciyi bozmaz.
    func testTranslateNullAndLimited() async {
        let t = FakePoolTransport { _ in
            (200, poolJSON(["ok": true, "limited": "daily_cap", "translations": [["text": NSNull(), "tier": 0]]]), [:])
        }
        let answer = await makeClient(t).ask("Stay low right now!", game: nil)
        XCTAssertNil(answer)
    }

    func testProviderSendsGameIDNotName() async throws {
        let t = ProvidersFakeTransport(.http(200, #"{"ok":true,"translations":[{"text":"Koş!","tier":1}]}"#))
        let p = NinoPoolProvider(config: .init(baseURL: poolTestServer, install: Self.install, app: "4.1.0"), transport: t)
        _ = try await p.ask(lines: ["Run!"], context: [], language: "tr", game: "Grand Theft Auto VI")
        XCTAssertEqual(t.body()["game"] as? String, "gta-6")
        _ = try await p.ask(lines: ["Run!"], context: [], language: "tr", game: "gta-vi")
        XCTAssertEqual(t.body()["game"] as? String, "gta-6")
    }

    // MARK: GET /v1/translations, /v1/ping, /v1/config

    func testTranslationsAndPingQueries() async throws {
        let t = FakePoolTransport { r in
            if r.url?.path == "/v1/translations" { return (200, poolJSON(["ok": true, "now": 1, "items": [], "next": NSNull()]), [:]) }
            return (204, Data(), [:])
        }
        let c = makeClient(t)
        _ = await c.sync(game: "Grand Theft Auto VI", force: true)
        await c.ping(game: "Grand Theft Auto VI")
        let list = try XCTUnwrap(t.requests.first { $0.url?.path == "/v1/translations" })
        XCTAssertEqual(list.httpMethod, "GET")
        let q = Self.query(list)
        XCTAssertTrue(Self.serverLanguages.contains(q["lang"] ?? ""))
        XCTAssertNotNil(Int(q["since"] ?? ""))
        XCTAssertTrue(Self.matches(Self.gameID, q["game"]))
        let ping = try XCTUnwrap(t.requests.first { $0.url?.path == "/v1/ping" })
        let p = Self.query(ping)
        XCTAssertTrue(Self.matches(Self.uuid, p["install"]))
        XCTAssertEqual(p["platform"], "mac")
        XCTAssertEqual(p["game"], "gta-6")
        XCTAssertEqual(p["lang"], "tr")
    }

    /// Sunucunun `remoteConfig` cevabı (worker.js `/v1/config`) olduğu gibi okunur.
    func testConfigShapeFromServer() async {
        let body = #"{"ok":true,"translate":{"enabled":false,"deadlineMs":900,"syncSeconds":240,"contextLines":4,"maxLines":12},"poolFirst":{"games":["gta-vi"],"langs":["tr"],"deadlineMs":3000},"minVersion":{"mac":"","windows":"","android":"","ios":""},"downloads":1234}"#
        let t = FakePoolTransport { _ in (200, Data(body.utf8), [:]) }
        let c = makeClient(t)
        await c.refreshConfig(force: true)
        let remote = await c.remote
        XCTAssertFalse(remote.translateEnabled)
        XCTAssertEqual(remote.syncSeconds, 240)
        XCTAssertEqual(remote.poolFirstGames, ["gta-vi"])
        XCTAssertEqual(remote.poolFirstDeadlineMs, 3000)
    }

    // MARK: Yerel sunucuyla uçtan uca (isteğe bağlı)

    /// `NINO_LOCAL_POOL_URL=http://127.0.0.1:8799` verilirse yerel `wrangler dev`'e gerçek istek gider. Yalnız yerel
    /// adreslere izin veren taşıyıcı kullanılır; başka adres hata verir.
    func testLocalServerEndToEnd() async throws {
        guard let raw = ProcessInfo.processInfo.environment["NINO_LOCAL_POOL_URL"], let base = URL(string: raw) else {
            throw XCTSkip("NINO_LOCAL_POOL_URL verilmedi")
        }
        let transport = LoopbackOnlyTransport()
        try transport.check(base)
        let config = PoolConfiguration(baseURL: base, enabled: true, appVersion: "4.1.0")
        let install = UUID().uuidString.lowercased()

        // Satır gönderme: sunucu 200 ve aynı parça kimliğiyle cevap vermeli.
        let queue = PoolQueue(directory: dir.appendingPathComponent("pool"), configuration: config, transport: transport)
        await queue.record("Stay low right now, partner!", game: "Grand Theft Auto VI")
        await queue.record("Who goes there in the dark?")
        await queue.freeze()
        let sent = await queue.sendRound()
        XCTAssertEqual(sent.sent, 1, "\(sent)")
        XCTAssertEqual(sent.parked, 0)

        // Uzak ayar.
        let client = PoolClient(configuration: config, transport: transport,
                                translations: PoolTranslations(root: dir, language: "tr"), install: install)
        await client.refreshConfig(force: true)
        let remote = await client.remote
        XCTAssertEqual(remote.maxLines, 12)

        // Toplu indirme: yerel veritabanına önceden konan çeviri (seed) inmeli.
        let added = await client.sync(game: "Grand Theft Auto VI", force: true)
        let seeded = await client.translations.lookup("Nino local contract test line.")
        if ProcessInfo.processInfo.environment["NINO_LOCAL_POOL_SEEDED"] == "1" {
            XCTAssertGreaterThanOrEqual(added, 1)
            XCTAssertEqual(seeded, "Nino yerel sözleşme deneme satırı.")
        }

        // Anında soru: sunucu `translate.enabled: false` derse istemci hiç sormaz (yerel sunucuda motor kapalı);
        // açıksa havuzdaki satır döner.
        let known = await client.ask("Nino local contract test line.", game: "Grand Theft Auto VI")
        if remote.translateEnabled, ProcessInfo.processInfo.environment["NINO_LOCAL_POOL_SEEDED"] == "1" {
            XCTAssertEqual(known, "Nino yerel sözleşme deneme satırı.")
        } else if !remote.translateEnabled {
            XCTAssertNil(known)
        }
        let provider = NinoPoolProvider(config: .init(baseURL: base, install: install, app: "4.1.0"),
                                        transport: transport)
        let answer = try await provider.ask(lines: ["Nino local contract test line.", "Some other new line here."],
                                            context: ["We go."], language: "tr", game: "Grand Theft Auto VI")
        XCTAssertEqual(answer.translations.count, 2)
        if ProcessInfo.processInfo.environment["NINO_LOCAL_POOL_SEEDED"] == "1" {
            XCTAssertEqual(answer.translations.first ?? nil, "Nino yerel sözleşme deneme satırı.")
        }

        // "Buradayım": 204.
        await client.ping(game: "Grand Theft Auto VI")
        XCTAssertEqual(transport.statuses["/v1/ping"], 204)
        XCTAssertEqual(transport.statuses["/v1/batches"], 200)
        XCTAssertEqual(transport.statuses["/v1/config"], 200)
        XCTAssertEqual(transport.statuses["/v1/translations"], 200)
        XCTAssertEqual(transport.statuses["/v1/translate"], 200)
    }
}

/// Yalnız 127.0.0.1 / localhost / ::1 adreslerine giden gerçek taşıyıcı (canlı sunucuya istek gidemez).
final class LoopbackOnlyTransport: PoolTransport, ProviderTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _statuses: [String: Int] = [:]
    var statuses: [String: Int] { lock.withLock { _statuses } }

    func check(_ url: URL?) throws {
        guard let host = url?.host, ["127.0.0.1", "localhost", "::1"].contains(host) else {
            throw URLError(.unsupportedURL)
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try check(request.url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        lock.withLock { _statuses[request.url?.path ?? ""] = http.statusCode }
        return (data, http)
    }
}
