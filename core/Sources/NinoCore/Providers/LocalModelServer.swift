// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Bilgisayardaki yerel model sunucusu (Ollama, LM Studio; OpenAI uyumlu).
public enum LocalModelServer {
    public static let defaultModel = "translategemma:4b"
    public static let defaultAddress = "http://localhost:11434/v1"

    public enum Kind: String, Sendable { case ollama, lmStudio, other }

    public struct Suggestion: Equatable, Sendable {
        public let model: String
        public let sizeGB: Double
        public let recommended: Bool
        public let minimumMemoryGB: Int?
    }

    public static let suggestions: [Suggestion] = [
        .init(model: "translategemma:4b", sizeGB: 3.3, recommended: true, minimumMemoryGB: nil),
        .init(model: "translategemma:12b", sizeGB: 8.1, recommended: false, minimumMemoryGB: 16),
    ]

    /// Kullanıcının yazdığı adresi düzeltir; geçersizse `nil`.
    public static func normalize(_ input: String) -> URL? {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains(where: \.isWhitespace) else { return nil }
        let withScheme = raw.contains("://") ? raw : "http://" + raw
        guard var c = URLComponents(string: withScheme),
              let scheme = c.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = c.host, !host.isEmpty else { return nil }
        var path = c.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.lowercased().hasSuffix("/chat/completions") { path.removeLast("/chat/completions".count) }
        while path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty { path = "/v1" }
        c.scheme = scheme
        c.path = path
        c.query = nil
        c.fragment = nil
        return c.url
    }

    public static func kind(_ url: URL) -> Kind {
        switch url.port {
        case 11434: return .ollama
        case 1234: return .lmStudio
        default: return .other
        }
    }

    /// Boş ya da eski varsayılan (`qwen2.5:7b`) ise yeni varsayılan.
    public static func modelName(_ saved: String?) -> String {
        let m = saved?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return m.isEmpty || m == "qwen2.5:7b" ? defaultModel : m
    }

    /// Kök adres: sondaki `/v1` atılmış hâli.
    public static func root(_ base: URL) -> URL {
        var s = base.absoluteString
        if s.hasSuffix("/v1") { s.removeLast(3) }
        return URL(string: s) ?? base
    }

    /// `model` ile `model:latest` aynıdır; büyük/küçük harf fark etmez.
    public static func sameModel(_ a: String, _ b: String) -> Bool {
        func n(_ s: String) -> String {
            let l = s.lowercased()
            return l.hasSuffix(":latest") ? String(l.dropLast(7)) : l
        }
        return n(a) == n(b)
    }

    /// Kurulu modeller: `GET <kök>/api/tags` (3 sn).
    public static func installedModels(base: URL, transport: ProviderTransport = URLSession.shared) async throws -> [String] {
        let r = URLRequest(url: root(base).appendingPathComponent("api/tags"), timeoutInterval: 3)
        let data: Data, response: HTTPURLResponse
        do { (data, response) = try await transport.send(r) } catch {
            throw ProviderErrorClassifier.classify(transportError: error)
        }
        guard (200..<300).contains(response.statusCode) else { throw ProviderFailure.server(response.statusCode) }
        guard let root = ProviderJSON.object(data) as? [String: Any], let models = root["models"] as? [[String: Any]] else {
            throw ProviderFailure.badResponse
        }
        return models.compactMap { ($0["name"] as? String) ?? ($0["model"] as? String) }
    }

    /// İndirme isteği: `POST <kök>/api/pull` (1 saat), satır satır JSON akar.
    public static func pullRequest(base: URL, model: String) -> URLRequest {
        .providerJSONPost(root(base).appendingPathComponent("api/pull"), body: ["model": model, "stream": true],
                  headers: [:], timeout: 3600)
    }

    /// İndirme ilerlemesi: parça başına `total`/`completed`.
    public struct PullProgress: Sendable {
        public enum State: Equatable, Sendable { case running(Double), done, failed(String) }
        private var totals: [String: Double] = [:]
        private var done: [String: Double] = [:]

        public init() {}

        public mutating func feed(_ line: String) -> State {
            guard let o = ProviderJSON.object(Data(line.utf8)) as? [String: Any] else { return .running(progress) }
            if let e = o["error"] as? String { return .failed(e) }
            if o["status"] as? String == "success" { return .done }
            if let d = o["digest"] as? String {
                if let t = (o["total"] as? NSNumber)?.doubleValue { totals[d] = t }
                if let c = (o["completed"] as? NSNumber)?.doubleValue { done[d] = c }
            }
            return .running(progress)
        }

        public var progress: Double {
            let t = totals.values.reduce(0, +)
            guard t > 0 else { return 0 }
            return min(0.99, done.values.reduce(0, +) / t)
        }
    }
}
