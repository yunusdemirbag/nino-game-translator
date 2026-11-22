// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

final class LegacyPackTests: XCTestCase {
    // MARK: gzip

    func testGzipHeaderFieldsAreSkipped() throws {
        let payload = Data(String(repeating: "Nino çeviri ", count: 9000).utf8) // birden çok blok
        let gz = TestGzip.make(payload, name: "x.json", comment: "c", extra: [1, 2, 3], headerCRC: true)
        XCTAssertTrue(Gzip.isGzip(gz))
        XCTAssertEqual(try Gzip.decompress(gz), payload)
    }

    func testGzipSizeMismatchIsBroken() {
        let gz = TestGzip.make(Data("{}".utf8), corruptSize: true)
        XCTAssertThrowsError(try Gzip.decompress(gz)) { XCTAssertEqual($0 as? Gzip.Failure, .sizeMismatch) }
    }

    func testShortDataIsNotGzip() {
        XCTAssertFalse(Gzip.isGzip(Data([0x1f, 0x8b, 8])))
    }

    // MARK: Dosya

    func testFormat2() throws {
        let file: [String: Any] = [
            "format": 2, "id": "ornek", "title": "Örnek Oyun",
            "entries": [libraryKey("Stay low!"): "  <b>Eğil</b>! ", "zz": "atla", libraryKey("Empty"): "<i></i>"],
            "segments": [libraryKey("Run."): "Koş."],
            "unknown": true,
        ]
        let pack = try LegacyPack(data: TestGzip.make(libraryJSON(file)), fileName: "ornek.json.gz")
        XCTAssertEqual(pack.id, "ornek")
        XCTAssertEqual(pack.title, "Örnek Oyun")
        XCTAssertEqual(pack.lineCount, 1)
        XCTAssertEqual(pack.exact("STAY LOW"), "Eğil!")
        XCTAssertEqual(pack.exact("run?"), "Koş.")
        XCTAssertNil(pack.exact("Empty"))
        XCTAssertNil(pack.fuzzy)
    }

    func testFlatObjectTakesIDFromFileName() throws {
        let pack = try LegacyPack(data: libraryJSON([libraryKey("Hello there"): "Merhaba"]), fileName: "mafia.json.gz")
        XCTAssertEqual(pack.id, "mafia")
        XCTAssertEqual(pack.title, "mafia")
        XCTAssertEqual(pack.exact("hello, there!"), "Merhaba")
    }

    func testRejections() {
        XCTAssertThrowsError(try LegacyPack(data: libraryJSON(["format": 3, "entries": [libraryKey("a b"): "x"]]), fileName: "a.json")) {
            XCTAssertEqual($0 as? LegacyPack.LoadError, .unsupportedFormat(3))
        }
        XCTAssertThrowsError(try LegacyPack(data: libraryJSON(["format": 1, "entries": [:]]), fileName: "a.json")) {
            XCTAssertEqual($0 as? LegacyPack.LoadError, .noEntries)
        }
        XCTAssertThrowsError(try LegacyPack(data: Data("nope".utf8), fileName: "a.json"))
        XCTAssertThrowsError(try LegacyPack(data: TestGzip.make(Data("{}".utf8), corruptSize: true), fileName: "a.json.gz")) {
            XCTAssertEqual($0 as? LegacyPack.LoadError, .badGzip)
        }
    }

    func testFormat1IgnoresSegmentsAndTitleFallsBackToID() throws {
        let file: [String: Any] = ["format": 1, "id": "oyun", "entries": [libraryKey("Yes sir"): "Evet efendim"],
                                   "segments": [libraryKey("No"): "Hayır"]]
        let pack = try LegacyPack(data: libraryJSON(file), fileName: "x.json")
        XCTAssertEqual(pack.title, "oyun")
        XCTAssertNil(pack.exact("No"))
    }

    // MARK: Bulanık dizin

    /// Kendi ürettiğimiz dizinle paketi kurar (paket betiğinin yaptığı gibi).
    static func packWithIndex(_ lines: [String: String], extraEmpty: [String] = []) throws -> LegacyPack {
        var entries: [String: String] = [:]
        for (en, tr) in lines { entries[libraryKey(en)] = tr }
        for en in extraEmpty { entries[libraryKey(en)] = "" }
        let englishByKey = Dictionary(uniqueKeysWithValues: (Array(lines.keys) + extraEmpty).map { (LineKey.key($0)!, $0) })
        let sorted = englishByKey.keys.sorted()
        var mask = [UInt8](repeating: 0, count: (sorted.count + 7) / 8)
        var lengths: [UInt8] = [], blooms: [UInt8] = []
        for (i, key) in sorted.enumerated() {
            guard let sig = FuzzySignature(text: englishByKey[key]!) else { continue }
            mask[i >> 3] |= 1 << UInt8(i & 7)
            lengths.append(UInt8(sig.length))
            blooms += sig.bytes
        }
        let file: [String: Any] = [
            "format": 2, "id": "test", "entries": entries,
            "fuzzy": ["version": 1, "count": sorted.count, "mask": Data(mask).base64EncodedString(),
                      "lengths": Data(lengths).base64EncodedString(), "blooms": Data(blooms).base64EncodedString()],
        ]
        return try LegacyPack(data: libraryJSON(file), fileName: "test.json")
    }

    func testIndexCountsEmptyTranslations() throws {
        let pack = try Self.packWithIndex(["Stay close to me, kid.": "Yanımdan ayrılma, evlat."],
                                          extraEmpty: ["Where did the old miller go tonight?"])
        XCTAssertEqual(pack.fuzzy?.keys.count, 2)
    }

    func testBrokenIndexStillLoads() throws {
        let file: [String: Any] = ["format": 2, "id": "t", "entries": [libraryKey("Hello there friend"): "Selam"],
                                   "fuzzy": ["version": 1, "count": 5, "mask": "AA==", "lengths": "", "blooms": ""]]
        let pack = try LegacyPack(data: libraryJSON(file), fileName: "t.json")
        XCTAssertNil(pack.fuzzy)
        XCTAssertEqual(pack.exact("hello there friend"), "Selam")
    }

    func testFoldAndSignatureTable() {
        let rows: [(String, String, Bool, Int, Int)] = [
            // Beklenenler tarifin (kutuphane.md 3.2) kurallarıyla elle çıkarıldı.
            ("Stay cIose to me, kid.", "stayciosetomekid", false, 16, 64),                        // I→l okuma, l→i katlama
            ("Where's the old mill?", "wherestheoidmiii", false, 16, 64),                          // kesme sözcük içinde serbest
            ("We rnust reach the 5outh gate.", "wernustreachthesouthgate", true, 24, 128),          // 5→s, harf-rakam bitişik
            ("CAPTAİN: The engine room is f1ooding•fast.", "captaintheengineroomisfioodingfast", true, 34, 128), // ASCII dışı, 1→i
        ]
        for (input, folded, noisy, length, bits) in rows {
            XCTAssertEqual(String(FuzzySignature.fold(input)), folded, input)
            XCTAssertEqual(FuzzySignature.isNoisy(input), noisy, input)
            let sig = FuzzySignature(text: input)
            XCTAssertEqual(sig?.length, length, input)
            XCTAssertEqual(sig?.bitCount, bits, input)
        }
        XCTAssertNil(FuzzySignature(text: "Stay low!"))  // katlanmış boy < 16
        XCTAssertEqual(FuzzySignature.bits(forLength: 100), 256)
    }

    func testSimilarityBounds() {
        let a = FuzzySignature(text: "Stay close to me, kid.")!
        XCTAssertEqual(FuzzySignature.similarity(a, a), 100, accuracy: 0.001)
        let b = FuzzySignature(text: "Completely unrelated words here")!
        XCTAssertLessThan(FuzzySignature.similarity(a, b), 30)
        XCTAssertEqual(FuzzySignature.similarity(a, FuzzySignature(length: 20, words: [0])), 0)
    }

    func testThresholds() {
        XCTAssertEqual(FuzzySignature.threshold(length: 20, noisy: false), 90)
        XCTAssertEqual(FuzzySignature.threshold(length: 30, noisy: false), 80)
        XCTAssertEqual(FuzzySignature.threshold(length: 20, noisy: true), 70)
        XCTAssertEqual(FuzzySignature.threshold(length: 30, noisy: true), 60)
        XCTAssertEqual(FuzzySignature.threshold(length: 50, noisy: true), 55)
    }

    func testSingleEditFindsOCRMistake() throws {
        let pack = try Self.packWithIndex(["Come here.": "Buraya gel.", "I can't do this anymore.": "Artık yapamam."])
        XCTAssertEqual(pack.fuzzyMatch("Corne here."), "Buraya gel.")     // rn → m
        XCTAssertEqual(pack.fuzzyMatch("I cant do this anymore."), "Artık yapamam.") // sözcük bölme
        XCTAssertNil(pack.fuzzyMatch("Go away."))
    }

    func testSingleEditAmbiguousGivesNothing() throws {
        let pack = try Self.packWithIndex(["Get the cat": "Kediyi al", "Get the car": "Arabayı al"])
        XCTAssertNil(pack.singleEditMatch("Get the ca"))
    }

    func testBloomNearLength() throws {
        let pack = try Self.packWithIndex([
            "The engine room is flooding fast, captain.": "Makine dairesi hızla su alıyor, kaptan.",
            "Where's the old mill?": "Eski değirmen nerede?",
        ])
        XCTAssertEqual(pack.bloomMatch("The engine roorn is f1ooding fast, captaín."), "Makine dairesi hızla su alıyor, kaptan.")
        XCTAssertNil(pack.bloomMatch("Something completely different is said here."))
    }

    func testBloomOneWayCoverageForHalfRead() throws {
        let long = "Grab the lantern and follow the creek down to the old mill before sunrise."
        let pack = try Self.packWithIndex([long: "Feneri al, güneş doğmadan dereyi izleyip eski değirmene in."])
        XCTAssertEqual(pack.bloomMatch("Grab the lantern and follow the creek down to the old mill"),
                       "Feneri al, güneş doğmadan dereyi izleyip eski değirmene in.")
    }

    func testClauseSplitting() {
        XCTAssertEqual(LegacyPack.clauses("Hello there. How are you doing today?"), ["Hello there.", "How are you doing today?"])
        XCTAssertEqual(LegacyPack.clauses("Wait. no way this happens"), ["Wait. no way this happens"])
        XCTAssertEqual(LegacyPack.clauses("Okay, fine, we go together now"), ["Okay, fine,", "we go together now"])
        XCTAssertTrue(LegacyPack.isCornerText("Press Start"))
        XCTAssertTrue(LegacyPack.isCornerText("map • open"))
        XCTAssertFalse(LegacyPack.isCornerText("Press start"))
    }

    // MARK: Gerçek paketler

    /// Gerçek paketteki imza, bizim hesapladığımızla bayt bayt aynı olmalı
    /// (katlama, üçlü, FNV, bit sırası ve sayısal anahtar sırası birlikte doğrulanır).
    func testRealPackSignatureMatchesOurs() throws {
        let source = try legacyPacksDirectory().appendingPathComponent("mafia-the-old-country.json.gz")
        let dir = try makeLibraryTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let copy = dir.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: copy)

        let pack = try LegacyPack(contentsOf: copy)
        XCTAssertEqual(pack.id, "mafia-the-old-country")
        // Cümle depoya konmaz: eski paketteki bir İngilizce satır ortam değişkeniyle verilir.
        guard let line = ProcessInfo.processInfo.environment["NINO_LEGACY_PACK_LINE"], !line.isEmpty else {
            throw XCTSkip("NINO_LEGACY_PACK_LINE verilmedi")
        }
        let key = try XCTUnwrap(LineKey.key(line))
        XCTAssertNotNil(pack.text(for: key))
        let stored = try XCTUnwrap(pack.fuzzy?.signature(for: key))
        let ours = try XCTUnwrap(FuzzySignature(text: line))
        XCTAssertEqual(Int(stored.length), min(String(FuzzySignature.fold(line)).count, 255))
        XCTAssertEqual(stored, ours)
    }
}
