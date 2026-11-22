// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Ayarla tarif edilen genel bir HTTP çevirmen sağlayıcısı. Adres, gövde şablonu
/// ve cevaptaki yol ayarlardan gelir; kodda hiçbir hizmetin adı ya da anahtarı yoktur.
///
/// Şablonlarda `{text}`, `{source}`, `{target}` ve `{key}` yer tutucuları kullanılır.
/// Gövde şablonunda değerler JSON için kaçışlanır; adres şablonunda URL için kodlanır.
public struct HTTPTranslationProvider: TranslationProvider {
    public struct Configuration: Codable, Equatable, Sendable {
        public var name: String
        public var urlTemplate: String
        public var method: String
        public var headers: [String: String]
        public var bodyTemplate: String?
        /// Cevap JSON'unda çeviriye giden yol. Sayılar dizi sırasıdır: `["data", "0", "text"]`.
        public var responsePath: [String]

        public init(name: String, urlTemplate: String, method: String = "POST",
                    headers: [String: String] = ["Content-Type": "application/json"],
                    bodyTemplate: String? = nil, responsePath: [String]) {
            self.name = name
            self.urlTemplate = urlTemplate
            self.method = method
            self.headers = headers
            self.bodyTemplate = bodyTemplate
            self.responsePath = responsePath
        }
    }

    public let configuration: Configuration
    private let apiKey: String?
    private let session: URLSession

    public var name: String { configuration.name }

    public init(configuration: Configuration, apiKey: String? = nil, session: URLSession = .shared) {
        self.configuration = configuration
        self.apiKey = apiKey
        self.session = session
    }

    public func translate(_ text: String, from source: String, to target: String) async throws -> String {
        let values = ["text": text, "source": source, "target": target, "key": apiKey ?? ""]
        let urlString = Self.fill(configuration.urlTemplate, values) { v in
            v.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? v
        }
        guard let url = URL(string: urlString) else { throw TranslationProviderError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = configuration.method
        for (k, v) in configuration.headers { request.setValue(Self.fill(v, values) { $0 }, forHTTPHeaderField: k) }
        if let body = configuration.bodyTemplate {
            request.httpBody = Data(Self.fill(body, values, escape: Self.jsonEscape).utf8)
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslationProviderError.http(http.statusCode)
        }
        guard let value = try? Self.extract(data, path: configuration.responsePath) else {
            throw TranslationProviderError.badResponse
        }
        guard !value.isEmpty else { throw TranslationProviderError.emptyResult }
        return value
    }

    static func fill(_ template: String, _ values: [String: String], escape: (String) -> String) -> String {
        var s = template
        for (k, v) in values { s = s.replacingOccurrences(of: "{\(k)}", with: escape(v)) }
        return s
    }

    static func jsonEscape(_ s: String) -> String {
        guard let data = try? JSONEncoder().encode(s), let quoted = String(data: data, encoding: .utf8) else { return s }
        return String(quoted.dropFirst().dropLast())
    }

    static func extract(_ data: Data, path: [String]) throws -> String? {
        var node: Any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        for step in path {
            if let i = Int(step), let array = node as? [Any] {
                guard i >= 0, i < array.count else { return nil }
                node = array[i]
            } else if let dict = node as? [String: Any], let next = dict[step] {
                node = next
            } else {
                return nil
            }
        }
        if let s = node as? String { return s }
        // Bazı cevaplar parçalı dizi verir: ["Mer", "haba"].
        if let parts = node as? [String] { return parts.joined() }
        return nil
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?#")
        return set
    }()
}
