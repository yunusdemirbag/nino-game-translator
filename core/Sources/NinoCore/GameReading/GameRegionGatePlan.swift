// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// MARK: - Bölge (§2)

extension GameReading {
    public enum RegionPreset: String, Codable, Sendable, CaseIterable {
        case bottom, top, fullFrame, custom

        public var box: Box? {
            switch self {
            case .bottom: return Box(left: 0.14, top: 0.62, right: 0.86, bottom: 0.97)
            case .top: return Box(left: 0.14, top: 0.03, right: 0.86, bottom: 0.38)
            case .fullFrame: return .full
            case .custom: return nil
            }
        }
    }

    /// Altyazı bölgesi.
    public struct Region: Equatable, Sendable, Codable {
        public static let minimumSize = 0.05
        public private(set) var box: Box

        public init(_ box: Box = RegionPreset.bottom.box!) { self.box = Region.fit(box) }
        public init(preset: RegionPreset) { self.init(preset.box ?? RegionPreset.bottom.box!) }

        /// Kayıt bir hazır seçime 0,001 payla eşitse o seçim, değilse özel.
        public var preset: RegionPreset {
            for p in RegionPreset.allCases {
                guard let b = p.box else { continue }
                if abs(b.left - box.left) <= 0.001, abs(b.top - box.top) <= 0.001,
                   abs(b.right - box.right) <= 0.001, abs(b.bottom - box.bottom) <= 0.001 { return p }
            }
            return .custom
        }

        /// Kaydırır; kareden taşmaz.
        public mutating func move(dx: Double, dy: Double) {
            var b = box
            b.left += dx; b.right += dx; b.top += dy; b.bottom += dy
            box = Region.fit(b)
        }

        /// Boyutlandırır (sağ-alt köşe); en küçük boy 0,05, taşarsa yukarı/sola kayar.
        public mutating func resize(width: Double, height: Double) {
            box = Region.fit(Box(left: box.left, top: box.top, right: box.left + width, bottom: box.top + height))
        }

        /// Dikey kaydırıcılar: konum = üst × 100, yükseklik = (alt − üst) × 100.
        public var sliderPosition: Double { box.top * 100 }
        public var sliderHeight: Double { (box.bottom - box.top) * 100 }

        static func fit(_ b: Box) -> Box {
            var w = min(1, max(minimumSize, b.width)), h = min(1, max(minimumSize, b.height))
            w = min(w, 1); h = min(h, 1)
            var left = max(0, b.left), top = max(0, b.top)
            if left + w > 1 { left = 1 - w }
            if top + h > 1 { top = 1 - h }
            return Box(left: left, top: top, right: left + w, bottom: top + h)
        }

        /// Okunacak alan: öğrenilen şerit varsa üst `şerit_üst − 0,05` (§2.2).
        public func readingArea(stripTop: Double?) -> Box {
            guard let stripTop else { return box }
            let top = stripTop - 0.05
            if top > box.top, top <= box.bottom - 0.06 {
                return Box(left: box.left, top: top, right: box.right, bottom: box.bottom)
            }
            return box
        }
    }
}

// MARK: - Tek kare kapısı (§1)

extension GameReading {
    public struct FrameGate: Sendable {
        public enum Entry: Equatable, Sendable {
            case admitted(ticket: Int)
            case skipped
            /// Okuma takıldı; kapı sıfırlandı, hat yeniden kurulmalı.
            case stuck(elapsedMs: Int)
        }

        public var stuckLimitMs = 45_000
        public var fallbackLimitMs = 9_000
        /// Yedek okuyucu devrede mi?
        public var fallbackActive = false

        private var holder: (ticket: Int, since: Int)?
        private var nextTicket = 1

        public init() {}

        public var isBusy: Bool { holder != nil }

        /// Kapıyı bu numara mı tutuyor?
        public func holds(_ ticket: Int) -> Bool { holder?.ticket == ticket }

        public mutating func enter(now: Int) -> Entry {
            if let h = holder {
                let elapsed = now - h.since
                let limit = fallbackActive ? fallbackLimitMs : stuckLimitMs
                if elapsed >= limit {
                    holder = nil
                    return .stuck(elapsedMs: elapsed)
                }
                return .skipped
            }
            let t = nextTicket
            nextTicket += 1
            holder = (t, now)
            return .admitted(ticket: t)
        }

        /// Yalnız kapıyı tutan numara kapıyı açar.
        @discardableResult
        public mutating func exit(ticket: Int) -> Bool {
            guard holder?.ticket == ticket else { return false }
            holder = nil
            return true
        }

        public mutating func reset() { holder = nil }
    }
}

// MARK: - Okuma planı (§3)

extension GameReading {
    /// İz aynıysa son okuma yeniden kullanılır. İz, **son gerçek okumanın** iziyle karşılaştırılır (yavaş solma
    /// kare kare eşiğin altında kalsa da birikir); altyazı bandında eşik daha duyarlıdır; süre verilirse son
    /// okumadan `maxReuseMs` sonra iz aynı görünse de yeniden okunur (sabit görüntüde altyazı kaçmasın).
    public struct ReadPlan: Sendable {
        public enum Decision: Equatable, Sendable {
            case reuse
            case read(deep: Bool)
        }

        /// −1: iz her zaman değişmiş sayılır.
        public var threshold: Int
        public var reuseLimit: Int
        public var deepEvery: Int
        /// Altyazı bandının içindeki eşik (yalnız altyazı satırı değişti, arka plan sabit).
        public var bandThreshold: Int
        /// Son gerçek okumadan bu kadar ms sonra iz aynı da olsa okunur (`now` verildiğinde). 0: süre sınırı yok.
        public var maxReuseMs: Int

        private(set) var lastFingerprint: Fingerprint?
        /// Son gerçek okumanın izi.
        private(set) var readFingerprint: Fingerprint?
        private(set) var lastReadAt: Int?
        private(set) var hasReading = false
        private var reuseCount = 0
        private(set) var emptyCount = 0
        /// Son okuma yalnız süre sınırı dolduğu için mi yapıldı (iz aynı görünüyordu)? Teşhis içindir.
        public private(set) var lastReadByTimeLimit = false

        public init(threshold: Int = 16, reuseLimit: Int = 20, deepEvery: Int = 3, bandThreshold: Int = 8, maxReuseMs: Int = 1_500) {
            self.threshold = threshold; self.reuseLimit = reuseLimit; self.deepEvery = deepEvery
            self.bandThreshold = bandThreshold; self.maxReuseMs = maxReuseMs
        }

        /// Hızlı altyazı algılama açıkken yeniden kullanım 2.
        public static func standard(fastDetection: Bool) -> ReadPlan {
            ReadPlan(reuseLimit: fastDetection ? 2 : 20)
        }

        /// Testlerin "her zaman" planı.
        public static let always = ReadPlan(threshold: -1, reuseLimit: 0, deepEvery: 1)

        /// `now` (ms) verilirse süre sınırı uygulanır; `band` alan içi altyazı bandıdır (`nil`: bütün alan).
        /// Bir sonraki karar iz aynı da olsa okumadır (bekletilen satır yeniden okunsun).
        public mutating func forceNextRead() { forceRead = true }
        private var forceRead = false

        public mutating func decide(_ fp: Fingerprint, now: Int? = nil, band: Box? = nil) -> Decision {
            defer { lastFingerprint = fp; forceRead = false }
            if !forceRead, threshold >= 0, hasReading, reuseCount < reuseLimit, let ref = readFingerprint ?? lastFingerprint,
               !fp.changed(from: ref, threshold: threshold),
               !fp.changed(from: ref, threshold: min(threshold, bandThreshold), within: band),
               !timeIsUp(now) {
                reuseCount += 1
                return .reuse
            }
            lastReadByTimeLimit = !forceRead && threshold >= 0 && hasReading && reuseCount < reuseLimit
                && (readFingerprint ?? lastFingerprint).map { ref in
                    !fp.changed(from: ref, threshold: threshold) && !fp.changed(from: ref, threshold: min(threshold, bandThreshold), within: band)
                } ?? false
            reuseCount = 0
            readFingerprint = fp
            if let now { lastReadAt = now }
            return .read(deep: deepEvery > 0 && emptyCount % deepEvery == 0)
        }

        private func timeIsUp(_ now: Int?) -> Bool {
            guard maxReuseMs > 0, let now, let last = lastReadAt else { return false }
            return now - last >= maxReuseMs
        }

        /// Her OCR'dan sonra: boşsa sayaç artar, doluysa 1 olur.
        public mutating func record(empty: Bool) {
            hasReading = true
            emptyCount = empty ? emptyCount + 1 : 1
        }

        public mutating func reset() {
            lastFingerprint = nil; readFingerprint = nil; lastReadAt = nil; hasReading = false; reuseCount = 0; emptyCount = 0
            lastReadByTimeLimit = false
        }
    }
}
