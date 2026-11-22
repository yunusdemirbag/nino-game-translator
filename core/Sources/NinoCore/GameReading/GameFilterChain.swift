// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation

// MARK: - Telefon (ayrı tarif; burada yalnız arayüz)

extension GameReading {
    /// Telefon bilgisi. Telefon/harita tarifi ayrı turdadır; uygulama bunu doldurur.
    public struct PhoneContext: Sendable {
        /// Karedeki telefonun kutusu (kare oranı). Son 5 sn içinde bulunan yer de geçerlidir.
        public var box: Box?
        /// Telefonda son okunan yazılar.
        public var recentTexts: [String]
        /// Son 30 sn'de telefonda yazı okundu mu?
        public var textSeenRecently: Bool
        /// Telefon son 10 sn'de görüldü mü (kart gösterme kuralı)?
        public var seenWithin10s: Bool
        /// Telefon uygulamasının kendi yazısı mı?
        public var isAppText: @Sendable (String) -> Bool

        public init(box: Box? = nil, recentTexts: [String] = [], textSeenRecently: Bool = false, seenWithin10s: Bool = false,
                    isAppText: @escaping @Sendable (String) -> Bool = { _ in false }) {
            self.box = box; self.recentTexts = recentTexts; self.textSeenRecently = textSeenRecently
            self.seenWithin10s = seenWithin10s; self.isAppText = isAppText
        }

        public static let none = PhoneContext()

        /// Maske kutusu: alt `max(alt, min(alt + 0,15, 0,84))`, 0,01 pay.
        public var maskBox: Box? {
            guard var b = box else { return nil }
            b.bottom = max(b.bottom, min(b.bottom + 0.15, 0.84))
            return Box(left: b.left - 0.01, top: b.top - 0.01, right: b.right + 0.01, bottom: b.bottom + 0.01).clamped
        }
    }

    /// Kare başına telefon bilgisini veren her şey (telefon tarifi geldiğinde yazılacak).
    public protocol PhoneTracker: Sendable {
        func context(for frame: Frame, now: Int) async -> PhoneContext
    }

    /// Bir kutusu siyaha boyanmış kare (telefon maskesi).
    public struct MaskedFrame: Frame {
        public let base: Frame
        public let mask: Box
        public init(_ base: Frame, mask: Box) { self.base = base; self.mask = mask }
        public var pixelWidth: Int { base.pixelWidth }
        public var pixelHeight: Int { base.pixelHeight }
        public var image: CGImage? { base.image.flatMap { paint($0, area: .full, scale: 1) } }

        public func fingerprint(of box: Box) -> Fingerprint {
            guard let img = crop(box, scale: 1) else { return base.fingerprint(of: box) }
            return Fingerprint.make(from: img)
        }

        public func crop(_ box: Box, scale: Double) -> CGImage? {
            guard let cut = base.crop(box, scale: scale) else { return nil }
            return paint(cut, area: box, scale: scale)
        }

        func paint(_ image: CGImage, area: Box, scale: Double) -> CGImage? {
            guard mask.intersects(area) else { return image }
            let w = image.width, h = image.height
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            let m = mask.local(in: area).clamped
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: m.left * Double(w), y: (1 - m.bottom) * Double(h), width: m.width * Double(w), height: m.height * Double(h)))
            return ctx.makeImage()
        }
    }
}

// MARK: - Süzgeç sırası (§6)

extension GameReading {
    public struct FilterChain: Sendable {
        public struct Context {
            public var now: Int
            /// Okunan alan (kare oranı).
            public var area: Box
            public var frame: Frame?
            public var phone: PhoneContext = .none
            /// Telefon oyunu (havuz öncelikli oyun).
            public var phoneGame = false
            /// Mesaj kartı işleyicisi bağlı.
            public var cardsEnabled = false
            public var questLine: Double? = 0.895
            public var baseline: Double?
            public var menuOpen = false
            /// "Yalnız altyazıyı çevir": görev/ipucu/sekme satırları ana bloktan atılır (telefon oyununda kapalı).
            public var subtitlesOnly = false
            /// Öğrenilen altyazı şeridi (kare oranı; yalnız altyazı kuralı için).
            public var strip: (top: Double, bottom: Double)?
            /// Ekrandaki (ya da az önce kalkan) altyazı cümleyi bitirmemişti (`And after what we went through,`):
            /// küçük harfle başlayan blok onun devamı olabilir. Kutusu kare oranında.
            public var openPrevious: Box?
            /// Ekrandaki altyazının metni (aynı satırın sonraki okumaları küçük harf kuralına takılmasın).
            public var currentText: String?
            /// Küçük harfle başlayan, ortadaki satır hemen atılmaz; kararlı görünürse okunur (belirirken kısmi okuma
            /// ile gerçek devam satırını ayırır). `false`: eski davranış.
            public var lowercaseWait = false

            public init(now: Int, area: Box, frame: Frame? = nil) { self.now = now; self.area = area; self.frame = frame }
        }

        public struct Result: Equatable, Sendable {
            /// Seçilen blok, alan içi kutular.
            public var lines: [Line] = []
            /// Satırlar alt alta; boşsa `nil`.
            public var text: String?
            /// Blok kutusu, alan içi.
            public var localBox: Box?
            /// Blok kutusu, kare oranında ve ortalanmış.
            public var box: Box?
            /// İpucu satırları, kare oranında.
            public var hints: [Line] = []
            public var card: Cards.Card?
            public var call: Cards.Call?
            /// Okuma neden boşaltıldı (günlük için).
            public var emptied: String?
            /// Atılan yazılar ve nedenleri (teşhis günlüğü).
            public var notes: [Output.Note] = []
            /// Bir sonraki kare iz aynı da olsa yeniden okunmalı (küçük harfli satır bekletiliyor).
            public var rereadSoon = false
        }

        /// Küçük harfli satırın bu kadar ms aynı okunması gerekir.
        public var lowercaseStableMs = 400
        private var lowercasePending: (key: String, since: Int)?

        public var staleMs = 9_000
        public var callWindowMs = 6_000
        public var cardWindowMs = 6_000
        private var firstSeen: [String: Int] = [:]
        private var lastCall: (name: String, at: Int)?
        private var lastCard: (text: String, at: Int)?

        public init() {}

        public mutating func reset() { firstSeen = [:]; lastCall = nil; lastCard = nil; lowercasePending = nil }

        public mutating func run(_ input: [Line], _ c: Context) -> Result {
            var r = Result()
            let area = c.area
            func frameBox(_ l: Line) -> Box? { l.box?.mapped(into: area) }

            // Konuşmaya benzeyen satır hangi adımda kayboldu (sessiz süzgeçlerin teşhisi).
            // Not yalnız satırı gerçekten atan adıma yazılır: adımdan önce konuşmaya benzeyen satır vardı, sonra yok.
            var lostAt: String?
            var alive = input.contains { Self.dialogueLike($0.text) }
            func track(_ stage: String, _ ls: [Line]) {
                let now = ls.contains { Self.dialogueLike($0.text) }
                if alive, !now, lostAt == nil { lostAt = stage }
                alive = now
            }
            let hadDialogue = alive
            // 4. Harfsiz satırlar.
            var lines = input.filter { Filters.hasEnoughLetters($0.text) }
            track("harfsiz", lines)
            // 5. Telefon üstündeki satırlar.
            if let pb = c.phone.box {
                lines = lines.filter { l in frameBox(l).map { !pb.contains(x: $0.midX, y: $0.midY, padding: 0.02) } ?? true }
                track("telefonun üstünde", lines)
            }
            // 6. Mesaj köşesi.
            var cornerCard: Cards.Card?
            if c.phoneGame, c.cardsEnabled {
                let corner = lines.filter { l in frameBox(l).map { $0.left >= 0.66 && $0.top >= 0.74 } ?? false }
                if !corner.isEmpty {
                    lines.removeAll { corner.contains($0) }
                    cornerCard = Cards.card(corner, area: area)
                    if let cc = cornerCard { lastCard = (cc.body, c.now) }
                    track(cornerCard == nil ? "sağ alt köşe (kart tanınmadı)" : "sağ alt köşe (mesaj kartı)", lines)
                }
            }
            // 7. Açık zeminde koyu yazı (telefon balonu).
            if c.phoneGame, let image = c.frame?.image {
                lines = lines.filter { l in frameBox(l).map { !Self.darkOnLight(image, box: $0) } ?? true }
                track("açık zeminde koyu yazı", lines)
            }
            // 8. Telefon uygulaması yazıları.
            lines = lines.filter { !c.phone.isAppText($0.text) }
            track("telefon uygulaması yazısı", lines)
            // 9. Telefon açıkken yukarıdaki yazı.
            if c.phone.box != nil || c.phone.textSeenRecently {
                let limit = max(c.baseline ?? 0, 0.8)
                lines = lines.filter { l in frameBox(l).map { $0.midY >= limit } ?? true }
                track("telefon açıkken yukarıda", lines)
            }
            // 10. Telefonda görülen yazı.
            if !c.phone.recentTexts.isEmpty {
                let keys = c.phone.recentTexts.map(Text.key)
                lines = lines.filter { l in
                    Text.words(l.text).count < 3 || !keys.contains { $0.contains(Text.key(l.text)) }
                }
                track("telefonda görülen yazı", lines)
            }
            // 11. Görev çizgisi.
            if let q = c.questLine {
                var kept: [Line] = []
                let speakers = lines.filter { Speaker.split($0.text) != nil }
                for l in lines {
                    guard let b = frameBox(l) else { kept.append(l); continue }
                    if Speaker.split(l.text) != nil || b.top < q { kept.append(l); continue }
                    let continues = speakers.contains { s in
                        guard let sb = frameBox(s) else { return false }
                        return b.top > sb.top && b.top - sb.bottom < max(0.02, b.height * 1.5)
                    }
                    if continues { kept.append(l) }
                }
                lines = kept
                track("görev çizgisinin altında", lines)
            }
            // 12. Eski duran yazı.
            var seen: [String: Int] = [:]
            for l in lines { let k = Text.key(l.text); seen[k] = firstSeen[k] ?? c.now }
            firstSeen = seen
            let ages = lines.map { c.now - (seen[Text.key($0.text)] ?? c.now) }
            if ages.contains(where: { $0 < staleMs }) {
                for (l, age) in zip(lines, ages) where age >= staleMs { r.notes.append(Output.Note(.stale, text: l.text)) }
                lines = zip(lines, ages).filter { $0.1 < staleMs }.map(\.0)
            }
            // 13. Dev satırlar.
            lines = Filters.dropGiantLines(lines, area: area)
            track("dev satır", lines)
            let beforeCenter = lines
            // 13b. Yalnız altyazı (telefon oyununun kendi kuralları var).
            if c.subtitlesOnly, !c.phoneGame {
                let f = Filters.SubtitlesOnly.filterWithDrops(lines, area: area, strip: c.strip)
                lines = f.kept
                r.notes += f.dropped.map { Output.Note(.subtitlesOnly($0.1), text: $0.0.text) }
            }
            // 14. Orta şart.
            if c.phoneGame {
                lines = lines.filter { l in frameBox(l).map { abs($0.midX - 0.5) <= 0.12 } ?? true }
            }
            if c.phoneGame { track("ortada değil", lines) }
            // 15. Zincir.
            var block = Self.chain(lines, area: area, labels: true, phoneGame: c.phoneGame)
            track("ipucu/etiket/blok seçimi", block)
            // 16. Kart için ikinci bakış.
            if c.cardsEnabled {
                let second = Self.chain(beforeCenter, area: area, labels: false, phoneGame: c.phoneGame)
                if let call = Cards.call(second, area: area) { r.call = call }
                else if let card = Cards.card(second, area: area) { r.card = card }
            }
            if r.card == nil, let cc = cornerCard { r.card = cc }
            var text = block.map(\.text).joined(separator: "\n")
            let blockText = text
            // 17. Menü bayrağı.
            if c.menuOpen, !block.isEmpty { block = []; r.emptied = "menu" }
            if c.cardsEnabled, !block.isEmpty {
                text = block.map(\.text).joined(separator: "\n")
                // 18. Küçük harfle başlayan blok; cümleyi bitirmemiş altyazının aynı şeritteki devamı korunur.
                if text.first?.isLowercase == true, !Self.continues(block, area: area, previous: c.openPrevious),
                   !(c.lowercaseWait && c.currentText.map { Similarity.isSameSubtitle(text, sentLines: Text.lines($0)) } == true) {
                    let phoneActive = c.phone.box != nil || c.phone.textSeenRecently || c.phone.seenWithin10s
                    let centered = Box.union(block.compactMap(\.box)).map { abs($0.mapped(into: area).midX - 0.5) <= 0.12 } ?? false
                    if c.lowercaseWait, !phoneActive, centered {
                        // Satır belirirken sonu okunmuş olabilir (`breakfast.`): bekletilir, kısa aralıkla yeniden okunur;
                        // aynı metin `lowercaseStableMs` boyunca okunursa gerçek satırdır (`they'll have that here.`).
                        let key = Text.key(text)
                        if let p = lowercasePending, Text.ratio(p.key, key) >= 0.9 {
                            if c.now - p.since < lowercaseStableMs { block = []; r.emptied = "lowercase-wait"; r.rereadSoon = true }
                        } else {
                            lowercasePending = (key, c.now)
                            block = []; r.emptied = "lowercase-wait"; r.rereadSoon = true
                        }
                    } else {
                        block = []; r.emptied = "lowercase"
                    }
                }
                // 19. Mesaj listesi.
                else if Cards.isList(block) { block = []; r.emptied = "list" }
                // 20. Arama ve mesaj kartı.
                else if let call = r.call {
                    lastCall = (call.name, c.now); block = []; r.emptied = "call"
                } else if let last = lastCall, c.now - last.at <= callWindowMs, Text.key(text) == Text.key(last.name) {
                    block = []; r.emptied = "call-name"
                } else if let card = r.card, cornerCard == nil {
                    lastCard = (card.body, c.now); block = []; r.emptied = "card"
                } else if let last = lastCard, c.now - last.at <= cardWindowMs, Cards.repeats(text, card: last.text) {
                    block = []; r.emptied = "card-repeat"
                }
            }
            // 21. Dev blok.
            if !block.isEmpty, Filters.isGiantBlock(block, area: area) { block = []; r.emptied = "giant" }
            if let e = r.emptied, let reason = Self.noteReason(e) { r.notes.insert(Output.Note(reason, text: blockText), at: 0) }
            else if block.isEmpty, hadDialogue, let stage = lostAt,
                    let sample = input.first(where: { Self.dialogueLike($0.text) }) {
                r.notes.append(Output.Note(.filtered(stage), text: sample.text))
            }
            // 22. İpuçları çıkışı.
            r.hints = beforeCenter.compactMap { l in
                let t = Filters.cleanJunk(l.text)
                return Filters.isHint(t) ? Line(t, confidence: l.confidence, box: frameBox(l)) : nil
            }
            // 24. Kutu.
            r.lines = block
            text = block.map(\.text).joined(separator: "\n")
            r.text = text.isEmpty ? nil : text
            r.localBox = Box.union(block.compactMap(\.box))
            r.box = r.localBox.map { Filters.centered($0.mapped(into: area)) }
            return r
        }

        /// Konuşmaya benzeyen satır: en az iki harfli sözcük ve küçük harf (teşhis notu için kaba ölçü).
        static func dialogueLike(_ text: String) -> Bool {
            Text.hasLowercase(text) && Text.words(text).filter { $0.count >= 2 && $0.contains(where: \.isLetter) }.count >= 2
        }

        static func noteReason(_ emptied: String) -> Output.Note.Reason? {
            switch emptied {
            case "menu": return .menu
            case "lowercase": return .lowercase
            case "lowercase-wait": return .lowercaseWaiting
            case "list": return .messageList
            case "call": return .callCard
            case "call-name": return .callName
            case "card": return .messageCard
            case "card-repeat": return .cardRepeat
            case "giant": return .giant
            default: return nil
            }
        }

        /// Blok, cümleyi bitirmemiş önceki altyazının devamı mı: aynı şeritte (dikey ortaları 0,08'den yakın) ve ortada.
        static func continues(_ block: [Line], area: Box, previous: Box?) -> Bool {
            guard let p = previous, let b = Box.union(block.compactMap(\.box))?.mapped(into: area) else { return false }
            return abs(b.midY - p.midY) <= 0.08 && abs(b.midX - 0.5) <= 0.12
        }

        /// İpucu → yol tarifi → çöp temizliği (+ madde imi, telefon oyununda baştaki tabela yazısı) → eşya etiketi →
        /// iki kenar → aynı sıra → blok seçimi → kırpılmış alt satır.
        static func chain(_ lines: [Line], area: Box, labels: Bool, phoneGame: Bool = false) -> [Line] {
            var ls = lines.filter { !Filters.isHint($0.text) && !Filters.isDirection($0.text) }
            ls = ls.compactMap { l in
                var t = Filters.cleanJunk(l.text)
                // Altyazıya özgü temizlik yalnız asıl bakışta (kartın ikinci bakışı mesaj gövdesini korusun).
                if labels { t = Filters.stripLeadingBullets(t) }
                if labels, phoneGame { t = Filters.stripSignPrefix(t) }
                return t.isEmpty ? nil : Line(t, confidence: l.confidence, box: l.box)
            }
            if labels { ls = ls.filter { !Filters.isItemLabel($0.text) } }
            ls = ls.filter { !Filters.touchesBothEdges($0) }
            ls = Filters.mergeSameRow(ls)
            var block = Filters.selectBlock(ls, area: area)
            guard labels else { return block }
            if phoneGame { block = Filters.stripLoneDialogueDash(block) }
            return Filters.dropClippedTail(block)
        }

        /// Satırın kutusunda 6 sıra nokta: açık zeminde koyu yazı mı?
        static func darkOnLight(_ image: CGImage, box: Box) -> Bool {
            guard let cut = ImageFrame(image).crop(box, scale: 1) else { return false }
            let cols = 33, rows = 6
            guard let px = ImageFrame.rgba(cut, width: cols, height: rows) else { return false }
            var v: [Double] = []
            for i in 0..<(cols * rows) { v.append(0.299 * Double(px[i * 4]) + 0.587 * Double(px[i * 4 + 1]) + 0.114 * Double(px[i * 4 + 2])) }
            guard v.count >= 20 else { return false }
            let dark = Text.quantile(v, 0.05)!, mid = Text.median(v)!, bright = Text.quantile(v, 0.95)!
            return mid - dark >= 25 && mid - dark > 2 * (bright - mid)
        }
    }
}
