// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import NinoCore

/// Okuma oturumunun modele bildirdikleri.
enum ReadingEvent: Sendable {
    /// Altyazı okundu (çeviriye gidiyor).
    case read(id: Int, text: String)
    /// Çeviri ekrana (ve TV'ye) gitti.
    case shown(id: Int, text: String, source: String, fromPack: Bool, latencyMs: Int?)
    case cleared(id: Int?)
    /// Bir okumanın süresi; `text`: okuma boş olmayan yazı döndürdü.
    case ocr(ms: Int, text: Bool)
    /// Okuma takıldı, hat sıfırlandı.
    case stuck
}

/// Bir çeviri oturumu: kare → oyun okuma hattı (`GameReading.Reader`) → çeviri sırası → çevirmen → çıkış.
/// Tarif: NinoCore docs/tarif/oyun-okuma.md. Altyazı dışındaki ekran öğeleri `ScreenLayer`'da.
actor ReadingSession {
    struct Options: Sendable {
        var showSpeakerNames = true
        var position: SubtitlePosition = .bottom
        /// Paketteki hazır çeviri (eşzamanlı). `nil`: paket araması kapalı.
        var packLookup: (@Sendable (String) -> String?)?
        var isTargetLanguage: @Sendable (String) -> Bool = GameReading.TranslationQueue.looksTurkish
    }

    let reader: GameReading.Reader
    let layer: ScreenLayer?
    private let translator: Translator
    private let output: SubtitleOutput
    private let clock: GameReading.Clock
    private let options: Options
    private let onEvent: @Sendable (ReadingEvent) -> Void

    private var queue: GameReading.TranslationQueue
    private var subtitles: [Int: GameReading.Subtitle] = [:]
    private var results: [Int: (text: String, fromPack: Bool)] = [:]
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var shownID: Int?
    private var light: Double?
    private var lastImage: CGImage?

    init(reader: GameReading.Reader, translator: Translator, output: SubtitleOutput, clock: GameReading.Clock,
         options: Options = Options(), layer: ScreenLayer? = nil, onEvent: @escaping @Sendable (ReadingEvent) -> Void) {
        self.reader = reader
        self.translator = translator
        self.output = output
        self.clock = clock
        self.options = options
        self.layer = layer
        self.onEvent = onEvent
        queue = GameReading.TranslationQueue(isTargetLanguage: options.isTargetLanguage)
    }

    // MARK: Kareler

    /// Akış bitene ya da görev iptal edilene kadar kareleri işler.
    func run(_ source: FrameSource) async {
        for await frame in source.frames() {
            if Task.isCancelled { break }
            await process(frame.image)
        }
    }

    func process(_ image: CGImage) async {
        lastImage = image
        let out = await reader.process(GameReading.ImageFrame(image))
        if let b = out.brightness { light = b }
        if out.stuck {
            onEvent(.stuck)
            await layer?.reset()
        }
        if let ms = out.ocrMs {
            let text = out.events.contains { if case .subtitleStarted = $0 { true } else { false } }
            onEvent(.ocr(ms: ms, text: text))
        }
        for e in out.events { await handle(e) }
        await perform(queue.tick(now: clock.nowMs))
        await layer?.frame(image, events: out.events, skipped: out.skipped)
    }

    /// Kaynak koptu: hat ve sıra sıfırlanır, ekran temizlenir.
    func reset() async {
        _ = await reader.reset()
        _ = queue.reset()
        for (_, t) in tasks { t.cancel() }
        tasks = [:]
        subtitles = [:]
        results = [:]
        shownID = nil
        try? await output.clear(id: nil)
        onEvent(.cleared(id: nil))
        await layer?.reset()
    }

    /// Durdurma: bekleyen çeviriler bırakılır, TV'deki öğeler kalkar.
    func stop() async {
        for (_, t) in tasks { t.cancel() }
        tasks = [:]
        _ = queue.reset()
        _ = await reader.reset()
        await layer?.reset()
    }

    // MARK: Okuma olayları

    private func handle(_ e: GameReading.Event) async {
        let now = clock.nowMs
        switch e {
        case let .subtitleStarted(s), let .subtitleUpdated(s), let .subtitleCorrected(s):
            onEvent(.read(id: s.id, text: s.text))
            subtitles[s.id] = s
            let pack = options.packLookup?(s.text)
            await perform(queue.enqueue(s.request(packTranslation: pack), now: now))
        case let .subtitleRestored(s):
            subtitles[s.id] = s
            queue.lineRestored(id: s.id)
            if let r = results[s.id] { await show(id: s.id, text: r.text, durationMs: 0, replace: false, fromPack: r.fromPack) }
        case let .subtitleEnded(id):
            queue.lineRemoved(id: id, now: now)
            if shownID == id {
                shownID = nil
                try? await output.clear(id: id)
                onEvent(.cleared(id: id))
            }
        default:
            // Ekran öğeleri `ScreenLayer`'da (kare sonunda bütün olaylarla birlikte verilir).
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
                let names = options.showSpeakerNames
                tasks[r.id] = Task { [weak self] in
                    let result = await Self.translate(sub, with: translator, showSpeakerNames: names)
                    guard !Task.isCancelled else { return }
                    await self?.finished(id: r.id, result: result)
                }
            case let .show(id, text, duration, replace, fromPack):
                await show(id: id, text: text, durationMs: duration, replace: replace, fromPack: fromPack || results[id]?.fromPack == true)
            case let .hide(id):
                if shownID == id { shownID = nil }
                try? await output.clear(id: id)
                onEvent(.cleared(id: id))
            case let .cancel(id):
                tasks.removeValue(forKey: id)?.cancel()
            case let .failed(id):
                await reader.translationFailed(id: id)
            case .dropped, .alreadyTarget, .proposeToPool:
                break
            }
        }
    }

    private func finished(id: Int, result: (text: String, fromPack: Bool)?) async {
        tasks[id] = nil
        if let result { results[id] = result }
        await perform(queue.finished(id: id, translation: result?.text, now: clock.nowMs))
    }

    private func show(id: Int, text: String, durationMs: Int, replace: Bool, fromPack: Bool) async {
        let sub = subtitles[id]
        // Buzlu zemin: altyazının arkasının bulanık hâli, yalnız kutusu bilinen satırda.
        let cover: String? = sub?.box.flatMap { box in lastImage.flatMap { GameReading.Frost.background($0, box: box) } }
        let payload = ShowPayload(id: id, text: text, source: sub?.text, position: options.position, durationMs: durationMs,
                                  box: sub?.box.map { NinoBox(left: $0.left, top: $0.top, right: $0.right, bottom: $0.bottom) },
                                  paragraphs: text.contains("\n") ? true : nil, replace: replace ? true : nil,
                                  light: light, cover: cover)
        shownID = id
        try? await output.show(payload)
        let latency = sub.map { max(0, clock.nowMs - $0.startedAt) }
        onEvent(.shown(id: id, text: text, source: sub?.text ?? "", fromPack: fromPack, latencyMs: latency))
    }

    private func trim() {
        guard subtitles.count > 32 else { return }
        for k in subtitles.keys.sorted().prefix(subtitles.count - 32) {
            subtitles[k] = nil
            results[k] = nil
        }
    }

    // MARK: Parça parça çeviri

    /// Konuşan etiketi ve tireler çevrilmez; cümleler ayrı çevrilir (oyun-okuma.md §10). Hiçbiri çevrilemezse nil.
    static func translate(_ sub: GameReading.Subtitle, with translator: Translator,
                          showSpeakerNames: Bool) async -> (text: String, fromPack: Bool)? {
        var out = ""
        var translated = false
        var allPack = true
        for part in sub.parts {
            if Task.isCancelled { return nil }
            guard part.translate else {
                if !showSpeakerNames, isSpeakerTag(part.text) { continue }
                out += part.text
                continue
            }
            let t = await translator.translate(part.text)
            if t.failed {
                out += part.text
            } else {
                translated = true
                out += t.text
                if t.origin != .pack { allPack = false }
            }
        }
        guard translated else { return nil }
        return (out.trimmingCharacters(in: .whitespaces), allPack)
    }

    static func isSpeakerTag(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespaces).last else { return false }
        return last == ":" || last == "："
    }
}
