// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
#if canImport(Vision)
import CoreML
import Vision
#endif

// MARK: - Yalnız işlemcide okuyan Vision okuyucusu (tarif §1.2)

#if canImport(Vision)
extension GameReading {
    /// Telefon okuması Neural Engine'i altyazıya bırakır: istek işlemciye bağlanır.
    public struct CPUTextReader: TextReader {
        public var languages: [String]
        public init(languages: [String] = ["en-US"]) { self.languages = languages }

        public func read(_ frame: Frame, area: Box, scale: Double) async throws -> [Line] {
            guard let image = frame.crop(area, scale: scale) else { return [] }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = true
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

// MARK: - Telefon izleyici (tarif §1.2, §3–§8)

extension GameReading {
    /// Panel güncellemesi. `elements`: `nil` değişmedi, boş liste ekrandaki telefon öğeleri kalkar,
    /// dolu liste telefon öğelerinin yerine geçer (`ElementsBoard.removeAll(kind: .phone)` + `set`).
    public struct PhoneUpdate: Equatable, Sendable {
        public var elements: [ScreenElement]?
        /// Telefonda sohbet ya da uygulama okundu (oyun GTA 6 sayılır, `GameSense.notePhoneRead`).
        public var phoneTextSeen: Bool
        /// Kaldırma yalnız panelin yeniden kurulması için (telefon hâlâ aynı sohbette, ör. kaydırma): gönderici eski
        /// öğeleri yenisi gelene kadar kısa süre TV'de tutabilir. `false`: telefon kapandı / ekran türü değişti, hemen kalkar.
        public var mayHold: Bool
        /// İzleyicinin verdiği sıra numarası (tur ve takip görevleri sırasız biter; eskisi yenisini ezmesin).
        public var serial: Int
        public init(elements: [ScreenElement]?, phoneTextSeen: Bool = false, mayHold: Bool = false, serial: Int = 0) {
            self.elements = elements; self.phoneTextSeen = phoneTextSeen; self.mayHold = mayHold; self.serial = serial
        }
        public static let remove = PhoneUpdate(elements: [])
        /// Sıra numarası karşılaştırılmaz.
        public static func == (a: PhoneUpdate, b: PhoneUpdate) -> Bool {
            a.elements == b.elements && a.phoneTextSeen == b.phoneTextSeen && a.mayHold == b.mayHold
        }
    }

    public actor PhoneWatcher: PhoneTracker {
        public struct Settings: Sendable {
            public var idleIntervalMs = 600
            public var shownIntervalMs = 1_000
            public var pauseAfterMenuMs = 8_000
            public var removeAfterUnseenMs = 1_200
            public var trackIntervalMs = 100
            /// Altyazı hattına: telefon son bu kadar sürede görüldüyse aynı yerde sayılır.
            public var subtitleHoldMs = 5_000
            public var textsRecentMs = 30_000
            public var seenRecentMs = 10_000
            public init() {}
        }

        public var settings: Settings
        private let reader: TextReader
        private let clock: Clock
        private let translator: PhoneTranslator?
        private let rectangles: PhoneRectangleDetector?
        public private(set) var memory: PhoneMemory

        private var phoneGame = false
        private var menuSeenAt = Int.min / 2
        private var mapCardShown = false
        private var reading = false
        private var lastRound = Int.min / 2
        private var lastTrack = Int.min / 2
        private var track = PhoneTrack()
        private var subtitleTrack = PhoneTrack()
        private var panel = PhonePanel()
        private var phoneSeenAt = Int.min / 2
        private var textSeenAt = Int.min / 2
        private var recentTexts: [String] = []
        private var pendingShift: (dx: Double, dy: Double)?
        private var serial = 0

        public init(textReader: TextReader, clock: Clock, memory: PhoneMemory, translator: PhoneTranslator?,
                    rectangles: PhoneRectangleDetector? = nil, settings: Settings = Settings()) {
            self.reader = textReader; self.clock = clock; self.memory = memory; self.translator = translator
            self.rectangles = rectangles; self.settings = settings
        }

        // MARK: Durum

        public func setPhoneGame(_ on: Bool) -> PhoneUpdate? {
            phoneGame = on
            guard !on else { return nil }
            return removePanel()
        }

        /// Menü/harita bayrağı açıldı (köşe turu `menuOpened`).
        public func noteMenu(at now: Int) { menuSeenAt = now }
        public func setMapCardShown(_ shown: Bool) { mapCardShown = shown }
        /// Çeviri dili değişti: o dilin hafızası yüklenir, panel kalkar.
        public func switchLanguage(_ language: String) -> PhoneUpdate? {
            memory.switchLanguage(language)
            return removePanel()
        }

        /// Telefon son `ms` içinde görüldü mü (mesaj kartı kuralı 10 sn, köşe ipucu kuralı 3 sn)?
        public func phoneSeen(withinMs ms: Int) -> Bool { clock.nowMs - phoneSeenAt <= ms }

        /// Son `ms` içinde bulunan telefonun kutusu.
        public func phoneBox(withinMs ms: Int) -> Box? {
            let now = clock.nowMs
            if let l = track.last, now - track.lastFoundAt <= ms { return l.box }
            if let l = subtitleTrack.last, now - subtitleTrack.lastFoundAt <= ms { return l.box }
            return nil
        }
        public var isPanelShown: Bool { panel.shown != nil }

        private func removePanel() -> PhoneUpdate? {
            guard panel.shown != nil else { return nil }
            panel.cleared()
            return .remove
        }

        // MARK: Altyazı hattına bilgi (§7)

        public func context(for frame: Frame, now: Int) async -> PhoneContext {
            guard phoneGame else { return .none }
            var box: Box?
            if let image = frame.image, let px = PhonePixels.from(image, width: PhoneFinder.gridWidth, height: PhoneFinder.gridHeight) {
                if let f = PhoneFinder.find(px) { _ = subtitleTrack.update(found: f, pixels: px, now: now); phoneSeenAt = max(phoneSeenAt, now) }
            }
            if let l = subtitleTrack.last, now - subtitleTrack.lastFoundAt <= settings.subtitleHoldMs { box = l.box }
            if box == nil, let l = track.last, now - track.lastFoundAt <= settings.subtitleHoldMs { box = l.box }
            let textRecent = now - textSeenAt <= settings.textsRecentMs
            return PhoneContext(box: box, recentTexts: textRecent ? recentTexts : [], textSeenRecently: textRecent,
                                seenWithin10s: now - phoneSeenAt <= settings.seenRecentMs,
                                isAppText: { PhoneDictionary.isAppText($0) })
        }

        /// Altyazı/köşe satırlarında telefon uygulaması yazısı görüldüyse telefonun yeri bu yazılardan tahmin edilir.
        public func noteLines(_ lines: [Line], frame: Frame?) {
            guard phoneGame else { return }
            let boxes = lines.filter { PhoneDictionary.isAppText($0.text) }.compactMap(\.box)
            guard !boxes.isEmpty else { return }
            let now = clock.nowMs
            let px = frame?.image.flatMap { PhonePixels.from($0, width: PhoneFinder.gridWidth, height: PhoneFinder.gridHeight) }
            if track.estimate(fromAppTexts: boxes, pixels: px, now: now) != nil { phoneSeenAt = now }
        }

        // MARK: Panel turu

        /// Aralığı gelmişse telefonu okur. Değişiklik yoksa `nil`.
        public func round(_ frame: Frame) async -> PhoneUpdate? { stamp(await readRound(frame)) }

        /// Dönen güncellemeye sıra numarası.
        private func stamp(_ u: PhoneUpdate?) -> PhoneUpdate? {
            guard var u else { return nil }
            serial += 1
            u.serial = serial
            return u
        }

        private func readRound(_ frame: Frame) async -> PhoneUpdate? {
            let now = clock.nowMs
            guard phoneGame else { return removePanel() }
            if now - menuSeenAt <= settings.pauseAfterMenuMs || mapCardShown { return removePanel() }
            let interval = panel.shown == nil ? settings.idleIntervalMs : settings.shownIntervalMs
            guard !reading, now - lastRound >= interval else { return nil }
            reading = true; lastRound = now
            defer { reading = false }

            let image = frame.image
            let px = image.flatMap { PhonePixels.from($0, width: PhoneFinder.gridWidth, height: PhoneFinder.gridHeight) }
            var found = px.flatMap { PhoneFinder.find($0) }
            if found == nil, let rectangles, let image, let full = PhonePixels.from(image, width: 480, height: 270) {
                found = PhoneFinder.findByShape(rectangles.rectangles(in: image), pixels: full)
            }
            guard let loc = track.update(found: found, pixels: px, now: now) ?? track.last.flatMap({ now - track.lastFoundAt <= 2_000 ? $0 : nil }) else {
                return unseen(now)
            }
            if found != nil { phoneSeenAt = now }
            guard let raw = try? await reader.read(frame, area: loc.box, scale: 1) else { return nil }
            let lines = raw.map { $0.mapped(into: loc.box) }
            if PhoneScreen.containsMapButton(lines) { return removePanel() }
            switch PhoneScreen.classify(lines, phone: loc) {
            case .empty, .notPhone: return unseen(now)
            case .list:
                phoneSeenAt = now
                return removePanel()
            case .screen(let r):
                phoneSeenAt = now; textSeenAt = now
                recentTexts = r.messages.map(\.text)
                let colors = image.flatMap { PhoneColorSampler(image: $0)?.illuminated(for: loc) }
                var update = await build(r, phone: loc, colors: colors) ?? PhoneUpdate(elements: nil)
                update.phoneTextSeen = true
                return update
            }
        }

        private func unseen(_ now: Int) -> PhoneUpdate? {
            guard panel.shown != nil, now - phoneSeenAt >= settings.removeAfterUnseenMs else { return nil }
            return removePanel()
        }

        /// Bilinen Türkçe: telefon sözlüğü (Türkçe hedef), havuz, kalıcı hafıza, oturum hafızası.
        private func knownTranslations(_ texts: [String]) async -> [String: String] {
            var out: [String: String] = [:]
            let turkish = (translator?.targetLanguage ?? "tr").lowercased().hasPrefix("tr")
            for t in texts {
                if turkish, let d = PhoneDictionary.turkish(t) { out[t] = d; continue }
                if let k = await translator?.known(t), !k.isEmpty { out[t] = PhoneText.clean(k); continue }
                if let m = memory.lookup(t) { out[t] = m }
            }
            return out
        }

        func build(_ r: PhoneScreenReading, phone: PhoneLocation, colors: PhoneColorSource?) async -> PhoneUpdate? {
            var known = await knownTranslations(r.messages.map(\.text))
            let mem = memory
            let oldHeader = panel.shown.map { ($0.kind, $0.header.map(Text.key)) }
            let plan = panel.plan(r, phone: phone, inMemory: { mem.contains($0) }, lookup: { known[$0] })
            switch plan {
            case .keep: return nil
            case .remove:
                // Kaydırma (aynı sohbet yeniden kurulacak) tutulabilir; sohbet değiştiyse hemen kalkar.
                let sameChat = oldHeader.map { $0.0 == r.kind && $0.1 == r.header.map(Text.key) } ?? false
                return PhoneUpdate(elements: [], mayHold: sameChat)
            case let .build(reading, unknown, context, _, removeFirst):
                if !unknown.isEmpty, let translator {
                    let res = await PhoneTranslation.translate(unknown, context: context, with: translator)
                    for (src, tr) in res.translations {
                        memory.store(src, tr, device: res.device.contains(src))
                        known[src] = tr
                    }
                    if !res.translations.isEmpty { memory.save() }
                }
                let wasShown = panel.shown != nil
                let els = panel.commit(reading, phone: phone, lookup: { known[$0] }, colors: colors)
                // Gösterilen panel düştüyse TV'den de kalkmalı.
                if els.isEmpty { return wasShown || removeFirst ? .remove : nil }
                return PhoneUpdate(elements: els)
            }
        }

        // MARK: Takip (§8.4)

        /// Panel ekrandayken en sık 100 ms'de bir: yalnız telefonun yeri bulunur, balonlar kaydırılır.
        public func trackPhone(_ frame: Frame) -> PhoneUpdate? { stamp(followPhone(frame)) }

        private func followPhone(_ frame: Frame) -> PhoneUpdate? {
            let now = clock.nowMs
            guard phoneGame, let s = panel.shown, now - lastTrack >= settings.trackIntervalMs,
                  let image = frame.image, let px = PhonePixels.from(image, width: PhoneFinder.gridWidth, height: PhoneFinder.gridHeight),
                  let f = PhoneFinder.find(px) else { return nil }
            lastTrack = now
            _ = track.update(found: f, pixels: px, now: now)
            phoneSeenAt = now
            return applyShift(dx: f.centerX - s.phone.centerX, dy: f.centerY - s.phone.centerY)
        }

        /// İki ölçüm aynı yöndeyse ortalaması kadar kaydırır (tek ölçüm gürültüdür).
        func applyShift(dx: Double, dy: Double) -> PhoneUpdate? {
            // Ölü bölge: telefon bulucunun ızgarası 1/240 × 1/135; 2 hücrelik oynama (elde sallanma, ızgara) kaydırma sayılmaz.
            guard abs(dx) > 0.009 || abs(dy) > 0.016, abs(dx) < 0.08, abs(dy) < 0.08 else { pendingShift = nil; return nil }
            if let p = pendingShift, abs(p.dx - dx) <= 0.008, abs(p.dy - dy) <= 0.011 {
                pendingShift = nil
                return PhoneUpdate(elements: panel.shift(dx: (p.dx + dx) / 2, dy: (p.dy + dy) / 2))
            }
            pendingShift = (dx, dy)
            return nil
        }
    }
}

// MARK: - Telefon araması (okuma-hatti §14.2)

extension GameReading {
    /// "X aranıyor…" yazısı: arama kartı görülünce kartın üstüne sade, eğik; durum boşsa ya da 3 sn görülmezse kalkar.
    public struct CallPresenter: Sendable {
        public enum Step: Equatable, Sendable { case none, set(ScreenElement), remove }
        public private(set) var shown: ScreenElement?
        private var lastSeen = Int.min / 2
        public var holdMs = 3_000
        public init() {}

        public mutating func observe(_ call: Cards.Call?, now: Int) -> Step {
            guard let call else {
                if shown != nil, now - lastSeen >= holdMs { shown = nil; return .remove }
                return .none
            }
            lastSeen = now
            guard let e = Cards.layout(call) else {
                if shown != nil { shown = nil; return .remove }
                return .none
            }
            if e == shown { return .none }
            shown = e
            return .set(e)
        }
    }
}
