// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// MARK: - Telefon hafızası (tarif §6.2, §6.3, §6.5)

extension GameReading {
    /// Telefon mesajlarının çevirileri. Dosya: `phone-memory-<dil>.json`, düz nesne
    /// `{"<sadeleştirilmiş İngilizce>": "<çeviri>"}`. Oturum hafızası ayrıca cihaz çevirilerini tutar.
    public struct PhoneMemory: Sendable {
        public static let defaultCapacity = 5_000

        public let directory: URL?
        public private(set) var language: String
        public var capacity: Int
        private var entries: [String: String] = [:]
        /// Ekleme sırası (en eski başta).
        private var order: [String] = []
        private var session: [String: String] = [:]

        public init(directory: URL?, language: String, capacity: Int = defaultCapacity) {
            self.directory = directory; self.language = language; self.capacity = capacity
            load()
        }

        public static func fileName(language: String) -> String { "phone-memory-\(language).json" }

        public var fileURL: URL? { directory?.appendingPathComponent(Self.fileName(language: language)) }
        public var count: Int { entries.count }

        /// Dil değişince o dilin dosyası yüklenir; oturum hafızası boşalır.
        public mutating func switchLanguage(_ newLanguage: String) {
            guard newLanguage != language else { return }
            language = newLanguage
            session = [:]
            load()
        }

        mutating func load() {
            entries = [:]; order = []
            guard let url = fileURL, let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            for k in obj.keys.sorted() {
                guard let v = obj[k] as? String, !v.isEmpty else { continue }
                let key = Text.key(k)
                guard !key.isEmpty, entries[key] == nil else { continue }
                entries[key] = v
                order.append(key)
            }
            trim()
        }

        public func save() {
            guard let url = fileURL else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let data = try? JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys]) else { return }
            try? data.write(to: url, options: .atomic)
        }

        private mutating func trim() {
            guard entries.count > capacity else { return }
            let drop = entries.count - capacity
            for k in order.prefix(drop) { entries[k] = nil }
            order.removeFirst(drop)
        }

        /// Kalıcı hafızaya yazar. `device` ise oturum hafızasına da.
        public mutating func store(_ source: String, _ translation: String, device: Bool = false) {
            let key = Text.key(source)
            guard !key.isEmpty, !translation.isEmpty else { return }
            if entries[key] == nil { order.append(key) }
            entries[key] = translation
            if device { session[key] = translation }
            trim()
        }

        /// Kalıcı hafızadan: ≥ 5 sözcükte aynısı ya da onunla başlayan/biten en uzun kayıt; kısada yalnız aynısı.
        public func persistent(_ text: String) -> String? { Self.find(text, in: entries) }

        public func sessionTranslation(_ text: String) -> String? { Self.find(text, in: session) }

        /// Hafızada (kalıcı, sonra oturum) var mı?
        public func lookup(_ text: String) -> String? { persistent(text) ?? sessionTranslation(text) }

        public func contains(_ text: String) -> Bool { lookup(text) != nil }

        static func find(_ text: String, in d: [String: String]) -> String? {
            let key = Text.key(text)
            guard !key.isEmpty else { return nil }
            if let v = d[key] { return v }
            guard key.split(separator: " ").count >= 5 else { return nil }
            let best = d.filter { $0.key.hasPrefix(key + " ") || $0.key.hasSuffix(" " + key) }.max { $0.key.count < $1.key.count }
            return best?.value
        }
    }
}

// MARK: - Çevirmen ve çeviri akışı (tarif §6.5)

extension GameReading {
    /// Telefon ve harita kartı çevirileri için uygulamanın verdiği çevirmen.
    public protocol PhoneTranslator: Sendable {
        /// Hedef dil (`tr` ise telefon sözlüğü de kullanılır).
        var targetLanguage: String { get }
        /// Havuzda bilinen çeviri.
        func known(_ text: String) async -> String?
        /// Bilinmeyenler havuza bildirilsin mi (havuz açık ya da oyun havuz öncelikli)?
        var reportsToPool: Bool { get }
        func report(_ texts: [String]) async
        /// Havuz soruluyor mu?
        var asksPool: Bool { get }
        /// Tek istekte havuza sorar; sırası `texts` ile aynı, bilinmeyen `nil`.
        func askPool(_ texts: [String], context: [String]) async -> [String?]
        /// Cihazda çeviri.
        func translateOnDevice(_ text: String) async throws -> String
    }

    public enum PhoneTranslation {
        public static let maxContext = 4
        public static let deviceParallel = 2

        public struct Result: Equatable, Sendable {
            /// Kaynak → çeviri (boş olmayanlar).
            public var translations: [String: String] = [:]
            /// Cihazda çevrilenler.
            public var device: Set<String> = []
        }

        /// Bilinmeyen metinleri çevirir: havuza bildirir, havuza tek istekte sorar, kalanları cihazda en çok 2'şer çevirir.
        public static func translate(_ unknown: [String], context: [String], with t: PhoneTranslator) async -> Result {
            var result = Result()
            guard !unknown.isEmpty else { return result }
            if t.reportsToPool { await t.report(unknown) }
            var remaining = unknown
            if t.asksPool {
                let answers = await t.askPool(unknown, context: Array(context.suffix(maxContext)))
                remaining = []
                for (i, src) in unknown.enumerated() {
                    let a = i < answers.count ? answers[i].map(PhoneText.clean) : nil
                    if let a, !a.isEmpty { result.translations[src] = a } else { remaining.append(src) }
                }
            }
            var index = 0
            while index < remaining.count {
                let batch = Array(remaining[index..<min(remaining.count, index + deviceParallel)])
                index += batch.count
                let done = await withTaskGroup(of: (String, String?).self) { group -> [(String, String?)] in
                    for src in batch { group.addTask { (src, try? await t.translateOnDevice(src)) } }
                    var out: [(String, String?)] = []
                    for await r in group { out.append(r) }
                    return out
                }
                for (src, tr) in done {
                    guard let tr else { continue }
                    let c = PhoneText.clean(tr)
                    if !c.isEmpty { result.translations[src] = c; result.device.insert(src) }
                }
            }
            return result
        }
    }
}
