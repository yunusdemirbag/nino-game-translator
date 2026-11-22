// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation

// MARK: - Kartın çerçevesi (tarif §9.3)

extension GameReading.MapCardFinder {
    /// Koyu kartın açık harita üstündeki çerçevesi. `pixels` 640 × 360 (değilse küçültülür).
    public static func frame(around text: GameReading.Box, pixels input: GameReading.PhonePixels) -> GameReading.Box? {
        let p = input.resized(width: 640, height: 360)
        func dark(_ x: Double, _ y: Double) -> Bool? {
            let px = Int(x * 640), py = Int(y * 360)
            guard px >= 0, py >= 0, px < 640, py < 360 else { return nil }
            return p.color(px, py).luma < 130
        }
        var ys: [Double] = [], xs: [Double] = []
        var y = text.top; while y <= text.bottom + 1e-9 { ys.append(y); y += 0.02 }
        var x = text.left; while x <= text.right + 1e-9 { xs.append(x); x += 0.03 }
        func mostlyDark(_ pts: [(Double, Double)]) -> Bool {
            let v = pts.compactMap { dark($0.0, $0.1) }
            return !v.isEmpty && v.filter { $0 }.count * 2 >= v.count
        }
        /// Bir yöne ilerler; ince açık şerit için 2–4 adım ileri bakar. (mesafe, sınıra ulaştı mı)
        func walk(step: Double, limit: Double, probe: (Double) -> [(Double, Double)]) -> (Double, Bool) {
            var d = 0.0
            while d + step <= limit + 1e-9 {
                if mostlyDark(probe(d + step)) { d += step; continue }
                var jumped = false
                for k in 2...4 where d + step * Double(k) <= limit + 1e-9 {
                    if mostlyDark(probe(d + step * Double(k))) { d += step * Double(k); jumped = true; break }
                }
                if !jumped { return (d, false) }
            }
            return (d, true)
        }
        let l = walk(step: 0.003, limit: 0.04) { d in ys.map { (text.left - d, $0) } }
        let r = walk(step: 0.003, limit: 0.09) { d in ys.map { (text.right + d, $0) } }
        let b = walk(step: 0.004, limit: 0.08) { d in xs.map { ($0, text.bottom + d) } }
        let t = walk(step: 0.004, limit: 0.06) { d in xs.map { ($0, text.top - d) } }
        // Bulunan kenar son koyu örnekle ilk açık örnek arasındadır: kutu ilk açık örneğe kadar uzar (kart tam örtülür).
        let box = GameReading.Box(left: l.1 ? text.left - 0.015 : text.left - l.0 - 0.003,
                                  top: t.1 ? text.top - 0.02 : text.top - t.0 - 0.004,
                                  right: r.1 ? text.right + 0.02 : text.right + r.0 + 0.003,
                                  bottom: b.1 ? text.bottom + 0.02 : text.bottom + b.0 + 0.004).clamped
        guard box.width >= text.width - 1e-9, box.height >= text.height - 1e-9 else { return nil }
        return box
    }
}

// MARK: - Yerleşim (tarif §9.5; 22 Kasım'dan beri kartın üstüne oturur)

extension GameReading {
    public enum MapCardLayout {
        /// Görüntüdeki çerçeveye eklenen pay ("bir tık fazlası").
        static let margin = 0.003

        /// Çeviri kartın koyu panelini tam ve biraz fazlasıyla örter (üst şerit, başlık, cümleler, alt satırlar;
        /// yer değiştirmez). Panel kenarı görüntüden bulunursa o, bulunamazsa yazı kutusu her yandan ~0,6 satır
        /// paylı. Görüntüdeki çerçeve yazı kutusunu solda en çok 0,014, üstte 0,02, sağda/altta 0,035 aşar (koyu
        /// haritada kenar bulunamaz, yürüyüş soldaki yer adının üstüne taşar; 17:18 karesi). Yazı küçülmez:
        /// sığmazsa kutu aşağı uzar; yalnız ekranın altına varınca satır boyu küçülür.
        public static func element(_ card: MapCard, title: String?, sentences: [String], stats: [String] = [],
                                   header: String? = nil, imageFrame: Box?) -> ScreenElement {
            let lhc = min(max(card.lineHeight, 0.024), 0.034)
            let lh0 = lhc * 0.9
            let pad = 0.6 * min(lhc, 0.03)
            let t = card.box
            // Görüntüden çerçeve varsa yazı kutusuna yalnız küçük pay; yoksa ~0,6 satır.
            let p = imageFrame == nil ? pad : 0.004
            let textArea = Box(left: t.left - p, top: t.top - p, right: t.right + p, bottom: t.bottom + p)
            let reach = Box(left: t.left - 0.014, top: t.top - 0.02, right: t.right + 0.035, bottom: t.bottom + 0.035)
            let image = imageFrame.map { f in
                Box(left: max(f.left, reach.left) - margin, top: max(f.top, reach.top) - margin,
                    right: min(f.right, reach.right) + margin, bottom: min(f.bottom, reach.bottom) + margin)
            }
            var frame = (image ?? textArea).union(textArea).clamped
            let width = frame.width
            let lines = [header, title].compactMap { $0 } + sentences + stats
            func rows(_ lh: Double) -> Int {
                let letter = lh * 0.42 * 9 / 16
                var n = 0
                for s in lines { n += max(1, Int(ceil(Double(s.count) * letter / max(1e-6, width - 0.03)))) }
                return n
            }
            func needed(_ lh: Double) -> Double { Double(rows(lh)) * lh * 1.32 + 0.022 }
            let floor = 0.98
            var lh = lh0
            let minLine = 0.016
            while lh > minLine, frame.top + needed(lh) > floor { lh = max(minLine, lh - 0.001) }
            if needed(lh) > frame.height { frame.bottom = min(floor, frame.top + needed(lh)) }
            var style = ScreenElement.Style(lineHeight: lh)
            style.card = true
            return ScreenElement(kind: .map, id: "kart", box: frame, text: lines.joined(separator: "\n"), style: style)
        }
    }
}

// MARK: - Gösterme kuralları (tarif §9.4)

extension GameReading {
    public struct MapCardPresenter: Sendable {
        public struct Job: Equatable, Sendable {
            public var key: String
            public var card: MapCard
            public var frame: Box?
            /// Başlık mekân adıysa çevrilmez.
            public var venue: Bool
        }

        public enum Step: Equatable, Sendable {
            case show(ScreenElement)
            case remove
            case translate(Job)
        }

        public static let memoryCapacity = 200
        public var requireTitleOrSixWords = true

        public private(set) var shown: (key: String, card: MapCard, element: ScreenElement)?
        public private(set) var inFlight: Job?
        public private(set) var pending: Job?
        private var memory: [String: (title: String?, sentences: [String], stats: [String], header: String?)] = [:]
        /// Aynı kartın (başlık ve yeri aynı) gösterilenden farklı okuması ve kaç kez üst üste görüldüğü.
        private var rival: (key: String, count: Int)?
        /// Aynı kartın farklı okuması gösterilenin yerine ancak bu kadar üst üste görülünce geçer (iki okuma arasında
        /// gidip gelme TV'de titreme yapıyordu).
        public var confirmations = 3
        private var memoryOrder: [String] = []

        public init() {}

        public var isShowing: Bool { shown != nil }

        /// Hafıza anahtarı: metin + alt satırların okunan biçimi (değeri eksik okunan kart ayrı tutulur) + üst şerit.
        static func memoryKey(_ c: MapCard) -> String {
            Text.key(c.fullText) + "|" + c.stats.map { $0.label + ($0.value == nil ? "" : "=") }.joined(separator: ",")
                + "|" + (c.header.map(Text.key) ?? "")
        }

        /// Kartın ne kadar eksiksiz okunduğu (alt satır + değer sayısı, üst şerit).
        static func statsScore(_ c: MapCard) -> Int {
            c.stats.count + c.stats.filter { $0.value != nil }.count + (c.header == nil ? 0 : 1)
        }

        func hidden(_ c: MapCard) -> Bool {
            if MapCardText.hasTurkishLetters(c.fullText) || c.sentences.isEmpty { return true }
            if requireTitleOrSixWords, c.title == nil, c.wordCount < 6 { return true }
            if c.title == nil, c.box.left > 0.6, c.box.top < 0.32 { return true }
            if c.box.top < 0.1 { return true }
            return false
        }

        /// Menü okumasının kartı (ya da `nil`).
        public mutating func observe(_ card: MapCard?, frame: Box?, menuOpen: Bool) -> [Step] {
            guard menuOpen else { return removeAll() }
            guard let card else { return removeAll() }
            if hidden(card) { return [] }
            let key = card.key
            if let s = shown {
                // Aynı metin; alt satırları daha eksiksiz okunduysa (ilk okuma `LOW`u kaçırmış olabilir) yenilenir.
                if s.key == key, Self.statsScore(card) <= Self.statsScore(s.card) {
                    rival = nil
                    return []
                }
                if s.key != key, s.card.title == card.title, Text.key(s.card.fullText).hasPrefix(Text.key(card.fullText)) { return [] }
                // Aynı kart, başka okuma: uzatan okuma hemen geçer; başkası ancak üst üste `confirmations` kez görülünce.
                let same = s.card.title == card.title && abs(s.card.box.top - card.box.top) < 0.04
                if same, s.key != key, !Text.key(card.fullText).hasPrefix(Text.key(s.card.fullText)) {
                    let n = rival?.key == key ? rival!.count + 1 : 1
                    rival = (key, n)
                    if n < confirmations { return [] }
                }
            }
            rival = nil
            if inFlight?.key == key || pending?.key == key { return [] }
            var steps: [Step] = []
            let sameCard = shown.map { $0.card.title == card.title && abs($0.card.box.top - card.box.top) < 0.04 } ?? false
            if shown != nil, !sameCard { shown = nil; steps.append(.remove) }
            let venue = card.title.map { MapCardText.isVenue(title: $0, description: card.sentences.first) } ?? false
            let job = Job(key: key, card: card, frame: frame, venue: venue)
            if let m = memory[Self.memoryKey(card)] {
                // Süren çevirinin sonucu artık eskidir.
                inFlight = nil; pending = nil
                steps.append(show(job, title: m.title, sentences: m.sentences, stats: m.stats, header: m.header))
                return steps
            }
            if inFlight != nil { pending = job; return steps }
            inFlight = job
            steps.append(.translate(job))
            return steps
        }

        mutating func removeAll() -> [Step] {
            pending = nil
            inFlight = nil
            rival = nil
            guard shown != nil else { return [] }
            shown = nil
            return [.remove]
        }

        mutating func show(_ job: Job, title: String?, sentences: [String], stats: [String] = [], header: String? = nil) -> Step {
            let el = MapCardLayout.element(job.card, title: title, sentences: sentences, stats: stats, header: header,
                                           imageFrame: job.frame)
            shown = (job.key, job.card, el)
            return .show(el)
        }

        /// Çeviri bitti. `title` Türkçe büyük harfli (ya da mekân adı), cümleler düzeltilmiş.
        /// `stats`: kartın alt satırlarının çevirisi (`GÜVENLİK: DÜŞÜK`), kartla aynı sırada; `header` üst şeridin.
        public mutating func finished(_ job: Job, title: String?, sentences: [String], stats: [String] = [],
                                      header: String? = nil, menuOpen: Bool) -> [Step] {
            let current = inFlight?.key == job.key
            if current { inFlight = nil }
            if !sentences.isEmpty {
                let mk = Self.memoryKey(job.card)
                if memory[mk] == nil { memoryOrder.append(mk) }
                memory[mk] = (title, sentences, stats, header)
                if memoryOrder.count > Self.memoryCapacity { memory[memoryOrder.removeFirst()] = nil }
            }
            if let p = pending {
                pending = nil
                if let m = memory[Self.memoryKey(p.card)] {
                    return [show(p, title: m.title, sentences: m.sentences, stats: m.stats, header: m.header)]
                }
                inFlight = p
                return [.translate(p)]
            }
            guard current, menuOpen, !sentences.isEmpty else { return [] }
            return [show(job, title: title, sentences: sentences, stats: stats, header: header)]
        }
    }
}

// MARK: - Harita kartı izleyici

extension GameReading {
    /// Köşe turunun menü araması satırlarıyla harita kartını izler, çevirir ve öğe verir.
    public actor MapCardWatcher {
        public enum Change: Equatable, Sendable {
            case set(ScreenElement)
            case remove
        }

        private var presenter = MapCardPresenter()
        private let translator: PhoneTranslator?
        private let clock: Clock
        private var menuOpen = false
        private var phoneGame = false
        private var mapSeenAt = Int.min / 2
        /// Harita ekranı (tuşlar) bu kadar süre önce görüldüyse kart aranır.
        public var mapMemoryMs = 10_000

        public init(translator: PhoneTranslator?, clock: Clock) { self.translator = translator; self.clock = clock }

        public var isShowing: Bool { presenter.isShowing }

        /// Gösterilen kartın oyundaki yazı alanı (görüntü değişimi için; `ScreenItemSender`).
        public var shownArea: Box? { presenter.shown?.card.box }

        /// Yalnız telefon oyununda (GTA 6) çalışır; kapanınca kart kalkar.
        public func setPhoneGame(_ on: Bool) -> [Change] {
            phoneGame = on
            return on ? [] : menuClosed()
        }

        /// `lines` kare oranında menü araması satırları; `image` çerçeve için (yoksa yazı alanı).
        /// Kart yalnız harita ekranında (tuşlar son 10 sn'de görüldü) aranır. `see` + `finish` bir arada.
        public func observe(_ lines: [Line], image: CGImage?, menuOpen open: Bool) async -> [Change] {
            let quick = see(lines, image: image, menuOpen: open).changes
            return quick + (await finish())
        }

        /// Çeviri beklemeden verilebilen değişiklikler (kaldırma, hafızadan gösterme). Çeviri gerekiyorsa sıraya
        /// konur; `finish` yapar. `switched`: gösterilen kart başka bir kartla değişti (eski kart hemen kalkmalı,
        /// gönderici tutmamalı; yeni kartın çevirisi beklenmez).
        public func see(_ lines: [Line], image: CGImage?, menuOpen open: Bool) -> (changes: [Change], switched: Bool) {
            menuOpen = open
            guard phoneGame else { return ([], false) }
            let now = clock.nowMs
            if MapScreen.isMapScreen(lines.map(\.text)) { mapSeenAt = now }
            let onMap = now - mapSeenAt <= mapMemoryMs
            let card = onMap ? MapCardFinder.find(lines) : nil
            var frame: Box?
            if let card, let image, let px = PhonePixels.from(image, width: 640, height: 360) {
                frame = MapCardFinder.frame(around: card.box, pixels: px)
            }
            var out: [Change] = []
            for step in presenter.observe(card, frame: frame, menuOpen: open) {
                switch step {
                case .remove: out.append(.remove)
                case .show(let e): out.append(.set(e))
                case .translate: queued.append(step)
                }
            }
            return (out, card != nil && out.contains(.remove))
        }

        /// `see`in sıraya koyduğu çeviriyi yapar.
        public func finish() async -> [Change] {
            let q = queued
            queued = []
            return await run(q)
        }

        private var queued: [MapCardPresenter.Step] = []

        /// Menü bayrağı sona erdi.
        public func menuClosed() -> [Change] {
            menuOpen = false
            queued = []
            return presenter.observe(nil, frame: nil, menuOpen: false).compactMap { $0 == .remove ? .remove : nil }
        }

        private func run(_ steps: [MapCardPresenter.Step]) async -> [Change] {
            var out: [Change] = []
            var queue = steps
            while !queue.isEmpty {
                switch queue.removeFirst() {
                case .remove: out.append(.remove)
                case .show(let e): out.append(.set(e))
                case .translate(let job):
                    let (title, sentences, stats, header) = await translate(job)
                    queue.append(contentsOf: presenter.finished(job, title: title, sentences: sentences, stats: stats,
                                                                header: header, menuOpen: menuOpen))
                }
            }
            return out
        }

        func translate(_ job: MapCardPresenter.Job) async -> (String?, [String], [String], String?) {
            guard let t = translator else { return (nil, [], [], nil) }
            let card = job.card
            var parts = card.sentences
            let titlePart = card.title.map(MapCardText.titleCase)
            if let tp = titlePart, !job.venue { parts.insert(tp, at: 0) }
            let headerPart = card.header.map(MapCardText.titleCase)
            if let hp = headerPart, !parts.contains(hp) { parts.insert(hp, at: 0) }
            // Alt satırların etiketleri ve harfli değerleri (`Security`, `Low`); rakamlı değerler olduğu gibi kalır.
            let statParts = card.stats.flatMap { s -> [String] in
                [MapCardText.titleCase(s.label)]
                    + (s.value.map { v in MapCardText.translatableValue(v) ? [MapCardText.titleCase(v)] : [] } ?? [])
            }
            for p in statParts where !parts.contains(p) { parts.append(p) }
            var result: [String: String] = [:]
            var unknown: [String] = []
            for p in parts {
                if let k = await t.known(p) { result[p] = k } else { unknown.append(p) }
            }
            if !unknown.isEmpty, t.asksPool {
                let a = await t.askPool(unknown, context: [])
                for (i, p) in unknown.enumerated() where i < a.count { if let v = a[i], !v.isEmpty { result[p] = v } }
                unknown = unknown.filter { result[$0] == nil }
            }
            if !unknown.isEmpty {
                let done = await withTaskGroup(of: (String, String?).self) { g -> [(String, String?)] in
                    for p in unknown { g.addTask { (p, try? await t.translateOnDevice(p)) } }
                    var o: [(String, String?)] = []
                    for await r in g { o.append(r) }
                    return o
                }
                for (p, v) in done { if let v, !v.isEmpty { result[p] = v } }
            }
            /// Çevirmen değiştirmeden döndürdüyse (özel ad: `Karin Futo`) özgün büyük harfli yazı kalır (`KARİN` olmaz).
            func upper(_ part: String, original: String) -> String {
                guard let v = result[part], Text.key(v) != Text.key(part) else { return original }
                return MapCardText.turkishUpper(MapCardText.fixTerms(PhoneText.clean(v)))
            }
            var title: String? = card.title
            if let tp = titlePart, let ct = card.title, !job.venue { title = upper(tp, original: ct) }
            let sentences = card.sentences.compactMap { s in result[s].map { MapCardText.fixTerms(PhoneText.clean($0)) } }
            let stats = card.stats.map { s -> String in
                func tr(_ x: String) -> String {
                    result[MapCardText.titleCase(x)].map { MapCardText.turkishUpper(PhoneText.clean($0)) } ?? x
                }
                let label = tr(s.label)
                guard let v = s.value else { return label }
                return label + ": " + (MapCardText.translatableValue(v) ? tr(v) : v)
            }
            let header = headerPart.map { upper($0, original: card.header!) }
            return (title, sentences.count == card.sentences.count ? sentences : [], stats, header)
        }
    }
}
