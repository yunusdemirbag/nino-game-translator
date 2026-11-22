// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Havuz ve paket sunucusuna giden istekler. Testler sahte taşıyıcı verir.
public protocol PoolTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// `URLSession` ile gerçek ağ.
public struct URLSessionPoolTransport: PoolTransport {
    public let session: URLSession

    public init(session: URLSession) { self.session = session }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Sunucu adresi ve uygulama bilgisi. Adres yalnız buradan gelir; çekirdekte adres yok.
public struct PoolConfiguration: Sendable {
    public var baseURL: URL?
    /// "Ortak havuz" ayarı.
    public var enabled: Bool
    public var platform: String
    public var appVersion: String

    public init(baseURL: URL?, enabled: Bool = true, platform: String = "mac", appVersion: String) {
        self.baseURL = baseURL
        self.enabled = enabled
        self.platform = platform
        self.appVersion = appVersion
    }

    /// Adaylardan ilk geçerli adres (`http`/`https`, makine adı var, doldurulmamış `$(` değil).
    /// Sıra çağıranındır: ortam değişkeni, kullanıcı ayarı, uygulama yapılandırması.
    public static func resolveURL(_ candidates: [String?]) -> URL? {
        for raw in candidates {
            guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, !s.hasPrefix("$("),
                  let url = URL(string: s), let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty else { continue }
            return url
        }
        return nil
    }

    public var userAgent: String { "nino-pool/1 (\(platform); \(appVersion))" }

    /// `nil`: adres yok.
    func request(_ path: String, query: [(String, String)] = [], method: String = "GET",
                 body: Data? = nil, timeout: TimeInterval) -> URLRequest? {
        guard let baseURL else { return nil }
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        guard var components = URLComponents(string: base + path) else { return nil }
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        guard let url = components.url else { return nil }
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.httpMethod = method
        r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }
}

/// Saat, kimlik ve rastgelelik; testlerde sabitlenir.
public struct PoolEnvironment: Sendable {
    public var now: @Sendable () -> Date
    public var uuid: @Sendable () -> UUID
    /// −0.2…0.2 arası.
    public var jitter: @Sendable () -> Double

    public init(now: @escaping @Sendable () -> Date = { Date() },
                uuid: @escaping @Sendable () -> UUID = { UUID() },
                jitter: @escaping @Sendable () -> Double = { Double.random(in: -0.2...0.2) }) {
        self.now = now
        self.uuid = uuid
        self.jitter = jitter
    }
}

/// Kurulum kimliği dosyası: tek satır küçük harf UUID; geçersizse yeniden üretilir.
public enum InstallID {
    public static func load(at url: URL, uuid: () -> UUID = { UUID() }) -> String {
        if let raw = try? String(contentsOf: url, encoding: .utf8) {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if UUID(uuidString: s) != nil { return s.lowercased() }
        }
        let fresh = uuid().uuidString.lowercased()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data((fresh + "\n").utf8).write(to: url, options: .atomic)
        return fresh
    }
}

extension JSONEncoder {
    /// Sunucu gövdeleri: sıralı anahtar, `/` kaçışlanmaz.
    static var pool: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }
}
