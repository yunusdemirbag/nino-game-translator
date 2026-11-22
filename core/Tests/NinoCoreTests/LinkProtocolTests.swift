// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import XCTest
@testable import NinoCore

final class NinoMessageTests: XCTestCase {
    func testRoundTripAll() throws {
        let all: [NinoMessage] = [
            .hello(version: 1, device: "Mac", client: "nino-mac/0.1.0"),
            .welcome(version: 1, name: "Salon TV"),
            .info(version: 1, versions: [1], name: "Salon TV", id: "abc"),
            .show(ShowPayload(id: 42, text: "Buraya gel.", source: "Come here.", position: .top, durationMs: 1500)),
            .clear(id: 42), .clear(id: nil),
            .ping(t: 1_732_233_600_000), .pong(t: 7),
            .error(code: "version_unsupported", message: nil, versions: [1]),
            .ok,
        ]
        for m in all {
            XCTAssertEqual(try NinoMessage(data: m.encoded()), m, m.jsonString)
            XCTAssertTrue(m.jsonString.contains(#""app":"nino""#))
        }
    }

    func testHandshakeShape() {
        XCTAssertEqual(NinoMessage.hello(version: 1, device: nil, client: nil).jsonString,
                       #"{"app":"nino","type":"hello","version":1}"#)
    }

    func testIgnoresUnknownFieldsAndTypes() throws {
        let m = try NinoMessage(string: #"{"app":"nino","type":"show","id":1,"text":"Selam","color":"red"}"#)
        XCTAssertEqual(m, .show(ShowPayload(id: 1, text: "Selam")))
        XCTAssertEqual(try NinoMessage(string: #"{"app":"nino","type":"dance"}"#), .unknown(type: "dance"))
    }

    func testRejects() {
        XCTAssertThrowsError(try NinoMessage(string: "nope")) { XCTAssertEqual($0 as? NinoMessage.DecodeError, .notJSON) }
        XCTAssertThrowsError(try NinoMessage(string: #"{"app":"other","type":"hello","version":1}"#)) {
            XCTAssertEqual($0 as? NinoMessage.DecodeError, .notNino)
        }
        XCTAssertThrowsError(try NinoMessage(string: #"{"app":"nino","type":"show","id":1}"#)) {
            XCTAssertEqual($0 as? NinoMessage.DecodeError, .missingField("text"))
        }
    }

    func testVersionNegotiation() {
        XCTAssertEqual(NinoLink.bestCommonVersion([1, 2, 3], ours: [1, 2]), 2)
        XCTAssertNil(NinoLink.bestCommonVersion([3], ours: [1]))
    }

    func testLocalAddresses() {
        for h in ["10.0.0.5", "172.16.1.1", "172.31.255.1", "192.168.1.20", "169.254.3.3", "127.0.0.1",
                  "::1", "fe80::1%en0", "fd12::3", "::ffff:192.168.1.2"] {
            XCTAssertTrue(NinoLink.isLocalAddress(h), h)
        }
        for h in ["8.8.8.8", "172.32.0.1", "2001:db8::1", "example.com", "1.2.3"] {
            XCTAssertFalse(NinoLink.isLocalAddress(h), h)
        }
    }
}

final class DisplaySessionTests: XCTestCase {
    private func hello(_ v: Int = 1) -> String { NinoMessage.hello(version: v, device: "Mac", client: nil).jsonString }

    func testHandshakeThenShowClearPing() {
        var s = DisplaySession(name: "Salon TV")
        XCTAssertEqual(s.receive(hello()), [.send(.welcome(version: 1, name: "Salon TV")), .ready(version: 1)])
        XCTAssertEqual(s.state, .ready)
        let p = ShowPayload(id: 1, text: "Selam")
        XCTAssertEqual(s.receive(NinoMessage.show(p).jsonString), [.show(p)])
        XCTAssertEqual(s.receive(NinoMessage.clear(id: 1).jsonString), [.clear(id: 1)])
        XCTAssertEqual(s.receive(NinoMessage.ping(t: 5).jsonString), [.send(.pong(t: 5))])
        XCTAssertEqual(s.receive(#"{"app":"nino","type":"dance"}"#), [])
    }

    func testVersionMismatchClosesWithVersions() {
        var s = DisplaySession(name: "TV")
        XCTAssertEqual(s.receive(hello(9)), [.send(.error(code: "version_unsupported", message: nil, versions: [1])), .close])
        XCTAssertEqual(s.state, .closed)
        XCTAssertEqual(s.receive(hello()), [])
    }

    func testBadHandshake() {
        var a = DisplaySession(name: "TV")
        XCTAssertEqual(a.receive(NinoMessage.ping(t: 1).jsonString), [.send(.error(code: "bad_handshake", message: nil, versions: nil)), .close])
        var b = DisplaySession(name: "TV")
        XCTAssertEqual(b.receive(#"{"app":"other","type":"hello","version":1}"#).last, .close)
    }

    func testBadMessageAfterReadyKeepsOpen() {
        var s = DisplaySession(name: "TV")
        _ = s.receive(hello())
        let out = s.receive("{bozuk")
        XCTAssertEqual(out.count, 1)
        guard case let .send(.error(code, _, _)) = out[0] else { return XCTFail() }
        XCTAssertEqual(code, "bad_message")
        XCTAssertEqual(s.state, .ready)
    }

    func testTooLargeCloses() {
        var s = DisplaySession(name: "TV")
        _ = s.receive(hello())
        // Sınır 512 KB (cover için): 17 KB artık geçer, 513 KB kapatır.
        let medium = NinoMessage.show(ShowPayload(id: 1, text: String(repeating: "a", count: 17_000))).jsonString
        XCTAssertEqual(s.receive(medium).count, 1)
        let big = NinoMessage.show(ShowPayload(id: 1, text: String(repeating: "a", count: 525_000))).jsonString
        XCTAssertEqual(s.receive(big), [.send(.error(code: "too_large", message: nil, versions: nil)), .close])
    }

    func testTimeoutAndReplaced() {
        var a = DisplaySession(name: "TV")
        XCTAssertEqual(a.handshakeTimedOut(), [.close])
        var b = DisplaySession(name: "TV")
        _ = b.receive(hello())
        XCTAssertEqual(b.handshakeTimedOut(), [])
        XCTAssertEqual(b.replaced(), [.send(.error(code: "replaced", message: nil, versions: nil)), .close])
    }

    func testBoardClearById() {
        var board = DisplayBoard()
        board.show(ShowPayload(id: 2, text: "İki"))
        XCTAssertFalse(board.clear(id: 1), "geç gelen clear yeni altyazıyı silmez")
        XCTAssertEqual(board.current?.id, 2)
        XCTAssertTrue(board.clear(id: 2))
        board.show(ShowPayload(id: 3, text: "Üç"))
        XCTAssertTrue(board.clear(id: nil))
        XCTAssertNil(board.current)
    }

    func testBackoff() {
        var b = ReconnectBackoff()
        XCTAssertEqual((0..<6).map { _ in b.next() }, [1, 2, 4, 8, 8, 8])
        b.reset()
        XCTAssertEqual(b.next(), 1)
    }

    func testDiscoveredDisplayParse() {
        let e = NWEndpointStub.endpoint
        let d = DiscoveredDisplay.parse(name: "Salon TV", txt: ["v": "1", "id": "abc"], endpoint: e)
        XCTAssertEqual(d.id, "abc")
        XCTAssertEqual(d.version, 1)
        XCTAssertTrue(d.isCompatible)
        XCTAssertFalse(DiscoveredDisplay.parse(name: "x", txt: ["v": "7"], endpoint: e).isCompatible)
        XCTAssertTrue(DiscoveredDisplay.parse(name: "x", txt: [:], endpoint: e).isCompatible)
    }
}

import Network
enum NWEndpointStub {
    static let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 1)
}

final class WebSocketCodecTests: XCTestCase {
    func testAcceptKeyFromRFCExample() {
        XCTAssertEqual(WebSocketFrame.acceptKey(for: "dGhlIHNhbXBsZSBub25jZQ=="), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    func testMaskedRoundTripAllLengths() throws {
        for n in [0, 5, 125, 126, 300, 70_000] {
            let f = WebSocketFrame(opcode: .text, payload: Data(repeating: 0x61, count: n))
            let bytes = f.encoded(mask: [1, 2, 3, 4])
            let (back, used) = try XCTUnwrap(WebSocketFrame.decode(bytes, maxPayload: 100_000, requireMask: true))
            XCTAssertEqual(back, f)
            XCTAssertEqual(used, bytes.count)
        }
    }

    func testIncompleteAndErrors() throws {
        let bytes = WebSocketFrame.text("selam").encoded(mask: [9, 9, 9, 9])
        XCTAssertNil(try WebSocketFrame.decode(bytes.prefix(4), maxPayload: 100, requireMask: true))
        XCTAssertThrowsError(try WebSocketFrame.decode(WebSocketFrame.text("x").encoded(), maxPayload: 100, requireMask: true)) {
            XCTAssertEqual($0 as? WebSocketFrame.DecodeError, .unmaskedClientFrame)
        }
        XCTAssertThrowsError(try WebSocketFrame.decode(bytes, maxPayload: 2, requireMask: true)) {
            XCTAssertEqual($0 as? WebSocketFrame.DecodeError, .tooLarge)
        }
    }

    func testAssemblerJoinsFragments() {
        var a = WebSocketAssembler(maxMessage: 100)
        XCTAssertEqual(a.add(WebSocketFrame(fin: false, opcode: .text, payload: Data("Mer".utf8))), .none)
        XCTAssertEqual(a.add(WebSocketFrame(fin: true, opcode: .continuation, payload: Data("haba".utf8))),
                       .message(.text, Data("Merhaba".utf8)))
        XCTAssertEqual(a.add(WebSocketFrame(opcode: .continuation, payload: Data())), .protocolError)
    }

    func testHTTPParse() throws {
        let raw = Data("POST /nino/show?x=1 HTTP/1.1\r\nHost: tv\r\nContent-Length: 4\r\n\r\nabcdEXTRA".utf8)
        let (r, used) = try XCTUnwrap(HTTPRequest.parse(raw))
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.path, "/nino/show")
        XCTAssertEqual(r.header("HOST"), "tv")
        XCTAssertEqual(r.body, Data("abcd".utf8))
        XCTAssertEqual(used, raw.count - 5)
        XCTAssertNil(try HTTPRequest.parse(Data("GET / HTTP/1.1\r\n".utf8)))
        XCTAssertThrowsError(try HTTPRequest.parse(Data("GARBAGE\r\n\r\n".utf8)))
    }
}

final class LinkURLTests: XCTestCase {
    func testBuildsURLs() throws {
        XCTAssertEqual(try NinoLink.url(scheme: "ws", host: "192.168.1.5", port: 47800, path: "/nino/ws").absoluteString,
                       "ws://192.168.1.5:47800/nino/ws")
        XCTAssertEqual(try NinoLink.url(scheme: "http", host: "fe80::1%en0", port: 1, path: "/nino/info").absoluteString,
                       "http://[fe80::1%25en0]:1/nino/info")
        XCTAssertEqual(try NinoLink.url(scheme: "http", host: "[::1]", port: 1, path: "/").absoluteString, "http://[::1]:1/")
        XCTAssertEqual(try NinoLink.url(scheme: "http", host: "192.168.0.2%en0", port: 1, path: "/").absoluteString, "http://192.168.0.2:1/")
        XCTAssertThrowsError(try NinoLink.url(scheme: "http", host: "", port: 1, path: "/"))
    }
}
