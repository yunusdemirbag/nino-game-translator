// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Model yanıt metninden çeviri listesini çıkarır. Sayı tutmazsa `nil`.
public enum AIResponseParser {
    public static func parse(_ raw: String, expected: Int) -> [String]? {
        guard expected > 0 else { return [] }
        var text = raw
        if let r = text.range(of: "</think>", options: .backwards) { text = String(text[r.upperBound...]) }
        text = stripControlTokens(text)
        if text.contains("```") {
            text = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
                .joined(separator: "\n")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let open = text.firstIndex(of: "["), let close = text.lastIndex(of: "]"), open < close {
            var slice = String(text[open...close])
            slice = slice.replacingOccurrences(of: #",\s*\]$"#, with: "]", options: .regularExpression)
            if let arr = ProviderJSON.object(Data(slice.utf8)) as? [Any] {
                let items = arr.map { ($0 as? String ?? "\($0)").trimmingCharacters(in: .whitespacesAndNewlines) }
                return items.count == expected ? items : nil
            }
            if text.hasPrefix("["), text.hasSuffix("]"), let items = unquotedArray(String(text.dropFirst().dropLast()), expected) {
                return items
            }
        }
        if expected > 1 {
            let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return lines.count == expected ? lines : nil
        }
        let single = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”")).trimmingCharacters(in: .whitespacesAndNewlines)
        return single.isEmpty ? nil : [single]
    }

    /// `<s>`, `</s>`, `<|…|>`, `<start_of_turn>`, `<end_of_turn>`, `<eos>`, `<bos>`, `<pad>`.
    static func stripControlTokens(_ s: String) -> String {
        s.replacingOccurrences(of: #"</?(?:s|start_of_turn|end_of_turn|eos|bos|pad)>|<\|/?[A-Za-z0-9_]{1,32}\|>"#,
                               with: "", options: .regularExpression)
    }

    /// Tırnaksız dizi: satır sonu → cümle sonundan sonraki virgül → düz virgül.
    static func unquotedArray(_ inner: String, _ expected: Int) -> [String]? {
        let attempts: [[String]] = [
            inner.components(separatedBy: "\n"),
            splitAfterSentenceEnd(inner),
            inner.components(separatedBy: ","),
        ]
        for parts in attempts {
            let items = parts.map { $0.trimmingCharacters(in: .whitespaces) }
            if items.count == expected, !items.contains(where: \.isEmpty) { return items }
        }
        return nil
    }

    static func splitAfterSentenceEnd(_ s: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var prev: Character?
        for c in s {
            if c == ",", let p = prev, ".!?…\"”".contains(p) {
                parts.append(current)
                current = ""
            } else {
                current.append(c)
            }
            if !c.isWhitespace { prev = c }
        }
        parts.append(current)
        return parts
    }
}
