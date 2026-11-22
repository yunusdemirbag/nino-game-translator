// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Çevirmenden gelen Türkçe metni toparlar.
public struct TurkishPostProcessor: Sendable {
    public init() {}

    private static let turkish = Locale(identifier: "tr_TR")
    private static let enders: Set<Character> = [".", "!", "?"]

    public func process(_ translated: String, source: String) -> String {
        var s = translated.replacingOccurrences(of: "…", with: "...")
        s = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")

        // Noktalamadan önceki boşluk.
        for p in [" ,", " .", " !", " ?", " ;", " :"] {
            while s.contains(p) { s = s.replacingOccurrences(of: p, with: String(p.dropFirst())) }
        }
        // Virgül ve noktalı virgülden sonra boşluk (harf geliyorsa).
        s = spaceAfter(s, [",", ";"])
        // ".." → "." ama "..." korunur; "...." → "...".
        s = fixDots(s)

        // Baş harf: kaynak büyük harfle başlıyorsa Türkçe kurala göre büyüt.
        if let first = source.first(where: \.isLetter), first.isUppercase,
           let idx = s.firstIndex(where: \.isLetter), s[idx].isLowercase {
            s.replaceSubrange(idx...idx, with: String(s[idx]).uppercased(with: Self.turkish))
        }

        // Son noktalama: kaynakta var, çeviride yoksa ekle.
        let src = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = s.last, !Self.enders.contains(last), !"\"'”’)]".contains(last) {
            if src.hasSuffix("...") || src.hasSuffix("…") {
                s += "..."
            } else if let end = src.last, Self.enders.contains(end) {
                s.append(end)
            }
        }
        return s
    }

    private func spaceAfter(_ s: String, _ marks: Set<Character>) -> String {
        var out = ""
        let chars = Array(s)
        for (i, c) in chars.enumerated() {
            out.append(c)
            if marks.contains(c), i + 1 < chars.count, chars[i + 1].isLetter { out.append(" ") }
        }
        return out
    }

    private func fixDots(_ s: String) -> String {
        var out = ""
        var run = 0
        func flush() {
            if run == 1 || run == 2 { out += "." } else if run >= 3 { out += "..." }
            run = 0
        }
        for c in s {
            if c == "." { run += 1 } else { flush(); out.append(c) }
        }
        flush()
        return out
    }
}
