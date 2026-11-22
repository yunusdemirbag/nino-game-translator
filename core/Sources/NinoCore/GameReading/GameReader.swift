// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation

// MARK: - Olaylar

extension GameReading {
    /// Sabitlenmiş ve gönderilmeye hazır altyazı.
    public struct Subtitle: Equatable, Sendable {
        public var id: Int
        /// Satırlar alt alta.
        public var text: String
        public var lines: [String]
        /// Konuşan adı (ilk satırda).
        public var speaker: String?
        /// Çevirmene giden parçalar (etiket ve tireler çevrilmez; büyük harf düzeltilmiş).
        public var parts: [Speaker.Part]
        /// Kare oranında, ortalanmış kutu.
        public var box: Box?
        /// Okunan alanın içindeki kutu.
        public var localBox: Box?
        /// Okumanın başladığı an (ms).
        public var startedAt: Int
        /// Gönderildiği an (ms).
        public var sentAt: Int
        public var inPack: Bool
        /// Kutunun altı taban çizgisinin üstünde (havuz öncelikli oyunda; §8.5).
        public var offBaseline: Bool
        public var isRestore: Bool

        /// Sıraya verilecek istek.
        public func request(packTranslation: String? = nil) -> TranslationQueue.Request {
            TranslationQueue.Request(id: id, text: text, box: box, packTranslation: packTranslation, offBaseline: offBaseline)
        }
    }

    public enum Event: Equatable, Sendable {
        /// Yeni altyazı: çevrilmeli.
        case subtitleStarted(Subtitle)
        /// Önceki altyazının uzaması (`Then` → `Then we go home.`): yerine konur.
        case subtitleUpdated(Subtitle)
        /// Önceki altyazının düzeltilmiş okuması: yerine konur.
        case subtitleCorrected(Subtitle)
        /// Kalkan altyazı geri geldi (önceki çevirisi yeniden gösterilir).
        case subtitleRestored(Subtitle)
        case subtitleEnded(id: Int)
        /// Bu karedeki ipucu satırları (kare oranında; `Hints` ile çevrilir).
        case hints([Line])
        case messageCard(Cards.Card)
        case callCard(Cards.Call)
        /// Köşe okuması (kare oranında satırlar; `CornerTracker` ile çevrilir).
        case corner(Corners.Place, [Line])
        case menuOpened(untilMs: Int)
        /// Kare başına ekran öğeleri listesi (ElementsBoard).
        case screenElements([ScreenElement])
        /// Altyazı şeridi bu oyunda ilk kez öğrenildi.
        case stripLearned(top: Double, bottom: Double)
    }

    public struct Output: Equatable, Sendable {
        public var events: [Event] = []
        /// Kapı doluydu ya da bekçi "meşgul" dedi: kare atlandı.
        public var skipped = false
        /// Okuma takıldı; hat sıfırlandı.
        public var stuck = false
        /// OCR yapıldı mı (yoksa son okuma kullanıldı).
        public var didRead = false
        /// Sahne aydınlığı (0–1), OCR yapıldıysa.
        public var brightness: Double?
        public var ocrMs: Int?
        public var averageConfidence: Float?
        /// Okunan yazı neden altyazı olmadı (teşhis; `SkipJournal` günlüğe çevirir).
        public var notes: [Note] = []
    }
}

// MARK: - Okuyucu (giriş noktası)

extension GameReading {
    /// Zamanlı okuma hattının tamamı. Mac: `process(frame)` her karede, `readCorners(frame)` köşe turunda.
    public actor Reader {
        public struct Configuration: Sendable {
            public var region = Region()
            public var gameKey = "genel"
            /// Havuz öncelikli oyun (telefon oyunu; taban çizgisi ve 0,935 görev çizgisi).
            public var poolPriority = false
            public var fastDetection = false
            public var cardsEnabled = false
            public var minConfidence: Float = 0.5
            public var gapIcon: GapIcon = .none
            public var stabilizer = Stabilizer.Settings()
            public var sendGate = SendGate.Settings()
            public var plan: ReadPlan?
            /// Harita ekranı (tuş satırları) menü sayılır (GTA 6; telefon/harita tarifi §9.1). Varsayılan kapalı.
            public var mapScreenCountsAsMenu = false
            /// "Yalnız altyazıyı çevir": ana bloktaki görev/ipucu/sekme/menü satırları atılır. Varsayılan kapalı.
            public var subtitlesOnly = false
            /// Menü bayrağı menü kapanınca (ıskayla) kalkar. `false`: eski davranış, tanınmadan 5 sn sonra (yalnız
            /// kaçırma ölçerin eski sürümü yeniden oynatması için).
            public var menuClearsOnExit = true
            /// Telefon oyununda cümleyi bitirmemiş altyazının küçük harfli devamı okunur. `false`: eski davranış.
            public var lowercaseContinuation = true

            public init(gameKey: String = "genel") { self.gameKey = gameKey }
        }

        public var configuration: Configuration
        private let ocr: OCR
        private let clock: Clock
        private let placementStore: PlacementStore?
        private let phone: PhoneTracker?
        private let isInPack: @Sendable (String) -> Bool

        private var gate = FrameGate()
        private var plan: ReadPlan
        private var chain = FilterChain()
        private var stabilizer: Stabilizer
        private var sendGate: SendGate
        private var lastLines: [Line] = []
        private var current: Subtitle?
        private var history: [Subtitle] = []
        private var nextID = 1
        private var knownNames: Set<String> = []
        private var menuOpenUntil = Int.min
        private var menuSeenAt = Int.min / 2
        /// Menü bayrağı açıkken art arda kaç menü aramasında menü görülmedi.
        private var menuMisses = 0
        /// Menünün son tanındığı karenin menü arama alanı izi.
        private var menuFingerprint: Fingerprint?
        /// Son altyazının kalktığı an ve kutusu (devam satırı kuralı).
        private var lastEnded: (at: Int, text: String, box: Box?)?
        /// İz aynı göründüğü için okunmayan karelerin başladığı an.
        private var reuseSince: Int?
        private var cornerRound = 0
        private var lastCornerRound = Int.min / 2
        private var cornersRunning = false
        /// Son menü aramasının satırları (kare oranında; oyun tanıma ve harita kartı için).
        public private(set) var lastMenuSearchLines: [Line] = []
        public private(set) var lastMenuSearchAt = Int.min / 2

        public init(textReader: TextReader, clock: Clock, configuration: Configuration = Configuration(),
                    placementStore: PlacementStore? = nil, phone: PhoneTracker? = nil,
                    isInPack: @escaping @Sendable (String) -> Bool = { _ in false }) {
            self.configuration = configuration
            self.ocr = OCR(reader: textReader, minConfidence: configuration.minConfidence, gapIcon: configuration.gapIcon)
            self.clock = clock
            self.placementStore = placementStore
            self.phone = phone
            self.isInPack = isInPack
            self.plan = configuration.plan ?? .standard(fastDetection: configuration.fastDetection)
            self.stabilizer = Stabilizer(settings: configuration.stabilizer)
            self.sendGate = SendGate(settings: configuration.sendGate, isInPack: isInPack)
        }

        public var placement: Placement { placementStore?.placement(for: configuration.gameKey) ?? Placement() }
        public var questLine: Double? { placement.questLine(poolPriority: configuration.poolPriority) }
        public var baseline: Double? { configuration.poolPriority ? placement.baseline : nil }
        public var menuOpen: Bool { clock.nowMs < menuOpenUntil }
        public var currentSubtitle: Subtitle? { current }

        /// Okunan alan (öğrenilen şeritle daraltılmış).
        public var readingArea: Box { configuration.region.readingArea(stripTop: placement.strip?.top) }

        public func setRegion(_ region: Region) { configuration.region = region; plan.reset() }

        /// "Yalnız altyazıyı çevir" ayarı çeviri sürerken değişti.
        public func setSubtitlesOnly(_ on: Bool) { configuration.subtitlesOnly = on }

        /// Çeviri başarısız oldu ve satır ekrandaydı: satır unutulur, 1 sn sonra yeniden denenir.
        public func translationFailed(id: Int) {
            guard current?.id == id else { return }
            stabilizer.forget(now: clock.nowMs)
            current = nil
        }

        /// Hattı sıfırlar (durdurma, oyun değişimi, takılma).
        public func reset() -> [Event] {
            gate.reset(); plan.reset(); chain.reset(); sendGate.reset(); lastLines = []
            let r = stabilizer.reset()
            defer { current = nil; history = []; lastEnded = nil; reuseSince = nil }
            if r == .clear, let c = current { return [.subtitleEnded(id: c.id)] }
            return []
        }

        // MARK: Kare

        public func process(_ input: Frame) async -> Output {
            var out = Output()
            let start = clock.nowMs
            let ticket: Int
            switch gate.enter(now: start) {
            case .skipped: out.skipped = true; return out
            case .stuck:
                out.stuck = true
                out.events = reset()
                return out
            case let .admitted(t): ticket = t
            }
            defer { gate.exit(ticket: ticket) }

            let phoneContext = await phone?.context(for: input, now: start) ?? .none
            let frame: Frame = phoneContext.maskBox.map { MaskedFrame(input, mask: $0) } ?? input
            let area = readingArea
            let fp = frame.fingerprint(of: area)

            var lines: [Line]
            var delayedSince: Int?
            switch plan.decide(fp, now: start, band: subtitleBand(area)) {
            case .reuse:
                lines = lastLines
                if reuseSince == nil { reuseSince = start }
            case let .read(deep):
                if plan.lastReadByTimeLimit { delayedSince = reuseSince }
                reuseSince = nil
                out.didRead = true
                do {
                    lines = try await ocr.read(frame, area: area, deep: deep)
                } catch WatchdogError.busy {
                    out.skipped = true
                    out.notes.append(Output.Note(.busy))
                    return out
                } catch WatchdogError.stuck {
                    out.stuck = true
                    out.events = reset()
                    return out
                } catch {
                    lines = []
                    out.notes.append(Output.Note(.readError))
                }
                guard gate.holds(ticket) else { return out } // takılma sırasında sıfırlandı
                plan.record(empty: lines.isEmpty)
                lastLines = lines
                let now = clock.nowMs
                out.ocrMs = max(0, now - start)
                if !lines.isEmpty { out.averageConfidence = lines.map(\.confidence).reduce(0, +) / Float(lines.count) }
                if let img = frame.crop(area, scale: 1) { out.brightness = sceneBrightness(img) }
            }

            let now = clock.nowMs
            var ctx = FilterChain.Context(now: now, area: area, frame: frame)
            ctx.phone = phoneContext
            ctx.phoneGame = configuration.poolPriority
            ctx.cardsEnabled = configuration.cardsEnabled
            ctx.questLine = questLine
            ctx.baseline = baseline
            ctx.menuOpen = menuOpen
            ctx.subtitlesOnly = configuration.subtitlesOnly
            if configuration.subtitlesOnly { ctx.strip = placement.strip }
            ctx.openPrevious = configuration.lowercaseContinuation ? openPrevious(now: now) : nil
            ctx.currentText = current?.text
            ctx.lowercaseWait = configuration.lowercaseContinuation
            let result = chain.run(lines, ctx)
            if result.rereadSoon { plan.forceNextRead() }
            out.notes += result.notes

            if !result.hints.isEmpty { out.events.append(.hints(result.hints)) }
            if let card = result.card { out.events.append(.messageCard(card)) }
            if let call = result.call { out.events.append(.callCard(call)) }

            let reaction = stabilizer.observe(result.text, box: result.localBox, fingerprint: fp, now: now)
            var sends: [SendGate.Reading] = []
            switch reaction {
            case .none:
                sends = sendGate.onNone(result.text, box: result.box, now: now)
            case let .translate(text):
                sends = sendGate.onTranslate(text, box: result.box, now: now)
                // Satır iz aynı göründüğü için geç okundu (sabit görüntü kuralı; plan §3).
                if let since = delayedSince { out.notes.append(Output.Note(.staticFrame(delayMs: max(0, now - since)), text: text)) }
            case .clear:
                sends = sendGate.onClearOrRestore(now: now)
            case .restore:
                sends = sendGate.onClearOrRestore(now: now)
            }
            for s in sends { out.events += emit(s, localBox: result.localBox, now: now) }
            switch reaction {
            case .clear:
                if let c = current {
                    out.events.append(.subtitleEnded(id: c.id)); history.append(c); current = nil
                    lastEnded = (now, c.text, c.box)
                }
            case let .restore(text):
                if let i = history.lastIndex(where: { $0.text == text }) ?? history.lastIndex(where: { Similarity.isSameSubtitle(text, sentLines: $0.lines) }) {
                    var back = history.remove(at: i)
                    back.isRestore = true
                    if let c = current { history.append(c) }
                    current = back
                    out.events.append(.subtitleRestored(back))
                } else {
                    out.events += emit(SendGate.Reading(text: text, box: result.box, startedAt: now, holdMs: 0,
                                                        score: Filters.score(text), inPack: sendGate.isInPack(text)), localBox: result.localBox, now: now)
                }
            default: break
            }
            if history.count > 8 { history.removeFirst(history.count - 8) }
            return out
        }

        /// Cümleyi bitirmemiş altyazının kutusu (ekrandaki ya da en çok 1,5 sn önce kalkan): küçük harfle başlayan
        /// blok onun devamı sayılabilir (`And after what we went through,` → `we deserve to get paid.`).
        private func openPrevious(now: Int) -> Box? {
            if let c = current { return Text.endsSentence(c.text) ? nil : (c.box ?? Box(left: 0.3, top: 0.8, right: 0.7, bottom: 0.95)) }
            guard let e = lastEnded, now - e.at <= 1_500, !Text.endsSentence(e.text) else { return nil }
            return e.box ?? Box(left: 0.3, top: 0.8, right: 0.7, bottom: 0.95)
        }

        /// Altyazı bandı (alan içi; plan §3): ekrandaki satırın kutusu, yoksa öğrenilen şerit, yoksa bütün alan.
        /// Satırın tam genişliği ve biraz üstü/altı sayılır (yeni satır daha uzun ya da bir satır aşağıda olabilir).
        private func subtitleBand(_ area: Box) -> Box? {
            let band: Box
            if let b = current?.localBox {
                band = b
            } else if let strip = placement.strip {
                band = Box(left: area.left, top: strip.top, right: area.right, bottom: strip.bottom).local(in: area)
            } else {
                return nil
            }
            let pad = max(0.05, band.height * 0.5)
            let out = Box(left: 0, top: max(0, band.top - pad), right: 1, bottom: min(1, band.bottom + pad))
            return out.bottom > out.top ? out : nil
        }

        private func emit(_ s: SendGate.Reading, localBox: Box?, now: Int) -> [Event] {
            var events: [Event] = []
            let lines = Text.lines(s.text)
            knownNames.formUnion(Speaker.names(fromLabelsIn: s.text))
            let parts = Speaker.parts(s.text).map { p -> Speaker.Part in
                p.translate ? Speaker.Part(Speaker.fixCapitals(p.text, knownNames: knownNames), translate: true) : p
            }
            let off = baseline.map { b in s.box.map { $0.bottom < b } ?? false } ?? false
            let sub = Subtitle(id: nextID, text: s.text, lines: lines, speaker: lines.first.flatMap { Speaker.split($0)?.name },
                               parts: parts, box: s.box, localBox: localBox, startedAt: s.startedAt, sentAt: now,
                               inPack: s.inPack, offBaseline: off, isRestore: false)
            nextID += 1
            if let prev = current {
                if Similarity.isExtension(s.text, of: prev.text) { events.append(.subtitleUpdated(sub)) }
                else if Similarity.isCorrection(s.text, of: prev.text) { events.append(.subtitleCorrected(sub)) }
                else { events.append(.subtitleStarted(sub)) }
                history.append(prev)
            } else {
                events.append(.subtitleStarted(sub))
            }
            current = sub
            if let b = s.box, let store = placementStore, store.record(b, game: configuration.gameKey), let strip = placement.strip {
                events.append(.stripLearned(top: strip.top, bottom: strip.bottom))
            }
            return events
        }

        /// Telefon oyunu kararı değişti (GTA 6 kuralları; telefon/harita tarifi §10). Okuyucu yeniden kurulmaz.
        public func setPhoneGame(_ on: Bool, packGame: String?) {
            GTA6Rules.apply(on, packGame: packGame, to: &configuration)
            plan.reset()
        }

        /// Menü bayrağını dışarıdan açar (ör. harita ekranı başka yoldan tanındı). Olay döner.
        public func markMenuOpen(durationMs: Int = 5_000) -> Event {
            menuOpenUntil = max(menuOpenUntil, clock.nowMs + durationMs)
            menuSeenAt = clock.nowMs
            return .menuOpened(untilMs: menuOpenUntil)
        }

        // MARK: Köşeler

        /// Köşe turu (§12.1). Aralık dolmadıysa ya da önceki tur sürüyorsa boş döner.
        public func readCorners(_ frame: Frame) async -> [Event] {
            let now = clock.nowMs
            guard !cornersRunning, now - lastCornerRound >= Corners.intervalMs(menuOpen: menuOpen) else { return [] }
            cornersRunning = true
            lastCornerRound = now
            defer { cornersRunning = false; cornerRound += 1 }
            var events: [Event] = []
            let places = Corners.places(round: cornerRound, questLine: questLine, menuSeenRecently: now - menuSeenAt <= 10_000)
            for (place, box) in places {
                let scale = place == .menuSearch ? Corners.menuScale(pixelWidth: frame.pixelWidth) : 1
                guard let raw = try? await ocr.read(frame, area: box, deep: false, scale: scale) else { continue }
                let lines = raw.map { l in Line(Filters.cleanJunk(l.text), confidence: l.confidence, box: l.box?.mapped(into: box)) }
                    .filter { !$0.text.isEmpty }
                switch place {
                case .menuSearch:
                    lastMenuSearchLines = lines
                    lastMenuSearchAt = clock.nowMs
                    let fp = frame.fingerprint(of: box)
                    if Corners.isMenuScreen(lines.map(\.text))
                        || (configuration.mapScreenCountsAsMenu && MapScreen.isMapScreen(lines.map(\.text))) {
                        menuOpenUntil = clock.nowMs + 5_000
                        menuSeenAt = clock.nowMs
                        menuMisses = 0
                        menuFingerprint = fp
                        events.append(.menuOpened(untilMs: menuOpenUntil))
                    } else if menuOpen, configuration.menuClearsOnExit {
                        // Menü kapandı mı (§12.2): bayrak 5 sn beklemez. Ekran büyük ölçüde değiştiyse ilk ıskada,
                        // değişmediyse (okuma bir kez tutmadı) ikinci ıskada kalkar; aksi hâlde menüden çıkınca
                        // gelen altyazılar 5 sn boyunca boşaltılıyordu (22 Kasım 23:41).
                        menuMisses += 1
                        let sceneChanged = menuFingerprint.map { fp.changedShare(from: $0, threshold: 40) >= 0.25 } ?? false
                        if sceneChanged || menuMisses >= 2 {
                            menuOpenUntil = clock.nowMs
                            menuMisses = 0
                        }
                    }
                case .topLeft:
                    var picked = Corners.topLeftLines(lines)
                    // Menüler çevrilmez (okuma-hatti §12): menü açıkken, harita listesi ya da satırlar menü öğeleriyse
                    // (duraklatma menüsünün sol sütunu `Map / Game / Store / Help`) köşe boş sayılır.
                    if menuOpen || Corners.isMapList(picked) || Corners.isMenuScreen(picked.map(\.text)) { picked = [] }
                    events.append(.corner(.topLeft, picked))
                case .questStrip:
                    events.append(.corner(.questStrip, Corners.questStripLines(lines, subtitle: current?.text, subtitleBox: current?.box)))
                }
            }
            return events
        }
    }

    /// Bütün köşe, ipucu, kart ve ek alan öğelerini tek listede tutar (TV'ye katman olarak gider).
    public struct ElementsBoard: Sendable {
        public private(set) var elements: [String: ScreenElement] = [:]
        public init() {}

        public mutating func set(_ e: ScreenElement) { elements["\(e.kind.rawValue):\(e.id)"] = e }
        public mutating func remove(kind: ScreenElement.Kind, id: String) { elements["\(kind.rawValue):\(id)"] = nil }
        public mutating func removeAll(kind: ScreenElement.Kind) { elements = elements.filter { $0.value.kind != kind } }
        public mutating func clear() { elements = [:] }

        /// Sıralı liste (önce tür, sonra kimlik). Boş liste TV'deki katmanı temizler.
        public var list: [ScreenElement] {
            elements.values.sorted { ($0.kind.rawValue, $0.id) < ($1.kind.rawValue, $1.id) }
        }

        public var event: Event { .screenElements(list) }
    }
}
