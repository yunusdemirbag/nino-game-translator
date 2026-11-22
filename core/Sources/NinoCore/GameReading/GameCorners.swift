// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// MARK: - Köşeler (§12)

extension GameReading {
    public enum Corners {
        public enum Place: String, Sendable { case topLeft, questStrip, menuSearch }

        public static let topLeftBox = Box(left: 0, top: 0, right: 0.40, bottom: 0.48)
        public static let menuSearchBox = Box(left: 0, top: 0.03, right: 1, bottom: 0.95)

        public static func questStripBox(questLine: Double) -> Box {
            Box(left: 0.08, top: questLine, right: 0.92, bottom: 0.995)
        }

        /// Köşe turu aralığı.
        public static func intervalMs(menuOpen: Bool) -> Int { menuOpen ? 600 : 1_500 }

        /// Bu turda okunacak yerler (`round` 0'dan sayar).
        public static func places(round: Int, questLine: Double?, menuSeenRecently: Bool) -> [(Place, Box)] {
            var out: [(Place, Box)] = [(.topLeft, topLeftBox)]
            if let q = questLine { out.append((.questStrip, questStripBox(questLine: q))) }
            if menuSeenRecently || round % 3 == 0 { out.append((.menuSearch, menuSearchBox)) }
            return out
        }

        /// Menü araması için küçültme: kare en çok 1 280 piksel genişliğe.
        public static func menuScale(pixelWidth: Int) -> Double { min(1, 1_280 / Double(max(1, pixelWidth))) }

        // MARK: Ekran türü (§12.2)

        static let menuWords: Set<String> = [
            "map", "brief", "progress", "settings", "stats", "gallery", "online", "inventory", "store", "help", "photo studio",
            "game", "journal", "options", "wardrobe", "outfits", "missions", "show text", "hide text", "flip", "put back",
            "rotate", "inspect", "examine", "read",
        ]
        static let shopWords: Set<String> = [
            "speed", "acceleration", "handling", "rating", "upgrade", "performance", "respray", "purchase", "owned",
            "braking", "armor", "armour",
        ]

        /// Menü satırı temizliği.
        public static func cleanMenuLine(_ text: String) -> String {
            var parts = Text.words(text)
            while let f = parts.first, parts.count > 1, !f.contains(where: \.isLetter) || (f.count <= 2 && !f.contains(where: { $0.isLetter || $0.isNumber })) {
                parts.removeFirst()
            }
            if parts.count > 1, let f = parts.first, parts[1].first?.isUppercase == true,
               (f.count <= 2 && f.allSatisfy({ $0.isLetter && $0.isLowercase })) || f == "Il" || f == "II" {
                parts.removeFirst()
            }
            while let l = parts.last, parts.count > 1, !l.contains(where: { $0.isLetter || $0.isNumber }) { parts.removeLast() }
            return parts.joined(separator: " ")
        }

        public static func isMenuScreen(_ lines: [String]) -> Bool {
            let cleaned = lines.map { cleanMenuLine($0).lowercased() }
            if cleaned.filter({ menuWords.contains($0) }).count >= 2 { return true }
            if cleaned.filter({ Set(Text.keyWords($0)).intersection(shopWords).isEmpty == false }).count >= 2 { return true }
            return cleaned.contains { Set(Text.keyWords($0)).intersection(["map", "brief", "progress"]).count >= 2 }
        }

        /// Menü satırlarının bilinen Türkçesi (yalnız Türkçe hedefte; Mac şu an menüleri çevirmez).
        public static let menuTurkish: [String: String] = [
            "map": "Harita", "game": "Oyun", "store": "Mağaza", "help": "Yardım", "photo studio": "Foto Stüdyosu",
            "settings": "Ayarlar", "options": "Seçenekler", "resume": "Devam Et", "continue": "Devam Et", "quit": "Çık",
            "exit": "Çık", "quit game": "Oyundan Çık", "back": "Geri", "select": "Seç", "save": "Kaydet", "load": "Yükle",
            "load game": "Oyun Yükle", "new game": "Yeni Oyun", "save game": "Oyun Kaydet", "inventory": "Envanter",
            "stats": "İstatistikler", "brief": "Özet", "journal": "Günlük", "gallery": "Galeri", "online": "Çevrim İçi",
            "story mode": "Hikâye Modu", "retry checkpoint": "Son Kayıttan Dene", "restart mission": "Görevi Baştan Başlat",
            "restart": "Baştan Başla", "skip": "Atla", "replay mission": "Görevi Yeniden Oyna", "audio": "Ses", "display": "Ekran",
            "controls": "Kontroller", "graphics": "Grafik", "accessibility": "Erişilebilirlik", "language": "Dil",
            "credits": "Jenerik", "friends": "Arkadaşlar", "messages": "Mesajlar", "contacts": "Kişiler", "phone": "Telefon",
            "camera": "Kamera", "missions": "Görevler", "objectives": "Hedefler", "weapons": "Silahlar", "vehicles": "Araçlar",
            "apparel": "Kıyafet", "gone fishing": "Balığa Çıktı",
        ]

        public static func menuLineTurkish(_ text: String) -> String? {
            let t = cleanMenuLine(text).lowercased()
            if let m = menuTurkish[t] { return m }
            if let r = t.range(of: #"^chapter (\d+)$"#, options: .regularExpression) { return "Bölüm " + t[r].dropFirst(8) }
            return nil
        }

        /// Menü grupları (bilgi için): kısa, aynı kenara hizalı, en az 3 satır.
        public static func menuGroups(_ lines: [Line]) -> [[Line]] {
            let short = lines.filter { l in
                guard let b = l.box else { return false }
                let w = Text.words(l.text)
                return b.height < 0.07 && (1...4).contains(w.count) && l.text.count <= 30 && !l.text.hasSuffix(".") && !l.text.hasSuffix("?")
            }.sorted { $0.box!.top < $1.box!.top }
            var used = Set<Int>(), groups: [[Line]] = []
            for edge in [\Box.left, \Box.right] {
                for (i, l) in short.enumerated() where !used.contains(i) {
                    var g = [i]
                    for (j, m) in short.enumerated() where j > i && !used.contains(j) {
                        let last = short[g.last!].box!
                        if abs(m.box![keyPath: edge] - l.box![keyPath: edge]) <= 0.012, m.box!.top - last.bottom <= 0.13 { g.append(j) }
                    }
                    if g.count >= 3 { used.formUnion(g); groups.append(g.map { short[$0] }) }
                }
            }
            return groups
        }

        // MARK: Sol üst kutusu (§12.3)

        static func boxWords(_ text: String) -> Int {
            text.split { !($0.isLetter || $0 == "'" || $0 == "’") }.filter { $0.count >= 2 }.count
        }

        /// Sol üst ipucu kutusunun satırları (kare oranında kutular).
        public static func topLeftLines(_ lines: [Line]) -> [Line] {
            let horizontal = lines.filter { l in
                guard let b = l.box else { return false }
                return b.width * 16 / 9 > b.height * 1.2 && Text.letterCount(l.text) >= 3
            }.sorted { $0.box!.top < $1.box!.top }
            let mh = Text.median(horizontal.map { $0.box!.height }) ?? 0
            var blocks: [[Line]] = []
            for l in horizontal {
                if let lastBlock = blocks.last {
                    let u = Box.union(lastBlock.map(\.box!))!
                    let b = l.box!
                    if b.top - lastBlock.last!.box!.bottom < 1.8 * mh, min(b.right, u.right) > max(b.left, u.left) {
                        blocks[blocks.count - 1].append(l); continue
                    }
                }
                blocks.append([l])
            }
            guard let best = blocks.max(by: { a, b in
                a.reduce(0) { $0 + boxWords($1.text) } < b.reduce(0) { $0 + boxWords($1.text) }
            }) else { return [] }
            let words = best.reduce(0) { $0 + boxWords($1.text) }
            let marker = best[0].text.first.map { !($0.isLetter || $0.isNumber || "\"'“‘([".contains($0)) } ?? false
            return words >= 4 || (words >= 2 && marker) ? best : []
        }

        // MARK: Sağ üst bildirim

        /// Sağ üstteki kısa oyun bildirimi (`Map updated`, GTA 6 23 Kasım 00:29): menü araması satırlarından (kare
        /// oranında) sağ üst bölgede (x ≥ 0,70, y 0,12–0,45) küçük harfli, 2–8 sözcüklü tek satır. Baştaki/sondaki
        /// simge kırıntıları atılır; para (`$9,335`) ve rakamlı satırlar sayılmaz. Menü açıkken çağrılmaz (menü çevrilmez).
        public static func topRightNotice(_ lines: [Line]) -> Line? {
            let found = lines.compactMap { l -> Line? in
                guard let b = l.box, b.left >= 0.70, b.top >= 0.12, b.bottom <= 0.45 else { return nil }
                var words = Text.words(l.text)
                var lead = 0
                while let f = words.first, words.count > 1, f.count <= 1 || !f.contains(where: \.isLetter) {
                    lead += f.count + 1; words.removeFirst()
                }
                while let t = words.last, words.count > 1, t.count <= 1 || !t.contains(where: \.isLetter) { words.removeLast() }
                let text = words.joined(separator: " ")
                guard (2...8).contains(words.filter({ $0.filter(\.isLetter).count >= 2 }).count), Text.hasLowercase(text),
                      !text.contains(where: { $0.isNumber || $0 == "$" }), !MapScreen.isButton(text) else { return nil }
                var box = b
                box.left += b.width * Double(lead) / Double(max(1, l.text.count))
                return Line(text, confidence: l.confidence, box: box)
            }
            return found.min { ($0.box?.top ?? 1) < ($1.box?.top ?? 1) }
        }

        /// Sağ üst bildirimin Türkçesi: koyu buzlu kutu, oyunun yazısının üstünde; sağ kenarı sabit, sola doğru uzar.
        public static func topRightElement(box b: Box, translation: String) -> ScreenElement {
            let lh = min(max(b.height, 0.026), 0.04) * 0.9
            let clean = Text.words(translation).filter { !ScreenGroups.iconTokens.contains($0) }.joined(separator: " ")
            let right = min(0.995, b.right + 0.006)
            let width = min(0.45, max(b.width + 0.012, Double(clean.count) * lh * 0.5 * 9 / 16 + 0.02))
            var style = ScreenElement.Style.darkFrost
            style.lineHeight = lh
            return ScreenElement(kind: .corner, id: "top-right",
                                 box: Box(left: max(0, right - width), top: b.top - 0.006, right: right, bottom: b.bottom + 0.006),
                                 text: clean, style: style)
        }

        static let mapHeadings: Set<String> = ["OPTIONAL", "STORY", "SIDE", "COMPLETED", "ACTIVITIES"]

        /// Harita listesi mi (başlık ya da ◆ ile başlayan en az 2 satır)?
        public static func isMapList(_ lines: [Line]) -> Bool {
            if lines.contains(where: { l in !Text.hasLowercase(l.text) && mapHeadings.contains(l.text.trimmingCharacters(in: .whitespaces)) }) { return true }
            return lines.filter { $0.text.hasPrefix("◆") || $0.text.hasPrefix("♦") }.count >= 2
        }

        // MARK: Görev şeridi (§12.4)

        public static func questStripLines(_ lines: [Line], subtitle: String?, subtitleBox: Box?) -> [Line] {
            lines.filter { l in
                guard let b = l.box, Speaker.split(l.text) == nil, b.midX >= 0.32, b.midX <= 0.68 else { return false }
                if let sb = subtitleBox, b.intersects(sb, padding: 0.01) { return false }
                if let s = subtitle {
                    let k = Text.key(l.text), sk = Text.key(s)
                    if k.count >= 6, sk.contains(k) || k.contains(sk) { return false }
                    let w = Text.keyWords(l.text)
                    if !w.isEmpty, Double(Similarity.common(w, Text.keyWords(s))) >= 0.5 * Double(w.count) { return false }
                }
                return true
            }
        }

        // MARK: Yerleşim (§12.7)

        /// Sol üst kutusunun Türkçesi: koyu buzlu kutu, oyunun kutusunun hemen altında.
        public static func topLeftElement(box b: Box, lineHeight h: Double, header: String?, body: String) -> ScreenElement {
            let lh = min(max(h, 0.026), 0.04) * 0.95
            let right = max(b.right + 0.01, b.left + 0.22)
            let left = b.left - 0.006
            let clean = Text.words(body).filter { !ScreenGroups.iconTokens.contains($0) }.joined(separator: " ")
            let text = header.map { "\($0) · \(clean)" } ?? clean
            let rows = Wrap.lineCount(text, width: right - left, lineHeight: lh, letterFactor: 0.5)
            let height = lh * Double(rows) * 1.25 + 0.02
            let top = min(1 - height - 0.01, b.bottom + 0.012)
            var style = ScreenElement.Style.darkFrost
            style.lineHeight = lh
            return ScreenElement(kind: .corner, id: "top-left", box: Box(left: left, top: top, right: right, bottom: top + height), text: text, style: style)
        }
    }

    /// Bir köşenin kararlılığı ve hafızası (§12.5).
    public struct CornerTracker: Sendable {
        public enum Step: Equatable, Sendable {
            case none
            case translate(String)
            /// Hafızadaki çeviri; çevirmene gitmez.
            case show(source: String, translation: String)
            case remove
        }

        public let place: Corners.Place
        public var isTargetLanguage: @Sendable (String) -> Bool
        private var previous: String?
        private var emptyCount = 0
        public private(set) var shownSource: String?
        private var memory: [(source: String, translation: String)] = []
        private var silentUntil = Int.min

        public init(place: Corners.Place, isTargetLanguage: @escaping @Sendable (String) -> Bool = TranslationQueue.looksTurkish) {
            self.place = place
            self.isTargetLanguage = isTargetLanguage
        }

        static func close(_ a: String, _ b: String) -> Bool {
            Text.key(a) == Text.key(b) || (a.count >= 30 && Text.ratio(a, b) >= 0.8)
        }

        public mutating func observe(_ text: String?, menuOpen: Bool, now: Int) -> Step {
            let t = text.map(Text.squeeze) ?? ""
            if let s = shownSource, !t.isEmpty, Text.key(s) == Text.key(t) { emptyCount = 0; previous = t; return .none }
            if t.isEmpty {
                previous = nil
                guard shownSource != nil else { return .none }
                emptyCount += 1
                if emptyCount >= (menuOpen ? 1 : 4) { shownSource = nil; emptyCount = 0; return .remove }
                return .none
            }
            emptyCount = 0
            let stable = menuOpen || previous.map { Self.close($0, t) } ?? false
            previous = t
            guard stable else { return .none }
            if Text.lines(text ?? t).contains(where: isTargetLanguage) || isTargetLanguage(t) {
                silentUntil = now + 15_000
                return .none
            }
            if now < silentUntil { previous = nil; return .none }
            if place == .topLeft {
                guard Text.hasLowercase(t) else { return .none }
                guard Text.words(t).filter({ $0.filter(\.isLetter).count >= 2 }).count >= 3 else { return .none }
            }
            if let hit = memory.last(where: { Self.close($0.source, t) }) {
                shownSource = t
                return .show(source: t, translation: hit.translation)
            }
            shownSource = t
            return .translate(t)
        }

        public mutating func translated(source: String, translation: String) {
            memory.append((source, translation))
            if memory.count > 40 { memory.removeFirst(memory.count - 40) }
        }

        /// Satırlardan biri hedef dilde görüldü: 15 sn köşeler çevrilmez.
        public mutating func silence(now: Int) { silentUntil = now + 15_000 }
    }
}

// MARK: - Tuş ipuçları (§13)

extension GameReading {
    public struct Hints: Sendable {
        static let navigation: Set<String> = [
            "back", "select", "exit", "close", "confirm", "cancel", "ok", "accept", "continue", "skip", "zoom", "rotate",
            "scroll", "navigate", "change", "toggle", "view", "rev", "buy", "equip",
        ]

        /// Yalnız cümle hâlindeki ipuçları çevrilir.
        public static func isTranslatable(_ text: String) -> Bool {
            let parts = Filters.hintParts(text)
            let words = parts.filter { !Filters.isButton($0) && $0.contains(where: \.isLetter) }
            if words.count <= 2 { return false }
            if Set(words.map { $0.lowercased() }).isSubset(of: navigation) { return false }
            return !Filters.isItemLabel(text)
        }

        /// Karşılaştırma anahtarı: 1 karakterlikler ve `l1–r3` atılır.
        public static func key(_ text: String) -> String {
            let banned: Set<String> = ["l1", "l2", "l3", "r1", "r2", "r3"]
            return Text.keyWords(text).filter { $0.count > 1 && !banned.contains($0) }.joined(separator: " ")
        }

        public struct Shown: Equatable, Sendable {
            public var key: String
            public var element: ScreenElement
        }

        public private(set) var shown: [String: Shown] = [:]
        public private(set) var translating: String?
        /// Seçim menüsü satırlarının anahtarları (çeviri satırın üstüne değil, yazısının üstüne oturur).
        private var choiceKeys: Set<String> = []
        public init() {}

        /// Seçim menüsü (`LUCIA` / `△ SPLIT UP & TAKE` / `□ SLOW DOWN` / `✕ PULL OVER`, 23 Kasım 00:29): alt alta, aynı
        /// solda en az 2 satır; her biri baştaki tuş simgesi kırıntısı + 1–3 büyük harfli sözcük (+ sondaki simge).
        /// Satırın simgesiz metni ve yalnız yazıyı kapsayan kutusu döner (simgeler ekranda görünür kalır).
        static func choiceRows(_ lines: [Line]) -> [(line: Line, source: Int)] {
            var rows: [(line: Line, source: Int)] = []
            for (i, l) in lines.enumerated() {
                guard let b = l.box else { continue }
                var parts = Filters.hintParts(l.text)
                var lead = 0
                while let f = parts.first, parts.count > 1, f.count == 1 || !f.contains(where: \.isLetter) {
                    lead += f.count + 1; parts.removeFirst()
                }
                guard lead > 0 else { continue }
                if parts.count >= 2, let t = parts.last, t.count <= 2 { parts.removeLast() }
                let words = parts.filter { $0 != "&" }
                guard (1...3).contains(words.count), words.allSatisfy(Filters.isUpperWord), words.contains(where: { $0.count >= 3 })
                else { continue }
                let total = Double(max(1, l.text.count))
                let text = parts.joined(separator: " ")
                var box = b
                // Simge kabaca satır boyunda bir karedir (16:9 karede genişliği boy × 9/16): kırıntı payı küçük kalırsa.
                box.left = max(b.left + b.width * Double(lead) / total, b.left + b.height * 9 / 16 * 1.1)
                box.right = min(b.right, box.left + b.width * Double(text.count + 1) / total)
                rows.append((Line(text, confidence: l.confidence, box: box), i))
            }
            rows.sort { ($0.line.box?.top ?? 0) < ($1.line.box?.top ?? 0) }
            // Alt alta ve aynı solda olanlar; tek satır menü sayılmaz.
            var best: [(line: Line, source: Int)] = []
            var run: [(line: Line, source: Int)] = []
            for r in rows {
                if let p = run.last?.line.box, let b = r.line.box,
                   !(abs(b.left - p.left) < 0.02 && b.top - p.bottom < 1.5 * p.height && b.top > p.top) {
                    if run.count > best.count { best = run }
                    run = []
                }
                run.append(r)
            }
            if run.count > best.count { best = run }
            return best.count >= 2 ? best : []
        }

        /// Her karede ipucu satırları (kare oranında) verilir; çevrilecek ilk ipucu döner.
        public mutating func observe(_ lines: [Line], questLine: Double?, menuOpen: Bool) -> (translate: Line?, removed: [String]) {
            if menuOpen {
                let ids = Array(shown.keys)
                shown = [:]
                return (nil, ids)
            }
            // Seçim menüsünün satırları (2 sözcüklü olsalar da) simgesiz metinleriyle çevrilir; ötekiler eskisi gibi.
            let choices = Self.choiceRows(lines)
            let choiceSources = Set(choices.map(\.source))
            let usable = (choices.map(\.line) + lines.enumerated().filter { !choiceSources.contains($0.offset) }.map(\.element)
                .filter { Self.isTranslatable($0.text) }).filter { l in
                guard let b = l.box else { return false }
                if let q = questLine, b.midY > q { return false }
                return true
            }
            for c in choices { choiceKeys.insert(Self.key(c.line.text)) }
            let keys = Set(usable.map { Self.key($0.text) })
            let gone = shown.keys.filter { !keys.contains($0) }
            for k in gone { shown[k] = nil }
            guard translating == nil, let next = usable.first(where: { shown[Self.key($0.text)] == nil }) else { return (nil, gone) }
            translating = Self.key(next.text)
            return (next, gone)
        }

        /// Çeviri geldi: üste, ortalı, titremeden yerleştirir.
        public mutating func translated(_ line: Line, turkish: String) -> ScreenElement? {
            let k = Self.key(line.text)
            if translating == k { translating = nil }
            guard let b = line.box else { return nil }
            let text = Text.words(turkish).filter { !ScreenGroups.iconTokens.contains($0) }.joined(separator: " ")
            guard !text.isEmpty, !Set(Text.keyWords(text)).isSubset(of: Self.navigation) else { return nil }
            let h = b.height
            if choiceKeys.contains(k) {
                // Seçim satırı: çeviri yazının üstüne oturur (simge solda görünür kalır).
                let width = max(b.width + 0.008, min(0.4, Double(text.count) * h * 0.5 * 9 / 16 + 0.016))
                let box = Box(left: b.left - 0.001, top: b.top - 0.004, right: min(1, b.left - 0.001 + width), bottom: b.bottom + 0.004)
                if let old = shown[k]?.element, old.text == text, abs(old.box.left - box.left) < 0.02, abs(old.box.top - box.top) < 0.02 {
                    return old
                }
                let el = ScreenElement(kind: .hint, id: "hint:" + k, box: box, text: text, style: .init(lineHeight: h))
                shown[k] = Shown(key: k, element: el)
                return el
            }
            let width = min(0.6, Double(text.count) * h * 0.5 * 9 / 16 + 0.02)
            var bottom = b.top - 0.008
            var left = b.midX - width / 2
            left = min(max(0, left), 1 - width)
            var box = Box(left: left, top: bottom - h - 0.006, right: left + width, bottom: bottom)
            // Üstteki öğeyle çakışırsa daha yukarı itilir.
            for other in shown.values.map(\.element.box) where other.intersects(box) {
                bottom = other.top - 0.006
                box = Box(left: box.left, top: bottom - h - 0.006, right: box.right, bottom: bottom)
            }
            if let old = shown[k]?.element, old.text == text, abs(old.box.left - box.left) < 0.06, abs(old.box.top - box.top) < 0.06 {
                return old
            }
            let el = ScreenElement(kind: .hint, id: "hint:" + k, box: box, text: text, style: .init(lineHeight: h))
            shown[k] = Shown(key: k, element: el)
            return el
        }

        public mutating func failed(_ line: Line) {
            if translating == Self.key(line.text) { translating = nil }
        }
    }
}
