// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Geçmiş satırının nereden çevrildiği (history.json `origin`).
public enum HistoryOrigin: String, Sendable { case pack, engine }

public extension HistoryEntry {
    init(id: UUID = UUID(), date: Date, source: String, translated: String, origin: HistoryOrigin?) {
        self.init(id: id, date: date, source: source, translated: translated)
        self.origin = origin
    }
}

/// Çeviri geçmişi (gecmis-hakkinda-saglik.md §1, veri-uyumu.md §3 `history.json`).
///
/// En yeni başta, en çok 200 satır, metin başına en çok 500 karakter. Aynı kaynak art arda gelirse
/// yeni satır açılmaz, en yenisi güncellenir. Dosyaya arka planda, sırayla yazılır; en son hâl kalır.
public final class HistoryStore: @unchecked Sendable {
    public static let limit = 200
    public static let textLimit = 500

    public let file: URL
    private let queue: DispatchQueue

    public init(file: URL) {
        self.file = file
        queue = DispatchQueue(label: "nino.history")
    }

    public convenience init(folder: DataFolder) { self.init(file: folder.historyFile) }

    /// Bu ve önceki oturumların satırları. Dosya yoksa ya da bozuksa boş.
    public func load() -> [HistoryEntry] {
        DataFiles.history(at: file).prefix(Self.limit).map {
            HistoryEntry(date: $0.date, source: $0.source, translated: $0.translation,
                         origin: $0.origin.flatMap { HistoryOrigin(rawValue: $0.rawValue) })
        }
    }

    /// Yeni satırı başa ekler (sınır ve birleştirme kurallarıyla).
    public static func adding(_ entry: HistoryEntry, to list: [HistoryEntry]) -> [HistoryEntry] {
        var entry = entry
        entry.source = clip(entry.source)
        entry.translated = clip(entry.translated)
        guard !entry.translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return list }
        var list = list
        if let first = list.first, sameSource(first.source, entry.source) {
            entry.id = first.id
            list[0] = entry
            return list
        }
        list.insert(entry, at: 0)
        if list.count > limit { list.removeLast(list.count - limit) }
        return list
    }

    static func sameSource(_ a: String, _ b: String) -> Bool {
        let fold: (String) -> String = {
            $0.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let fa = fold(a), fb = fold(b)
        return !fa.isEmpty && fa == fb
    }

    static func clip(_ text: String) -> String {
        text.count > textLimit ? String(text.prefix(textLimit)) : text
    }

    /// Arka planda yazar; art arda çağrılarda en son hâl kalır.
    public func save(_ entries: [HistoryEntry]) {
        let data = Self.encode(entries)
        let file = file
        queue.async {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data?.write(to: file, options: .atomic)
        }
    }

    /// Listeyi ve dosyayı boşaltır.
    public func clear() { save([]) }

    /// Bekleyen yazmaların bitmesini bekler (kapanış ve testler).
    public func flush() { queue.sync {} }

    static func encode(_ entries: [HistoryEntry]) -> Data? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let count = entries.count
        let items: [[String: Any]] = entries.prefix(limit).enumerated().map { index, entry in
            var item: [String: Any] = [
                "id": count - index,
                "date": formatter.string(from: entry.date),
                "source": clip(entry.source),
                "translation": clip(entry.translated),
            ]
            if let origin = entry.origin { item["origin"] = origin.rawValue }
            return item
        }
        return try? JSONSerialization.data(withJSONObject: ["version": 1, "entries": items],
                                           options: [.sortedKeys, .withoutEscapingSlashes])
    }

    // MARK: Pano metinleri

    /// Tek satır: çeviri + yeni satır + asıl metin.
    public static func clipboardText(_ entry: HistoryEntry) -> String {
        entry.translated + "\n" + entry.source
    }

    /// Bütün satırlar düz metin: her satır "saat · çeviri / asıl", aralarında boş satır.
    public static func plainText(_ entries: [HistoryEntry], timeZone: TimeZone = .current) -> String {
        entries.map { "[\(timeText($0.date, timeZone: timeZone))] " + clipboardText($0) }.joined(separator: "\n\n")
    }

    /// `saat:dakika:saniye`.
    public static func timeText(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
