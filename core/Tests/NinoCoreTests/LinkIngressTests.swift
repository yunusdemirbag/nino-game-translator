// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import XCTest
@testable import NinoCore

/// Web TV gibi davranan deneme istemcisi: göndericiye bağlanır, `hello`'ya `welcome` döner.
final class FakeWebTV: @unchecked Sendable {
    let task: URLSessionWebSocketTask

    init(port: UInt16) {
        task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/nino/ws")!)
        task.maximumMessageSize = NinoLink.maxMessageBytes
        task.resume()
    }

    func receiveText(timeout: TimeInterval = 3) async throws -> String {
        let m = try await withTimeout(.seconds(timeout)) { try await self.task.receive() }
        guard case let .string(s) = m else { throw URLError(.cannotDecodeContentData) }
        return s
    }

    /// `hello`'yu bekler, `welcome` döner.
    @discardableResult
    func handshake(name: String = "Salon LG", extra: String = "") async throws -> NinoMessage {
        let hello = try NinoMessage(string: try await receiveText())
        try await sendText(#"{"app":"nino","type":"welcome","version":1,"name":"\#(name)"\#(extra)}"#)
        return hello
    }

    func sendText(_ s: String) async throws { try await task.send(.string(s)) }

    /// Sıradaki ping olmayan mesaj.
    func next() async throws -> String {
        while true {
            let s = try await receiveText()
            if case let .ping(t)? = try? NinoMessage(string: s) {
                try await sendText(NinoMessage.pong(t: t).jsonString)
                continue
            }
            return s
        }
    }

    func close() { task.cancel(with: .normalClosure, reason: nil) }
}

final class LinkIngressTests: XCTestCase {
    private var ingress: NinoSenderIngress!
    private var port: UInt16 = 0

    override func setUp() async throws {
        ingress = NinoSenderIngress(options: .init(name: "Mac", id: "mac-1", port: 0, device: "Mac", client: "nino-test/1",
                                                   appVersion: "4.0.0", handshakeTimeout: 0.5))
        port = try await ingress.start()
    }

    override func tearDown() {
        ingress.stop()
    }

    func testInfoHasSenderRoleAndCORS() async throws {
        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/nino/info")!)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Access-Control-Allow-Origin"), "*")
        let info = try NinoInfo(data: data)
        XCTAssertEqual(info, NinoInfo(name: "Mac", id: "mac-1", appVersion: "4.0.0", role: "sender"))
        let fetched = try await NinoInfo.fetch(host: "127.0.0.1", port: port)
        XCTAssertTrue(fetched.isSender)

        var options = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/nino/info")!)
        options.httpMethod = "OPTIONS"
        let (_, pre) = try await URLSession.shared.data(for: options)
        XCTAssertEqual((pre as? HTTPURLResponse)?.statusCode, 204)
        XCTAssertEqual((pre as? HTTPURLResponse)?.value(forHTTPHeaderField: "Access-Control-Allow-Origin"), "*")
        let (_, missing) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/yok")!)
        XCTAssertEqual((missing as? HTTPURLResponse)?.statusCode, 404)
    }

    func testSenderSpeaksFirstThenShowsToAllTVs() async throws {
        let changes = Recorder<[NinoSenderIngress.Display]>()
        ingress.onDisplaysChange = { changes.append($0) }
        let a = FakeWebTV(port: port)
        let hello = try await a.handshake(name: "Salon LG", extra: #","model":"LG OLED55","appVersion":"4.1.0","id":"tv-salon""#)
        XCTAssertEqual(hello, .hello(version: 1, device: "Mac", client: "nino-test/1"))
        let b = FakeWebTV(port: port)
        try await b.handshake(name: "Yatak Samsung", extra: #","id":"tv-yatak""#)
        try await waitUntil { self.ingress.displays.count == 2 }
        let first = try XCTUnwrap(ingress.displays.first)
        XCTAssertEqual(first.name, "Salon LG")
        XCTAssertEqual(first.model, "LG OLED55")
        XCTAssertEqual(first.appVersion, "4.1.0")
        XCTAssertEqual(first.host, "127.0.0.1")

        let p = ShowPayload(id: 4, text: "Buraya gel.", box: NinoBox(left: 0.1, top: 0.8, right: 0.9, bottom: 0.9))
        try await ingress.show(p)
        try await ingress.send(.region(RegionPayload(id: "map", text: "Köprü")))
        for tv in [a, b] {
            let got1 = try await tv.next()
            XCTAssertEqual(try NinoMessage(string: got1), .show(p))
            let got2 = try await tv.next()
            XCTAssertEqual(try NinoEvent(string: got2), .region(RegionPayload(id: "map", text: "Köprü")))
        }
        a.close()
        try await waitUntil { self.ingress.displays.count == 1 }
        XCTAssertEqual(ingress.displays.first?.name, "Yatak Samsung")
        XCTAssertEqual(changes.values.last?.count, 1)
        b.close()
    }

    /// Aynı TV (aynı `id`) yeniden bağlanınca eskisi `error/replaced` alıp kapanır, altyazı yenisine gider.
    func testSameTVReconnectReplacesOldConnection() async throws {
        let events = Recorder<DisplayLinkEvent>()
        ingress.onLinkEvent = { events.append($0) }
        let old = FakeWebTV(port: port)
        try await old.handshake(extra: #","id":"tv-1""#)
        try await waitUntil { self.ingress.displays.count == 1 }
        let fresh = FakeWebTV(port: port)
        try await fresh.handshake(extra: #","id":"tv-1""#)

        let got = try await old.next()
        XCTAssertEqual(got, #"{"app":"nino","code":"replaced","type":"error"}"#)
        XCTAssertEqual(try NinoMessage(string: got), .error(code: "replaced", message: nil, versions: nil))
        do {
            _ = try await old.receiveText(timeout: 2)
            XCTFail("eski bağlantı kapanmalıydı")
        } catch {}

        try await waitUntil { self.ingress.displays.count == 1 && events.values.count == 3 }
        XCTAssertEqual(ingress.displays.first?.tvID, "tv-1")
        XCTAssertEqual(events.values.map(\.kind), [.connected, .disconnected, .connected])
        XCTAssertEqual(events.values[1].reason, .replaced)
        XCTAssertEqual(events.values[1].connectionID, events.values[0].connectionID)

        let p = ShowPayload(id: 7, text: "Yeni bağlantı")
        try await ingress.show(p)
        let shown = try await fresh.next()
        XCTAssertEqual(try NinoMessage(string: shown), .show(p))
        fresh.close()
        try await waitUntil { self.ingress.displays.isEmpty }
        XCTAssertEqual(events.values.filter { $0.reason == .replaced }.count, 1)
    }

    /// İki istemci aynı kimlikle birbirini kovalarsa (saniyede bir yeniden bağlanma) döngü kırılır:
    /// ilk yerine geçmeden sonra 5 sn içinde gelen yeni bağlantı `duplicate` ile geri çevrilir, sağlam olan kalır.
    func testRepeatedReplaceWithinCooldownRejectsNewcomer() async throws {
        let events = Recorder<DisplayLinkEvent>()
        ingress.onLinkEvent = { events.append($0) }
        let a = FakeWebTV(port: port)
        try await a.handshake(extra: #","id":"tv-loop""#)
        try await waitUntil { self.ingress.displays.count == 1 }
        let b = FakeWebTV(port: port)
        try await b.handshake(extra: #","id":"tv-loop""#)
        let first = try await a.next()
        XCTAssertEqual(try NinoMessage(string: first), .error(code: NinoLink.ErrorCode.replaced, message: nil, versions: nil))

        // Hemen ardından üçüncü bağlantı: b kalmalı, c geri çevrilmeli.
        let c = FakeWebTV(port: port)
        try await c.handshake(extra: #","id":"tv-loop""#)
        let rejected = try await c.next()
        XCTAssertEqual(try NinoMessage(string: rejected), .error(code: NinoLink.ErrorCode.duplicate, message: nil, versions: nil))

        try await waitUntil { self.ingress.displays.count == 1 }
        let p = ShowPayload(id: 9, text: "Sağlam bağlantı")
        try await ingress.show(p)
        let shown = try await b.next()
        XCTAssertEqual(try NinoMessage(string: shown), .show(p))
        // Geri çevrilen bağlantı için kopma olayı yok: yalnız a'nın replaced'i var.
        XCTAssertEqual(events.values.filter { $0.kind == .disconnected }.count, 1)
        b.close()
        try await waitUntil { self.ingress.displays.isEmpty }
    }

    /// Kimlik yoksa aynı uzak adres aynı TV sayılır.
    func testSameAddressWithoutIDReplaces() async throws {
        let old = FakeWebTV(port: port)
        try await old.handshake()
        let fresh = FakeWebTV(port: port)
        try await fresh.handshake()
        let got = try await old.next()
        XCTAssertEqual(try NinoMessage(string: got), .error(code: NinoLink.ErrorCode.replaced, message: nil, versions: nil))
        try await waitUntil { self.ingress.displays.count == 1 }
        fresh.close()
    }

    /// Farklı kimlikli iki TV (aynı adresten bile) birlikte kalır, ikisi de altyazı alır.
    func testDifferentTVsStayTogether() async throws {
        let a = FakeWebTV(port: port)
        try await a.handshake(name: "Salon", extra: #","id":"tv-a""#)
        let b = FakeWebTV(port: port)
        try await b.handshake(name: "Yatak", extra: #","id":"tv-b""#)
        try await waitUntil { self.ingress.displays.count == 2 }
        let p = ShowPayload(id: 3, text: "İkisine de")
        try await ingress.show(p)
        for tv in [a, b] {
            let got = try await tv.next()
            XCTAssertEqual(try NinoMessage(string: got), .show(p))
        }
        XCTAssertEqual(ingress.displays.count, 2)
        a.close()
        b.close()
    }

    func testNewTVGetsStyleStartedAndCurrentSubtitle() async throws {
        let style = NinoStyle(fontSize: 58, theme: "cinema")
        try await ingress.send(.style(style))
        try await ingress.send(.started)
        let p = ShowPayload(id: 9, text: "Hâlâ ekranda")
        try await ingress.show(p)
        let tv = FakeWebTV(port: port)
        try await tv.handshake()
        let got3 = try await tv.next()
        XCTAssertEqual(try NinoEvent(string: got3), .style(style))
        let got4 = try await tv.next()
        XCTAssertEqual(try NinoEvent(string: got4), .started)
        let got5 = try await tv.next()
        XCTAssertEqual(try NinoMessage(string: got5), .show(p))
        tv.close()
    }

    func testTVPingGetsPongAndSilentTVIsDropped() async throws {
        ingress.stop()
        ingress = NinoSenderIngress(options: .init(name: "Mac", port: 0, pingInterval: 0.1, silenceTimeout: 0.5))
        port = try await ingress.start()
        let tv = FakeWebTV(port: port)
        try await tv.handshake()
        try await tv.sendText(NinoMessage.ping(t: 77).jsonString)
        var sawPing = false
        var sawPong = false
        while !(sawPing && sawPong) {
            let m = try NinoMessage(string: try await tv.receiveText())
            if case .ping = m { sawPing = true }
            if m == .pong(t: 77) { sawPong = true }
        }
        // Artık pong yollamıyoruz: gönderici kapatmalı.
        try await waitUntil(timeout: 3) { self.ingress.displays.isEmpty }
        tv.close()
    }

    func testNoWelcomeClosesAndBadFirstMessageCloses() async throws {
        let silent = FakeWebTV(port: port)
        _ = try await silent.receiveText() // hello
        let started = Date()
        do {
            while true { _ = try await silent.receiveText() }
        } catch {
            XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        }
        let rude = FakeWebTV(port: port)
        _ = try await rude.receiveText()
        try await rude.sendText(NinoMessage.show(ShowPayload(id: 1, text: "x")).jsonString)
        do {
            while true { _ = try await rude.receiveText() }
        } catch {}
        XCTAssertTrue(ingress.displays.isEmpty)
    }

    func testComputerOnlyRoutesSubtitlesToLegacyOBSOnly() async throws {
        let legacy = LegacyEventServer(options: .init(port: 0))
        let legacyPort = try await legacy.start()
        defer { legacy.stop() }
        let hub = DisplayHub()
        await hub.add(ingress, key: "web")
        await hub.add(legacy, key: "legacy")
        let web = FakeWebTV(port: port)
        try await web.handshake()
        let oldTV = FakeLegacyTV(port: legacyPort)
        let obs = FakeLegacyTV(port: legacyPort, query: "?viewer=obs")
        defer { oldTV.close(); obs.close() }
        try await waitUntil { self.ingress.displays.count == 1 && legacy.viewers.count == 2 }

        await hub.setSubtitlesOnTV(false)
        XCTAssertFalse(legacy.subtitlesOnTV)
        // Kapatınca TV temizlenir.
        let c1 = try await web.next()
        XCTAssertEqual(try NinoMessage(string: c1), .clear(id: nil))
        _ = try await web.next() // screen-clear
        _ = try await web.next() // region-clear
        try await hub.send(.started)
        try await hub.show(ShowPayload(id: 1, text: "Yalnız bilgisayarda"))
        try await hub.send(.style(NinoStyle(bold: true)))
        let s1 = try await web.next()
        XCTAssertEqual(try NinoEvent(string: s1), .started, "altyazı web TV'ye gitmemeli")
        try await waitUntil { obs.names() == ["started", "subtitle", "style"] }
        try await waitUntil { oldTV.names() == ["started"] }

        await hub.setSubtitlesOnTV(true)
        let s2 = try await web.next()
        XCTAssertEqual(try NinoEvent(string: s2), .style(NinoStyle(bold: true)))
        let s3 = try await web.next()
        XCTAssertEqual(try NinoMessage(string: s3), .show(ShowPayload(id: 1, text: "Yalnız bilgisayarda")))
        web.close()
    }

    func testStartedIsNotReplayedOutsideWindow() {
        var r = DisplayReplay()
        r.record(.started, now: Date().addingTimeInterval(-30))
        r.record(.style(NinoStyle(fontSize: 40)))
        XCTAssertEqual(r.messages(), [NinoEvent.style(NinoStyle(fontSize: 40)).jsonString])
        r.record(.started)
        XCTAssertEqual(r.messages().count, 2)
        XCTAssertEqual(r.messages(subtitles: false), [NinoEvent.started.jsonString])
    }

    func testSecondIngressOnSamePortFails() async throws {
        let twin = NinoSenderIngress(options: .init(name: "İkinci", port: port, portAttempts: 2, portRetryDelay: 0.05))
        do {
            _ = try await twin.start()
            twin.stop()
            XCTFail("dolu port hata vermeliydi")
        } catch {}
    }

    func testHubSendsToOutgoingIncomingAndSurvivesFailure() async throws {
        let tvServer = NinoDisplayServer(options: .init(name: "Android TV", port: 0, advertise: false))
        let tvPort = try await tvServer.start()
        defer { tvServer.stop() }
        let sender = NinoSender(host: "127.0.0.1", port: tvPort)
        try await sender.connect()
        let dead = NinoSender(host: "127.0.0.1", port: 1) // hiç bağlanmadı: hata verir

        let hub = DisplayHub()
        await hub.add(sender, key: "android")
        await hub.add(ingress, key: "web")
        await hub.add(dead, key: "dead")
        let web = FakeWebTV(port: port)
        try await web.handshake()
        try await waitUntil { self.ingress.displays.count == 1 }

        let p = ShowPayload(id: 1, text: "Herkese")
        try await hub.show(p)
        try await waitUntil { tvServer.current == p }
        let got6 = try await web.next()
        XCTAssertEqual(try NinoMessage(string: got6), .show(p))
        try await hub.clear(id: 1)
        try await waitUntil { tvServer.current == nil }
        let got7 = try await web.next()
        XCTAssertEqual(try NinoMessage(string: got7), .clear(id: 1))

        // Bütün çıkışlar hata verirse hub hata döner.
        let lonely = DisplayHub()
        await lonely.add(dead, key: "dead")
        do {
            try await lonely.show(p)
            XCTFail("hata bekleniyordu")
        } catch let f as DisplayHub.Failure {
            XCTAssertEqual(Array(f.failures.keys), ["dead"])
        }
        try await DisplayHub().show(p) // çıkış yok: sessiz
        web.close()
        await sender.disconnect()
    }
}
