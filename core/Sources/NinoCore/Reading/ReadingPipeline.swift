// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics

/// Sabitlenmiş bir altyazı.
public struct Subtitle: Equatable, Sendable {
    public let id: Int
    public let text: String
    public let sentences: [String]
    /// Çevrilmesi gereken yeni cümleler.
    public let newSentences: [String]
    /// Yakın zamanda görülmüş mü (çeviri önbellekten gelir).
    public let isRepeat: Bool
    /// Önceki altyazının uzantısı mı.
    public let isContinuation: Bool
    /// Sabitlendiği kare sırası.
    public let startFrame: Int
}

public enum SubtitleEvent: Equatable, Sendable {
    case started(Subtitle)
    case ended(Subtitle)
}

public struct ReadingConfiguration: Sendable {
    public var region: NormalizedRect
    public var filter: NoiseFilter
    public var stableFrames: Int
    public var missingFrames: Int
    public var similarity: Double
    public var splitter: SentenceSplitter
    /// Tekrar sayılmak için kaç son altyazı hatırlanır.
    public var historySize: Int

    public init(region: NormalizedRect = .defaultSubtitle,
                filter: NoiseFilter = NoiseFilter(),
                stableFrames: Int = 3,
                missingFrames: Int = 2,
                similarity: Double = 0.85,
                splitter: SentenceSplitter = SentenceSplitter(),
                historySize: Int = 32) {
        self.region = region
        self.filter = filter
        self.stableFrames = stableFrames
        self.missingFrames = missingFrames
        self.similarity = similarity
        self.splitter = splitter
        self.historySize = historySize
    }
}

public enum ReadingPipelineError: Error, Equatable {
    case noRecognizer
}

/// Kareden altyazı olayına kadar tüm okuma hattı. Tek iş parçacığında, sırayla kullanılır.
public final class ReadingPipeline {
    public let configuration: ReadingConfiguration
    private let recognizer: TextRecognizer?
    private var stabilizer: Stabilizer
    private var current: Subtitle?
    private var previous: Subtitle?
    private var history: [String] = []
    private var nextID = 1
    private var frame = 0
    private var lastEndFrame: Int?

    public init(recognizer: TextRecognizer? = nil, configuration: ReadingConfiguration = ReadingConfiguration()) {
        self.recognizer = recognizer
        self.configuration = configuration
        self.stabilizer = Stabilizer(stableFrames: configuration.stableFrames,
                                     missingFrames: configuration.missingFrames,
                                     similarity: configuration.similarity)
    }

    /// Bir kareyi okuyucuyla okur ve işler.
    public func process(_ image: CGImage) async throws -> [SubtitleEvent] {
        guard let recognizer else { throw ReadingPipelineError.noRecognizer }
        let lines = try await recognizer.recognize(image, in: configuration.region)
        return process(lines: lines)
    }

    /// Önceden okunmuş satırları bir kare olarak işler.
    public func process(lines: [RecognizedLine]) -> [SubtitleEvent] {
        frame += 1
        let text = configuration.filter.text(from: lines, region: configuration.region)
        return stabilizer.observe(text).compactMap(handle)
    }

    private func handle(_ event: StabilizerEvent) -> SubtitleEvent? {
        switch event {
        case .disappeared:
            guard let ended = current else { return nil }
            current = nil
            lastEndFrame = frame
            return .ended(ended)
        case let .stabilized(text, frame):
            let subtitle = makeSubtitle(text: text, frame: frame)
            previous = subtitle
            current = subtitle
            return .started(subtitle)
        }
    }

    private func makeSubtitle(text: String, frame: Int) -> Subtitle {
        let key = TextSimilarity.key(text)
        let sentences = configuration.splitter.split(text)
        var newSentences = sentences
        var isContinuation = false
        let window = configuration.stableFrames + configuration.missingFrames
        let recent = current != nil || lastEndFrame.map { frame - $0 <= window } == true
        if let previous, recent {
            let previousKey = TextSimilarity.key(previous.text)
            if !previousKey.isEmpty, key.count > previousKey.count, key.hasPrefix(previousKey) {
                isContinuation = true
                let seen = Set(previous.sentences.map(TextSimilarity.key))
                newSentences = sentences.filter { !seen.contains(TextSimilarity.key($0)) }
            }
        }
        let isRepeat = history.contains { TextSimilarity.isSame($0, key, threshold: configuration.similarity) }
        history.append(key)
        if history.count > configuration.historySize { history.removeFirst(history.count - configuration.historySize) }
        defer { nextID += 1 }
        return Subtitle(id: nextID, text: text, sentences: sentences, newSentences: newSentences,
                        isRepeat: isRepeat, isContinuation: isContinuation, startFrame: frame)
    }
}
