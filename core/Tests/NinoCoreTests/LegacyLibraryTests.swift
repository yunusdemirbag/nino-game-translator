// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

final class LegacyLibraryTests: XCTestCase {
    var dirs: [URL] = []

    override func tearDownWithError() throws {
        for d in dirs { try? FileManager.default.removeItem(at: d) }
    }

    func dir() throws -> URL {
        let d = try makeLibraryTempDirectory()
        dirs.append(d)
        return d
    }

    func write(_ object: [String: Any], _ name: String, in dir: URL, gzip: Bool = false) throws {
        let data = libraryJSON(object)
        try (gzip ? TestGzip.make(data) : data).write(to: dir.appendingPathComponent(name))
    }

    func pack(_ id: String, title: String? = nil, entries: [String: String], segments: [String: String] = [:]) -> [String: Any] {
        var e: [String: String] = [:], s: [String: String] = [:]
        for (k, v) in entries { e[libraryKey(k)] = v }
        for (k, v) in segments { s[libraryKey(k)] = v }
        return ["format": 2, "id": id, "title": title ?? id, "entries": e, "segments": s]
    }

    func testReadsLegacyAndModernPacksAndSkipsBroken() throws {
        let bundled = try dir(), user = try dir()
        try write(pack("mafia", title: "Mafia: The Old Country", entries: ["Stay low!": "Eğil!"]), "mafia.json.gz", in: bundled, gzip: true)
        try Data("bozuk".utf8).write(to: bundled.appendingPathComponent("broken.json"))
        let modern = try TranslationPack(game: .init(id: "yeni-oyun", title: "Yeni Oyun"),
                                         lines: [.init(source: "Come here.", target: "Buraya gel.")])
        try modern.write(to: user.appendingPathComponent("yeni.ninopack.json"))

        let library = LegacyLibrary(directories: [bundled, user])
        XCTAssertEqual(library.gameIDs, ["mafia", "yeni-oyun"])
        XCTAssertEqual(library.failures.map(\.file), ["broken.json"])
        XCTAssertEqual(library.infos.first, .init(id: "mafia", title: "Mafia: The Old Country", lineCount: 1, bundled: true, legacy: true))
        XCTAssertEqual(library.exact("STAY LOW")?.text, "Eğil!")
        XCTAssertEqual(library.exact("Come here.")?.text, "Buraya gel.")
        XCTAssertNotNil(library.pack(for: "yeni-oyun"))
    }

    func testUserPackReplacesBundled() throws {
        let bundled = try dir(), user = try dir()
        try write(pack("gta-v", entries: ["Stay low!": "Eski"]), "gta-v.json", in: bundled)
        try write(pack("gta-v", entries: ["Stay low!": "Yeni"]), "gta-v.json.gz", in: user, gzip: true)
        let library = LegacyLibrary(directories: [bundled, user])
        XCTAssertEqual(library.packs.count, 1)
        XCTAssertEqual(library.infos[0].bundled, false)
        XCTAssertEqual(library.exact("Stay low!")?.text, "Yeni")
    }

    func testEntriesBeatSegmentsOfOtherPacks() throws {
        let d = try dir()
        try write(pack("a-game", entries: ["Okay then.": "Tamam o zaman.", "Only A": "A"]), "a.json", in: d)
        try write(pack("b-game", entries: ["Only B": "B"], segments: ["Okay then.": "Parça"]), "b.json", in: d)
        let library = LegacyLibrary(directories: [d])
        let hit = try XCTUnwrap(library.exact("okay then"))
        XCTAssertEqual(hit.text, "Tamam o zaman.")
        XCTAssertEqual(hit.packs, [0, 1])
    }

    func testScopeAndDistinctiveHit() throws {
        let d = try dir()
        try write(pack("a-game", entries: ["Shared line": "Ortak A", "Only in A": "A"]), "a.json", in: d)
        try write(pack("b-game", entries: ["Shared line": "Ortak B", "Only in B": "B"]), "b.json", in: d)
        let library = LegacyLibrary(directories: [d])
        var scope = PackScope()

        XCTAssertEqual(scope.lookup("Shared line", in: library)?.text, "Ortak B")
        XCTAssertEqual(scope.scopeID(in: library), "a-game") // kapsam yoktu: ilk paket
        XCTAssertNil(scope.takeDistinctiveHit(in: library))

        XCTAssertEqual(scope.lookup("Only in B", in: library)?.packID, "b-game")
        XCTAssertEqual(scope.takeDistinctiveHit(in: library), "b-game")
        XCTAssertNil(scope.takeDistinctiveHit(in: library)) // okununca silinir

        _ = scope.lookup("Shared line", in: library)
        XCTAssertEqual(scope.scopeID(in: library), "b-game") // kapsam ortak paketlerden biriyse kalır
    }

    func testFuzzyOnlyInScope() throws {
        let d = try dir()
        try write(pack("a-game", entries: ["Come here now.": "Hemen buraya gel."]), "a.json", in: d)
        let library = LegacyLibrary(directories: [d])
        var scope = PackScope()
        XCTAssertNil(scope.lookup("Corne here now.", in: library)) // kapsam yok
        _ = scope.lookup("Come here now.", in: library)
        let m = scope.lookup("Corne here now.", in: library)
        XCTAssertEqual(m?.text, "Hemen buraya gel.")
        XCTAssertEqual(m?.kind, .fuzzy)
    }

    func testSelectedGameRestrictsSearch() throws {
        let d = try dir()
        try write(pack("gta-v", title: "Grand Theft Auto V", entries: ["Okay.": "Tamam (GTA)."]), "gta-v.json", in: d)
        try write(pack("mafia-the-old-country", title: "Mafia: The Old Country", entries: ["Okay.": "Tamam (Mafia)."]), "m.json", in: d)
        try write(pack("pool-genel", title: "GTA 5", entries: ["Okay.": "Ortak"]), "pool-genel.json", in: d)
        let library = LegacyLibrary(directories: [d])
        var scope = PackScope()
        scope.select(game: "GTA 5")
        XCTAssertEqual(scope.lookup("Okay.", in: library)?.text, "Tamam (GTA).")
        scope.select(game: "Mafia The Old Country")
        XCTAssertEqual(scope.lookup("okay", in: library)?.packID, "mafia-the-old-country")
        scope.select(game: "Elden Ring") // paketi yok: hiç aranmaz
        XCTAssertNil(scope.lookup("Okay.", in: library))
        scope.select(game: nil)
        XCTAssertNotNil(scope.lookup("Okay.", in: library))
    }

    /// Uygulamayla gelen 9 paket geçici klasöre kopyalanıp okunur.
    func testRealBundledPacks() throws {
        let source = try legacyPacksDirectory()
        let d = try dir()
        let files = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".json.gz") }
        for f in files { try FileManager.default.copyItem(at: f, to: d.appendingPathComponent(f.lastPathComponent)) }

        let library = LegacyLibrary(directories: [d])
        XCTAssertEqual(library.failures, [])
        XCTAssertEqual(library.packs.count, 9)
        XCTAssertEqual(Set(library.gameIDs), [
            "assassins-creed-shadows", "call-of-duty-modern-warfare-2019", "death-stranding-2",
            "death-stranding-directors-cut", "elden-ring", "gta-v", "mafia-the-old-country",
            "marvels-spider-man-2", "red-dead-redemption-2",
        ])
        for case let .legacy(p) in library.packs {
            XCTAssertNotNil(p.fuzzy, p.id)
            XCTAssertGreaterThan(p.lineCount, 1000, p.id)
        }
        if let line = ProcessInfo.processInfo.environment["NINO_LEGACY_PACK_LINE"], !line.isEmpty {
            XCTAssertNotNil(library.exact(line))
        }
        XCTAssertEqual(library.index(forGameNamed: "GTA 5").map { library.packs[$0].id }, "gta-v")
        XCTAssertEqual(library.index(forGameNamed: "Red Dead Redemption II").map { library.packs[$0].id }, "red-dead-redemption-2")
    }
}
