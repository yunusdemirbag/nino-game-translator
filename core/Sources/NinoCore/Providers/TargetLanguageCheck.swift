// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Bir metnin, verilen diller arasında `language` olma olasılığı (0–1).
public protocol LanguageGuesser: Sendable {
    func probability(_ text: String, is language: String, among languages: [String]) -> Double
}

#if canImport(NaturalLanguage)
/// Apple'ın dil tanıyıcısı.
public struct NaturalLanguageGuesser: LanguageGuesser {
    public init() {}
    public func probability(_ text: String, is language: String, among languages: [String]) -> Double {
        let r = NLLanguageRecognizer()
        r.languageConstraints = languages.map { NLLanguage(rawValue: $0) }
        r.processString(text)
        return r.languageHypotheses(withMaximum: languages.count)[NLLanguage(rawValue: language)] ?? 0
    }
}
#endif

/// "Zaten hedef dilde mi?" denetimi: PS5'in Türkçe menüleri boşa çevrilmesin.
public struct TargetLanguageCheck: Sendable {
    public let guesser: LanguageGuesser
    public let threshold: Double

    public init(guesser: LanguageGuesser, threshold: Double = 0.90) {
        self.guesser = guesser
        self.threshold = threshold
    }

    static let turkishOnly: Set<Character> = ["ı", "İ", "ğ", "Ğ", "ş", "Ş"]
    static let turkishLetters: Set<Character> = ["ğ", "ı", "ş", "ç", "ö", "ü", "Ğ", "İ", "Ş", "Ç", "Ö", "Ü"]

    /// Çeviriden önce: metin zaten hedef dilde mi?
    public func isAlreadyTarget(_ text: String, target: String, source: String = "en") -> Bool {
        let t = TargetLanguage.normalize(target)
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let longWords = words.filter { $0.filter(\.isLetter).count >= 2 }

        if t == "tr" {
            let marked = words.filter { $0.contains(where: Self.turkishOnly.contains) }
            if !marked.isEmpty {
                // OCR tuş simgesini harf sanıp tek sözcüğe yapıştırmış olabilir.
                if marked.count == 1 {
                    let rest = longWords.filter { $0 != marked[0] }
                    if rest.count >= 3,
                       guesser.probability(rest.joined(separator: " "), is: source, among: [t, source]) >= threshold {
                        return false
                    }
                }
                return true
            }
        }
        if t == "ar" || t == "ur", text.unicodeScalars.contains(where: TargetLanguage.isArabicScalar) { return true }
        if let range = Self.scriptRange[t], text.unicodeScalars.contains(where: { range.contains($0.value) }) { return true }
        if longWords.count >= 3, guesser.probability(text, is: t, among: [t, source]) >= threshold { return true }
        return false
    }

    static let scriptRange: [String: ClosedRange<UInt32>] = [
        "th": 0x0E00...0x0E7F, "hi": 0x0900...0x097F, "bn": 0x0980...0x09FF,
    ]

    /// Çeviri kaynakla neredeyse aynı mı (≥ 0.90)? Yankı denetimi de bunu kullanır.
    public static func isEcho(source: String, translation: String, threshold: Double = 0.90) -> Bool {
        TextSimilarity.ratio(source, translation) >= threshold
    }

    /// Çeviriden sonra: gösterilmemeli mi? Paketten gelen ve kaynağında Türkçe
    /// harf olmayan satır (isim, ünlem) aynı olsa da gösterilir.
    public static func shouldHide(source: String, translation: String, fromPack: Bool) -> Bool {
        if fromPack, !source.contains(where: turkishLetters.contains) { return false }
        return isEcho(source: source, translation: translation)
    }
}
