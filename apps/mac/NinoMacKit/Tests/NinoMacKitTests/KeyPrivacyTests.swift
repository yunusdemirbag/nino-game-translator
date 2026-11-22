// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore
import XCTest
@testable import NinoMacKit

/// Kullanıcının API anahtarı yalnız bu Mac'in kasasında durur ve yalnız seçilen sağlayıcının kendi adresine gider:
/// havuz sunucusuna, ayarlara, günlüklere, "Ayrıntılar"a ve sorun bildirimi gövdesine girmez.
@MainActor
final class KeyPrivacyTests: XCTestCase {
    private let secret = "NINO-TEST-SECRET-7f3a9c"
    private let line = "We need to get out of the city before the storm hits."

    func testKeyGoesOnlyToItsProvider() async throws {
        let cases: [(MacSettings.OnlineEngine, Set<String>)] = [
            (.gemini, ["generativelanguage.googleapis.com"]),
            // OpenAI: NinoCore'un yerleşik model listesi şu an boş, zincire hiç girmiyor (istek yok).
            (.claude, ["api.anthropic.com"]),
            (.deepl, ["api.deepl.com", "api-free.deepl.com"]),
        ]
        for (engine, hosts) in cases {
            let providerNet = RecordingTransport()
            let pool = FakePoolServer(answer: "Fırtına vurmadan şehirden çıkmalıyız.")
            var s = MacSettings()
            s.onlineTranslation = true
            s.onlineEngine = engine
            let secrets = MemorySecretStore([TranslatorFactory.account(for: engine): secret])
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("nino-keyp-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let client = PoolClient(configuration: PoolConfiguration(baseURL: URL(string: "https://pool.invalid")!,
                                                                     appVersion: "test"),
                                    transport: pool, translations: PoolTranslations(root: root, language: "tr"),
                                    install: "test-install")
            let input = TranslatorFactory.Inputs(settings: s, library: LegacyLibrary(), pool: client, queue: nil,
                                                 cacheDirectory: nil, secrets: secrets, providerTransport: providerNet,
                                                 deviceProvider: nil, onAlert: { _, _ in })
            let built = await TranslatorFactory().build(input)
            XCTAssertEqual(built.onlineEngine, engine)
            _ = await built.translator.translate(line + " (\(engine.rawValue))")

            let sent = providerNet.requests
            XCTAssertFalse(sent.isEmpty, "\(engine): sağlayıcıya istek gitmeli")
            for r in sent {
                XCTAssertTrue(hosts.contains(r.url?.host ?? ""), "\(engine): beklenmeyen adres \(r.url?.absoluteString ?? "")")
                XCTAssertFalse(r.url?.absoluteString.contains(secret) ?? false, "\(engine): anahtar adreste olmamalı")
            }
            for r in pool.requests {
                XCTAssertFalse(Self.contains(r, secret), "\(engine): anahtar havuz sunucusuna gitmemeli")
            }
            XCTAssertFalse(pool.requests.isEmpty, "\(engine): havuz yedeği soruldu (anahtarsız metinle)")
        }
    }

    func testSavedKeyStaysInVaultOnly() async throws {
        let suite = "nino-keyp-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nino-keyp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = DataFolder(support: root, logs: root)
        var env = LiveEngineEnvironment(
            identity: AppIdentity(flavor: .testing, defaultsDomain: suite, keychainService: "test", folderName: "test"),
            folder: folder, settingsStore: SettingsStore(defaults: defaults), vault: MemoryVault(),
            ports: .ephemeral, appVersion: "4.1.0", poolBaseURL: nil, packsBaseURL: nil, poolTransport: nil,
            providerTransport: RecordingTransport(), deviceProvider: { nil },
            textReader: SessionOverlaysTests.FailingReader(fail: false),
            clock: GameReading.SystemClock(), checksTranslatorReadiness: false)
        env.keyCheck = { _, _ in (.valid, "Örnek.") }
        let state = AppState()
        let engine = LiveEngine(state: state, environment: env)
        engine.saveGeminiKey(secret)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !state.setup.geminiKeySaved { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(state.setup.geminiKeySaved)
        XCTAssertEqual(try engine.records.translationKey(.gemini), secret, "anahtar kasada")

        // Ayarlar (UserDefaults) ve veri klasöründeki hiçbir dosya (günlükler dahil) anahtarı içermez.
        let domain = defaults.persistentDomain(forName: suite) ?? [:]
        let defaultsText = String(describing: domain)
            + String(decoding: (try? PropertyListSerialization.data(fromPropertyList: domain, format: .xml,
                                                                    options: 0)) ?? Data(), as: UTF8.self)
        XCTAssertFalse(defaultsText.contains(secret), "anahtar ayarlara yazılmamalı")
        XCTAssertFalse(String(decoding: state.settings.encoded(), as: UTF8.self).contains(secret))
        if let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in files {
                let data = (try? Data(contentsOf: url)) ?? Data()
                XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(secret), "anahtar \(url.lastPathComponent) içinde")
            }
        }

        // Sistem sağlığı "Ayrıntılar" ve sorun bildirimi gövdesi (günlüklerle birlikte).
        let facts = DeviceFacts(appVersion: "4.1.0", build: "1", model: "Mac", systemVersion: "26", processor: "M",
                                memoryGB: 16)
        let details = DetailsText.make(state: state, facts: facts, metrics: HealthMetrics(), tvApp: .unknown,
                                       folder: folder)
        XCTAssertFalse(details.contains(secret))
        let device = DeviceInfo.make(state: state, facts: facts, tvApp: .unknown)
        let report = ProblemReport(kind: .user, description: "çeviri yok", findings: details,
                                   logs: ReportLogs.collect(folder: folder, facts: facts),
                                   device: String(describing: device))
        let body = try ReportContract.body(report, context: ReportContext(install: "i", app: "4.1.0", language: "tr"))
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(secret), "anahtar sorun bildirimine girmemeli")
    }

    static func contains(_ r: URLRequest, _ s: String) -> Bool {
        if r.url?.absoluteString.contains(s) == true { return true }
        if (r.allHTTPHeaderFields ?? [:]).contains(where: { $0.value.contains(s) || $0.key.contains(s) }) { return true }
        return String(decoding: r.httpBody ?? Data(), as: UTF8.self).contains(s)
    }
}

/// Sağlayıcı isteklerini kaydeder, hepsine 500 döner (ağ yok).
final class RecordingTransport: ProviderTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var list: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { list } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { list.append(request) }
        return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
    }
}
