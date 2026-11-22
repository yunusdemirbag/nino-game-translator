// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Sözlük terimi. `keep` için Türkçesi İngilizcesiyle aynıdır.
public struct GlossaryTerm: Equatable, Hashable, Sendable {
    public let english: String
    public let turkish: String
    /// Yalnız aynı büyük/küçük harfle geçince eşleşir (`Soul` ad, `soul` ruh).
    public let exact: Bool

    public init(english: String, turkish: String, exact: Bool = false) {
        self.english = english
        self.turkish = turkish
        self.exact = exact
    }

    var key: String { exact ? english + "\u{3}" : english.lowercased() }
}

/// Metinde bulunan terim.
public struct GlossaryMatch: Equatable, Sendable {
    public let range: Range<String.Index>
    public let term: GlossaryTerm
}

/// en→tr sözlüğü: terimler, korunanlar, argo kuralları, hazır satırlar.
public struct Glossary: Equatable, Sendable {
    public private(set) var game: String?
    public private(set) var terms: [String: GlossaryTerm] = [:]
    public private(set) var phrases: [String: String] = [:]
    public private(set) var lines: [String: String] = [:]

    public init() {}

    public var isEmpty: Bool { terms.isEmpty && phrases.isEmpty && lines.isEmpty }

    // MARK: Okuma

    /// JSON ya da yorumlu/sondaki virgüllü JSON. Bozuksa `nil`.
    public static func parse(_ data: Data) -> Glossary? {
        let cleaned = Data(relaxedJSON(String(decoding: data, as: UTF8.self)).utf8)
        guard let root = ProviderJSON.object(cleaned) as? [String: Any] else { return nil }
        var g = Glossary()
        g.game = root["game"] as? String
        if let t = root["terms"] as? [String: Any] {
            for (en, tr) in t { if let tr = tr as? String { g.addTerm(en, tr) } }
        }
        for en in root["keep"] as? [Any] ?? [] { if let en = en as? String { g.addTerm(en, en) } }
        for en in root["keepExact"] as? [Any] ?? [] { if let en = en as? String { g.addTerm(en, en, exact: true) } }
        if let p = root["phrases"] as? [String: Any] {
            for (k, v) in p {
                guard let v = v as? String, (try? NSRegularExpression(pattern: k)) != nil else { continue }
                g.phrases[k] = v
            }
        }
        if let l = root["lines"] as? [String: Any] {
            for (k, v) in l {
                guard let v = v as? String else { continue }
                let key = lineKey(k)
                let tr = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty, !tr.isEmpty { g.lines[key] = tr }
            }
        }
        return g
    }

    /// Terim ekler; kurala uymayan terim alınmaz.
    public mutating func addTerm(_ english: String, _ turkish: String, exact: Bool = false) {
        let en = english.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let tr = turkish.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard en.contains(where: \.isLetter), !tr.isEmpty, en.utf16.count <= 80 else { return }
        let term = GlossaryTerm(english: en, turkish: tr, exact: exact)
        terms[term.key] = term
    }

    /// Üstüne yazar: aynı terimde `other` kazanır.
    public func merged(with other: Glossary) -> Glossary {
        var g = self
        g.game = other.game ?? game
        g.terms.merge(other.terms) { $1 }
        g.phrases.merge(other.phrases) { $1 }
        g.lines.merge(other.lines) { $1 }
        return g
    }

    // MARK: Eşleşme

    /// Uzun terim önce, çakışan kısa terim alınmaz; aynı uzunlukta alfabetik.
    public func matches(in text: String) -> [GlossaryMatch] {
        let ordered = terms.values.sorted {
            let a = $0.english.utf16.count, b = $1.english.utf16.count
            return a != b ? a > b : $0.english < $1.english
        }
        var found: [GlossaryMatch] = []
        for term in ordered {
            var start = text.startIndex
            let options: String.CompareOptions = term.exact ? [] : [.caseInsensitive]
            while start < text.endIndex, let r = text.range(of: term.english, options: options, range: start..<text.endIndex) {
                if Self.isWordBoundary(text, r), !found.contains(where: { $0.range.overlaps(r) }) {
                    found.append(GlossaryMatch(range: r, term: term))
                }
                start = r.upperBound
            }
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    public func containsTerm(_ text: String) -> Bool { !matches(in: text).isEmpty }

    static func isWordBoundary(_ s: String, _ r: Range<String.Index>) -> Bool {
        if r.lowerBound > s.startIndex {
            let c = s[s.index(before: r.lowerBound)]
            if c.isLetter || c.isNumber { return false }
        }
        if r.upperBound < s.endIndex {
            let c = s[r.upperBound]
            if c.isLetter || c.isNumber { return false }
        }
        return true
    }

    /// Argo kurallarını anahtar bayt sırasıyla uygular.
    public func applyPhrases(_ text: String) -> String {
        var s = text
        for key in phrases.keys.sorted(by: Self.byteOrder) {
            guard let re = try? NSRegularExpression(pattern: #"\b(?:"# + key + #")\b"#, options: [.caseInsensitive]) else { continue }
            s = GameIdioms.replace(re, in: s, with: phrases[key]!)
        }
        return s
    }

    /// Argo kuralı bu metne uyuyor mu?
    public func hasPhrase(in text: String) -> Bool { applyPhrases(text) != text }

    /// Hazır satır. Türkçesi noktalamasızsa kaynağın son `. ! ? …` dizisi eklenir.
    public func readyLine(for sentence: String) -> String? {
        guard let tr = lines[Self.lineKey(sentence)] else { return nil }
        if let last = tr.last, ".!?…".contains(last) { return tr }
        let src = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = src.reversed().prefix { ".!?…".contains($0) }
        return tr + String(tail.reversed())
    }

    /// Satır anahtarı: küçük harf, `’ ‘` → `'`, tek boşluk, baştaki/sondaki harf-rakam dışı atılır.
    public static func lineKey(_ text: String) -> String {
        var s = text.lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
        s = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let isWord: (Character) -> Bool = { $0.isLetter || $0.isNumber }
        guard let first = s.firstIndex(where: isWord), let last = s.lastIndex(where: isWord) else { return "" }
        return String(s[first...last])
    }

    /// Büyük harfle yazılmış terimlerin (≥ 2 harfli) sözcükleri: cümle düzeninde büyük kalır.
    public var capitalizedWords: Set<String> {
        var out = Set<String>()
        for t in terms.values where !t.exact {
            for w in t.english.split(separator: " ") where w.filter(\.isLetter).count >= 2 {
                if let f = w.first, f.isUppercase { out.insert(String(w)) }
            }
        }
        return out
    }

    // MARK: İz

    /// FNV-1a 32 bit iz: `g` + 8 hex. Boş sözlük `g811c9dc5`.
    public var fingerprint: String {
        var h: UInt32 = 2_166_136_261
        func feed(_ s: String) {
            for b in s.utf8 { h ^= UInt32(b); h = h &* 16_777_619 }
        }
        let sortedTerms = terms.values.sorted {
            let a = $0.english.lowercased(), b = $1.english.lowercased()
            return a != b ? Self.byteOrder(a, b) : (!$0.exact && $1.exact)
        }
        for t in sortedTerms {
            feed(t.english.lowercased() + "\u{1}" + t.turkish + (t.exact ? "\u{3}" : "") + "\u{2}")
        }
        for k in phrases.keys.sorted(by: Self.byteOrder) { feed(k + "\u{4}" + phrases[k]! + "\u{5}") }
        for k in lines.keys.sorted(by: Self.byteOrder) { feed(k + "\u{6}" + lines[k]! + "\u{7}") }
        return "g" + String(format: "%08x", h)
    }

    static func byteOrder(_ a: String, _ b: String) -> Bool {
        Array(a.utf8).lexicographicallyPrecedes(Array(b.utf8))
    }

    /// `//`, `/* */` yorumlarını ve `}`/`]` öncesi virgülü siler (dizgi içine dokunmaz).
    static func relaxedJSON(_ s: String) -> String {
        var out: [Character] = []
        let c = Array(s)
        var i = 0
        var inString = false
        while i < c.count {
            let ch = c[i]
            if inString {
                out.append(ch)
                if ch == "\\", i + 1 < c.count { out.append(c[i + 1]); i += 2; continue }
                if ch == "\"" { inString = false }
                i += 1
                continue
            }
            if ch == "\"" { inString = true; out.append(ch); i += 1; continue }
            if ch == "/", i + 1 < c.count, c[i + 1] == "/" {
                while i < c.count, c[i] != "\n" { i += 1 }
                continue
            }
            if ch == "/", i + 1 < c.count, c[i + 1] == "*" {
                i += 2
                while i + 1 < c.count, !(c[i] == "*" && c[i + 1] == "/") { i += 1 }
                i += 2
                continue
            }
            if ch == "}" || ch == "]" {
                while let last = out.last, last.isWhitespace { out.removeLast() }
                if out.last == "," { out.removeLast() }
            }
            out.append(ch)
            i += 1
        }
        return String(out)
    }
}

/// Uygulamayla gelen sözlük + kullanıcı klasörü (`*.json`, ad sırasıyla üstüne).
/// Klasöre en çok `interval` saniyede bir bakılır; dosyalar değiştiyse yeniden okunur.
public actor GlossaryFolder {
    public let directory: URL?
    public let interval: TimeInterval
    private let base: Glossary
    private let now: @Sendable () -> Date
    private var lastCheck: Date = .distantPast
    private var signature: [String] = []
    private var cached: Glossary

    public init(directory: URL?, base: Glossary = BuiltinGlossary.enTr, interval: TimeInterval = 5,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.base = base
        self.interval = interval
        self.now = now
        self.cached = base
    }

    public func current() -> Glossary {
        let t = now()
        guard t.timeIntervalSince(lastCheck) >= interval else { return cached }
        lastCheck = t
        let files = listFiles()
        let sig = files.map { f -> String in
            let v = try? f.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return "\(f.path)|\(v?.fileSize ?? -1)|\(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }
        guard sig != signature else { return cached }
        signature = sig
        var g = base
        for f in files {
            guard let data = try? Data(contentsOf: f), let user = Glossary.parse(data) else { continue }
            g = g.merged(with: user)
        }
        cached = g
        return g
    }

    private func listFiles() -> [URL] {
        guard let directory,
              let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return items.filter { $0.pathExtension.lowercased() == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
