// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CryptoKit
import Foundation

/// Eski paketlerin ve ortak havuzun satır anahtarı: sadeleştirilmiş metnin
/// SHA-256 özetinin ilk 8 baytı. Sunucu ve öbür platformlarla birebir aynı.
public enum LineKey {
    /// Biçim etiketinin içindeki en çok kod noktası.
    static let maxTagLength = 40

    /// Sadeleştirme: etiketler boşluk, NFKC, küçük harf, NFD + aksan atma,
    /// harf/rakam dışı ayraç, tek boşluk.
    public static func canon(_ text: String) -> String {
        let untagged = replacingTags(in: text, with: " ")
        let folded = untagged.precomposedStringWithCompatibilityMapping
            .lowercased()
            .decomposedStringWithCanonicalMapping
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in folded.unicodeScalars {
            let category = scalar.properties.generalCategory
            // Sunucu (`nino-pool/src/key.js`) bütün işaretleri (`\p{M}`: Mn, Mc, Me) atar; aynısı.
            if category == .nonspacingMark || category == .spacingMark || category == .enclosingMark { continue }
            if isLetterOrNumber(category) {
                if pendingSpace, !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(scalar)
            } else {
                pendingSpace = true
            }
        }
        return String(out)
    }

    /// Satırın anahtarı; metinde harf/rakam yoksa `nil`.
    public static func key(_ text: String) -> UInt64? {
        let c = canon(text)
        return c.isEmpty ? nil : hash(canon: c)
    }

    /// Zaten sadeleştirilmiş metnin anahtarı.
    public static func hash(canon: String) -> UInt64 {
        let digest = SHA256.hash(data: Data(canon.utf8))
        var value: UInt64 = 0
        for byte in digest.prefix(8) { value = value << 8 | UInt64(byte) }
        return value
    }

    /// 16 haneli küçük hex.
    public static func hex(_ key: UInt64) -> String {
        let s = String(key, radix: 16)
        return String(repeating: "0", count: 16 - s.count) + s
    }

    /// 16 haneli hex (büyük/küçük harf fark etmez); değilse `nil`.
    public static func parse(_ hex: String) -> UInt64? {
        guard hex.utf8.count == 16, hex.utf8.allSatisfy({ isHexDigit($0) }) else { return nil }
        return UInt64(hex, radix: 16)
    }

    // MARK: Yardımcılar

    static func isLetterOrNumber(_ c: Unicode.GeneralCategory) -> Bool {
        switch c {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    private static func isHexDigit(_ b: UInt8) -> Bool {
        (48...57).contains(b) || (65...70).contains(b) || (97...102).contains(b)
    }

    /// `<…>` biçim etiketlerini (içinde `<`/`>` yok, en çok 40 kod noktası) değiştirir.
    static func replacingTags(in text: String, with replacement: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        while i < scalars.count {
            if scalars[i] == "<" {
                var j = i + 1
                while j < scalars.count, j - i - 1 <= maxTagLength, scalars[j] != "<", scalars[j] != ">" { j += 1 }
                if j < scalars.count, scalars[j] == ">", j - i - 1 <= maxTagLength {
                    out.append(contentsOf: replacement.unicodeScalars)
                    i = j + 1
                    continue
                }
            }
            out.append(scalars[i])
            i += 1
        }
        return String(out)
    }
}
