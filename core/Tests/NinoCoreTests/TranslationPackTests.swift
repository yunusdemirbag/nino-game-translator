// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import XCTest
@testable import NinoCore

final class TranslationPackTests: XCTestCase {
    private func samplePack(version: String? = "1.0") throws -> TranslationPack {
        try TranslationPack(
            game: .init(id: "ornek-oyun", title: "Örnek Oyun", version: version),
            terms: [Term("Osk")],
            lines: [
                .init(source: "Come here.", target: "Buraya gel."),
                .init(source: "The ferry leaves at dawn, so get some sleep.", target: "Feribot şafakta kalkıyor, biraz uyu."),
                .init(source: "Are you coming with us?", target: "Bizimle geliyor musun?"),
                .init(source: "No.", target: "Hayır."),
            ])
    }

    func testExactMatchUsesKey() throws {
        let p = try samplePack()
        XCTAssertEqual(p.lookup("  come HERE. "), "Buraya gel.")
        XCTAssertNil(p.lookup("Come here?"))
    }

    func testFuzzyMatchesOCRErrors() throws {
        let p = try samplePack()
        XCTAssertEqual(p.lookup("The ferry 1eaves at dawn, so get some s1eep."), "Feribot şafakta kalkıyor, biraz uyu.")
        XCTAssertEqual(p.lookup("Are you comlng with us?"), "Bizimle geliyor musun?")
    }

    func testFuzzyRejects() throws {
        let p = try samplePack()
        XCTAssertNil(p.lookup("Go."), "kısa yazı bulanık eşleşmez")
        XCTAssertNil(p.lookup("Are you coming with us."), "soru ile soru olmayan eşleşmez")
        XCTAssertNil(p.lookup("The ferry leaves at noon, so pack your bags now."))
    }

    func testValidationAndWarnings() throws {
        XCTAssertThrowsError(try TranslationPack(game: .init(id: "Bad Id"), lines: [])) {
            XCTAssertEqual($0 as? TranslationPack.LoadError, .badGameID("Bad Id"))
        }
        let p = try TranslationPack(game: .init(id: "x"), lines: [
            .init(source: "Hi.", target: "Selam."),
            .init(source: "hi.", target: "Merhaba."),
            .init(source: " ", target: "Boş"),
        ])
        XCTAssertEqual(p.lines.count, 1)
        XCTAssertEqual(p.warnings, 2)
        XCTAssertEqual(p.lookup("Hi."), "Selam.", "ilki kalır")
    }

    func testDecodesFileFormat() throws {
        let json = #"""
        { "nino": 1, "game": { "id": "ornek-oyun" }, "extra": true,
          "terms": [ { "source": "Vale Harbor", "target": "Vale Limanı" } ],
          "lines": [ { "source": "Come here.", "target": "Buraya gel.", "speaker": "Osk" } ] }
        """#
        let p = try TranslationPack(data: Data(json.utf8))
        XCTAssertEqual(p.languages, .init(source: "en", target: "tr"))
        XCTAssertEqual(p.terms, [Term("Vale Harbor", "Vale Limanı")])
        XCTAssertEqual(p.match("Come here.")?.speaker, "Osk")
    }

    func testRejectsUnknownVersionAndBadJSON() {
        XCTAssertThrowsError(try TranslationPack(data: Data(#"{"nino":2,"game":{"id":"x"},"lines":[]}"#.utf8))) {
            XCTAssertEqual($0 as? TranslationPack.LoadError, .unsupportedVersion(2))
        }
        XCTAssertThrowsError(try TranslationPack(data: Data("nope".utf8)))
    }

    func testRoundTrip() throws {
        let p = try samplePack()
        let back = try TranslationPack(data: p.encoded())
        XCTAssertEqual(back.lines, p.lines)
        XCTAssertEqual(back.game, p.game)
        XCTAssertEqual(back.terms, p.terms)
    }

    func testLibraryLoadsFolderAndKeepsNewest() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nino-packs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try samplePack(version: "1.2").write(to: dir.appendingPathComponent("a.ninopack.json"))
        try samplePack(version: "1.10").write(to: dir.appendingPathComponent("b.ninopack.json"))
        try Data("bozuk".utf8).write(to: dir.appendingPathComponent("c.ninopack.json"))
        try Data("{}".utf8).write(to: dir.appendingPathComponent("notes.json"))

        let lib = PackLibrary(directory: dir)
        XCTAssertEqual(lib.gameIDs, ["ornek-oyun"])
        XCTAssertEqual(lib.pack(for: "ornek-oyun")?.game.version, "1.10")
        XCTAssertEqual(lib.failures.map(\.file), ["c.ninopack.json"])
        XCTAssertNil(lib.pack(for: "yok"))
    }

    func testTranslatorUsesPackAndItsTerms() async throws {
        let provider = FakeProvider("p", .transform { $0.replacingOccurrences(of: "Thank", with: "Teşekkürler") })
        let t = Translator(chain: ProviderChain(providers: [provider]), pack: try samplePack())
        let a = await t.translate("Come here.")
        XCTAssertEqual(a.origin, .pack)
        _ = await t.translate("Thank Osk.")
        XCTAssertEqual(provider.calls, ["Thank ⟦0⟧."])
    }
}
