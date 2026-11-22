// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Kütüphanedeki bir paket: eski biçim ya da yeni `.ninopack.json`.
public enum LibraryPack: Sendable {
    case legacy(LegacyPack)
    case modern(TranslationPack)

    public var id: String {
        switch self {
        case let .legacy(p): return p.id
        case let .modern(p): return p.game.id
        }
    }

    public var title: String {
        switch self {
        case let .legacy(p): return p.title
        case let .modern(p): return p.game.title ?? p.game.id
        }
    }

    public var lineCount: Int {
        switch self {
        case let .legacy(p): return p.lineCount
        case let .modern(p): return p.lines.count
        }
    }

    public var isLegacy: Bool { if case .legacy = self { return true } else { return false } }

    /// Yalnız tam eşleme.
    public func exact(_ sentence: String) -> String? {
        switch self {
        case let .legacy(p): return p.exact(sentence)
        case let .modern(p):
            guard let line = p.match(sentence),
                  TranslationKey.make(line.source) == TranslationKey.make(sentence) else { return nil }
            return line.target
        }
    }

    /// Tam, sonra bulanık eşleme.
    public func lookup(_ sentence: String) -> String? {
        switch self {
        case let .legacy(p): return p.exact(sentence) ?? p.fuzzyMatch(sentence)
        case let .modern(p): return p.lookup(sentence)
        }
    }
}

/// Birden çok klasördeki eski ve yeni paketleri birlikte gören kütüphane.
/// Klasörler sırayla okunur; aynı kimlik sonra gelirse öncekinin yerine geçer.
public struct LegacyLibrary: Sendable {
    public struct Info: Equatable, Sendable {
        public let id: String
        public let title: String
        public let lineCount: Int
        /// İlk klasörden (uygulamayla gelen) mi?
        public let bundled: Bool
        public let legacy: Bool
    }

    public struct Failure: Equatable, Sendable {
        public let file: String
        public let reason: String
    }

    /// Bir tam eşleşme: Türkçe ve anahtarın bulunduğu paketler.
    public struct Hit: Sendable {
        public let text: String
        public let packIndex: Int
        /// Anahtarın geçtiği bütün eski paketler (sırayla).
        public let packs: [Int]
    }

    /// Genel havuz paketi; elle seçimde hiç seçilmez.
    public static let generalPackID = "pool-genel"

    public private(set) var packs: [LibraryPack] = []
    public private(set) var infos: [Info] = []
    public private(set) var failures: [Failure] = []
    private var merged: [UInt64: (text: String, pack: Int)] = [:]
    private var owners: [UInt64: [Int]] = [:]

    public init(packs: [LibraryPack] = []) {
        for p in packs { add(p, bundled: false) }
        rebuild()
    }

    /// Klasörleri sırayla okur (önce uygulamayla gelen, sonra kullanıcı klasörü).
    public init(directories: [URL], fileManager: FileManager = .default) {
        for (n, dir) in directories.enumerated() {
            let files = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = url.lastPathComponent
                guard !name.hasPrefix(".") else { continue }
                do {
                    if name.hasSuffix("." + TranslationPack.fileExtension) {
                        add(.modern(try TranslationPack(contentsOf: url)), bundled: n == 0)
                    } else if LegacyPack.isPackFile(url) {
                        add(.legacy(try LegacyPack(contentsOf: url)), bundled: n == 0)
                    }
                } catch {
                    failures.append(Failure(file: name, reason: String(describing: error)))
                }
            }
        }
        rebuild()
    }

    private mutating func add(_ pack: LibraryPack, bundled: Bool) {
        let info = Info(id: pack.id, title: pack.title, lineCount: pack.lineCount, bundled: bundled, legacy: pack.isLegacy)
        if let i = packs.firstIndex(where: { $0.id == pack.id }) {
            packs[i] = pack
            infos[i] = info
        } else {
            packs.append(pack)
            infos.append(info)
        }
    }

    /// Önce bütün parçalar, sonra bütün tam satırlar; aynı anahtarda sonraki kazanır.
    private mutating func rebuild() {
        merged = [:]
        var multi: [UInt64: Set<Int>] = [:]
        for pass in 0..<2 {
            for (i, pack) in packs.enumerated() {
                guard case let .legacy(p) = pack else { continue }
                for (k, v) in pass == 0 ? p.segments : p.entries {
                    if let previous = merged.updateValue((v, i), forKey: k), previous.pack != i {
                        multi[k, default: [previous.pack]].insert(i)
                    }
                }
            }
        }
        owners = multi.mapValues { $0.sorted() }
    }

    public var gameIDs: [String] { packs.map(\.id) }

    public func index(of id: String) -> Int? { packs.firstIndex { $0.id == id } }

    public func pack(for id: String) -> LibraryPack? { index(of: id).map { packs[$0] } }

    /// Seçilen ada (oyun adı anahtarıyla) eşit son paket; genel paket hariç.
    public func index(forGameNamed name: String) -> Int? {
        let key = GameName.key(name)
        guard !key.isEmpty else { return nil }
        return packs.indices.last { i in
            packs[i].id != Self.generalPackID
                && (GameName.key(packs[i].id) == key || GameName.key(packs[i].title) == key)
        }
    }

    /// Bütün paketlerde tam eşleme: önce birleşik eski sözlük, sonra yeni paketler.
    public func exact(_ sentence: String) -> Hit? {
        if let key = LineKey.key(sentence), let m = merged[key] {
            return Hit(text: m.text, packIndex: m.pack, packs: owners[key] ?? [m.pack])
        }
        for (i, p) in packs.enumerated() where !p.isLegacy {
            if let t = p.exact(sentence) { return Hit(text: t, packIndex: i, packs: [i]) }
        }
        return nil
    }
}

/// Hangi oyunun paketinde aranacağını tutan durum: kapsam, ayırt edici isabet, seçili oyun.
public struct PackScope: Sendable {
    public enum Kind: Equatable, Sendable { case exact, fuzzy }

    public struct Match: Equatable, Sendable {
        public let text: String
        public let packID: String
        public let legacy: Bool
        public let kind: Kind
    }

    /// Son tam eşleşmenin paketi.
    public private(set) var scope: Int?
    /// Elle seçilen oyunun adı (yoksa `nil`).
    public private(set) var selectedGame: String?
    private var distinctive: Int?

    public init() {}

    /// Kullanıcı oyunu seçti ya da seçimi kaldırdı; kapsam sıfırlanır.
    public mutating func select(game: String?) {
        let trimmed = game?.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedGame = (trimmed?.isEmpty ?? true) ? nil : trimmed
        scope = nil
        distinctive = nil
    }

    /// Ayırt edici isabetin paket kimliği; okununca silinir (oyun tanıma kullanır).
    public mutating func takeDistinctiveHit(in library: LegacyLibrary) -> String? {
        defer { distinctive = nil }
        return distinctive.flatMap { $0 < library.packs.count ? library.packs[$0].id : nil }
    }

    public func scopeID(in library: LegacyLibrary) -> String? {
        scope.flatMap { $0 < library.packs.count ? library.packs[$0].id : nil }
    }

    public mutating func lookup(_ sentence: String, in library: LegacyLibrary) -> Match? {
        if let selectedGame {
            // Seçili oyun: yalnız onun paketi; paketi yoksa hiç aranmaz.
            guard let i = library.index(forGameNamed: selectedGame) else { return nil }
            let pack = library.packs[i]
            if let t = pack.exact(sentence) { return Match(text: t, packID: pack.id, legacy: pack.isLegacy, kind: .exact) }
            if let t = pack.lookup(sentence) { return Match(text: t, packID: pack.id, legacy: pack.isLegacy, kind: .fuzzy) }
            return nil
        }
        if let hit = library.exact(sentence) {
            if hit.packs.count == 1 {
                scope = hit.packIndex
                distinctive = hit.packIndex
            } else if scope.map({ !hit.packs.contains($0) }) ?? true {
                scope = hit.packs.first
            }
            let pack = library.packs[hit.packIndex]
            return Match(text: hit.text, packID: pack.id, legacy: pack.isLegacy, kind: .exact)
        }
        guard let s = scope, s < library.packs.count else { return nil }
        let pack = library.packs[s]
        let fuzzy: String?
        switch pack {
        case let .legacy(p): fuzzy = p.fuzzyMatch(sentence)
        case let .modern(p): fuzzy = p.lookup(sentence)
        }
        return fuzzy.map { Match(text: $0, packID: pack.id, legacy: pack.isLegacy, kind: .fuzzy) }
    }
}
