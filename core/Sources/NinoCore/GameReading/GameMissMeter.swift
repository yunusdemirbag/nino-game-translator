// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// MARK: - Kaçırma ölçer (oyun-okuma.md "Kaçırma ölçer")

extension GameReading {
    /// Kayıttaki kareleri bastırma kuralları kapalı okuyup çıkan benzersiz diyalog satırlarını günlükteki "okundu"
    /// satırlarıyla karşılaştırır. Video çözme ve OCR çağıran taraftadır (Mac: `nino-debug kacan`); burada yalnız
    /// saf mantık var: satır toplama, diyalog tanımı, eşleştirme, rapor.
    public enum MissMeter {
        /// Bir diyalog satırı adayı (kayıtta görüldüğü aralık).
        public struct Candidate: Equatable, Sendable {
            public var text: String
            public var firstMs: Int
            public var lastMs: Int
            public var frames: Int
            /// `altyazı` ya da ekran öğesinin yeri (`sol üst`, `sağ alt`, `sağ`, `sol`, `üst`, `harita`).
            public var kind = "altyazı"
        }

        /// Günlükteki bir okuma (`#n okundu …`) ya da teşhis notu.
        public struct LogEntry: Equatable, Sendable {
            public var ms: Int
            public var text: String
            public init(ms: Int, text: String) { self.ms = ms; self.text = text }
        }

        /// Kaçan satır ve o sırada okumayı engelleyen nedenler.
        public struct Miss: Equatable, Sendable {
            public var candidate: Candidate
            /// Günlükteki teşhis notları (aynı aralıkta; yeni sürümlerde).
            public var loggedReasons: [String]
            /// Kurallar açık okuyucunun aynı karelerdeki notları (yeniden oynatma).
            public var replayReasons: [String]
        }

        public struct Report: Equatable, Sendable {
            public var dialogue: [Candidate] = []
            public var caught: [Candidate] = []
            public var misses: [Miss] = []
            public var rate: Double { dialogue.isEmpty ? 1 : Double(caught.count) / Double(dialogue.count) }
        }

        // MARK: Diyalog tanımı

        /// Kayıtçının karelere çizdiği kendi yazısı (alt şerit) ve okuma kutusu kırıntıları.
        public static func isOwnOverlay(_ text: String) -> Bool {
            let t = text.trimmingCharacters(in: .whitespaces).uppercased()
            return ["OKUNAN", "ÇEVİRİ", "CEVIRI", "ÇEVIRI", "CEVİRİ"].contains { t.hasPrefix($0) }
        }

        /// Diyalog satırı mı: harfli en az iki sözcük (ya da `OK.` gibi kısa cevap), küçük harf içerir (tamamı büyük
        /// harfli tabela/menü/HUD yazısı sayılmaz), ipucu ya da eşya etiketi değil, kutusu karenin ortasında ve
        /// alt şeritte. Kare oranında kutu.
        public static func isDialogue(_ text: String, box: Box?) -> Bool {
            let t = Filters.cleanJunk(text)
            guard !isOwnOverlay(t) else { return false }
            let short = Stabilizer.isShortAnswer(t)
            if !short {
                guard Filters.hasEnoughLetters(t), Text.words(t).filter({ $0.contains(where: \.isLetter) }).count >= 2,
                      Text.hasLowercase(t), !Filters.isHint(t), !Filters.isItemLabel(t) else { return false }
            }
            if let b = box {
                guard abs(b.midX - 0.5) <= 0.15, b.top >= 0.62 else { return false }
            }
            return true
        }

        // MARK: Toplama

        /// Kare kare okunan diyalog bloklarını benzersiz satırlara toplar. Aynı satır (benzerlik ≥ 0,8 ya da biri
        /// ötekini içeriyor) 3 sn içinde yeniden görülürse aynı adaydır; en uzun okunuşu tutulur.
        public struct Collector: Sendable {
            public private(set) var candidates: [Candidate] = []
            public var joinGapMs = 3_000
            public init() {}

            public mutating func add(_ text: String, at ms: Int, kind: String = "altyazı") {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                if let i = candidates.lastIndex(where: { $0.kind == kind && ms - $0.lastMs <= joinGapMs && MissMeter.same($0.text, t) }) {
                    candidates[i].lastMs = max(candidates[i].lastMs, ms)
                    candidates[i].frames += 1
                    if Text.key(t).count > Text.key(candidates[i].text).count { candidates[i].text = t }
                } else {
                    candidates.append(Candidate(text: t, firstMs: ms, lastMs: ms, frames: 1, kind: kind))
                }
            }
        }

        /// İki okuma aynı satır mı (bulanık).
        public static func same(_ a: String, _ b: String) -> Bool {
            // Sayılar (mesafe, para) değişse de aynı öğedir (`Turn Left 102 m` → `Turn Left 87 m`).
            let ka = Text.key(a).filter { !$0.isNumber }, kb = Text.key(b).filter { !$0.isNumber }
            guard !ka.isEmpty, !kb.isEmpty else { return false }
            if ka.contains(kb) || kb.contains(ka) { return min(ka.count, kb.count) >= 4 }
            return Text.ratio(ka, kb) >= 0.8
        }

        /// Aday, günlükteki okumada geçiyor mu: okuma birden çok satırsa (` / `) her parça ve bütünü denenir.
        public static func matches(_ candidate: String, read: String) -> Bool {
            let parts = read.components(separatedBy: " / ") + [read.replacingOccurrences(of: " / ", with: " ")]
            let kc = Text.key(candidate)
            for p in parts {
                let kp = Text.key(p)
                guard !kp.isEmpty else { continue }
                if kp.contains(kc) || (kc.contains(kp) && kp.count >= kc.count / 2) { return true }
                if Text.ratio(kc, kp) >= 0.7 { return true }
            }
            // Birden çok satırlık aday, tek satırlık okumaların bitişiği olabilir: adayın her satırı geçmeli.
            let lines = candidate.split(separator: "\n").map(String.init)
            if lines.count > 1 { return lines.allSatisfy { l in parts.contains { Text.ratio(Text.key(l), Text.key($0)) >= 0.7 || Text.key($0).contains(Text.key(l)) } } }
            return false
        }

        // MARK: Karşılaştırma

        /// `reads`: günlükteki okumalar; `notes`: günlükteki "atlandı/atıldı" satırları; `replayNotes`: kurallar açık
        /// yeniden oynatmanın notları. Pencere: aday görülmeden `beforeMs` önce – son görülmesinden `afterMs` sonra.
        public static func compare(_ candidates: [Candidate], reads: [LogEntry], notes: [LogEntry] = [],
                                   replayNotes: [LogEntry] = [], beforeMs: Int = 3_000, afterMs: Int = 4_000) -> Report {
            var r = Report()
            for c in candidates {
                r.dialogue.append(c)
                let window = (c.firstMs - beforeMs)...(c.lastMs + afterMs)
                if reads.contains(where: { window.contains($0.ms) && matches(c.text, read: $0.text) }) {
                    r.caught.append(c)
                    continue
                }
                let near = (c.firstMs - 1_000)...(c.lastMs + 1_000)
                func reasons(_ list: [LogEntry]) -> [String] {
                    var seen: [String] = []
                    for n in list where near.contains(n.ms) {
                        let label = n.text.components(separatedBy: " \"").first ?? n.text
                        if !seen.contains(label) { seen.append(label) }
                    }
                    return seen
                }
                r.misses.append(Miss(candidate: c, loggedReasons: reasons(notes), replayReasons: reasons(replayNotes)))
            }
            return r
        }

        // MARK: Günlük

        /// `altyazi.log` biçimindeki bir satırın iletisi: `#n okundu "…" → çeviriye`, `#n okundu (uzadı) "…"`,
        /// `#n yeniden okundu "…"` okuma; `atlandı:`/`atıldı:`/`geç okundu:` not. Diğerleri `nil`.
        public enum LogKind: Equatable, Sendable { case read(String), note(String), element(String) }

        public static func classify(_ message: String) -> LogKind? {
            // Ekran öğeleri (çevirileri yazılır; kaynakla metin eşleşmez, zamanla eşlenir).
            if message.hasPrefix("Ekran öğeleri ("), !message.hasPrefix("Ekran öğeleri kalktı") { return .element(message) }
            if message.hasPrefix("harita kartı:") || message.hasPrefix("telefon:") { return .element(message) }
            if message.hasPrefix("atlandı:") || message.hasPrefix("atıldı:") || message.hasPrefix("geç okundu:") { return .note(message) }
            guard message.hasPrefix("#"), message.contains(" okundu") else { return nil }
            guard let open = message.firstIndex(of: "\""), let close = message.lastIndex(of: "\""), open < close else { return nil }
            return .read(String(message[message.index(after: open)..<close]))
        }

        // MARK: Ekran öğeleri

        /// Ekran öğesi adayı: altyazı bandının dışında, en az iki harfli iki sözcük (büyük harf olabilir: `SPLIT UP &
        /// TAKE`); kayıtçının kendi yazısı ve tek sözcüklük HUD (pusula, `R1`) sayılmaz.
        public static func isElement(_ text: String, box: Box) -> Bool {
            let t = Filters.cleanJunk(text)
            guard !isOwnOverlay(t), Filters.hasEnoughLetters(t) else { return false }
            guard Text.words(t).filter({ $0.filter(\.isLetter).count >= 2 }).count >= 2 else { return false }
            // Altyazı bandı (ortada, altta) diyalog sayılır.
            if box.top >= 0.62, abs(box.midX - 0.5) <= 0.2 { return false }
            return true
        }

        /// Öğenin yeri (kare oranı).
        public static func elementPlace(_ b: Box) -> String {
            if b.midY < 0.5, b.midX < 0.4 { return "sol üst" }
            if b.midY < 0.25 { return "üst" }
            if b.midY >= 0.7, b.midX >= 0.6 { return "sağ alt" }
            if b.midX >= 0.6 { return "sağ" }
            if b.midX < 0.4 { return "sol" }
            return "orta"
        }

        /// Öğeler: görüldüğü aralıkta (3 sn önce – 4 sn sonra) günlükte herhangi bir ekran öğesi satırı varsa
        /// yakalanmış sayılır (günlük çeviriyi yazar; kaynakla metin eşleşmesi yapılamaz).
        public static func compareElements(_ candidates: [Candidate], logged: [LogEntry], beforeMs: Int = 3_000,
                                           afterMs: Int = 4_000) -> Report {
            var r = Report()
            for c in candidates {
                r.dialogue.append(c)
                let window = (c.firstMs - beforeMs)...(c.lastMs + afterMs)
                if logged.contains(where: { window.contains($0.ms) }) { r.caught.append(c) }
                else { r.misses.append(Miss(candidate: c, loggedReasons: [], replayReasons: [])) }
            }
            return r
        }

        public static func formatElements(_ r: Report, stamp: (Int) -> String) -> String {
            var s = "## Ekran öğeleri (altyazı dışı yazılar)\n\n"
            let pct = String(format: "%.1f", r.rate * 100).replacingOccurrences(of: ".", with: ",")
            s += "- Öğe: \(r.dialogue.count), günlükte karşılığı olan: \(r.caught.count), olmayan: \(r.misses.count) (%\(pct))\n"
            s += "- Öğe: altyazı bandı dışındaki, en az iki sözcüklü yazı bloğu (bildirim/mesaj kartı, köşe bildirimi,\n"
            s += "  seçim menüsü, harita kartı). Günlük çeviriyi yazdığı için yalnız zamanla eşlenir (kaba ölçü).\n\n"
            for m in r.misses {
                let c = m.candidate
                s += "- KARŞILIKSIZ \(stamp(c.firstMs))–\(stamp(c.lastMs)) [\(c.kind)] \"\(c.text.replacingOccurrences(of: "\n", with: " / "))\"\n"
            }
            return s + "\n"
        }

        // MARK: Rapor

        public static func format(_ r: Report, title: String, stamp: (Int) -> String) -> String {
            var s = "# \(title)\n\n"
            let pct = String(format: "%.1f", r.rate * 100).replacingOccurrences(of: ".", with: ",")
            s += "- Diyalog satırı: \(r.dialogue.count), okunan: \(r.caught.count), kaçan: \(r.misses.count) (yakalama %\(pct))\n"
            s += "- Diyalog: alt şeritte (üst ≥ 0,62), ortada (±0,15), küçük harf içeren, en az iki sözcüklü (ya da `OK.` gibi)\n"
            s += "  satır; menü karelerindeki, tamamı büyük harfli (tabela/HUD), ipucu ve eşya etiketi yazıları sayılmaz.\n\n"
            if !r.misses.isEmpty {
                s += "## Kaçanlar\n\n"
                for m in r.misses {
                    let c = m.candidate
                    s += "- \(stamp(c.firstMs))–\(stamp(c.lastMs)) (\(c.frames) kare) \"\(c.text.replacingOccurrences(of: "\n", with: " / "))\"\n"
                    if !m.loggedReasons.isEmpty { s += "  - günlükte: \(m.loggedReasons.joined(separator: "; "))\n" }
                    if !m.replayReasons.isEmpty { s += "  - yeniden oynatmada: \(m.replayReasons.joined(separator: "; "))\n" }
                    if m.loggedReasons.isEmpty, m.replayReasons.isEmpty { s += "  - neden bilinmiyor (not yok)\n" }
                }
                s += "\n"
            }
            s += "## Okunanlar\n\n"
            for c in r.caught { s += "- \(stamp(c.firstMs)) \"\(c.text.replacingOccurrences(of: "\n", with: " / "))\"\n" }
            return s
        }
    }
}

// MARK: - Kare tarayıcı

extension GameReading.MissMeter {
    /// Kayıttaki kareleri sırayla tarar: (1) bastırma kuralları kapalı okuma (her karede OCR, menü bayrağı, telefon
    /// kuralları, yalnız-altyazı, eski yazı ve tekrar süzgeci yok) diyalog adaylarını toplar; (2) menü ekranı olan
    /// kareler sayılmaz; (3) isteğe bağlı olarak kuralları açık gerçek okuyucu aynı kareleri sahte saatle okur ve
    /// notlarını (o anda okumayı engelleyen kural) toplar.
    public actor Scanner {
        public typealias GR = GameReading
        /// Kurallar açık bir yeniden oynatmanın sonuçları.
        public struct Replay: Sendable {
            public var notes: [LogEntry] = []
            public var reads: [LogEntry] = []
        }

        private let ocr: GR.OCR
        private let textReader: GR.TextReader
        private let region: GR.Box
        private let replayers: [(name: String, reader: GR.Reader, clock: GR.ManualClock)]
        public private(set) var collector = Collector()
        /// Altyazı dışı ekran öğeleri.
        public private(set) var elements = Collector()
        public private(set) var replays: [String: Replay] = [:]
        public private(set) var menuFrames = 0
        public private(set) var frames = 0
        private var lastMs: Int?
        private var previous: GR.Frame?
        /// Kurallar açık okuyucunun kare arası adımı (Mac'te kare ~100 ms'de bir gelir).
        public var replayStepMs = 250

        /// `replayConfigurations`: adı → okuyucu ayarı; her biri aynı kareleri sahte saatle okur.
        public init(textReader: GR.TextReader, region: GR.Box = GR.Box(left: 0.05, top: 0.6, right: 0.95, bottom: 0.98),
                    replayConfigurations: [(String, GR.Reader.Configuration)] = [], startMs: Int = 0) {
            self.textReader = textReader
            self.ocr = GR.OCR(reader: textReader)
            self.region = region
            self.replayers = replayConfigurations.map { name, cfg in
                let clock = GR.ManualClock(startMs)
                return (name, GR.Reader(textReader: textReader, clock: clock, configuration: cfg), clock)
            }
        }

        public func setReplayStep(_ ms: Int) { replayStepMs = max(50, ms) }

        private func step(_ frame: GR.Frame, at t: Int) async {
            for r in replayers {
                r.clock.nowMs = max(r.clock.nowMs, t)
                let out = await r.reader.process(frame)
                var rep = replays[r.name] ?? Replay()
                for n in out.notes { rep.notes.append(LogEntry(ms: t, text: n.label + (n.text.map { " \"" + $0 + "\"" } ?? ""))) }
                for e in out.events {
                    switch e {
                    case let .subtitleStarted(s), let .subtitleUpdated(s), let .subtitleCorrected(s), let .subtitleRestored(s):
                        rep.reads.append(LogEntry(ms: t, text: s.text.replacingOccurrences(of: "\n", with: " / ")))
                    default: break
                    }
                }
                replays[r.name] = rep
                _ = await r.reader.readCorners(frame)
            }
        }

        /// Bir kare (`ms`: kaydın zamanı).
        public func scan(_ frame: GR.Frame, at ms: Int) async {
            frames += 1
            if !replayers.isEmpty {
                // Önceki kare bu kareye dek ekranda kalır.
                if let prev = previous, let last = lastMs {
                    var t = last + replayStepMs
                    while t < ms, t - last <= 10_000 { await step(prev, at: t); t += replayStepMs }
                }
                await step(frame, at: ms)
                previous = frame
            }
            lastMs = ms
            // Menü karesi sayılmaz.
            if let menu = try? await textReader.read(frame, area: GR.Corners.menuSearchBox, scale: 1) {
                let texts = menu.map { GR.Filters.cleanJunk($0.text) }
                if GR.Corners.isMenuScreen(texts) { menuFrames += 1; return }
                let mapped = menu.compactMap { l in l.box.map { GR.Line(l.text, confidence: l.confidence, box: $0.mapped(into: GR.Corners.menuSearchBox)) } }
                    .filter { !isOwnOverlay($0.text) }
                if GR.MapScreen.isMapScreen(texts) {
                    // Harita ekranı: kart (yer adı + açıklama) öğe sayılır, altyazı okunmaz.
                    for block in GR.Filters.blocks(mapped) {
                        let text = block.map(\.text).joined(separator: "\n")
                        if let b = GR.Box.union(block.compactMap(\.box)), isElement(text, box: b), b.midX >= 0.55 {
                            elements.add(text, at: ms, kind: "harita")
                        }
                    }
                    menuFrames += 1
                    return
                }
                for block in GR.Filters.blocks(mapped) {
                    let text = block.map(\.text).joined(separator: "\n")
                    if let b = GR.Box.union(block.compactMap(\.box)), isElement(text, box: b) {
                        elements.add(text, at: ms, kind: elementPlace(b))
                    }
                }
            }
            guard let raw = try? await ocr.read(frame, area: region, deep: false) else { return }
            let lines = raw.filter { !isOwnOverlay($0.text) }
            for block in GR.Filters.blocks(lines.filter { $0.box != nil }) {
                let chosen = GR.FilterChain.chain(block, area: region, labels: true)
                guard !chosen.isEmpty else { continue }
                let text = chosen.map(\.text).joined(separator: "\n")
                let box = GR.Box.union(chosen.compactMap(\.box))?.mapped(into: region)
                if isDialogue(text, box: box) { collector.add(text, at: ms) }
            }
        }
    }
}
