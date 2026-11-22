// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Oyun adlarını karşılaştırma ve oyun kimliği üretme kuralları.
public enum GameName {
    static let maxKeyLength = 80
    static let maxIDLength = 64

    private static let roman: [String: String] = [
        "ii": "2", "iii": "3", "iv": "4", "v": "5", "vi": "6", "vii": "7", "viii": "8", "ix": "9",
        "x": "10", "xi": "11", "xii": "12", "xiii": "13", "xiv": "14", "xv": "15", "xvi": "16",
    ]

    private static let abbreviations: [(String, String)] = [
        ("grand theft auto", "gta"),
        ("call of duty", "cod"),
        ("red dead redemption", "rdr"),
        ("ea sports fc", "fc"),
        ("ea sports", ""),
    ]

    /// Adları karşılaştırmak için anahtar: `Grand Theft Auto VI` → `gta 6`.
    public static func key(_ name: String) -> String {
        var s = name
        for mark in ["™", "®", "©"] { s = s.replacingOccurrences(of: mark, with: " ") }
        s = s.decomposedStringWithCompatibilityMapping.lowercased()
        var cleaned = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark: continue
            default: break
            }
            switch scalar {
            case "'", "’", "`": continue
            case "ı": cleaned.append("i")
            case "&": cleaned.append(contentsOf: " and ".unicodeScalars)
            default:
                cleaned.append(LineKey.isLetterOrNumber(scalar.properties.generalCategory) ? scalar : " ")
            }
        }
        // Harf ile rakam arasına boşluk.
        var spaced = String.UnicodeScalarView()
        var previous: Unicode.Scalar?
        for scalar in cleaned {
            if let p = previous, p != " ", scalar != " ", isDigit(p) != isDigit(scalar) { spaced.append(" ") }
            spaced.append(scalar)
            previous = scalar
        }
        var words = String(spaced).split(separator: " ").map { roman[String($0)] ?? String($0) }
        if words.count > 1, words.first == "the" { words.removeFirst() }
        var joined = " " + words.joined(separator: " ") + " "
        for (long, short) in abbreviations {
            joined = joined.replacingOccurrences(of: " \(long) ", with: short.isEmpty ? " " : " \(short) ")
        }
        let result = joined.split(separator: " ").joined(separator: " ")
        return String(result.prefix(maxKeyLength))
    }

    /// Havuzda kullanılan oyun kimliği: `Mafia: The Old Country` → `mafia-the-old-country`.
    /// Boş kalırsa `nil`.
    public static func id(_ name: String) -> String? {
        var out = ""
        for ch in name.lowercased().unicodeScalars {
            let ok = ch.isASCII && (("a"..."z").contains(ch) || ("0"..."9").contains(ch) || ch == "." || ch == "_" || ch == "-")
            let c: Character = ok ? Character(ch) : "-"
            if c == "-", out.last == "-" { continue }
            out.append(c)
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        let limited = String(trimmed.prefix(maxIDLength)).trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        return limited.isEmpty ? nil : limited
    }

    private static func isDigit(_ s: Unicode.Scalar) -> Bool {
        s.properties.generalCategory == .decimalNumber
    }
}
