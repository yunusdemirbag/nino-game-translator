// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Cihaz içi çeviride sözlük terimlerini uydurma özel adlarla korur. Çevirmen
/// özel adı bırakıp ekini ekler (`Torvek'i al`); dönüşte ek gerçek terime göre kurulur.
public struct NameShield: Sendable {
    public static let names = ["Torvek", "Mirdal", "Haskor", "Belmuk", "Ravdin", "Sorkel", "Gundar", "Vestar"]

    public struct Shielded: Equatable, Sendable {
        /// Adlarla değiştirilmiş cümle.
        public let text: String
        /// Adlarla değiştirilmiş bağlam (varsa).
        public let context: String?
        /// Bu cümlenin adları → Türkçe karşılık.
        public let own: [String: String]
        /// Yalnız bağlamda kullanılan adlar (çıktıda kalmamalı).
        public let foreign: [String]
        /// Kaynakta `’` varsa ekler de onunla yazılır.
        public let apostrophe: Character
    }

    public let glossary: Glossary

    public init(glossary: Glossary) { self.glossary = glossary }

    public func shield(_ sentence: String, context: String? = nil) -> Shielded {
        let all = sentence + "\n" + (context ?? "")
        var free = Self.names.filter { all.range(of: $0, options: .caseInsensitive) == nil }
        var assigned: [String: String] = [:]   // terim anahtarı → ad
        var turkishOf: [String: String] = [:]  // ad → Türkçe
        func replace(_ text: String, used: inout Set<String>) -> String {
            var out = text
            for m in glossary.matches(in: text).reversed() {
                let key = m.term.key
                let name: String
                if let n = assigned[key] {
                    name = n
                } else {
                    guard !free.isEmpty else { continue }
                    name = free.removeFirst()
                    assigned[key] = name
                    turkishOf[name] = m.term.turkish
                }
                used.insert(name)
                let lower = out.index(out.startIndex, offsetBy: text.distance(from: text.startIndex, to: m.range.lowerBound))
                let upper = out.index(lower, offsetBy: text.distance(from: m.range.lowerBound, to: m.range.upperBound))
                out.replaceSubrange(lower..<upper, with: name)
            }
            return out
        }
        // Eşleşmeler sağdan sola değiştirildiği için ad sırası soldan sağa olsun diye önce ad dağıtılır.
        for m in glossary.matches(in: sentence) where assigned[m.term.key] == nil && !free.isEmpty {
            let n = free.removeFirst(); assigned[m.term.key] = n; turkishOf[n] = m.term.turkish
        }
        var ownNames = Set<String>(), contextNames = Set<String>()
        let text = replace(sentence, used: &ownNames)
        let ctx = context.map { replace($0, used: &contextNames) }
        let own = turkishOf.filter { ownNames.contains($0.key) }
        let foreign = contextNames.subtracting(ownNames).sorted()
        let apostrophe: Character = sentence.contains("’") ? "’" : "'"
        return Shielded(text: text, context: ctx, own: own, foreign: foreign, apostrophe: apostrophe)
    }

    /// Adları terimlerle değiştirir. Beklenen ad yoksa ya da bağlamın adı kaldıysa `nil`.
    public func restore(_ output: String, _ shielded: Shielded) -> String? {
        for name in shielded.foreign where Self.regex(name).firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) != nil {
            return nil
        }
        var result = output
        for (name, turkish) in shielded.own {
            let re = Self.regex(name)
            let ns = result as NSString
            let matches = re.matches(in: result, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { return nil }
            var out = ""
            var last = 0
            for m in matches {
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                var suffix = ""
                for g in 1...2 where m.range(at: g).location != NSNotFound { suffix = ns.substring(with: m.range(at: g)) }
                var piece = TurkishSuffix.attach(turkish, suffix: suffix, apostrophe: shielded.apostrophe)
                if Self.atSentenceStart(ns.substring(to: m.range.location)), let f = piece.first {
                    piece = String(f).uppercased(with: TurkishSuffix.tr) + piece.dropFirst()
                }
                out += piece
                last = m.range.location + m.range.length
            }
            out += ns.substring(from: last)
            result = out
        }
        return result
    }

    static func regex(_ name: String) -> NSRegularExpression {
        // ad + ek: kesmeyle (boşluklu da olabilir) ya da bitişik.
        let p = #"(?<![\p{L}\p{N}])"# + name + #"(?:\s?['`´‘’](\p{L}+)|(\p{L}*))(?![\p{L}\p{N}])"#
        return try! NSRegularExpression(pattern: p, options: [.caseInsensitive])
    }

    static func atSentenceStart(_ before: String) -> Bool {
        for c in before.reversed() {
            if c.isWhitespace || "\"'“”‘’-–—(¡¿«".contains(c) { continue }
            return ".!?…".contains(c)
        }
        return true
    }
}
