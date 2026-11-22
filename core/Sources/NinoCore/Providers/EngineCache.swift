// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import CryptoKit

/// Motor adları (önbellek dosya adına girer; eski dosyalarla birebir aynı).
public enum EngineName {
    /// Cihaz içi; sondaki sayı metin hattı sürümüdür (kurallar değişince artar).
    public static let device = "apple-p3"
    public static let deepL = "deepl"

    /// `<hizmet>:<model>` (ör. `gemini:gemini-3.5-flash-lite`).
    public static func ai(_ service: String, model: String) -> String { "\(service):\(model)" }

    /// `local:<makine>[:<kapı>]/<model>`.
    public static func local(baseURL: URL, model: String) -> String {
        let host = baseURL.host ?? "localhost"
        let port = baseURL.port.map { ":\($0)" } ?? ""
        return "local:\(host)\(port)/\(model)"
    }
}

/// Önbellek anahtarı ön ekleri (U+001F ile).
public enum EngineCacheKey {
    public static let separator = "\u{1F}"

    /// Cihaz içi: cümle; bağlamla çevrildiyse `bağlam␟cümle`; sözlük etkiliyse başta `iz␟`.
    public static func device(_ sentence: String, context: String? = nil, fingerprint: String? = nil) -> String {
        var k = context.map { $0 + separator + sentence } ?? sentence
        if let fingerprint { k = fingerprint + separator + k }
        return k
    }

    /// Yapay zekâ: oyun biliniyorsa `oyun␟metin`.
    public static func ai(_ text: String, game: String? = nil) -> String {
        guard let game, !game.isEmpty else { return text }
        return game + separator + text
    }

    /// DeepL: satırda sözlük terimi varsa `iz␟satır`.
    public static func deepL(_ line: String, fingerprint: String?) -> String {
        guard let fingerprint else { return line }
        return fingerprint + separator + line
    }
}

/// Motor ve dil çifti başına ayrı JSONL dosyası (`["anahtar","çeviri"]` satırları).
/// Mevcut `TranslationCache`'ten bağımsızdır; onu değiştirmez.
public actor EngineCache {
    public static func fileName(engine: String, source: String, target: String) -> String {
        let plain = [engine, source, target].allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
        }
        if plain { return "v1-\(engine)-\(source)-\(target).jsonl" }
        let digest = SHA256.hash(data: Data((engine + "\0" + source + "\0" + target).utf8))
        return "v1h-" + digest.map { String(format: "%02x", $0) }.joined() + ".jsonl"
    }

    public let fileURL: URL?
    public let capacity: Int
    private var entries: [String: (text: String, use: UInt64)] = [:]
    private var tick: UInt64 = 0
    private var lineCount = 0
    private var loaded = false
    private var diskOK = true

    public init(fileURL: URL?, capacity: Int = 20_000) {
        self.fileURL = fileURL
        self.capacity = max(10, capacity)
    }

    public var count: Int { loadIfNeeded(); return entries.count }

    public func lookup(_ key: String) -> String? {
        loadIfNeeded()
        guard let e = entries[key] else { return nil }
        tick += 1
        entries[key] = (e.text, tick)
        return e.text
    }

    public func store(_ key: String, _ text: String) {
        loadIfNeeded()
        guard !key.isEmpty, !text.isEmpty else { return }
        tick += 1
        if entries[key]?.text == text {
            entries[key] = (text, tick)
            return
        }
        entries[key] = (text, tick)
        append([key, text])
        evictIfNeeded()
        if lineCount >= capacity * 2 { rewrite() }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        for line in data.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            lineCount += 1
            guard let pair = ProviderJSON.object(Data(line)) as? [Any], pair.count >= 2,
                  let k = pair[0] as? String, let v = pair[1] as? String, !k.isEmpty, !v.isEmpty else { continue }
            tick += 1
            entries[k] = (v, tick)
        }
        evictIfNeeded()
        if lineCount - entries.count > capacity / 2 { rewrite() }
    }

    private func evictIfNeeded() {
        guard entries.count > capacity else { return }
        let drop = entries.count - capacity + capacity / 10
        for (k, _) in entries.sorted(by: { $0.value.use < $1.value.use }).prefix(drop) { entries[k] = nil }
    }

    static func line(_ pair: [String]) -> Data {
        var d = (try? JSONSerialization.data(withJSONObject: pair, options: [.withoutEscapingSlashes])) ?? Data()
        d.append(UInt8(ascii: "\n"))
        return d
    }

    private func append(_ pair: [String]) {
        guard let fileURL, diskOK else { return }
        do {
            let fm = FileManager.default
            if !fm.fileExists(atPath: fileURL.path) {
                try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data().write(to: fileURL)
            }
            let h = try FileHandle(forWritingTo: fileURL)
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: Self.line(pair))
            lineCount += 1
        } catch {
            diskOK = false // bellekte sürer
        }
    }

    private func rewrite() {
        guard let fileURL, diskOK else { return }
        var data = Data()
        let ordered = entries.sorted { $0.value.use < $1.value.use }
        for (k, v) in ordered { data.append(Self.line([k, v.text])) }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            lineCount = ordered.count
        } catch {
            diskOK = false
        }
    }
}

/// Motor anahtarlı sarmalayıcı: her (motor, kaynak, hedef) için tek `EngineCache`.
/// Motor değişince eski motorun çevirisi gösterilmez.
public actor EngineCacheStore {
    public let directory: URL?
    public let capacity: Int
    private var caches: [String: EngineCache] = [:]

    /// `directory` `nil` ise yalnız bellekte.
    public init(directory: URL?, capacity: Int = 20_000) {
        self.directory = directory
        self.capacity = capacity
    }

    public func cache(engine: String, source: String, target: String) -> EngineCache {
        let name = EngineCache.fileName(engine: engine, source: source, target: target)
        if let c = caches[name] { return c }
        let c = EngineCache(fileURL: directory?.appendingPathComponent(name), capacity: capacity)
        caches[name] = c
        return c
    }
}
