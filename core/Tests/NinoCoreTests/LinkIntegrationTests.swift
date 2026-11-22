// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Network
import XCTest
@testable import NinoCore

/// Gerçek soketlerle, yalnız bu makinede (127.0.0.1) uçtan uca deneme.
final class LinkIntegrationTests: XCTestCase {
    private var server: NinoDisplayServer!
    private var port: UInt16 = 0
    private let changes = Recorder<ShowPayload?>()

    override func setUp() async throws {
        server = NinoDisplayServer(options: .init(name: "Deneme TV", id: "deneme-1", port: 0, advertise: false,
                                                  handshakeTimeout: 0.5, idleTimeout: 1.5))
        let changes = self.changes
        server.onChange = { changes.append($0) }
        port = try await server.start()
    }

    override func tearDown() {
        server.stop()
    }

    func testHandshakeShowClear() async throws {
        let sender = NinoSender(host: "127.0.0.1", port: port, device: "Mac", client: "nino-test")
        let name = try await sender.connect()
        XCTAssertEqual(name, "Deneme TV")

        let p = ShowPayload(id: 1, text: "Buraya gel.", source: "Come here.")
        try await sender.show(p)
        try await waitUntil { self.server.current == p }

        try await sender.clear(id: 99)
        try await sender.ping()
        XCTAssertEqual(server.current, p, "farklı id'li clear silmez")

        try await sender.clear(id: 1)
        try await waitUntil { self.server.current == nil }
        XCTAssertEqual(changes.values, [p, nil])
        let rtt = try await sender.ping()
        XCTAssertLessThan(rtt, 2)
        await sender.disconnect()
    }

    func testVersionMismatch() async {
        let sender = NinoSender(host: "127.0.0.1", port: port, versions: [7])
        do {
            try await sender.connect()
            XCTFail("hata bekleniyordu")
        } catch {
            XCTAssertEqual(error as? NinoSender.SenderError, .versionUnsupported(theirs: [1]))
        }
    }

    func testNewSenderReplacesOld() async throws {
        let first = NinoSender(host: "127.0.0.1", port: port)
        try await first.connect()
        let second = NinoSender(host: "127.0.0.1", port: port)
        try await second.connect()
        try await waitUntil { await first.state == .disconnected }
        let err = await first.lastError
        if case let .error(code, _, _)? = err { XCTAssertEqual(code, "replaced") }
        try await second.show(ShowPayload(id: 5, text: "İkinci"))
        try await waitUntil { self.server.current?.id == 5 }
        await second.disconnect()
    }

    func testIdleClearsScreen() async throws {
        let sender = NinoSender(host: "127.0.0.1", port: port)
        try await sender.connect()
        try await sender.show(ShowPayload(id: 1, text: "Selam"))
        try await waitUntil { self.server.current != nil }
        try await waitUntil(timeout: 4) { self.server.current == nil }
        await sender.disconnect()
    }

    func testDurationAutoClears() async throws {
        try await NinoHTTPClient.show(ShowPayload(id: 3, text: "Kısa", durationMs: 200), host: "127.0.0.1", port: port)
        XCTAssertEqual(server.current?.id, 3)
        try await waitUntil { self.server.current == nil }
    }

    func testHTTPInfoShowClear() async throws {
        let info = try await NinoHTTPClient.info(host: "127.0.0.1", port: port)
        XCTAssertEqual(info, .info(version: 1, versions: [1], name: "Deneme TV", id: "deneme-1"))
        try await NinoHTTPClient.show(ShowPayload(id: 9, text: "HTTP ile"), host: "127.0.0.1", port: port)
        XCTAssertEqual(server.current?.text, "HTTP ile")
        try await NinoHTTPClient.clear(id: nil, host: "127.0.0.1", port: port)
        XCTAssertNil(server.current)
    }

    func testHTTPErrors() async throws {
        var r = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/nino/show")!)
        r.httpMethod = "POST"
        r.httpBody = Data(#"{"app":"nino","type":"clear"}"#.utf8)
        let (_, bad) = try await URLSession.shared.data(for: r)
        XCTAssertEqual((bad as? HTTPURLResponse)?.statusCode, 400)
        let (_, missing) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/yok")!)
        XCTAssertEqual((missing as? HTTPURLResponse)?.statusCode, 404)
    }

    func testHandshakeTimeoutClosesSilentClient() async throws {
        let task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/nino/ws")!)
        task.resume()
        let started = Date()
        do {
            _ = try await task.receive()
            XCTFail("bağlantı kapanmalıydı")
        } catch {
            XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        }
    }

    /// Yerel ağa kısa süre "Nino Deneme" yayınlar; yalnız NINO_BONJOUR_TESTS=1 ise çalışır.
    func testBonjourAdvertiseBrowseResolve() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NINO_BONJOUR_TESTS"] == "1", "NINO_BONJOUR_TESTS=1 ile çalışır")
        let id = "bonjour-\(UUID().uuidString.prefix(8).lowercased())"
        let tv = NinoDisplayServer(options: .init(name: "Nino Deneme \(id)", id: id, port: 0, advertise: true))
        let tvPort = try await tv.start()
        defer { tv.stop() }

        let browser = NinoBrowser()
        defer { browser.stop() }
        let found: DiscoveredDisplay? = try await withTimeout(.seconds(10)) {
            for await list in browser.displays() {
                if let d = list.first(where: { $0.id == id }) { return d }
            }
            return nil
        }
        let display = try XCTUnwrap(found)
        XCTAssertEqual(display.version, 1)
        let (host, resolvedPort) = try await NinoBrowser.resolve(display.endpoint)
        XCTAssertEqual(resolvedPort, tvPort)
        let info = try await NinoHTTPClient.info(host: host, port: resolvedPort)
        if case let .info(_, _, _, gotID) = info { XCTAssertEqual(gotID, id) } else { XCTFail() }
    }
}

final class ReconnectTests: XCTestCase {
    func testKeepAliveReconnectsAndResendsLastShown() async throws {
        let first = NinoDisplayServer(options: .init(name: "TV", port: 0, advertise: false))
        let port = try await first.start()
        let sender = NinoSender(host: "127.0.0.1", port: port)
        try await sender.connect()
        let p = ShowPayload(id: 7, text: "Hâlâ burada")
        try await sender.show(p)
        try await waitUntil { first.current == p }
        await sender.startKeepAlive(interval: 0.1, pongTimeout: 0.3, backoff: ReconnectBackoff(initial: 0.1, maximum: 0.2))

        first.stop()
        try await waitUntil { await sender.state == .disconnected }
        let second = NinoDisplayServer(options: .init(name: "TV 2", port: port, advertise: false))
        _ = try await second.start()
        defer { second.stop() }

        try await waitUntil(timeout: 5) { second.current == p }
        let state = await sender.state
        XCTAssertEqual(state, .connected(version: 1, displayName: "TV 2"))
        await sender.disconnect()
    }

    func testPickDisplayPrefersLastThenFallsBack() async {
        let a = DiscoveredDisplay.parse(name: "A", txt: ["id": "a", "v": "1"], endpoint: NWEndpointStub.endpoint)
        let b = DiscoveredDisplay.parse(name: "B", txt: ["id": "b", "v": "1"], endpoint: NWEndpointStub.endpoint)
        let old = DiscoveredDisplay.parse(name: "C", txt: ["id": "c", "v": "9"], endpoint: NWEndpointStub.endpoint)

        func stream(_ lists: [[DiscoveredDisplay]], finish: Bool) -> AsyncStream<[DiscoveredDisplay]> {
            AsyncStream { c in
                for l in lists { c.yield(l) }
                if finish { c.finish() }
            }
        }
        let last = await NinoSetup.pickDisplay(stream([[a], [a, b]], finish: false), lastID: "b", timeout: 1)
        XCTAssertEqual(last?.id, "b")
        let fallback = await NinoSetup.pickDisplay(stream([[old, a]], finish: false), lastID: "zz", timeout: 0.2)
        XCTAssertEqual(fallback?.id, "a")
        let none = await NinoSetup.pickDisplay(stream([[old]], finish: true), lastID: nil, timeout: 0.2)
        XCTAssertNil(none)
    }
}

final class Recorder<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func append(_ v: T) { lock.withLock { items.append(v) } }
    var values: [T] { lock.withLock { items } }
}

func waitUntil(timeout: TimeInterval = 3, _ condition: @escaping () async -> Bool) async throws {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    XCTFail("koşul \(timeout) sn içinde sağlanmadı")
}
