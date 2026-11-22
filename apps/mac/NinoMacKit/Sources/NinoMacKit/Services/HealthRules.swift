// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// Sistem sağlığının kuralları (gecmis-hakkinda-saglik.md §3): seviyeler, eşikler, muhtemel sebepler.
// Ekran yalnız `HealthMetrics`'in bir kopyasını okur; ölçümleri motor biriktirir.

/// Mac'in ağ türü. Ham değer sorun kayıtlarındaki `network` alanıdır.
public enum NetworkKind: String, Sendable, CaseIterable {
    case wired = "ethernet"
    case wifi
    case other
    case offline
    /// Henüz bilinmiyor ("Denetleniyor…").
    case unknown
}

/// Bir denetimin seviyesi.
public enum HealthLevel: Int, Sendable, Comparable {
    case notMeasured, good, fair, problem
    public static func < (a: HealthLevel, b: HealthLevel) -> Bool { a.rawValue < b.rawValue }
    public var needsAction: Bool { self == .fair || self == .problem }
}

/// PS5 bağlantısının son kopma sebebi (tavsiye metni için).
public enum HealthDropReason: String, Sendable {
    case asleep, inUseElsewhere, passcode, remotePlayDisabled, pairingInvalid, notFound, other

    public init(_ reason: SourceStatus.DropReason) {
        switch reason {
        case .asleep: self = .asleep
        case .inUseElsewhere, .refused: self = .inUseElsewhere
        case .passcodeRequired, .passcodeWrong: self = .passcode
        case .remotePlayDisabled: self = .remotePlayDisabled
        case .pairingInvalid, .rejected: self = .pairingInvalid
        case .notFound: self = .notFound
        case .noPicture, .network, .other: self = .other
        }
    }
}

/// Nino TV uygulamasının kurulum durumu (Sistem sağlığı satırı ve cihaz bilgileri).
public enum TVAppHealth: Equatable, Sendable {
    case unknown
    case installing
    case installed(version: String)
    case waitingForApproval
    case developerModeOff
    case waitingForPassword
    case samsungSignIn
    case failed(code: String, reason: String, message: String)
    case hostIPMismatch(tvValue: String, macAddress: String)
}

/// Sağlık ölçümlerinin anlık kopyası. Motor doldurur; sayfa iki saniyede bir okur.
public struct HealthMetrics: Equatable, Sendable {
    public var network: NetworkKind = .unknown
    public var translating = false
    /// Bu ya da son oturumda ölçüm alındı mı.
    public var hasMeasurements = false
    /// Şu an PS5'ten görüntü geliyor mu.
    public var receivingVideo = false
    /// Görüntü kaynağı PS5 mi (oyun penceresi / yakalama kartı değil).
    public var sourceIsPS5 = true

    // PS5 bağlantısı
    public var connectAttempts = 0
    public var connections = 0
    public var dropsWhileStreaming = 0
    /// Koptu ve geri gelmedi: koptuğu an.
    public var ps5DownSince: Date?
    public var lastDropReason: HealthDropReason?
    public var streamedSeconds: Double = 0

    // Bu Mac'in ağı ve TV (oturumda)
    public var networkDrops = 0
    public var tvDrops = 0

    // PS5 görüntüsü
    public var lossPerMinute: Double?
    public var stallsPerMinute: Double?
    public var retransmissions = 0
    public var bufferOverflows = 0
    public var corruptFrames = 0

    // Çeviri
    public var subtitleLines = 0
    /// Çeviri motoruna giden satır sayısı (hazır çeviriden gelenler hariç).
    public var translatedLines = 0
    public var medianTranslationMs: Int?
    public var maxTranslationMs: Int?
    /// Çevrimiçi motor ya da yerel model kullanılıyor.
    public var usesOnlineOrLocalEngine = false

    // TV
    public var subtitlesOnTV = true
    public var connectedTVs = 0
    public var tvApp: TVAppHealth = .unknown

    /// Mac'in yerel ağ izni kapalı görünüyor (güçlü işaret).
    public var localNetworkSuspect = false

    public init() {}
}

/// Muhtemel sebep (önemliden önemsize).
public enum ProbableCause: Sendable, Equatable {
    case noNetwork
    case droppedAfterNetworkLoss
    case ps5Asleep
    case usedElsewhere
    case ps5DroppedGeneral
    case couldNotConnect
    case networkDropped(times: Int)
    case pictureLossWifi
    case pictureLossWired
    case frequentDrops(times: Int)
    case slowTranslation(seconds: Double)
    case tvDropped(times: Int)
}

public enum HealthRules {
    // MARK: Seviyeler

    public static func video(_ m: HealthMetrics) -> HealthLevel {
        guard m.hasMeasurements, m.lossPerMinute != nil || m.stallsPerMinute != nil else { return .notMeasured }
        let loss = m.lossPerMinute ?? 0, stalls = m.stallsPerMinute ?? 0
        if loss >= 100 || stalls >= 4 { return .problem }
        if loss >= 10 || stalls >= 2.5 { return .fair }
        return .good
    }

    /// Çeviri sürerken PS5 koptu ve yeniden bağlanılamadı.
    public static func ps5Down(_ m: HealthMetrics) -> Bool { m.translating && m.ps5DownSince != nil }

    public static func neverConnected(_ m: HealthMetrics) -> Bool { m.connections == 0 && m.connectAttempts >= 2 }

    public static func console(_ m: HealthMetrics) -> HealthLevel {
        guard m.hasMeasurements else { return .notMeasured }
        if ps5Down(m) { return .problem }
        if m.connections == 0 { return m.connectAttempts >= 2 ? .problem : .notMeasured }
        if m.dropsWhileStreaming >= 3 { return .fair }
        return .good
    }

    public static func translation(_ m: HealthMetrics) -> HealthLevel {
        guard m.hasMeasurements, let median = m.medianTranslationMs else { return .notMeasured }
        if median >= 3000 { return .problem }
        if median >= 1500 { return .fair }
        return .good
    }

    /// Wi-Fi ya da başka bağlantıda, ölçülmeden yeşil gösterilmez.
    public static func network(_ m: HealthMetrics) -> HealthLevel {
        switch m.network {
        case .wired: return .good
        case .offline: return .problem
        case .unknown: return .notMeasured
        case .wifi, .other: return video(m)
        }
    }

    public static func tv(_ m: HealthMetrics) -> HealthLevel {
        guard m.translating, m.subtitlesOnTV else { return .notMeasured }
        return m.connectedTVs > 0 ? .good : .problem
    }

    // MARK: Muhtemel sebepler (§3.1)

    public static func causes(_ m: HealthMetrics) -> [ProbableCause] {
        var list: [ProbableCause] = []
        if m.network == .offline { list.append(.noNetwork) }
        guard m.hasMeasurements else { return list }
        if ps5Down(m), m.network != .offline {
            if m.networkDrops > 0 {
                list.append(.droppedAfterNetworkLoss)
            } else {
                switch m.lastDropReason {
                case .asleep: list.append(.ps5Asleep)
                case .inUseElsewhere: list.append(.usedElsewhere)
                default: list.append(.ps5DroppedGeneral)
                }
            }
        } else if neverConnected(m) {
            list.append(.couldNotConnect)
        }
        if m.networkDrops > 0, m.network != .offline, m.ps5DownSince == nil {
            list.append(.networkDropped(times: m.networkDrops))
        }
        if video(m).needsAction {
            list.append(m.network == .wired ? .pictureLossWired : .pictureLossWifi)
        }
        if m.ps5DownSince == nil, m.dropsWhileStreaming >= 3, video(m) == .good, m.networkDrops == 0 {
            list.append(.frequentDrops(times: m.dropsWhileStreaming))
        }
        if translation(m).needsAction, let median = m.medianTranslationMs {
            list.append(.slowTranslation(seconds: (Double(median) / 100).rounded() / 10))
        }
        if m.tvDrops > 0 { list.append(.tvDropped(times: m.tvDrops)) }
        return list
    }

    /// "Her şey yolunda" gösterilir mi: sebep yok, çeviri sürüyor ve görüntü geliyor.
    public static func allGood(_ m: HealthMetrics) -> Bool {
        causes(m).isEmpty && m.translating && m.receivingVideo
    }

    /// PS5 kopukluğunun dakikası (en az 1).
    public static func downMinutes(_ m: HealthMetrics, now: Date) -> Int {
        guard let since = m.ps5DownSince else { return 0 }
        return max(1, Int(now.timeIntervalSince(since) / 60))
    }
}

// MARK: - Sorun kayıtları (§3.3, sorunlar.json)

public enum ProblemKind: String, Sendable, CaseIterable {
    case ps5Dropped, ps5Unreachable, networkLost, tvDropped
}

/// Bir sorun kaydı; dosyadaki biçimin aynısı.
public struct ProblemRecord: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var kind: ProblemKind
    public var reason: String?
    public var streamedMinutes: Double?
    public var lossPerMinute: Double?
    public var stallsPerMinute: Double?
    public var network: String
    public var game: String?

    public init(id: UUID = UUID(), date: Date, kind: ProblemKind, reason: String? = nil,
                streamedMinutes: Double? = nil, lossPerMinute: Double? = nil, stallsPerMinute: Double? = nil,
                network: String, game: String? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.reason = reason
        self.streamedMinutes = streamedMinutes
        self.lossPerMinute = lossPerMinute
        self.stallsPerMinute = stallsPerMinute
        self.network = network
        self.game = game
    }

    /// Günlüğe yazılan tek satır.
    public var logLine: String {
        var parts = ["sorun: \(kind.rawValue)", "ağ \(network)"]
        if let reason { parts.append("sebep \(reason)") }
        if let streamedMinutes { parts.append(String(format: "akış %.1f dk", streamedMinutes)) }
        if let lossPerMinute { parts.append(String(format: "kayıp %.0f/dk", lossPerMinute)) }
        if let stallsPerMinute { parts.append(String(format: "donma %.1f/dk", stallsPerMinute)) }
        if let game { parts.append("oyun \(game)") }
        return parts.joined(separator: ", ")
    }
}

/// `sorunlar.json`: en çok 40 kayıt, Nino yeniden açılsa da kalır.
public final class ProblemLog: @unchecked Sendable {
    public static let limit = 40
    public let file: URL
    private let lock = NSLock()
    private var records: [ProblemRecord]

    public init(file: URL) {
        self.file = file
        records = DataFiles.incidents(at: file).compactMap { r in
            guard let kind = r.kind.flatMap({ ProblemKind(rawValue: $0.rawValue) }) else { return nil }
            return ProblemRecord(id: r.id, date: r.date, kind: kind, reason: r.reason,
                                 streamedMinutes: r.streamedMinutes, lossPerMinute: r.lossPerMinute,
                                 stallsPerMinute: r.stallsPerMinute, network: r.network ?? "unknown", game: r.game)
        }
    }

    public convenience init(folder: DataFolder) { self.init(file: folder.incidentsFile) }

    /// Dosyadaki sırayla (eskiden yeniye).
    public var all: [ProblemRecord] { lock.withLock { records } }

    /// En yeniler başta, en çok `count`.
    public func recent(_ count: Int) -> [ProblemRecord] {
        Array(all.sorted { $0.date > $1.date }.prefix(count))
    }

    /// Son `days` günün kayıtları, en yeni başta.
    public func within(days: Double, of now: Date) -> [ProblemRecord] {
        all.filter { now.timeIntervalSince($0.date) <= days * 86_400 }.sorted { $0.date > $1.date }
    }

    public func add(_ record: ProblemRecord) {
        let snapshot: [ProblemRecord] = lock.withLock {
            records.append(record)
            if records.count > Self.limit { records.removeFirst(records.count - Self.limit) }
            return records
        }
        write(snapshot)
    }

    private func write(_ records: [ProblemRecord]) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let list: [[String: Any]] = records.map { r in
            var item: [String: Any] = ["id": r.id.uuidString, "date": formatter.string(from: r.date),
                                       "kind": r.kind.rawValue, "network": r.network]
            if let v = r.reason { item["reason"] = v }
            if let v = r.streamedMinutes { item["streamedMinutes"] = v }
            if let v = r.lossPerMinute { item["lossPerMinute"] = v }
            if let v = r.stallsPerMinute { item["stallsPerMinute"] = v }
            if let v = r.game { item["game"] = v }
            return item
        }
        guard let data = try? JSONSerialization.data(withJSONObject: list,
                                                     options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

/// Ölçümlerin değişiminden sorun kaydı çıkarır (§3.3 "Ne zaman kaydedilir").
/// Motor her ölçüm kopyasında `observe` çağırır; dönen türler kaydedilir.
public struct ProblemDetector: Sendable {
    /// Kopmadan sonra bu kadar sürede geri gelmezse "dakikalarca gelmedi".
    public static let unreachableAfter: TimeInterval = 180
    /// TV bu kadar sürede geri gelmezse "TV koptu".
    public static let tvGrace: TimeInterval = 20

    private var previous: HealthMetrics?
    private var unreachableReported = false
    private var tvZeroSince: Date?
    private var tvReported = false

    public init() {}

    public mutating func observe(_ m: HealthMetrics, now: Date) -> [ProblemKind] {
        defer { previous = m }
        var found: [ProblemKind] = []
        guard m.translating else {
            unreachableReported = false
            tvZeroSince = nil
            tvReported = false
            return found
        }
        let before = previous
        // PS5 koptu (görüntü gelirken).
        if let before, before.translating, before.receivingVideo, before.ps5DownSince == nil, m.ps5DownSince != nil {
            found.append(.ps5Dropped)
            unreachableReported = false
        }
        if m.ps5DownSince == nil { unreachableReported = false }
        if let since = m.ps5DownSince, !unreachableReported, now.timeIntervalSince(since) >= Self.unreachableAfter {
            found.append(.ps5Unreachable)
            unreachableReported = true
        }
        // Ağ gitti.
        if let before, before.network != .offline, m.network == .offline { found.append(.networkLost) }
        // TV koptu: bağlı sayısı 0'a indi ve 20 sn geri gelmedi.
        if m.subtitlesOnTV {
            if m.connectedTVs == 0 {
                if tvZeroSince == nil, let before, before.connectedTVs > 0 { tvZeroSince = now }
                if let since = tvZeroSince, !tvReported, now.timeIntervalSince(since) >= Self.tvGrace {
                    found.append(.tvDropped)
                    tvReported = true
                }
            } else {
                tvZeroSince = nil
                tvReported = false
            }
        }
        return found
    }
}
