// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Çevrilen son 200 altyazı (`history.json`; önceki sürüm ve Windows ile aynı biçim).
struct SubtitleHistory: Equatable {
    enum Origin: String, Codable { case pack, engine }

    struct Entry: Codable, Equatable, Identifiable {
        let id: Int
        let date: Date
        let source: String
        let translation: String
        let origin: Origin
    }

    static let limit = 200
    static let textLimit = 500

    /// En yenisi başta.
    private(set) var entries: [Entry] = []

    var nextID: Int { (entries.map(\.id).max() ?? 0) + 1 }

    mutating func add(source: String, translation: String, origin: Origin, date: Date = Date()) {
        let entry = Entry(id: nextID, date: date,
                          source: String(source.prefix(Self.textLimit)),
                          translation: String(translation.prefix(Self.textLimit)),
                          origin: origin)
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    mutating func removeAll() { entries.removeAll() }

    // MARK: Dosya

    private struct File: Codable {
        var version = 1
        var entries: [Entry]
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Dosya yoksa ya da bozuksa boş geçmiş.
    static func load(from url: URL) -> SubtitleHistory {
        guard let data = try? Data(contentsOf: url), let file = try? decoder().decode(File.self, from: data) else {
            return SubtitleHistory()
        }
        var h = SubtitleHistory()
        h.entries = Array(file.entries.prefix(limit))
        return h
    }

    func data() -> Data? { try? Self.encoder().encode(File(entries: entries)) }

    func save(to url: URL) throws {
        guard let data = data() else { return }
        try data.write(to: url, options: .atomic)
    }
}
