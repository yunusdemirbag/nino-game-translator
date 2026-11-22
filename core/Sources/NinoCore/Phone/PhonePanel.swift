// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// MARK: - Kararlılık (tarif §6.1, §6.2, §6.4)

extension GameReading {
    /// Telefon panelinin okumadan okumaya kararları. Çeviri dışarıda yapılır.
    public struct PhonePanel: Sendable {
        public struct Shown: Equatable, Sendable {
            public var items: [PhonePanelItem]
            public var kind: PhoneScreenKind
            public var header: String?
            /// Yerleşimin kurulduğu telefon yeri.
            public var phone: PhoneLocation
            public var elements: [ScreenElement]
        }

        public enum Plan: Equatable, Sendable {
            /// Bir şey yapma (panel olduğu gibi kalır).
            case keep
            /// Panel kalkar.
            case remove
            /// Bilinenlerle (ve çevrilecek onaylı bilinmeyenlerle) panel kurulur.
            /// `removeFirst`: önce ekrandaki panel kalkar (sohbet değişti).
            case build(PhoneScreenReading, unknown: [String], context: [String], interim: Bool, removeFirst: Bool)
        }

        public private(set) var shown: Shown?
        public private(set) var lastKey: String?
        /// Bir önceki okumanın mesajları.
        public private(set) var previous: [String] = []

        public init() {}

        public static func isSimilar(_ a: String, _ b: String) -> Bool {
            let x = Text.key(a), y = Text.key(b)
            if x.isEmpty || y.isEmpty { return false }
            if x == y || x.hasPrefix(y) || x.hasSuffix(y) || y.hasPrefix(x) || y.hasSuffix(x) { return true }
            return TextSimilarity.ratio(x, y) >= 0.75
        }

        static func readingKey(_ r: PhoneScreenReading, phone: PhoneLocation) -> String {
            r.messages.map { Text.key($0.text) + "@" + String(Int(floor(($0.box.top - phone.box.top) * 60))) }.joined(separator: "|")
        }

        /// Kesik mesajları atar (§6.2).
        public static func dropPartial(_ r: PhoneScreenReading, phone: PhoneLocation, inMemory: (String) -> Bool) -> PhoneScreenReading {
            guard r.kind == .chat else { return r }
            var c = r
            if let last = c.messages.last, !inMemory(last.text), last.box.bottom > phone.box.bottom - 0.06,
               last.box.height > last.lineHeight * 1.8 {
                let t = last.text.trimmingCharacters(in: .whitespaces)
                let ok = t.last.map { ".!?…\")".contains($0) } ?? false
                if !ok { c.messages.removeLast() }
            }
            // Üstte başlığın altına kırpılmış balon: hafızada olsa da hep atılır (okumadan okumaya girip çıkmasın).
            if c.messages.count > 1, let first = c.messages.first, first.sender == nil, first.text.first?.isLowercase == true,
               first.box.top < phone.box.top + 0.095 {
                c.messages.removeFirst()
            }
            return c
        }

        /// Gösterilen öğeler ↔ okunan mesajlar: benzer metin, telefona göre yeri en yakın, her mesaj bir kez.
        static func match(_ items: [PhonePanelItem], _ oldPhone: PhoneLocation, _ messages: [PhoneMessage],
                          _ phone: PhoneLocation) -> [(PhonePanelItem, PhoneMessage)] {
            var used = Set<Int>()
            var out: [(PhonePanelItem, PhoneMessage)] = []
            for item in items {
                let rel = item.message.box.top - oldPhone.box.top
                let best = messages.indices.filter { !used.contains($0) && isSimilar(messages[$0].text, item.source) }
                    .min { abs(messages[$0].box.top - phone.box.top - rel) < abs(messages[$1].box.top - phone.box.top - rel) }
                if let i = best { used.insert(i); out.append((item, messages[i])) }
            }
            return out
        }

        static func plainHeader(_ h: String?) -> String? {
            guard let h, Text.words(h).count <= 3, !h.contains(where: { ".,!?:;…".contains($0) }) else { return nil }
            return h
        }

        /// Yeni okuma. `lookup`: bilinen Türkçe (sözlük, havuz, hafıza).
        public mutating func plan(_ input: PhoneScreenReading, phone: PhoneLocation, inMemory: (String) -> Bool,
                                  lookup: (String) -> String?) -> Plan {
            let r = Self.dropPartial(input, phone: phone, inMemory: inMemory)
            let texts = r.messages.map(\.text)
            let prev = previous
            previous = texts
            let key = Self.readingKey(r, phone: phone)
            if key == lastKey { return .keep }
            guard !r.messages.isEmpty else { lastKey = key; return .keep }

            var removeFirst = false
            if let s = shown {
                // Kaydırma: her gösterilen mesaj, okunanlardan benzer ve yeri en yakın olanla bire bir eşlenir (grup
                // sohbetinde aynı metin, ör. tek kelimelik cevap, iki kez geçebilir). Kaydırmada bütün mesajlar birlikte
                // kayar: ortanca kayma ölçülür (tek mesajın okuma oynaması kaydırma sayılmaz).
                let common = Self.match(s.items, s.phone, r.messages, phone)
                let shifts = common.map { abs(($0.1.box.top - phone.box.top) - ($0.0.message.box.top - s.phone.box.top)) }.sorted()
                let moved = !shifts.isEmpty && shifts[shifts.count / 2] > 0.02
                let few = common.count * 2 < s.items.count
                let allSeenBefore = texts.allSatisfy { t in prev.contains { Self.isSimilar($0, t) } }
                if moved || few, allSeenBefore {
                    shown = nil; lastKey = key
                    return .remove
                }
                // Sohbet değişti.
                if let h = Self.plainHeader(r.header), let old = s.header, Text.key(h) != Text.key(old) {
                    shown = nil; removeFirst = true
                } else if s.kind == r.kind {
                    let same = texts.count * 2 >= s.items.count && texts.count <= s.items.count + 1
                        && texts.allSatisfy { t in s.items.contains { Self.isSimilar($0.source, t) } }
                    if same { lastKey = key; return .keep }
                    // Yeni mesajlar ancak bir önceki okumada da görüldüyse.
                    let fresh = texts.filter { t in !s.items.contains { Self.isSimilar($0.source, t) } }
                    let confirmed = fresh.allSatisfy { t in prev.contains { Self.isSimilar($0, t) } }
                    if !confirmed { return .keep }
                }
            }
            // Onay: bilinmeyen mesaj bir önceki okumada aynı metinle görülmediyse çeviriye gitmez.
            let unknownAll = texts.filter { lookup($0) == nil }
            let prevKeys = Set(prev.map(Text.key))
            let confirmed = unknownAll.filter { prevKeys.contains(Text.key($0)) }
            let interim = confirmed.count < unknownAll.count
            if interim {
                // Panel boşsa bilinenler hemen gösterilir; anahtar yazılmaz.
                guard shown == nil || removeFirst, texts.contains(where: { lookup($0) != nil }) else {
                    return removeFirst ? .remove : .keep
                }
            } else {
                lastKey = key
            }
            var context: [String] = []
            if let firstUnknown = texts.firstIndex(where: { confirmed.contains($0) }) {
                context = Array(texts[..<firstUnknown].suffix(PhoneTranslation.maxContext))
            }
            return .build(r, unknown: confirmed, context: context, interim: interim, removeFirst: removeFirst)
        }

        /// Çeviriler geldikten sonra yerleşimi kurar ve gösterileni günceller.
        public mutating func commit(_ r: PhoneScreenReading, phone: PhoneLocation, lookup: (String) -> String?,
                                    colors: PhoneColorSource?) -> [ScreenElement] {
            var layoutPhone = phone
            if let s = shown, abs(s.phone.centerX - phone.centerX) < 0.05, abs(s.phone.centerY - phone.centerY) < 0.05 {
                // Elde sallanma: mesajlar eski telefon yerine taşınır, panel yerinde kalır.
                layoutPhone = s.phone
            }
            let shift = (dx: layoutPhone.box.left - phone.box.left, dy: layoutPhone.box.top - phone.box.top)
            let items: [PhonePanelItem] = r.messages.compactMap { m in
                guard let t = lookup(m.text) else { return nil }
                var mm = m
                mm.box = Box(left: m.box.left + shift.dx, top: m.box.top + shift.dy, right: m.box.right + shift.dx, bottom: m.box.bottom + shift.dy)
                return PhonePanelItem(source: m.text, translation: t, message: mm)
            }
            var els = r.kind == .chat ? PhoneLayout.chat(items, header: r.header, phone: layoutPhone, colors: colors)
                                      : PhoneLayout.app(items, phone: layoutPhone, colors: colors)
            if let s = shown, s.kind == r.kind {
                els = PhoneLayout.keepBoxes(old: s.elements, oldSources: Self.sources(s.elements, items: s.items),
                                            new: els, newSources: Self.sources(els, items: items), kind: r.kind)
            }
            shown = els.isEmpty ? nil : Shown(items: items, kind: r.kind, header: r.header, phone: layoutPhone, elements: els)
            return els
        }

        /// Balon kimliği → İngilizce kaynak (balonlar gösterilmeye değer öğelerin sırasıyladır).
        static func sources(_ els: [ScreenElement], items: [PhonePanelItem]) -> [String: String] {
            let srcs = items.filter { PhoneLayout.worthShowing(source: $0.source, translation: $0.translation) }.map(\.source)
            let bubbles = els.filter { !$0.style.backdrop && $0.id != "01-baslik" }
            return Dictionary(zip(bubbles.map(\.id), srcs).map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        }

        /// Panel kalktı.
        public mutating func cleared() { shown = nil; lastKey = nil }

        /// Takipte bütün öğeler kaydırıldı.
        public mutating func shift(dx: Double, dy: Double) -> [ScreenElement] {
            guard var s = shown else { return [] }
            for i in s.elements.indices {
                let b = s.elements[i].box
                s.elements[i].box = Box(left: b.left + dx, top: b.top + dy, right: b.right + dx, bottom: b.bottom + dy)
            }
            s.phone = s.phone.shifted(dx: dx, dy: dy)
            shown = s
            return s.elements
        }
    }
}
