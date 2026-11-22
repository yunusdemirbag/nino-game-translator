// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// MARK: - Bekletme (§8.2–8.4)

extension GameReading {
    /// Sabitleyicinin "çevir" dediği okumayı kısa bir süre bekletir; o sürede gelen daha
    /// iyi okuma onun yerine geçer.
    public struct SendGate: Sendable {
        public struct Settings: Sendable {
            public var enabled = true
            public var brokenHoldMs = 800
            public var partialHoldMs = 300
            public var rereadWindowMs = 4_000
            public init() {}
        }

        /// Gönderilecek okuma.
        public struct Reading: Equatable, Sendable {
            public var text: String
            public var box: Box?
            /// Okumanın başladığı an.
            public var startedAt: Int
            public var holdMs: Int
            public var score: Int
            public var inPack: Bool
        }

        public var settings: Settings
        /// Pakette var mı (önce adlı satır, yoksa adsız gövde).
        public var isInPack: @Sendable (String) -> Bool
        public private(set) var pending: Reading?
        private var lastSent: (text: String, at: Int)?
        private var lastClearAt = Int.min

        public init(settings: Settings = Settings(), isInPack: @escaping @Sendable (String) -> Bool = { _ in false }) {
            self.settings = settings
            self.isInPack = isInPack
        }

        func inPack(_ text: String) -> Bool {
            if isInPack(text) { return true }
            let body = Text.lines(text).map { Speaker.split($0)?.body ?? $0 }.joined(separator: "\n")
            return body != text && isInPack(body)
        }

        func holdFor(_ text: String) -> Int {
            if Similarity.isBroken(text) { return settings.brokenHoldMs }
            if !Similarity.isComplete(text) { return settings.partialHoldMs }
            return 0
        }

        func expired(_ p: Reading, now: Int) -> Bool { now - p.startedAt >= p.holdMs }

        /// Sabitleyici "çevir" dedi.
        public mutating func onTranslate(_ text: String, box: Box?, now: Int) -> [Reading] {
            guard let p = pending else { return process(text, box: box, now: now) }
            let newPack = inPack(text)
            if newPack { pending = nil; return process(text, box: box, now: now) }
            var merged = p
            merged.holdMs = max(p.holdMs, holdFor(text))
            if Similarity.addsMeaningMarker(text, to: p.text), Similarity.isCorrection(text, of: p.text) {
                merged.text = keepMissingLines(new: text, old: p.text)
                merged.box = box ?? p.box
                merged.score = Filters.score(merged.text)
                return settle(merged, now: now)
            }
            if Similarity.isReread(text, of: p.text) || Similarity.isReread(p.text, of: text), !expired(merged, now: now) {
                let s = Filters.score(text)
                if s > p.score {
                    merged.text = keepMissingLines(new: text, old: p.text)
                    merged.box = box ?? p.box
                    merged.score = s
                }
                pending = merged
                return []
            }
            if Similarity.isBroken(p.text) { pending = nil; return process(text, box: box, now: now) }
            if Similarity.isBroken(text), !Similarity.isRelated(text, p.text), !expired(merged, now: now) {
                pending = merged
                return []
            }
            pending = nil
            return [markSent(p, now: now)] + process(text, box: box, now: now)
        }

        /// Sabitleyici "temizle" ya da "geri getir" dedi.
        public mutating func onClearOrRestore(now: Int) -> [Reading] {
            lastClearAt = now
            guard let p = pending else { return [] }
            pending = nil
            return Similarity.isBroken(p.text) ? [] : [markSent(p, now: now)]
        }

        /// Tepki yok; her karede çağrılır (bekleme dolunca gönderir).
        public mutating func onNone(_ reading: String?, box: Box?, now: Int) -> [Reading] {
            guard var p = pending else { return [] }
            if let r = reading, Text.key(r).count >= 3, Similarity.isRelated(r, p.text) {
                let s = Filters.score(r)
                if s > p.score { p.text = keepMissingLines(new: r, old: p.text); p.box = box ?? p.box; p.score = s }
            }
            return settle(p, now: now)
        }

        public mutating func reset() { pending = nil; lastSent = nil; lastClearAt = Int.min }

        private mutating func settle(_ p: Reading, now: Int) -> [Reading] {
            if expired(p, now: now) { pending = nil; return [markSent(p, now: now)] }
            pending = p
            return []
        }

        private mutating func markSent(_ r: Reading, now: Int) -> Reading {
            lastSent = (r.text, now)
            return r
        }

        private mutating func process(_ text: String, box: Box?, now: Int) -> [Reading] {
            let pack = inPack(text)
            var r = Reading(text: text, box: box, startedAt: now, holdMs: 0, score: Filters.score(text), inPack: pack)
            guard settings.enabled else { return [markSent(r, now: now)] }
            if let last = lastSent, now - last.at <= settings.rereadWindowMs, !pack || last.at > lastClearAt {
                let sentLines = Text.lines(last.text)
                let all = Text.lines(text).allSatisfy { l in
                    sentLines.contains { s in Similarity.isSameSubtitle(l, sentLines: [s]) || Similarity.isReread(l, of: s) }
                }
                if all, r.score <= Filters.score(last.text) { return [] }
            }
            if pack { return [markSent(r, now: now)] }
            r.holdMs = holdFor(text)
            if r.holdMs == 0 { return [markSent(r, now: now)] }
            pending = r
            return []
        }

        /// Daha iyi okuma bekleyenin yerine geçerken bekleyende olup yenisinde olmayan temiz satırlar korunur.
        func keepMissingLines(new: String, old: String) -> String {
            let newKey = Text.key(new)
            let missing = Text.lines(old).filter { l in
                let k = Text.key(l)
                return !k.isEmpty && !newKey.contains(k) && !Similarity.isBroken(l)
                    && !Text.lines(new).contains { Similarity.isReread($0, of: l) || Similarity.isReread(l, of: $0) || Text.ratio($0, l) >= 0.75 }
            }
            return ([new] + missing).joined(separator: "\n")
        }
    }
}

// MARK: - Çeviri sırası (§8.5–8.7)

extension GameReading {
    /// Çevirmenden bağımsız çeviri sırası. Uygulama `translate` eylemini çevirmene verir,
    /// sonucu `finished` ile geri bildirir.
    public struct TranslationQueue: Sendable {
        public struct Settings: Sendable {
            public var maxWaiting = 2
            public var lateMs = 2_500
            public var onScreenMs = 15_000
            public var alreadyTargetSimilarity = 0.90
            public init() {}
        }

        public struct Request: Equatable, Sendable {
            public var id: Int
            public var text: String
            public var box: Box?
            /// Paketteki çeviri (varsa hemen gösterilir).
            public var packTranslation: String?
            /// Kutunun altı taban çizgisinin üstünde mi (§8.5 adım 3).
            public var offBaseline: Bool

            public init(id: Int, text: String, box: Box? = nil, packTranslation: String? = nil, offBaseline: Bool = false) {
                self.id = id; self.text = text; self.box = box; self.packTranslation = packTranslation; self.offBaseline = offBaseline
            }
        }

        public enum Action: Equatable, Sendable {
            case translate(Request)
            case show(id: Int, text: String, durationMs: Int, replace: Bool, fromPack: Bool)
            /// TV'deki eski çeviriyi kaldır.
            case hide(id: Int)
            case cancel(id: Int)
            case dropped(id: Int)
            /// Çeviri başarısız ve satır ekranda: sabitleyici satırı unutsun.
            case failed(id: Int)
            /// Havuza önerilecek satır.
            case proposeToPool(text: String)
            /// Satır zaten hedef dilde (köşeler 15 sn çevrilmesin).
            case alreadyTarget(id: Int)
        }

        public var settings: Settings
        public var isTargetLanguage: @Sendable (String) -> Bool

        public private(set) var translating: Request?
        public private(set) var waiting: [Request] = []
        private var onScreenID: Int?
        private var removedAt: [Int: Int] = [:]
        private var requests: [Int: Request] = [:]
        private var lastShown: (id: Int, source: String)?
        private var superseded: Set<Int> = []

        public init(settings: Settings = Settings(),
                    isTargetLanguage: @escaping @Sendable (String) -> Bool = TranslationQueue.looksTurkish) {
            self.settings = settings
            self.isTargetLanguage = isTargetLanguage
        }

        /// Varsayılan hedef dil denetimi: en az iki Türkçe harf (tek bulaşık harf yetmez).
        public static let looksTurkish: @Sendable (String) -> Bool = { text in
            text.filter { "ğışçöüĞİŞÇÖÜ".contains($0) }.count >= 2
        }

        public mutating func enqueue(_ r: Request, now: Int) -> [Action] {
            var out: [Action] = []
            requests[r.id] = r
            let previousScreen = onScreenID
            onScreenID = r.id
            if let p = previousScreen, p != r.id, removedAt[p] == nil { removedAt[p] = now }

            if isTargetLanguage(r.text), r.packTranslation == nil {
                if let last = lastShown, last.id == previousScreen { out.append(.hide(id: last.id)) }
                out.append(.alreadyTarget(id: r.id))
                return out
            }
            if r.offBaseline {
                if let pack = r.packTranslation {
                    let words = Text.words(r.text).filter { $0.contains(where: \.isLetter) }.count
                    if words < 3 { return out }
                    return out + showPack(r, pack, now: now)
                }
                if !Similarity.isBroken(r.text) { out.append(.proposeToPool(text: r.text)) }
                return out
            }
            if let pack = r.packTranslation { return out + showPack(r, pack, now: now) }
            out.append(.proposeToPool(text: r.text))
            guard let current = translating else {
                translating = r
                return out + [.translate(r)]
            }
            // Süren çeviri bu okumanın yarımıysa bırakılır.
            if Similarity.isExtension(r.text, of: current.text) {
                superseded.insert(current.id)
                translating = r
                waiting.removeAll { Similarity.isCorrection(r.text, of: $0.text) && r.text.count >= $0.text.count }
                return out + [.cancel(id: current.id), .translate(r)]
            }
            for w in waiting where Similarity.isCorrection(r.text, of: w.text) && r.text.count >= w.text.count {
                out.append(.dropped(id: w.id))
            }
            waiting.removeAll { Similarity.isCorrection(r.text, of: $0.text) && r.text.count >= $0.text.count }
            waiting.append(r)
            while waiting.count > settings.maxWaiting { out.append(.dropped(id: waiting.removeFirst().id)) }
            return out
        }

        /// Ekrandaki satır kalktı.
        public mutating func lineRemoved(id: Int, now: Int) {
            if removedAt[id] == nil { removedAt[id] = now }
            if onScreenID == id { onScreenID = nil }
        }

        /// Satır geri geldi (geri getir): yeniden ekranda sayılır.
        public mutating func lineRestored(id: Int) {
            removedAt[id] = nil
            if let p = onScreenID, p != id, removedAt[p] == nil { removedAt[p] = Int.max / 2 }
            onScreenID = id
        }

        public mutating func finished(id: Int, translation: String?, now: Int) -> [Action] {
            var out: [Action] = []
            if translating?.id == id { translating = nil }
            defer { superseded.remove(id) }
            if let r = requests[id], !superseded.contains(id) {
                out += decide(r, translation: translation, now: now)
            } else {
                out.append(.dropped(id: id))
            }
            return out + startNext(now: now)
        }

        /// Her karede: bırakılacak çeviri var mı?
        public mutating func tick(now: Int) -> [Action] {
            guard let t = translating, onScreenID != t.id else { return [] }
            let newerShown = (lastShown?.id ?? 0) > t.id
            let late = removedAt[t.id].map { now - $0 > settings.lateMs } ?? false
            let showable = waiting.contains { $0.id > t.id && isShowable($0, now: now) }
            guard newerShown || (late && showable) else { return [] }
            superseded.insert(t.id)
            translating = nil
            return [.cancel(id: t.id)] + startNext(now: now)
        }

        public mutating func reset() -> [Action] {
            let ids = ([translating?.id].compactMap { $0 }) + waiting.map(\.id)
            translating = nil; waiting = []; onScreenID = nil; removedAt = [:]; requests = [:]; lastShown = nil; superseded = []
            return ids.map { .cancel(id: $0) }
        }

        private func isShowable(_ r: Request, now: Int) -> Bool {
            if onScreenID == r.id { return true }
            guard let at = removedAt[r.id] else { return true }
            return now - at <= settings.lateMs
        }

        private func duration(_ r: Request, _ text: String) -> Int {
            onScreenID == r.id ? settings.onScreenMs : min(8_000, 2_000 + 60 * text.count)
        }

        private mutating func showPack(_ r: Request, _ pack: String, now: Int) -> [Action] {
            var out = waiting.map { Action.dropped(id: $0.id) }
            waiting = []
            if let t = translating { superseded.insert(t.id) }
            let hidden = Text.ratio(pack, r.text) >= settings.alreadyTargetSimilarity && r.text.contains(where: { "ğışçöüĞİŞÇÖÜ".contains($0) })
            if hidden { return out }
            let replace = lastShown.map { Similarity.isCorrection(r.text, of: $0.source) } ?? false
            lastShown = (r.id, r.text)
            out.append(.show(id: r.id, text: pack, durationMs: duration(r, pack), replace: replace, fromPack: true))
            return out
        }

        private mutating func decide(_ r: Request, translation: String?, now: Int) -> [Action] {
            guard let text = translation else {
                return onScreenID == r.id ? [.failed(id: r.id)] : [.dropped(id: r.id)]
            }
            if let last = lastShown, last.id > r.id { return [.dropped(id: r.id)] }
            if !isShowable(r, now: now) { return [.dropped(id: r.id)] }
            if Text.ratio(text, r.text) >= settings.alreadyTargetSimilarity {
                var out: [Action] = [.alreadyTarget(id: r.id)]
                if let last = lastShown { out.append(.hide(id: last.id)) }
                return out
            }
            let replace = lastShown.map { Similarity.isCorrection(r.text, of: $0.source) } ?? false
            lastShown = (r.id, r.text)
            return [.show(id: r.id, text: text, durationMs: duration(r, text), replace: replace, fromPack: false)]
        }

        private mutating func startNext(now: Int) -> [Action] {
            guard translating == nil else { return [] }
            var out: [Action] = []
            while let next = waiting.first {
                waiting.removeFirst()
                if isShowable(next, now: now) {
                    translating = next
                    out.append(.translate(next))
                    break
                }
                out.append(.dropped(id: next.id))
            }
            return out
        }
    }
}
