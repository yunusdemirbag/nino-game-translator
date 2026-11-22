// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Robot cevabının biçimi (ninoya-sor.md §3 "Robot balonu"): paragraflar, numaralı adımlar, maddeler.
public enum AssistantFormatting {
    public enum Block: Equatable, Sendable {
        case paragraph(String)
        /// `1.` ya da `1)` (en çok iki basamak).
        case step(number: String, text: String)
        /// `-`, `•` ya da `*`.
        case bullet(String)

        public var isListItem: Bool {
            switch self {
            case .paragraph: return false
            case .step, .bullet: return true
            }
        }
    }

    public static func parseBlocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            let indented = raw.first == " " || raw.first == "\t"
            if let step = parseStep(trimmed) {
                flushParagraph()
                blocks.append(.step(number: step.0, text: step.1))
            } else if let bullet = parseBullet(trimmed) {
                flushParagraph()
                blocks.append(.bullet(bullet))
            } else if indented, paragraph.isEmpty, let last = blocks.last, last.isListItem {
                // Bir adımın/maddenin altındaki girintili satır onun devamıdır.
                blocks[blocks.count - 1] = appending(trimmed, to: last)
            } else {
                paragraph.append(trimmed)
            }
        }
        flushParagraph()
        return blocks
    }

    static func appending(_ line: String, to block: Block) -> Block {
        switch block {
        case .step(let n, let t): return .step(number: n, text: t + "\n" + line)
        case .bullet(let t): return .bullet(t + "\n" + line)
        case .paragraph(let t): return .paragraph(t + "\n" + line)
        }
    }

    /// "1. Metin" / "12) Metin"; "2024. yılında" adım sayılmaz.
    static func parseStep(_ line: String) -> (String, String)? {
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard (1...2).contains(digits.count) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let mark = rest.first, mark == "." || mark == ")" else { return nil }
        let after = rest.dropFirst()
        guard let space = after.first, space == " " else { return nil }
        let text = after.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (String(digits), text)
    }

    static func parseBullet(_ line: String) -> String? {
        guard let first = line.first, ["-", "•", "*"].contains(first) else { return nil }
        let rest = line.dropFirst()
        guard rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    /// Bağlantılar tıklanabilir: `http(s)://` ve `www.`; sondaki noktalama dahil edilmez.
    public static func linkified(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let regex = try? NSRegularExpression(pattern: #"(https?://|www\.)[^\s<>"]+"#) else { return result }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var link = ns.substring(with: match.range)
            while let last = link.last, ".,;:!?)]}'\"".contains(last) { link.removeLast() }
            guard !link.isEmpty else { continue }
            let urlText = link.hasPrefix("www.") ? "https://" + link : link
            guard let url = URL(string: urlText),
                  let range = Range(NSRange(location: match.range.location, length: (link as NSString).length), in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].link = url
        }
        return result
    }
}
