// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import NinoCore
import XCTest
@testable import Nino

/// TV yolu: eski TV uygulamaları (8787 düzeni, SSE) ve yeni protokoldeki TV'ler aynı altyazıyı alır.
/// Portlar rastgele: Mac'te çalışan başka bir Nino'ya ve ağdaki gerçek TV'ye karışmaz.
final class TVLinkTests: XCTestCase {
    func testLegacyTVReceivesSubtitleAndStyle() async throws {
        let link = TVLink(legacyPort: 0, ingressPort: 0)
        await link.start(tv: nil, deviceName: "iPhone", version: "test")
        XCTAssertNotEqual(link.legacyPort, 0)
        defer { Task { await link.stop() } }

        let url = URL(string: "http://127.0.0.1:\(link.legacyPort)/events")!
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let received = LatestBox<[String]>()
        let reader = Task {
            var lines: [String] = []
            for try await line in bytes.lines {
                lines.append(line)
                received.set(lines)
            }
        }
        try await Task.sleep(for: .milliseconds(300))
        await link.send(.style(SubtitleStyle().ninoStyle))
        try await link.hub.show(ShowPayload(id: 7, text: "Çatıya çık.", source: "Get to the rooftop."))
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let all = (received.get() ?? []).joined(separator: "\n")
            if all.contains("Çatıya çık.") && all.contains("event: style") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        reader.cancel()
        let all = (received.get() ?? []).joined(separator: "\n")
        XCTAssertTrue(all.contains("event: subtitle"), all)
        XCTAssertTrue(all.contains("Çatıya çık."), all)
        XCTAssertTrue(all.contains("event: style"), all)
        XCTAssertEqual(link.connectedCount, 1)
    }
}
