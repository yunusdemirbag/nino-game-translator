// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

/// Oyun terimi: karakter, yer, eşya adı. `target` yoksa olduğu gibi korunur.
public struct Term: Equatable, Hashable, Sendable, Codable {
    public var source: String
    public var target: String?

    public init(_ source: String, _ target: String? = nil) {
        self.source = source
        self.target = target
    }

    public var replacement: String { target ?? source }
}

/// Terimleri çeviriden önce yer tutucuyla değiştirir, sonra geri koyar.
public struct TermProtector: Sendable {
    public struct Protected: Equatable, Sendable {
        /// Yer tutuculu metin.
        public let text: String
        /// Yer tutucu sırası → konacak metin.
        public let replacements: [String]
    }

    public let terms: [Term]

    public init(terms: [Term]) {
        // Aynı terimden bir tane; en uzun önce eşleşir.
        var seen = Set<String>()
        self.terms = terms
            .filter { !$0.source.trimmingCharacters(in: .whitespaces).isEmpty }
            .filter { seen.insert($0.source.lowercased()).inserted }
            .sorted { $0.source.count > $1.source.count }
    }

    public static func placeholder(_ i: Int) -> String { "⟦\(i)⟧" }

    public func protect(_ text: String) -> Protected {
        var result = text
        var replacements: [String] = []
        for term in terms {
            var searchStart = result.startIndex
            while let r = result.range(of: term.source, options: [.caseInsensitive], range: searchStart..<result.endIndex) {
                if isBoundary(result, r) {
                    let ph = Self.placeholder(replacements.count)
                    replacements.append(term.replacement)
                    result.replaceSubrange(r, with: ph)
                    searchStart = result.index(r.lowerBound, offsetBy: ph.count)
                } else {
                    searchStart = r.upperBound
                }
            }
        }
        return Protected(text: result, replacements: replacements)
    }

    /// Yer tutucuları geri koyar. Biri kaybolduysa `nil` döner.
    public func restore(_ translated: String, _ protected: Protected) -> String? {
        var result = ""
        var found = Set<Int>()
        var chars = Substring(translated)
        while let open = chars.firstIndex(of: "⟦") {
            result += chars[..<open]
            guard let close = chars[open...].firstIndex(of: "⟧") else {
                result += chars[open...]
                chars = ""
                break
            }
            let inner = chars[chars.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            if let i = Int(inner), i >= 0, i < protected.replacements.count {
                result += protected.replacements[i]
                found.insert(i)
            } else {
                result += chars[open...close]
            }
            chars = chars[chars.index(after: close)...]
        }
        result += chars
        return found.count == protected.replacements.count ? result : nil
    }

    private func isBoundary(_ s: String, _ r: Range<String.Index>) -> Bool {
        if r.lowerBound > s.startIndex {
            let before = s[s.index(before: r.lowerBound)]
            if before.isLetter || before.isNumber { return false }
        }
        if r.upperBound < s.endIndex {
            let after = s[r.upperBound]
            if after.isLetter || after.isNumber { return false }
        }
        return true
    }
}
