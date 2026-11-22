// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
@testable import NinoMacKit
import XCTest

final class ConsoleStringsTests: XCTestCase {
    /// Kodun kullandığı bütün anahtarlar.
    var usedKeys: [String] {
        let psn: [PSNLoginError] = [.incomplete, .rejected(detail: nil), .tooManyAttempts(detail: nil), .server(detail: nil),
                                    .network(detail: nil), .unreadable(detail: nil), .windowClosed, .pageFailed(detail: nil)]
        return psn.map(\.key) + PairingFailure.allCases.map(\.key)
            + ["console.error.sendLog", "console.psn.cancel", "console.psn.error.manualInvalid"]
    }

    func catalog() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NinoMacKit/Resources/Console.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try XCTUnwrap(json?["strings"] as? [String: Any])
    }

    func testEveryKeyHasEnglishAndTurkish() throws {
        let strings = try catalog()
        for key in usedKeys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let locs = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            for lang in ["en", "tr"] {
                let unit = (locs[lang] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String ?? ""
                XCTAssertFalse(value.isEmpty, "\(key) \(lang)")
            }
        }
        XCTAssertEqual(Set(strings.keys), Set(usedKeys), "katalogda kullanılmayan ya da eksik anahtar")
    }

    func testFormatArgumentsMatch() throws {
        let strings = try catalog()
        let entry = try XCTUnwrap(strings["console.error.sendLog"] as? [String: Any])
        let locs = try XCTUnwrap(entry["localizations"] as? [String: [String: [String: String]]])
        for lang in ["en", "tr"] { XCTAssertTrue(locs[lang]?["stringUnit"]?["value"]?.contains("%@") ?? false, lang) }
    }

    func testBundleResolvesKeys() {
        XCTAssertNotEqual(ConsoleText.string("console.pair.error.badCode"), "console.pair.error.badCode")
    }
}
