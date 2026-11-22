// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Asker/oyun kalıplarını çeviriden önce düz İngilizceye çevirir (her hedefte).
public enum GameIdioms {
    public static let rules: [(phrase: String, plain: String)] = [
        ("hit the deck", "lie flat"),
        ("haul tail", "run fast"),
        ("we're toast", "we are finished"),
        ("waste 'em", "kill them"),
        ("go loud", "start shooting"),
        ("radio silence", "no talking"),
        ("out of juice", "out of power"),
        ("hold the fort", "defend this place"),
        ("bought the farm", "died"),
    ]

    private static let compiled: [(NSRegularExpression, String)] = rules.compactMap { rule in
        let escaped = NSRegularExpression.escapedPattern(for: rule.phrase).replacingOccurrences(of: "'", with: "['’]")
        guard let re = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}])"# + escaped + #"(?![\p{L}\p{N}])"#,
                                                options: [.caseInsensitive]) else { return nil }
        return (re, rule.plain)
    }

    public static func apply(_ text: String) -> String {
        var s = text
        for (re, plain) in compiled { s = replace(re, in: s, with: plain) }
        return s
    }

    /// Eşleşmenin ilk harfi büyükse karşılığın ilk harfi de büyür.
    static func replace(_ re: NSRegularExpression, in text: String, with plain: String) -> String {
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let found = ns.substring(with: m.range)
            out += matchCase(found, plain)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    static func matchCase(_ found: String, _ replacement: String) -> String {
        guard let f = found.first(where: \.isLetter), f.isUppercase, let r = replacement.first else { return replacement }
        return String(r).uppercased() + replacement.dropFirst()
    }
}
