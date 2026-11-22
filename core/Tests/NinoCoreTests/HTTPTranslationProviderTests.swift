// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import XCTest
@testable import NinoCore

/// Ağa çıkmadan URLSession cevabı veren sahte protokol.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                data.append(buf, count: n)
            }
            stream.close()
            Self.lastBody = data
        } else {
            Self.lastBody = request.httpBody
        }
        let (status, data) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

final class HTTPTranslationProviderTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
    }

    func testPostBodyTemplateAndResponsePath() async throws {
        StubURLProtocol.handler = { _ in (200, Data(#"{"data":[{"text":"Buraya gel."}]}"#.utf8)) }
        let config = HTTPTranslationProvider.Configuration(
            name: "http-1", urlTemplate: "http://127.0.0.1:9/translate",
            headers: ["Content-Type": "application/json", "Authorization": "Bearer {key}"],
            bodyTemplate: #"{"q":"{text}","source":"{source}","target":"{target}"}"#,
            responsePath: ["data", "0", "text"])
        let p = HTTPTranslationProvider(configuration: config, apiKey: "test-key", session: StubURLProtocol.session())
        let out = try await p.translate("Say \"hi\".", from: "en", to: "tr")
        XCTAssertEqual(out, "Buraya gel.")
        XCTAssertEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let body = try JSONSerialization.jsonObject(with: StubURLProtocol.lastBody ?? Data()) as? [String: String]
        XCTAssertEqual(body?["q"], "Say \"hi\".")
        XCTAssertEqual(body?["target"], "tr")
    }

    func testGetQueryIsEncoded() async throws {
        StubURLProtocol.handler = { _ in (200, Data(#"{"t":["Mer","haba"]}"#.utf8)) }
        let config = HTTPTranslationProvider.Configuration(
            name: "http-2", urlTemplate: "http://127.0.0.1:9/t?q={text}&sl={source}", method: "GET",
            headers: [:], responsePath: ["t"])
        let p = HTTPTranslationProvider(configuration: config, session: StubURLProtocol.session())
        let out = try await p.translate("a&b c", from: "en", to: "tr")
        XCTAssertEqual(out, "Merhaba")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.query, "q=a%26b%20c&sl=en")
    }

    func testHTTPErrorAndBadShape() async {
        let config = HTTPTranslationProvider.Configuration(name: "h", urlTemplate: "http://127.0.0.1:9/", responsePath: ["x"])
        let p = HTTPTranslationProvider(configuration: config, session: StubURLProtocol.session())

        StubURLProtocol.handler = { _ in (503, Data()) }
        do { _ = try await p.translate("a", from: "en", to: "tr"); XCTFail() } catch {
            XCTAssertEqual(error as? TranslationProviderError, .http(503))
        }
        StubURLProtocol.handler = { _ in (200, Data(#"{"y":1}"#.utf8)) }
        do { _ = try await p.translate("a", from: "en", to: "tr"); XCTFail() } catch {
            XCTAssertEqual(error as? TranslationProviderError, .badResponse)
        }
    }
}
