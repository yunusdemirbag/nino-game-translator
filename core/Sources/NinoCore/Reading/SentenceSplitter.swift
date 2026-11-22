// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

/// Yazıyı cümlelere böler.
public struct SentenceSplitter: Sendable {
    public var abbreviations: Set<String>

    public static let defaultAbbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "st", "jr", "sr", "prof", "vs", "etc", "e.g", "i.e",
    ]

    private static let enders: Set<Character> = [".", "!", "?", "…"]
    private static let closers: Set<Character> = ["\"", "”", "'", "’", ")", "]"]

    public init(abbreviations: Set<String> = SentenceSplitter.defaultAbbreviations) {
        self.abbreviations = Set(abbreviations.map { $0.lowercased() })
    }

    public func split(_ text: String) -> [String] {
        let chars = Array(text)
        var sentences: [String] = []
        var start = 0
        var i = 0

        func cut(_ end: Int) {
            let piece = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { sentences.append(piece) }
            start = end
        }

        while i < chars.count {
            guard Self.enders.contains(chars[i]) else { i += 1; continue }
            let runStart = i
            while i < chars.count, Self.enders.contains(chars[i]) { i += 1 }
            let run = String(chars[runStart..<i])
            while i < chars.count, Self.closers.contains(chars[i]) { i += 1 }
            let end = i

            guard end < chars.count else { break }
            guard chars[end].isWhitespace else { continue }

            var next = end
            while next < chars.count, chars[next].isWhitespace { next += 1 }
            guard next < chars.count else { break }
            if chars[next].isLowercase { continue }
            if run == ".", isAbbreviation(before: runStart, in: chars) { continue }
            cut(end)
        }
        cut(chars.count)
        return sentences
    }

    private func isAbbreviation(before dot: Int, in chars: [Character]) -> Bool {
        var s = dot
        while s > 0, !chars[s - 1].isWhitespace { s -= 1 }
        let word = String(chars[s..<dot]).drop { !$0.isLetter }.lowercased()
        return abbreviations.contains(word)
    }
}
