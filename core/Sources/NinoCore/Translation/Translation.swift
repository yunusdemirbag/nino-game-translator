// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

/// Önbellek ve paket eşleştirmesinde kullanılan anahtar.
public enum TranslationKey {
    /// Küçük harf, kırpılmış, tek boşluk; kıvrık tırnak düz, `…` üç nokta. Noktalama korunur.
    public static func make(_ text: String) -> String {
        var s = ""
        s.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "“", "”", "„": s.append("\"")
            case "‘", "’", "‚": s.append("'")
            case "…": s.append("...")
            default: s.append(ch)
            }
        }
        return s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Bir çevirinin nereden geldiği.
public enum TranslationOrigin: Equatable, Sendable, Codable {
    case cache
    case pack
    case provider(String)
    case none
}

/// Tek bir cümlenin çevirisi.
public struct Translation: Equatable, Sendable {
    public let source: String
    public let text: String
    public let origin: TranslationOrigin

    public init(source: String, text: String, origin: TranslationOrigin) {
        self.source = source
        self.text = text
        self.origin = origin
    }

    /// Hiçbir kaynak çeviremedi mi?
    public var failed: Bool { origin == .none }
}
