// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Okumalar arasındaki ilişkiler: aynı altyazı, yeniden okuma, uzama, düzeltme (tarif §7.3, §7.4, §8.2).
extension GameReading {
    public enum Similarity {
        typealias T = GameReading.Text

        // MARK: Anlam işareti (§7.4)

        /// Olumsuzluk sözcükleri: yalın olanlar ve `n't` kısaltmalarının kesme işaretsiz hâli (kök + "t").
        static let negations: Set<String> = Set(["cannot", "neither", "never", "no", "nobody", "none", "nor", "not",
                                                 "nothing", "nowhere"])
            .union(contractionStems.map { $0 + "t" })
        /// `n't` kısaltmalarının kökü: yardımcı fiil + "n", ayrıca düzensiz üç kök (can't, won't, ain't).
        static let contractionStems: Set<String> = Set(
            ["do", "does", "did", "is", "are", "was", "were", "could", "should", "would", "have", "has", "had", "must", "need"]
                .map { $0 + "n" })
            .union(["can", "won", "ain"])
        static let digitLetters: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b"]

        static func letterize(_ w: String) -> String {
            String(w.map { digitLetters[$0] ?? $0 })
        }

        static func negationCount(_ words: [String]) -> Int {
            var n = 0
            for (i, raw) in words.enumerated() {
                let w = raw.contains(where: \.isLetter) ? letterize(raw) : raw
                if negations.contains(w) { n += 1 }
                if w == "t", i > 0, contractionStems.contains(letterize(words[i - 1])) { n += 1 }
            }
            return n
        }

        /// Okuma, gönderilende olmayan bir anlam işareti (olumsuzluk ya da yeni sayı) ekliyor mu?
        public static func addsMeaningMarker(_ reading: String, to sent: String) -> Bool {
            let r = T.keyWords(reading), s = T.keyWords(sent)
            if negationCount(r) > negationCount(s) { return true }
            let sentSet = Set(s)
            for (i, w) in r.enumerated() where w.contains(where: \.isNumber) && !sentSet.contains(w) {
                let candidates = [i < s.count ? s[i] : nil, (i + s.count - r.count) >= 0 && (i + s.count - r.count) < s.count ? s[i + s.count - r.count] : nil]
                let confusion = candidates.contains { c in
                    guard let c, c.contains(where: \.isLetter) else { return false }
                    return letterize(c) == letterize(w)
                }
                if !confusion { return true }
            }
            return false
        }

        // MARK: Sözcükler

        /// 1 harften uzun, rakamsız sözcükler.
        static func cleanWords(_ text: String) -> [String] {
            T.keyWords(text).filter { $0.count > 1 && !$0.contains(where: \.isNumber) }
        }

        static func common(_ short: [String], _ long: [String]) -> Int {
            let set = Set(long)
            return short.filter { set.contains($0) }.count
        }

        /// `new`, `old`'un uzaması mı?
        public static func isExtension(_ new: String, of old: String) -> Bool {
            let n = T.keyWords(new), o = T.keyWords(old)
            guard n.count > o.count, !o.isEmpty else { return false }
            if Array(n.prefix(o.count)) == o { return true }
            return o.count >= 2 && Array(n.suffix(o.count)) == o
        }

        // MARK: Aynı altyazı (§7.3)

        public static func isSameSubtitle(_ reading: String, sentLines: [String]) -> Bool {
            let sent = sentLines.joined(separator: " ")
            if addsMeaningMarker(reading, to: sent) { return false }
            let rk = T.key(reading), sk = T.key(sent)
            if rk.isEmpty || sk.isEmpty { return false }
            if rk.count > sk.count, rk.hasPrefix(sk) || rk.hasSuffix(sk) { return false }
            if T.ratio(reading, sent) >= 0.85 { return true }
            if rk.count < sk.count, sk.hasPrefix(rk) || sk.hasSuffix(rk) {
                for n in 1...sentLines.count {
                    if T.key(sentLines.prefix(n).joined(separator: " ")) == rk { return true }
                    if T.key(sentLines.suffix(n).joined(separator: " ")) == rk { return true }
                }
                return false
            }
            let rw = cleanWords(reading), sw = cleanWords(sent)
            // Sözcük örtüşmesi kuralları, temiz okunan ve anlamca farklı yeni satırı yutmaz
            // (`And shut the damn dog up.` → `Shut the damn dog up, man!`).
            if differsMeaningfully(reading, from: sent) { return false }
            if rw.count >= 4, Double(common(rw, sw)) >= 0.85 * Double(rw.count) { return true }
            let (short, long) = rw.count <= sw.count ? (rw, sw) : (sw, rw)
            if short.count >= 6, Double(short.count) / Double(long.count) >= 0.75,
               Double(common(short, long)) / Double(long.count) >= 0.75 { return true }
            return false
        }

        /// Temiz ve tam okunmuş (büyük harfle başlıyor, cümle bitiriyor, bozuk/çöp değil) okuma, gönderilenden
        /// farklı sözcükle başlıyor ve gönderilende olmayan bir sözcük ekliyor: yeniden okuma değil, yeni satırdır.
        public static func differsMeaningfully(_ reading: String, from sent: String) -> Bool {
            guard isComplete(reading), !isBroken(reading), !Filters.looksLikeJunk(reading) else { return false }
            let r = T.keyWords(reading), s = T.keyWords(sent)
            guard let rf = r.first, let sf = s.first, rf != sf else { return false }
            let sentSet = Set(s)
            return r.contains { $0.count >= 2 && $0.allSatisfy(\.isLetter) && !sentSet.contains($0) }
        }

        /// Bozuk biçimli okuma: büyük harfle ya da tırnak/üç nokta/tireyle başlamıyor (`/shut…`, `shut…`)
        /// ya da nokta ardından küçük harfle sürüyor (`up. man`).
        public static func isMalformed(_ reading: String) -> Bool {
            let t = reading.trimmingCharacters(in: .whitespaces)
            guard let f = t.first else { return false }
            if f.isLetter { if f.isLowercase { return true } }
            else if !("\"'“‘.…-–—(¿¡".contains(f) || f.isNumber) { return true }
            return T.regex(#"[a-z]{2}\. [a-z]"#, t, caseInsensitive: false)
        }

        /// Ekrandaki satırla ilgili (sözcüklerinin en az yarısı ortak) bozuk biçimli okuma: solma/geçiş karesi.
        public static func isMalformedReread(_ reading: String, of sent: String) -> Bool {
            guard T.endsSentence(sent), isMalformed(reading), !addsMeaningMarker(reading, to: sent), !isExtension(reading, of: sent) else { return false }
            return isRelated(reading, sent)
        }

        /// Ekrandakinin daha kötü yeniden okuması mı?
        public static func isWorseReread(_ reading: String, than sent: String) -> Bool {
            guard cleanWords(reading).count >= 5 else { return false }
            if differsMeaningfully(reading, from: sent) { return false }
            if isExtension(reading, of: sent) || isExtension(sent, of: reading) { return false }
            if addsMeaningMarker(reading, to: sent) { return false }
            let similar = T.sequenceRatio(T.keyWords(reading), T.keyWords(sent)) >= 0.65 || T.ratio(reading, sent) >= 0.75
            return similar && Filters.score(reading) < Filters.score(sent) + 4
        }

        /// TV'nin "yerine koy" bayrağı için: düzeltme ya da uzama.
        public static func isCorrection(_ new: String, of old: String) -> Bool {
            if isExtension(new, of: old) || isExtension(old, of: new) { return true }
            if T.ratio(new, old) >= 0.8 { return true }
            let a = cleanWords(new), b = cleanWords(old)
            let (short, long) = a.count <= b.count ? (a, b) : (b, a)
            guard short.count >= 5 else { return false }
            return T.sequenceRatio(T.keyWords(new), T.keyWords(old)) >= 0.65
                || Double(common(short, long)) / Double(max(1, long.count)) >= 0.7
        }

        // MARK: Okuma türleri (§8.2)

        static let typographic = Set("…’‘“”—–«»")

        /// Bozuk okuma.
        public static func isBroken(_ text: String) -> Bool {
            if text.unicodeScalars.contains(where: { !$0.isASCII }) {
                if text.contains(where: { !$0.isASCII && !typographic.contains($0) }) { return true }
            }
            for w in T.words(text) {
                let chars = Array(w)
                for i in chars.indices.dropFirst().dropLast() {
                    let c = chars[i]
                    if !c.isLetter, c != "'", c != "’", c != "-", chars[i - 1].isLetter, chars[i + 1].isLetter { return true }
                }
                for i in chars.indices.dropFirst() {
                    let a = chars[i - 1], b = chars[i]
                    if (a.isLetter && b.isNumber) || (a.isNumber && b.isLetter) { return true }
                }
                let letters = w.filter(\.isLetter)
                if letters.count == 1, w.allSatisfy({ $0.isLetter || $0.isPunctuation }), !["a", "A", "I", "o", "O"].contains(letters) { return true }
                if w.count > 14 { return true }
            }
            return false
        }

        /// Her satır büyük harfle başlıyor ve cümle bitiriyor.
        public static func isComplete(_ text: String) -> Bool {
            let lines = T.lines(text)
            guard !lines.isEmpty else { return false }
            return lines.allSatisfy { l in l.first(where: \.isLetter)?.isUppercase == true && T.endsSentence(l) }
        }

        public static func isRelated(_ a: String, _ b: String) -> Bool {
            let x = T.keyWords(a), y = T.keyWords(b)
            let (short, long) = x.count <= y.count ? (x, y) : (y, x)
            let c = common(short, long)
            if short.count <= 1 { return c >= 1 }
            return c >= 2 && c * 2 >= short.count
        }

        static func isSubsequence(_ a: [String], of b: [String]) -> Bool {
            var j = 0
            for w in b where j < a.count && w == a[j] { j += 1 }
            return j == a.count
        }

        static func isContiguous(_ a: [String], in b: [String]) -> Bool {
            guard !a.isEmpty, a.count <= b.count else { return false }
            for i in 0...(b.count - a.count) where Array(b[i..<(i + a.count)]) == a { return true }
            return false
        }

        /// `new`, `old`'un yeniden okuması mı?
        public static func isReread(_ new: String, of old: String) -> Bool {
            if addsMeaningMarker(new, to: old) { return false }
            let n = T.keyWords(new), o = T.keyWords(old)
            if n.count == o.count, T.key(new).count >= 4, T.ratio(new, old) >= 0.75 { return true }
            if n.count == o.count, n.count >= 2 {
                let rawNew = T.words(new)
                let diff = n.indices.filter { n[$0] != o[$0] }
                if !diff.isEmpty, diff.count * 2 < n.count, rawNew.count == n.count, diff.allSatisfy({ isBroken(rawNew[$0]) }) { return true }
            }
            if isBroken(new) || isBroken(old), isRelated(new, old) { return true }
            let contiguous = isContiguous(n, in: o)
            if n.count >= 2, n.count < o.count, !contiguous, isSubsequence(n, of: o) { return true }
            if contiguous, n.count < o.count {
                let startsLower = new.first(where: \.isLetter)?.isLowercase == true
                if !T.endsSentence(new) || startsLower { return true }
            }
            return false
        }
    }
}
