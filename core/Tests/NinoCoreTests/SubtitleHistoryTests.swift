// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

final class SubtitleHistoryTests: XCTestCase {
    func testSimilarity() {
        XCTAssertTrue(SubtitleHistory.isSimilar("Who is that?", "who is that"))
        XCTAssertFalse(SubtitleHistory.isSimilar("Where is the boy", "Where is the ship"))
        XCTAssertFalse(SubtitleHistory.isSimilar("", ""))
    }

    func testAddUpdatesSimilarAndCaps() {
        var h = SubtitleHistory()
        let d = Date(timeIntervalSince1970: 1_763_300_000)
        h.add(source: "Who is that?", translation: "O kim?", origin: .engine, date: d)
        h.add(source: "Who is that", translation: "O da kim?", origin: .pack, date: d + 1)
        XCTAssertEqual(h.entries.count, 1)
        XCTAssertEqual(h.entries[0].id, 0)
        XCTAssertEqual(h.entries[0].translation, "O da kim?")
        h.add(source: "Ignored", translation: "   ", origin: .engine)
        XCTAssertEqual(h.entries.count, 1)
        for i in 0..<250 { h.add(source: "Line \(i) is unique \(i * 7919)", translation: "Satır \(i)", origin: .engine, date: d + Double(i + 2)) }
        XCTAssertEqual(h.entries.count, 200)
        XCTAssertEqual(h.entries[0].translation, "Satır 249")
        h.add(source: String(repeating: "a", count: 600) + " end", translation: String(repeating: "b", count: 600), origin: .engine)
        XCTAssertEqual(h.entries[0].translation.count, 500)
        XCTAssertEqual(h.entries(since: d + 251).count, 1 + 1)
    }

    func testFileRoundTripAndPlainText() throws {
        let dir = try makeLibraryTempDirectory("nino-history")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("history.json")
        XCTAssertTrue(SubtitleHistory(contentsOf: file).entries.isEmpty)
        try Data("bozuk".utf8).write(to: file)
        XCTAssertTrue(SubtitleHistory(contentsOf: file).entries.isEmpty)

        var h = SubtitleHistory()
        h.add(source: "Stay low!", translation: "Alçakta kal!", origin: .pack, date: Date(timeIntervalSince1970: 3600))
        try h.write(to: file)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        XCTAssertEqual(object["version"] as? Int, 1)
        let entry = (object["entries"] as! [[String: Any]])[0]
        XCTAssertEqual(entry["date"] as? String, "1970-01-01T01:00:00Z")
        XCTAssertEqual(entry["origin"] as? String, "pack")
        XCTAssertEqual(SubtitleHistory(contentsOf: file).entries, h.entries)
        XCTAssertEqual(h.plainText(timeZone: TimeZone(identifier: "UTC")!), "[01:00:00] Alçakta kal!\nStay low!")

        // Eski dosyada `version` sonda olabilir, kesirli tarih de okunur.
        try Data(#"{"entries":[{"id":4,"date":"2026-11-16T10:00:00.123Z","source":"a b","translation":"c","origin":"engine"}],"version":1}"#.utf8).write(to: file)
        XCTAssertEqual(SubtitleHistory(contentsOf: file).entries.first?.id, 4)

        // Tek bozuk kayıt bütün geçmişi silmez.
        try Data(#"{"version":1,"entries":[{"id":1,"date":"yok","source":"a","translation":"b","origin":"pack"},{"id":2,"date":"2026-11-16T10:00:00Z","source":"c","translation":"d","origin":"engine"}]}"#.utf8).write(to: file)
        XCTAssertEqual(SubtitleHistory(contentsOf: file).entries.map(\.id), [2])
    }

    func testLogQuoteAndWrite() throws {
        XCTAssertEqual(SubtitleLog.quote("Who is\nthat?"), "\"Who is / that?\"")
        let long = SubtitleLog.quote(String(repeating: "x", count: 200))
        XCTAssertEqual(long.count, 122)
        XCTAssertTrue(long.hasSuffix("…\""))

        let dir = try makeLibraryTempDirectory("nino-log")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("altyazi.log")
        let log = SubtitleLog(fileURL: file, timeZone: TimeZone(identifier: "UTC")!, now: { Date(timeIntervalSince1970: 0.25) })
        log.write("\(SubtitleLog.quote("Stay low!")) → paket:gta-v")
        log.flush()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "[1970-01-01 00:00:00.250] \"Stay low!\" → paket:gta-v\n")

        try Data(count: SubtitleLog.maxBytes + 1).write(to: file)
        log.write("yeni")
        log.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("altyazi.log.1").path))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "[1970-01-01 00:00:00.250] yeni\n")

        SubtitleLog(fileURL: nil).write("hiçbir yere") // çökmez
    }
}
