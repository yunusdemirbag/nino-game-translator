// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoMacKit

final class AppIdentityTests: XCTestCase {
    func testReleaseUsesRealData() {
        let id = AppIdentity.current(bundleID: "com.ninotranslator.mac")
        XCTAssertEqual(id, .release)
        XCTAssertEqual(id.folderName, "Nino")
    }

    func testDevelopmentAndUnknownStayApart() {
        XCTAssertEqual(AppIdentity.current(bundleID: "com.ninotranslator.mac.dev"), .development)
        XCTAssertEqual(AppIdentity.current(bundleID: nil), .development)
        XCTAssertNotEqual(AppIdentity.development.keychainService, AppIdentity.release.keychainService)
    }
}
