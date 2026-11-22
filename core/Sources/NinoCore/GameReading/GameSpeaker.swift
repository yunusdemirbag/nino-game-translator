// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Konuşan adı, çevirmene giden parçalar ve büyük harf düzeltme (tarif §10).
extension GameReading {
    public enum Speaker {
        /// Tek sözcüklü ad olamayacak başlıklar.
        public static let titleWords: Set<String> = [
            // oyun arayüzündeki bölüm başlıkları
            "objective", "objectives", "goal", "mission", "quest", "task", "chapter", "level", "location",
            "tip", "hint", "tutorial", "note", "warning", "info", "status", "update", "controls", "new",
            "reward", "rewards", "bonus", "score", "unlocked", "completed", "failed",
            // tuş komutları
            "press", "hold", "tap", "use",
            // cümle başında iki noktadan önce gelebilen sıradan sözcükler
            "look", "listen", "wait", "remember", "okay", "ok", "well", "yes", "no", "now", "then", "so", "and", "but",
            "question", "answer", "result", "results", "example", "time",
        ]

        static let nameRegex = try! NSRegularExpression(
            pattern: #"^((?:\p{Lu}[\p{L}'’.\-]*)(?: \p{Lu}[\p{L}'’.\-]*){0,2}) ?[:：]\s*([\s\S]*)$"#)

        /// `AD: gövde` ayırır (§10.1). Ad yoksa `nil`.
        public static func split(_ text: String) -> (name: String, body: String)? {
            let ns = text as NSString
            guard let m = nameRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
            let name = ns.substring(with: m.range(at: 1))
            let body = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count <= 24, !name.contains(where: \.isNumber) else { return nil }
            if !name.contains(" "), titleWords.contains(name.lowercased()) { return nil }
            guard body.contains(where: \.isLetter), !body.hasPrefix("/") else { return nil }
            return (name, body)
        }

        /// Çeviriyi gösterime hazırlar: ayar açıksa ad başa eklenir, kapalıysa atılır.
        public static func compose(translation: String, source: String, showNames: Bool) -> String {
            let sourceLines = Text.lines(source)
            let names = sourceLines.compactMap { split($0)?.name }
            if showNames {
                guard let name = split(source)?.name ?? names.first else { return translation }
                return translation.hasPrefix(name) ? translation : "\(name): \(translation)"
            }
            guard !names.isEmpty else { return translation }
            let known = Set(names)
            return Text.lines(translation).map { l in
                if let s = split(l), known.contains(s.name) { return s.body }
                return l
            }.joined(separator: "\n")
        }

        // MARK: Parçalar (§10.2)

        public struct Part: Equatable, Sendable {
            public var text: String
            /// Çevrilecek mi? Etiket, tire ve ayraçlar olduğu gibi kalır.
            public var translate: Bool
            public init(_ text: String, translate: Bool) { self.text = text; self.translate = translate }
        }

        static let labelRegex = try! NSRegularExpression(
            pattern: #"^((?:[\p{Lu}0-9][\p{Lu}0-9'’.\-]*)(?: [\p{Lu}0-9][\p{Lu}0-9'’.\-]*){0,2}|(?:\p{Lu}[\p{L}'’.\-]*)(?: \p{Lu}[\p{L}'’.\-]*){0,2}): "#)

        static func label(_ line: String) -> String? {
            let ns = line as NSString
            guard let m = labelRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
            let name = ns.substring(with: m.range(at: 1))
            if !name.contains(" "), titleWords.contains(name.lowercased()) { return nil }
            guard name.contains(where: \.isLetter) else { return nil }
            return ns.substring(with: m.range)
        }

        /// Cümle bölücünün kısaltmaları ve rütbe kısaltmaları (`Sgt.` gibi, ardından ad gelir).
        public static let abbreviations: Set<String> = SentenceSplitter.defaultAbbreviations
            .union(["lt", "sgt", "capt", "maj", "col", "gen", "cpl", "mt"])

        /// Çevirmene giden parçalar.
        public static func parts(_ text: String) -> [Part] {
            var speeches: [(prefix: String?, body: String)] = []
            for raw in text.split(separator: "\n") {
                let l = raw.trimmingCharacters(in: .whitespaces)
                guard !l.isEmpty else { continue }
                if let lab = label(l) {
                    speeches.append((lab, String(l.dropFirst(lab.count))))
                } else if let f = l.first, "-–—".contains(f) {
                    let rest = l.dropFirst().drop(while: \.isWhitespace)
                    speeches.append((String(l.prefix(l.count - rest.count)), String(rest)))
                } else if !speeches.isEmpty {
                    speeches[speeches.count - 1].body += " " + l
                } else {
                    speeches.append((nil, l))
                }
            }
            var out: [Part] = []
            for (i, s) in speeches.enumerated() {
                if i > 0 { out.append(Part("\n", translate: false)) }
                if let p = s.prefix { out.append(Part(p, translate: false)) }
                for (j, sentence) in sentences(s.body).enumerated() {
                    if j > 0 { out.append(Part(" ", translate: false)) }
                    out.append(Part(sentence, translate: true))
                }
            }
            return out
        }

        static func sentences(_ text: String) -> [String] {
            let chars = Array(text)
            var result: [String] = []
            var start = 0, i = 0
            while i < chars.count {
                guard Text.enders.contains(chars[i]) else { i += 1; continue }
                let runStart = i
                while i < chars.count, Text.enders.contains(chars[i]) { i += 1 }
                while i < chars.count, Text.closers.contains(chars[i]) { i += 1 }
                let end = i
                guard end < chars.count, chars[end].isWhitespace else { continue }
                var next = end
                while next < chars.count, chars[next].isWhitespace { next += 1 }
                guard next < chars.count, !chars[next].isLowercase else { continue }
                if chars[runStart] == ".", end - runStart == 1 {
                    var s = runStart
                    while s > 0, !chars[s - 1].isWhitespace { s -= 1 }
                    let word = String(chars[s..<runStart]).drop { !$0.isLetter }
                    if abbreviations.contains(word.lowercased()) || (word.count == 1 && word.first!.isUppercase) { continue }
                }
                let piece = String(chars[start..<end]).trimmingCharacters(in: .whitespaces)
                if !piece.isEmpty { result.append(piece) }
                start = end
            }
            let tail = String(chars[start...]).trimmingCharacters(in: .whitespaces)
            if !tail.isEmpty { result.append(tail) }
            return result
        }

        // MARK: Büyük harf düzeltme

        /// Etiketlerden öğrenilen adlar (her ≥ 2 harfli sözcük ayrı, küçük harfle).
        public static func names(fromLabelsIn text: String) -> Set<String> {
            var out: Set<String> = []
            for l in Text.lines(text) {
                guard let s = split(l) else { continue }
                for w in s.name.split(separator: " ") where w.filter(\.isLetter).count >= 2 {
                    out.insert(w.lowercased().trimmingCharacters(in: CharacterSet.letters.inverted))
                }
            }
            return out
        }

        /// Küçük harfi olmayan, en az 2 harfli, boşluklu cümleyi cümle düzenine çevirir.
        public static func fixCapitals(_ text: String, knownNames: Set<String> = []) -> String {
            guard !Text.hasLowercase(text), Text.letterCount(text) >= 2, text.contains(" ") else { return text }
            var out = ""
            var sentenceStart = true
            for token in text.lowercased().split(separator: " ", omittingEmptySubsequences: false) {
                var w = String(token)
                let core = w.trimmingCharacters(in: CharacterSet.letters.inverted)
                let isI = core == "i" || core.hasPrefix("i'") || core.hasPrefix("i’")
                if sentenceStart || isI || knownNames.contains(core) {
                    if let idx = w.firstIndex(where: \.isLetter) { w.replaceSubrange(idx...idx, with: String(w[idx]).uppercased()) }
                }
                if w.contains(where: \.isLetter) { sentenceStart = false }
                if Text.endsSentence(w) { sentenceStart = true }
                out += (out.isEmpty ? "" : " ") + w
            }
            return out
        }
    }
}

// MARK: - Öğrenilen altyazı yeri (§9)

extension GameReading {
    public struct Placement: Equatable, Sendable, Codable {
        public struct Sample: Equatable, Sendable, Codable {
            public var top: Double
            public var bottom: Double
            public init(top: Double, bottom: Double) { self.top = top; self.bottom = bottom }
        }

        public static let maxSamples = 60
        public private(set) var samples: [Sample] = []

        public init(samples: [Sample] = []) { self.samples = Array(samples.suffix(Self.maxSamples)) }

        /// Gösterilen altyazının kare kutusunu kaydeder. Kaydedildiyse `true`.
        @discardableResult
        public mutating func record(_ box: Box) -> Bool {
            guard box.bottom > box.top, box.top >= 0, box.bottom <= 1, box.bottom >= 0.80 else { return false }
            samples.append(Sample(top: box.top, bottom: box.bottom))
            if samples.count > Self.maxSamples { samples.removeFirst(samples.count - Self.maxSamples) }
            return true
        }

        /// Şerit: en az 8 örnek; üstlerin %10'luk, altların %90'lık dilimi.
        public var strip: (top: Double, bottom: Double)? {
            guard samples.count >= 8 else { return nil }
            return (Text.quantile(samples.map(\.top), 0.1)!, Text.quantile(samples.map(\.bottom), 0.9)!)
        }

        public var readTop: Double? { strip.map { $0.top - 0.05 } }

        /// Görev çizgisi; `nil` altyazı en dipte demektir.
        public var questLine: Double? {
            guard let s = strip else { return 0.895 }
            let h = Text.median(samples.map { $0.bottom - $0.top }) ?? 0
            let line = s.bottom + max(0.012, h)
            if line >= 0.97 { return nil }
            return max(line, s.top + 0.03, 0.895)
        }

        /// Taban çizgisi: en az 12 örnek, altların %70'i ortancaya 0,03'ten yakın.
        public var baseline: Double? {
            guard samples.count >= 12, let m = Text.median(samples.map(\.bottom)) else { return nil }
            let near = samples.filter { abs($0.bottom - m) < 0.03 }.count
            guard Double(near) >= 0.7 * Double(samples.count) else { return nil }
            return m - 0.07
        }

        /// Havuz öncelikli oyunda görev çizgisi en çok 0,935.
        public func questLine(poolPriority: Bool) -> Double? {
            poolPriority ? min(questLine ?? 0.935, 0.935) : questLine
        }

        /// Mac'te oyun anahtarı.
        public static func gameKey(poolPriority: Bool, packGame: String?) -> String {
            poolPriority ? "gta-6" : (packGame ?? "genel")
        }
    }

    /// Oyun başına öğrenilen yerler; JSON dosyasında.
    public final class PlacementStore: @unchecked Sendable {
        public let url: URL
        private let lock = NSLock()
        private var games: [String: Placement]

        public init(url: URL) {
            self.url = url
            if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([String: Placement].self, from: data) {
                games = decoded
            } else {
                games = [:]
            }
        }

        public func placement(for game: String) -> Placement {
            lock.lock(); defer { lock.unlock() }
            return stored(game) ?? Placement()
        }

        /// Kayıt; yoksa aynı oyunun takma adlı eski kaydı (`pool-gta-6`, `grand-theft-auto-vi` → `gta-6`). Kilit içinde.
        private func stored(_ game: String) -> Placement? {
            if let p = games[game] { return p }
            guard let id = GameIDs.id(game) else { return nil }
            return games.keys.sorted().first { GameIDs.id($0) == id }.flatMap { games[$0] }
        }

        /// Kaydeder ve diske yazar. Şerit ilk kez öğrenildiyse `true`.
        @discardableResult
        public func record(_ box: Box, game: String) -> Bool {
            lock.lock()
            var p = stored(game) ?? Placement()
            let hadStrip = p.strip != nil
            guard p.record(box) else { lock.unlock(); return false }
            games[game] = p
            let snapshot = games
            lock.unlock()
            save(snapshot)
            return !hadStrip && p.strip != nil
        }

        private func save(_ snapshot: [String: Placement]) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
