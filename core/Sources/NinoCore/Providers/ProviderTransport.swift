// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Çevirmenlerin ağ kapısı. Uygulamada `URLSession`, testlerde sahte taşıyıcı.
public protocol ProviderTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: ProviderTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderFailure.badResponse }
        return (data, http)
    }
}

/// Sıralı anahtarlı JSON gövdesi (önbellek ve test kararlılığı için).
enum ProviderJSON {
    static func body(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }

    static func object(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}

extension URLRequest {
    static func providerJSONPost(_ url: URL, body: Any, headers: [String: String], timeout: TimeInterval) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        r.httpBody = ProviderJSON.body(body)
        return r
    }
}
