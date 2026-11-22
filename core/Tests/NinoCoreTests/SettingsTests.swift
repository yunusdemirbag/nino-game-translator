// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import XCTest
@testable import NinoCore

final class SettingsTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nino-settings-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func testDirectoriesLayout() throws {
        let d = NinoDirectories(root: dir)
        try d.prepare()
        for u in [d.cacheDirectory, d.packsDirectory, d.logsDirectory] {
            var isDir: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) && isDir.boolValue)
        }
        XCTAssertEqual(d.translationCacheFile.lastPathComponent, "translations.json")
        XCTAssertEqual(d.settingsFile.deletingLastPathComponent().standardizedFileURL, dir.standardizedFileURL)
        XCTAssertEqual(try NinoDirectories.standard().root.lastPathComponent, "Nino")
    }

    func testMissingFileGivesDefaults() {
        let store = SettingsStore(directories: NinoDirectories(root: dir))
        XCTAssertEqual(store.load(), NinoSettings())
    }

    func testSaveAndLoad() throws {
        let store = SettingsStore(directories: NinoDirectories(root: dir))
        var s = NinoSettings()
        s.reading.stableFrames = 4
        s.translation.userTerms = [Term("Osk")]
        s.translation.selectedGameID = "ornek-oyun"
        s.translation.providers = [.init(name: "http-1", urlTemplate: "http://127.0.0.1:9/t", responsePath: ["t"])]
        s.display.host = "192.168.1.30"
        try store.save(s)
        XCTAssertEqual(store.load(), s)
    }

    func testPartialFileFillsDefaultsAndClamps() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("settings.json")
        try Data(#"{"reading":{"stableFrames":0},"unknown":{"rate":5}}"#.utf8).write(to: url)
        let s = SettingsStore(fileURL: url).load()
        XCTAssertEqual(s.reading.stableFrames, 1)
        XCTAssertEqual(s.reading.missingFrames, 2)
        XCTAssertEqual(s.translation.targetLanguage, "tr")
        XCTAssertEqual(s.display.port, 47800)
    }

    func testCorruptFileIsMovedAside() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("settings.json")
        try Data("bozuk".utf8).write(to: url)
        XCTAssertEqual(SettingsStore(fileURL: url).load(), NinoSettings())
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("settings.bad.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testReadingConfiguration() {
        var s = NinoSettings()
        s.reading.ignoredPhrases = ["Hold to Skip"]
        s.reading.missingFrames = 5
        let c = s.readingConfiguration
        XCTAssertEqual(c.missingFrames, 5)
        XCTAssertTrue(c.filter.isNoise(RecognizedLine(text: "hold to skip", confidence: 1, box: .defaultSubtitle)))
    }

    func testProvidersGetKeysFromSecretStore() async throws {
        var s = NinoSettings()
        s.translation.providers = [.init(name: "http-1", urlTemplate: "http://127.0.0.1:9/t?k={key}", method: "GET",
                                         headers: [:], responsePath: ["t"])]
        let secrets = MemorySecretStore([NinoSettings.secretAccount(forProvider: "http-1"): "gizli"])
        StubURLProtocol.handler = { _ in (200, Data(#"{"t":"tamam"}"#.utf8)) }
        defer { StubURLProtocol.handler = nil }
        let providers = s.makeProviders(secrets: secrets, session: StubURLProtocol.session())
        XCTAssertEqual(providers.map(\.name), ["http-1"])
        _ = try await providers[0].translate("ok", from: "en", to: "tr")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.query, "k=gizli")
    }
}

final class SecretStoreTests: XCTestCase {
    func testMemoryStore() throws {
        let s = MemorySecretStore()
        XCTAssertNil(try s.get("a"))
        try s.set("1", for: "a")
        try s.set("2", for: "a")
        XCTAssertEqual(try s.get("a"), "2")
        try s.delete("a")
        XCTAssertNil(try s.get("a"))
    }

    /// Gerçek Keychain'e yazar; yalnız NINO_KEYCHAIN_TESTS=1 ise çalışır.
    func testKeychainStore() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NINO_KEYCHAIN_TESTS"] == "1", "NINO_KEYCHAIN_TESTS=1 ile çalışır")
        let s = KeychainSecretStore(service: "com.ninotranslator.tests")
        let account = "test-\(UUID().uuidString)"
        defer { try? s.delete(account) }
        XCTAssertNil(try s.get(account))
        try s.set("bir", for: account)
        XCTAssertEqual(try s.get(account), "bir")
        try s.set("iki", for: account)
        XCTAssertEqual(try s.get(account), "iki")
        try s.delete(account)
        XCTAssertNil(try s.get(account))
    }
}
