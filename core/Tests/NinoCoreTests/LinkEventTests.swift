// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Darwin
import Foundation
import XCTest
@testable import NinoCore

/// `/events`'e bağlanıp hiç okumayan ham soket (sessizce ölmüş TV gibi): alma tamponu küçük, kapanmaz.
final class SilentSSEClient {
    let fd: Int32

    init(port: UInt16) throws {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EBADF) }
        var small: Int32 = 2048
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &small, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard r == 0 else { Darwin.close(fd); throw POSIXError(.ECONNREFUSED) }
        let request = "GET /events?model=Samsung%20QE55&app=4.0.3 HTTP/1.1\r\nHost: 127.0.0.1\r\nAccept: text/event-stream\r\n\r\n"
        _ = request.withCString { write(fd, $0, strlen($0)) }
    }

    func close() { Darwin.close(fd) }
}

final class LinkEventTests: XCTestCase {
    private func big(_ id: Int) -> ShowPayload {
        // Kapak alanı büyük: tamponları hızla doldurur.
        ShowPayload(id: id, text: "Satır \(id)", durationMs: 3000, cover: String(repeating: "QUJD", count: 4000))
    }

    /// Bağlandı → TV kapattı: tek "bağlandı", tek "koptu" (karşı kapattı), süre ve model/sürüm dolu.
    func testLegacyConnectAndPeerClose() async throws {
        let server = LegacyEventServer(options: .init(port: 0, randomPortFallback: false))
        let events = Recorder<DisplayLinkEvent>()
        server.onLinkEvent = { events.append($0) }
        let port = try await server.start()
        defer { server.stop() }
        let tv = FakeLegacyTV(port: port, query: "?model=Samsung%20QE55&app=4.0.3")
        try await waitUntil { events.values.count == 1 }
        let c = try XCTUnwrap(events.values.first)
        XCTAssertEqual(c.kind, .connected)
        XCTAssertEqual(c.route, .legacySSE)
        XCTAssertEqual(c.host, "127.0.0.1")
        XCTAssertEqual(c.model, "Samsung QE55")
        XCTAssertEqual(c.appVersion, "4.0.3")
        tv.close()
        try await waitUntil { events.values.count == 2 }
        let d = events.values[1]
        XCTAssertEqual(d.kind, .disconnected)
        XCTAssertTrue(d.reason == .peerClosed || d.reason == .readFailed, "\(String(describing: d.reason))")
        XCTAssertEqual(d.connectionID, c.connectionID)
        XCTAssertNotNil(d.duration)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(events.values.count, 2, "kopma bir kez")
        XCTAssertTrue(server.connectedTVs.isEmpty)
    }

    /// Okumayı bırakan TV: yazmalar birikir → zaman aşımıyla düşürülür; aynı adresten yeni TV bağlanır, altyazı alır.
    func testSilentlyDeadViewerIsDroppedAndSameAddressReconnects() async throws {
        let server = LegacyEventServer(options: .init(port: 0, randomPortFallback: false, pingInterval: 0.1,
                                                      writeTimeout: 0.3, maxPendingBytes: 4 * 1024 * 1024))
        let events = Recorder<DisplayLinkEvent>()
        server.onLinkEvent = { events.append($0) }
        let port = try await server.start()
        defer { server.stop() }
        let dead = try SilentSSEClient(port: port)
        defer { dead.close() }
        try await waitUntil { server.connectedTVs.count == 1 }
        // Kalp atışı + altyazı yağmuru: tampon dolunca gönderim asılı kalır.
        var id = 0
        let end = Date().addingTimeInterval(8)
        while Date() < end, !events.values.contains(where: { $0.kind != .connected }) {
            for _ in 0..<20 {
                id += 1
                try await server.show(big(id))
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let drop = try XCTUnwrap(events.values.first { $0.kind != .connected }, "ölü izleyici düşürülmedi")
        XCTAssertEqual(drop.kind, .timedOut)
        XCTAssertEqual(drop.reason, .writeStalled)
        XCTAssertTrue(server.connectedTVs.isEmpty, "kaynak bırakıldı")

        let tv = FakeLegacyTV(port: port)
        defer { tv.close() }
        try await waitUntil { server.connectedTVs.count == 1 }
        try await server.show(ShowPayload(id: 999_999, text: "Yeniden geldim", durationMs: 2000))
        try await waitUntil { tv.data(of: "subtitle")?["text"] as? String == "Yeniden geldim" }
        XCTAssertEqual(events.values.filter { $0.kind == .connected }.count, 2)
    }

    /// Kapanışı bize ulaşmamış eski akış, aynı adresten gelen yeni TV'yi engellemez: eski "değiştirildi" ile düşer.
    func testNewStreamFromSameAddressReplacesStaleOne() async throws {
        let server = LegacyEventServer(options: .init(port: 0, randomPortFallback: false))
        let events = Recorder<DisplayLinkEvent>()
        server.onLinkEvent = { events.append($0) }
        let port = try await server.start()
        defer { server.stop() }
        let stale = try SilentSSEClient(port: port)
        defer { stale.close() }
        try await waitUntil { server.connectedTVs.count == 1 }
        let obs = FakeLegacyTV(port: port, query: "?viewer=obs")
        defer { obs.close() }
        try await waitUntil { server.viewers.contains(where: \.isOBS) }
        let tv = FakeLegacyTV(port: port)
        defer { tv.close() }
        try await waitUntil { events.values.contains { $0.reason == .replaced } }
        try await waitUntil { server.connectedTVs.count == 1 }
        XCTAssertEqual(server.viewers.filter(\.isOBS).count, 1, "OBS yerinden edilmez")
        try await server.show(ShowPayload(id: 1, text: "Merhaba yine", durationMs: 2000))
        try await waitUntil { tv.data(of: "subtitle")?["text"] as? String == "Merhaba yine" }
        XCTAssertEqual(events.values.first { $0.reason == .replaced }?.kind, .disconnected)
    }

    /// Aynı adresten art arda yeni akış (iki istemci birbirini kovalıyor): ilk yerine geçmeden sonra 5 sn içinde
    /// gelen üçüncü akış sessizce geri çevrilir, ikinci akış kalır ve altyazı alır; tek "replaced" olayı.
    func testRepeatedNewStreamsWithinCooldownKeepTheHealthyOne() async throws {
        let server = LegacyEventServer(options: .init(port: 0, randomPortFallback: false))
        let events = Recorder<DisplayLinkEvent>()
        server.onLinkEvent = { events.append($0) }
        let port = try await server.start()
        defer { server.stop() }
        let first = FakeLegacyTV(port: port)
        defer { first.close() }
        try await waitUntil { server.connectedTVs.count == 1 }
        let second = FakeLegacyTV(port: port)
        defer { second.close() }
        try await waitUntil { events.values.contains { $0.reason == .replaced } }
        let third = FakeLegacyTV(port: port)
        defer { third.close() }
        try await Task.sleep(nanoseconds: 300_000_000)
        try await waitUntil { server.connectedTVs.count == 1 }
        try await server.show(ShowPayload(id: 2, text: "Sağlam akış", durationMs: 2000))
        try await waitUntil { second.data(of: "subtitle")?["text"] as? String == "Sağlam akış" }
        XCTAssertNil(third.data(of: "subtitle"), "geri çevrilen akış altyazı almaz")
        XCTAssertEqual(events.values.filter { $0.reason == .replaced }.count, 1)
        XCTAssertEqual(events.values.filter { $0.kind == .connected }.count, 2)
    }

    func testKernelTimeoutCountsAsStalledWrite() {
        XCTAssertEqual(LegacyEventServer.reason(for: .posix(.ETIMEDOUT)), .writeStalled)
        XCTAssertEqual(LegacyEventServer.reason(for: .posix(.ECONNRESET)), .readFailed)
        XCTAssertEqual(LegacyEventServer.Options().connectionDropTime, 25)
    }

    /// Sunucu durunca her TV için "sunucu durdu".
    func testLegacyStopEmitsServerStopped() async throws {
        let server = LegacyEventServer(options: .init(port: 0, randomPortFallback: false))
        let events = Recorder<DisplayLinkEvent>()
        server.onLinkEvent = { events.append($0) }
        let port = try await server.start()
        let tv = FakeLegacyTV(port: port)
        defer { tv.close() }
        try await waitUntil { server.connectedTVs.count == 1 }
        server.stop()
        XCTAssertEqual(events.values.last?.reason, .serverStopped)
        XCTAssertEqual(events.values.filter { $0.kind != .connected }.count, 1)
    }

    /// 47800 girişi: el sıkışınca "bağlandı" (model/sürüm welcome'dan), susan TV "kalp atışı zaman aşımı".
    func testIngressConnectAndHeartbeatTimeout() async throws {
        let ingress = NinoSenderIngress(options: .init(name: "Mac", port: 0, pingInterval: 0.1, silenceTimeout: 0.4))
        let events = Recorder<DisplayLinkEvent>()
        ingress.onLinkEvent = { events.append($0) }
        let port = try await ingress.start()
        defer { ingress.stop() }
        let tv = FakeWebTV(port: port)
        defer { tv.close() }
        try await tv.handshake(extra: #","model":"QE55Q80C","appVersion":"4.0.3""#)
        try await waitUntil { events.values.count == 1 }
        XCTAssertEqual(events.values[0].kind, .connected)
        XCTAssertEqual(events.values[0].route, .ingress)
        XCTAssertEqual(events.values[0].model, "QE55Q80C")
        XCTAssertEqual(events.values[0].appVersion, "4.0.3")
        try await waitUntil { events.values.count >= 2 }
        XCTAssertEqual(events.values[1].kind, .timedOut)
        XCTAssertEqual(events.values[1].reason, .heartbeatTimeout)
    }

    /// Giden bağlantı: bağlandı, TV kapanınca koptu; elle kopunca "bu taraf kapattı".
    func testOutgoingSenderEvents() async throws {
        let display = NinoDisplayServer(options: .init(name: "Deneme TV", port: 0, advertise: false))
        let port = try await display.start()
        let sender = NinoSender(host: "127.0.0.1", port: port)
        let events = Recorder<DisplayLinkEvent>()
        await sender.setLinkEventHandler { events.append($0) }
        try await sender.connect()
        XCTAssertEqual(events.values.map(\.kind), [.connected])
        XCTAssertEqual(events.values[0].route, .outgoing)
        display.stop()
        try await waitUntil { events.values.count == 2 }
        XCTAssertEqual(events.values[1].kind, .disconnected)
        XCTAssertNotNil(events.values[1].reason)
        XCTAssertFalse(events.values[1].reason?.isLocal ?? true)

        let again = NinoDisplayServer(options: .init(name: "Deneme TV", port: 0, advertise: false))
        let p2 = try await again.start()
        defer { again.stop() }
        let s2 = NinoSender(host: "127.0.0.1", port: p2)
        let e2 = Recorder<DisplayLinkEvent>()
        await s2.setLinkEventHandler { e2.append($0) }
        try await s2.connect()
        await s2.disconnect()
        XCTAssertEqual(e2.values.map(\.reason), [nil, .localClose])
    }
}
