// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import NinoCore

/// Ekran öğelerinin oturuma bildirdikleri (ana iş parçacığında AppState'e yazılır).
public enum OverlayEvent: Sendable, Equatable {
    /// Ek alan çevirileri değişti (ekran dışı pencere ve yayın penceresi).
    case extraAreas([ExtraAreaText])
    /// Ekrandaki yazılardan oyun tanındı (bugün yalnız GTA 6).
    case screenGame(String)
    /// TV'ye giden ekran öğeleri değişti (yalnız yerel günlük; boş: kalktı).
    case elementsShown([GameReading.ScreenElement])
    /// Bir ek alanın çevirisi gösterildi ya da kalktı (boş metin).
    case regionShown(id: String, text: String)
}

/// Altyazı dışındaki her şey: köşeler, tuş ipuçları, mesaj/arama kartı, telefon paneli, harita kartı (`ElementsBoard`
/// → TV'ye `screen`/`screen-clear`) ve ek alanlar (`region`/`region-clear`).
///
/// Okumalar (köşe turu, telefon turu, ek alan turu) altyazı hattını beklemesin diye kendi görevlerinde döner; her biri
/// sürerken yenisi başlamaz (okuma-hatti.md §11–§14, telefon-harita.md "Giriş noktası").
public actor ScreenOverlays {
    public struct Options: Sendable {
        /// "Köşeleri çevir".
        public var cornersEnabled = true
        /// Sürekli okunan ek alanlar (en çok 3; kapalılar okunmaz).
        public var extraAreas: [GameReading.ExtraArea] = []
        public var isTargetLanguage: @Sendable (String) -> Bool = GameReading.TranslationQueue.looksTurkish
        public init() {}
    }

    /// TV'deki katmanın süresi (okuma-hatti.md §12.7).
    public static let layerDurationMs = GameReading.ScreenElement.layerDurationMs

    public nonisolated let phone: GameReading.PhoneWatcher?
    private let reader: GameReading.Reader
    private let map: GameReading.MapCardWatcher
    private let extra: GameReading.ExtraAreaReader
    private let translator: OverlayTranslator
    private let output: DisplayOutput
    private let clock: GameReading.Clock
    private var options: Options
    private let onEvent: @Sendable (OverlayEvent) -> Void

    private var board = GameReading.ElementsBoard()
    /// TV'ye giden liste (NinoCore `ScreenItemSender`): değişince gönderir, ekranda duran listeyi `layerDurationMs`
    /// dolmadan yeniler, harita kartını tek kaçırmada kaldırmaz (oyun-okuma.md "Ekran öğesi gönderici").
    private var sender = GameReading.ScreenItemSender()
    private var regions: [String: ExtraAreaText] = [:]
    private var topLeft: GameReading.CornerTracker
    private var quest: GameReading.CornerTracker
    /// Sağ üst bildirim (`Map updated`): menü araması satırlarından; okuma ~4,5 sn'de bir olduğundan kararlılık beklenmez.
    private var topRight = GameReading.CornerTracker(place: .menuSearch)
    private var hints = GameReading.Hints()
    private var cards = GameReading.CardPresenter()
    private var calls = GameReading.CallPresenter()
    private var sense = GameReading.GameSense()
    private var phoneGame = false
    /// Son uygulanan telefon güncellemesinin sıra numarası (tur ve takip görevleri sırasız biter).
    private var phoneSerial = 0
    /// Sıfırlamada artar; eski turların sonuçları atılır.
    private var generation = 0
    private var cornersRunning = false
    private var phoneRunning = false
    private var extraRunning = false
    private var cardTranslating = false
    /// Görev şeridinin son okumasındaki vurgulu (pembe) ifadeler ve son çevrilen şerit (vurgu çevirisi gelince yeniden kurulur).
    private var questAccent: [String] = []
    private var questShown: (lines: [GameReading.Line], translation: String, icons: [LinkIcon])?
    /// Vurgulu ifade → kendi çevirisi (çeviride karşılığını bulmak için; telefon-harita.md §11).
    private var accentTerms: [String: String] = [:]
    private var accentTranslating: Set<String> = []
    /// "Ekranı çevir" sürerken ya da sonucu ekrandayken köşe/ipucu katmanı TV'ye gitmez (sonucun yerine geçmesin).
    private var suspended = false
    /// Bu oturumda TV'ye giden `screen` / `region` mesajı sayısı (testler).
    public private(set) var screenMessages = 0
    public private(set) var regionMessages = 0

    public init(reader: GameReading.Reader, textReader: GameReading.TextReader, phone: GameReading.PhoneWatcher?,
                translator: OverlayTranslator, output: DisplayOutput, clock: GameReading.Clock, options: Options = Options(),
                onEvent: @escaping @Sendable (OverlayEvent) -> Void = { _ in }) {
        self.reader = reader
        self.phone = phone
        self.translator = translator
        self.output = output
        self.clock = clock
        self.options = options
        self.onEvent = onEvent
        self.map = GameReading.MapCardWatcher(translator: translator, clock: clock)
        self.extra = GameReading.ExtraAreaReader(ocr: GameReading.OCR(reader: textReader),
                                                 translator: translator, clock: clock)
        self.topLeft = GameReading.CornerTracker(place: .topLeft, isTargetLanguage: options.isTargetLanguage)
        self.quest = GameReading.CornerTracker(place: .questStrip, isTargetLanguage: options.isTargetLanguage)
    }

    public func setOptions(_ o: Options) async {
        let areasChanged = o.extraAreas != options.extraAreas
        options = o
        topLeft.isTargetLanguage = o.isTargetLanguage
        quest.isTargetLanguage = o.isTargetLanguage
        if !o.cornersEnabled {
            for kind in [GameReading.ScreenElement.Kind.corner, .questStrip] { board.removeAll(kind: kind) }
            await publish()
        }
        if areasChanged, o.extraAreas.isEmpty { await apply(await extra.reset()) }
    }

    /// Oyunun PS5'ten ya da kullanıcıdan bilinen adı (ekrandan tanıma bunu ezmez).
    public func setReportedGame(_ name: String?) { sense.reported = name }

    public var isPhoneGame: Bool { phoneGame }

    /// Ekranı çevir başladı / bitti. Bitince katman yeniden gönderilir (boşsa gönderilmez).
    public func setSuspended(_ on: Bool) async {
        guard on != suspended else { return }
        suspended = on
        if !on {
            sender.forgetSent()
            if !board.list.isEmpty { await publish() }
        }
    }

    public var isSuspended: Bool { suspended }

    /// Telefon oyunu kararı (telefon-harita.md §1.1). Kapanınca panel ve harita kartı kalkar.
    public func setPhoneGame(_ on: Bool) async {
        guard on != phoneGame else { return }
        phoneGame = on
        if let u = await phone?.setPhoneGame(on) { applyPhone(u) }
        applyMap(await map.setPhoneGame(on))
        await publish(drop: on ? [] : [.map, .phone])
    }

    public func switchLanguage(_ language: String) async {
        if let u = await phone?.switchLanguage(language) { applyPhone(u) }
        await publish(drop: [.phone])
    }

    // MARK: Kareler

    /// Ana okumanın her karesi: okuma olayları (ipucu, kart, arama) ve yan turların başlatılması. Hızlı döner.
    public func frame(_ image: CGImage, events: [GameReading.Event], skipped: Bool) async {
        let frame = GameReading.ImageFrame(image)
        if !skipped { await observe(events, image: image) }
        startRounds(frame)
        await refreshIfStale()
    }

    private func observe(_ events: [GameReading.Event], image: CGImage? = nil) async {
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

        // Tuş ipuçları (§13).
        let (next, removed) = hints.observe(hintLines, questLine: questLine, menuOpen: menuOpen)
        for k in removed { board.remove(kind: .hint, id: "hint:" + k); changed = true }
        if let line = next { translateHint(line, image: image) }

        // Mesaj kartı (§14.2).
        let phoneSeen = await phone?.phoneSeen(withinMs: 10_000) ?? false
        switch cards.observe(card, phoneSeenRecently: phoneSeen, now: now) {
        case .none: break
        case .remove:
            board.remove(kind: .messageCard, id: "card")
            changed = true
        case let .translate(body):
            if let card, !cardTranslating { translateCard(card, body: body) }
        }

        // Arama kartı (§10).
        switch calls.observe(call, now: now) {
        case .none: break
        case let .set(e): board.set(e); changed = true
        case .remove: board.remove(kind: .callCard, id: "call"); changed = true
        }
        if changed { await publish() }
    }

    private func startRounds(_ frame: GameReading.ImageFrame) {
        guard !suspended else { return }
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
        let areas = options.extraAreas
        if !extraRunning, !areas.isEmpty || !regions.isEmpty {
            extraRunning = true
            Task { [extra] in
                let changes = await extra.round(frame, areas: areas)
                await self.extraDone(changes, generation: gen)
            }
        }
    }

    // MARK: Köşe turu (§12)

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
                changed = await observeCorner(place, lines: lines, menuOpen: menuOpen, now: now, image: frame.cgImage) || changed
            default: break
            }
        }
        if let phone, phoneGame, !cornerLines.isEmpty { await phone.noteLines(cornerLines, frame: frame) }

        // Menü araması bu turda yapıldıysa: oyun tanıma ve harita kartı.
        if await reader.lastMenuSearchAt >= start {
            let lines = await reader.lastMenuSearchLines
            if sense.observeScreen(lines.map(\.text)), let game = sense.current { onEvent(.screenGame(game)) }
            // Kart başka kartla değişince eski kart çeviri beklenmeden kalkar (gönderici tutmaz); çeviri sonra.
            let quick = await map.see(lines, image: frame.cgImage, menuOpen: await reader.menuOpen)
            applyMap(quick.changes)
            if quick.switched, !board.list.contains(where: { $0.kind == .map }) { await publish(drop: [.map]) }
            applyMap(await map.finish())
            await observeNotice(lines, menuOpen: await reader.menuOpen, now: clock.nowMs)
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
        await refreshIfStale()
    }

    /// Bir köşenin okuması; değişiklik olduysa `true`.
    private func observeCorner(_ place: GameReading.Corners.Place, lines raw: [GameReading.Line], menuOpen: Bool,
                               now: Int, image: CGImage? = nil) async -> Bool {
        var lines = raw
        // Telefonun içindeki satırlar köşe ipucu sayılmaz.
        if let box = await phone?.phoneBox(withinMs: 3_000) {
            lines = lines.filter { l in l.box.map { !box.contains(x: $0.midX, y: ($0.top + $0.bottom) / 2) } ?? true }
        }
        // Menüler çevrilmez (okuma-hatti.md §12): menü bayrağı açıkken sol üst köşe boş sayılır; köşe okuması menü
        // tanınmadan önce aynı turda yapılmış olabilir (GTA 6 duraklatma menüsü "Map Game Store Help"). Görev şeridi
        // ve harita kartı bundan etkilenmez.
        if place == .topLeft, menuOpen { lines = [] }
        let text = lines.isEmpty ? nil : lines.map(\.text).joined(separator: "\n")
        let kind: GameReading.ScreenElement.Kind = place == .topLeft ? .corner : .questStrip
        let id = place == .topLeft ? "top-left" : "quest"
        let step = place == .topLeft ? topLeft.observe(text, menuOpen: menuOpen, now: now)
            : quest.observe(text, menuOpen: menuOpen, now: now)
        if place == .questStrip, let image, step != .none {
            questAccent = lines.flatMap { GameReading.Accent.phrases($0, image: image) }
        }
        // Satırdaki tuş simgeleri (`Hold [D-pad] to …`): çevirmene `⟦T1⟧` yer tutucusuyla gider, simge TV'ye ayrı
        // (protokol.md "Tuş simgeleri"). Kararlılık ham metinle ölçülür; simge yalnız çevirmeden/göstermeden önce aranır.
        let prep = step == .none || step == .remove ? nil : GameReading.ButtonIcons.prepare(lines, image: image)
        let icons = prep?.icons ?? []
        switch step {
        case .none: return false
        case .remove:
            board.remove(kind: kind, id: id)
            if place == .questStrip { questShown = nil }
            return true
        case let .show(_, remembered):
            let translation = withIcons(remembered, icons: icons)
            if place == .questStrip { return setQuest(lines: lines, translation: translation, icons: icons) }
            guard let e = Self.cornerElement(place, lines: lines, translation: translation, icons: icons) else { return false }
            board.set(e)
            return true
        case let .translate(source):
            let gen = generation
            let ask = icons.isEmpty ? source : (prep?.text ?? source)
            Task {
                let out = try? await self.translator.translate([ask])
                let translation = out?.first.map { self.withIcons($0, icons: icons) }
                await self.cornerTranslated(place, source: source, lines: lines, translation: translation, icons: icons,
                                            generation: gen)
            }
            return false
        }
    }

    /// Çeviride kaybolan `⟦T1⟧` yer tutucusu yerine konur (Türkçede `tuşu`nun yerine ya da ilk fiilin önüne).
    nonisolated func withIcons(_ translation: String, icons: [LinkIcon]) -> String {
        guard !icons.isEmpty else { return translation }
        return IconPlaceholders.ensure(translation, ids: icons.map(\.id), language: translator.targetLanguage)
    }

    private func cornerTranslated(_ place: GameReading.Corners.Place, source: String, lines: [GameReading.Line],
                                  translation: String?, icons: [LinkIcon] = [], generation gen: Int) async {
        guard gen == generation, let translation, !translation.isEmpty else { return }
        if place == .topLeft {
            // Çeviri sürerken menü açıldıysa sol üst sonucu atılır (§12.5 madde 10).
            if await reader.menuOpen { return }
            topLeft.translated(source: source, translation: translation)
            guard topLeft.shownSource == source else { return }
        } else {
            quest.translated(source: source, translation: translation)
            guard quest.shownSource == source else { return }
            if setQuest(lines: lines, translation: translation, icons: icons) { await publish() }
            return
        }
        guard let e = Self.cornerElement(place, lines: lines, translation: translation, icons: icons) else { return }
        board.set(e)
        await publish()
    }

    /// Görev şeridi öğesi: vurgulu ifadenin çevirisi biliniyorsa çeviride karşılığı `⟦…⟧` ile işaretlenir; bilinmiyorsa
    /// önce vurgusuz gösterilir, ifade ayrıca çevrilir ve öğe yeniden kurulur.
    @discardableResult
    private func setQuest(lines: [GameReading.Line], translation: String, icons: [LinkIcon] = []) -> Bool {
        questShown = (lines, translation, icons)
        var text = translation
        for phrase in questAccent {
            if let term = accentTerms[phrase] {
                if let marked = GameReading.Accent.mark(text, term: term) { text = marked }
            } else {
                translateAccent(phrase)
            }
        }
        guard let e = Self.cornerElement(.questStrip, lines: lines, translation: text, icons: icons) else { return false }
        board.set(e)
        return true
    }

    private func translateAccent(_ phrase: String) {
        guard !accentTranslating.contains(phrase) else { return }
        accentTranslating.insert(phrase)
        let gen = generation
        Task {
            let out = try? await self.translator.translate([phrase])
            await self.accentTranslated(phrase, translation: out?.first, generation: gen)
        }
    }

    private func accentTranslated(_ phrase: String, translation: String?, generation gen: Int) async {
        accentTranslating.remove(phrase)
        guard gen == generation, let translation, !translation.isEmpty else { return }
        accentTerms[phrase] = translation
        if accentTerms.count > 200 { accentTerms = [phrase: translation] }
        guard questAccent.contains(phrase), let shown = questShown else { return }
        if setQuest(lines: shown.lines, translation: shown.translation, icons: shown.icons) { await publish() }
    }

    static func cornerElement(_ place: GameReading.Corners.Place, lines: [GameReading.Line],
                              translation: String, icons: [LinkIcon] = []) -> GameReading.ScreenElement? {
        guard let box = GameReading.Box.union(lines.compactMap(\.box)) else { return nil }
        let h = median(lines.compactMap { $0.box?.height }) ?? 0.03
        // Yalnız metinde yer tutucusu kalan simgeler gider.
        let used = Set(IconPlaceholders.ids(in: translation))
        let icons = icons.filter { used.contains($0.id) }
        if place == .topLeft {
            var e = GameReading.Corners.topLeftElement(box: box, lineHeight: h, header: nil, body: translation)
            e.icons = icons
            return e
        }
        // `plain` değil: TV düz öğeyi kutu genişliğinde, opak ve ortalı çizer; çeviri orijinal şeridi tam örter
        // (`plain` öğe yazı kadar dar ve yarı saydamdı, "the docks" görünüyordu).
        let style = GameReading.ScreenElement.Style(lineHeight: h)
        return GameReading.ScreenElement(kind: .questStrip, id: "quest", box: box, text: translation, style: style, icons: icons)
    }

    // MARK: İpucu ve kart çevirisi

    private func translateHint(_ line: GameReading.Line, image: CGImage?) {
        let gen = generation
        // İpucundaki tuş simgesi de yer tutucuyla çevrilir (`Hold ⟦T1⟧ to …`).
        let prep = GameReading.ButtonIcons.prepare([line], image: image)
        Task {
            let out = try? await self.translator.translate([prep.icons.isEmpty ? line.text : prep.text])
            let translation = out?.first.map { self.withIcons($0, icons: prep.icons) }
            await self.hintTranslated(line, translation: translation, icons: prep.icons, generation: gen)
        }
    }

    private func hintTranslated(_ line: GameReading.Line, translation: String?, icons: [LinkIcon] = [],
                                generation gen: Int) async {
        guard gen == generation else { return }
        guard let translation, !translation.isEmpty, var e = hints.translated(line, turkish: translation) else {
            hints.failed(line)
            return
        }
        let used = Set(IconPlaceholders.ids(in: e.text))
        e.icons = icons.filter { used.contains($0.id) }
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
        if u.phoneTextSeen, sense.notePhoneRead(), let game = sense.current { onEvent(.screenGame(game)) }
        guard applyPhone(u) else { return }
        // Telefon kapandı / ekran türü değişti: hemen kalkar. Yalnız yeniden kurulum (kaydırma): gönderici kısa süre tutar.
        let gone = u.elements?.isEmpty == true && !u.mayHold
        await publish(drop: gone ? [.phone] : [])
    }

    /// Panel değişikliği tahtaya yazıldıysa `true`. Eski sıra numaralı (geç biten) güncelleme atılır.
    @discardableResult
    private func applyPhone(_ u: GameReading.PhoneUpdate) -> Bool {
        guard let els = u.elements else { return false }
        if u.serial != 0 {
            guard u.serial > phoneSerial else { return false }
            phoneSerial = u.serial
        }
        board.removeAll(kind: .phone)
        for e in els { board.set(e) }
        return true
    }

    /// Sağ üst bildirimi çevirir ve yazının üstüne koyar; menü açıkken (menü çevrilmez) ya da bildirim gidince kalkar.
    private func observeNotice(_ lines: [GameReading.Line], menuOpen: Bool, now: Int) async {
        let notice = menuOpen ? nil : GameReading.Corners.topRightNotice(lines)
        // `menuOpen: true`: iki okuma arası ~4,5 sn; bildirim tek görülüşte çevrilir, bir ıskada kalkar.
        switch topRight.observe(notice?.text, menuOpen: true, now: now) {
        case .none: return
        case .remove:
            board.remove(kind: .corner, id: "top-right")
            await publish()
        case let .show(_, translation):
            guard let box = notice?.box else { return }
            board.set(GameReading.Corners.topRightElement(box: box, translation: translation))
            await publish()
        case let .translate(source):
            guard let box = notice?.box else { return }
            let gen = generation
            Task {
                let out = try? await self.translator.translate([source])
                await self.noticeTranslated(source: source, box: box, translation: out?.first, generation: gen)
            }
        }
    }

    private func noticeTranslated(source: String, box: GameReading.Box, translation: String?, generation gen: Int) async {
        guard gen == generation, let translation, !translation.isEmpty else { return }
        topRight.translated(source: source, translation: translation)
        guard topRight.shownSource == source, !(await reader.menuOpen) else { return }
        board.set(GameReading.Corners.topRightElement(box: box, translation: translation))
        await publish()
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

    // MARK: Ek alanlar (§11)

    private func extraDone(_ changes: [GameReading.ExtraAreaReader.Change], generation gen: Int) async {
        extraRunning = false
        guard gen == generation else { return }
        await apply(changes)
    }

    private func apply(_ changes: [GameReading.ExtraAreaReader.Change]) async {
        guard !changes.isEmpty else { return }
        for c in changes {
            switch c {
            case let .show(e):
                regions[e.id] = ExtraAreaText(id: e.id, text: e.text, alignment: Self.alignment(e.box))
                regionMessages += 1
                try? await output.send(.region(RegionPayload(id: e.id, text: e.text, box: NinoBox(e.box),
                                                             line: e.style.lineHeight)))
                onEvent(.regionShown(id: e.id, text: e.text))
            case let .remove(id):
                regions[id] = nil
                regionMessages += 1
                try? await output.send(.region(RegionPayload(id: id, text: "")))
                onEvent(.regionShown(id: id, text: ""))
            }
        }
        onEvent(.extraAreas(extraAreaTexts))
    }

    /// Ek alanların ekrandaki sırası: alanların ayardaki sırası.
    var extraAreaTexts: [ExtraAreaText] {
        let order = options.extraAreas.map(\.id)
        return regions.values.sorted { (order.firstIndex(of: $0.id) ?? 99, $0.id) < (order.firstIndex(of: $1.id) ?? 99, $1.id) }
    }

    static func alignment(_ b: GameReading.Box) -> ExtraAreaText.Alignment {
        b.midX < 0.4 ? .leading : (b.midX > 0.6 ? .trailing : .center)
    }

    // MARK: TV

    /// Liste değiştiyse TV'ye: boşsa `screen-clear`, değilse bütün liste (`overlay`, 120 sn).
    /// `observed`: bu turda okunan türler (harita kartı kaçırması yalnız bunlarda sayılır); `drop`: hemen kalkacak türler.
    private func publish(observed: Set<GameReading.ScreenElement.Kind> = [], pixels: GameReading.PhonePixels? = nil,
                         sources: [String: GameReading.Box] = [:], drop: Set<GameReading.ScreenElement.Kind> = []) async {
        guard !suspended else { return }
        guard let m = sender.update(board.list, nowMs: clock.nowMs, observed: observed, pixels: pixels,
                                    sources: sources, drop: drop) else { return }
        await deliver(m, refresh: false)
    }

    /// Değişmeyen ama ekranda duran öğeleri, TV'deki süre dolmadan yeniden gönderir.
    private func refreshIfStale() async {
        guard !suspended, let m = sender.refresh(nowMs: clock.nowMs) else { return }
        await deliver(m, refresh: true)
    }

    private func deliver(_ m: GameReading.ScreenItemSender.Message, refresh: Bool) async {
        screenMessages += 1
        switch m {
        case .clear:
            try? await output.send(.screenClear)
            if !refresh { onEvent(.elementsShown([])) }
        case let .screen(list):
            try? await output.send(.screen(Self.payload(list)))
            if !refresh { onEvent(.elementsShown(list)) }
        }
    }

    public var elements: [GameReading.ScreenElement] { board.list }

    static func payload(_ list: [GameReading.ScreenElement]) -> ScreenPayload {
        ScreenPayload(items: list.map(item), durationMs: layerDurationMs, overlay: true)
    }

    /// Öğe biçimi → protokol bayrakları (NinoCore docs/tarif/protokol.md "screen").
    static func item(_ e: GameReading.ScreenElement) -> ScreenItem {
        let s = e.style
        return ScreenItem(box: NinoBox(e.box), text: e.text, line: s.lineHeight,
                          paragraphs: e.text.contains("\n") ? true : nil,
                          plain: s.plain ? true : nil, italic: s.italic ? true : nil,
                          fill: s.background, ink: s.textColor,
                          angle: abs(s.angle) >= 0.3 ? s.angle : nil,
                          alpha: s.opacity < 1 ? s.opacity : nil,
                          side: s.bubble ? true : nil, frost: s.frosted ? true : nil,
                          backdrop: s.backdrop ? true : nil, card: s.card ? true : nil,
                          icons: e.icons.isEmpty ? nil : e.icons)
    }

    // MARK: Sıfırlama

    /// Kaynak koptu, oyun değişti ya da çeviri durdu: her şey unutulur, TV'deki örtüler ve kutular kalkar.
    public func reset() async {
        generation += 1
        cornersRunning = false
        extraRunning = false
        phoneRunning = false
        cardTranslating = false
        questAccent = []
        questShown = nil
        accentTranslating = []
        let hadElements = sender.reset() != nil
        let hadRegions = !regions.isEmpty
        board.clear()
        topLeft = GameReading.CornerTracker(place: .topLeft, isTargetLanguage: options.isTargetLanguage)
        quest = GameReading.CornerTracker(place: .questStrip, isTargetLanguage: options.isTargetLanguage)
        topRight = GameReading.CornerTracker(place: .menuSearch, isTargetLanguage: options.isTargetLanguage)
        hints = GameReading.Hints()
        cards = GameReading.CardPresenter()
        calls = GameReading.CallPresenter()
        _ = await extra.reset()
        _ = await map.menuClosed()
        if phoneGame, let phone {
            // Panel kalkar, telefon araması sürer.
            _ = await phone.setPhoneGame(false)
            _ = await phone.setPhoneGame(true)
        }
        regions = [:]
        if hadElements { try? await output.send(.screenClear) }
        if hadRegions {
            try? await output.send(.regionClear)
            onEvent(.extraAreas([]))
        }
    }
}

func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let s = values.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}
