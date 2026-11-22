// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import NinoCore

/// Oturumdan arayüze giden olaylar (ana iş parçacığında AppState'e yazılır).
public enum SessionEvent: Sendable {
    /// Altyazı TV'ye (ve bilgisayardaki pencereye) gitti.
    case shown(LiveLine, id: Int)
    /// Ekrandaki altyazı kalktı.
    case cleared(id: Int?)
    /// Satır yalnız bu pakette bulundu (oyun tanıma oyu).
    case packVote(String)
    /// Okuma takıldı, hat sıfırlandı.
    case readerStuck
    /// Ara sıra son kare (ayarlardaki bölge önizlemesi; saniyede en çok bir).
    case frame(CGImageBox)
    /// Altyazı şeridi bu oyunda ilk kez öğrenildi.
    case stripLearned
    /// Bir okumanın süresi (ölçüm: `ocr`).
    case ocr(ms: Int)
    /// Satırın yolculuğu (yalnız yerel `altyazi.log`; ölçüme ve teşhise girmez).
    case trace(LineTrace)
    /// Son saniyede işlenen kare sayısı (saniyede bir; otomatik teşhis).
    case fps(Int)
}

/// Bir altyazı satırının okunmadan kalkana dek adımları; hepsi aynı satır numarasıyla (`id`) günlüğe yazılır.
public enum LineTrace: Sendable, Equatable {
    public enum ReadKind: String, Sendable { case new, updated, corrected, restored }
    public enum DropReason: String, Sendable {
        /// Daha yeni bir satır ekranda.
        case newerShown
        /// Satır ekrandan kalktı, çeviri geç kaldı.
        case late
        /// Yerine düzeltilmiş ya da uzamış okuma geçti.
        case superseded
        /// Çeviri yok ve satır ekranda değil.
        case noTranslation
        /// Satır zaten hedef dilde.
        case alreadyTarget
        /// Hat sıfırlandı (kopma, oyun değişti, durdurma).
        case reset
    }

    case read(id: Int, text: String, kind: ReadKind)
    case translated(id: Int, origin: LiveLine.Origin, ms: Int, text: String)
    case translationFailed(id: Int, ms: Int)
    case cleared(id: Int, shownMs: Int?)
    case dropped(id: Int, reason: DropReason)
    /// Okuma neden atlandı ya da yazı neden atıldı (oyun-okuma.md "Teşhis notları"; aynı neden art arda tek satır).
    case note(String)
}

/// `CGImage`'ı aktörler arasında taşımak için.
public struct CGImageBox: @unchecked Sendable {
    public let image: CGImage
    public init(_ image: CGImage) { self.image = image }
}

/// Bir çeviri oturumu: kare → okuma hattı (`GameReading.Reader`) → çeviri sırası → çevirmen → çıkış (`DisplayHub`).
///
/// Ana iş parçacığından bağımsızdır; sonuçları `onEvent` ile bildirir.
public actor SubtitleSession {
    public struct Options: Sendable {
        public var showSpeakerNames = true
        public var position: SubtitlePosition = .bottom
        /// Paketteki hazır çeviri (eşzamanlı; kütüphanenin anlık kopyası). `nil`: paket araması kapalı.
        public var packLookup: (@Sendable (String) -> String?)?
        /// Çeviri dili (kaybolan tuş simgesi yer tutucusunun yerine konması için).
        public var targetLanguage = "tr"
        /// "Zaten hedef dilde" denetimi.
        public var isTargetLanguage: @Sendable (String) -> Bool = GameReading.TranslationQueue.looksTurkish
        public init() {}
    }

    public let reader: GameReading.Reader
    private var translator: SubtitleTranslating
    private let output: DisplayOutput
    private let clock: GameReading.Clock
    private var options: Options
    private let onEvent: @Sendable (SessionEvent) -> Void

    private var queue: GameReading.TranslationQueue
    private var subtitles: [Int: GameReading.Subtitle] = [:]
    private var results: [Int: SessionTranslation] = [:]
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var shownID: Int?
    private var light: Double?
    private var lastFrameEvent = Int.min / 2
    private var framesSinceEvent = 0
    /// Son kare (buzlu zemin için).
    private var lastImage: CGImage?
    /// Altyazı dışındaki ekran öğeleri ve ek alanlar; nil ise hiçbiri okunmaz.
    public let overlays: ScreenOverlays?
    /// Bu oturumda gösterilen satır sayısı (testler ve sağlık özeti).
    public private(set) var shownCount = 0
    /// Günlük izi: çevirinin başladığı an, satırın gösterildiği an, ekrandan kalkan satırlar.
    private var translateStarted: [Int: Int] = [:]
    private var shownAt: [Int: Int] = [:]
    private var ended: Set<Int> = []
    private var failedIDs: Set<Int> = []
    private var lastShownLine: Int?
    private var resetting = false
    /// Teşhis notlarını günlük satırına çevirir (aynı neden art arda tek satır + özet).
    private var skipJournal = GameReading.SkipJournal()

    public init(reader: GameReading.Reader, translator: SubtitleTranslating, output: DisplayOutput,
                clock: GameReading.Clock, options: Options = Options(), overlays: ScreenOverlays? = nil,
                onEvent: @escaping @Sendable (SessionEvent) -> Void) {
        self.reader = reader
        self.overlays = overlays
        self.translator = translator
        self.output = output
        self.clock = clock
        self.options = options
        self.onEvent = onEvent
        self.queue = GameReading.TranslationQueue(isTargetLanguage: options.isTargetLanguage)
    }

    public func setTranslator(_ t: SubtitleTranslating) { translator = t }

    public func setOptions(_ o: Options) {
        options = o
        queue.isTargetLanguage = o.isTargetLanguage
    }

    public var currentTranslator: SubtitleTranslating { translator }

    // MARK: Kareler

    /// Akış bitene ya da görev iptal edilene kadar kareleri işler.
    public func run(_ frames: AsyncStream<Frame>) async {
        for await frame in frames {
            if Task.isCancelled { break }
            await process(frame.image)
        }
    }

    public func process(_ image: CGImage) async {
        let now = clock.nowMs
        framesSinceEvent += 1
        if now - lastFrameEvent >= 1_000 {
            let elapsed = now - lastFrameEvent
            if elapsed < 10_000 { onEvent(.fps(Int((Double(framesSinceEvent) * 1_000 / Double(elapsed)).rounded()))) }
            framesSinceEvent = 0
            lastFrameEvent = now
            onEvent(.frame(CGImageBox(image)))
        }
        lastImage = image
        let out = await reader.process(GameReading.ImageFrame(image))
        if let b = out.brightness { light = b }
        if out.stuck {
            onEvent(.readerStuck)
            await overlays?.reset()
        }
        if let ms = out.ocrMs { onEvent(.ocr(ms: ms)) }
        for line in skipJournal.observe(out.notes, now: clock.nowMs) { onEvent(.trace(.note(line))) }
        for e in out.events { await handle(e) }
        await perform(queue.tick(now: clock.nowMs))
        await overlays?.frame(image, events: out.events, skipped: out.skipped)
    }

    /// Kaynak koptu ya da oyun değişti: hat ve sıra sıfırlanır, TV temizlenir.
    public func reset() async {
        flushNotes()
        _ = await reader.reset()
        resetting = true
        await perform(queue.reset())
        resetting = false
        for (_, t) in tasks { t.cancel() }
        tasks = [:]
        subtitles = [:]
        results = [:]
        if let id = shownID { onEvent(.trace(.cleared(id: id, shownMs: shownAt[id].map { max(0, clock.nowMs - $0) }))) }
        shownID = nil
        translateStarted = [:]
        shownAt = [:]
        ended = []
        failedIDs = []
        try? await output.clear(id: nil)
        onEvent(.cleared(id: nil))
        await overlays?.reset()
    }

    /// Bekleyen çevirileri bırakır (durdurma).
    public func stop() async {
        flushNotes()
        if let id = shownID {
            traceCleared(id)
            shownID = nil
        }
        for (_, t) in tasks { t.cancel() }
        tasks = [:]
        _ = queue.reset()
        _ = await reader.reset()
        await overlays?.reset()
        await translator.flush()
    }

    private func flushNotes() {
        for line in skipJournal.flush() { onEvent(.trace(.note(line))) }
    }

    // MARK: Okuma olayları

    private func handle(_ e: GameReading.Event) async {
        let now = clock.nowMs
        switch e {
        case let .subtitleStarted(s), let .subtitleUpdated(s), let .subtitleCorrected(s):
            let kind: LineTrace.ReadKind = {
                if case .subtitleUpdated = e { return .updated }
                if case .subtitleCorrected = e { return .corrected }
                return .new
            }()
            onEvent(.trace(.read(id: s.id, text: s.text, kind: kind)))
            subtitles[s.id] = s
            let pack = options.packLookup?(s.text)
            await perform(queue.enqueue(s.request(packTranslation: pack), now: now))
        case let .subtitleRestored(s):
            onEvent(.trace(.read(id: s.id, text: s.text, kind: .restored)))
            subtitles[s.id] = s
            queue.lineRestored(id: s.id)
            if let r = results[s.id] { await show(id: s.id, text: r.text, durationMs: 0, replace: false, origin: r.origin) }
        case let .subtitleEnded(id):
            queue.lineRemoved(id: id, now: now)
            ended.insert(id)
            if shownID == id {
                shownID = nil
                try? await output.clear(id: id)
                traceCleared(id)
                onEvent(.cleared(id: id))
            }
        case .stripLearned:
            onEvent(.stripLearned)
        case .hints, .messageCard, .callCard, .corner, .menuOpened, .screenElements:
            // Ekran öğeleri `ScreenOverlays`'te (kare sonunda bütün olaylarla birlikte verilir).
            break
        }
        trim()
    }

    private func perform(_ actions: [GameReading.TranslationQueue.Action]) async {
        for a in actions {
            switch a {
            case let .translate(r):
                guard let sub = subtitles[r.id] else {
                    await perform(queue.finished(id: r.id, translation: nil, now: clock.nowMs))
                    continue
                }
                let translator = self.translator
                let showNames = options.showSpeakerNames
                let image = lastImage
                let language = options.targetLanguage
                translateStarted[r.id] = clock.nowMs
                tasks[r.id] = Task { [weak self] in
                    let result = await Self.translate(sub, with: translator, showSpeakerNames: showNames, image: image,
                                                      language: language, onVote: { id in self?.vote(id) })
                    guard !Task.isCancelled else { return }
                    await self?.finished(id: r.id, result: result)
                }
            case let .show(id, text, duration, replace, fromPack):
                if fromPack, results[id] == nil, translateStarted[id] == nil {
                    // Paketten doğrudan: çeviriye hiç gitmedi.
                    onEvent(.trace(.translated(id: id, origin: .pack, ms: 0, text: text)))
                }
                let origin: LiveLine.Origin = fromPack ? .pack : (results[id]?.origin ?? .engine)
                await show(id: id, text: text, durationMs: duration, replace: replace, origin: origin)
            case let .hide(id):
                if shownID == id { shownID = nil }
                try? await output.clear(id: id)
                traceCleared(id)
                onEvent(.cleared(id: id))
            case let .cancel(id):
                tasks.removeValue(forKey: id)?.cancel()
                translateStarted[id] = nil
                onEvent(.trace(.dropped(id: id, reason: resetting ? .reset : dropReason(id))))
            case let .failed(id):
                await reader.translationFailed(id: id)
            case let .dropped(id):
                onEvent(.trace(.dropped(id: id, reason: resetting ? .reset : dropReason(id))))
            case let .alreadyTarget(id):
                onEvent(.trace(.dropped(id: id, reason: .alreadyTarget)))
            case .proposeToPool:
                // LibraryTranslator pakette/havuzda olmayan satırı zaten kuyruğa öneriyor; iki kez önerilmesin.
                break
            }
        }
    }

    private nonisolated func vote(_ id: String) { onEvent(.packVote(id)) }

    private func finished(id: Int, result: SessionTranslation?) async {
        tasks[id] = nil
        let ms = translateStarted.removeValue(forKey: id).map { max(0, clock.nowMs - $0) } ?? 0
        if let result, !result.failed {
            onEvent(.trace(.translated(id: id, origin: result.origin, ms: ms, text: result.text)))
        } else {
            failedIDs.insert(id)
            onEvent(.trace(.translationFailed(id: id, ms: ms)))
        }
        if let result, !result.failed { results[id] = result }
        let text = (result?.failed ?? true) ? nil : result?.text
        await perform(queue.finished(id: id, translation: text, now: clock.nowMs))
    }

    private func show(id: Int, text: String, durationMs: Int, replace: Bool, origin: LiveLine.Origin) async {
        let sub = subtitles[id]
        // Buzlu zemin: altyazının arkasının bulanık hali (okuma-hatti.md §15), yalnız kutusu bilinen satırda.
        let cover: String? = sub?.box.flatMap { box in lastImage.flatMap { GameReading.Frost.background($0, box: box) } }
        // Konuşan adı ayrı gider (protokol.md `speaker`): TV adı ayrı çizer, `text` adsız.
        let split = Self.splitSpeaker(text, source: sub?.text, showSpeakerNames: options.showSpeakerNames)
        // Tuş simgeleri: yalnız metinde yer tutucusu kalanlar (protokol.md "Tuş simgeleri").
        let used = Set(IconPlaceholders.ids(in: split.text))
        let icons = (results[id]?.icons ?? []).filter { used.contains($0.id) }
        let payload = ShowPayload(id: id, text: split.text, source: sub?.text, position: options.position,
                                  durationMs: durationMs, box: sub?.box.map(NinoBox.init), paragraphs: split.text.contains("\n") ? true : nil,
                                  replace: replace ? true : nil, light: light, cover: cover, speaker: split.speaker,
                                  icons: icons.isEmpty ? nil : icons)
        shownID = id
        shownCount += 1
        shownAt[id] = clock.nowMs
        lastShownLine = max(lastShownLine ?? id, id)
        try? await output.show(payload)
        let latency = sub.map { max(0, clock.nowMs - $0.startedAt) }
        // Bilgisayardaki pencereler ve geçmiş yer tutucuyu okunur biçimde görür (`[→]`).
        let readable = IconPlaceholders.readable(text, icons: icons)
        onEvent(.shown(LiveLine(translated: readable, source: sub?.text ?? "", origin: origin, latencyMs: latency), id: id))
    }

    private func trim() {
        if ended.count > 64 { ended = Set(ended.sorted().suffix(32)) }
        if failedIDs.count > 64 { failedIDs = Set(failedIDs.sorted().suffix(32)) }
        guard subtitles.count > 32 else { return }
        for k in subtitles.keys.sorted().prefix(subtitles.count - 32) {
            subtitles[k] = nil
            results[k] = nil
            shownAt[k] = nil
        }
    }

    /// Ekrandaki satır kalktı: ne kadar göründüğüyle günlüğe.
    private func traceCleared(_ id: Int) {
        let ms = shownAt.removeValue(forKey: id).map { max(0, clock.nowMs - $0) }
        onEvent(.trace(.cleared(id: id, shownMs: ms)))
    }

    /// Bırakılan çevirinin en olası nedeni (sıranın kararını yeniden kurar).
    private func dropReason(_ id: Int) -> LineTrace.DropReason {
        if let last = lastShownLine, last > id { return .newerShown }
        if failedIDs.contains(id) { return .noTranslation }
        if ended.contains(id) { return .late }
        return .superseded
    }

    // MARK: Parça parça çeviri

    /// Konuşan etiketi ve tireler çevrilmez; cümleler ayrı çevrilir (oyun-okuma.md §10).
    static func translate(_ sub: GameReading.Subtitle, with translator: SubtitleTranslating, showSpeakerNames: Bool,
                          image: CGImage? = nil, language: String = "tr",
                          onVote: @Sendable (String) -> Void) async -> SessionTranslation? {
        // Satırda tuş simgesi varsa (`Hold [D-pad] to …`) satır yer tutucuyla tek parça çevrilir: `Hold ⟦T1⟧ to …`.
        // Önbellek/havuz anahtarı yer tutuculu metindir; simge ayrı taşınır.
        let prep = GameReading.ButtonIcons.prepare(iconLines(sub), image: image)
        if !prep.icons.isEmpty {
            if Task.isCancelled { return nil }
            let t = await translator.translate(prep.text)
            if let hit = await translator.takeDistinctiveHit() { onVote(hit) }
            guard !t.failed else { return SessionTranslation(text: sub.text, origin: .untranslated, failed: true) }
            let text = IconPlaceholders.ensure(t.text.trimmingCharacters(in: .whitespaces), ids: prep.ids, language: language)
            return SessionTranslation(text: text, origin: t.origin, icons: prep.icons)
        }
        var out = ""
        var origins: [LiveLine.Origin] = []
        var anyFailed = false
        var anyTranslated = false
        for part in sub.parts {
            if Task.isCancelled { return nil }
            guard part.translate else {
                if !showSpeakerNames, isSpeakerTag(part.text) { continue }
                out += part.text
                continue
            }
            let t = await translator.translate(part.text)
            if let hit = await translator.takeDistinctiveHit() { onVote(hit) }
            if t.failed {
                anyFailed = true
                out += part.text
            } else {
                anyTranslated = true
                out += t.text
                origins.append(t.origin)
            }
        }
        guard anyTranslated else { return SessionTranslation(text: sub.text, origin: .untranslated, failed: true) }
        _ = anyFailed
        let origin: LiveLine.Origin
        if origins.contains(.engine) { origin = .engine } else if origins.contains(.cache) { origin = .cache }
        else if origins.contains(.pool) { origin = .pool } else { origin = .pack }
        return SessionTranslation(text: out.trimmingCharacters(in: .whitespaces), origin: origin)
    }

    /// Gösterilecek çeviriden konuşan adını ayırır. Yalnız kaynakta tek bir baştaki etiket (`AD: …`) varsa ve çeviri
    /// o etiketle başlıyorsa; çok konuşanlı satırda adlar metinde kalır. Ayar kapalıysa ad hiç gönderilmez.
    static func splitSpeaker(_ text: String, source: String?, showSpeakerNames: Bool) -> (text: String, speaker: String?) {
        let lines = (source ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard showSpeakerNames, let name = lines.first.flatMap({ GameReading.Speaker.split($0)?.name }),
              lines.filter({ GameReading.Speaker.split($0) != nil }).count == 1 else { return (text, nil) }
        for sep in [":", "："] where text.hasPrefix(name + sep) {
            let body = text.dropFirst(name.count + sep.count).trimmingCharacters(in: .whitespaces)
            return body.contains(where: \.isLetter) ? (body, name) : (text, nil)
        }
        return (text, nil)
    }

    /// Altyazının satırları kutularıyla (kutu satır sayısına eşit bölünür; simge araması için).
    static func iconLines(_ sub: GameReading.Subtitle) -> [GameReading.Line] {
        let texts = sub.lines.isEmpty ? [sub.text] : sub.lines
        guard let b = sub.box, !texts.isEmpty else { return texts.map { GameReading.Line($0) } }
        let step = b.height / Double(texts.count)
        return texts.enumerated().map { i, t in
            GameReading.Line(t, box: GameReading.Box(left: b.left, top: b.top + Double(i) * step, right: b.right,
                                                     bottom: b.top + Double(i + 1) * step))
        }
    }

    static func isSpeakerTag(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespaces).last else { return false }
        return last == ":" || last == "："
    }
}

extension NinoBox {
    init(_ b: GameReading.Box) { self.init(left: b.left, top: b.top, right: b.right, bottom: b.bottom) }
}
