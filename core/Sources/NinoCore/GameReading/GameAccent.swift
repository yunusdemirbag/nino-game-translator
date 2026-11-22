// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation

// MARK: - Vurgu renkli sözcükler (GTA 6 görev şeridindeki pembe sözcük; telefon-harita.md §11)

extension GameReading {
    /// Oyunun renkli (pembe) vurguladığı sözcükleri görüntüden bulur ve çeviride karşılığını `⟦…⟧` ile işaretler.
    /// TV sayfası `⟦…⟧` arasını vurgu rengiyle çizer (protokol.md "screen" → `text`).
    ///
    /// Yöntem: satır kutusunun her sütununda pembe ve yazı (parlak) nokta sayılır; sözcüklerin yeri harf sayısıyla
    /// kestirilir; pembe/yazı oranı ≥ 0,4 olan sözcük vurguludur. Çeviride karşılık: vurgulu ifadenin kendi çevirisi
    /// (`term`) Türkçe ekler yüzünden kök eşlemesiyle aranır; bulunmazsa vurgusuz.
    public enum Accent {
        /// Vurgu rengi mi? GTA 6 pembesi ≈ (255, 95, 178); kırmızı/turuncu (B ≈ G) ve beyaz sayılmaz.
        public static func isAccent(_ c: RGB) -> Bool {
            c.r >= 160 && c.r - c.g >= 60 && c.b - c.g >= 15
        }

        /// Satırın vurgulu ifadeleri (art arda vurgulu sözcükler birleşir). `image` tam kare; satır kutusu kare oranında.
        public static func phrases(_ line: Line, image: CGImage) -> [String] {
            guard let box = line.box else { return [] }
            let w = Double(image.width), h = Double(image.height)
            let rect = CGRect(x: (box.left * w).rounded(.down), y: (box.top * h).rounded(.down),
                              width: (box.width * w).rounded(.up), height: (box.height * h).rounded(.up))
                .intersection(CGRect(x: 0, y: 0, width: w, height: h))
            guard rect.width >= 4, rect.height >= 2, let crop = image.cropping(to: rect),
                  let px = PhonePixels.from(crop, width: crop.width, height: crop.height) else { return [] }
            return phrases(text: line.text, pixels: px)
        }

        /// `pixels`: yalnız satırın kutusu.
        public static func phrases(text: String, pixels: PhonePixels) -> [String] {
            let words = Text.words(text)
            guard !words.isEmpty, pixels.width > 0 else { return [] }
            var accent = [Int](repeating: 0, count: pixels.width)
            var ink = [Int](repeating: 0, count: pixels.width)
            for x in 0..<pixels.width {
                for y in 0..<pixels.height {
                    let c = pixels.color(x, y)
                    if isAccent(c) { accent[x] += 1; ink[x] += 1 } else if c.luma >= 170 { ink[x] += 1 }
                }
            }
            guard accent.reduce(0, +) >= 3 else { return [] }
            // Sözcüklerin yeri: harf başına 1, boşluk 0,45 pay.
            let weights = words.map { Double($0.count) }
            let total = weights.reduce(0, +) + 0.45 * Double(words.count - 1)
            var marked: [Bool] = []
            var start = 0.0
            for wgt in weights {
                let a = Int((start / total * Double(pixels.width)).rounded(.down))
                let b = min(pixels.width, Int(((start + wgt) / total * Double(pixels.width)).rounded(.up)))
                let acc = a < b ? accent[a..<b].reduce(0, +) : 0
                let all = a < b ? ink[a..<b].reduce(0, +) : 0
                marked.append(all > 0 && Double(acc) / Double(all) >= 0.4)
                start += wgt + 0.45
            }
            var out: [String] = []
            var current: [String] = []
            for (i, w) in words.enumerated() {
                if marked[i] { current.append(w) } else if !current.isEmpty { out.append(current.joined(separator: " ")); current = [] }
            }
            if !current.isEmpty { out.append(current.joined(separator: " ")) }
            return out.map { $0.trimmingCharacters(in: .punctuationCharacters) }.filter { Text.letterCount($0) >= 2 }
        }

        static let turkish = Locale(identifier: "tr_TR")

        static func stem(_ w: String) -> String { w.filter(\.isLetter).lowercased(with: turkish) }

        /// `translation` içinde `term`ün (vurgulu ifadenin çevirisi) karşılığını `⟦…⟧` ile sarar; yoksa `nil`.
        /// Eşleme kök ile: kısa (≤ 3 harf) sözcük tam, uzun sözcük en az 4 ortak baş harf (`liman` ~ `Limanlara`).
        public static func mark(_ translation: String, term: String) -> String? {
            // Tuş simgesi yer tutucuları (`⟦T1⟧`) vurgu işareti değildir: korunur.
            let ids = IconPlaceholders.ids(in: translation)
            var hidden = translation
            for id in ids { hidden = hidden.replacingOccurrences(of: IconPlaceholders.tag(id), with: "\u{E000}\(id.dropFirst())\u{E001}") }
            let clean = hidden.replacingOccurrences(of: "⟦", with: "").replacingOccurrences(of: "⟧", with: "")
            let termStems = Text.words(term).map(stem).filter { !$0.isEmpty }
            guard !termStems.isEmpty else { return nil }
            let words = Text.words(clean)
            func matches(_ w: String) -> Bool {
                let s = stem(w)
                guard !s.isEmpty else { return false }
                return termStems.contains { t in
                    if t.count <= 3 || s.count <= 3 { return t == s }
                    let common = zip(t, s).prefix { $0 == $1 }.count
                    return common >= min(t.count, 4) && common >= min(t.count, s.count) - 2
                }
            }
            let hits = words.indices.filter { matches(words[$0]) }
            guard let first = hits.first, let last = hits.last, last - first < termStems.count + 1 else { return nil }
            var out = words
            // Noktalama işaretin dışında kalır.
            let lead = String(out[first].prefix { !$0.isLetter && !$0.isNumber })
            out[first] = lead + "⟦" + out[first].dropFirst(lead.count)
            let tailCount = out[last].reversed().prefix { !$0.isLetter && !$0.isNumber }.count
            out[last] = String(out[last].dropLast(tailCount)) + "⟧" + String(out[last].suffix(tailCount))
            var joined = out.joined(separator: " ")
            for id in ids { joined = joined.replacingOccurrences(of: "\u{E000}\(id.dropFirst())\u{E001}", with: IconPlaceholders.tag(id)) }
            return joined
        }
    }
}
