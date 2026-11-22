// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Network
import XCTest
@testable import NinoCore

/// Eski TV gibi `/events`'i okuyan deneme istemcisi. Satırları kaydeder.
final class FakeLegacyTV: @unchecked Sendable {
    let lines = Recorder<String>()
    private var task: Task<Void, Never>?
    let session = URLSession(configuration: .ephemeral)

    init(port: UInt16, query: String = "") {
        let url = URL(string: "http://127.0.0.1:\(port)/events\(query)")!
        let lines = self.lines
        let session = self.session
        task = Task {
            guard let (bytes, _) = try? await session.bytes(from: url) else { return }
            do { for try await line in bytes.lines { lines.append(line) } } catch {}
        }
    }

    /// `event:` + `data:` çiftleri.
    var events: [(name: String, data: String)] {
        var out: [(String, String)] = []
        var name: String?
        for l in lines.values {
            if l.hasPrefix("event: ") { name = String(l.dropFirst(7)) }
            if l.hasPrefix("data: "), let n = name {
                out.append((n, String(l.dropFirst(6))))
                name = nil
            }
        }
        return out
    }

    func names() -> [String] { events.map(\.name).filter { $0 != "ping" } }

    func data(of name: String) -> [String: Any]? {
        events.last { $0.name == name }.flatMap { try? JSONSerialization.jsonObject(with: Data($0.data.utf8)) as? [String: Any] }
    }

    func close() {
        task?.cancel()
        session.invalidateAndCancel()
    }
}

final class LegacyTranslatorTests: XCTestCase {
    func testSubtitleShape() {
        var t = LegacyTranslator()
        let at = Date(timeIntervalSince1970: 1_732_233_600)
        let e = t.subtitle(ShowPayload(id: 1, text: "Selam", source: "Hi", durationMs: 0,
                                       box: NinoBox(left: 0.1, top: 1.2, right: 0.9, bottom: 0.95), replace: true,
                                       light: 0.333, cover: "QUJD"), now: at)
        XCTAssertEqual(e.name, "subtitle")
        XCTAssertEqual(e.data, #"{"at":1732233600000,"box":{"bottom":0.95,"left":0.1,"right":0.9,"top":1},"cover":"QUJD","duration":15000,"light":0.33,"replace":true,"text":"Selam"}"#)
        XCTAssertEqual(String(decoding: e.frame, as: UTF8.self), "event: subtitle\ndata: \(e.data)\n\n")
        let timed = t.subtitle(ShowPayload(id: 2, text: "Kısa", durationMs: 2500, replace: false), now: at)
        XCTAssertEqual(timed.data, #"{"at":1732233600000,"duration":2500,"text":"Kısa"}"#)
    }

    func testClearOnlyForLastSubtitle() {
        var t = LegacyTranslator()
        _ = t.subtitle(ShowPayload(id: 5, text: "a"))
        XCTAssertNil(t.clear(id: 4))
        XCTAssertEqual(t.clear(id: 5), LegacyEvent(name: "clear", body: [:]))
        XCTAssertNil(t.clear(id: 5), "zaten temiz")
        XCTAssertEqual(t.clear(id: nil)?.data, "{}")
    }

    func testEvents() {
        var t = LegacyTranslator()
        XCTAssertEqual(t.event(.style(NinoStyle(fontSize: 30, backgroundShape: "band", watermark: false))).data,
                       #"{"backgroundShape":"band","fontSize":30,"watermark":false}"#)
        XCTAssertEqual(t.event(.started), LegacyEvent(name: "started", body: [:]))
        XCTAssertEqual(t.event(.stopped).name, "stopped")
        let item = ScreenItem(box: NinoBox(left: 0, top: 0, right: 0.5, bottom: 0.1), text: "Ara", line: 0.025, italic: true, angle: 3.14)
        XCTAssertEqual(t.event(.screen(ScreenPayload(items: [item], durationMs: 120_000, overlay: true))).data,
                       #"{"duration":120000,"items":[{"angle":3.1,"box":{"bottom":0.1,"left":0,"right":0.5,"top":0},"italic":true,"line":0.025,"text":"Ara"}],"overlay":true}"#)
        XCTAssertEqual(t.event(.screen(ScreenPayload(items: [], durationMs: 10, overlay: false))).data, #"{"duration":10,"items":[]}"#)
        XCTAssertEqual(t.event(.screenClear).name, "screen-clear")
        XCTAssertEqual(t.event(.region(RegionPayload(id: "map", text: "Köprü", line: 0.02))).data, #"{"id":"map","line":0.02,"text":"Köprü"}"#)
        XCTAssertEqual(t.event(.regionClear).name, "region-clear")
        XCTAssertFalse(LegacyEvent(name: "started", body: [:]).isSubtitleEvent)
        XCTAssertTrue(LegacyEvent(name: "region", body: [:]).isSubtitleEvent)
    }

    func testSanitizeModel() {
        XCTAssertEqual(LegacyEventServer.sanitizeModel("LG <OLED55> C3 (2023)!"), "LG OLED55 C3 (2023)")
        XCTAssertEqual(LegacyEventServer.sanitizeModel(String(repeating: "a", count: 80)).count, 60)
    }
}

final class LegacyEventServerTests: XCTestCase {
    private var server: LegacyEventServer!
    private var port: UInt16 = 0

    override func setUp() async throws {
        server = LegacyEventServer(options: .init(port: 0, pingInterval: 0.3))
        port = try await server.start()
    }

    override func tearDown() {
        server.stop()
    }

    func testHelloObsOptionsAndNotFound() async throws {
        let (hello, r1) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/hello")!)
        let helloText = String(decoding: hello, as: UTF8.self)
        let helloJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: hello) as? [String: String])
        XCTAssertEqual(helloJSON["app"], "nino")
        // Sahadaki eski TV uygulaması taramada cevabın içinde eski adı arar (yalnız alt dizge denetimi).
        XCTAssertTrue(helloText.contains(LegacyCompatName.lowercased))
        XCTAssertFalse(LegacyCompatName.lowercased.isEmpty)
        XCTAssertEqual((r1 as? HTTPURLResponse)?.value(forHTTPHeaderField: "Access-Control-Allow-Origin"), "*")
        let (obs, r2) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/obs?size=60&bg=green")!)
        XCTAssertEqual((r2 as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue((r2 as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/html") == true)
        let page = String(decoding: obs, as: UTF8.self)
        XCTAssertTrue(page.contains("/events?viewer=obs"))
        XCTAssertTrue(page.contains("textContent"))
        XCTAssertFalse(page.contains("innerHTML"))
        var opt = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/events")!)
        opt.httpMethod = "OPTIONS"
        let (_, r3) = try await URLSession.shared.data(for: opt)
        XCTAssertEqual((r3 as? HTTPURLResponse)?.statusCode, 204)
        let (_, r4) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/speech/1.wav")!)
        XCTAssertEqual((r4 as? HTTPURLResponse)?.statusCode, 404)
    }

    func testStreamRetryReplayEventsAndPing() async throws {
        try await server.send(.style(NinoStyle(fontSize: 58)))
        try await server.send(.started)
        let tv = FakeLegacyTV(port: port, query: "?model=LG%20OLED55%3Cx%3E&app=3.2.1")
        defer { tv.close() }
        try await waitUntil { tv.names() == ["style", "started"] }
        XCTAssertEqual(tv.lines.values.first, "retry: 2000")
        XCTAssertEqual(tv.data(of: "style")?["fontSize"] as? Int, 58)
        try await waitUntil { self.server.connectedTVs.count == 1 }
        XCTAssertEqual(server.connectedTVs.first?.model, "LG OLED55x")
        XCTAssertEqual(server.connectedTVs.first?.appVersion, "3.2.1")

        try await server.show(ShowPayload(id: 1, text: "Buraya gel.", box: NinoBox(left: 0.1, top: 0.8, right: 0.9, bottom: 0.9)))
        try await server.clear(id: 2) // başka altyazı: yollanmaz
        try await server.clear(id: 1)
        try await server.send(.screen(ScreenPayload(items: [], durationMs: 5000)))
        try await server.send(.stopped)
        try await waitUntil { tv.names() == ["style", "started", "subtitle", "clear", "screen", "stopped"] }
        XCTAssertEqual(tv.data(of: "subtitle")?["text"] as? String, "Buraya gel.")
        XCTAssertEqual(tv.data(of: "subtitle")?["duration"] as? Int, 15000)
        XCTAssertEqual(tv.data(of: "screen")?["duration"] as? Int, 5000)
        try await waitUntil { tv.lines.values.contains(": ping") && tv.events.contains { $0.name == "ping" && $0.data == "{}" } }
    }

    func testOBSIsNotATVAndComputerOnlyFiltersSubtitles() async throws {
        let changes = Recorder<[LegacyEventServer.Viewer]>()
        server.onViewersChange = { changes.append($0) }
        server.subtitlesOnTV = false
        let tv = FakeLegacyTV(port: port)
        let obs = FakeLegacyTV(port: port, query: "?viewer=obs")
        defer { tv.close(); obs.close() }
        try await waitUntil { self.server.viewers.count == 2 }
        XCTAssertEqual(server.connectedTVs.count, 1)

        try await server.send(.started)
        try await server.show(ShowPayload(id: 1, text: "Yalnız bilgisayarda"))
        try await server.send(.region(RegionPayload(id: "a", text: "b")))
        try await server.send(.stopped)
        try await waitUntil { obs.names() == ["started", "subtitle", "region", "stopped"] }
        try await waitUntil { tv.names() == ["started", "stopped"] }

        tv.close()
        try await waitUntil { self.server.connectedTVs.isEmpty }
        XCTAssertEqual(server.viewers.count, 1)
        XCTAssertTrue(changes.values.contains { $0.count == 2 })
    }

    func testStartedNotReplayedAfterWindowOrToOBS() async throws {
        server.stop()
        server = LegacyEventServer(options: .init(port: 0, startedReplayWindow: 0.2))
        port = try await server.start()
        try await server.send(.started)
        let obs = FakeLegacyTV(port: port, query: "?viewer=obs")
        defer { obs.close() }
        try await waitUntil { obs.lines.values.first == "retry: 2000" }
        try await Task.sleep(for: .milliseconds(300))
        let late = FakeLegacyTV(port: port)
        defer { late.close() }
        try await waitUntil { late.lines.values.first == "retry: 2000" }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(obs.names(), [])
        XCTAssertEqual(late.names(), [])
    }

    func testBusyPortFallsBackToRandom() async throws {
        // Rastgele bir portu kendimiz tutuyoruz; 8787'ye hiç dokunmuyoruz.
        let blocker = LegacyEventServer(options: .init(port: 0))
        let busy = try await blocker.start()
        defer { blocker.stop() }
        let second = LegacyEventServer(options: .init(port: busy, portAttempts: 2, portRetryDelay: 0.05))
        let got = try await second.start()
        defer { second.stop() }
        XCTAssertNotEqual(got, busy)
        let strict = LegacyEventServer(options: .init(port: busy, portAttempts: 1, randomPortFallback: false))
        do {
            _ = try await strict.start()
            strict.stop()
            XCTFail("dolu port hata vermeliydi")
        } catch {}
    }

    func testHubDrivesLegacyToo() async throws {
        let hub = DisplayHub()
        await hub.add(server, key: "legacy")
        let tv = FakeLegacyTV(port: port)
        defer { tv.close() }
        try await waitUntil { self.server.connectedTVs.count == 1 }
        try await hub.send(.style(NinoStyle(theme: "glass")))
        try await hub.show(ShowPayload(id: 3, text: "Hub'dan"))
        try await waitUntil { tv.names() == ["style", "subtitle"] }
    }
}
