// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// MARK: - Oyun işaretleri: elle yazılmış tarif + paketlerden çıkan adlar

extension GameReading {
    /// Ekranda birlikte görülünce oyunu kesin söyleyen sözcük kümesi (menü, HUD, harita imzası).
    public struct GameSignature: Equatable, Sendable {
        /// Aranacak ifadeler (büyük/küçük harf ve noktalama önemsiz).
        public var phrases: [String]
        /// En az kaç ifade görülmeli.
        public var need: Int
        /// Bu ifade(ler) mutlaka görülmeli (ör. `photo studio`); boşsa yok.
        public var required: [String]
        /// İfadenin satırı bu bölgede olmalı (kare oranı; satırın kutusu yoksa yer bakılmaz).
        public var area: Box?

        public init(_ phrases: [String], need: Int, required: [String] = [], area: Box? = nil) {
            self.phrases = phrases
            self.need = need
            self.required = required
            self.area = area
        }
    }

    /// Bir oyunun elle yazılmış işaretleri.
    public struct GameRecipe: Equatable, Sendable {
        /// Havuz/paket kimliği (`gta-6`).
        public var id: String
        public var name: String
        public var signatures: [GameSignature]
        /// Oyuna özgü adlar (karakter, yer, uygulama). İki farklısı görülünce oyun tanınır.
        public var names: [String]

        public init(id: String, name: String, signatures: [GameSignature] = [], names: [String] = []) {
            self.id = id
            self.name = name
            self.signatures = signatures
            self.names = names
        }
    }

    /// Elle yazılmış tarif (oyun kimliği → işaretler). Yeni oyun buraya eklenir; paketli oyunların adları
    /// ayrıca paketlerden çıkarılır (`GameMarkers.packNames`).
    public enum GameRecipes {
        public static let gta6 = GameRecipe(
            id: "gta-6", name: ScreenGame.gta6,
            signatures: [
                // Duraklatma menüsü: sağ üstte CHAPTER n, altında görev seçenekleri; solda Photo Studio.
                GameSignature(["chapter", "retry checkpoint", "restart mission", "quit mission", "photo studio", "store",
                               "help", "settings"], need: 4, required: ["photo studio"]),
                // Harita/menü üst şeridi.
                GameSignature(["jason and lucia", "jason lucia", "brief", "progress", "map"], need: 3,
                              required: ["brief", "progress"], area: Box(left: 0, top: 0, right: 1, bottom: 0.15)),
                GameSignature(["jason and lucia"], need: 1, area: Box(left: 0, top: 0, right: 1, bottom: 0.15)),
                // Harita tuşları + bu haritanın yer adları.
                GameSignature(["recenter", "2d view", "add marker", "set destination", "port gellhorn", "vice city",
                               "leonida", "belville", "draper island", "emerald springs"], need: 4,
                              required: ["2d view"]),
            ],
            names: ["jason", "lucia", "leonida", "vice city", "port gellhorn", "whatup", "buckme", "grassrivers",
                    "ambrosia", "kelly county", "mount kalaga", "draper island", "emerald springs", "belville",
                    "rydeme", "vice city horn", "leonida journal", "cal hampton", "boobie ike", "brian heder"]
        )

        public static let all: [GameRecipe] = [gta6]
    }

    /// Ekranda okunan satırlardan oyun: tarif imzaları ve oyuna özgü adlar (tariften + paketlerden).
    public struct GameMarkers: Sendable {
        public struct Game: Equatable, Sendable {
            public var id: String
            public var name: String
            public var signatures: [GameSignature]
            /// Anahtar biçiminde adlar (`port gellhorn`).
            public var names: Set<String>
        }

        /// Kesin tanıma.
        public struct Verdict: Equatable, Sendable {
            public var id: String
            public var name: String
            /// Neyle tanındı (günlük için): imza ifadeleri ya da adlar.
            public var hits: [String]
            /// İmzayla (menü/HUD) mı tanındı; `false`: yalnız özel adlarla (başka oyuna geçmek için yetmez, doğrular).
            public var strong: Bool = true
        }

        public private(set) var games: [Game]

        /// Bir ad bu kadar pakette sık geçiyorsa ayırt edici değil.
        static let maxOwners = 1
        /// Paketten çıkan bir ad en az bu kadar satırda geçmeli.
        static let minCount = 4
        static let perPackLimit = 60

        public init(recipes: [GameRecipe] = GameRecipes.all, packNames: [(id: String, name: String, names: [String])] = []) {
            var list: [Game] = recipes.map {
                Game(id: $0.id, name: $0.name, signatures: $0.signatures, names: Set($0.names.map(Self.key).filter { !$0.isEmpty }))
            }
            for p in packNames {
                let names = Set(p.names.map(Self.key).filter { !$0.isEmpty })
                if let i = list.firstIndex(where: { $0.id == p.id || GameName.key($0.name) == GameName.key(p.name) }) {
                    list[i].names.formUnion(names)
                } else {
                    list.append(Game(id: p.id, name: p.name, signatures: [], names: names))
                }
            }
            games = list
        }

        /// Tarif + kütüphanedeki paketlerin ayırt edici adları.
        public init(recipes: [GameRecipe] = GameRecipes.all, library: LegacyLibrary) {
            self.init(recipes: recipes, packNames: Self.packNames(library))
        }

        // MARK: Paketlerden ad çıkarma

        /// Her paketin sık geçen ve yalnız o pakette sık geçen özel adları. Eski paketlerde İngilizce metin yok:
        /// Türkçe çevirideki büyük harfle başlayan (cümle başı olmayan) sözcükler kullanılır; adlar çeviride
        /// genelde değişmeden kalır. Yeni paketlerde İngilizce kaynak da sayılır.
        public static func packNames(_ library: LegacyLibrary) -> [(id: String, name: String, names: [String])] {
            var counts: [[String: Int]] = []
            for pack in library.packs {
                var c: [String: Int] = [:]
                guard pack.id != LegacyLibrary.generalPackID else { counts.append(c); continue }
                switch pack {
                case let .legacy(p):
                    for t in p.entries.values { for w in Set(capitalizedWords(t)) { c[w, default: 0] += 1 } }
                case let .modern(p):
                    for l in p.lines {
                        for w in Set(capitalizedWords(l.source) + capitalizedWords(l.target)) { c[w, default: 0] += 1 }
                    }
                }
                counts.append(c)
            }
            // Birden çok pakette sık geçen sözcük (Bay, Tanrı, Hey…) ayırt edici değil.
            var owners: [String: Int] = [:]
            for c in counts { for (w, n) in c where n >= 2 { owners[w, default: 0] += 1 } }
            var out: [(id: String, name: String, names: [String])] = []
            for (i, pack) in library.packs.enumerated() where pack.id != LegacyLibrary.generalPackID {
                let names = counts[i]
                    .filter { $0.value >= minCount && (owners[$0.key] ?? 0) <= maxOwners && !stopWords.contains($0.key) }
                    .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                    .prefix(perPackLimit).map(\.key)
                if !names.isEmpty { out.append((pack.id, pack.title, Array(names))) }
            }
            return out
        }

        /// Cümle başı olmayan, büyük harfle başlayan, en az 4 harfli sözcükler (küçük harfe çevrilmiş).
        static func capitalizedWords(_ text: String) -> [String] {
            var out: [String] = []
            var sentenceStart = true
            for raw in text.split(whereSeparator: { $0.isWhitespace }) {
                let word = raw.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
                defer {
                    if let last = raw.last, ".!?…:\"".contains(last) { sentenceStart = true }
                }
                guard !word.isEmpty else { continue }
                let wasStart = sentenceStart
                sentenceStart = false
                // İyelik/ek: "Lucia'nın" → "Lucia".
                let stem = word.split(whereSeparator: { $0 == "'" || $0 == "’" }).first.map(String.init) ?? word
                guard !wasStart, stem.count >= 4, stem.first?.isUppercase == true, stem.allSatisfy(\.isLetter),
                      stem.dropFirst().contains(where: \.isLowercase) else { continue }
                out.append(key(stem))
            }
            return out
        }

        /// Çok yaygın büyük harfli sözcükler (hitap, unvan, gün, ay, kurum).
        static let stopWords: Set<String> = [
            "bay", "bayan", "tanri", "allah", "efendim", "hanim", "mister", "miss", "god", "jesus", "hey", "tamam",
            "evet", "hayir", "pazartesi", "sali", "carsamba", "persembe", "cuma", "cumartesi", "pazar", "ocak", "subat",
            "mart", "nisan", "mayis", "haziran", "temmuz", "agustos", "eylul", "ekim", "kasim", "aralik", "amerika",
            "amerikan", "ingiliz", "ingilizce", "turkce", "noel", "polis", "doktor", "baba", "anne", "kaptan", "patron",
        ]

        // MARK: Karar

        static func key(_ text: String) -> String { GameName.key(text) }

        /// Satırların anahtarı (büyük/küçük harf, noktalama ve aksan önemsiz).
        static func lineKeys(_ lines: [Line]) -> [(key: String, box: Box?)] {
            lines.map { (" " + key(Corners.cleanMenuLine($0.text)) + " ", $0.box) }
        }

        /// İfade satırda geçiyor mu: tam sözcük olarak ya da (≥5 harfte) bir harf yanlışıyla.
        static func contains(_ line: String, _ phrase: String) -> Bool {
            if line.contains(" \(phrase) ") { return true }
            guard phrase.count >= 5 else { return false }
            let words = line.split(separator: " ").map(String.init)
            let n = phrase.split(separator: " ").count
            guard words.count >= n else { return false }
            for i in 0...(words.count - n) {
                let window = words[i..<(i + n)].joined(separator: " ")
                if abs(window.count - phrase.count) <= 1, TextSimilarity.ratio(window, phrase) >= 0.84 { return true }
            }
            return false
        }

        /// Kesin imza (tek karede): varsa ilk eşleşen oyun.
        public func signature(_ lines: [Line]) -> Verdict? {
            let keyed = Self.lineKeys(lines)
            for g in games {
                for s in g.signatures {
                    let found = s.phrases.filter { p in
                        let k = Self.key(p)
                        return keyed.contains { l in
                            if let area = s.area, let b = l.box, !area.contains(x: b.midX, y: (b.top + b.bottom) / 2) { return false }
                            return Self.contains(l.key, k)
                        }
                    }
                    let required = s.required.map(Self.key)
                    if found.count >= s.need, required.allSatisfy({ r in found.contains { Self.key($0) == r } }) {
                        return Verdict(id: g.id, name: g.name, hits: found)
                    }
                }
            }
            return nil
        }

        /// Satırlarda geçen oyuna özgü adlar: oyun kimliği → adlar.
        public func names(in lines: [Line]) -> [String: Set<String>] {
            let keyed = Self.lineKeys(lines)
            var out: [String: Set<String>] = [:]
            for g in games {
                for n in g.names where keyed.contains(where: { $0.key.contains(" \(n) ") }) {
                    out[g.id, default: []].insert(n)
                }
            }
            return out
        }

        public func game(id: String) -> Game? { games.first { $0.id == id } }
    }
}

// MARK: - İlk saniyelerde hızlı oyun tanıma

extension GameReading {
    /// İlk karenin gelişinden (Remote Play bağlanırken geçen süre sayılmaz) itibaren `windowMs` boyunca her karede (bir okuma sürerken gelen kareler atlanır) hafif bir
    /// okuma yapar ve oyunu imzadan ya da iki farklı özel addan tanır; sonra `laterGapMs` arayla sürer.
    /// Okuma ana okuma hattından ayrı (işlemcide, hızlı Vision) yapılır.
    public final class QuickGameSense: @unchecked Sendable {
        public struct Options: Sendable {
            public var windowMs = 10_000
            public var laterGapMs = 5_000
            /// İki farklı adın birlikte sayılacağı süre.
            public var namesMemoryMs = 30_000
            /// Kesin tanıma için en az bu kadar farklı ad.
            public var namesNeeded = 2
            public init() {}
        }

        private let lock = NSLock()
        private var markers: GameMarkers
        private let reader: TextReader
        private let clock: Clock
        private let options: Options
        private var armed = false
        private var started: Int?
        private var busy = false
        private var lastRead: Int?
        private var stopped = false
        private var seen: [String: [String: Int]] = [:]

        public init(markers: GameMarkers = GameMarkers(), reader: TextReader, clock: Clock, options: Options = Options()) {
            self.markers = markers
            self.reader = reader
            self.clock = clock
            self.options = options
        }

        public func setMarkers(_ m: GameMarkers) { lock.withLock { markers = m } }

        /// Yeni oturum ya da yeniden bağlanma: pencere ilk karede başlar.
        public func start() {
            lock.withLock {
                armed = true
                started = nil
                busy = false
                lastRead = nil
                stopped = false
                seen = [:]
            }
        }

        /// Oyun başka yoldan kesinleşti ya da oturum bitti: okuma durur.
        public func stop() { lock.withLock { stopped = true } }

        public var isRunning: Bool { lock.withLock { armed && !stopped } }

        /// Bu karede okunmalı mı? `true` dönerse okuma başlamış sayılır (`read` mutlaka çağrılmalı).
        public func claim() -> Bool {
            lock.withLock {
                guard armed, !stopped, !busy else { return false }
                let now = clock.nowMs
                if started == nil { started = now }
                let started = started ?? now
                if now - started >= options.windowMs, let last = lastRead, now - last < options.laterGapMs { return false }
                busy = true
                lastRead = now
                return true
            }
        }

        /// `claim` sonrası: kareyi okur ve kesin tanırsa döndürür.
        public func read(_ frame: Frame) async -> GameMarkers.Verdict? {
            let lines = (try? await reader.read(frame, area: Box(left: 0, top: 0, right: 1, bottom: 1), scale: 1)) ?? []
            return lock.withLock {
                busy = false
                return judgeLocked(lines.filter { $0.confidence >= 0.3 })
            }
        }

        /// `claim` + `read`.
        public func observe(_ frame: Frame) async -> GameMarkers.Verdict? {
            guard claim() else { return nil }
            return await read(frame)
        }

        /// Başka yoldan okunan satırlar (altyazı, köşe): yalnız ad sayılır, imza da bakılır.
        public func observeLines(_ lines: [Line]) -> GameMarkers.Verdict? {
            lock.withLock { !armed || stopped ? nil : judgeLocked(lines) }
        }

        private func judgeLocked(_ lines: [Line]) -> GameMarkers.Verdict? {
            guard !lines.isEmpty else { return nil }
            if let v = markers.signature(lines) { return v }
            let now = clock.nowMs
            for (id, names) in markers.names(in: lines) {
                for n in names { seen[id, default: [:]][n] = now }
            }
            for id in seen.keys { seen[id] = seen[id]?.filter { now - $0.value <= options.namesMemoryMs } }
            let ranked = seen.map { (id: $0.key, n: $0.value.count) }.sorted { $0.n > $1.n }
            guard let best = ranked.first, best.n >= options.namesNeeded,
                  ranked.dropFirst().first.map({ $0.n < best.n }) ?? true,
                  let g = markers.game(id: best.id) else { return nil }
            return GameMarkers.Verdict(id: g.id, name: g.name, hits: (seen[best.id] ?? [:]).keys.sorted(), strong: false)
        }
    }
}

#if canImport(Vision)
import Vision

extension GameReading {
    /// Oyun tanıma için hafif okuma: hızlı Vision, dil düzeltmesi yok, işlemcide (altyazı hattı Neural Engine'de kalır).
    public struct QuickTextReader: TextReader {
        public init() {}

        public func read(_ frame: Frame, area: Box, scale: Double) async throws -> [Line] {
            guard let image = frame.crop(area, scale: scale) ?? frame.image else { return [] }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            if let stages = try? request.supportedComputeStageDevices {
                for (stage, devices) in stages {
                    if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                        request.setComputeDevice(cpu, for: stage)
                    }
                }
            }
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            return (request.results ?? []).compactMap { o in
                guard let best = o.topCandidates(1).first else { return nil }
                let b = o.boundingBox
                return Line(best.string, confidence: best.confidence,
                            box: Box(left: b.minX, top: 1 - b.maxY, right: b.maxX, bottom: 1 - b.minY))
            }
        }
    }
}
#endif
