// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoMacKit

/// Hepsi geçici klasörde; gerçek `Application Support` ve `Logs`'a dokunulmaz.
final class StorageFolderTests: XCTestCase {
    private var root: URL!
    private var support: URL { root.appendingPathComponent("Support", isDirectory: true) }
    private var logs: URL { root.appendingPathComponent("Logs", isDirectory: true) }
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("nino-storage-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try fm.createDirectory(at: logs, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func resolver(legacyApp: Bool = false, otherInstance: Bool = false,
                          migration: Bool = true) -> DataFolderResolver {
        DataFolderResolver(folderName: "Nino", applicationSupportRoot: support, logsRoot: logs,
                           migrationAllowed: migration,
                           environment: LegacyEnvironment(legacyAppPresent: { legacyApp },
                                                          otherInstanceRunning: { otherInstance }))
    }

    private var legacyName: String { LegacyNames.folderName }

    private func makeFolder(_ base: URL, _ name: String, files: [String: String] = [:]) throws -> URL {
        let dir = base.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for (file, text) in files { try Data(text.utf8).write(to: dir.appendingPathComponent(file)) }
        return dir
    }

    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    func testLegacyNamesDecode() {
        XCTAssertFalse(LegacyNames.folderName.isEmpty)
        XCTAssertTrue(LegacyNames.bundleID.hasPrefix("com."))
        XCTAssertTrue(LegacyNames.systemInstallPath.hasPrefix("/Applications/"))
        XCTAssertTrue(LegacyNames.userInstallPath.hasPrefix("Applications/"))
    }

    func testCreatesWhenNothingExists() {
        let r = resolver().resolve()
        XCTAssertEqual(r.support, .created)
        XCTAssertEqual(r.folder.support, support.appendingPathComponent("Nino", isDirectory: true))
        XCTAssertTrue(fm.fileExists(atPath: r.folder.support.path))
        XCTAssertTrue(fm.fileExists(atPath: r.folder.logs.path))
    }

    func testFilledNewFolderWinsAndLegacyUntouched() throws {
        _ = try makeFolder(support, "Nino", files: ["history.json": "{}"])
        let legacy = try makeFolder(support, legacyName, files: ["a": "1"])
        let r = resolver().resolve()
        XCTAssertEqual(r.support, .existing)
        XCTAssertEqual(read(legacy.appendingPathComponent("a")), "1")
        XCTAssertNil(read(r.folder.support.appendingPathComponent("a")), "birleştirilmez")
    }

    func testDSStoreOnlyCountsAsEmptyAndLegacyIsMoved() throws {
        _ = try makeFolder(support, "Nino", files: [".DS_Store": "x"])
        _ = try makeFolder(support, legacyName, files: ["history.json": "{\"v\":1}"])
        let r = resolver().resolve()
        XCTAssertEqual(r.support, .moved)
        XCTAssertEqual(read(r.folder.support.appendingPathComponent("history.json")), "{\"v\":1}")
        XCTAssertFalse(fm.fileExists(atPath: support.appendingPathComponent(legacyName).path))
        XCTAssertFalse(r.notes.isEmpty)
    }

    func testCopiesWhenLegacyAppPresentAndLeavesLogsFresh() throws {
        let legacy = try makeFolder(support, legacyName, files: ["history.json": "h"])
        let legacyLogs = try makeFolder(logs, legacyName, files: ["altyazi.log": "old"])
        let stale = try makeFolder(support, "Nino.kopya-\(UUID().uuidString)", files: ["half": "1"])
        let r = resolver(legacyApp: true).resolve()
        XCTAssertEqual(r.support, .copied)
        XCTAssertEqual(read(r.folder.support.appendingPathComponent("history.json")), "h")
        XCTAssertNotNil(read(r.folder.support.appendingPathComponent("kopyalandi.txt")))
        XCTAssertEqual(read(legacy.appendingPathComponent("history.json")), "h", "eski klasör yerinde kalır")
        XCTAssertFalse(fm.fileExists(atPath: stale.path), "yarım kalmış kopya silinir")
        let leftovers = try fm.contentsOfDirectory(atPath: support.path).filter { $0.contains(".kopya-") }
        XCTAssertEqual(leftovers, [])
        // Günlükler kopyalanmaz.
        XCTAssertEqual(r.logs, .freshBesideLegacy)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: r.folder.logs.path), [])
        XCTAssertEqual(read(legacyLogs.appendingPathComponent("altyazi.log")), "old")
    }

    func testLogsMovedWhenLegacyAppAbsent() throws {
        _ = try makeFolder(logs, legacyName, files: ["remoteplay.log": "r"])
        let r = resolver().resolve()
        XCTAssertEqual(r.logs, .moved)
        XCTAssertEqual(read(r.folder.logs.appendingPathComponent("remoteplay.log")), "r")
    }

    func testOtherInstanceRunningUsesLegacy() throws {
        let legacy = try makeFolder(support, legacyName, files: ["a": "1"])
        let r = resolver(otherInstance: true).resolve()
        XCTAssertEqual(r.folder.support.standardizedFileURL, legacy.standardizedFileURL)
        XCTAssertEqual(r.support, .usingLegacy(reason: "otherInstance"))
        XCTAssertFalse(fm.fileExists(atPath: support.appendingPathComponent("Nino").path))
    }

    func testFailedMoveDoesNotCreateNewFolder() throws {
        let legacy = try makeFolder(support, legacyName, files: ["a": "1"])
        // Kökü salt okunur yap: yeniden adlandırma başarısız olur.
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: support.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: support.path) }
        let r = resolver().resolve()
        XCTAssertEqual(r.support, .usingLegacy(reason: "moveFailed"))
        XCTAssertEqual(r.folder.support.standardizedFileURL, legacy.standardizedFileURL)
        XCTAssertFalse(fm.fileExists(atPath: support.appendingPathComponent("Nino").path))
    }

    func testFailedCopyRemovesTempAndUsesLegacy() throws {
        let legacy = try makeFolder(support, legacyName, files: ["ok": "1"])
        let locked = legacy.appendingPathComponent("locked")
        try Data("x".utf8).write(to: locked)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }
        let r = resolver(legacyApp: true).resolve()
        XCTAssertEqual(r.support, .usingLegacy(reason: "copyFailed"))
        XCTAssertEqual(r.folder.support.standardizedFileURL, legacy.standardizedFileURL)
        let names = try fm.contentsOfDirectory(atPath: support.path)
        XCTAssertFalse(names.contains { $0.contains(".kopya-") })
        XCTAssertFalse(names.contains("Nino"))
    }

    func testNoMigrationWhenNotAllowed() throws {
        let legacy = try makeFolder(support, legacyName, files: ["a": "1"])
        let stale = try makeFolder(support, "Nino.kopya-x")
        let r = resolver(legacyApp: false, migration: false).resolve()
        XCTAssertEqual(r.support, .created)
        XCTAssertEqual(read(legacy.appendingPathComponent("a")), "1")
        XCTAssertTrue(fm.fileExists(atPath: stale.path))
    }

    func testDataFolderPaths() {
        let f = DataFolder(support: URL(fileURLWithPath: "/s"), logs: URL(fileURLWithPath: "/l"))
        XCTAssertEqual(f.phoneMemoryFile(language: "tr").lastPathComponent, "phone-memory-tr.json")
        XCTAssertEqual(f.poolStateFile.path, "/s/pool/state.json")
        XCTAssertEqual(f.adbKeyFile.path, "/s/adb/adbkey")
        XCTAssertEqual(f.incidentsFile.lastPathComponent, "sorunlar.json")
        XCTAssertEqual(f.subtitleLog.path, "/l/altyazi.log")
    }
}
