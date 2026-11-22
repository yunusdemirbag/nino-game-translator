// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import XCTest
@testable import NinoMacKit

/// Bütün metin tabloları 12 dilde dolu mu, yer tutucular İngilizceyle aynı mı.
/// Tablolar diskten okunur; sonradan eklenen tablo ve anahtarları da kendiliğinden yakalar.
final class LocalizationTests: XCTestCase {
    static let languages = ["en", "tr", "ar", "bn", "fil", "hi", "id", "ms", "nl", "th", "ur", "vi"]

    private static var resources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NinoMacKit/Resources")
    }

    private func tables() throws -> [(name: String, strings: [String: Any])] {
        let files = try FileManager.default.contentsOfDirectory(at: Self.resources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "xcstrings" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertGreaterThanOrEqual(files.count, 7)
        return try files.map { url in
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            let strings = try XCTUnwrap(json?["strings"] as? [String: Any], url.lastPathComponent)
            return (url.deletingPathExtension().lastPathComponent, strings)
        }
    }

    /// Bir dildeki tekil değer (çoğul/cihaz varyasyonu kullanılmıyor: NinoL10n düz `String(format:)` yapar).
    private func value(_ entry: Any, _ language: String) -> String? {
        let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any]
        let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        return unit?["value"] as? String
    }

    func testEveryKeyHasEveryLanguage() throws {
        for table in try tables() {
            XCTAssertFalse(table.strings.isEmpty, table.name)
            for (key, entry) in table.strings {
                for language in Self.languages {
                    let text = value(entry, language)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    XCTAssertFalse(text.isEmpty, "\(table.name) › \(key) › \(language) boş")
                }
            }
        }
    }

    func testPlaceholdersMatchEnglish() throws {
        for table in try tables() {
            for (key, entry) in table.strings {
                guard let english = value(entry, "en") else { continue }
                let expected = Self.placeholders(in: english)
                XCTAssertFalse(expected.mixed, "\(table.name) › \(key) › en: konumlu ve konumsuz karışık")
                for language in Self.languages where language != "en" {
                    guard let text = value(entry, language) else { continue }
                    let found = Self.placeholders(in: text)
                    XCTAssertFalse(found.mixed, "\(table.name) › \(key) › \(language): konumlu ve konumsuz karışık")
                    XCTAssertEqual(found.specs, expected.specs, "\(table.name) › \(key) › \(language): yer tutucular")
                    XCTAssertEqual(found.percents, expected.percents, "\(table.name) › \(key) › \(language): %%")
                }
            }
        }
    }

    func testEveryLanguageResolvesAtRuntime() {
        // Derlenen paket her dilin klasörünü taşımalı (fil.lproj dahil); İngilizceye düşmemeli.
        let english = NinoL10n.string("home.splash.tagline", table: "Home", language: "en")
        for language in Self.languages where language != "en" {
            let text = NinoL10n.string("home.splash.tagline", table: "Home", language: language)
            XCTAssertNotEqual(text, english, language)
            XCTAssertNotEqual(text, "home.splash.tagline", language)
        }
        XCTAssertEqual(NinoL10n.languageCode(for: Locale(identifier: "tl")), "fil")
        XCTAssertEqual(MainWindowView.interfaceLanguage(for: "tl"), "fil")
        for code in MacSettings.targetLanguages {
            XCTAssertTrue(Self.languages.contains(MainWindowView.interfaceLanguage(for: code)), code)
            XCTAssertNotEqual(MainWindowView.interfaceLanguage(for: code), "en", code)
        }
        XCTAssertTrue(NinoL10n.isRightToLeft(languageCode: "ar"))
        XCTAssertTrue(NinoL10n.isRightToLeft(languageCode: "ur"))
        XCTAssertFalse(NinoL10n.isRightToLeft(languageCode: "th"))
    }

    func testPlaceholderParser() {
        let parsed = Self.placeholders(in: "%2$@ a %1$lld %.1f %% b")
        XCTAssertEqual(parsed.specs, ["1:%lld", "1:%.1f", "2:%@"].sorted())
        XCTAssertEqual(parsed.percents, 1)
        XCTAssertTrue(parsed.mixed)
        XCTAssertFalse(Self.placeholders(in: "%@ ve %@").mixed)
        XCTAssertEqual(Self.placeholders(in: "%@ ve %@").specs, ["1:%@", "2:%@"])
    }

    /// Biçim belirteçleri: sıra numarası + tür (`%d` ile `%lld` ayrı, `%.1f` hassasiyetiyle).
    static func placeholders(in text: String) -> (specs: [String], percents: Int, mixed: Bool) {
        let pattern = #"%(?:(\d+)\$)?([-+ #0]*\d*(?:\.\d+)?(?:ll|l|h)?[@dfsuxXc%])"#
        let regex = try! NSRegularExpression(pattern: pattern)
        var specs: [String] = []
        var percents = 0
        var next = 0
        var positional = false
        var plain = false
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let body = ns.substring(with: match.range(at: 2))
            if body == "%" { percents += 1; continue }
            let index: Int
            if match.range(at: 1).location != NSNotFound {
                positional = true
                index = Int(ns.substring(with: match.range(at: 1))) ?? 0
            } else {
                plain = true
                next += 1
                index = next
            }
            specs.append("\(index):%\(body)")
        }
        return (specs.sorted(), percents, positional && plain)
    }
}
