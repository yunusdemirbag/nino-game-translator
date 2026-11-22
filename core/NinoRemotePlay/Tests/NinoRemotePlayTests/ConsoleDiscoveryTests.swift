// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import XCTest
@testable import NinoRemotePlay

/// Gerçek ağda PS5 arar. Yalnız NINO_PS5_TESTS=1 ise çalışır.
final class ConsoleDiscoveryLiveTests: XCTestCase {
    func testFindsConsoleOnLAN() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NINO_PS5_TESTS"] == "1", "NINO_PS5_TESTS=1 ile çalışır")
        let discovery = ConsoleDiscovery()
        let stream = try discovery.consoles()
        let found: [ConsoleInfo] = await withTaskGroup(of: [ConsoleInfo].self) { group in
            group.addTask {
                for await list in stream where !list.isEmpty { return list }
                return []
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(8))
                return []
            }
            let first = await group.next() ?? []
            group.cancelAll()
            discovery.stop()
            return first
        }
        for c in found {
            print("KONSOL: \(c.name) \(c.address) \(c.state) ps5=\(c.isPS5) sürüm=\(c.systemVersion) oyun=\(c.runningAppName ?? "-")")
        }
        XCTAssertFalse(found.isEmpty, "ağda konsol bulunamadı")
    }
}

final class BroadcastTests: XCTestCase {
    func testBroadcastAddressesAreIPv4() {
        for a in ConsoleDiscovery.broadcastAddresses() {
            XCTAssertEqual(Int32(a.ss_family), AF_INET)
        }
    }
}
