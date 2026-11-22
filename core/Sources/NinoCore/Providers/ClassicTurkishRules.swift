// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Eski Türkçe son düzeltme kuralları (cihaz içi çeviri, hedef `tr`). NinoCore'un
/// `TurkishPostProcessor`'ından farklıdır; farklar `docs/tarif/cevirmenler.md`'de.
/// Yalnız anlamı değiştirmeyen biçim kuralları.
public struct ClassicTurkishRules: Sendable {
    public init() {}

    static let tr = Locale(identifier: "tr_TR")
    static let closers: Set<Character> = ["\"", "'", "”", "’", "»", ")", "]"]
    static let enders: Set<Character> = [".", "!", "?", "…"]

    /// Tek cümleyi düzeltir.
    public func polish(_ translation: String, source: String) -> String {
        guard translation.contains(where: \.isLetter) else { return translation }
        var s = fixQuotes(translation, source: source)
        s = removeSpaceBeforePunctuation(s)
        s = s.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fixEnding(s, source: source)
    }

    // MARK: 1. Tırnaklar

    func fixQuotes(_ s: String, source: String) -> String {
        var out = s
        if source.contains("“") || source.contains("”") {
            out = curl(out, straight: "\"", open: "“", close: "”")
        } else {
            out = String(out.map { "“”„‟".contains($0) ? "\"" : $0 })
        }
        if source.contains("‘") || source.contains("’") {
            out = curl(out, straight: "'", open: "‘", close: "’")
        } else {
            out = String(out.map { "‘’‚‛".contains($0) ? "'" : $0 })
        }
        return out
    }

    func curl(_ s: String, straight: Character, open: Character, close: Character) -> String {
        var out = ""
        var prev: Character?
        for c in s {
            if c == straight {
                let opening = prev == nil || prev!.isWhitespace || "([-–—".contains(prev!)
                out.append(opening ? open : close)
            } else {
                out.append(c)
            }
            prev = c
        }
        return out
    }

    // MARK: 2. Noktalamadan önceki boşluk

    func removeSpaceBeforePunctuation(_ s: String) -> String {
        var out: [Character] = []
        for c in s {
            if ",.!?;:…".contains(c) {
                while let l = out.last, l == " " || l == "\t" { out.removeLast() }
            }
            out.append(c)
        }
        return String(out)
    }

    // MARK: 4. Son işaret

    func fixEnding(_ s: String, source: String) -> String {
        let (srcCore, srcClose) = Self.splitCloser(source.trimmingCharacters(in: .whitespacesAndNewlines))
        let srcMarks = Self.trailingMarks(srcCore)
        let expressive = srcMarks.contains("!") || srcMarks.contains("?") || srcMarks.contains("…") || srcMarks.contains("...")
        guard expressive else { return s }
        let (core, close) = Self.splitCloser(s)
        // Son işaret kaynakta tırnak içinde, çeviride dışında (ya da tersi): dokunma.
        guard srcClose.isEmpty == close.isEmpty else { return s }
        let marks = Self.trailingMarks(core)
        guard marks != srcMarks else { return s }
        return String(core.dropLast(marks.count)) + srcMarks + close
    }

    static func splitCloser(_ s: String) -> (String, String) {
        let tail = s.reversed().prefix { closers.contains($0) }
        return (String(s.dropLast(tail.count)), String(tail.reversed()))
    }

    static func trailingMarks(_ s: String) -> String {
        String(s.reversed().prefix { enders.contains($0) }.reversed())
    }

    // MARK: 8.3 Hitap

    static let senWords: Set<String> = ["sen", "seni", "sana", "senin", "sende", "senden", "seninle", "senle"]
    static let sizWords: Set<String> = ["siz", "sizi", "size", "sizin", "sizde", "sizden", "sizinle", "sizler"]
    /// "siz"li emir → "sen"li emir. (`alın` bilerek yok.)
    static let imperatives: [(String, String)] = [
        ("dikkat edin", "dikkat et"), ("acele edin", "acele et"), ("ateş edin", "ateş et"),
        ("yardım edin", "yardım et"), ("takip edin", "takip et"), ("sessiz olun", "sessiz ol"),
        ("hazır olun", "hazır ol"), ("sakin olun", "sakin ol"), ("bekleyin", "bekle"), ("durun", "dur"),
        ("gelin", "gel"), ("koşun", "koş"), ("gidin", "git"), ("bakın", "bak"), ("dinleyin", "dinle"),
        ("saklanın", "saklan"), ("kaçın", "kaç"), ("savaşın", "savaş"), ("dövüşün", "dövüş"),
        ("durdurun", "durdur"), ("çekilin", "çekil"), ("eğilin", "eğil"), ("atlayın", "atla"),
        ("tutun", "tut"), ("bırakın", "bırak"), ("söyleyin", "söyle"), ("gösterin", "göster"),
        ("getirin", "getir"), ("kalkın", "kalk"), ("odaklanın", "odaklan"), ("yaklaşın", "yaklaş"),
        ("uzaklaşın", "uzaklaş"),
    ]

    private static let imperativeRegexes: [(NSRegularExpression, String)] = imperatives.map { from, to in
        (try! NSRegularExpression(pattern: #"(?<!\p{L})"# + from + #"(?=[!.,?…]|$)"#, options: [.caseInsensitive]), to)
    }

    /// Satırın cümlelerinden birinde "sen" geçiyorsa, "siz" geçmeyen cümlelerdeki
    /// bilinen "siz"li emirler "sen"li olur.
    public func applyAddress(_ sentences: [String]) -> [String] {
        guard sentences.contains(where: { Self.hasWord($0, Self.senWords) }) else { return sentences }
        return sentences.map { sentence in
            guard !Self.hasWord(sentence, Self.sizWords) else { return sentence }
            var s = sentence
            for (re, to) in Self.imperativeRegexes {
                s = GameIdioms.replace(re, in: s, with: to)
            }
            return s
        }
    }

    static func hasWord(_ s: String, _ set: Set<String>) -> Bool {
        s.lowercased(with: tr).split(whereSeparator: { !$0.isLetter }).contains { set.contains(String($0)) }
    }
}
