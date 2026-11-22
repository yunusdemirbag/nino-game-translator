// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Eski biçimli oyun paketi: İngilizce metin yok, satırlar `LineKey` ile bulunur.
public struct LegacyPack: Sendable {
    public enum LoadError: Error, Equatable {
        case badGzip
        case invalidJSON
        case unsupportedFormat(Int)
        case noEntries
    }

    public let id: String
    public let title: String
    public let format: Int
    /// Tam satırlar.
    public let entries: [UInt64: String]
    /// Çok cümleli satırların parçaları (biçim 2).
    public let segments: [UInt64: String]
    /// Bulanık dizin; yoksa ya da bozuksa `nil`.
    public let fuzzy: FuzzyIndex?

    public var lineCount: Int { entries.count }

    public init(id: String, title: String? = nil, format: Int = 2, entries: [UInt64: String],
                segments: [UInt64: String] = [:], fuzzy: FuzzyIndex? = nil) {
        self.id = id
        self.title = title ?? id
        self.format = format
        self.entries = entries
        self.segments = segments
        self.fuzzy = fuzzy
    }

    /// Satırın Türkçesi: önce tam satır, sonra parça.
    public func text(for key: UInt64) -> String? { entries[key] ?? segments[key] }

    public func exact(_ sentence: String) -> String? {
        LineKey.key(sentence).flatMap(text(for:))
    }

    // MARK: Dosya

    /// `.json.gz` ya da `.json` (yeni biçim `.ninopack.json` hariç).
    public static func isPackFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasSuffix("." + TranslationPack.fileExtension) { return false }
        return name.hasSuffix(".json.gz") || name.hasSuffix(".json")
    }

    /// Dosya adından kimlik: `mafia.json.gz` → `mafia`.
    public static func baseName(_ fileName: String) -> String {
        for ext in [".json.gz", ".json"] where fileName.hasSuffix(ext) { return String(fileName.dropLast(ext.count)) }
        return fileName
    }

    public init(contentsOf url: URL) throws {
        try self.init(data: try Data(contentsOf: url), fileName: url.lastPathComponent)
    }

    public init(data raw: Data, fileName: String) throws {
        var data = raw
        if Gzip.isGzip(raw) {
            do { data = try Gzip.decompress(raw) } catch { throw LoadError.badGzip }
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoadError.invalidJSON
        }
        let fallbackID = Self.baseName(fileName)
        var allKeys = Set<UInt64>()

        func readTable(_ value: Any?) -> [UInt64: String] {
            guard let dict = value as? [String: Any] else { return [:] }
            var out: [UInt64: String] = [:]
            out.reserveCapacity(dict.count)
            for (hex, v) in dict {
                guard let key = LineKey.parse(hex), let text = v as? String else { continue }
                allKeys.insert(key)
                let clean = Self.cleanTurkish(text)
                if !clean.isEmpty { out[key] = clean }
            }
            return out
        }

        if let format = object["format"] {
            let f = (format as? NSNumber)?.intValue ?? -1
            guard f == 1 || f == 2 else { throw LoadError.unsupportedFormat(f) }
            let id = (object["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackID
            let title = (object["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
            let entries = readTable(object["entries"])
            let segments = f == 2 ? readTable(object["segments"]) : [:]
            guard !entries.isEmpty else { throw LoadError.noEntries }
            let fuzzy = (object["fuzzy"] as? [String: Any]).flatMap { FuzzyIndex(json: $0, keys: allKeys) }
            self.init(id: id, title: title, format: f, entries: entries, segments: segments, fuzzy: fuzzy)
        } else {
            let entries = readTable(object)
            guard !entries.isEmpty else { throw LoadError.noEntries }
            self.init(id: fallbackID, title: fallbackID, format: 1, entries: entries)
        }
    }

    /// Türkçedeki biçim etiketleri silinir, boşluklar teklenir.
    static func cleanTurkish(_ text: String) -> String {
        LineKey.replacingTags(in: text, with: "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: Bulanık eşleme

    /// Önce tek düzeltme, sonra Bloom benzerliği. Bulunamazsa ya da belirsizse `nil`.
    public func fuzzyMatch(_ sentence: String) -> String? {
        singleEditMatch(sentence) ?? bloomMatch(sentence)
    }

    static let confusions: [(String, String)] = [
        ("rn", "m"), ("m", "rn"), ("cl", "d"), ("d", "cl"), ("vv", "w"), ("ri", "n"), ("n", "ri"), ("li", "h"),
        ("l", "i"), ("i", "l"), ("1", "l"), ("1", "i"), ("0", "o"), ("5", "s"), ("j", "i"), ("c", "e"), ("e", "c"),
        ("a", "o"), ("o", "a"), ("h", "b"), ("b", "h"), ("f", "t"), ("t", "f"), ("u", "v"), ("v", "u"), ("y", "v"),
        ("v", "y"), ("q", "g"), ("g", "q"),
    ].map { ($0.0, $0.1) }

    /// Tek bir OCR düzeltmesiyle oluşabilecek hâller (özgün hâl hariç).
    static func singleEditVariants(_ canon: String) -> Set<String> {
        let chars = Array(canon)
        var out = Set<String>()
        for (read, actual) in confusions {
            let r = Array(read)
            guard r.count <= chars.count else { continue }
            for i in 0...(chars.count - r.count) where Array(chars[i..<(i + r.count)]) == r {
                out.insert(String(chars[..<i]) + actual + String(chars[(i + r.count)...]))
            }
        }
        for i in chars.indices {
            var c = chars
            c.remove(at: i)
            out.insert(String(c))
        }
        for i in 1..<max(1, chars.count) where chars[i - 1] != " " && chars[i] != " " {
            var c = chars
            c.insert(" ", at: i)
            out.insert(String(c))
        }
        out.remove(canon)
        return out.filter { !$0.isEmpty && !$0.hasPrefix(" ") && !$0.hasSuffix(" ") && !$0.contains("  ") }
    }

    func singleEditMatch(_ sentence: String) -> String? {
        let canon = LineKey.canon(sentence)
        guard (6...48).contains(canon.count) else { return nil }
        var found: String?
        for v in Self.singleEditVariants(canon) {
            guard let t = text(for: LineKey.hash(canon: v)) else { continue }
            if let f = found, f != t { return nil }
            found = t
        }
        return found
    }

    struct Candidate { var index: Int; var score: Double; var text: String }

    func bloomMatch(_ sentence: String) -> String? {
        guard let fuzzy else { return nil }
        let folded = FuzzySignature.fold(sentence)
        guard folded.count >= FuzzySignature.minFoldedLength else { return nil }
        let query = FuzzySignature(folded: folded)
        let L = query.length
        let threshold = FuzzySignature.threshold(length: L, noisy: FuzzySignature.isNoisy(sentence))
        let floor = threshold - FuzzySignature.margin

        var candidates: [Int: Candidate] = [:]
        for len in (L - L / 4)...min(255, L + L / 4) {
            for i in fuzzy.byLength[len] {
                let s = FuzzySignature.similarity(query, fuzzy.signatures[i])
                guard s >= floor, let t = text(for: fuzzy.keys[i]) else { continue }
                candidates[i] = Candidate(index: i, score: s, text: t)
            }
        }
        if let best = candidates.values.map(\.score).max(), best >= threshold {
            return Self.choose(Array(candidates.values), threshold: threshold)
        }
        guard L >= 22 else { return nil }

        let clauses = Self.clauses(sentence)
        let lower = max(22, L * 11 / 20), upper = min(255, L * 5 / 2)
        if lower <= upper {
            for len in lower...upper where len != L {
                for i in fuzzy.byLength[len] {
                    let cand = fuzzy.signatures[i]
                    let (q, c) = FuzzySignature.aligned(query, cand)
                    let candidateShorter = len < L
                    let (short, long) = candidateShorter ? (c, q) : (q, c)
                    let shortSet = short.reduce(0) { $0 + $1.nonzeroBitCount }
                    var common = 0
                    for k in 0..<q.count { common += (q[k] & c[k]).nonzeroBitCount }
                    guard common * 10 >= 9 * shortSet else { continue }
                    let shortCovered = 100 * FuzzySignature.coverage(short, in: long)
                    let longCovered = 100 * FuzzySignature.coverage(long, in: short)
                    guard shortCovered >= 90, longCovered >= (candidateShorter ? 55 : 25) else { continue }
                    let score = shortCovered - 10
                    guard score >= floor else { continue }
                    if candidateShorter, !Self.clausesAppear(clauses, in: cand) { continue }
                    guard let t = text(for: fuzzy.keys[i]) else { continue }
                    if score > candidates[i]?.score ?? -1 { candidates[i] = Candidate(index: i, score: score, text: t) }
                }
            }
        }
        return Self.choose(Array(candidates.values), threshold: threshold)
    }

    static func choose(_ candidates: [Candidate], threshold: Double) -> String? {
        guard let best = candidates.min(by: { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }),
              best.score >= threshold else { return nil }
        let ambiguous = candidates.contains { $0.index != best.index && $0.text != best.text && $0.score > best.score - FuzzySignature.margin }
        return ambiguous ? nil : best.text
    }

    // MARK: Yan cümleler

    /// Okuma birden çok yan cümleyse her birinin üçlülerinin en az %30'u adayda olmalı.
    static func clausesAppear(_ clauses: [String], in candidate: FuzzySignature) -> Bool {
        guard clauses.count > 1 else { return true }
        for (n, clause) in clauses.enumerated() {
            var options = [clause]
            if n == 0 { options.append(stripCaps(clause, fromStart: true)) }
            if n == clauses.count - 1 { options.append(stripCaps(clause, fromStart: false)) }
            let passes = options.contains { option in
                let folded = FuzzySignature.fold(option)
                if folded.count < 6 || isCornerText(option) { return true }
                let sig = FuzzySignature(folded: folded, bits: candidate.bitCount, length: min(folded.count, 255))
                return FuzzySignature.coverage(sig.words, in: candidate.words) >= 0.30
            }
            if !passes { return false }
        }
        return true
    }

    /// Baştaki ya da sondaki en çok 3 büyük harfli sözcüğü atar.
    static func stripCaps(_ text: String, fromStart: Bool) -> String {
        var words = text.split(separator: " ").map(String.init)
        func isCaps(_ w: String) -> Bool { w.contains(where: \.isLetter) && !w.contains(where: \.isLowercase) }
        for _ in 0..<3 {
            guard let w = fromStart ? words.first : words.last, isCaps(w) else { break }
            if fromStart { words.removeFirst() } else { words.removeLast() }
        }
        return words.joined(separator: " ")
    }

    /// Köşe yazısı: ≤ 4 sözcük ve (`•` var ya da her sözcük büyük harfle başlayıp yalnız harf/rakam).
    public static func isCornerText(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty, words.count <= 4 else { return false }
        if text.contains("•") { return true }
        return words.allSatisfy { w in
            (w.first?.isUppercase ?? false) && w.allSatisfy { $0.isLetter || $0.isNumber }
        }
    }

    /// Yan cümlelere böler; 6 harften kısa yan cümle komşusuna eklenir.
    static func clauses(_ text: String) -> [String] {
        let enders: Set<Character> = [".", "!", "?", "…", ",", ";", ":"]
        let strong: Set<Character> = [",", ";", ":", "…"]
        let closers = Set<Character>("\"'”’)]")  // cümle sonundan sonra gelebilen kapanışlar
        let chars = Array(text)
        var parts: [String] = []
        var start = 0, i = 0
        while i < chars.count {
            guard enders.contains(chars[i]) else { i += 1; continue }
            var j = i
            while j < chars.count, enders.contains(chars[j]) { j += 1 }
            let run = chars[i..<j]
            while j < chars.count, closers.contains(chars[j]) { j += 1 }
            var k = j
            while k < chars.count, chars[k].isWhitespace { k += 1 }
            if k > j, k < chars.count,
               chars[k].isUppercase || run.contains(where: { strong.contains($0) }) || run.filter({ $0 == "." }).count > 1 {
                parts.append(String(chars[start..<j]))
                start = k
                i = k
            } else {
                i = j
            }
        }
        if start < chars.count { parts.append(String(chars[start...])) }
        parts = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        func letters(_ s: String) -> Int { s.filter(\.isLetter).count }
        var merged: [String] = []
        var carry = ""
        for p in parts {
            let joined = carry.isEmpty ? p : carry + " " + p
            if letters(joined) < 6 { carry = joined } else { merged.append(joined); carry = "" }
        }
        if !carry.isEmpty {
            if let last = merged.popLast() { merged.append(last + " " + carry) } else { merged.append(carry) }
        }
        return merged
    }
}

/// Paketteki bulanık dizin: imzası olan anahtarlar, uzunlukları ve Bloom imzaları.
public struct FuzzyIndex: Sendable {
    public let keys: [UInt64]
    public let signatures: [FuzzySignature]
    /// Uzunluğa göre imza sıraları (0…255).
    let byLength: [[Int]]

    public init(keys: [UInt64], signatures: [FuzzySignature]) {
        self.keys = keys
        self.signatures = signatures
        var buckets = [[Int]](repeating: [], count: 256)
        for (i, s) in signatures.enumerated() { buckets[min(255, s.length)].append(i) }
        self.byLength = buckets
    }

    public func signature(for key: UInt64) -> FuzzySignature? {
        guard let i = keys.firstIndex(of: key) else { return nil }
        return signatures[i]
    }

    /// Paketteki `fuzzy` nesnesi; tutarsızsa `nil`.
    init?(json: [String: Any], keys allKeys: Set<UInt64>) {
        guard (json["version"] as? NSNumber)?.intValue == 1,
              let count = (json["count"] as? NSNumber)?.intValue, count == allKeys.count,
              let mask = (json["mask"] as? String).flatMap({ Data(base64Encoded: $0) }).map([UInt8].init),
              let lengths = (json["lengths"] as? String).flatMap({ Data(base64Encoded: $0) }).map([UInt8].init),
              let blooms = (json["blooms"] as? String).flatMap({ Data(base64Encoded: $0) }).map([UInt8].init),
              mask.count == (count + 7) / 8 else { return nil }
        let sorted = allKeys.sorted()
        var keys: [UInt64] = [], sigs: [FuzzySignature] = []
        var offset = 0
        for i in 0..<count where mask[i >> 3] & (1 << UInt8(i & 7)) != 0 {
            guard keys.count < lengths.count else { return nil }
            let length = Int(lengths[keys.count])
            let size = FuzzySignature.bits(forLength: length) / 8
            guard offset + size <= blooms.count,
                  let sig = FuzzySignature(length: length, bytes: blooms[offset..<(offset + size)]) else { return nil }
            keys.append(sorted[i])
            sigs.append(sig)
            offset += size
        }
        guard keys.count == lengths.count, offset == blooms.count else { return nil }
        self.init(keys: keys, signatures: sigs)
    }
}
