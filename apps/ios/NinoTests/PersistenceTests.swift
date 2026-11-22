// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import Nino

/// Önceki sürümün kayıtları yeni uygulamada aynen açılmalı (docs/yeni/ios/kalicilik.md).
final class PersistenceTests: XCTestCase {
    private func settings(_ json: String) -> AppSettings {
        let suite = "nino-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(json.utf8), forKey: Keys.settings)
        return AppSettings.load(from: defaults, preferredLanguages: ["nl-NL"])
    }

    func testFullDefaultSettings() {
        let s = settings(#"{"region":{"top":0.62,"bottom":0.97,"left":0.14,"right":0.86},"areaPreset":"bottom","extraAreas":[],"style":{"fontSize":46,"bottomPercent":7,"placement":"cover","background":100,"backgroundShape":"fit","bold":false,"textColor":"white","displayMode":"inApp","stackPrevious":true,"theme":"classic","autoSize":true,"font":"condensed","watermark":true},"sourceLanguage":"en","targetLanguage":"tr","onlineTranslation":false,"onlineEngine":"deepl","geminiModel":"gemini-3.5-flash-lite","openAIModel":"gpt-6-luna","claudeModel":"claude-haiku-5-5","localAIBaseURL":"http:\/\/localhost:11434\/v1","localAIModel":"translategemma:4b","output":"tv","overlayClickThrough":false,"videoSource":"ps5","gameConsole":"ps5","gamePacks":true,"sharePool":true,"autoReport":true,"translateCorners":true,"askGame":true,"showSpeakerNames":true,"fastSubtitleDetection":false,"xboxAudioOnDevice":true,"appearance":"system","homeStyle":"livingRoom","frameSource":"ps5","remotePlayApp":"automatic"}"#)
        XCTAssertEqual(s, AppSettings())
        XCTAssertEqual(s.style.font, .action)
        XCTAssertEqual(s.localAIBaseURL, "http://localhost:11434/v1")
    }

    func testOldShortRecord() {
        let s = settings(#"{"region":{"top":0.55,"bottom":0.95,"left":0.1,"right":0.9},"sourceLanguage":"en","targetLanguage":"ar","output":"both","style":{"fontSize":58,"placement":"cover","background":30}}"#)
        XCTAssertEqual(s.areaPreset, .custom)
        XCTAssertEqual(s.output, .tv)
        XCTAssertEqual(s.targetLanguage, "ar")
        XCTAssertEqual(s.style.fontSize, 58)
        XCTAssertEqual(s.style.background, 100)
        XCTAssertEqual(s.style.textColor, "white")
    }

    func testMissingTargetIsTurkishNotSystem() {
        XCTAssertEqual(settings(#"{"sourceLanguage":"en"}"#).targetLanguage, "tr")
    }

    func testExtraAreasAndLenientFields() {
        let s = settings(#"{"region":{"top":0.62,"bottom":0.97,"left":0.14,"right":0.86},"extraAreas":[{"id":"7C1D2E3F-0000-4000-8000-000000000001","name":"Görev","region":{"top":0.03,"bottom":0.3,"left":0.66,"right":0.98},"enabled":true}],"onlineTranslation":true,"onlineEngine":"free","homeStyle":"bogus"}"#)
        XCTAssertEqual(s.areaPreset, .bottom)
        XCTAssertEqual(s.extraAreas.count, 1)
        XCTAssertEqual(s.extraAreas[0].name, "Görev")
        XCTAssertEqual(s.onlineEngine, .deepL)
        XCTAssertEqual(s.homeStyle, "livingRoom")
    }

    func testBrokenExtraAreaDropsWholeList() {
        let s = settings(#"{"extraAreas":[{"name":"A"},{"name":5}]}"#)
        XCTAssertEqual(s.extraAreas, [])
    }

    func testWrongRequiredTypeResetsEverything() {
        let s = settings(#"{"targetLanguage":"tr","gamePacks":"evet"}"#)
        XCTAssertEqual(s.targetLanguage, "nl") // ilk açılış: sistem dili
        XCTAssertTrue(s.gamePacks)
    }

    func testUnknownFieldsArePreservedOnSave() throws {
        var s = settings(#"{"targetLanguage":"tr","videoSource":"card","remotePlayApp":"chiaki"}"#)
        s.targetLanguage = "ar"
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(s.encoded())) as? [String: Any])
        XCTAssertEqual(dict["videoSource"] as? String, "card")
        XCTAssertEqual(dict["remotePlayApp"] as? String, "chiaki")
        XCTAssertEqual(dict["targetLanguage"] as? String, "ar")
        XCTAssertEqual(dict["output"] as? String, "tv")
    }

    func testConsoleAndTVRecords() throws {
        let store = MemoryStore([
            Keys.console: Data(#"{"host":"192.168.1.103","name":"PS5-002","registKey":"MWEyYjNjNGQAAAAAAAAAAA==","morning":"AAECAwQFBgcICQoLDA0ODw=="}"#.utf8),
            Keys.tv: Data(#"{"name":"Salon TV","host":"192.168.1.50"}"#.utf8),
            Keys.accountID: Data(#""AAECAwQFBgc=""#.utf8),
            Keys.tvKey: Data(#""""#.utf8),
            Keys.setupComplete: Data("true".utf8),
        ])
        let console = try XCTUnwrap(store.load(PairedConsole.self, for: Keys.console))
        XCTAssertEqual(console.name, "PS5-002")
        XCTAssertEqual(console.registKey.prefix(8), Data("1a2b3c4d".utf8))
        XCTAssertEqual(console.morning.count, 16)
        let tv = try XCTUnwrap(store.load(PairedTV.self, for: Keys.tv))
        XCTAssertEqual(tv.brand, .lg)
        XCTAssertEqual(store.load(Data.self, for: Keys.accountID), Data([0, 1, 2, 3, 4, 5, 6, 7]))
        XCTAssertEqual(store.load(String.self, for: Keys.tvKey), "")
        XCTAssertEqual(store.load(Bool.self, for: Keys.setupComplete), true)
        XCTAssertNil(try? JSONDecoder().decode(PairedTV.self, from: Data(#"{"name":"a","host":"b","brand":"sony"}"#.utf8)))
    }

    func testHistoryFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID()).json")
        try Data(#"{"version":1,"entries":[{"id":12,"date":"2026-11-22T21:14:03Z","source":"Stay close.","translation":"Yakın dur.","origin":"pack"},{"id":11,"date":"2026-11-22T21:13:58Z","source":"Who's there?","translation":"Kim var orada?","origin":"engine"}]}"#.utf8).write(to: url)
        var h = SubtitleHistory.load(from: url)
        XCTAssertEqual(h.entries.map(\.id), [12, 11])
        XCTAssertEqual(h.nextID, 13)
        h.add(source: "Go", translation: "Git", origin: .engine)
        try h.save(to: url)
        XCTAssertEqual(SubtitleHistory.load(from: url).entries.first?.translation, "Git")
        try Data(#"{"version":1,"entries":[{"id":1,"date":"2026-11-22T21:14:03Z","source":"a","translation":"b","origin":"x"}]}"#.utf8).write(to: url)
        XCTAssertTrue(SubtitleHistory.load(from: url).entries.isEmpty)
    }

    func testFolderMigration() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("folders-\(UUID())")
        let old = base.appendingPathComponent(LegacyNames.folder)
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: old.appendingPathComponent("history.json"))
        let url = AppFolders.resolve(in: base)
        XCTAssertEqual(url.lastPathComponent, "Nino")
        XCTAssertTrue(fm.fileExists(atPath: url.appendingPathComponent("history.json").path))
        XCTAssertFalse(fm.fileExists(atPath: old.path))
    }

    func testKeychainLegacyMigration() {
        let service = "com.ninotranslator.tests.\(UUID())"
        let legacy = "com.ninotranslator.tests.legacy.\(UUID())"
        let old = KeychainStore(service: legacy, legacyService: nil)
        old.save("abc", for: Keys.tvKey)
        let store = KeychainStore(service: service, legacyService: legacy)
        XCTAssertEqual(store.load(String.self, for: Keys.tvKey), "abc")
        XCTAssertNil(old.load(String.self, for: Keys.tvKey))
        XCTAssertEqual(KeychainStore(service: service, legacyService: nil).load(String.self, for: Keys.tvKey), "abc")
        store.remove(Keys.tvKey)
    }
}
