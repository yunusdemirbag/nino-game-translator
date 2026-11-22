// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// MARK: - Harita ekranı (tarif §9.1)

extension GameReading {
    public enum MapScreen {
        /// Harita ekranının tuş satırları.
        public static let buttons: Set<String> = [
            "recenter", "2d view", "3d view", "add marker", "remove marker", "set destination",
            "remove destination", "close menu", "view on map", "markers", "cinematic",
        ]
        /// Telefon okumasında haritayı ele veren tuşlar (tarif §4).
        public static let phoneMapButtons: Set<String> = [
            "recenter", "2d view", "3d view", "add marker", "set destination", "close menu",
        ]

        /// Satırların (temizlenip küçük harfle) en az ikisi harita tuşu mu? Tuş adının ardındaki kısa tuş simgesi
        /// okuması (`RECENTER L3`, `ADD MARKER C`, `SET DESTINATION x`) sayılmaz.
        public static func isMapScreen(_ lines: [String]) -> Bool {
            lines.filter(isButton).count >= 2
        }

        static func isButton(_ line: String) -> Bool { buttons.contains(buttonName(line)) }

        /// Tuş satırının adı (küçük harf): sondaki kumanda simgesi okumaları atılır (`L3`, `R2`, `C`, `8`, `×`,
        /// `○`, `(X)` …; en çok 2 parça). Gerçek sözcükler (`progress`, `exit`) kalır.
        public static func buttonName(_ line: String) -> String {
            var words = Text.words(Corners.cleanMenuLine(line).lowercased())
            var dropped = 0
            while words.count >= 2, dropped < 2, let last = words.last, isGlyph(last) {
                words.removeLast()
                dropped += 1
            }
            return words.joined(separator: " ")
        }

        static func isGlyph(_ token: String) -> Bool {
            token.trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}<>")).count <= 2
        }
    }
}

// MARK: - Kartı bulma (tarif §9.2)

extension GameReading {
    /// Haritada seçili görevin kartı.
    public struct MapCard: Equatable, Sendable {
        /// Kartın üst şeridindeki görev adı (`STEAL VEHICLES FOR MOSES`); başlığın üstünde, cümlelerle aynı solda.
        /// Kartın kimliğine (`fullText`, `key`) girmez: aynı görevin kartlarında hep aynıdır.
        public var header: String?
        public var title: String?
        public var sentences: [String]
        /// Kart kutusu (başlık ve hedef satırı dahil, kare oranı).
        public var box: Box
        /// Kart satırlarının ortanca boyu.
        public var lineHeight: Double
        /// İlk cümle satırının sol kenarı.
        public var left: Double

        /// Kartın alt satırları (`SECURITY` / `LOW`, `TAKE VALUE` / `$100 - $1,000`, `FEATURES`): etiket ve sağdaki değer.
        /// Çeviri bunları da örter, o yüzden onlar da çevrilip aynı kutuya yazılır.
        public var stats: [Stat] = []

        public struct Stat: Equatable, Sendable {
            public var label: String
            public var value: String?
            public init(label: String, value: String? = nil) { self.label = label; self.value = value }
        }

        public init(title: String?, sentences: [String], box: Box, lineHeight: Double, left: Double, stats: [Stat] = [],
                    header: String? = nil) {
            self.header = header; self.title = title; self.sentences = sentences; self.box = box; self.lineHeight = lineHeight; self.left = left
            self.stats = stats
        }

        public var fullText: String { ([title].compactMap { $0 } + sentences).joined(separator: " ") }
        public var wordCount: Int { Text.words(fullText).count }
        /// Kart anahtarı = sadeleştirilmiş tam metin + `@` + `⌊üst × 50⌋`.
        public var key: String { Text.key(fullText) + "@" + String(Int(floor(box.top * 50))) }
    }

    public enum MapCardFinder {
        static let distance = #"\b\d+(?:[.,]\d+)?\s?(?:km|mi|ft|m|ml)\b"#
        static let leadFragments: Set<String> = ["i", "•", "●", "◆", "△", "▲", "ml"]

        struct Row { var text: String; var box: Box }

        /// Aday satırlar: uzaklık etiketi ve baştaki harfsiz parçalar silinmiş. `minX`: satır bundan sağda başlamalı
        /// (ilk tur 0,30: soldaki menü listesi `Declasse Yosemite 1500` cümle sanılmasın).
        static func candidates(_ lines: [Line], minX: Double = 0.30) -> [Row] {
            var out: [Row] = []
            for l in lines {
                guard var b = l.box, b.right > minX else { continue }
                var t = l.text
                // Haritadaki pinin uzaklığı (`1.62 km`) kart satırına yapışabilir: silinir, baştaysa sol kenar silinen
                // karakter payı kadar sağa kayar (eskiden yalnız 0,5'e çekiliyordu; kutu pini örtüyordu).
                if let r = t.range(of: distance, options: [.regularExpression, .caseInsensitive]) {
                    let before = t[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                    if before.isEmpty || !before.contains(where: \.isLetter), b.width > 0, !t.isEmpty {
                        var cut = t.distance(from: t.startIndex, to: r.upperBound)
                        while cut < t.count, t[t.index(t.startIndex, offsetBy: cut)] == " " { cut += 1 }
                        b.left += b.width * Double(cut) / Double(t.count)
                    }
                    t = Text.squeeze(t.replacingOccurrences(of: distance, with: " ", options: [.regularExpression, .caseInsensitive]))
                    if minX > 0, b.left < 0.5 { b.left = 0.5 }
                }
                let total = max(1, t.count)
                var words = Text.words(t)
                var dropped = 0
                while let f = words.first, !f.contains(where: \.isLetter) { dropped += f.count + 1; words.removeFirst() }
                if dropped > 0 {
                    b.left += b.width * Double(min(dropped, total)) / Double(total)
                    t = words.joined(separator: " ")
                }
                guard b.left > minX, Text.letterCount(t) >= 3 else { continue }
                out.append(Row(text: t, box: b))
            }
            return out.sorted { $0.box.top < $1.box.top }
        }

        static func isSentenceRow(_ t: String) -> Bool {
            Text.words(t).count >= 3 && t.filter(\.isLowercase).count >= 6
        }

        static func overlapsX(_ a: Box, _ b: Box, padding: Double = 0) -> Bool {
            min(a.right, b.right) + padding > max(a.left, b.left)
        }

        /// Cümle başındaki simge kırıntılarını (büyük harften önce) atar.
        static func stripLeadFragments(_ text: String) -> String {
            var words = Text.words(text)
            while words.count >= 2, words[1].first?.isUppercase == true,
                  leadFragments.contains(words[0]) || words[0].contains(where: \.isNumber) || !words[0].contains(where: \.isLetter) {
                words.removeFirst()
            }
            return words.joined(separator: " ")
        }

        static func join(_ a: String, _ b: String) -> String {
            if a.hasSuffix("-") { return a + b }
            return a + " " + b
        }

        /// Kart satırlarından kartı kurar. Önce sağ taraf (x > 0,30) aranır; yoksa kart ekranın solunda da olabilir
        /// (duraklatma menüsünün MAP sekmesinde sol üstteki görev kartı `BREAKFAST RUN`, 23:49 karesi). Solda yalnız
        /// yapısıyla tanınır: büyük harfli başlık hemen üstte, cümleler nokta/ünlemle biter, en az 6 sözcük. Soldaki
        /// menü listesinin satırları (`Declasse Yosemite 1500`, tek sözcüklü sekmeler) bu yapıda değildir.
        public static func find(_ lines: [Line]) -> MapCard? {
            if let c = find(lines, minX: 0.30) { return c }
            guard let c = find(lines, minX: 0), c.title != nil, c.wordCount >= 6,
                  c.sentences.allSatisfy(Text.endsSentence) else { return nil }
            return c
        }

        static func find(_ lines: [Line], minX: Double) -> MapCard? {
            let rows = candidates(lines, minX: minX)
            guard let startIndex = rows.firstIndex(where: { isSentenceRow($0.text) }) else { return nil }
            var first = rows[startIndex]
            // Başlık.
            var title: Row?
            for r in rows[..<startIndex] {
                let below = r.box.bottom - first.box.top
                guard below <= 0.01, first.box.top - r.box.bottom < 0.06, overlapsX(r.box, first.box, padding: 0.05) else { continue }
                var t = Text.words(r.text)
                while let l = t.last, t.count > 1, (1...3).contains(l.count), !l.contains(where: \.isLetter) { t.removeLast() }
                let text = t.joined(separator: " ")
                if Text.letterCount(text) >= 3, !Text.hasLowercase(text) { title = Row(text: text, box: r.box) }
            }
            // Başlığın solu ilk cümlenin solundan en çok 0,01 solda olabilir: fazlası haritadan yapışan yazıdır
            // (Vision `1.62 km`yi `162 km` okuyunca uzaklık silinmiyordu).
            if var t = title, t.box.left < first.box.left - 0.01 { t.box.left = first.box.left - 0.01; title = t }
            // Kartın üst şeridi (görev adı): başlığın hemen üstünde, cümlelerle aynı solda, büyük harfli.
            var header: Row?
            if let t = title {
                let lh = max(first.box.height, t.box.height)
                for r in rows where r.box.bottom <= t.box.top + 0.005 && t.box.top - r.box.bottom < 1.5 * lh {
                    guard abs(r.box.left - first.box.left) < 0.02, Text.letterCount(r.text) >= 3, !Text.hasLowercase(r.text),
                          !MapScreen.isButton(r.text), overlapsX(r.box, first.box) else { continue }
                    header = r
                }
            }
            // Haritadaki büyük yer adı (`Port Gellhorn`) okumada ilk cümle satırına yapışabilir: satır başlıktan
            // belirgin solda başlıyorsa baştaki büyük harfli sözcükler atılır (titremenin kaynağı).
            if let t = title { first = clipMapLabel(first, titleLeft: t.box.left) }
            var card = [first]
            for r in rows[(startIndex + 1)...] {
                let prev = card.last!.box
                let gap = r.box.top - prev.bottom
                if isSentenceRow(r.text), gap < 2.6 * prev.height, overlapsX(r.box, prev), abs(r.box.left - first.box.left) < 0.06 {
                    card.append(r)
                } else if gap < 1.2 * prev.height, abs(r.box.left - prev.left) < 0.03, Text.hasLowercase(r.text),
                          !Text.endsSentence(card.last!.text) {
                    card.append(r)
                } else {
                    break
                }
            }
            // Cümleler.
            let rightEnd = card.map(\.box.right).max()!
            var sentences: [(text: String, firstLeft: Double)] = []
            var prev: Row?
            for r in card {
                if let p = prev, let last = sentences.last {
                    let lowerStart = r.text.first?.isLowercase == true
                    let continues = (lowerStart && !Text.endsSentence(last.text))
                        || (abs(r.box.left - last.firstLeft) < 0.03 && r.box.top - p.box.bottom < p.box.height
                            && !(p.box.right < rightEnd - 0.04 && r.text.first?.isUppercase == true))
                    if continues {
                        sentences[sentences.count - 1].text = join(last.text, r.text)
                        prev = r
                        continue
                    }
                }
                sentences.append((r.text, r.box.left))
                prev = r
            }
            var box = Box.union(card.map(\.box) + [title?.box, header?.box].compactMap { $0 })!
            // Hedef satırı.
            if let goal = rows[(startIndex + 1)...].first(where: { r in
                Text.regex(#"^goal\b"#, r.text) && r.box.top - box.bottom <= 0.05 && r.box.top >= box.top
                    && r.box.left >= box.left - 0.03 && r.box.right <= box.right + 0.08
            }) {
                box = box.union(goal.box)
            }
            // Alt satırlar (etiket + değer).
            let (stats, statsBox) = findStats(rows: rows, lines: lines, below: box, left: title?.box.left ?? first.box.left)
            if let sb = statsBox { box = box.union(sb) }
            let lh = Text.median(card.map(\.box.height)) ?? 0.02
            return MapCard(title: title?.text, sentences: sentences.map { stripLeadFragments($0.text) }, box: box,
                           lineHeight: lh, left: first.box.left, stats: stats, header: header.map { Text.squeeze($0.text) })
        }

        /// İlk cümle satırına yapışmış harita yer adını atar. Atılacak sözcük sayısı: baştaki en çok 3 büyük harfli
        /// sözcük; kalan da büyük harfle başlamalı ve atılan kısmın harf oranı satırın başlığın solunda kalan
        /// payını (+0,05) aşmamalı. Yer adı yazısı büyük olduğundan harf oranı gerçek payın altında kalır.
        static func clipMapLabel(_ row: Row, titleLeft: Double) -> Row {
            guard row.box.left < titleLeft - 0.03, row.box.width > 0 else { return row }
            let share = (titleLeft - row.box.left) / row.box.width
            let words = Text.words(row.text)
            let total = Double(max(1, row.text.count))
            var best: Int?
            var k = 1
            while k <= min(3, words.count - 3) {
                let dropped = words[..<k]
                guard dropped.allSatisfy({ $0.first?.isUppercase == true }) else { break }
                let chars = Double(dropped.map(\.count).reduce(0, +) + k)
                if words[k].first?.isUppercase == true, chars / total <= share + 0.05 { best = k }
                k += 1
            }
            guard let n = best else { return row }
            var b = row.box
            b.left = titleLeft
            return Row(text: words[n...].joined(separator: " "), box: b)
        }

        /// Kartın cümlelerinin altındaki büyük harfli etiket satırları ve aynı hizadaki sağ değerleri
        /// (`SECURITY … LOW`). Değer rakam içermeli ya da en az 3 harf olmalı (simge kırıntısı `IR` sayılmaz).
        static func findStats(rows: [Row], lines: [Line], below box: Box, left: Double) -> ([MapCard.Stat], Box?) {
            var stats: [MapCard.Stat] = []
            var union: Box?
            var lastBottom = box.bottom
            for r in rows where r.box.top >= box.bottom - 0.005 {
                if r.box.top - lastBottom > 0.06 { break }
                guard abs(r.box.left - left) < 0.06, Text.letterCount(r.text) >= 3, !Text.hasLowercase(r.text),
                      r.box.right < left + 0.25 else { continue }
                if MapScreen.isButton(r.text) { break }
                var b = r.box
                if b.left < left { b.left = left }
                let mid = (r.box.top + r.box.bottom) / 2
                let value = lines.compactMap { l -> (String, Box)? in
                    guard let lb = l.box, lb.left > r.box.right + 0.02, lb.right <= box.right + 0.05,
                          lb.top - 0.01 <= mid, lb.bottom + 0.01 >= mid else { return nil }
                    let t = Text.squeeze(l.text)
                    guard t.contains(where: \.isNumber) || Text.letterCount(t) >= 3 else { return nil }
                    return (t, lb)
                }.min { $0.1.left < $1.1.left }
                if let v = value { b = b.union(v.1) }
                stats.append(MapCard.Stat(label: Text.squeeze(r.text), value: value?.0))
                union = union.map { $0.union(b) } ?? b
                lastBottom = r.box.bottom
                if stats.count >= 6 { break }
            }
            return (stats, union)
        }
    }
}

// MARK: - Terim ve mekân kuralları (tarif §9.4)

extension GameReading {
    public enum MapCardText {
        static let terms: [(String, String)] = [
            ("KAPALI TUTULMASI", "DEPOSU"), ("Kapalı Tutulması", "Deposu"), ("kapalı tutulması", "deposu"),
            ("işaretli faturaların", "işaretli paraların"), ("işaretli faturalar", "işaretli paralar"),
            ("işaretli fatura", "işaretli para"),
            ("NARKOTİK", "UYUŞTURUCU"), ("narkotik", "uyuşturucu"),
            ("trafik ışığı papağan balığı", "stoplight papağanbalığı"), ("kırmızı ışık papağan balığı", "stoplight papağanbalığı"),
        ]

        public static func fixTerms(_ text: String) -> String {
            var t = text
            for (wrong, right) in terms { t = t.replacingOccurrences(of: wrong, with: right) }
            return t
        }

        static let businessWords: Set<String> = [
            "distributor", "shop", "store", "dive bar", "bar", "restaurant", "dealer", "club", "diner", "garage",
            "convenience", "wholesaler", "boutique", "salon", "motel", "hotel", "bodega",
        ]
        static let venueTitleWords: Set<String> = [
            "CUSTOMS", "AUTO", "SHOP", "BAR", "CLUB", "MOTORS", "GARAGE", "SPEEDWAY", "DINER", "CAFE", "GRILL", "MOTEL",
            "HOTEL", "STORE", "MART", "LOUNGE", "SALOON", "TACKLE", "ANCHOR", "MARINA", "AMMU-NATION", "BARBER", "TATTOO", "PAWN",
        ]

        /// Başlık bir mekân adı mı (çevrilmez)?
        public static func isVenue(title: String, description: String?) -> Bool {
            if let d = description {
                let first = Text.keyWords(d).prefix(4)
                if first.contains(where: { businessWords.contains($0) || $0.hasSuffix("bar") && $0.count > 3 }) { return true }
            }
            let words = Text.words(title.uppercased()).map { $0.trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "-"))) }
            if words.contains(where: venueTitleWords.contains) { return true }
            return title.uppercased().hasPrefix("THE ") && words.count <= 4
        }

        /// `BUY FLOWERS` → `Buy Flowers` (çevirmene giden başlık).
        public static func titleCase(_ title: String) -> String {
            Text.words(title).map { w in
                guard let f = w.first else { return w }
                return String(f).uppercased() + w.dropFirst().lowercased()
            }.joined(separator: " ")
        }

        /// Alt satır değeri çevrilir mi? Rakam ya da para içermeyen, harfli değerler (`LOW`).
        public static func translatableValue(_ v: String) -> Bool {
            !v.contains(where: { $0.isNumber || $0 == "$" }) && Text.letterCount(v) >= 3
        }

        /// Türkçe büyük harf (`i` → `İ`).
        public static func turkishUpper(_ text: String) -> String { text.uppercased(with: Locale(identifier: "tr_TR")) }

        static let turkishLetters = Set("ğışĞİŞ")
        public static func hasTurkishLetters(_ text: String) -> Bool { text.contains { turkishLetters.contains($0) } }
    }
}
