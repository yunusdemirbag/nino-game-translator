// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import XCTest
@testable import NinoMacKit

/// Mac'in havuz sunucusuna (nino-pool) giden istekleri sunucunun beklediği biçimde mi
/// (docs/yeni/mac/sunucu-uyumu.md). Kurallar sunucu kodundan: `reports.js` (receiveReport), `assistant.js`
/// (validateConversation, handleAssistant), `identify.js` (handleIdentify), `worker.js` (`/v1/config`).
final class ServerContractTests: XCTestCase {
    static let install = "8d0f5c9e-3b1a-4c2d-9e8f-7a6b5c4d3e2f"
    /// `receiveReport`'un okuduğu alanlar (+ istemcinin kendi `kind` alanı, sunucu yok sayar).
    static let reportFields: Set<String> = ["v", "install", "app", "platform", "language", "text", "contact", "log",
                                            "device", "images", "kind"]
    static let assistantFields: Set<String> = ["v", "install", "app", "platform", "language", "device", "messages"]

    func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func photo(bytes: Int) -> PhotoAttachment {
        var data = Data(count: bytes)
        for i in stride(from: 0, to: bytes, by: 97) { data[i] = UInt8(i & 0xff) }
        return PhotoAttachment(jpeg: data, pixelWidth: 10, pixelHeight: 10)
    }

    // MARK: POST /v1/reports

    func testReportBodyUsesServerFieldNamesAndLimits() throws {
        let log = (0..<20_000).map { "satır \($0)" }.joined(separator: "\n")
        let report = ProblemReport(kind: .user, description: String(repeating: "uzun açıklama ", count: 600),
                                   findings: "— Nino'nun bulguları —\nmuhtemel sebep: yok", contact: "a@b.c",
                                   photos: [Self.photo(bytes: 900 * 1024), Self.photo(bytes: 900 * 1024),
                                            Self.photo(bytes: 900 * 1024)],
                                   logs: log, device: "app: 4.1.0 | device: Mac16,1")
        let data = try ReportContract.body(report, context: ReportContext(install: Self.install, app: "4.1.0", language: "tr"))
        XCTAssertLessThanOrEqual(data.count, 4 * 1024 * 1024)
        let o = try object(data)
        XCTAssertTrue(Set(o.keys).isSubset(of: Self.reportFields), "\(o.keys.sorted())")
        XCTAssertEqual(o["v"] as? Int, 1)
        XCTAssertEqual(o["platform"] as? String, "mac")
        XCTAssertTrue((8...64).contains((o["install"] as? String)?.count ?? 0))
        // Sunucu `log`u okur (eskiden `logs` gidiyordu, günlük sessizce kayboluyordu); ilk 60 000 birimi tutar.
        let sentLog = try XCTUnwrap(o["log"] as? String)
        XCTAssertLessThanOrEqual(sentLog.utf16.count, 60_000)
        XCTAssertTrue(sentLog.hasSuffix("satır 19999"), "en yeni satırlar gitmeli")
        // Sunucu `text`in ilk 4000 birimini tutar: tespitler kesilmemeli.
        let text = try XCTUnwrap(o["text"] as? String)
        XCTAssertLessThanOrEqual(text.utf16.count, 4000)
        XCTAssertTrue(text.hasSuffix("muhtemel sebep: yok"))
        let images = try XCTUnwrap(o["images"] as? [[String: Any]])
        XCTAssertLessThanOrEqual(images.count, 3)
        for image in images {
            XCTAssertEqual(image["mime"] as? String, "image/jpeg")
            let bytes = Data(base64Encoded: image["data"] as? String ?? "")
            XCTAssertLessThanOrEqual(bytes?.count ?? .max, 1500 * 1024)
        }
    }

    func testReportTooLargeForServerIsRefusedLocally() {
        let photos = (0..<3).map { _ in Self.photo(bytes: 1400 * 1024) }
        let report = ProblemReport(kind: .user, description: "x", findings: "", photos: photos, device: "")
        XCTAssertThrowsError(try ReportContract.body(report, context: ReportContext(install: Self.install, app: "4.1.0",
                                                                                     language: "tr")))
    }

    func testReportServerReplies() {
        func r(_ status: Int, _ body: String) -> ReportError? {
            ReportContract.interpret(status: status, data: Data(body.utf8)).failureValue
        }
        XCTAssertNil(r(200, #"{"ok":true,"id":"x"}"#))
        XCTAssertEqual(r(400, #"{"ok":false,"error":"bad_report"}"#), .server)
        XCTAssertEqual(r(413, #"{"ok":false,"error":"image_too_large"}"#), .tooLarge)
        XCTAssertEqual(r(413, #"{"ok":false,"error":"too_large"}"#), .tooLarge)
        XCTAssertEqual(r(429, #"{"ok":false,"error":"rate_limited"}"#), .dailyLimit)
        XCTAssertEqual(r(503, #"{"ok":false,"error":"server"}"#), .server)
    }

    // MARK: POST /v1/assistant

    func testAssistantBodyMatchesValidateConversation() throws {
        let chat = [AssistantMessage(role: .user, text: "TV'ye nasıl kurarım?", photos: [Self.photo(bytes: 1000)]),
                    AssistantMessage(role: .assistant, text: "Hangi TV?"),
                    AssistantMessage(role: .user, text: String(repeating: "ş", count: 2500))]
        let data = try AssistantContract.body(for: chat, context: AssistantContext(install: Self.install, app: "4.1.0",
                                                                                     language: "tr", device: "Mac16,1"))
        XCTAssertLessThanOrEqual(data.count, 6 * 1024 * 1024)
        let o = try object(data)
        XCTAssertTrue(Set(o.keys).isSubset(of: Self.assistantFields), "\(o.keys.sorted())")
        XCTAssertEqual(o["v"] as? Int, 1)
        XCTAssertEqual(o["platform"] as? String, "mac")
        let messages = try XCTUnwrap(o["messages"] as? [[String: Any]])
        XCTAssertLessThanOrEqual(messages.count, 24)
        XCTAssertEqual(messages.last?["role"] as? String, "user")
        for m in messages {
            XCTAssertTrue(["user", "assistant"].contains(m["role"] as? String ?? ""))
            XCTAssertLessThanOrEqual((m["text"] as? String)?.utf16.count ?? .max, 2000)
            if m["role"] as? String == "assistant" { XCTAssertNil(m["images"]) }
            for image in (m["images"] as? [[String: Any]]) ?? [] {
                XCTAssertTrue(["image/jpeg", "image/png", "image/webp"].contains(image["mime"] as? String ?? ""))
            }
        }
    }

    func testAssistantServerReplies() {
        func r(_ status: Int, _ body: String) -> AssistantError? {
            AssistantContract.interpret(status: status, data: Data(body.utf8)).failureValue
        }
        XCTAssertEqual(try AssistantContract.interpret(status: 200, data: Data(#"{"ok":true,"reply":"Merhaba","report":null}"#.utf8)).get(),
                       AssistantReply(text: "Merhaba", reportID: nil))
        XCTAssertEqual(try AssistantContract.interpret(status: 200, data: Data(#"{"ok":true,"reply":"Tamam","report":"abc"}"#.utf8)).get(),
                       AssistantReply(text: "Tamam", reportID: "abc"))
        XCTAssertEqual(r(503, #"{"ok":false,"error":"assistant_disabled"}"#), .disabled)
        XCTAssertEqual(r(503, #"{"ok":false,"error":"server"}"#), .busy)
        XCTAssertEqual(r(429, #"{"ok":false,"error":"rate_limited"}"#), .dailyLimit)
        XCTAssertEqual(r(429, #"{"ok":false,"error":"busy"}"#), .busy)
        XCTAssertEqual(r(413, #"{"ok":false,"error":"image_too_large"}"#), .tooLarge)
        XCTAssertEqual(r(413, #"{"ok":false,"error":"too_large"}"#), .tooLarge)
        XCTAssertEqual(r(400, #"{"ok":false,"error":"bad_image"}"#), .rejected)
        XCTAssertEqual(r(400, #"{"ok":false,"error":"too_many_images"}"#), .rejected)
        XCTAssertEqual(r(502, #"{"ok":false,"error":"model_failed"}"#), .serverError)
        XCTAssertEqual(r(502, #"{"ok":false,"error":"refused"}"#), .serverError)
    }

    // MARK: POST /v1/identify

    /// Sunucu: gövde ≤ 600 KB, `image.length × 0.75` ≤ 450 KB, `install` UUID.
    func testIdentifyBodyFitsServerLimits() throws {
        let client = GameIdentifyClient(network: SheetsFakeNetwork(), baseURL: URL(string: "http://127.0.0.1:9")!,
                                        appVersion: "4.1.0", install: Self.install)
        let body = try client.body(jpeg: Data(count: GameIdentifyClient.maxBytes))
        XCTAssertLessThanOrEqual(body.count, 600 * 1024)
        let o = try object(body)
        let image = try XCTUnwrap(o["image"] as? String)
        XCTAssertLessThanOrEqual(Double(image.count) * 0.75, 450 * 1024)
        XCTAssertEqual(o["v"] as? Int, 1)
        XCTAssertNotNil(UUID(uuidString: o["install"] as? String ?? ""))
        // Sunucu cevapları: tanınmadı / tanındı.
        XCTAssertNil(GameIdentifyClient.game(from: Data(#"{"ok":true,"game":null,"id":null,"confidence":0}"#.utf8)))
        XCTAssertEqual(GameIdentifyClient.game(from: Data(#"{"ok":true,"game":"Grand Theft Auto VI","id":"grand-theft-auto-vi","confidence":0.9}"#.utf8)),
                       "Grand Theft Auto VI")
    }

    // MARK: GET /v1/config

    @MainActor
    func testDownloadCounterReadsServerConfig() async throws {
        let body = #"{"ok":true,"translate":{"enabled":true},"poolFirst":{"games":[]},"minVersion":{"mac":""},"downloads":4321}"#
        let network = SheetsFakeNetwork { _ in (200, Data(body.utf8)) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "nino-contract-\(UUID().uuidString)"))
        let counter = DownloadCounterService(network: network, defaults: defaults)
        let n = await counter.refresh()
        XCTAssertEqual(n, 4321)
        XCTAssertEqual(network.requests.first?.url?.path, "/v1/config")
        XCTAssertEqual(network.requests.first?.httpMethod, "GET")
        // Sayı yoksa (sunucu alanı hiç göndermez) sayaç görünmez.
        XCTAssertNil(DownloadCounterService.parse(Data(#"{"ok":true}"#.utf8)))
    }

    // MARK: Yerel sunucuyla uçtan uca (isteğe bağlı)

    /// `NINO_LOCAL_POOL_URL=http://127.0.0.1:8799` verilirse yerel `wrangler dev`'e gerçek istek gider. Ağ, yalnız
    /// yerel adrese giden (canlı adresi yerel adrese çeviren) istemciyle kurulur. `NINO_CONTRACT_DUMP` klasörü
    /// verilirse yardımcı ve tanıma gövdeleri oraya yazılır (sunucu doğrulamasında denemek için).
    @MainActor
    func testLocalServerEndToEnd() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["NINO_LOCAL_POOL_URL"], let base = URL(string: raw) else {
            throw XCTSkip("NINO_LOCAL_POOL_URL verilmedi")
        }
        let network = try LoopbackNetwork(local: base)

        // Sorun bildirimi: 200 {ok, id}.
        let report = ProblemReport(kind: .user, description: "Yerel sözleşme denemesi", findings: "— tespitler —",
                                   photos: [try PhotoAttachment.prepare(data: Self.pngData())],
                                   logs: "Nino 4.1.0\nsatır", device: "app: 4.1.0 | device: Mac")
        let sent = await ReportClient(network: network, baseURL: base, appVersion: "4.1.0")
            .send(report, context: ReportContext(install: Self.install, app: "4.1.0", language: "tr"))
        XCTAssertNoThrow(try sent.get())
        XCTAssertEqual(network.statuses["/v1/reports"], 200)

        // İndirme sayacı: canlı adres yerel adrese çevrilir; yerel veritabanında sayı varsa okunur.
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "nino-contract-\(UUID().uuidString)"))
        let count = await DownloadCounterService(network: network, defaults: defaults).refresh()
        XCTAssertEqual(network.statuses["/v1/config"], 200)
        if env["NINO_LOCAL_POOL_SEEDED"] == "1" { XCTAssertEqual(count, 4321) }

        // Yardımcı: yerelde model anahtarı yok → 503 assistant_disabled → "kapalı".
        let chat = [AssistantMessage(role: .user, text: "TV'ye nasıl kurarım?")]
        let context = AssistantContext(install: Self.install, app: "4.1.0", language: "tr", device: "Mac16,1")
        let answer = await AssistantClient(network: network, baseURL: base, appVersion: "4.1.0").ask(chat, context: context)
        XCTAssertEqual(answer.failureValue, .disabled)

        // Tanıma: yerelde Claude kapalı → 503 → nil.
        let identify = GameIdentifyClient(network: network, baseURL: base, appVersion: "4.1.0", install: Self.install)
        let frame = try XCTUnwrap(NSBitmapImageRep(data: Self.pngData())?.cgImage)
        let game = await identify.identify(frame)
        XCTAssertNil(game)
        XCTAssertEqual(network.statuses["/v1/identify"], 503)

        if let dump = env["NINO_CONTRACT_DUMP"] {
            let folder = URL(fileURLWithPath: dump, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let photo = try PhotoAttachment.prepare(data: Self.pngData())
            let assistantChat = [AssistantMessage(role: .user, text: "Merhaba", photos: [photo]),
                                 AssistantMessage(role: .assistant, text: "Selam! Hangi TV?"),
                                 AssistantMessage(role: .user, text: "TCL Google TV, PS5 ve Mac")]
            try AssistantContract.body(for: assistantChat, context: context).write(to: folder.appendingPathComponent("assistant.json"))
            let jpeg = try XCTUnwrap(GameIdentifyClient.jpeg(frame))
            try identify.body(jpeg: jpeg).write(to: folder.appendingPathComponent("identify.json"))
            try ReportContract.body(report, context: ReportContext(install: Self.install, app: "4.1.0", language: "tr"))
                .write(to: folder.appendingPathComponent("report.json"))
        }
    }

    static func pngData() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 180, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<320 { for y in 0..<180 { rep.setColor(NSColor(red: CGFloat(x) / 320, green: CGFloat(y) / 180, blue: 0.5, alpha: 1), atX: x, y: y) } }
        return rep.representation(using: .png, properties: [:])!
    }
}

/// Yalnız yerel adrese giden gerçek istemci: canlı havuz adresini yerel adrese çevirir, başka her adresi reddeder.
final class LoopbackNetwork: NetworkClient, @unchecked Sendable {
    let local: URL
    private let lock = NSLock()
    private var _statuses: [String: Int] = [:]
    var statuses: [String: Int] { lock.withLock { _statuses } }

    init(local: URL) throws {
        guard let host = local.host, ["127.0.0.1", "localhost", "::1"].contains(host) else { throw URLError(.unsupportedURL) }
        self.local = local
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var r = request
        guard var components = r.url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else {
            throw URLError(.badURL)
        }
        if components.host == PoolServer.liveURL.host {
            components.scheme = local.scheme
            components.host = local.host
            components.port = local.port
        }
        guard let host = components.host, ["127.0.0.1", "localhost", "::1"].contains(host), let url = components.url else {
            throw URLError(.unsupportedURL)
        }
        r.url = url
        let (data, response) = try await URLSession.shared.data(for: r)
        guard let http = response as? HTTPURLResponse else { throw NetworkClientError.notHTTP }
        lock.withLock { _statuses[url.path] = http.statusCode }
        return (data, http)
    }
}
