// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Nino'nun sunucusu: sorun bildirimi ve "Nino'ya Sor" yardımcısı.
enum NinoServer {
    static var base: URL? {
        let env = ProcessInfo.processInfo.environment["NINO_POOL_URL"]
        let candidates = [env, UserDefaults.standard.string(forKey: "ninoPoolURL"), "https://nino-pool.y-demirbag2506.workers.dev"]
        for c in candidates.compactMap({ $0 }) {
            if let u = URL(string: c), ["http", "https"].contains(u.scheme ?? "") { return u }
        }
        return nil
    }

    /// Kuruluş kimliği: `pool/state.json` içindeki `install` (yoksa üretilip yazılır).
    static func installID(folders: AppFolders) -> String {
        let url = folders.support.appendingPathComponent("pool/state.json")
        if let data = try? Data(contentsOf: url),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let id = json["install"] as? String, !id.isEmpty { return id }
        let id = UUID().uuidString.lowercased()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: ["install": id]) { try? data.write(to: url, options: .atomic) }
        return id
    }

    enum Failure: Error, Equatable { case offline, tooMany, tooLarge, rejected, busy, notReady, server }

    static func post(_ path: String, body: [String: Any], agent: String, timeout: TimeInterval) async throws -> [String: Any] {
        guard let base else { throw Failure.offline }
        var request = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("\(agent) (ios; \(AppInfo.version))", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) } catch { throw Failure.offline }
        let json = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            guard json["ok"] as? Bool == true else { throw Failure.server }
            return json
        case 400: throw Failure.rejected
        case 413: throw Failure.tooLarge
        case 429: throw (json["error"] as? String) == "busy" ? Failure.busy : Failure.tooMany
        case 503: throw (json["error"] as? String) == "assistant_disabled" ? Failure.notReady : Failure.busy
        default: throw Failure.server
        }
    }
}
