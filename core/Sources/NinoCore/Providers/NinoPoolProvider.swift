// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Nino'nun ücretsiz havuz sunucusuna anında çeviri sorusu (`POST /v1/translate`).
/// Sunucu adresi yapılandırmayla gelir; kodda adres yoktur.
public struct NinoPoolProvider: TranslationProvider {
    public struct Config: Sendable {
        public var baseURL: URL
        public var install: String
        public var app: String
        public var platform: String
        public var timeout: TimeInterval

        public init(baseURL: URL, install: String, app: String, platform: String = "mac", timeout: TimeInterval = 20) {
            self.baseURL = baseURL
            self.install = install
            self.app = app
            self.platform = platform
            self.timeout = timeout
        }
    }

    public struct Answer: Equatable, Sendable {
        /// İstekle aynı sırada; sunucu çeviremediyse `nil`.
        public let translations: [String?]
        /// Sunucunun satırdan tanıdığı oyun.
        public let game: String?
    }

    public let config: Config
    private let transport: ProviderTransport

    public var name: String { "pool" }

    public init(config: Config, transport: ProviderTransport = URLSession.shared) {
        self.config = config
        self.transport = transport
    }

    public func translate(_ text: String, from source: String, to target: String) async throws -> String {
        let a = try await ask(lines: [text], context: [], language: target, game: nil)
        guard let t = a.translations.first ?? nil, !t.isEmpty else { throw ProviderFailure.notReady }
        return t
    }

    /// Sunucu `game`i yalnız kimlik biçiminde (`^[a-z0-9][a-z0-9._-]{0,63}$`) kabul eder; ad kimliğe çevrilir.
    /// Sunucu istekte en çok 12 satır alır (fazlası 413).
    public func makeRequest(lines: [String], context: [String], language: String, game: String?) -> URLRequest {
        let body: [String: Any] = [
            "v": 1, "install": config.install, "app": config.app, "platform": config.platform,
            "lang": TargetLanguage.normalize(language), "game": game.flatMap(GameIDs.id) ?? "",
            "lines": lines, "context": context,
        ]
        return .providerJSONPost(config.baseURL.appendingPathComponent("v1/translate"), body: body, headers: [:], timeout: config.timeout)
    }

    public func ask(lines: [String], context: [String], language: String, game: String?) async throws -> Answer {
        let r = makeRequest(lines: lines, context: context, language: language, game: game)
        let data: Data, response: HTTPURLResponse
        do { (data, response) = try await transport.send(r) } catch {
            throw ProviderErrorClassifier.classify(transportError: error)
        }
        guard response.statusCode == 200 else { throw ProviderFailure.server(response.statusCode) }
        guard let root = ProviderJSON.object(data) as? [String: Any], root["ok"] as? Bool != false,
              let list = root["translations"] as? [Any] else { throw ProviderFailure.badResponse }
        var out: [String?] = list.map { item in
            guard let t = (item as? [String: Any])?["text"] as? String, !t.isEmpty else { return nil }
            return t
        }
        if out.count < lines.count { out += Array(repeating: nil, count: lines.count - out.count) }
        let g = (root["game"] as? String).flatMap(GameIDs.id)
        return Answer(translations: Array(out.prefix(lines.count)), game: g)
    }

    /// Süreli soru: süre (100–10 000 ms) dolunca `nil` döner; istek sürer, geç gelen
    /// yanıt `onLate` ile verilir (havuz deposuna yazmak için).
    public func ask(lines: [String], context: [String], language: String, game: String?, deadlineMs: Int,
                    onLate: @escaping @Sendable (Answer) -> Void) async -> Answer? {
        let ms = min(10_000, max(100, deadlineMs))
        let once = ProviderOnceFlag()
        return await withCheckedContinuation { (cont: CheckedContinuation<Answer?, Never>) in
            Task {
                let a = try? await ask(lines: lines, context: context, language: language, game: game)
                if once.claim() { cont.resume(returning: a) } else if let a { onLate(a) }
            }
            Task {
                try? await Task.sleep(for: .milliseconds(ms))
                if once.claim() { cont.resume(returning: nil) }
            }
        }
    }
}

final class ProviderOnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func claim() -> Bool { lock.withLock { defer { used = true }; return !used } }
}
