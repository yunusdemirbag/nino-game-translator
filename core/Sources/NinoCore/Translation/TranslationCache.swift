// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Diskte tutulan çeviri önbelleği. En eski kullanılan kayıt, sınır aşılınca silinir.
public actor TranslationCache {
    public struct Entry: Codable, Equatable, Sendable {
        public var key: String
        public var source: String
        public var text: String
        public var origin: String
        public var date: Date
        var lastUse: UInt64
    }

    public let capacity: Int
    private let fileURL: URL?
    private var entries: [String: Entry] = [:]
    private var tick: UInt64 = 0
    private var dirty = false

    /// `fileURL` `nil` ise yalnız bellekte tutulur.
    public init(fileURL: URL? = nil, capacity: Int = 50_000) {
        self.fileURL = fileURL
        self.capacity = max(1, capacity)
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder.nino.decode([Entry].self, from: data) {
            for e in list { entries[e.key] = e }
            tick = list.map(\.lastUse).max() ?? 0
        }
    }

    public var count: Int { entries.count }

    public func lookup(_ source: String) -> String? {
        let key = TranslationKey.make(source)
        guard var e = entries[key] else { return nil }
        tick += 1
        e.lastUse = tick
        entries[key] = e
        dirty = true
        return e.text
    }

    public func store(source: String, text: String, origin: String, date: Date = Date()) {
        let key = TranslationKey.make(source)
        tick += 1
        entries[key] = Entry(key: key, source: source, text: text, origin: origin, date: date, lastUse: tick)
        dirty = true
        if entries.count > capacity {
            let extra = entries.count - capacity
            for old in entries.values.sorted(by: { $0.lastUse < $1.lastUse }).prefix(extra) {
                entries[old.key] = nil
            }
        }
    }

    public func removeAll() {
        entries.removeAll()
        dirty = true
    }

    /// Değişiklik varsa diske yazar.
    public func save() throws {
        guard let fileURL, dirty else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let list = entries.values.sorted { $0.lastUse < $1.lastUse }
        try JSONEncoder.nino.encode(list).write(to: fileURL, options: .atomic)
        dirty = false
    }
}

extension JSONEncoder {
    static var nino: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var nino: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
