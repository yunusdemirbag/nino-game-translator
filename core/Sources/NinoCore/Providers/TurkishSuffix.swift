// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Çevirmenin yer tutucu ada eklediği Türkçe eki gerçek terime göre yeniden kurar.
/// `Westport + da → Westport'ta`, `ateş oku + u → ateş okunu`, `dolap + u → dolabı`.
public enum TurkishSuffix {
    static let tr = Locale(identifier: "tr_TR")
    static let vowels: Set<Character> = ["a", "e", "ı", "i", "o", "ö", "u", "ü"]
    static let backVowels: Set<Character> = ["a", "ı", "o", "u"]
    static let rounded: Set<Character> = ["o", "ö", "u", "ü"]
    static let narrow: Set<Character> = ["ı", "i", "u", "ü"]
    static let hard: Set<Character> = ["f", "s", "t", "k", "ç", "ş", "h", "p"]

    public static func attach(_ term: String, suffix rawSuffix: String, apostrophe: Character = "'") -> String {
        guard !rawSuffix.isEmpty else { return term }
        guard rawSuffix.allSatisfy(\.isLetter), rawSuffix.count <= 12 else {
            return term + String(apostrophe) + rawSuffix
        }
        var s = Array(rawSuffix.lowercased(with: tr))

        // Yer tutucuya göre konmuş kaynaştırma harfi atılır.
        if s.count >= 2, s[0] == "y", vowels.contains(s[1]) || s[1] == "l" {
            s.removeFirst()
        } else if s.count >= 3, s[0] == "n", narrow.contains(s[1]), s[2] == "n" {
            s.removeFirst()
        }

        let words = term.lowercased(with: tr).split(separator: " ")
        let lastWord = Array(words.last ?? "")
        let letters = lastWord.filter(\.isLetter)
        let wordVowels = letters.filter { vowels.contains($0) }
        let vowelless = wordVowels.isEmpty
        let lastVowel: Character = wordVowels.last ?? "i"
        let lastLetter: Character = vowelless ? "i" : (letters.last ?? "i")
        let endsWithVowel = vowels.contains(lastLetter)
        let compound = words.count >= 2 && narrow.contains(lastLetter) && letters.count >= 3

        var buffer = ""
        if let first = s.first {
            if vowels.contains(first) {
                let genitive = s.count >= 2 && narrow.contains(s[0]) && s[1] == "n" && (s.count == 2 || String(s[2...]) == "ki")
                if compound || (endsWithVowel && genitive) {
                    buffer = "n"
                } else if endsWithVowel {
                    buffer = "y"
                }
            } else if first == "d" || first == "t" {
                if compound {
                    buffer = "n"
                    s[0] = "d"
                } else {
                    s[0] = hard.contains(lastLetter) ? "t" : "d"
                }
            } else if s.count >= 2, s[0] == "l", s[1] == "a" || s[1] == "e",
                      !(s.count >= 3 && s[2] == "r") {
                if endsWithVowel || compound { buffer = "y" }
            }
        }

        // Ünlü uyumu; sondaki "-ki" değişmez.
        let frozenTail = s.count > 2 && s.suffix(2) == ["k", "i"] ? 2 : 0
        var prev = lastVowel
        for i in 0..<(s.count - frozenTail) where vowels.contains(s[i]) {
            let back = backVowels.contains(prev), round = rounded.contains(prev)
            if s[i] == "a" || s[i] == "e" {
                s[i] = back ? "a" : "e"
            } else if narrow.contains(s[i]) {
                s[i] = back ? (round ? "u" : "ı") : (round ? "ü" : "i")
            }
            prev = s[i]
        }
        let ending = buffer + String(s)

        if let f = term.first(where: \.isLetter), f.isUppercase {
            return term + String(apostrophe) + ending
        }
        // Cins ad: bitişik; ünlüyle başlayan ekte son ünsüz yumuşar.
        var base = term
        if buffer.isEmpty, let first = s.first, vowels.contains(first) {
            if base.hasSuffix("nk") {
                base = String(base.dropLast()) + "g"
            } else if wordVowels.count > 1, let last = base.last {
                let soft: [Character: Character] = ["p": "b", "ç": "c", "k": "ğ"]
                if let r = soft[last] { base = String(base.dropLast()) + String(r) }
            }
        }
        return base + ending
    }
}
