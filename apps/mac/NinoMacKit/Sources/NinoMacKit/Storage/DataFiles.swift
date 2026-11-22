// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Veri klasöründeki dosyaların okuyucuları (docs/yeni/mac/veri-uyumu.md §3, havuz-paketler.md §6–7).
///
/// Hepsi yalnız okur: dosya yoksa ya da bozuksa boş döner, hiçbir şeyi silmez, taşımaz, yazmaz.
/// Dizilerde bozuk öğe atlanır, dosyanın geri kalanı okunur.
public enum DataFiles {
    // MARK: Tarih

    /// ISO-8601, kesirli saniyeli ya da kesirsiz.
    static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: text) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    static func object(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    // MARK: history.json

    public struct HistoryRecord: Equatable, Sendable {
        public enum Origin: String, Sendable { case pack, engine }
        public var id: Int
        public var date: Date
        public var source: String
        public var translation: String
        /// Bilinmeyen köken nil.
        public var origin: Origin?
    }

    /// En yeni başta (dosyadaki sırayla).
    public static func history(at url: URL) -> [HistoryRecord] {
        guard let entries = object(at: url)?["entries"] as? [Any] else { return [] }
        return entries.compactMap { item in
            guard let e = item as? [String: Any],
                  let id = number(e["id"]).map({ Int($0) }),
                  let dateText = e["date"] as? String, let date = parseDate(dateText),
                  let source = e["source"] as? String,
                  let translation = e["translation"] as? String else { return nil }
            return HistoryRecord(id: id, date: date, source: source, translation: translation,
                                 origin: (e["origin"] as? String).flatMap(HistoryRecord.Origin.init(rawValue:)))
        }
    }

    // MARK: subtitle-layout.json

    public struct LayoutBand: Equatable, Sendable {
        /// 0–1, ekran yüksekliğine oranla.
        public var top: Double
        public var bottom: Double
    }

    /// Oyun kimliği → öğrenilmiş altyazı kutuları. Oyun tanınmazken anahtar `genel`.
    public static func subtitleLayout(at url: URL) -> [String: [LayoutBand]] {
        guard let samples = object(at: url)?["samples"] as? [String: Any] else { return [:] }
        var out: [String: [LayoutBand]] = [:]
        for (game, value) in samples {
            guard let list = value as? [Any] else { continue }
            out[game] = list.compactMap { item in
                guard let b = item as? [String: Any], let top = number(b["top"]), let bottom = number(b["bottom"]),
                      top.isFinite, bottom.isFinite else { return nil }
                return LayoutBand(top: top, bottom: bottom)
            }
        }
        return out
    }

    // MARK: phone-memory-<dil>.json

    /// Sadeleştirilmiş İngilizce mesaj → çeviri. Dizge olmayan değer atlanır.
    public static func phoneMemory(at url: URL) -> [String: String] {
        guard let obj = object(at: url) else { return [:] }
        return obj.compactMapValues { $0 as? String }
    }

    // MARK: pool/state.json

    public struct PoolState: Equatable, Sendable {
        /// Kurulum kimliği (küçük harf UUID). Yeni uygulama aynısını sürdürür.
        public var install: String?
        public var frozenThrough: Int?
        public var failures: Int?
        public var nextAttempt: Double?
        public var serverRetryAt: Double?
        public var app: String?
        public var dropped: Int?
    }

    /// Dosya yoksa ya da nesne değilse nil. Bozuk dosyayı kenara almak havuz istemcisinin işi.
    public static func poolState(at url: URL) -> PoolState? {
        guard let o = object(at: url) else { return nil }
        return PoolState(install: o["install"] as? String,
                         frozenThrough: number(o["frozenThrough"]).map { Int($0) },
                         failures: number(o["failures"]).map { Int($0) },
                         nextAttempt: number(o["nextAttempt"]),
                         serverRetryAt: number(o["serverRetryAt"]),
                         app: o["app"] as? String,
                         dropped: number(o["dropped"]).map { Int($0) })
    }

    // MARK: sorunlar.json

    public struct IncidentRecord: Equatable, Sendable {
        public enum Kind: String, Sendable { case ps5Dropped, ps5Unreachable, networkLost, tvDropped }
        public var id: UUID
        public var date: Date
        /// Bilinmeyen tür ham haliyle `rawKind`'da kalır.
        public var kind: Kind?
        public var rawKind: String
        public var reason: String?
        public var streamedMinutes: Double?
        public var lossPerMinute: Double?
        public var stallsPerMinute: Double?
        public var network: String?
        public var game: String?
    }

    public static func incidents(at url: URL) -> [IncidentRecord] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return list.compactMap { item in
            guard let e = item as? [String: Any],
                  let idText = e["id"] as? String, let id = UUID(uuidString: idText),
                  let dateText = e["date"] as? String, let date = parseDate(dateText),
                  let kind = e["kind"] as? String else { return nil }
            return IncidentRecord(id: id, date: date, kind: IncidentRecord.Kind(rawValue: kind), rawKind: kind,
                                  reason: e["reason"] as? String,
                                  streamedMinutes: number(e["streamedMinutes"]),
                                  lossPerMinute: number(e["lossPerMinute"]),
                                  stallsPerMinute: number(e["stallsPerMinute"]),
                                  network: e["network"] as? String,
                                  game: e["game"] as? String)
        }
    }
}

public extension DataFolder {
    func history() -> [DataFiles.HistoryRecord] { DataFiles.history(at: historyFile) }
    func subtitleLayout() -> [String: [DataFiles.LayoutBand]] { DataFiles.subtitleLayout(at: subtitleLayoutFile) }
    func phoneMemory(language: String) -> [String: String] {
        DataFiles.phoneMemory(at: phoneMemoryFile(language: language))
    }
    func poolState() -> DataFiles.PoolState? { DataFiles.poolState(at: poolStateFile) }
    func incidents() -> [DataFiles.IncidentRecord] { DataFiles.incidents(at: incidentsFile) }
}
