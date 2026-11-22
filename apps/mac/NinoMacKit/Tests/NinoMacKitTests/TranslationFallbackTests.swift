// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore
import XCTest
@testable import NinoMacKit

/// Anahtar yokken paketsiz oyunda çeviri durmaz: cihaz içi çeviri, o da yoksa havuzun ücretsiz çevirisi.
/// Ayrıca anahtar önerisi, dil paketi önerisi ve Sistem sağlığı "Çeviri" satırının kuralları.
final class TranslationFallbackTests: XCTestCase {
    private let line = "We need to get out of the city before the storm hits."

    // MARK: Zincir

    func testNoKeyNoDeviceUsesPoolTranslation() async throws {
        let server = FakePoolServer(answer: "Fırtına vurmadan şehirden çıkmalıyız.")
        let built = await build(pool: server, device: nil)
        XCTAssertNil(built.onlineEngine)
        XCTAssertEqual(built.providerNames, ["pool"])
        let out = await built.translator.translate(line)
        XCTAssertEqual(out.text, "Fırtına vurmadan şehirden çıkmalıyız.")
        XCTAssertFalse(out.failed)
    }

    func testNoKeyDeviceFirstThenPoolWhenDeviceFails() async throws {
        let server = FakePoolServer(answer: "Havuzdan gelen çeviri.")
        let device = FakeDevice(result: .success("Cihazın çevirisi."))
        let built = await build(pool: server, device: device)
        XCTAssertEqual(built.providerNames, ["device", "pool"])
        let out = await built.translator.translate(line)
        XCTAssertEqual(out.text, "Cihazın çevirisi.")

        // Dil paketi eksik: cihaz içi çeviri hata verir, havuz devralır.
        let broken = await build(pool: FakePoolServer(answer: "Havuzdan gelen çeviri."),
                                 device: FakeDevice(result: .failure(TranslationProviderError.badResponse)))
        let out2 = await broken.translator.translate(line)
        XCTAssertEqual(out2.text, "Havuzdan gelen çeviri.")
        XCTAssertFalse(out2.failed)
    }

    func testPoolSilentDoesNotRestOrFail() async throws {
        // Sunucu cevap vermez (null): boş sonuç sıradakine geçer, halka dinlenmeye alınmaz.
        let server = FakePoolServer(answer: nil)
        let built = await build(pool: server, device: nil)
        for _ in 0..<4 {
            let out = await built.translator.translate(line)
            XCTAssertTrue(out.failed)
        }
        let p = PoolFallbackProvider(pool: makePool(server, enabled: true), deadline: .milliseconds(200))
        let text = try await p.translate(line, from: "en", to: "tr")
        XCTAssertEqual(text, "")
    }

    func testPoolSharingOffIsRespected() async throws {
        let server = FakePoolServer(answer: "Gitmemeliydi.")
        let built = await build(pool: server, device: nil, sharePool: false)
        let out = await built.translator.translate(line)
        XCTAssertTrue(out.failed)
        XCTAssertEqual(server.translateCalls, 0)
    }

    func testPlaceholderTextNeverGoesToPool() async throws {
        let server = FakePoolServer(answer: "x")
        let p = PoolFallbackProvider(pool: makePool(server, enabled: true), deadline: .milliseconds(200))
        let text = try await p.translate("Talk to ⟦0⟧ now, please.", from: "en", to: "tr")
        XCTAssertEqual(text, "")
        XCTAssertEqual(server.translateCalls, 0)
    }

    // MARK: Öneriler ve Sistem sağlığı

    func testTranslationPathRules() {
        typealias R = TranslationNudgeRules
        XCTAssertEqual(R.path(engine: .gemini, readiness: .languagePackMissing(source: "en", target: "tr"),
                              sharePool: true, sourceLanguage: "en"), .engine(.gemini))
        XCTAssertEqual(R.path(engine: nil, readiness: .ready, sharePool: true, sourceLanguage: "en"), .poolAndDevice)
        XCTAssertEqual(R.path(engine: nil, readiness: .ready, sharePool: false, sourceLanguage: "en"), .deviceOnly)
        let missing = R.path(engine: nil, readiness: .languagePackMissing(source: "en", target: "tr"),
                             sharePool: true, sourceLanguage: "en")
        XCTAssertEqual(missing, .poolOnly(packMissing: true))
        XCTAssertEqual(missing.level, .fair)
        XCTAssertEqual(R.path(engine: nil, readiness: .languagePackMissing(source: "en", target: "tr"),
                              sharePool: false, sourceLanguage: "en").level, .problem)
        XCTAssertEqual(R.path(engine: nil, readiness: .ready, sharePool: true, sourceLanguage: "en").level, .good)
    }

    @MainActor
    func testHealthTranslatorRowShowsPath() {
        let state = AppState()
        state.translator = .languagePackMissing(source: "en", target: "tr")
        let row = HealthChecks.translatorRow(state, locale: Locale(identifier: "tr"))
        XCTAssertEqual(row.value, "Dil paketi eksik: yalnız Nino havuzu")
        XCTAssertEqual(row.level, .fair)
        XCTAssertNotNil(row.advice)
        state.translator = .ready
        XCTAssertEqual(HealthChecks.translatorRow(state, locale: Locale(identifier: "tr")).value,
                       "Anahtar yok: Nino havuzu + bu Mac'in çevirisi")
        state.settings.onlineTranslation = true
        state.settings.onlineEngine = .gemini
        state.settingsStatus.savedKeys = [.gemini]
        let ready = HealthChecks.translatorRow(state, locale: Locale(identifier: "tr"))
        XCTAssertEqual(ready.level, .good)
        XCTAssertTrue(ready.value.contains("Gemini"))
    }

    @MainActor
    func testKeySuggestionRules() throws {
        let suite = "nino-nudge-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState()
        state.nudges.attach(defaults: defaults)
        state.setupStep = .done
        state.game = RecognizedGame(id: "hollow-knight-silksong", name: "Hollow Knight Silksong", poolFirst: false,
                                    evidence: .screen)
        XCTAssertEqual(state.keySuggestionGame?.id, "hollow-knight-silksong")

        // Paketli, havuz öncelikli, tahmini oyun ya da anahtar varken yok.
        state.settingsStatus.gamePacks = [GamePackInfo(id: "x", name: "Hollow Knight Silksong", lines: 10)]
        XCTAssertNil(state.keySuggestionGame)
        state.settingsStatus.gamePacks = []
        state.game?.poolFirst = true
        XCTAssertNil(state.keySuggestionGame)
        state.game?.poolFirst = false
        state.game?.evidence = .lastPlayed
        XCTAssertNil(state.keySuggestionGame)
        state.game?.evidence = .console
        state.settings.onlineTranslation = true
        state.settings.onlineEngine = .deepl
        state.settingsStatus.savedKeys = [.deepl]
        XCTAssertNil(state.keySuggestionGame)
        state.settings.onlineTranslation = false
        XCTAssertNotNil(state.keySuggestionGame)

        // Kapatılınca o oyunda bir daha çıkmaz (kalıcı).
        state.nudges.dismissKeySuggestion(gameID: "hollow-knight-silksong")
        XCTAssertNil(state.keySuggestionGame)
        let again = AppState()
        again.nudges.attach(defaults: defaults)
        XCTAssertTrue(again.nudges.dismissedKeyGames.contains("hollow-knight-silksong"))

        // Dil paketi önerisi bir kez.
        state.translator = .languagePackMissing(source: "en", target: "tr")
        XCTAssertTrue(state.offersLanguagePack)
        state.nudges.markLanguagePackOffered()
        XCTAssertFalse(state.offersLanguagePack)
        let third = AppState()
        third.nudges.attach(defaults: defaults)
        third.setupStep = .done
        third.translator = .languagePackMissing(source: "en", target: "tr")
        XCTAssertFalse(third.offersLanguagePack)
    }

    // MARK: Yardımcılar

    private func makePool(_ server: FakePoolServer, enabled: Bool) -> PoolClient {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nino-fallback-\(UUID().uuidString)")
        let config = PoolConfiguration(baseURL: URL(string: "https://pool.invalid")!, enabled: enabled, appVersion: "test")
        return PoolClient(configuration: config, transport: server,
                          translations: PoolTranslations(root: root, language: "tr"), install: "test-install")
    }

    private func build(pool server: FakePoolServer, device: TranslationProvider?,
                       sharePool: Bool = true) async -> TranslatorFactory.Built {
        var settings = MacSettings()
        settings.sharePool = sharePool
        settings.onlineTranslation = true
        settings.onlineEngine = .gemini   // anahtar yok: çevrimiçi motor devrede değil
        let input = TranslatorFactory.Inputs(
            settings: settings, library: LegacyLibrary(), pool: makePool(server, enabled: sharePool), queue: nil,
            cacheDirectory: nil, secrets: MemorySecretStore(), providerTransport: URLSession.shared,
            deviceProvider: device, onAlert: { _, _ in })
        return await TranslatorFactory().build(input)
    }
}

/// `/v1/translate` sorusuna sabit cevap veren sahte havuz sunucusu (ağ yok).
final class FakePoolServer: PoolTransport, @unchecked Sendable {
    let answer: String?
    private let lock = NSLock()
    private var calls = 0
    private var sent: [URLRequest] = []
    var translateCalls: Int { lock.withLock { calls } }
    var requests: [URLRequest] { lock.withLock { sent } }

    init(answer: String?) { self.answer = answer }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        lock.withLock { sent.append(request) }
        let body: [String: Any]
        if url.path.hasSuffix("/v1/translate") {
            lock.withLock { calls += 1 }
            body = ["ok": true, "translations": [["text": answer as Any? ?? NSNull()]]]
        } else {
            body = ["ok": true]
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private struct FakeDevice: TranslationProvider {
    let result: Result<String, Error>
    var name: String { "device" }
    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        try result.get()
    }
}
