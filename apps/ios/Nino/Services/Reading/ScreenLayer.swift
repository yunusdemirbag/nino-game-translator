// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import NinoCore

/// Ekran katmanının modele bildirdikleri.
enum ScreenLayerEvent: Sendable, Equatable {
    /// Ekrandaki yazılardan oyun tanındı (bugün yalnız GTA 6).
    case screenGame(String)
    /// TV'ye giden ekran öğeleri değişti (boş: kalktı).
    case elements([GameReading.ScreenElement])
}

/// Ekran öğesi → protokol mesajı. TV'ye ne zaman gideceğine NinoCore'un `ScreenItemSender`'ı karar verir (değişince
/// gönderir, ekranda duran listeyi 60 sn'de bir yeniler, harita kartını tek kaçırmada kaldırmaz).
enum ScreenChannel {
    static let durationMs = GameReading.ScreenElement.layerDurationMs

    static func payload(_ list: [GameReading.ScreenElement]) -> ScreenPayload {
        ScreenPayload(items: list.map(item), durationMs: durationMs, overlay: true)
    }

    /// Öğe biçimi → protokol bayrakları (NinoCore docs/tarif/protokol.md "screen").
    static func item(_ e: GameReading.ScreenElement) -> ScreenItem {
        let s = e.style
        return ScreenItem(box: NinoBox(left: e.box.left, top: e.box.top, right: e.box.right, bottom: e.box.bottom),
                          text: e.text, line: s.lineHeight,
                          paragraphs: e.text.contains("\n") ? true : nil,
                          plain: s.plain ? true : nil, italic: s.italic ? true : nil,
                          fill: s.background, ink: s.textColor,
                          angle: abs(s.angle) >= 0.3 ? s.angle : nil,
                          alpha: s.opacity < 1 ? s.opacity : nil,
                          side: s.bubble ? true : nil, frost: s.frosted ? true : nil,
                          backdrop: s.backdrop ? true : nil, card: s.card ? true : nil)
    }
}

/// Altyazı dışındaki ekran öğeleri: köşeler, tuş ipuçları, mesaj/arama kartı, telefon paneli ve harita kartı
/// (`ElementsBoard` → TV'ye `screen` / `screen-clear`). Tarif: NinoCore docs/tarif/oyun-okuma.md, telefon-harita.md.
/// Yan okumalar (köşe turu, telefon turu) altyazı hattını bekletmesin diye kendi görevlerinde döner; her biri sürerken
/// yenisi başlamaz.
actor ScreenLayer {
    struct Options: Sendable {
        /// "Köşeleri çevir" (yalnız İngilizce kaynakta).
        var cornersEnabled = true
        var isTargetLanguage: @Sendable (String) -> Bool = GameReading.TranslationQueue.looksTurkish
    }

    nonisolated let phone: GameReading.PhoneWatcher?
    private let reader: GameReading.Reader
    private let map: GameReading.MapCardWatcher
    private let translator: ElementTranslation
    private let send: @Sendable (NinoEvent) async -> Void
    private let clock: GameReading.Clock
    private let options: Options
    private let onEvent: @Sendable (ScreenLayerEvent) -> Void

    private var board = GameReading.ElementsBoard()
    /// TV'ye giden liste (NinoCore `ScreenItemSender`, oyun-okuma.md "Ekran öğesi gönderici").
    private var sender = GameReading.ScreenItemSender()
    private var topLeft: GameReading.CornerTracker
    private var quest: GameReading.CornerTracker
    private var hints = GameReading.Hints()
    private var cards = GameReading.CardPresenter()
    private var calls = GameReading.CallPresenter()
    private var sense = GameReading.GameSense()
    private(set) var phoneGame = false
    /// Sıfırlamada artar; eski turların sonuçları atılır.
    private var generation = 0
    private var cornersRunning = false
    private var phoneRunning = false
    private var cardTranslating = false
    /// Bu oturumda TV'ye giden `screen` / `screen-clear` sayısı (testler).
    private(set) var screenMessages = 0

    init(reader: GameReading.Reader, phone: GameReading.PhoneWatcher?, translator: ElementTranslation,
         clock: GameReading.Clock, options: Options = Options(),
         send: @escaping @Sendable (NinoEvent) async -> Void, onEvent: @escaping @Sendable (ScreenLayerEvent) -> Void = { _ in }) {
        self.reader = reader
        self.phone = phone
        self.translator = translator
        self.send = send
        self.clock = clock
        self.options = options
        self.onEvent = onEvent
        map = GameReading.MapCardWatcher(translator: translator, clock: clock)
        topLeft = GameReading.CornerTracker(place: .topLeft, isTargetLanguage: options.isTargetLanguage)
        quest = GameReading.CornerTracker(place: .questStrip, isTargetLanguage: options.isTargetLanguage)
    }

    /// Oyunun PS5'ten ya da kullanıcıdan bilinen adı (ekrandan tanıma bunu ezmez).
    func setReportedGame(_ name: String?) { sense.reported = name }

    /// Telefon oyunu kararı (telefon-harita.md §1). Kapanınca panel ve harita kartı kalkar.
    func setPhoneGame(_ on: Bool) async {
        guard on != phoneGame else { return }
        phoneGame = on
        if let u = await phone?.setPhoneGame(on) { applyPhone(u) }
        applyMap(await map.setPhoneGame(on))
        await publish(drop: on ? [] : [.map])
    }

    var elements: [GameReading.ScreenElement] { board.list }

    // MARK: Kareler

    /// Ana okumanın her karesi: okuma olayları (ipucu, kart, arama) ve yan turların başlatılması. Hızlı döner.
    func frame(_ image: CGImage, events: [GameReading.Event], skipped: Bool) async {
        let frame = GameReading.ImageFrame(image)
        if !skipped { await observe(events) }
        startRounds(frame)
        await refresh()
    }

    private func observe(_ events: [GameReading.Event]) async {
        let now = clock.nowMs
        var hintLines: [GameReading.Line] = []
        var card: GameReading.Cards.Card?
        var call: GameReading.Cards.Call?
        for e in events {
            switch e {
            case let .hints(lines): hintLines += lines
            case let .messageCard(c): card = c
            case let .callCard(c): call = c
            case .menuOpened: await phone?.noteMenu(at: now)
            default: break
            }
        }
        let menuOpen = await reader.menuOpen
        let questLine = await reader.questLine
        var changed = false

        let (next, removed) = hints.observe(hintLines, questLine: questLine, menuOpen: menuOpen)
        for k in removed { board.remove(kind: .hint, id: "hint:" + k); changed = true }
        if let line = next { translateHint(line) }

        let phoneSeen = await phone?.phoneSeen(withinMs: 10_000) ?? false
        switch cards.observe(card, phoneSeenRecently: phoneSeen, now: now) {
        case .none: break
        case .remove:
            board.remove(kind: .messageCard, id: "card")
            changed = true
        case let .translate(body):
            if let card, !cardTranslating { translateCard(card, body: body) }
        }

        switch calls.observe(call, now: now) {
        case .none: break
        case let .set(e): board.set(e); changed = true
        case .remove: board.remove(kind: .callCard, id: "call"); changed = true
        }
        if changed { await publish() }
    }

    private func startRounds(_ frame: GameReading.ImageFrame) {
        let gen = generation
        if options.cornersEnabled, !cornersRunning {
            cornersRunning = true
            Task { [reader] in
                let start = self.clock.nowMs
                let events = await reader.readCorners(frame)
                await self.cornersDone(events, frame: frame, start: start, generation: gen)
            }
        }
        if let phone, phoneGame {
            if !phoneRunning {
                phoneRunning = true
                Task {
                    let u = await phone.round(frame)
                    await self.phoneDone(u, generation: gen, round: true)
                }
            }
            Task {
                let u = await phone.trackPhone(frame)
                await self.phoneDone(u, generation: gen, round: false)
            }
        }
    }

    // MARK: Köşe turu

    private func cornersDone(_ events: [GameReading.Event], frame: GameReading.ImageFrame, start: Int, generation gen: Int) async {
        cornersRunning = false
        guard gen == generation, options.cornersEnabled else { return }
        let now = clock.nowMs
        let menuOpen = await reader.menuOpen
        var changed = false
        var cornerLines: [GameReading.Line] = []
        for e in events {
            switch e {
            case .menuOpened:
                await phone?.noteMenu(at: now)
            case let .corner(place, lines):
                cornerLines += lines
                changed = await observeCorner(place, lines: lines, menuOpen: menuOpen, now: now) || changed
            default: break
            }
        }
        if let phone, phoneGame, !cornerLines.isEmpty { await phone.noteLines(cornerLines, frame: frame) }

        // Menü araması bu turda yapıldıysa: oyun tanıma ve harita kartı.
        if await reader.lastMenuSearchAt >= start {
            let lines = await reader.lastMenuSearchLines
            if sense.observeScreen(lines.map(\.text)), let game = sense.current { onEvent(.screenGame(game)) }
            applyMap(await map.observe(lines, image: frame.cgImage, menuOpen: await reader.menuOpen))
            // Kart tek okumada kaybolursa TV'de tutulur; kalkması için kart bölgesinin görüntüsü değişmeli.
            var sources: [String: GameReading.Box] = [:]
            if let area = await map.shownArea { sources["map:kart"] = area }
            let mapLive = board.list.contains { $0.kind == .map } || sender.isShowing(.map)
            let pixels = phoneGame && mapLive ? GameReading.PhonePixels.from(frame.cgImage, width: 640, height: 360) : nil
            await publish(observed: [.map], pixels: pixels, sources: sources)
            await phone?.setMapCardShown(await mapCardShown())
        } else if !menuOpen, await mapCardShown() {
            applyMap(await map.menuClosed())
            await publish(drop: [.map])
            await phone?.setMapCardShown(await mapCardShown())
        }
        if changed { await publish() }
        await refresh()
    }

    private func observeCorner(_ place: GameReading.Corners.Place, lines raw: [GameReading.Line], menuOpen: Bool,
                               now: Int) async -> Bool {
        var lines = raw
        // Telefonun içindeki satırlar köşe ipucu sayılmaz.
        if let box = await phone?.phoneBox(withinMs: 3_000) {
            lines = lines.filter { l in l.box.map { !box.contains(x: $0.midX, y: ($0.top + $0.bottom) / 2) } ?? true }
        }
        let text = lines.isEmpty ? nil : lines.map(\.text).joined(separator: "\n")
        let kind: GameReading.ScreenElement.Kind = place == .topLeft ? .corner : .questStrip
        let id = place == .topLeft ? "top-left" : "quest"
        let step = place == .topLeft ? topLeft.observe(text, menuOpen: menuOpen, now: now)
            : quest.observe(text, menuOpen: menuOpen, now: now)
        switch step {
        case .none: return false
        case .remove:
            board.remove(kind: kind, id: id)
            return true
        case let .show(_, translation):
            guard let e = Self.cornerElement(place, lines: lines, translation: translation) else { return false }
            board.set(e)
            return true
        case let .translate(source):
            let gen = generation
            Task {
                let out = try? await self.translator.translate([source])
                await self.cornerTranslated(place, source: source, lines: lines, translation: out?.first, generation: gen)
            }
            return false
        }
    }

    private func cornerTranslated(_ place: GameReading.Corners.Place, source: String, lines: [GameReading.Line],
                                  translation: String?, generation gen: Int) async {
        guard gen == generation, let translation, !translation.isEmpty else { return }
        if place == .topLeft {
            // Çeviri sürerken menü açıldıysa sol üst sonucu atılır.
            if await reader.menuOpen { return }
            topLeft.translated(source: source, translation: translation)
            guard topLeft.shownSource == source else { return }
        } else {
            quest.translated(source: source, translation: translation)
            guard quest.shownSource == source else { return }
        }
        guard let e = Self.cornerElement(place, lines: lines, translation: translation) else { return }
        board.set(e)
        await publish()
    }

    static func cornerElement(_ place: GameReading.Corners.Place, lines: [GameReading.Line],
                              translation: String) -> GameReading.ScreenElement? {
        guard let box = GameReading.Box.union(lines.compactMap(\.box)) else { return nil }
        let heights = lines.compactMap { $0.box?.height }.sorted()
        let h = heights.isEmpty ? 0.03 : heights[heights.count / 2]
        if place == .topLeft {
            return GameReading.Corners.topLeftElement(box: box, lineHeight: h, header: nil, body: translation)
        }
        var style = GameReading.ScreenElement.Style(lineHeight: h)
        style.plain = true
        return GameReading.ScreenElement(kind: .questStrip, id: "quest", box: box, text: translation, style: style)
    }

    // MARK: İpucu ve kart çevirisi

    private func translateHint(_ line: GameReading.Line) {
        let gen = generation
        Task {
            let out = try? await self.translator.translate([line.text])
            await self.hintTranslated(line, translation: out?.first, generation: gen)
        }
    }

    private func hintTranslated(_ line: GameReading.Line, translation: String?, generation gen: Int) async {
        guard gen == generation else { return }
        guard let translation, !translation.isEmpty, let e = hints.translated(line, turkish: translation) else {
            hints.failed(line)
            return
        }
        board.set(e)
        await publish()
    }

    private func translateCard(_ card: GameReading.Cards.Card, body: String) {
        cardTranslating = true
        let gen = generation
        Task {
            let out: String?
            if let known = await self.translator.known(body) { out = known } else { out = try? await self.translator.translate([body]).first }
            await self.cardTranslated(card, body: body, translation: out, generation: gen)
        }
    }

    private func cardTranslated(_ card: GameReading.Cards.Card, body: String, translation: String?, generation gen: Int) async {
        cardTranslating = false
        guard gen == generation, let translation, !translation.isEmpty else { return }
        cards.translated(name: card.name, message: body, translation: translation)
        guard let e = GameReading.Cards.layout(card, translation: translation) else { return }
        board.set(e)
        await publish()
    }

    // MARK: Telefon ve harita

    private func phoneDone(_ u: GameReading.PhoneUpdate?, generation gen: Int, round: Bool) async {
        if round { phoneRunning = false }
        guard gen == generation, phoneGame, let u else { return }
        applyPhone(u)
        if u.phoneTextSeen, sense.notePhoneRead(), let game = sense.current { onEvent(.screenGame(game)) }
        if u.elements != nil { await publish() }
    }

    private func applyPhone(_ u: GameReading.PhoneUpdate) {
        guard let els = u.elements else { return }
        board.removeAll(kind: .phone)
        for e in els { board.set(e) }
    }

    /// Harita kartı TV'de mi (izleyicide ya da gönderici tutuyor)?
    private func mapCardShown() async -> Bool { await map.isShowing || sender.isHolding(.map) }

    private func applyMap(_ changes: [GameReading.MapCardWatcher.Change]) {
        for c in changes {
            switch c {
            case let .set(e): board.set(e)
            case .remove: board.remove(kind: .map, id: "kart")
            }
        }
    }

    // MARK: TV

    /// `observed`: bu turda okunan türler (harita kartı kaçırması yalnız bunlarda sayılır); `drop`: hemen kalkacak türler.
    private func publish(observed: Set<GameReading.ScreenElement.Kind> = [], pixels: GameReading.PhonePixels? = nil,
                         sources: [String: GameReading.Box] = [:], drop: Set<GameReading.ScreenElement.Kind> = []) async {
        guard let m = sender.update(board.list, nowMs: clock.nowMs, observed: observed, pixels: pixels,
                                    sources: sources, drop: drop) else { return }
        await deliver(m, refresh: false)
    }

    /// Değişmeyen ama ekranda duran öğeler TV'deki süre dolmadan yeniden gönderilir.
    private func refresh() async {
        guard let m = sender.refresh(nowMs: clock.nowMs) else { return }
        await deliver(m, refresh: true)
    }

    private func deliver(_ m: GameReading.ScreenItemSender.Message, refresh: Bool) async {
        screenMessages += 1
        switch m {
        case .clear:
            await send(.screenClear)
            if !refresh { onEvent(.elements([])) }
        case let .screen(list):
            await send(.screen(ScreenChannel.payload(list)))
            if !refresh { onEvent(.elements(list)) }
        }
    }

    /// TV yolu yeniden kuruldu: ekrandaki öğeler hemen yeniden gönderilir.
    func resend() async {
        sender.forgetSent()
        if !board.list.isEmpty { await publish() }
    }

    // MARK: Sıfırlama

    /// Kaynak koptu ya da çeviri durdu: her şey unutulur, TV'deki öğeler kalkar.
    func reset() async {
        generation += 1
        cornersRunning = false
        phoneRunning = false
        cardTranslating = false
        board.clear()
        topLeft = GameReading.CornerTracker(place: .topLeft, isTargetLanguage: options.isTargetLanguage)
        quest = GameReading.CornerTracker(place: .questStrip, isTargetLanguage: options.isTargetLanguage)
        hints = GameReading.Hints()
        cards = GameReading.CardPresenter()
        calls = GameReading.CallPresenter()
        _ = await map.menuClosed()
        if phoneGame, let phone {
            // Panel kalkar, telefon araması sürer.
            _ = await phone.setPhoneGame(false)
            _ = await phone.setPhoneGame(true)
        }
        if sender.reset() != nil {
            screenMessages += 1
            await send(.screenClear)
            onEvent(.elements([]))
        }
    }
}
