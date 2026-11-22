// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoMacKit

final class SamsungBundledCATests: XCTestCase {
    /// Samsung'un dört herkese açık ara sertifikası pakette, sabit sırayla.
    func testFourIntermediatesAreBundled() {
        XCTAssertEqual(SamsungIntermediates.bundled().count, 4)
    }
}
