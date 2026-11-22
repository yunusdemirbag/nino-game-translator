// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Oyuna özel hazır çeviri paketi. Değişmez; oluşturulunca dizinlenir.
public struct TranslationPack: PhraseLookup, Sendable {
    public struct Game: Codable, Equatable, Sendable {
        public var id: String
        public var title: String?
        public var version: String?

        public init(id: String, title: String? = nil, version: String? = nil) {
            self.id = id
            self.title = title
            self.version = version
        }
    }

    public struct Languages: Codable, Equatable, Sendable {
        public var source: String
        public var target: String

        public init(source: String = "en", target: String = "tr") {
            self.source = source
            self.target = target
        }
    }

    public struct Line: Codable, Equatable, Sendable {
        public var source: String
        public var target: String
        public var speaker: String?

        public init(source: String, target: String, speaker: String? = nil) {
            self.source = source
            self.target = target
            self.speaker = speaker
        }
    }

    public enum LoadError: Error, Equatable {
        case unsupportedVersion(Int)
        case badGameID(String)
        case invalidJSON(String)
    }

    public static let formatVersion = 1
    public static let fileExtension = "ninopack.json"
    public static let fuzzyMinLength = 12
    public static let fuzzyThreshold = 0.90

    public let game: Game
    public let languages: Languages
    public let terms: [Term]
    public let lines: [Line]
    /// Yükleme sırasında atlanan satır sayısı.
    public let warnings: Int

    private let exact: [String: Int]
    private let fuzzyKeys: [String]
    private let wordIndex: [String: [Int]]

    public init(game: Game, languages: Languages = Languages(), terms: [Term] = [], lines: [Line]) throws {
        guard Self.isValidGameID(game.id) else { throw LoadError.badGameID(game.id) }
        self.game = game
        self.languages = languages
        self.terms = terms

        var kept: [Line] = []
        var exact: [String: Int] = [:]
        var warnings = 0
        for line in lines {
            let s = line.source.trimmingCharacters(in: .whitespacesAndNewlines)
            let t = line.target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty, !t.isEmpty else { warnings += 1; continue }
            let key = TranslationKey.make(s)
            guard exact[key] == nil else { warnings += 1; continue }
            exact[key] = kept.count
            kept.append(Line(source: s, target: t, speaker: line.speaker))
        }
        self.lines = kept
        self.exact = exact
        self.warnings = warnings

        let keys = kept.map { TextSimilarity.key($0.source) }
        var index: [String: [Int]] = [:]
        for (i, k) in keys.enumerated() {
            for w in Set(k.split(separator: " ").map(String.init)) { index[w, default: []].append(i) }
        }
        self.fuzzyKeys = keys
        self.wordIndex = index
    }

    public static func isValidGameID(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy { c in
            ("a"..."z").contains(c) || ("0"..."9").contains(c) || c == "-" || c == "."
        }
    }

    // MARK: Eşleme

    public func lookup(_ sentence: String) -> String? {
        match(sentence)?.target
    }

    /// Cümleye karşılık gelen satır: önce tam, sonra bulanık eşleme.
    public func match(_ sentence: String) -> Line? {
        if let i = exact[TranslationKey.make(sentence)] { return lines[i] }
        return fuzzyMatch(sentence)
    }

    func fuzzyMatch(_ sentence: String) -> Line? {
        let key = TextSimilarity.key(sentence)
        guard key.count >= Self.fuzzyMinLength else { return nil }
        let words = Set(key.split(separator: " ").map(String.init))
        let isQuestion = Self.isQuestion(sentence)

        var shared: [Int: Int] = [:]
        for w in words { for i in wordIndex[w] ?? [] { shared[i, default: 0] += 1 } }

        var best: (index: Int, score: Double)?
        for (i, count) in shared.sorted(by: { $0.key < $1.key }) {
            let candidate = fuzzyKeys[i]
            let candidateWords = candidate.split(separator: " ").count
            guard count * 2 >= max(words.count, candidateWords) else { continue }
            let ratio = Double(candidate.count) / Double(key.count)
            guard ratio >= 0.8, ratio <= 1.25 else { continue }
            guard Self.isQuestion(lines[i].source) == isQuestion else { continue }
            let score = TextSimilarity.ratio(key, candidate)
            guard score >= Self.fuzzyThreshold else { continue }
            if best == nil || score > best!.score { best = (i, score) }
        }
        return best.map { lines[$0.index] }
    }

    private static func isQuestion(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'”’)]")))
            .hasSuffix("?")
    }

    // MARK: Dosya

    private struct File: Codable {
        var nino: Int
        var game: Game
        var languages: Languages?
        var terms: [Term]?
        var lines: [Line]
    }

    public init(data: Data) throws {
        let file: File
        do {
            // Önce yalnız sürümü oku, sonra tamamını.
            struct Head: Decodable { var nino: Int }
            let head = try JSONDecoder().decode(Head.self, from: data)
            guard head.nino == Self.formatVersion else { throw LoadError.unsupportedVersion(head.nino) }
            file = try JSONDecoder().decode(File.self, from: data)
        } catch let e as LoadError {
            throw e
        } catch {
            throw LoadError.invalidJSON(String(describing: error))
        }
        try self.init(game: file.game, languages: file.languages ?? Languages(), terms: file.terms ?? [], lines: file.lines)
    }

    public init(contentsOf url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(File(nino: Self.formatVersion, game: game, languages: languages, terms: terms, lines: lines))
    }

    public func write(to url: URL) throws {
        try encoded().write(to: url, options: .atomic)
    }
}

/// Klasördeki paketleri yükler ve oyun kimliğine göre verir.
public struct PackLibrary: Sendable {
    public struct Failure: Equatable, Sendable {
        public let file: String
        public let reason: String
    }

    public private(set) var packs: [String: TranslationPack] = [:]
    public private(set) var failures: [Failure] = []

    public init(packs: [TranslationPack] = []) {
        for p in packs { add(p) }
    }

    /// Klasördeki tüm `.ninopack.json` dosyalarını yükler. Klasör yoksa boş döner.
    public init(directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where url.lastPathComponent.hasSuffix("." + TranslationPack.fileExtension) {
            do {
                add(try TranslationPack(contentsOf: url))
            } catch {
                failures.append(Failure(file: url.lastPathComponent, reason: String(describing: error)))
            }
        }
    }

    public var gameIDs: [String] { packs.keys.sorted() }

    public func pack(for gameID: String) -> TranslationPack? { packs[gameID] }

    mutating func add(_ pack: TranslationPack) {
        if let existing = packs[pack.game.id],
           Self.compare(existing.game.version, pack.game.version) >= 0 { return }
        packs[pack.game.id] = pack
    }

    /// Nokta ile ayrılmış sürümleri sayı olarak karşılaştırır.
    static func compare(_ a: String?, _ b: String?) -> Int {
        let x = (a ?? "0").split(separator: ".").map { Int($0) ?? 0 }
        let y = (b ?? "0").split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }
}
