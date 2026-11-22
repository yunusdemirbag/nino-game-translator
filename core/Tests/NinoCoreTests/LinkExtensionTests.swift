// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import XCTest
@testable import NinoCore

final class LinkExtensionTests: XCTestCase {
    func testShowExtrasRoundTripAndShape() throws {
        let p = ShowPayload(id: 3, text: "Selam", durationMs: 2000,
                            box: NinoBox(left: 0.1, top: 0.8, right: 0.9, bottom: 0.95),
                            paragraphs: true, replace: true, light: 0.42, cover: "QUJD")
        let m = NinoMessage.show(p)
        XCTAssertEqual(try NinoMessage(data: m.encoded()), m)
        XCTAssertEqual(m.jsonString,
                       #"{"app":"nino","box":{"bottom":0.95,"left":0.1,"right":0.9,"top":0.8},"cover":"QUJD","durationMs":2000,"#
                       + #""id":3,"light":0.42,"paragraphs":true,"position":"bottom","replace":true,"text":"Selam","type":"show"}"#)
        XCTAssertEqual(p.coverData, Data("ABC".utf8))
    }

    func testBoxIsClampedAndRounded() {
        let p = ShowPayload(id: 1, text: "x", box: NinoBox(left: -0.2, top: 0.123456, right: 1.7, bottom: 0.5), light: 0.4567)
        let json = NinoMessage.show(p).jsonString
        XCTAssertTrue(json.contains(#""box":{"bottom":0.5,"left":0,"right":1,"top":0.1235}"#), json)
        XCTAssertTrue(json.contains(#""light":0.46"#), json)
    }

    func testEventsRoundTrip() throws {
        let item = ScreenItem(box: NinoBox(left: 0.1, top: 0.1, right: 0.4, bottom: 0.2), text: "Görev", line: 0.03,
                              paragraphs: true, plain: true, italic: true, fill: "#112233", ink: "#ffffff", angle: -2.5,
                              alpha: 0.8, side: true, frost: true, backdrop: false, card: true)
        let all: [NinoEvent] = [
            .style(NinoStyle(fontSize: 46, bottomPercent: 7, placement: "cover", background: 100, backgroundShape: "band",
                             bold: false, textColor: "yellow", displayMode: "inApp", stackPrevious: true, theme: "glass",
                             autoSize: true, font: "condensed", watermark: false)),
            .style(NinoStyle()),
            .started, .stopped,
            .screen(ScreenPayload(items: [item], durationMs: 120_000, overlay: true)),
            .screen(ScreenPayload(items: [], durationMs: 5000)),
            .screenClear,
            .region(RegionPayload(id: "map", text: "Köprü", box: NinoBox(left: 0.7, top: 0.05, right: 0.95, bottom: 0.1), line: 0.02)),
            .region(RegionPayload(id: "7", text: "")),
            .regionClear,
        ]
        for e in all {
            XCTAssertEqual(try NinoEvent(data: e.encoded()), e, e.jsonString)
            XCTAssertTrue(e.jsonString.contains(#""app":"nino""#))
            // Eski çözücü bunları bilinmeyen tür sayar; bağlantı kapanmaz.
            XCTAssertEqual(try NinoMessage(data: e.encoded()), .unknown(type: e.type))
        }
        XCTAssertEqual(NinoEvent.started.jsonString, #"{"app":"nino","type":"started"}"#)
        XCTAssertEqual(NinoEvent.screenClear.jsonString, #"{"app":"nino","type":"screen-clear"}"#)
        XCTAssertEqual(NinoEvent.style(NinoStyle(fontSize: 30, bold: true)).jsonString,
                       #"{"app":"nino","bold":true,"fontSize":30,"type":"style"}"#)
    }

    func testEventDecodingEdgeCases() throws {
        XCTAssertNil(try NinoEvent(string: #"{"app":"nino","type":"show","id":1,"text":"x"}"#))
        XCTAssertEqual(try NinoEvent(string: #"{"app":"nino","type":"region","id":12,"text":"a"}"#),
                       .region(RegionPayload(id: "12", text: "a")))
        XCTAssertThrowsError(try NinoEvent(string: #"{"app":"x","type":"started"}"#))
        // Küçük açılar yollanmaz.
        let tiny = ScreenItem(box: NinoBox(left: 0, top: 0, right: 1, bottom: 1), text: "a", angle: 0.2)
        XCTAssertNil(tiny.jsonObject["angle"])
    }

    func testInfoExtensions() throws {
        let info = NinoInfo(name: "Mac", id: "m1", model: "Mac", appVersion: "4.0.0", role: NinoLink.senderRole)
        let back = try NinoInfo(data: info.encoded())
        XCTAssertEqual(back, info)
        XCTAssertTrue(back.isSender)
        // Uzantılı info eski çözücüyle de okunur.
        XCTAssertEqual(try NinoMessage(data: info.encoded()), .info(version: 1, versions: [1], name: "Mac", id: "m1"))
        // Uzantısız info.
        let plain = try NinoInfo(data: NinoMessage.info(version: 1, versions: [1], name: "TV", id: "t").encoded())
        XCTAssertFalse(plain.isSender)
        XCTAssertNil(plain.model)
        XCTAssertEqual(info.message.jsonString, #"{"app":"nino","id":"m1","name":"Mac","type":"info","version":1,"versions":[1]}"#)
    }

    func testFittingLimitDropsOversizedCover() {
        let small = ShowPayload(id: 1, text: "a", cover: String(repeating: "A", count: 1000))
        XCTAssertEqual(small.fittingLimit(), small)
        let huge = ShowPayload(id: 1, text: "a", cover: String(repeating: "A", count: NinoLink.maxMessageBytes))
        XCTAssertNil(huge.fittingLimit().cover)
        XCTAssertEqual(huge.fittingLimit().text, "a")
        XCTAssertEqual(NinoLink.maxMessageBytes, 512 * 1024)
    }

    func testQueryItems() throws {
        let raw = Data("GET /events?model=LG%20OLED&app=4.1&viewer=obs&x HTTP/1.1\r\nHost: a\r\n\r\n".utf8)
        let (r, _) = try XCTUnwrap(HTTPRequest.parse(raw))
        XCTAssertEqual(r.path, "/events")
        XCTAssertEqual(r.queryItems, ["model": "LG OLED", "app": "4.1", "viewer": "obs", "x": ""])
    }
}

/// Uzantılar gerçek soketle: NinoSender → NinoDisplayServer.
final class LinkExtensionIntegrationTests: XCTestCase {
    func testLargeCoverPassesOverWebSocketAndHTTP() async throws {
        let server = NinoDisplayServer(options: .init(name: "TV", port: 0, advertise: false))
        let port = try await server.start()
        defer { server.stop() }
        let cover = Data((0..<150_000).map { UInt8($0 % 251) }).base64EncodedString()
        let p = ShowPayload(id: 1, text: "Buzlu", box: NinoBox(left: 0.1, top: 0.8, right: 0.9, bottom: 0.9), light: 0.3, cover: cover)
        let sender = NinoSender(host: "127.0.0.1", port: port)
        try await sender.connect()
        try await sender.show(p)
        try await waitUntil { server.current == p }
        // Uzantı türleri TV'yi kapatmaz.
        try await sender.send(.style(NinoStyle(fontSize: 50)))
        try await sender.send(.started)
        try await sender.ping()
        await sender.disconnect()

        var q = p
        q.id = 2
        try await NinoHTTPClient.show(q, host: "127.0.0.1", port: port)
        XCTAssertEqual(server.current, q)
    }
}
