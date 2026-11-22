// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// DeepL hesabının kullanımı.
public struct DeepLUsage: Equatable, Sendable {
    public let characterCount: Int
    public let characterLimit: Int
    public var exhausted: Bool { characterLimit > 0 && characterCount >= characterLimit }
}

/// Kullanıcının kendi DeepL anahtarıyla çeviri. Hedef `tr` iken sözlük terimleri
/// `<x>…</x>` etiketiyle sabitlenir.
public struct DeepLProvider: TranslationProvider {
    public static let freeBase = URL(string: "https://api-free.deepl.com/v2/")!
    public static let proBase = URL(string: "https://api.deepl.com/v2/")!

    public let apiKey: String
    public let glossary: Glossary?
    public let timeout: TimeInterval
    public let health: ProviderHealth
    private let transport: ProviderTransport

    public var name: String { EngineName.deepL }

    public init(apiKey: String, glossary: Glossary? = nil, timeout: TimeInterval = 4,
                transport: ProviderTransport = URLSession.shared, health: ProviderHealth = ProviderHealth()) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.glossary = glossary
        self.timeout = timeout
        self.transport = transport
        self.health = health
    }

    public static func baseURL(for key: String) -> URL {
        key.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(":fx") ? freeBase : proBase
    }

    public static func supports(_ target: String) -> Bool { TargetLanguage.find(target)?.deepLSupported ?? false }

    /// Önbellek anahtarı: satırda sözlük terimi varsa sözlük izi ön eki.
    public func cacheKey(_ line: String) -> String {
        guard let glossary, glossary.containsTerm(line) else { return line }
        return EngineCacheKey.deepL(line, fingerprint: glossary.fingerprint)
    }

    public func translate(_ text: String, from source: String, to target: String) async throws -> String {
        let out = try await translate(sentences: [text], context: [], target: target)
        guard let first = out.first, !first.isEmpty else { throw ProviderFailure.badResponse }
        return first
    }

    public func translate(sentences: [String], context: [String], target: String, probe: Bool = false) async throws -> [String] {
        guard !sentences.isEmpty else { return [] }
        guard !apiKey.isEmpty, Self.supports(target) else { throw ProviderFailure.notReady }
        if !probe, await health.isResting { throw ProviderFailure.notReady }
        let (request, tagged) = makeRequest(sentences: sentences, context: context, target: target)
        do {
            let data: Data, response: HTTPURLResponse
            do { (data, response) = try await transport.send(request) } catch {
                throw ProviderErrorClassifier.classify(transportError: error)
            }
            if let f = ProviderErrorClassifier.classifyDeepL(status: response.statusCode) { throw f }
            guard let root = ProviderJSON.object(data) as? [String: Any],
                  let list = root["translations"] as? [[String: Any]], list.count == sentences.count else {
                throw ProviderFailure.badResponse
            }
            let out = list.map { item -> String in
                let t = item["text"] as? String ?? ""
                return tagged ? Self.untag(t) : t
            }
            if !probe { await health.recordSuccess() }
            return out
        } catch let failure as ProviderFailure {
            if !probe { await health.record(failure) }
            throw failure
        }
    }

    /// İstek ve terim etiketi kullanılıp kullanılmadığı.
    public func makeRequest(sentences: [String], context: [String], target: String) -> (URLRequest, Bool) {
        let code = TargetLanguage.normalize(target)
        var texts = sentences
        var tagged = false
        if code == "tr", let glossary {
            let tags = sentences.map { Self.tagTerms($0, glossary) }
            if tags.contains(where: { $0 != nil }) {
                tagged = true
                texts = zip(sentences, tags).map { $1 ?? Self.escape($0) }
            }
        }
        var body: [String: Any] = [
            "text": texts, "source_lang": "EN", "target_lang": code.uppercased(), "preserve_formatting": true,
        ]
        if code == "tr" { body["formality"] = "prefer_less" }
        if !context.isEmpty { body["context"] = context.joined(separator: "\n") }
        if tagged {
            body["tag_handling"] = "xml"
            body["ignore_tags"] = ["x"]
        }
        let url = Self.baseURL(for: apiKey).appendingPathComponent("translate")
        let req = URLRequest.providerJSONPost(url, body: body, headers: ["Authorization": "DeepL-Auth-Key \(apiKey)"], timeout: timeout)
        return (req, tagged)
    }

    /// Terimleri Türkçesiyle `<x>…</x>` içine alır, gerisini XML için kaçışlar. Terim yoksa `nil`.
    public static func tagTerms(_ sentence: String, _ glossary: Glossary) -> String? {
        let matches = glossary.matches(in: sentence)
        guard !matches.isEmpty else { return nil }
        var out = ""
        var cursor = sentence.startIndex
        for m in matches {
            out += escape(String(sentence[cursor..<m.range.lowerBound]))
            out += "<x>" + escape(m.term.turkish) + "</x>"
            cursor = m.range.upperBound
        }
        out += escape(String(sentence[cursor...]))
        return out
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func untag(_ s: String) -> String {
        s.replacingOccurrences(of: "<x>", with: "").replacingOccurrences(of: "</x>", with: "")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// `GET …/usage`.
    public func usage() async throws -> DeepLUsage {
        var r = URLRequest(url: Self.baseURL(for: apiKey).appendingPathComponent("usage"), timeoutInterval: timeout)
        r.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        let data: Data, response: HTTPURLResponse
        do { (data, response) = try await transport.send(r) } catch {
            throw ProviderErrorClassifier.classify(transportError: error)
        }
        if let f = ProviderErrorClassifier.classifyDeepL(status: response.statusCode) { throw f }
        guard let root = ProviderJSON.object(data) as? [String: Any],
              let count = root["character_count"] as? Int, let limit = root["character_limit"] as? Int else {
            throw ProviderFailure.badResponse
        }
        return DeepLUsage(characterCount: count, characterLimit: limit)
    }
}
