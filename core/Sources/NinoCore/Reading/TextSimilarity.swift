// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

/// İki yazının ne kadar benzediğini ölçer.
public enum TextSimilarity {
    /// Küçük harf, harf/rakam dışı her şey boşluk, boşluklar teke iner.
    public static func key(_ text: String) -> String {
        let mapped = text.lowercased().map { ($0.isLetter || $0.isNumber) ? $0 : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// `1 - düzenleme uzaklığı / uzun olanın boyu`. 0–1 arası.
    public static func ratio(_ a: String, _ b: String) -> Double {
        let x = Array(key(a)), y = Array(key(b))
        let longest = max(x.count, y.count)
        if longest == 0 { return 1 }
        return 1 - Double(levenshtein(x, y)) / Double(longest)
    }

    /// İki yazı "aynı altyazı" mı? Benzerlik eşiğe ulaşmalı; ama biri ötekinin
    /// uzantısıysa (yazı büyüyorsa) aynı sayılmaz.
    public static func isSame(_ a: String, _ b: String, threshold: Double) -> Bool {
        let x = key(a), y = key(b)
        if x != y, x.hasPrefix(y) || y.hasPrefix(x) { return false }
        return ratio(a, b) >= threshold
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
