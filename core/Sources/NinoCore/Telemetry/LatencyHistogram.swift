// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Sabit kovalı süre histogramı (ms). Kova sınırları bütün platformlarda aynı (tarif: docs/tarif/olcum.md); sunucu
/// yüzdelikleri bu kovalardan hesaplar.
public struct LatencyHistogram: Equatable, Sendable {
    /// Kova üst sınırları (ms). Son kova (`edges.count`) 10 000 ms'den uzunlar.
    public static let edges: [Int] = [5, 10, 20, 35, 50, 75, 100, 150, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 5000, 10000]

    public private(set) var counts: [Int] = Array(repeating: 0, count: LatencyHistogram.edges.count + 1)
    public private(set) var count = 0
    public private(set) var sum = 0
    public private(set) var max = 0

    public init() {}

    /// `v ≤ sınır` olan ilk kova.
    public static func bucket(of ms: Int) -> Int {
        edges.firstIndex { ms <= $0 } ?? edges.count
    }

    public mutating func record(_ ms: Int) {
        let v = Swift.max(0, ms)
        counts[Self.bucket(of: v)] += 1
        count += 1
        sum += v
        max = Swift.max(max, v)
    }

    public mutating func record(seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        record(Int((seconds * 1000).rounded()))
    }

    public mutating func merge(_ other: LatencyHistogram) {
        for i in counts.indices { counts[i] += other.counts[i] }
        count += other.count
        sum += other.sum
        max = Swift.max(max, other.max)
    }

    /// Sunucuyla aynı hesap: istenen sıranın düştüğü kovada doğrusal ara değer; üst sınır en fazla `max`.
    public func percentile(_ p: Double) -> Int? {
        guard count > 0 else { return nil }
        let rank = Swift.max(1e-9, p * Double(count))
        var cum = 0.0
        for (i, c) in counts.enumerated() where c > 0 {
            if cum + Double(c) >= rank {
                let lower = Double(i == 0 ? 0 : Self.edges[i - 1])
                var upper = i < Self.edges.count ? Double(Self.edges[i]) : Swift.max(Double(max), lower)
                if Double(max) >= lower && Double(max) < upper { upper = Double(max) }
                return Int((lower + (rank - cum) / Double(c) * (upper - lower)).rounded())
            }
            cum += Double(c)
        }
        return max
    }

    /// `{"n", "sum", "max", "h"}`; sondaki sıfır kovalar atılır.
    public var jsonValue: TelemetryValue {
        var h = counts
        while let last = h.last, last == 0, !h.isEmpty { h.removeLast() }
        return .object(["n": .int(count), "sum": .int(sum), "max": .int(max), "h": .array(h.map { .int($0) })])
    }
}

/// Bir çeviri oturumunun süre ölçümleri. Ölçüm adları: `ocr`, `tr.cache`, `tr.pack`, `tr.pool`, `tr.provider`,
/// `tr.provider:<ad>`, `tr.total`, `first_frame`, `first_subtitle`.
public struct SessionTimings: Equatable, Sendable {
    public enum Metric {
        public static let ocr = "ocr"
        public static let cache = "tr.cache"
        public static let pack = "tr.pack"
        public static let pool = "tr.pool"
        public static let provider = "tr.provider"
        public static let total = "tr.total"
        public static let firstFrame = "first_frame"
        public static let firstSubtitle = "first_subtitle"
        /// `tr.provider:deepl` gibi; ad geçersizse yalnız `tr.provider`.
        public static func provider(_ name: String) -> String {
            let clean = name.lowercased()
            return clean.range(of: #"^[a-z0-9_-]{1,24}$"#, options: .regularExpression) != nil ? "tr.provider:\(clean)" : provider
        }
    }

    public static let maxMetrics = 24
    private static let metricPattern = #"^[a-z0-9_.]{1,32}(:[a-z0-9_-]{1,24})?$"#

    public private(set) var histograms: [String: LatencyHistogram] = [:]

    public init() {}

    /// Süreyi ekler. Geçersiz ad ya da 24 ölçümden fazlası sessizce atlanır.
    public mutating func record(_ metric: String, ms: Int) {
        guard metric.range(of: Self.metricPattern, options: .regularExpression) != nil else { return }
        if histograms[metric] == nil, histograms.count >= Self.maxMetrics { return }
        histograms[metric, default: LatencyHistogram()].record(ms)
    }

    /// Çevirmenden gelen satır: hem genel `tr.provider` hem adıyla ayrı tutulur.
    public mutating func recordProvider(_ name: String, ms: Int) {
        record(Metric.provider, ms: ms)
        let named = Metric.provider(name)
        if named != Metric.provider { record(named, ms: ms) }
    }

    public var isEmpty: Bool { histograms.isEmpty }

    public var jsonValue: TelemetryValue {
        .object(histograms.filter { $0.value.count > 0 }.mapValues { $0.jsonValue })
    }
}
