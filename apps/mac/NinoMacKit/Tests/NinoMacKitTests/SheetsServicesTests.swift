// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import XCTest
@testable import NinoMacKit

/// Sahte ağ: hiçbir istek dışarı çıkmaz; istekler kaydedilir, cevap elle verilir.
final class SheetsFakeNetwork: NetworkClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    var handler: @Sendable (URLRequest) throws -> (Int, Data)

    init(_ handler: @escaping @Sendable (URLRequest) throws -> (Int, Data) = { _ in (200, Data("{}".utf8)) }) {
        self.handler = handler
    }

    var requests: [URLRequest] { lock.withLock { _requests } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _requests.append(request) }
        let (status, data) = try handler(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    static func json(_ status: Int, _ object: Any) -> (Int, Data) {
        (status, try! JSONSerialization.data(withJSONObject: object))
    }
}

final class SheetsServicesTests: XCTestCase {
    var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("nino-sheets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temp)
    }

    // MARK: Geçmiş

    func testHistoryLimitMergeAndFile() throws {
        var list: [HistoryEntry] = []
        for i in 0..<230 {
            list = HistoryStore.adding(HistoryEntry(date: Date(timeIntervalSince1970: Double(i)), source: "Line \(i)",
                                                    translated: "Satır \(i)", origin: .pack), to: list)
        }
        XCTAssertEqual(list.count, 200)
        XCTAssertEqual(list.first?.source, "Line 229")
        // Aynı kaynak art arda: yeni satır açılmaz.
        list = HistoryStore.adding(HistoryEntry(date: Date(), source: "line 229!", translated: "Düzeltildi",
                                                origin: .engine), to: list)
        XCTAssertEqual(list.count, 200)
        XCTAssertEqual(list.first?.translated, "Düzeltildi")
        // 500 karakter sınırı.
        list = HistoryStore.adding(HistoryEntry(date: Date(), source: String(repeating: "a", count: 900),
                                                translated: "x"), to: list)
        XCTAssertEqual(list.first?.source.count, 500)

        let store = HistoryStore(file: temp.appendingPathComponent("history.json"))
        store.save(list)
        store.flush()
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 200)
        XCTAssertEqual(loaded[1].translated, "Düzeltildi")
        XCTAssertEqual(loaded[1].origin, .engine)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: store.file)) as? [String: Any]
        XCTAssertEqual(json?["version"] as? Int, 1)
        XCTAssertEqual((json?["entries"] as? [[String: Any]])?.first?["id"] as? Int, 200)
        store.clear()
        store.flush()
        XCTAssertTrue(store.load().isEmpty)
    }

    func testHistoryClipboardText() {
        let entry = HistoryEntry(date: Date(timeIntervalSince1970: 0), source: "Come here.", translated: "Buraya gel.")
        XCTAssertEqual(HistoryStore.clipboardText(entry), "Buraya gel.\nCome here.")
        XCTAssertEqual(HistoryStore.timeText(Date(timeIntervalSince1970: 3723), timeZone: TimeZone(identifier: "UTC")!),
                       "01:02:03")
    }

    // MARK: Sağlık

    func testHealthLevelsAndThresholds() {
        var m = HealthMetrics()
        XCTAssertEqual(HealthRules.video(m), .notMeasured)
        XCTAssertEqual(HealthRules.console(m), .notMeasured)
        m.hasMeasurements = true
        m.lossPerMinute = 9; m.stallsPerMinute = 2
        XCTAssertEqual(HealthRules.video(m), .good)
        m.lossPerMinute = 10
        XCTAssertEqual(HealthRules.video(m), .fair)
        m.lossPerMinute = 0; m.stallsPerMinute = 4
        XCTAssertEqual(HealthRules.video(m), .problem)
        m.medianTranslationMs = 1499
        XCTAssertEqual(HealthRules.translation(m), .good)
        m.medianTranslationMs = 1500
        XCTAssertEqual(HealthRules.translation(m), .fair)
        m.medianTranslationMs = 3000
        XCTAssertEqual(HealthRules.translation(m), .problem)
        m.connectAttempts = 1
        XCTAssertEqual(HealthRules.console(m), .notMeasured)
        m.connectAttempts = 2
        XCTAssertEqual(HealthRules.console(m), .problem)
        m.connections = 1; m.dropsWhileStreaming = 3
        XCTAssertEqual(HealthRules.console(m), .fair)
        m.network = .wifi
        XCTAssertEqual(HealthRules.network(m), .problem) // görüntüyle aynı
        m.network = .wired
        XCTAssertEqual(HealthRules.network(m), .good)
        m.network = .unknown
        XCTAssertEqual(HealthRules.network(m), .notMeasured)
        XCTAssertEqual(HealthRules.tv(m), .notMeasured)
        m.translating = true; m.subtitlesOnTV = true
        XCTAssertEqual(HealthRules.tv(m), .problem)
        m.connectedTVs = 1
        XCTAssertEqual(HealthRules.tv(m), .good)
    }

    func testHealthCausesOrder() {
        var m = HealthMetrics()
        m.network = .offline
        XCTAssertEqual(HealthRules.causes(m), [.noNetwork])
        m = HealthMetrics()
        m.hasMeasurements = true
        m.translating = true
        m.network = .wifi
        m.connections = 1
        m.ps5DownSince = Date()
        m.lastDropReason = .asleep
        m.lossPerMinute = 50; m.stallsPerMinute = 0
        m.medianTranslationMs = 2000
        m.tvDrops = 2
        XCTAssertEqual(HealthRules.causes(m), [.ps5Asleep, .pictureLossWifi, .slowTranslation(seconds: 2.0), .tvDropped(times: 2)])
        m.networkDrops = 1
        XCTAssertEqual(HealthRules.causes(m).first, .droppedAfterNetworkLoss)
        m.ps5DownSince = nil
        XCTAssertEqual(HealthRules.causes(m).prefix(2), [.networkDropped(times: 1), .pictureLossWifi])
        m = HealthMetrics()
        m.hasMeasurements = true
        m.connectAttempts = 3
        XCTAssertEqual(HealthRules.causes(m), [.couldNotConnect])
        m = HealthMetrics()
        m.hasMeasurements = true
        m.network = .wired
        m.connections = 1
        m.dropsWhileStreaming = 4
        m.lossPerMinute = 0; m.stallsPerMinute = 0
        XCTAssertEqual(HealthRules.causes(m), [.frequentDrops(times: 4)])
        m.dropsWhileStreaming = 0
        m.translating = true; m.receivingVideo = true
        XCTAssertTrue(HealthRules.allGood(m))
    }

    func testProblemDetector() {
        var detector = ProblemDetector()
        var m = HealthMetrics()
        m.translating = true; m.receivingVideo = true; m.network = .wifi; m.subtitlesOnTV = true; m.connectedTVs = 1
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(detector.observe(m, now: t0), [])
        m.ps5DownSince = t0; m.receivingVideo = false; m.network = .offline; m.connectedTVs = 0
        XCTAssertEqual(detector.observe(m, now: t0.addingTimeInterval(1)), [.ps5Dropped, .networkLost])
        XCTAssertEqual(detector.observe(m, now: t0.addingTimeInterval(22)), [.tvDropped])
        XCTAssertEqual(detector.observe(m, now: t0.addingTimeInterval(181)), [.ps5Unreachable])
        XCTAssertEqual(detector.observe(m, now: t0.addingTimeInterval(300)), [])
    }

    func testProblemLogKeepsFortyAndReloads() {
        let file = temp.appendingPathComponent("sorunlar.json")
        let log = ProblemLog(file: file)
        for i in 0..<45 {
            log.add(ProblemRecord(date: Date(timeIntervalSince1970: Double(i) * 3600), kind: .ps5Dropped,
                                  network: "wifi", game: "GTA 6"))
        }
        let again = ProblemLog(file: file)
        XCTAssertEqual(again.all.count, 40)
        XCTAssertEqual(again.recent(1).first?.date, Date(timeIntervalSince1970: 44 * 3600))
        XCTAssertEqual(again.within(days: 1, of: Date(timeIntervalSince1970: 44 * 3600)).count, 25)
        // Eski okuyucuyla da okunur (aynı biçim).
        XCTAssertEqual(DataFiles.incidents(at: file).count, 40)
    }

    // MARK: Nino'ya Sor sözleşmesi

    func testAssistantBodyRules() throws {
        let photo = PhotoAttachment(jpeg: Data([1, 2, 3]), pixelWidth: 1, pixelHeight: 1)
        var chat: [AssistantMessage] = []
        chat.append(AssistantMessage(role: .user, text: "ilk soru", photos: [photo]))
        chat.append(AssistantMessage(role: .assistant, text: "cevap"))
        chat.append(AssistantMessage(role: .user, text: "", photos: [photo, photo, photo, photo]))
        chat.append(AssistantMessage(role: .assistant, text: "", localError: .busy))
        chat.append(AssistantMessage(role: .user, text: "gönderilemeyen", failed: .offline))
        chat.append(AssistantMessage(role: .user, text: "  son  ", photos: [photo]))
        let context = AssistantContext(install: "abc", app: "4.1.0", language: "tr", device: "")
        let data = try AssistantContract.body(for: chat, context: context)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("\\/"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["device"])
        XCTAssertEqual("mac", json["platform"] as? String)
        let sent = (json["messages"] as? [[String: Any]]) ?? []
        XCTAssertEqual(sent.map { $0["text"] as? String }, ["[screenshot] ilk soru", "cevap", "", "son"])
        // Eski mesajın fotoğrafı etikete döner; son kullanıcı mesajının en çok 3 fotoğrafı gider.
        XCTAssertNil(sent.first?["images"])
        XCTAssertEqual((sent[2]["images"] as? [Any])?.count, 3)

        // Son mesaj robotunsa gönderilmez.
        XCTAssertThrowsError(try AssistantContract.body(for: [AssistantMessage(role: .assistant, text: "x")],
                                                        context: context))
        // İlk mesaj robotunsa atılır; en çok 24 mesaj.
        var long: [AssistantMessage] = []
        for i in 0..<30 { long.append(AssistantMessage(role: i % 2 == 0 ? .assistant : .user, text: "m\(i)")) }
        let longJSON = try JSONSerialization.jsonObject(with: AssistantContract.body(for: long, context: context))
        let longMessages = try XCTUnwrap((longJSON as? [String: Any])?["messages"] as? [[String: Any]])
        XCTAssertEqual(longMessages.count, 23)
        XCTAssertEqual(longMessages.first?["role"] as? String, "user")
    }

    func testAssistantClipUTF16() {
        let emoji = String(repeating: "👋", count: 1500) // 3000 UTF-16 birimi
        let clipped = AssistantContract.clip(emoji)
        XCTAssertEqual(clipped.utf16.count, 2000)
        XCTAssertEqual(clipped.count, 1000)
    }

    func testAssistantStatusMapping() {
        func map(_ status: Int, _ body: Any) -> Result<AssistantReply, AssistantError> {
            AssistantContract.interpret(status: status, data: try! JSONSerialization.data(withJSONObject: body))
        }
        XCTAssertEqual(map(200, ["ok": true, "reply": " Merhaba ", "report": "r1"]),
                       .success(AssistantReply(text: "Merhaba", reportID: "r1")))
        XCTAssertEqual(map(200, ["ok": true, "reply": ""]), .failure(.serverError))
        XCTAssertEqual(map(400, [:]), .failure(.rejected))
        XCTAssertEqual(map(413, [:]), .failure(.tooLarge))
        XCTAssertEqual(map(429, ["error": "busy"]), .failure(.busy))
        XCTAssertEqual(map(429, [:]), .failure(.dailyLimit))
        XCTAssertEqual(map(503, ["error": "assistant_disabled"]), .failure(.disabled))
        XCTAssertEqual(map(503, [:]), .failure(.busy))
        XCTAssertEqual(map(500, [:]), .failure(.serverError))
        XCTAssertTrue(AssistantError.offline.retryable)
        XCTAssertFalse(AssistantError.dailyLimit.retryable)
    }

    func testAssistantClientUsesSheetsFakeNetwork() async throws {
        let network = SheetsFakeNetwork { _ in SheetsFakeNetwork.json(200, ["ok": true, "reply": "Tamam"]) }
        let client = AssistantClient(network: network, baseURL: URL(string: "https://pool.test/")!, appVersion: "4.1.0")
        let result = await client.ask([AssistantMessage(role: .user, text: "Selam")],
                                      context: AssistantContext(install: "i", app: "4.1.0", language: "tr", device: "Mac"))
        XCTAssertEqual(result, .success(AssistantReply(text: "Tamam", reportID: nil)))
        let request = try XCTUnwrap(network.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://pool.test/v1/assistant")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 90)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "nino-assistant/1 (mac; 4.1.0)")
        let failing = AssistantClient(network: SheetsFakeNetwork { _ in throw URLError(.notConnectedToInternet) },
                                      baseURL: PoolServer.liveURL, appVersion: "1")
        let offline = await failing.ask([AssistantMessage(role: .user, text: "x")],
                                        context: AssistantContext(install: "", app: "", language: "en", device: ""))
        XCTAssertEqual(offline, .failure(.offline))
        let noAddress = AssistantClient(network: network, baseURL: nil, appVersion: "1")
        let none = await noAddress.ask([], context: AssistantContext(install: "", app: "", language: "en", device: ""))
        XCTAssertEqual(none, .failure(.noAddress))
    }

    func testPoolServerAddress() {
        XCTAssertEqual(PoolServer.baseURL(environment: ["NINO_POOL_URL": "http://localhost:8787"], userValue: "https://x"),
                       URL(string: "http://localhost:8787"))
        XCTAssertEqual(PoolServer.baseURL(environment: ["NINO_POOL_URL": "ftp://x"], userValue: "https://y.test"),
                       URL(string: "https://y.test"))
        XCTAssertEqual(PoolServer.baseURL(environment: [:], userValue: "nonsense"), PoolServer.liveURL)
    }

    @MainActor
    func testAssistantChatFlow() async {
        let chat = AssistantChat()
        chat.draft = "Merhaba"
        var answers: [Result<AssistantReply, AssistantError>] = [.failure(.offline),
                                                                 .success(AssistantReply(text: "Selam", reportID: "r"))]
        let ask: @MainActor ([AssistantMessage]) async -> Result<AssistantReply, AssistantError> = { _ in
            answers.removeFirst()
        }
        XCTAssertTrue(chat.canSend)
        chat.send(using: ask)
        XCTAssertEqual(chat.draft, "")
        XCTAssertTrue(chat.waiting)
        await chat.waitForReply()
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.messages[0].failed, .offline)
        XCTAssertEqual(chat.messages[1].localError, .offline)
        chat.retry(using: ask)
        await chat.waitForReply()
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertNil(chat.messages[0].failed)
        XCTAssertEqual(chat.messages[1].text, "Selam")
        XCTAssertTrue(chat.messages[1].reportSent)
        chat.addPhotos(Array(repeating: PhotoAttachment(jpeg: Data(), pixelWidth: 1, pixelHeight: 1), count: 5))
        XCTAssertEqual(chat.attachments.count, 3)
        XCTAssertFalse(chat.canAddPhoto)
        chat.reset()
        XCTAssertFalse(chat.hasMessages)
        XCTAssertTrue(chat.attachments.isEmpty)
    }

    func testAssistantFormatting() {
        let text = """
        Şunları yap:
        1. PS5'i aç.
           Ayarlar'a gir.
        2) TV'yi aç.
        - Kablo kullan
        • ya da 5 GHz

        2024. yılında çıktı.
        www.example.com.
        """
        let blocks = AssistantFormatting.parseBlocks(text)
        XCTAssertEqual(blocks, [
            .paragraph("Şunları yap:"),
            .step(number: "1", text: "PS5'i aç.\nAyarlar'a gir."),
            .step(number: "2", text: "TV'yi aç."),
            .bullet("Kablo kullan"),
            .bullet("ya da 5 GHz"),
            .paragraph("2024. yılında çıktı.\nwww.example.com."),
        ])
        let attributed = AssistantFormatting.linkified("Bak: https://nino.test/a. Sonra")
        let links = attributed.runs.compactMap(\.link)
        XCTAssertEqual(links, [URL(string: "https://nino.test/a")!])
    }

    // MARK: Sorun Bildir

    func testReportBodyAndStatus() throws {
        let report = ProblemReport(kind: .user, description: " Takıldı ", findings: "— Nino'nun bulguları —",
                                   contact: "oyuncu@example.com", photos: [PhotoAttachment(jpeg: Data([9]), pixelWidth: 1,
                                                                              pixelHeight: 1)],
                                   logs: "log", device: "Mac")
        let data = try ReportContract.body(report, context: ReportContext(install: "i", app: "4.1.0", language: "tr"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["text"] as? String, "Takıldı\n\n— Nino'nun bulguları —")
        XCTAssertEqual(json["contact"] as? String, "oyuncu@example.com")
        XCTAssertEqual(json["log"] as? String, "log")
        XCTAssertNil(json["logs"])
        XCTAssertEqual("mac", json["platform"] as? String)
        XCTAssertEqual((json["images"] as? [Any])?.count, 1)
        let auto = try JSONSerialization.jsonObject(with: ReportContract.body(
            ProblemReport(kind: .auto, description: "", findings: "x", device: ""),
            context: ReportContext(install: "", app: "", language: "en"))) as? [String: Any]
        XCTAssertEqual(auto?["kind"] as? String, "auto")
        XCTAssertNil(auto?["contact"])
        XCTAssertNil(auto?["log"])
        XCTAssertNoThrow(try ReportContract.interpret(status: 201, data: Data()).get())
        XCTAssertEqual(ReportContract.interpret(status: 429, data: Data()).failureValue, .dailyLimit)
        XCTAssertEqual(ReportContract.interpret(status: 413, data: Data()).failureValue, .tooLarge)
        XCTAssertEqual(ReportContract.interpret(status: 400, data: Data()).failureValue, .server)
    }

    func testReportClientNeverLeavesFake() async throws {
        let network = SheetsFakeNetwork { _ in (200, Data(#"{"ok":true}"#.utf8)) }
        let client = ReportClient(network: network, baseURL: URL(string: "https://pool.test")!, appVersion: "4.1.0")
        let result = await client.send(ProblemReport(kind: .user, description: "", findings: "", device: ""),
                                       context: ReportContext(install: "i", app: "4.1.0", language: "tr"))
        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(network.requests.first?.url?.absoluteString, "https://pool.test/v1/reports")
        let offline = await ReportClient(network: SheetsFakeNetwork { _ in throw URLError(.timedOut) },
                                         baseURL: PoolServer.liveURL, appVersion: "1")
            .send(ProblemReport(kind: .user, description: "", findings: "", device: ""),
                  context: ReportContext(install: "", app: "", language: "en"))
        XCTAssertEqual(offline.failureValue, .offline)
    }

    // MARK: Sorun Bildir ekleri

    func testReportAttachmentLimits() {
        func image(_ bytes: Int) -> ReportAttachment {
            ReportAttachment(name: "r.jpg", content: .image(PhotoAttachment(jpeg: Data(count: bytes), pixelWidth: 1,
                                                                            pixelHeight: 1)))
        }
        func text(_ n: String) -> ReportAttachment { ReportAttachment(name: n, content: .text("satır")) }
        // En çok 3 resim (sunucu sınırı), toplam en çok 5 dosya.
        var r = ReportAttachments.merge([], [image(10), image(10), image(10), image(10)])
        XCTAssertEqual(r.attachments.count, 3)
        XCTAssertTrue(r.limited)
        r = ReportAttachments.merge(r.attachments, [text("a.txt"), text("b.txt"), text("c.txt")])
        XCTAssertEqual(r.attachments.count, 5)
        XCTAssertTrue(r.limited)
        // Toplam boyut 2,8 MB'ı geçemez.
        r = ReportAttachments.merge([], [image(1_000_000), image(1_000_000), image(900_000)])
        XCTAssertEqual(r.attachments.count, 2)
        XCTAssertTrue(r.limited)
        XCTAssertFalse(ReportAttachments.merge([], [text("a.txt")]).limited)
    }

    func testReportAttachmentReadsTextAndRejectsBinary() throws {
        let txt = temp.appendingPathComponent("not.txt")
        try Data("\u{FEFF}Merhaba\nikinci satır".utf8).write(to: txt)
        let item = try ReportAttachments.prepare(fileAt: txt)
        XCTAssertEqual(item.textFile, ReportTextFile(name: "not.txt", text: "Merhaba\nikinci satır"))
        let bin = temp.appendingPathComponent("ikili.txt")
        try Data([0x41, 0, 0x42]).write(to: bin)
        XCTAssertThrowsError(try ReportAttachments.prepare(fileAt: bin))
        let big = temp.appendingPathComponent("buyuk.log")
        try Data(repeating: 0x61, count: ReportAttachments.maxTextFileBytes + 1).write(to: big)
        XCTAssertThrowsError(try ReportAttachments.prepare(fileAt: big)) {
            XCTAssertEqual($0 as? ReportAttachments.Failure, .limit)
        }
    }

    func testReportBodyWithTextFilesKeepsServerShape() throws {
        let ctx = ReportContext(install: "kurulum-1", app: "4.1.0", language: "tr")
        let plain = ProblemReport(kind: .user, description: "x", findings: "f", logs: "günlük", device: "Mac")
        // Ek yoksa gövde eskisiyle bayt bayt aynı (alan eklenmez).
        let legacy = try ContractJSON.encode(["v": 1, "kind": "user", "install": "kurulum-1", "app": "4.1.0",
                                              "platform": "mac", "language": "tr", "text": "x\n\nf",
                                              "device": "Mac", "log": "günlük"])
        XCTAssertEqual(try ReportContract.body(plain, context: ctx), legacy)

        var with = plain
        with.logs = String(repeating: "eski satır\n", count: 10_000)
        with.textFiles = [ReportTextFile(name: "oyun.txt", text: "OYUN-KAYDI-SONU"),
                          ReportTextFile(name: "uzun.txt", text: String(repeating: "u", count: 40_000) + "UZUN-SON")]
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: ReportContract.body(with, context: ctx))
            as? [String: Any])
        XCTAssertNil(o["files"])
        let log = try XCTUnwrap(o["log"] as? String)
        XCTAssertLessThanOrEqual(log.utf16.count, ReportContract.maxLogUnits)
        XCTAssertTrue(log.contains("— ek: oyun.txt —\nOYUN-KAYDI-SONU"))
        XCTAssertTrue(log.hasSuffix("UZUN-SON"), "ekler sonda, kesilmeden")
        XCTAssertTrue(log.hasPrefix("eski satır") || log.contains("eski satır"), "günlüğün sonu da kalır")
    }

    func testReportRedactsStoredKeys() throws {
        let key = "AIzaSyD-gizli-anahtar-1234567890"
        let report = ProblemReport(kind: .user, description: "anahtarım \(key)", findings: "", logs: "l \(key)",
                                   textFiles: [ReportTextFile(name: "a.txt", text: "KEY=\(key)")], device: "")
            .redacting([key, "kısa"])
        let body = try ReportContract.body(report, context: ReportContext(install: "kurulum-1", app: "1", language: "tr"))
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertFalse(text.contains(key))
        XCTAssertTrue(text.contains("[gizli]"))
    }

    @MainActor
    func testReportDraftSendResetsAfterThanks() async {
        let draft = ReportDraft()
        draft.description = "Ses yok"
        draft.add([ReportAttachment(name: "a.txt", content: .text("x"))])
        var delivered: ProblemReport?
        var done = false
        await draft.send(build: { ProblemReport(kind: .user, description: draft.description, findings: "", device: "") },
                         using: { delivered = $0; return .success(()) }, thanksDuration: .milliseconds(1),
                         onDone: { done = true })
        XCTAssertEqual(delivered?.description, "Ses yok")
        XCTAssertTrue(done)
        XCTAssertEqual(draft.description, "")
        XCTAssertTrue(draft.attachments.isEmpty)
        draft.description = "x"
        await draft.send(build: { ProblemReport(kind: .user, description: "x", findings: "", device: "") },
                         using: { _ in .failure(.dailyLimit) })
        XCTAssertEqual(draft.error, .dailyLimit)
        XCTAssertEqual(draft.phase, .editing)
        draft.description = "y"
        XCTAssertNil(draft.error) // yazı değişince hata silinir
    }

    // MARK: Fotoğraf

    func testPhotoAttachmentDownscalesAndFlattens() throws {
        let image = NSImage(size: NSSize(width: 3200, height: 1600))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 3200, height: 1600).fill()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 1600, height: 800).fill()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let png = rep.representation(using: .png, properties: [:])!
        let photo = try PhotoAttachment.prepare(data: png)
        XCTAssertEqual(max(photo.pixelWidth, photo.pixelHeight), 1600)
        XCTAssertLessThanOrEqual(photo.jpeg.count, PhotoAttachment.targetBytes)
        XCTAssertEqual(photo.jpeg.prefix(2), Data([0xFF, 0xD8]))
        XCTAssertThrowsError(try PhotoAttachment.prepare(data: Data("not an image".utf8)))
    }

    // MARK: Güncelleme ve sayaç

    func testVersionCompare() {
        XCTAssertTrue(VersionCompare.isNewer("0.1.10", than: "0.1.9"))
        XCTAssertTrue(VersionCompare.isNewer("v4.1", than: "4.0.9"))
        XCTAssertFalse(VersionCompare.isNewer("4.1", than: "4.1.0"))
        XCTAssertFalse(VersionCompare.isNewer("4.0.0", than: "4.1.0"))
    }

    @MainActor
    func testGitHubUpdateCheckerHourlyLimit() async {
        let release: [String: Any] = ["tag_name": "v4.2.0", "html_url": "https://github.com/x/releases/tag/v4.2.0",
                                      "assets": [["name": "Nino-Mac.zip", "browser_download_url": "https://dl.test/n.zip"]]]
        let network = SheetsFakeNetwork { _ in SheetsFakeNetwork.json(200, release) }
        var clock = Date(timeIntervalSince1970: 0)
        var installed: ReleaseInfo?
        let checker = GitHubUpdateChecker(network: network, currentVersion: "4.1.0", now: { clock },
                                          install: { installed = $0 })
        let first = await checker.check(force: false)
        XCTAssertEqual(first, .available(ReleaseInfo(version: "4.2.0",
                                                     notesURL: URL(string: "https://github.com/x/releases/tag/v4.2.0"),
                                                     downloadURL: URL(string: "https://dl.test/n.zip"))))
        clock = clock.addingTimeInterval(1800)
        let skipped = await checker.check(force: false)
        XCTAssertEqual(skipped, .skipped)
        let forced = await checker.check(force: true)
        if case .available = forced {} else { XCTFail("zorlanan denetim ağa çıkmalı") }
        XCTAssertEqual(network.requests.count, 2)
        XCTAssertEqual(network.requests.first?.value(forHTTPHeaderField: "User-Agent"), "Nino-Mac")
        checker.install()
        XCTAssertEqual(installed?.version, "4.2.0")
        XCTAssertEqual(UpdateStatus.from(.skipped, previous: .upToDate), .upToDate)
        XCTAssertEqual(UpdateStatus.from(.failed, previous: .checking), .failed(message: ""))

        let failing = GitHubUpdateChecker(network: SheetsFakeNetwork { _ in (500, Data()) }, currentVersion: "4.1.0",
                                          install: { _ in })
        let failed = await failing.check(force: true)
        XCTAssertEqual(failed, .failed)
        let fake = FakeUpdateService(result: .upToDate)
        let fakeResult = await fake.check(force: true)
        XCTAssertEqual(fakeResult, .upToDate)
        XCTAssertEqual(fake.checks, [true])
    }

    @MainActor
    func testDownloadCounter() async throws {
        let suiteName = "nino-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var answer: (Int, Data) = SheetsFakeNetwork.json(200, ["downloads": 7028])
        let network = SheetsFakeNetwork { _ in answer }
        var clock = Date(timeIntervalSince1970: 0)
        let counter = DownloadCounterService(network: network, defaults: defaults, now: { clock })
        XCTAssertNil(counter.stored)
        let first = await counter.refresh()
        XCTAssertEqual(first, 7028)
        XCTAssertEqual(network.requests.first?.url?.absoluteString,
                       "https://nino-pool.y-demirbag2506.workers.dev/v1/config")
        XCTAssertEqual(network.requests.first?.timeoutInterval, 10)
        answer = SheetsFakeNetwork.json(200, ["downloads": 9000])
        clock = clock.addingTimeInterval(300)
        let limited = await counter.refresh()
        XCTAssertEqual(limited, 7028) // 10 dakika dolmadı
        XCTAssertEqual(network.requests.count, 1)
        answer = SheetsFakeNetwork.json(200, ["downloads": 0])
        clock = clock.addingTimeInterval(600)
        let invalid = await counter.refresh()
        XCTAssertEqual(invalid, 7028) // 0 geçersiz, saklanan kalır
        answer = (503, Data())
        clock = clock.addingTimeInterval(600)
        let offline = await counter.refresh()
        XCTAssertEqual(offline, 7028)
        XCTAssertEqual(defaults.integer(forKey: "ninoDownloadTotal"), 7028)
    }

    // MARK: Destek metinleri ve zip

    @MainActor
    func testDeviceInfoAndDetails() throws {
        let state = PreviewEngine.sampleState()
        state.game = RecognizedGame(id: "gta-6", name: "GTA 6", poolFirst: true, evidence: .screen)
        let facts = DeviceFacts(appVersion: "4.1.0", build: "412", model: "Mac15,6", systemVersion: "macOS 27.0.0",
                                processor: "Apple M3 Pro", memoryGB: 18)
        let info = DeviceInfo.make(state: state, facts: facts, tvApp: .installed(version: "2.3"))
        XCTAssertEqual(info.rows.map(\.value), [
            "4.1.0 (412)", "Mac15,6", "macOS 27.0.0", "Android TV · TV uygulaması 2.3 · bağlı değil",
            "PS5 · Remote Play (Nino bağlanıyor)", "çeviri durdu, oyun: GTA 6 (ekrandan), PS5: boşta",
        ])
        XCTAssertFalse(info.summary.contains("Salon TV")) // TV'nin verilen adı yazılmaz
        XCTAssertFalse(info.summary.contains("192.168"))

        let logs = temp.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs.appendingPathComponent("frames"), withIntermediateDirectories: true)
        let lines = (1...100).map { "[2026-11-22 10:00:00.000] satır \($0)" }.joined(separator: "\n")
        try Data(lines.utf8).write(to: logs.appendingPathComponent("altyazi.log"))
        try Data("eski".utf8).write(to: logs.appendingPathComponent("altyazi.log.1"))
        try Data("ses".utf8).write(to: logs.appendingPathComponent("ses.f32"))
        try Data("kare".utf8).write(to: logs.appendingPathComponent("frames/latest.jpg"))
        let folder = DataFolder(support: temp, logs: logs)
        let details = DetailsText.make(state: state, facts: facts, metrics: HealthMetrics(), tvApp: .unknown,
                                       folder: folder)
        let detailLines = details.components(separatedBy: "\n")
        XCTAssertEqual(detailLines[0], "Nino 4.1.0, macOS 27.0.0, Apple M3 Pro, 18 GB")
        XCTAssertEqual(detailLines[1], "motor: ücretsiz, çeviri: durdu, PS5: boşta")
        XCTAssertTrue(details.contains("satır 61\n"))
        XCTAssertFalse(details.contains("satır 60\n"))
        XCTAssertTrue(details.hasSuffix("— tvinstall.log, son 8 satır —\n-"))

        let exporter = LogExporter(logsFolder: logs, destinations: [temp.appendingPathComponent("İndirilenler")],
                                   now: { Date(timeIntervalSince1970: 0) })
        XCTAssertEqual(exporter.logFiles().map(\.lastPathComponent), ["altyazi.log", "altyazi.log.1"])
        XCTAssertTrue(exporter.fileName().hasPrefix("Nino-kayitlar-"))
        XCTAssertFalse(exporter.fileName().contains(":"))
        let zip = try exporter.export(details: details)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path))
        let bytes = try Data(contentsOf: zip)
        XCTAssertEqual(bytes.prefix(2), Data("PK".utf8))
        let listing = String(decoding: bytes, as: UTF8.self)
        XCTAssertTrue(listing.contains("ayrintilar.txt"))
        XCTAssertFalse(listing.contains("latest.jpg"))
        XCTAssertFalse(listing.contains("ses.f32"))
    }

    // MARK: Metin tablosu

    func testEverySheetsKeyHasTurkishAndEnglish() throws {
        let keys = try Self.tableKeys()
        XCTAssertGreaterThan(keys.count, 150)
        for key in keys {
            XCTAssertNotEqual(NinoL10n.string(key, table: "Sheets", language: "tr"), key, key)
            XCTAssertNotEqual(NinoL10n.string(key, table: "Sheets", language: "en"), key, key)
        }
    }

    /// Kaynaklarda geçen her "sheets.…" anahtarı tabloda var (yazım hatası sessizce anahtarı gösterirdi).
    func testEverySheetsLiteralExistsInTable() throws {
        let keys = try Self.tableKeys()
        let root = Self.packageFolder.appendingPathComponent("Sources/NinoMacKit")
        var literals = Set<String>()
        let regex = try NSRegularExpression(pattern: #""(sheets\.[A-Za-z0-9_.]+(?: %[@dl]+)*)""#)
        for folder in ["UI/Sheets", "Services", "Model"] {
            let dir = root.appendingPathComponent(folder)
            for file in try FileManager.default.contentsOfDirectory(atPath: dir.path) where file.hasSuffix(".swift") {
                let text = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
                for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    literals.insert((text as NSString).substring(with: m.range(at: 1)))
                }
            }
        }
        XCTAssertGreaterThan(literals.count, 100)
        for literal in literals { XCTAssertTrue(keys.contains(literal), literal) }
        // Kod içinde birleştirilen anahtarlar.
        let ids = ["noNetwork", "afterNetworkLoss", "asleep", "elsewhere", "dropped", "couldNotConnect",
                   "pictureLossWifi", "pictureLossWired", "slow", "networkDropped", "frequentDrops", "tvDropped"]
        for id in ids { XCTAssertTrue(keys.contains("sheets.health.cause.\(id).title"), id) }
        for kind in ProblemKind.allCases { XCTAssertTrue(keys.contains("sheets.health.problem.\(kind.rawValue)")) }
        let reasons: [HealthDropReason] = [.asleep, .inUseElsewhere, .passcode, .remotePlayDisabled, .pairingInvalid,
                                           .notFound, .other]
        for r in reasons { XCTAssertTrue(keys.contains("sheets.health.consoleAdvice.\(r.rawValue)"), r.rawValue) }
        for key in DeviceInfo.summaryLabel.keys { XCTAssertTrue(keys.contains(key), key) }
    }

    func testCauseTextsResolveWithArguments() {
        let tr = Locale(identifier: "tr")
        XCTAssertEqual(HealthText.causeAction(.networkDropped(times: 3), tr),
                       "Bu Mac 3 kez ağdan düştü. Mac'i modeme Ethernet kablosuyla takın ya da modemin yanına taşıyın.")
        XCTAssertTrue(HealthText.causeAction(.slowTranslation(seconds: 2.5), tr).contains("2,5 sn"))
        for cause in [ProbableCause.noNetwork, .droppedAfterNetworkLoss, .ps5Asleep, .usedElsewhere, .ps5DroppedGeneral,
                      .couldNotConnect, .networkDropped(times: 1), .pictureLossWifi, .pictureLossWired,
                      .frequentDrops(times: 3), .slowTranslation(seconds: 2), .tvDropped(times: 1)] {
            XCTAssertFalse(HealthText.causeAction(cause, tr).hasPrefix("sheets."), "\(cause)")
            XCTAssertFalse(HealthText.causeTitle(cause, tr).hasPrefix("sheets."), "\(cause)")
        }
    }

    static var packageFolder: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func tableKeys() throws -> Set<String> {
        let url = packageFolder.appendingPathComponent("Sources/NinoMacKit/Resources/Sheets.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return Set(try XCTUnwrap(json?["strings"] as? [String: Any]).keys)
    }
}

extension Result {
    var failureValue: Failure? { if case .failure(let e) = self { return e }; return nil }
}
