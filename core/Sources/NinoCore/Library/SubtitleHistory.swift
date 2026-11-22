// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Altyazı geçmişi (`history.json`). En yeni başta, en çok 200 kayıt.
public struct SubtitleHistory: Sendable {
    public enum Origin: String, Codable, Sendable { case pack, engine }

    public struct Entry: Codable, Equatable, Sendable {
        public var id: Int
        public var date: Date
        public var source: String
        public var translation: String
        public var origin: Origin
    }

    public static let capacity = 200
    public static let maxTextLength = 500
    public static let similarity = 0.85

    public private(set) var entries: [Entry] = []

    public init(entries: [Entry] = []) { self.entries = entries }

    /// Dosya yoksa ya da bozuksa boş geçmiş.
    public init(contentsOf url: URL) {
        // Kayıtlar tek tek okunur; bozuk kayıt atlanır, geri kalan geçmiş kaybolmaz.
        struct Loose: Decodable {
            var value: Entry?
            init(from decoder: Decoder) throws { value = try? Entry(from: decoder) }
        }
        struct File: Decodable { var entries: [Loose] }
        if let data = try? Data(contentsOf: url), let file = try? Self.decoder.decode(File.self, from: data) {
            entries = Array(file.entries.compactMap(\.value).prefix(Self.capacity))
        }
    }

    /// Ekler; son kaydın kaynağı benziyorsa onu günceller (kimlik aynı kalır).
    public mutating func add(source: String, translation: String, origin: Origin, date: Date = Date()) {
        let t = String(translation.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTextLength))
        guard !t.isEmpty else { return }
        let s = String(source.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTextLength))
        if let last = entries.first, Self.isSimilar(last.source, s) {
            entries[0] = Entry(id: last.id, date: date, source: s, translation: t, origin: origin)
            return
        }
        let id = (entries.map(\.id).max() ?? -1) + 1
        entries.insert(Entry(id: id, date: date, source: s, translation: t, origin: origin), at: 0)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
    }

    /// Bir andan sonraki kayıtlar (ör. oturum başı).
    public func entries(since date: Date) -> [Entry] { entries.filter { $0.date >= date } }

    /// Sadeleşmiş metinler eşitse (boş değil) ya da Levenshtein oranı ≥ 0.85.
    public static func isSimilar(_ a: String, _ b: String) -> Bool {
        let x = TextSimilarity.key(a), y = TextSimilarity.key(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x == y || TextSimilarity.ratio(x, y) >= similarity
    }

    /// `[HH:mm:ss] Türkçe\nİngilizce`, kayıtlar arası boş satır.
    public func plainText(timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm:ss"
        return entries.map { "[\(f.string(from: $0.date))] \($0.translation)\n\($0.source)" }.joined(separator: "\n\n")
    }

    /// Yerine koyarak yazar (yarım dosya kalmaz).
    public func write(to url: URL) throws {
        struct File: Encodable { var version = 1; var entries: [Entry] }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(File(entries: entries)).write(to: url, options: .atomic)
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let plain = ISO8601DateFormatter()
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = plain.date(from: s) ?? fractional.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "tarih: \(s)"))
        }
        return d
    }
}

/// Altyazı günlüğü (`altyazi.log`). Arka planda yazar; yazamazsa sessizce geçer.
public final class SubtitleLog: @unchecked Sendable {
    public static let maxBytes = 1 << 20
    public static let maxQuote = 120

    public let fileURL: URL?
    private let queue = DispatchQueue(label: "nino.subtitle-log")
    private let now: @Sendable () -> Date
    private let formatter: DateFormatter

    /// `fileURL` `nil` ise hiçbir şey yazılmaz.
    public init(fileURL: URL?, timeZone: TimeZone = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.now = now
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    /// Satırlar ` / ` ile birleşir, en çok 120 karakter, çift tırnakta.
    public static func quote(_ text: String) -> String {
        let joined = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " / ")
        let short = joined.count > maxQuote ? String(joined.prefix(maxQuote - 1)) + "…" : joined
        return "\"\(short)\""
    }

    public func write(_ message: String) {
        guard let fileURL else { return }
        let line = "[\(formatter.string(from: now()))] \(message)\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let size = (try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
            if size > Self.maxBytes {
                let old = fileURL.appendingPathExtension("1")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: fileURL, to: old)
            }
            _ = PoolQueue.append(Data(line.utf8), to: fileURL)
        }
    }

    /// Bekleyen yazmaları bitirir (testler ve kapanış için).
    public func flush() { queue.sync {} }
}
