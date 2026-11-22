// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// MARK: - Ekran öğesi

extension GameReading {
    /// TV'ye katman olarak giden tek öğe (köşe, ipucu, kart, ek alan; ileride telefon/harita).
    public struct ScreenElement: Equatable, Sendable {
        public enum Kind: String, Sendable, Codable {
            case corner, questStrip, hint, messageCard, callCard, extraArea, menu, phone, map
        }

        public struct Style: Equatable, Sendable {
            public var background: String?
            public var textColor: String?
            public var opacity: Double
            public var frosted: Bool
            public var italic: Bool
            /// Yan balon (kart, köşe kutusu).
            public var bubble: Bool
            /// Satır boyu (kare oranı).
            public var lineHeight: Double
            /// Dönme açısı (derece, saat yönü artı; telefon balonları).
            public var angle: Double = 0
            /// Yazısız zemin (telefonun yanındaki mesajlaşma paneli).
            public var backdrop = false
            /// Harita görev kartı biçimi (koyu zemin, üstte vurgu çizgisi, ilk satır başlık).
            public var card = false
            /// Kutusuz, gölgeli sade yazı.
            public var plain = false

            public init(background: String? = nil, textColor: String? = nil, opacity: Double = 1, frosted: Bool = false,
                        italic: Bool = false, bubble: Bool = false, lineHeight: Double = 0.03) {
                self.background = background; self.textColor = textColor; self.opacity = opacity
                self.frosted = frosted; self.italic = italic; self.bubble = bubble; self.lineHeight = lineHeight
            }

            public static let darkFrost = Style(background: "#1c1c24", textColor: "#f2f2f5", opacity: 0.62, frosted: true, bubble: true)
            public static let lightFrost = Style(background: "#eef0f5", textColor: "#1c1c1e", opacity: 0.72, frosted: true, bubble: true)
        }

        /// Katman öğelerinin TV süresi.
        public static let layerDurationMs = 120_000

        public var kind: Kind
        public var id: String
        public var box: Box
        public var text: String
        public var style: Style
        /// `text` içindeki `⟦T1⟧` yer tutucularının tuş simgeleri (`ButtonIcons`; protokol.md "Tuş simgeleri").
        public var icons: [LinkIcon] = []

        public init(kind: Kind, id: String, box: Box, text: String, style: Style = Style(), icons: [LinkIcon] = []) {
            self.kind = kind; self.id = id; self.box = box; self.text = text; self.style = style; self.icons = icons
        }
    }

    /// Köşe, ipucu, kart ve ek alan çevirileri için çevirmen.
    public protocol ElementTranslator: Sendable {
        /// Pakette (ya da havuzda) bilinen çeviri; hemen döner.
        func known(_ text: String) -> String?
        /// Çevirmene gider. Birlikte çevirebiliyorsa tek istek.
        func translate(_ texts: [String]) async throws -> [String]
    }
}

// MARK: - Ekranı çevir grupları (§16)

extension GameReading {
    public enum ScreenGroups {
        /// En az 2 harf ve en az bir sözcükte 2 harf.
        public static func isText(_ s: String) -> Bool {
            Text.letterCount(s) >= 2 && Text.words(s).contains { $0.filter(\.isLetter).count >= 2 }
        }

        public struct Group: Equatable, Sendable {
            public var lines: [Line]
            public var box: Box
            public var lineHeight: Double
        }

        /// Satırları gruplara toplar (kare oranında kutular).
        public static func groups(_ lines: [Line], limit: Int = 30) -> [Group] {
            let cleaned = lines.compactMap { l -> Line? in
                guard l.box != nil else { return nil }
                let t = Filters.cleanJunk(l.text)
                return isText(t) ? Line(t, confidence: l.confidence, box: l.box) : nil
            }.sorted { $0.box!.top < $1.box!.top }
            var groups: [[Line]] = []
            for l in cleaned {
                let b = l.box!
                if let i = groups.lastIndex(where: { g in
                    let last = g.last!.box!
                    let hMax = max(b.height, last.height), hMin = min(b.height, last.height)
                    let overlap = min(b.right, last.right) - max(b.left, last.left)
                    return hMax <= 1.6 * hMin && b.top - last.bottom < 0.8 * hMax && overlap >= 0.5 * min(b.width, last.width)
                }) {
                    groups[i].append(l)
                } else {
                    groups.append([l])
                }
            }
            return groups.prefix(limit).map { g in
                Group(lines: g, box: Box.union(g.map(\.box!))!, lineHeight: Text.median(g.map { $0.box!.height }) ?? 0)
            }
        }

        /// Parçalar: önceki parça cümle bitirdiyse ya da (≤ 3 sözcük, virgülsüz ve yeni satır büyük harfle) yeni parça.
        public static func parts(_ texts: [String]) -> [String] {
            var out: [String] = []
            for t in texts {
                guard let prev = out.last else { out.append(t); continue }
                let newPart = Text.endsSentence(prev)
                    || (Text.words(prev).count <= 3 && !prev.hasSuffix(",") && t.first?.isUppercase == true)
                if newPart { out.append(t) } else { out[out.count - 1] = prev + " " + t }
            }
            return out
        }

        static let iconTokens: Set<String> = Filters.buttons.subtracting(["L", "R", "&", "@", "*", "LI", "RI"])

        /// Simgeleri `[1]`, `[2]` yer tutucularıyla değiştirir. Yalnız simgeden oluşan parçada `nil`.
        public static func protectIcons(_ text: String) -> (text: String, icons: [String])? {
            var icons: [String] = []
            let words = Text.words(text).map { w -> String in
                guard iconTokens.contains(w.uppercased()) || iconTokens.contains(w) else { return w }
                icons.append(w)
                return "[\(icons.count)]"
            }
            if !icons.isEmpty, words.allSatisfy({ $0.hasPrefix("[") && $0.hasSuffix("]") }) { return nil }
            return (words.joined(separator: " "), icons)
        }

        /// Yer tutucuları geri koyar; düşen simge başa eklenir.
        public static func restoreIcons(_ text: String, icons: [String]) -> String {
            var t = text
            var missing: [String] = []
            for (i, icon) in icons.enumerated() {
                let tag = "[\(i + 1)]"
                if t.contains(tag) { t = t.replacingOccurrences(of: tag, with: icon) } else { missing.append(icon) }
            }
            return (missing + [t]).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }

        /// TV süresi: `min(60 000, max(12 000, 8 000 + 50 × harf))`.
        public static func durationMs(letters: Int) -> Int { min(60_000, max(12_000, 8_000 + 50 * letters)) }
    }
}

// MARK: - Mesaj ve arama kartı (§14)

extension GameReading {
    public enum Cards {
        static let nameBanned = Set(".,!?:;…\"")

        /// Gönderen adı mı?
        public static func isName(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespaces)
            let words = Text.words(t)
            guard (2...30).contains(t.count), (1...4).contains(words.count) else { return false }
            guard words.allSatisfy({ w in (w.first?.isUppercase == true || w.first == "&") && w.filter(\.isUppercase).count <= 1 }) else { return false }
            return Text.hasLowercase(t) && !t.contains(where: { nameBanned.contains($0) })
        }

        /// Uygulama bildirimi adı (`BuckMe`): tek sözcük, harf, büyük harfle başlar, içinde en çok 2 büyük harf daha
        /// (bitişik yazılmış ad). Yalnız mesaj kartının başlığında kabul edilir; liste ve arama kuralları `isName` ile kalır.
        public static func isAppName(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespaces)
            guard (4...16).contains(t.count), t.allSatisfy(\.isLetter), t.first?.isUppercase == true,
                  t.dropFirst().contains(where: \.isUppercase), t.contains(where: \.isLowercase) else { return false }
            return t.dropFirst().filter(\.isUppercase).count <= 2
        }

        public struct Card: Equatable, Sendable {
            public var name: String
            public var body: String
            /// Kare oranında kart kutusu.
            public var box: Box?
            public var firstBodyHeight: Double?
        }

        public struct Call: Equatable, Sendable {
            public var name: String
            /// Türkçe durum; boşsa konuşma sürüyor (gösterilmez).
            public var status: String
            public var box: Box?
            public var firstLineHeight: Double?
        }

        /// İlk satırdan harfsiz parçalar (okundu tikleri) ve sondaki alıcı satırı atılır.
        public static func tidy(_ lines: [Line]) -> [Line] {
            var ls = lines
            if var first = ls.first {
                first.text = Text.words(first.text).drop { !$0.contains(where: \.isLetter) }.joined(separator: " ")
                ls[0] = first
            }
            if ls.count >= 3, let last = ls.last {
                let w = Text.words(last.text).filter { $0.contains(where: \.isLetter) }
                let arrow = last.text.contains("→") || last.text.contains("->")
                if (1...3).contains(w.count), w.allSatisfy({ $0.first?.isUppercase == true }), arrow || Text.words(last.text).count == 1 {
                    ls.removeLast()
                }
            }
            return ls
        }

        public static func isList(_ lines: [Line]) -> Bool {
            guard lines.count >= 3 else { return false }
            let names = lines.filter { isName($0.text) }.count
            let dots = lines.filter { $0.text.hasSuffix("...") || $0.text.hasSuffix("…") }.count
            return names >= 2 || dots >= 2
        }

        /// Mesaj kartı (kutular alan içi; `area` kare oranı).
        public static func card(_ raw: [Line], area: Box = .full) -> Card? {
            let lines = tidy(raw)
            // Gönderen adı ya da uygulama adı (`BuckMe` bildirimi, 23 Kasım 00:29: adda iki büyük harf olduğundan kart
            // sayılmıyordu, satırlar sessizce atılıyordu). Başlık çevrilmez.
            guard !isList(lines), lines.count >= 2, isName(lines[0].text) || isAppName(lines[0].text) else { return nil }
            let body = lines.dropFirst().map(\.text).joined(separator: " ")
            if let nb = lines[0].box, let bb = lines[1].box, nb.bottom > bb.top + 0.01 { return nil }
            let words = Text.words(body)
            if words.count >= 3 {
                guard Text.hasLowercase(body) else { return nil }
            } else {
                guard body.contains(where: \.isLetter), let nb = lines[0].box, let bb = lines[1].box, nb.left >= 0.55, bb.left >= 0.55 else { return nil }
            }
            let box = Box.union(lines.compactMap(\.box)).map { $0.mapped(into: area) }
            let h = lines[1].box.map { $0.height * area.height }
            return Card(name: lines[0].text, body: body, box: box, firstBodyHeight: h)
        }

        static let callStatus: [String: String] = [
            "calling": "aranıyor…", "dialing": "aranıyor…", "dialling": "aranıyor…", "connecting": "aranıyor…", "ringing": "aranıyor…",
            "incoming call": "seni arıyor…", "incoming": "seni arıyor…",
            "call ended": "arama bitti", "ended": "arama bitti", "call failed": "arama bitti", "busy": "arama bitti",
            "no answer": "arama bitti", "unavailable": "arama bitti",
        ]

        public static func call(_ raw: [Line], area: Box = .full) -> Call? {
            let lines = tidy(raw)
            guard lines.count == 2, isName(lines[0].text) else { return nil }
            var second = lines[1].text.trimmingCharacters(in: .whitespaces)
            while let l = second.last, l == "." || l == "…" || l == " " { second.removeLast() }
            let status: String
            if let s = callStatus[second.lowercased()] { status = s }
            else if Text.regex(#"^\d{1,2}:\d{2}$"#, second) { status = "" }
            else { return nil }
            let box = Box.union(lines.compactMap(\.box)).map { $0.mapped(into: area) }
            return Call(name: lines[0].text, status: status, box: box, firstLineHeight: lines[0].box.map { $0.height * area.height })
        }

        /// Okuma kartın tekrarı mı?
        public static func repeats(_ reading: String, card: String) -> Bool {
            let r = Text.keyWords(reading).filter { $0.count > 1 }
            let c = Set(Text.keyWords(card))
            guard !r.isEmpty else { return false }
            let inCard = r.filter { c.contains($0) }.count
            if c.count <= 2 { return inCard == r.count }
            return inCard * 2 >= r.count
        }

        /// Kartın üstündeki açık buzlu kart (§14.2).
        public static func layout(_ card: Card, translation: String) -> ScreenElement? {
            guard let b = card.box else { return nil }
            let lh = min(card.firstBodyHeight ?? 0.03, 0.032) * 0.85
            let text = "\(card.name): \(translation)"
            let left = b.left - 0.012
            let right = min(0.995, max(b.right + 0.012, left + 0.18))
            let rows = Wrap.lineCount(text, width: right - left, lineHeight: lh, letterFactor: 0.5)
            let height = lh * Double(rows) * 1.25 + 0.02
            let top = max(0, b.top - 0.018 - height - 0.012)
            var style = ScreenElement.Style.lightFrost
            style.lineHeight = lh
            return ScreenElement(kind: .messageCard, id: "card", box: Box(left: left, top: top, right: right, bottom: top + height),
                                 text: text, style: style)
        }

        public static func layout(_ call: Call) -> ScreenElement? {
            guard !call.status.isEmpty, let b = call.box else { return nil }
            let lh = min(call.firstLineHeight ?? 0.03, 0.032) * 0.8
            let height = lh * 1.3
            let top = b.top - height - 0.035
            let right = max(b.right, b.left + 0.2)
            return ScreenElement(kind: .callCard, id: "call", box: Box(left: b.left, top: top, right: right, bottom: top + height),
                                 text: "\(call.name) \(call.status)", style: .init(italic: true, lineHeight: lh))
        }
    }

    /// Mac'te kartı gösterme kuralları (§14.2).
    public struct CardPresenter: Sendable {
        public var shown: (name: String, message: String, translation: String)?
        private var lastSeen = 0
        private var lastText: String?
        public init() {}

        public enum Step: Equatable, Sendable {
            case none
            /// Çevrilmesi gereken gövde (simgesiz).
            case translate(String)
            case remove
        }

        /// Her karede kart (ya da `nil`) verilir.
        public mutating func observe(_ card: Cards.Card?, phoneSeenRecently: Bool, now: Int) -> Step {
            guard var card else {
                if shown != nil, now - lastSeen >= 3_000 { shown = nil; return .remove }
                return .none
            }
            if phoneSeenRecently || (card.box.map { $0.left < 0.55 || $0.top < 0.72 } ?? true) {
                if shown != nil { shown = nil; return .remove }
                return .none
            }
            lastSeen = now
            let words = Text.words(card.body)
            if words.count > 1, words[0].count == 1, !"aAI".contains(words[0]) { card.body = words.dropFirst().joined(separator: " ") }
            if let s = shown, Text.ratio(card.body, s.message) >= 0.85 { return .none }
            defer { lastText = card.body }
            guard lastText == card.body else { return .none }
            return .translate(Text.words(card.body).filter { !ScreenGroups.iconTokens.contains($0) }.joined(separator: " "))
        }

        public mutating func translated(name: String, message: String, translation: String) {
            shown = (name, message, translation)
        }
    }
}

// MARK: - Sarma (§17.2) ve yığın (§17.1)

extension GameReading {
    public enum Wrap {
        public static let maxLetters = 42
        public static let maxLines = 3
        public static let minScale = 0.75

        /// Kutuya sığan satır sayısı (harf genişliği boy × çarpan × 9/16, satırda en az 12 harf).
        static func lineCount(_ text: String, width: Double, lineHeight: Double, letterFactor: Double) -> Int {
            let perLine = max(12, Int(width / max(1e-6, lineHeight * letterFactor * 9 / 16)))
            return max(1, Int(ceil(Double(text.count) / Double(perLine))))
        }

        /// TV satır bölme: satırlar ve ölçek.
        public static func wrap(_ text: String) -> (lines: [String], scale: Double) {
            if text.count < maxLetters || text.contains("\n") { return (text.components(separatedBy: "\n"), 1) }
            let scale = min(1, max(minScale, 126 / Double(text.count)))
            let capacity = Int(floor(Double(maxLetters) / scale))
            let count = min(maxLines, max(2, Int(ceil(Double(text.count) / Double(capacity)))))
            var words = Text.words(text)
            // Konuşan adı sonraki sözcükle birleşik tutulur.
            if let i = words.prefix(3).firstIndex(where: { $0.hasSuffix(":") }), i + 1 < words.count {
                let joined = words[0...(i + 1)].joined(separator: " ")
                words.replaceSubrange(0...(i + 1), with: [joined])
            }
            return (best(words, lines: count), scale)
        }

        static func best(_ words: [String], lines: Int) -> [String] {
            guard lines > 1, words.count > 1 else { return [words.joined(separator: " ")] }
            var bestSplit: [String] = [words.joined(separator: " ")]
            var bestKey = (Int.max, Int.max)
            func search(_ start: Int, _ remaining: Int, _ acc: [String]) {
                if remaining == 1 {
                    let all = acc + [words[start...].joined(separator: " ")]
                    let key = (all.map(\.count).max()!, all.reduce(0) { $0 + $1.count * $1.count })
                    if key < bestKey { bestKey = key; bestSplit = all }
                    return
                }
                guard start < words.count - remaining + 1 else { return }
                for end in (start + 1)...(words.count - remaining + 1) {
                    search(end, remaining - 1, acc + [words[start..<end].joined(separator: " ")])
                }
            }
            search(0, min(lines, words.count), [])
            return bestSplit
        }
    }

    /// Bilgisayardaki altyazı penceresinin yığını (saniye).
    public struct SubtitleStack: Sendable {
        public struct Entry: Equatable, Sendable {
            public var text: String
            public var shownAt: Double
            public var until: Double
            public var holdUntil: Double
            public var paragraph: Bool
        }

        public var stackAbove = true
        public var raiseWindow = 1.5
        public var fullyVisible = 1.5
        public var fade = 0.4
        public var minimumVisible = 1.2
        public var maxClearDelay = 5.0

        public private(set) var current: Entry?
        public private(set) var previous: Entry?
        public private(set) var older: Entry?

        public init() {}

        public mutating func show(_ text: String, durationMs: Int?, at t: Double, replace: Bool = false, paragraph: Bool = false) {
            let letters = Double(text.count)
            let given = durationMs.flatMap { $0 > 0 ? $0 : nil }
            let life = given.map { max(minimumVisible, Double($0) / 1000) } ?? min(8, 2 + letters * 0.06)
            let entry = Entry(text: text, shownAt: t, until: t + life, holdUntil: t + min(maxClearDelay, 2 + letters * 0.06), paragraph: paragraph)
            expire(at: t)
            defer { current = entry }
            guard let cur = current else { previous = nil; older = nil; return }
            if replace, !cur.paragraph { return }
            if stackAbove, t - cur.shownAt < raiseWindow, !cur.paragraph, !paragraph, !Self.sameLine(cur.text, text) {
                if let p = previous, t - p.shownAt < raiseWindow + fullyVisible, !Self.sameLine(p.text, text) { older = p } else { older = nil }
                previous = cur
            } else {
                previous = nil; older = nil
            }
        }

        public mutating func clear(at t: Double) {
            guard var cur = current else { return }
            cur.until = min(cur.until, max(t, cur.holdUntil))
            current = cur
        }

        public mutating func removeAll() { current = nil; previous = nil; older = nil }

        /// Görünen satırlar, yukarıdan aşağı.
        public mutating func visible(at t: Double) -> [String] {
            expire(at: t)
            return [older, previous, current].compactMap { $0?.text }
        }

        private mutating func expire(at t: Double) {
            if let c = current, t >= c.until { current = nil; previous = nil; older = nil }
            // Üsttekiler, şimdiki satır 1,5 sn tam göründükten sonra 0,4 sn'de solar.
            if let c = current, t >= c.shownAt + fullyVisible + fade { previous = nil; older = nil }
        }

        /// Üstteki satırların saydamlığı (1 tam, 0 yok).
        public func aboveOpacity(at t: Double) -> Double {
            guard let c = current, previous != nil else { return 0 }
            let start = c.shownAt + fullyVisible
            if t <= start { return 1 }
            return max(0, 1 - (t - start) / fade)
        }

        /// Büyük/küçük harf, noktalama ve boşluk yok sayılınca aynı; ya da biri ötekini içeriyor.
        public static func sameLine(_ a: String, _ b: String) -> Bool {
            func norm(_ s: String) -> String { String(s.lowercased().filter { $0.isLetter || $0.isNumber }) }
            let x = norm(a), y = norm(b)
            if x.isEmpty || y.isEmpty { return false }
            if x == y { return true }
            let (short, long) = x.count <= y.count ? (a, b) : (b, a)
            let ns = norm(short), nl = norm(long)
            guard nl.contains(ns) else { return false }
            if Text.words(short).count == 1 {
                return Text.words(long).map(norm).contains(ns)
            }
            return true
        }
    }
}
