// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation

/// Altyazının gideceği yer (TV).
public protocol SubtitleOutput: Sendable {
    func show(_ payload: ShowPayload) async throws
    func clear(id: Int?) async throws
}

extension NinoSender: SubtitleOutput {}

/// Motorun bildirdiği olaylar.
public enum EngineEvent: Equatable, Sendable {
    /// Okuma hattı yeni bir altyazı sabitledi.
    case subtitleStarted(Subtitle)
    /// Altyazı çevrildi; `text` gösterilecek Türkçe metindir.
    case translated(id: Int, text: String, translations: [Translation])
    /// Hiçbir cümle çevrilemedi; İngilizce metin gösterildi.
    case translationFailed(id: Int)
    /// Çeviri geldiğinde altyazı çoktan bitmişti ya da yenisi gelmişti.
    case dropped(id: Int)
    case shown(id: Int)
    case cleared(id: Int)
    case outputFailed(id: Int, message: String)
}

/// Uçtan uca akış: kare → okuma hattı → çeviri → TV.
///
/// Kareler çeviriyi beklemez: çeviri ayrı bir görevde yürür, okuma sürer.
/// Geç gelen çeviri, altyazı bitmişse ya da yenisi gösterilmişse atılır.
public actor NinoEngine {
    public struct Options: Sendable {
        public var position: SubtitlePosition
        public var sendSource: Bool
        /// Çeviri olmazsa İngilizce metni göster.
        public var showUntranslated: Bool

        public init(position: SubtitlePosition = .bottom, sendSource: Bool = true,
                    showUntranslated: Bool = true) {
            self.position = position
            self.sendSource = sendSource
            self.showUntranslated = showUntranslated
        }
    }

    public let options: Options
    private let pipeline: ReadingPipeline
    private let translator: Translator
    private var output: SubtitleOutput?

    private var onScreen: Subtitle?
    private var shownID: Int?
    private var latestStartedID = 0
    private var inFlight: [Int: Task<Void, Never>] = [:]
    private var continuations: [UUID: AsyncStream<EngineEvent>.Continuation] = [:]

    public init(pipeline: ReadingPipeline, translator: Translator, output: SubtitleOutput? = nil,
                options: Options = Options()) {
        self.pipeline = pipeline
        self.translator = translator
        self.output = output
        self.options = options
    }

    public func setOutput(_ output: SubtitleOutput?) { self.output = output }

    /// Olay akışı. Birden çok dinleyici olabilir.
    public func events() -> AsyncStream<EngineEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<EngineEvent>.makeStream()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.removeListener(id) } }
        return stream
    }

    private func removeListener(_ id: UUID) { continuations[id] = nil }

    private func emit(_ e: EngineEvent) {
        for c in continuations.values { c.yield(e) }
    }

    // MARK: Kareler

    /// Kaynak bitene ya da görev iptal edilene kadar kareleri işler.
    public func run(_ source: FrameSource) async {
        for await frame in source.frames() {
            if Task.isCancelled { break }
            do { try await process(frame.image) } catch { continue }
        }
        await waitUntilIdle()
        await translator.flush()
    }

    /// Çeviri önbelleğini diske yazar.
    public func flush() async {
        await translator.flush()
    }

    /// Bir kareyi okur ve işler.
    public func process(_ image: CGImage) async throws {
        let events = try await pipeline.process(image)
        for e in events { handle(e) }
    }

    /// Önceden okunmuş satırları bir kare olarak işler (testler, deneme).
    public func process(lines: [RecognizedLine]) {
        for e in pipeline.process(lines: lines) { handle(e) }
    }

    /// Süren tüm çevirilerin bitmesini bekler.
    public func waitUntilIdle() async {
        while let task = inFlight.values.first {
            await task.value
        }
    }

    // MARK: İç

    private func handle(_ event: SubtitleEvent) {
        switch event {
        case let .started(sub):
            latestStartedID = sub.id
            onScreen = sub
            emit(.subtitleStarted(sub))
            inFlight[sub.id] = Task { [weak self] in
                await self?.translateAndShow(sub)
            }
        case let .ended(sub):
            if onScreen?.id == sub.id { onScreen = nil }
            if shownID == sub.id {
                shownID = nil
                let output = output
                Task { [weak self] in
                    do {
                        try await output?.clear(id: sub.id)
                        await self?.emit(.cleared(id: sub.id))
                    } catch {
                        await self?.emit(.outputFailed(id: sub.id, message: "\(error)"))
                    }
                }
            }
        }
    }

    private func translateAndShow(_ sub: Subtitle) async {
        defer { inFlight[sub.id] = nil }
        let translations = await translator.translate(sub.sentences)
        let allFailed = !translations.isEmpty && translations.allSatisfy(\.failed)
        let text = translations.map(\.text).joined(separator: " ")
        if allFailed {
            emit(.translationFailed(id: sub.id))
            if !options.showUntranslated { return }
        } else {
            emit(.translated(id: sub.id, text: text, translations: translations))
        }

        // Altyazı bitmiş ya da yenisi başlamışsa gösterme.
        guard onScreen?.id == sub.id, sub.id == latestStartedID else {
            emit(.dropped(id: sub.id))
            return
        }
        let payload = ShowPayload(id: sub.id, text: text, source: options.sendSource ? sub.text : nil,
                                  position: options.position)
        do {
            try await output?.show(payload)
            emit(.shown(id: sub.id))
            if onScreen?.id == sub.id {
                shownID = sub.id
            } else {
                // Gönderirken altyazı bitti: hemen kaldır.
                try await output?.clear(id: sub.id)
                emit(.cleared(id: sub.id))
            }
        } catch {
            emit(.outputFailed(id: sub.id, message: "\(error)"))
        }
    }
}
