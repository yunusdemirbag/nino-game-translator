// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Bulanık eşleme için Bloom imzası (ardışık üçlüler, FNV-1a 64).
public struct FuzzySignature: Equatable, Sendable {
    public static let minFoldedLength = 16

    /// Katlanmış metnin uzunluğu (en çok 255).
    public let length: Int
    /// 64 bitlik sözcükler; bit sayısı `words.count * 64`.
    public let words: [UInt64]

    public var bitCount: Int { words.count * 64 }
    public var setBits: Int { words.reduce(0) { $0 + $1.nonzeroBitCount } }
    public var fill: Double { Double(setBits) / Double(bitCount) }

    public init(length: Int, words: [UInt64]) {
        self.length = length
        self.words = words
    }

    /// Satırın imzası; katlanmış boy 16'dan kısaysa `nil`.
    public init?(text: String) {
        let folded = Self.fold(text)
        guard folded.count >= Self.minFoldedLength else { return nil }
        self.init(folded: folded)
    }

    init(folded: [Character]) {
        let length = min(folded.count, 255)
        self.init(folded: folded, bits: Self.bits(forLength: length), length: length)
    }

    init(folded: [Character], bits: Int, length: Int) {
        var words = [UInt64](repeating: 0, count: bits / 64)
        for h in Self.trigramHashes(folded) {
            let bit = Int(h & UInt64(bits - 1))
            words[bit >> 6] |= 1 << UInt64(bit & 63)
        }
        self.init(length: length, words: words)
    }

    /// Küçük sonlu bayt dizisi (pakette saklanan biçim).
    public var bytes: [UInt8] {
        words.flatMap { w in (0..<8).map { UInt8(truncatingIfNeeded: w >> (8 * UInt64($0))) } }
    }

    public init?(length: Int, bytes: ArraySlice<UInt8>) {
        guard !bytes.isEmpty, bytes.count % 8 == 0 else { return nil }
        var words: [UInt64] = []
        words.reserveCapacity(bytes.count / 8)
        var i = bytes.startIndex
        while i < bytes.endIndex {
            var w: UInt64 = 0
            for k in 0..<8 { w |= UInt64(bytes[i + k]) << (8 * UInt64(k)) }
            words.append(w)
            i += 8
        }
        self.init(length: length, words: words)
    }

    // MARK: Kurallar

    public static func bits(forLength length: Int) -> Int {
        var b = 64
        while length * 3 > b, b < 256 { b *= 2 }
        return b
    }

    /// Sadeleşmiş metin, boşluksuz; OCR'ın karıştırdığı harfler bire indirilir.
    public static func fold(_ text: String) -> [Character] {
        var out: [Character] = []
        for ch in LineKey.canon(text) where ch != " " {
            switch ch {
            case "l", "1", "ı", "j": out.append("i")
            case "0": out.append("o")
            case "5": out.append("s")
            case "æ": out.append("a")
            case "ø", "œ": out.append("o")
            case "ß": out.append("s")
            default: out.append(ch)
            }
        }
        return out
    }

    static func trigramHashes(_ folded: [Character]) -> Set<UInt64> {
        guard folded.count >= 3 else { return [] }
        var seen = Set<UInt64>()
        for i in 0...(folded.count - 3) {
            var h: UInt64 = 0xcbf29ce484222325
            for ch in folded[i..<(i + 3)] {
                for b in ch.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
            }
            seen.insert(h)
        }
        return seen
    }

    /// Büyük imzayı küçüğün boyuna katlar (aynı üçlülerin küçük boydaki imzası).
    func folded(toWords n: Int) -> [UInt64] {
        guard words.count > n else { return words }
        var out = [UInt64](repeating: 0, count: n)
        for (i, w) in words.enumerated() { out[i % n] |= w }
        return out
    }

    /// İki imzayı aynı boya getirir.
    static func aligned(_ a: FuzzySignature, _ b: FuzzySignature) -> ([UInt64], [UInt64]) {
        let n = min(a.words.count, b.words.count)
        return (a.folded(toWords: n), b.folded(toWords: n))
    }

    /// `a`'nın bitlerinin `b`'de bulunma oranı, `b`'nin doluluğuyla arındırılmış (0–1).
    static func coverage(_ a: [UInt64], in b: [UInt64]) -> Double {
        let aSet = a.reduce(0) { $0 + $1.nonzeroBitCount }
        let bSet = b.reduce(0) { $0 + $1.nonzeroBitCount }
        let bits = b.count * 64
        guard aSet > 0, bSet > 0, bSet < bits else { return 0 }
        var common = 0
        for i in 0..<a.count { common += (a[i] & b[i]).nonzeroBitCount }
        let fill = Double(bSet) / Double(bits)
        return (Double(common) / Double(aSet) - fill) / (1 - fill)
    }

    /// Rastlantı arındırılmış benzerlik, 0–100.
    public static func similarity(_ query: FuzzySignature, _ candidate: FuzzySignature) -> Double {
        let (q, c) = aligned(query, candidate)
        let qa = coverage(q, in: c), aq = coverage(c, in: q)
        guard qa > 0 || aq > 0 else { return 0 }
        return max(0, 100 * min(qa, aq))
    }

    // MARK: Bozuk satır

    /// OCR izi taşıyan satır mı?
    public static func isNoisy(_ text: String) -> Bool {
        let typographic: Set<Character> = ["’", "‘", "“", "”", "—", "–", "…"]
        if text.contains(where: { !$0.isASCII && !typographic.contains($0) }) { return true }
        let edge = CharacterSet(charactersIn: ".,!?;:'\"()[]-…“”’‘")
        for raw in text.split(whereSeparator: \.isWhitespace) {
            let word = Array(String(raw).trimmingCharacters(in: edge))
            guard !word.isEmpty else { continue }
            if word.count > 14 { return true }
            if word.count == 1, word[0].isLetter, !["a", "A", "I", "o", "O"].contains(word[0]) { return true }
            if word.contains(where: \.isLetter), word.contains(where: \.isNumber) {
                for i in 1..<word.count where word[i - 1].isLetter && word[i].isNumber || word[i - 1].isNumber && word[i].isLetter {
                    return true
                }
            }
            if word.count >= 3 {
                for i in 1..<(word.count - 1) where !word[i].isLetter && word[i - 1].isLetter && word[i + 1].isLetter {
                    if !["'", "’", "-"].contains(word[i]) { return true }
                }
            }
        }
        return false
    }

    /// Kabul eşiği (0–100).
    public static func threshold(length: Int, noisy: Bool) -> Double {
        if noisy { return length < 24 ? 70 : (length < 40 ? 60 : 55) }
        return length < 24 ? 90 : 80
    }

    public static let margin = 5.0
}
