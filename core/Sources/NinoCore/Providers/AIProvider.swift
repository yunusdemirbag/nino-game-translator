// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Kullanıcının kendi anahtarıyla çalışan yapay zekâ hizmetleri. Ham değerler
/// önbellek motor adına (`<hizmet>:<model>`) ve eski ayar kayıtlarına girer.
public enum AIService: String, CaseIterable, Sendable {
    case gemini, openai, claude, local
}

public struct AIProviderConfig: Sendable {
    public var service: AIService
    public var model: AIModel
    /// Baş/son boşluk kırpılarak kullanılır. Yerel modelde boş olabilir.
    public var apiKey: String?
    /// Yalnız yerel model: düzeltilmiş adres (`LocalModelServer.normalize`).
    public var localBaseURL: URL?
    public var maxOutputTokens: Int
    /// `nil`: bulut 5 sn, yerel 15 sn.
    public var timeout: TimeInterval?

    public init(service: AIService, model: AIModel, apiKey: String? = nil, localBaseURL: URL? = nil,
                maxOutputTokens: Int = 1024, timeout: TimeInterval? = nil) {
        self.service = service
        self.model = model
        self.apiKey = apiKey
        self.localBaseURL = localBaseURL
        self.maxOutputTokens = maxOutputTokens
        self.timeout = timeout
    }

    var key: String { apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

    /// Bulutta anahtar kayıtlı; yerelde adres ve model adı geçerli.
    public var isReady: Bool {
        switch service {
        case .local: return localBaseURL != nil && !model.id.trimmingCharacters(in: .whitespaces).isEmpty
        default: return !key.isEmpty
        }
    }
}

/// Gemini / OpenAI / Claude / yerel model (OpenAI uyumlu) çevirmeni. Eksik
/// cümleler tek istekte JSON dizisi olarak gider, aynı sırada dizi beklenir.
public struct AIProvider: TranslationProvider {
    public static let geminiBase = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/")!
    public static let openAIURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    public static let claudeURL = URL(string: "https://api.anthropic.com/v1/messages")!

    public let config: AIProviderConfig
    public let health: ProviderHealth
    private let transport: ProviderTransport
    private let budget: RequestBudget

    public var name: String { "ai-\(config.service.rawValue)" }

    /// Önbellek motor adı.
    public var engineName: String {
        if config.service == .local, let url = config.localBaseURL { return EngineName.local(baseURL: url, model: config.model.id) }
        return EngineName.ai(config.service.rawValue, model: config.model.id)
    }

    public init(config: AIProviderConfig, transport: ProviderTransport = URLSession.shared,
                budget: RequestBudget = .shared, health: ProviderHealth = ProviderHealth()) {
        self.config = config
        self.transport = transport
        self.budget = budget
        self.health = health
    }

    public func translate(_ text: String, from source: String, to target: String) async throws -> String {
        let out = try await translate(sentences: [text], context: [], game: nil, target: target)
        guard let first = out.first, !first.isEmpty else { throw ProviderFailure.badResponse }
        return first
    }

    /// `probe`: anahtar denemesi; dakikalık hak yemez, dinlenmeye bakmaz, sağlığı değiştirmez.
    public func translate(sentences: [String], context: [ContextLine], game: String?, target: String,
                          probe: Bool = false) async throws -> [String] {
        guard !sentences.isEmpty else { return [] }
        guard config.isReady, let language = TargetLanguage.find(target) else { throw ProviderFailure.notReady }
        if !probe {
            if await health.isResting { throw ProviderFailure.notReady }
            guard await budget.acquire(engineName, limit: config.model.requestsPerMinute) else { throw ProviderFailure.notReady }
        }
        let request = try makeRequest(sentences: sentences, context: context, game: game, language: language)
        do {
            let data: Data, response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(request)
            } catch {
                throw ProviderErrorClassifier.classify(transportError: error)
            }
            if let failure = ProviderErrorClassifier.classify(status: response.statusCode, body: data) {
                if case let .minuteLimit(_, limit?) = failure { await budget.lower(engineName, to: limit) }
                throw failure
            }
            guard let text = Self.extractText(config.service, data),
                  let list = AIResponseParser.parse(text, expected: sentences.count) else {
                throw ProviderFailure.badResponse
            }
            if !probe { await health.recordSuccess() }
            return list
        } catch let failure as ProviderFailure {
            if !probe { await health.record(failure) }
            throw failure
        }
    }

    // MARK: İstek

    public func makeRequest(sentences: [String], context: [ContextLine], game: String?,
                            language: TargetLanguage) throws -> URLRequest {
        let system = AIPrompt.system(for: language)
        let user = AIPrompt.user(sentences: sentences, context: context, game: game, language: language)
        let model = config.model
        let timeout = config.timeout ?? (config.service == .local ? 15 : 5)
        switch config.service {
        case .gemini:
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            let path = model.id.addingPercentEncoding(withAllowedCharacters: allowed) ?? model.id
            guard let url = URL(string: Self.geminiBase.absoluteString + path + ":generateContent") else {
                throw ProviderFailure.notReady
            }
            var generation: [String: Any] = ["maxOutputTokens": config.maxOutputTokens]
            if let t = model.thinking { generation["thinkingConfig"] = ["thinkingLevel": t] }
            let body: [String: Any] = [
                "systemInstruction": ["parts": [["text": system]]],
                "contents": [["role": "user", "parts": [["text": user]]]],
                "generationConfig": generation,
            ]
            return .providerJSONPost(url, body: body, headers: ["x-goog-api-key": config.key], timeout: timeout)
        case .openai:
            var body: [String: Any] = [
                "model": model.id,
                "messages": [["role": "developer", "content": system], ["role": "user", "content": user]],
                "max_completion_tokens": config.maxOutputTokens,
            ]
            if let e = model.effort { body["reasoning_effort"] = e }
            return .providerJSONPost(Self.openAIURL, body: body, headers: ["Authorization": "Bearer \(config.key)"], timeout: timeout)
        case .claude:
            var body: [String: Any] = [
                "model": model.id,
                "max_tokens": config.maxOutputTokens,
                "system": system,
                "messages": [["role": "user", "content": user]],
            ]
            if let e = model.effort { body["output_config"] = ["effort": e] }
            if let t = model.thinking { body["thinking"] = ["type": t] }
            return .providerJSONPost(Self.claudeURL, body: body,
                             headers: ["x-api-key": config.key, "anthropic-version": "2023-06-01"], timeout: timeout)
        case .local:
            guard let base = config.localBaseURL else { throw ProviderFailure.notReady }
            let messages: [[String: String]] = AIPrompt.isTranslationModel(model.id)
                ? AIPrompt.translationModelMessages(sentences: sentences, context: context, model: model.id, language: language)
                : [["role": "system", "content": system], ["role": "user", "content": user]]
            let body: [String: Any] = [
                "model": model.id, "messages": messages, "temperature": 0.2,
                "max_tokens": config.maxOutputTokens, "stream": false,
            ]
            let headers = config.key.isEmpty ? [:] : ["Authorization": "Bearer \(config.key)"]
            return .providerJSONPost(base.appendingPathComponent("chat/completions"), body: body, headers: headers, timeout: timeout)
        }
    }

    // MARK: Yanıt

    /// Yanıttan metin; yoksa ya da boşsa `nil`.
    public static func extractText(_ service: AIService, _ data: Data) -> String? {
        guard let root = ProviderJSON.object(data) as? [String: Any] else { return nil }
        var text: String?
        switch service {
        case .gemini:
            let parts = ((root["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]
            text = parts?.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined()
        case .openai, .local:
            text = ((root["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
        case .claude:
            text = (root["content"] as? [[String: Any]])?.filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }.joined()
        }
        guard let t = text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return t
    }
}
