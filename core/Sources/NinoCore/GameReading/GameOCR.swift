// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation

// MARK: - Simge metni düzeltme (§4.5)

extension GameReading {
    public enum IconText {
        /// Yan yana tekrarı teke inen simgeler.
        static let collapsible: Set<String> = [
            "✕", "×", "⨯", "✖", "○", "◯", "●", "□", "▢", "◻", "■", "△", "▲", "⨂", "✜", "▦", "◆",
            "L1", "L2", "L3", "R1", "R2", "R3", "OPTIONS", "TOUCHPAD",
        ]

        /// `13)` → `L3`, `(R3` → `R3`, `(C1` → `L1`; yan yana aynı simge teke iner.
        public static func fix(_ text: String) -> String {
            var out: [String] = []
            for word in Text.words(text) {
                let w = normalize(word)
                if let last = out.last, last == w, collapsible.contains(w) { continue }
                out.append(w)
            }
            return out.joined(separator: " ")
        }

        static func normalize(_ word: String) -> String {
            let open: Set<Character> = ["(", "["], close: Set<Character> = [")", "]"]
            var core = Substring(word)
            var bracket = false
            if let f = core.first, open.contains(f) { core = core.dropFirst(); bracket = true }
            if let l = core.last, close.contains(l) { core = core.dropLast(); bracket = true }
            let c = String(core)
            switch c {
            case "L3", "l3", "I3": return "L3"
            case "13": return bracket ? "L3" : word
            case "R3": return "R3"
            case "C1": return bracket ? "L1" : word
            default: return word
            }
        }
    }
}

// MARK: - OCR (§4.1–4.3)

extension GameReading {
    /// Satır parçaları arasındaki geniş boşluğa ne konacağı.
    public enum GapIcon: Sendable {
        /// Hiçbir şey (yalnız boşluk).
        case none
        /// Sabit yer tutucu (testler `●`).
        case placeholder(String)
        /// Görüntüden tanı.
        case recognizer(IconRecognizer)
    }

    public struct OCR: Sendable {
        public var reader: TextReader
        public var minConfidence: Float = 0.5
        public var gapIcon: GapIcon = .none

        public init(reader: TextReader, minConfidence: Float = 0.5, gapIcon: GapIcon = .none) {
            self.reader = reader; self.minConfidence = minConfidence; self.gapIcon = gapIcon
        }

        /// Alanı okur; satırlar alan içi kutulu, üstten sıralı.
        public func read(_ frame: Frame, area: Box, deep: Bool, scale: Double = 1) async throws -> [Line] {
            var raw = try await reader.read(frame, area: area, scale: scale)
            if raw.isEmpty, deep {
                // Ortadaki %40 şerit, sonra bütün alan; sırayla, 2 kat.
                let strip = Box(left: 0.30, top: 0, right: 0.70, bottom: 1)
                let stripLines = try await reader.read(frame, area: strip.mapped(into: area), scale: 2)
                if !stripLines.isEmpty {
                    raw = stripLines.map { Line($0.text, confidence: $0.confidence, box: $0.box?.mapped(into: strip)) }
                } else {
                    raw = try await reader.read(frame, area: area, scale: 2)
                }
            }
            let aspect = Double(frame.pixelWidth) * area.width / max(1, Double(frame.pixelHeight) * area.height)
            return clean(raw, aspect: aspect, frame: frame, area: area)
        }

        func clean(_ raw: [Line], aspect: Double, frame: Frame?, area: Box) -> [Line] {
            let kept = raw.compactMap { line -> Line? in
                guard line.confidence >= minConfidence else { return nil }
                let t = IconText.fix(line.text.trimmingCharacters(in: .whitespacesAndNewlines))
                return t.isEmpty ? nil : Line(t, confidence: line.confidence, box: line.box)
            }
            return Self.mergeFragments(kept, aspect: aspect) { gap in
                switch gapIcon {
                case .none: return nil
                case let .placeholder(s): return s
                case let .recognizer(r):
                    guard let frame else { return nil }
                    return r.icon(in: frame, box: gap.mapped(into: area), strict: false)
                }
            }
            .sorted { ($0.box?.top ?? 2) < ($1.box?.top ?? 2) }
        }

        /// Vision'ın simge yerinde böldüğü satır parçalarını birleştirir (§4.2).
        static func mergeFragments(_ lines: [Line], aspect: Double, icon: (Box) -> String?) -> [Line] {
            let boxed = lines.filter { $0.box != nil }.sorted { $0.box!.left < $1.box!.left }
            var rows: [(parts: [Line], box: Box)] = []
            for frag in boxed {
                let b = frag.box!
                var joined = false
                for i in rows.indices {
                    let last = rows[i].parts.last!.box!
                    let hMax = max(b.height, last.height), hMin = min(b.height, last.height)
                    guard hMin >= hMax / 2 else { continue }
                    guard abs(b.midY - last.midY) < 0.45 * hMax else { continue }
                    let gap = (b.left - rows[i].box.right) * aspect
                    guard gap > -0.01, gap < 4 * hMax else { continue }
                    // Tabela yazısı (`NO ALCOHOL`) yandaki konuşma satırına katılmaz.
                    guard !Filters.signBesideSentence(rows[i].parts.map(\.text).joined(separator: " "), frag.text) else { continue }
                    var add = frag
                    if gap > 0.9 * hMax {
                        let gapBox = Box(left: rows[i].box.right, top: min(b.top, last.top),
                                         right: b.left, bottom: max(b.bottom, last.bottom))
                        if let s = icon(gapBox) { add.text = s + " " + frag.text }
                    }
                    rows[i].parts.append(add)
                    rows[i].box = rows[i].box.union(b)
                    joined = true
                    break
                }
                if !joined { rows.append(([frag], b)) }
            }
            var out = rows.map { row -> Line in
                guard row.parts.count > 1 else { return row.parts[0] }
                let text = IconText.fix(row.parts.map(\.text).joined(separator: " "))
                return Line(text, confidence: row.parts.map(\.confidence).min() ?? 0, box: row.box)
            }
            out += lines.filter { $0.box == nil }
            return out
        }
    }
}

// MARK: - Vision okuyucusu

#if canImport(Vision)
extension GameReading {
    /// NinoCore'un `VisionTextRecognizer`'ını sarar: alanı keser, kesilen görüntünün
    /// tamamını okur; kutular alan içi orandır.
    public struct VisionTextReader: TextReader {
        public var languages: [String]
        public var usesLanguageCorrection: Bool
        public init(languages: [String] = ["en-US"], usesLanguageCorrection: Bool = true) {
            self.languages = languages; self.usesLanguageCorrection = usesLanguageCorrection
        }

        public func read(_ frame: Frame, area: Box, scale: Double) async throws -> [Line] {
            guard let image = frame.crop(area, scale: scale) else { return [] }
            let recognizer = VisionTextRecognizer(languages: languages, usesLanguageCorrection: usesLanguageCorrection)
            let lines = try await recognizer.recognize(image, in: NormalizedRect(x: 0, y: 0, width: 1, height: 1))
            return lines.map { Line($0.text, confidence: $0.confidence, box: Box($0.box)) }
        }
    }
}
#endif

// MARK: - Vision takılma bekçisi (§4.6)

extension GameReading {
    public enum WatchdogError: Error, Equatable {
        /// Sıra kalabalık; bu kare atlandı.
        case busy
        /// İşlemci kipinde bile okuma 45 sn'yi aştı; hat yeniden kurulmalı.
        case stuck
    }

    /// Okumalar tek sıradan geçer. Kapıyı tutan okuma takılırsa yedeğe, yoksa işlemciye geçer.
    public actor GuardedTextReader: TextReader {
        public enum Mode: Equatable, Sendable { case primary, fallback, cpuOnly }

        public struct Limits: Sendable {
            public var waitMs = 4_000
            public var busyMs = 8_000
            public var cpuExtraWaitMs = 1_000
            public var stuckMs = 45_000
            public var pollMs = 50
            public init() {}
        }

        /// Kapıyı tutan okuma ne kadardır sürüyor → ne yapılır.
        public enum Verdict: Equatable, Sendable { case busy, switchToFallback, switchToCPU, stuck }

        public static func verdict(holderElapsedMs e: Int, mode: Mode, hasFallback: Bool, limits: Limits = Limits()) -> Verdict {
            switch mode {
            case .primary, .fallback:
                if e < limits.busyMs { return .busy }
                return hasFallback && mode == .primary ? .switchToFallback : .switchToCPU
            case .cpuOnly:
                return e < limits.stuckMs ? .busy : .stuck
            }
        }

        public private(set) var mode: Mode = .primary
        private let primary: TextReader
        private let fallback: TextReader?
        private let cpu: TextReader
        private let clock: Clock
        private let sleep: @Sendable (Int) async -> Void
        private let limits: Limits
        private var holder: (id: Int, since: Int, mode: Mode)?
        private var nextID = 1
        /// Takılma bildirildi mi (köşe okuması görünce hattı yeniden kurar).
        public private(set) var stuckFlag = false

        public init(primary: TextReader, fallback: TextReader? = nil, cpu: TextReader? = nil,
                    clock: Clock, limits: Limits = Limits(),
                    sleep: @escaping @Sendable (Int) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0) * 1_000_000) }) {
            self.primary = primary; self.fallback = fallback; self.cpu = cpu ?? primary
            self.clock = clock; self.limits = limits; self.sleep = sleep
        }

        public func clearStuckFlag() { stuckFlag = false }

        public func read(_ frame: Frame, area: Box, scale: Double) async throws -> [Line] {
            if holder != nil {
                let wait = limits.waitMs + (mode == .cpuOnly ? limits.cpuExtraWaitMs : 0)
                let start = clock.nowMs
                while holder != nil, clock.nowMs - start < wait { await sleep(limits.pollMs) }
                if let h = holder {
                    switch Self.verdict(holderElapsedMs: clock.nowMs - h.since, mode: mode, hasFallback: fallback != nil, limits: limits) {
                    case .busy: throw WatchdogError.busy
                    case .switchToFallback: mode = .fallback; holder = nil
                    case .switchToCPU: mode = .cpuOnly; holder = nil
                    case .stuck: holder = nil; stuckFlag = true; throw WatchdogError.stuck
                    }
                }
            }
            let id = nextID
            nextID += 1
            let usedMode = mode
            holder = (id, clock.nowMs, usedMode)
            defer {
                if holder?.id == id { holder = nil }
            }
            let reader: TextReader = usedMode == .primary ? primary : (usedMode == .fallback ? (fallback ?? cpu) : cpu)
            let result = try await reader.read(frame, area: area, scale: scale)
            return result
        }

        /// Asıl okuyucu sonunda döndüyse yedekten asıla geçilir (uygulama çağırır).
        public func primaryRecovered() { if mode == .fallback { mode = .primary } }
    }
}
