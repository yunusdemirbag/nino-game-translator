// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Zamanlı sabitleyici (tarif §7).
extension GameReading {
    public struct Stabilizer: Sendable {
        public enum Reaction: Equatable, Sendable {
            case none
            case translate(String)
            case clear
            /// Kalkan satır döndü; ilk gönderilen metin.
            case restore(String)
        }

        public struct Settings: Sendable {
            public var similarity = 0.85
            public var clearAfterMovedMs = 800
            public var holdUnmovedMs = 4_000
            public var restoreWindowMs = 1_500
            public var retryAfterMs = 1_000
            public var junkStableMs = 700
            public var historySize = 5
            public init() {}
        }

        struct Shown: Sendable {
            var reading: String
            /// İlk gönderilen metin.
            var sent: String
            var box: Box?
            var fingerprint: Fingerprint?
        }

        public var settings: Settings
        private(set) var shown: Shown?
        private var goneAt: Int?
        private var emptySince: Int?
        private var candidate: (text: String, count: Int, since: Int)?
        private var history: [(shown: Shown, removedAt: Int)] = []
        private var failed: (text: String, retryAt: Int)?

        public init(settings: Settings = Settings()) { self.settings = settings }

        /// Ekrandaki satırın ilk gönderilen metni.
        public var shownText: String? { shown?.sent }

        /// Bir okuma. `text` satırları alt alta; `box` alan içi, `fingerprint` bölge izi.
        public mutating func observe(_ text: String?, box: Box? = nil, fingerprint: Fingerprint? = nil, now: Int) -> Reaction {
            let reading = (text ?? "").split(separator: "\n").map { Text.squeeze(String($0)) }.filter { !$0.isEmpty }.joined(separator: "\n")

            // 1. Kısa okuma boştur.
            if Text.key(reading).count < 3, !Self.isShortAnswer(reading) {
                candidate = nil
                guard let s = shown else { return .none }
                let moved: Bool
                if let fp = fingerprint, let old = s.fingerprint, let b = s.box {
                    moved = fp.changed(from: old, within: b)
                } else {
                    moved = true
                }
                if moved, goneAt == nil { goneAt = now }
                if emptySince == nil { emptySince = now }
                if let g = goneAt, now - g >= settings.clearAfterMovedMs { return clearShown(now: now) }
                if let e = emptySince, now - e >= settings.holdUnmovedMs { return clearShown(now: now) }
                return .none
            }

            // 2. Aday.
            if let c = candidate, Text.ratio(reading, c.text) >= settings.similarity {
                candidate = (reading, c.count + 1, c.since)
            } else {
                candidate = (reading, 1, now)
            }
            let c = candidate!

            // 3. Hazır mı?
            let ready: Bool
            if Filters.looksLikeJunk(reading) {
                ready = c.count >= 2 && now - c.since >= settings.junkStableMs
            } else {
                ready = c.count >= 2 || Text.endsSentence(reading)
            }

            // 4. Ekrandakinin aynısı ya da başına çöp eklenmiş hâli.
            if let s = shown {
                let sk = Text.key(s.sent), rk = Text.key(reading)
                let prefixJunk = sk.count >= 12 && rk.count > sk.count && rk.hasSuffix(sk)
                // Ekrandaki satırın son okunuşunun aynısı da sayılır (gönderilenle ilgiliyse): solarken bozulan
                // `/shut the capin dog up. man`, son okunan `Shut the damn dog up, man!`'e benzer.
                let sameAsLast = s.reading != s.sent && Similarity.isRelated(reading, s.sent)
                    && Similarity.isSameSubtitle(reading, sentLines: Text.lines(s.reading))
                let sameAsSent = Similarity.isSameSubtitle(reading, sentLines: Text.lines(s.sent))
                if prefixJunk || sameAsLast || sameAsSent {
                    // Yalnız son okunuşa benzeyen daha kötü okuma, karşılaştırma yazısını bozmasın.
                    if prefixJunk || sameAsSent || Filters.score(reading) >= Filters.score(s.reading) { shown?.reading = reading }
                    if let box { shown?.box = box }
                    if let fingerprint { shown?.fingerprint = fingerprint }
                    goneAt = nil
                    emptySince = nil
                    return .none
                }
            }

            // 5.
            guard ready else { return .none }

            // 6. Daha kötü yeniden okuma.
            if let s = shown, Similarity.isWorseReread(reading, than: s.sent) || Similarity.isMalformedReread(reading, of: s.sent)
                || (s.reading != s.sent && Similarity.isRelated(reading, s.sent) && Similarity.isWorseReread(reading, than: s.reading)) {
                return .none
            }

            // 7. Az önce kalkan satır döndü.
            if let i = history.lastIndex(where: { now - $0.removedAt <= settings.restoreWindowMs
                && Similarity.isSameSubtitle(reading, sentLines: Text.lines($0.shown.sent)) }) {
                var back = history.remove(at: i).shown
                back.reading = reading
                if let box { back.box = box }
                if let fingerprint { back.fingerprint = fingerprint }
                if let s = shown { remember(s, now: now) }
                shown = back
                goneAt = nil
                emptySince = nil
                return .restore(back.sent)
            }

            // 8. Çevirisi az önce başarısız oldu.
            if let f = failed, now < f.retryAt, Similarity.isSameSubtitle(reading, sentLines: Text.lines(f.text)) { return .none }

            // 9. Yeni satır.
            if let s = shown { remember(s, now: now) }
            shown = Shown(reading: reading, sent: reading, box: box, fingerprint: fingerprint)
            goneAt = nil
            emptySince = nil
            failed = nil
            return .translate(reading)
        }

        /// 2 harfli gerçek kısa cevap (`OK.`, `No.`, `Go!`): büyük harfle başlar, noktalama ile biter.
        static func isShortAnswer(_ text: String) -> Bool {
            Text.regex(#"^[A-Z][A-Za-z][.!?]+$"#, text, caseInsensitive: false)
        }

        /// Çeviri başarısız oldu: satır unutulur, en erken 1 sn sonra yeniden denenir.
        public mutating func forget(now: Int) {
            guard let s = shown else { return }
            failed = (s.sent, now + settings.retryAfterMs)
            shown = nil
            goneAt = nil
            emptySince = nil
        }

        /// Sıfırlama: ekranda satır varsa temizle.
        public mutating func reset() -> Reaction {
            let had = shown != nil
            shown = nil; goneAt = nil; emptySince = nil; candidate = nil; history = []; failed = nil
            return had ? .clear : .none
        }

        private mutating func clearShown(now: Int) -> Reaction {
            if let s = shown { remember(s, now: now) }
            shown = nil
            goneAt = nil
            emptySince = nil
            return .clear
        }

        private mutating func remember(_ s: Shown, now: Int) {
            history.append((s, now))
            if history.count > settings.historySize { history.removeFirst(history.count - settings.historySize) }
        }
    }
}
