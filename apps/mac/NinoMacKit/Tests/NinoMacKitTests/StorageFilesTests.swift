// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoMacKit

final class StorageFilesTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("nino-files-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    private func file(_ name: String, _ text: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private var missing: URL { dir.appendingPathComponent("yok.json") }

    // MARK: Okuyucular

    func testHistory() throws {
        let url = try file("history.json", """
        {"entries":[
          {"id":3,"date":"2026-11-20T10:00:00Z","source":"Who is that?","translation":"O kim?","origin":"pack"},
          {"id":"bad"},
          {"id":2,"date":"2026-11-20T09:59:58.123Z","source":"Go","translation":"Git","origin":"other"}
        ],"version":1}
        """)
        let h = DataFiles.history(at: url)
        XCTAssertEqual(h.map(\.id), [3, 2])
        XCTAssertEqual(h[0].origin, .pack)
        XCTAssertNil(h[1].origin)
        XCTAssertEqual(h[0].translation, "O kim?")
        XCTAssertEqual(DataFiles.history(at: missing), [])
        XCTAssertEqual(DataFiles.history(at: try file("b.json", "{bozuk")), [])
    }

    func testSubtitleLayout() throws {
        let url = try file("subtitle-layout.json",
                           #"{"samples":{"genel":[{"top":0.8,"bottom":0.9},{"top":"x"}],"gta-6":[{"top":0.7,"bottom":0.95}],"bad":3}}"#)
        let l = DataFiles.subtitleLayout(at: url)
        XCTAssertEqual(l["genel"], [DataFiles.LayoutBand(top: 0.8, bottom: 0.9)])
        XCTAssertEqual(l["gta-6"]?.count, 1)
        XCTAssertNil(l["bad"])
        XCTAssertEqual(DataFiles.subtitleLayout(at: missing), [:])
    }

    func testPhoneMemory() throws {
        let url = try file("phone-memory-tr.json", #"{"where are you":"Neredesin","n":1}"#)
        XCTAssertEqual(DataFiles.phoneMemory(at: url), ["where are you": "Neredesin"])
        XCTAssertEqual(DataFiles.phoneMemory(at: try file("x.json", "[]")), [:])
    }

    func testPoolState() throws {
        let url = try file("pool/state.json",
                           #"{"install":"0f0e-uuid","frozenThrough":42,"failures":0,"nextAttempt":1763300000.5,"app":"0.2.6","dropped":1}"#)
        let s = try XCTUnwrap(DataFiles.poolState(at: url))
        XCTAssertEqual(s.install, "0f0e-uuid")
        XCTAssertEqual(s.frozenThrough, 42)
        XCTAssertEqual(s.nextAttempt, 1763300000.5)
        XCTAssertNil(s.serverRetryAt)
        XCTAssertNil(DataFiles.poolState(at: missing))
        let broken = try file("pool2/state.json", "{{")
        XCTAssertNil(DataFiles.poolState(at: broken))
        XCTAssertTrue(fm.fileExists(atPath: broken.path), "okuyucu bozuk dosyayı kenara almaz")
    }

    func testIncidents() throws {
        let id = UUID()
        let url = try file("sorunlar.json", """
        [{"id":"\(id.uuidString)","date":"2026-11-21T20:00:00Z","kind":"ps5Dropped","reason":"x",
          "streamedMinutes":12.5,"network":"wifi","game":"gta-6"},
         {"id":"nope","date":"2026-11-21T20:00:00Z","kind":"tvDropped"},
         {"id":"\(UUID().uuidString)","date":"2026-11-21T20:01:00.5Z","kind":"futureKind"}]
        """)
        let list = DataFiles.incidents(at: url)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].id, id)
        XCTAssertEqual(list[0].kind, .ps5Dropped)
        XCTAssertEqual(list[0].streamedMinutes, 12.5)
        XCTAssertNil(list[1].kind)
        XCTAssertEqual(list[1].rawKind, "futureKind")
        XCTAssertEqual(DataFiles.incidents(at: try file("o.json", "{}")), [])
    }

    // MARK: Günlük

    func testLogFormatAndRotation() throws {
        let url = dir.appendingPathComponent("logs/altyazi.log")
        let fixed = Date(timeIntervalSince1970: 0)
        let log = RotatingLog(url: url, limit: 100, now: { fixed })
        log.write("merhaba")
        log.flush()
        let first = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(first.hasSuffix("] merhaba\n"))
        XCTAssertNotNil(first.range(of: #"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\] "#, options: .regularExpression))
        for i in 0..<10 { log.write("satır \(i) " + String(repeating: "x", count: 20)) }
        log.flush()
        XCTAssertTrue(fm.fileExists(atPath: log.rotatedURL.path))
        let size = try XCTUnwrap(fm.attributesOfItem(atPath: url.path)[.size] as? Int)
        XCTAssertLessThanOrEqual(size, 100)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("satır 9"))
    }

    func testLogUnwritableIsSilent() {
        let log = RotatingLog(url: URL(fileURLWithPath: "/dev/null/olmaz/altyazi.log"))
        log.write("x")
        log.flush()
    }

    func testQuote() {
        XCTAssertEqual(RotatingLog.quote("Who is\nthat?"), "\"Who is / that?\"")
        let long = String(repeating: "a", count: 130)
        let q = RotatingLog.quote(long)
        XCTAssertEqual(q.count, 122)
        XCTAssertTrue(q.hasSuffix("…\""))
    }
}
