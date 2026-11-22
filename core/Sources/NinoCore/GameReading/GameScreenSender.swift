// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// MARK: - TV'ye giden ekran öğeleri (oyun-okuma.md "Ekran öğesi gönderici")

extension GameReading {
    /// `ElementsBoard` listesinden TV'ye gidecek `screen` / `screen-clear` kararını verir (Mac ve iOS ortak).
    ///
    /// - Liste değişince gönderir; değişmeyen ve ekranda duran liste TV'deki süre (`layerDurationMs`) dolmadan,
    ///   yarısında bir yeniden gönderilir.
    /// - Tutulan türlerin (bugün yalnız harita kartı) kalkmasında histerezis: öğe, türü en az `misses` ardışık
    ///   gözlemde görülmezse, en az `minGoneMs` geçtiyse ve oyundaki kaynak bölgesi görüntüsel olarak değiştiyse
    ///   kalkar. Aynı türden başka öğe gelirse hemen değişir; `drop` ile istenen türler hemen kalkar.
    /// - Süreyle tutulan türler (telefon paneli): liste türü bir an kaybederse öğeler `timedHoldMs` kadar kalır
    ///   (yenisi gelince değişir, `drop` ile ya da süre dolunca `refresh` içinde kalkar).
    /// - Yazısız öğe (zemin hariç) gitmez; kutuları yalnız `boxTolerance` kadar oynamış liste "aynı" sayılır.
    ///
    /// Saat dışarıdan verilir; görüntü 640 × 360 `PhonePixels` olarak verilir.
    public struct ScreenItemSender: Sendable {
        public enum Message: Equatable, Sendable {
            case screen([ScreenElement])
            case clear
        }

        public struct Settings: Equatable, Sendable {
            /// Kalkması histerezisle olan türler.
            public var holdKinds: Set<ScreenElement.Kind> = [.map]
            /// Kalkması için ardışık kaçırma sayısı (yalnız türün gözlendiği turlar sayılır).
            public var misses = 3
            /// Son görülmeden bu yana en az bu kadar süre.
            public var minGoneMs = 4_000
            /// Bölge imzasının ortalama parlaklık farkı (0–255) bunu aşarsa bölge "değişti" sayılır.
            public var changeThreshold = 10.0
            /// Değişmeyen liste bu süre sonra yeniden gönderilir.
            public var refreshAfterMs = ScreenElement.layerDurationMs / 2
            /// Süreyle tutulan türler: liste bu türü bir an kaybederse (izleyici paneli yeniden kuruyor) öğeler en çok bu
            /// kadar TV'de kalır; aynı türden yeni öğeler gelince hemen değişir, `drop` ile hemen kalkar.
            public var timedHoldMs: [ScreenElement.Kind: Int] = [.phone: 3_000]
            /// Kutular bu kadar (karenin oranı) oynadıysa liste değişmiş sayılmaz (okuma/takip titremesi).
            public var boxTolerance = 0.005
            public init() {}
        }

        struct Held: Sendable {
            var element: ScreenElement
            var lastSeenMs: Int
            var misses: Int
            var source: Box?
            var look: [Double]?
            /// Son listede var mı (yoksa yalnız TV'de tutuluyor)?
            var present = true
        }

        public var settings: Settings
        public private(set) var sent: [ScreenElement] = []
        public private(set) var sentAtMs = Int.min / 2
        private var held: [String: Held] = [:]
        /// Süreyle tutulanlar: anahtar → (öğe, son görülme).
        private var timed: [String: (element: ScreenElement, lastSeenMs: Int)] = [:]

        public init(settings: Settings = Settings()) { self.settings = settings }

        public static func key(_ e: ScreenElement) -> String { "\(e.kind.rawValue):\(e.id)" }

        /// Bu türden bir öğe TV'de mi (tutulan dahil)?
        public func isShowing(_ kind: ScreenElement.Kind) -> Bool { sent.contains { $0.kind == kind } }

        /// Bu türden tutulan (okumada kaybolmuş ama TV'de bırakılan) öğe var mı?
        public func isHolding(_ kind: ScreenElement.Kind) -> Bool { held.values.contains { $0.element.kind == kind && !$0.present } }

        /// Yeni liste. `observed`: bu turda okunup karar verilen türler (kaçırma yalnız bunlarda sayılır);
        /// `pixels` o turun karesi (640 × 360); `sources` öğe anahtarı → oyundaki kaynak bölgesi;
        /// `drop`: tutulan öğeleri hemen kalkacak türler (menü kapandı, oyun değişti…).
        public mutating func update(_ list: [ScreenElement], nowMs: Int, observed: Set<ScreenElement.Kind> = [],
                                    pixels: PhonePixels? = nil, sources: [String: Box] = [:],
                                    drop: Set<ScreenElement.Kind> = []) -> Message? {
            // Yazısız öğe gitmez (zemin hariç: telefonun üstünü örter).
            let list = list.filter { $0.style.backdrop || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            var current: [String: ScreenElement] = [:]
            for e in list { current[Self.key(e)] = e }
            updateTimed(list, nowMs: nowMs, drop: drop)
            // Görülenler.
            for (k, e) in current where settings.holdKinds.contains(e.kind) {
                var h = held[k] ?? Held(element: e, lastSeenMs: nowMs, misses: 0, source: nil, look: nil)
                if h.element != e || observed.contains(e.kind) || held[k] == nil { h.lastSeenMs = nowMs }
                h.element = e
                h.misses = 0
                h.present = true
                if let s = sources[k] { h.source = s }
                if let px = pixels, let s = h.source, observed.contains(e.kind) { h.look = Self.look(px, s) }
                held[k] = h
            }
            // Kaybolanlar.
            for (k, var h) in held where current[k] == nil {
                let kind = h.element.kind
                if drop.contains(kind) || list.contains(where: { $0.kind == kind }) || !settings.holdKinds.contains(kind) {
                    held[k] = nil
                    continue
                }
                h.present = false
                if observed.contains(kind) {
                    h.misses += 1
                    let changed: Bool
                    if let px = pixels, let s = h.source, let old = h.look {
                        changed = Self.difference(old, Self.look(px, s)) > settings.changeThreshold
                    } else {
                        changed = true
                    }
                    if h.misses >= settings.misses, nowMs - h.lastSeenMs >= settings.minGoneMs, changed {
                        held[k] = nil
                        continue
                    }
                }
                held[k] = h
            }
            lastList = list
            lastHeld = held.filter { current[$0.key] == nil }.map(\.value.element)
            return compose(nowMs: nowMs)
        }

        private var lastList: [ScreenElement] = []
        private var lastHeld: [ScreenElement] = []

        private mutating func compose(nowMs: Int) -> Message? {
            var effective = lastList + lastHeld
            let keys = Set(effective.map(Self.key))
            for (k, t) in timed where !keys.contains(k) { effective.append(t.element) }
            effective.sort { ($0.kind.rawValue, $0.id) < ($1.kind.rawValue, $1.id) }
            guard !Self.same(effective, sent, tolerance: settings.boxTolerance) else { return nil }
            return send(effective, nowMs: nowMs)
        }

        private mutating func updateTimed(_ list: [ScreenElement], nowMs: Int, drop: Set<ScreenElement.Kind>) {
            let kinds = Set(list.map(\.kind))
            for (k, t) in timed {
                let kind = t.element.kind
                if drop.contains(kind) || kinds.contains(kind) || nowMs - t.lastSeenMs >= (settings.timedHoldMs[kind] ?? 0) { timed[k] = nil }
            }
            for e in list where settings.timedHoldMs[e.kind] != nil { timed[Self.key(e)] = (e, nowMs) }
        }

        /// Aynı öğeler, aynı yazı ve biçim; kutular yalnız `tolerance` kadar oynamış.
        public static func same(_ a: [ScreenElement], _ b: [ScreenElement], tolerance: Double) -> Bool {
            guard a.count == b.count else { return false }
            return zip(a, b).allSatisfy { x, y in
                x.kind == y.kind && x.id == y.id && x.text == y.text && x.style == y.style
                    && abs(x.box.left - y.box.left) <= tolerance && abs(x.box.right - y.box.right) <= tolerance
                    && abs(x.box.top - y.box.top) <= tolerance && abs(x.box.bottom - y.box.bottom) <= tolerance
            }
        }

        /// Değişmeyen ama ekranda duran liste TV'deki süre dolmadan yeniden gönderilir; süresi dolan tutulan öğe kalkar.
        public mutating func refresh(nowMs: Int) -> Message? {
            if timed.contains(where: { nowMs - $0.value.lastSeenMs >= (settings.timedHoldMs[$0.value.element.kind] ?? 0) }) {
                // Listede hâlâ olanlar yeniden "görüldü" sayılır; yalnız kaybolmuşların süresi işler.
                updateTimed(lastList, nowMs: nowMs, drop: [])
                if let m = compose(nowMs: nowMs) { return m }
            }
            guard !sent.isEmpty, needsRefresh(nowMs: nowMs) else { return nil }
            return send(sent, nowMs: nowMs)
        }

        /// Bu türden süreyle tutulan (listeden düşmüş ama TV'de bırakılan) öğe var mı?
        public func isHoldingTimed(_ kind: ScreenElement.Kind) -> Bool {
            let present = Set(lastList.map(Self.key))
            return timed.contains { $0.value.element.kind == kind && !present.contains($0.key) }
        }

        public func needsRefresh(nowMs: Int) -> Bool { nowMs - sentAtMs >= settings.refreshAfterMs }

        /// Gönderilen unutulur: bir sonraki `update` listeyi (boş değilse) yeniden gönderir. Tutulanlar da unutulur.
        public mutating func forgetSent() {
            sent = []
            held = [:]
            timed = [:]
            lastHeld = []
        }

        /// Her şey unutulur; TV'de öğe varsa `.clear` döner.
        public mutating func reset() -> Message? {
            let had = !sent.isEmpty
            sent = []
            held = [:]
            timed = [:]
            lastList = []
            lastHeld = []
            sentAtMs = Int.min / 2
            return had ? .clear : nil
        }

        private mutating func send(_ list: [ScreenElement], nowMs: Int) -> Message {
            sent = list
            sentAtMs = nowMs
            return list.isEmpty ? .clear : .screen(list)
        }

        // MARK: Bölge imzası

        static let lookColumns = 24, lookRows = 12

        /// Bölgenin küçük gri imzası (24 × 12 parlaklık örneği).
        public static func look(_ pixels: PhonePixels, _ box: Box) -> [Double] {
            let b = box.clamped
            var out: [Double] = []
            out.reserveCapacity(lookColumns * lookRows)
            for r in 0..<lookRows {
                let y = b.top + (Double(r) + 0.5) / Double(lookRows) * b.height
                let py = min(pixels.height - 1, max(0, Int(y * Double(pixels.height))))
                for c in 0..<lookColumns {
                    let x = b.left + (Double(c) + 0.5) / Double(lookColumns) * b.width
                    let px = min(pixels.width - 1, max(0, Int(x * Double(pixels.width))))
                    out.append(pixels.color(px, py).luma)
                }
            }
            return out
        }

        /// İki imzanın ortalama mutlak farkı.
        public static func difference(_ a: [Double], _ b: [Double]) -> Double {
            guard a.count == b.count, !a.isEmpty else { return .infinity }
            return zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) } / Double(a.count)
        }
    }
}
