// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Sayfaların servislerinin ağ kapısı. Uygulamada `URLSessionNetworkClient`, testlerde sahte istemci.
/// Servisler ağa yalnız bunun üstünden çıkar; böylece testte hiçbir istek dışarı gitmez.
public protocol NetworkClient: Sendable {
    /// İsteği gönderir. HTTP olmayan cevapta ya da ağ hatasında hata atar.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public enum NetworkClientError: Error, Equatable {
    case notHTTP
}

/// Çerezsiz, önbelleksiz gerçek istemci.
public struct URLSessionNetworkClient: NetworkClient {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkClientError.notHTTP }
        return (data, http)
    }
}

/// Nino havuz sunucusunun adresi (ninoya-sor.md §4, havuz-paketler.md §6).
public enum PoolServer {
    /// Canlı sunucu.
    public static let liveURL = URL(string: "https://nino-pool.y-demirbag2506.workers.dev")!
    /// Adres değiştirme ayarının kullanıcı tercihindeki adı.
    public static let overrideDefaultsKey = "ninoPoolURL"
    public static let overrideEnvironmentKey = "NINO_POOL_URL"

    /// Sıra: ortam değişkeni → kullanıcı ayarı → canlı adres. `http` ile başlamayan değer atlanır.
    public static func baseURL(environment: [String: String], userValue: String?) -> URL? {
        for candidate in [environment[overrideEnvironmentKey], userValue] {
            guard let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), text.hasPrefix("http"),
                  let url = URL(string: text) else { continue }
            return url
        }
        return liveURL
    }

    /// Kökün altına yol ekler (`v1/assistant`); kökün sonundaki `/` sorun olmaz.
    public static func endpoint(_ base: URL, _ path: String) -> URL {
        let root = String(base.absoluteString.reversed().drop { $0 == "/" }.reversed())
        return URL(string: "\(root)/\(path)") ?? base.appendingPathComponent(path)
    }
}

/// Sıralı anahtarlı, `/` kaçırmayan JSON (sunucu sözleşmesi).
enum ContractJSON {
    static func encode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}

/// Mac'in kurulum kimliği: havuz istemcisinin `pool/state.json`'daki kimliği (veri-uyumu.md §3).
/// Yoksa eski `install` dosyasına bakılır; ikisi de yoksa boş döner (yeni kimliği havuz istemcisi üretir).
public enum InstallIdentity {
    public static func read(folder: DataFolder) -> String {
        if let id = folder.poolState()?.install, UUID(uuidString: id) != nil { return id.lowercased() }
        let legacy = folder.support.appendingPathComponent("install")
        if let text = try? String(contentsOf: legacy, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if UUID(uuidString: trimmed) != nil { return trimmed.lowercased() }
        }
        return ""
    }
}
