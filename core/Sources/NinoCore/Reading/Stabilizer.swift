// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

/// Sabitleyicinin çıkardığı olay.
public enum StabilizerEvent: Equatable, Sendable {
    /// Yazı yeterince kare boyunca sabit kaldı.
    case stabilized(text: String, frame: Int)
    /// Ekrandaki yazı kayboldu.
    case disappeared(text: String)
}

/// Her karede okunan yazıyı alır; yazı birkaç kare sabit kalınca bir kez
/// "sabitlendi", kaybolunca "kayboldu" der. Zaman kare sayısıyla ölçülür.
public struct Stabilizer: Sendable {
    public let stableFrames: Int
    public let missingFrames: Int
    public let similarity: Double

    private var frame = 0
    private var shown: String?
    private var shownMissing = 0
    private var candidate: String?
    private var candidateCount = 0
    private var emptyRun = 0

    public init(stableFrames: Int = 3, missingFrames: Int = 2, similarity: Double = 0.85) {
        precondition(stableFrames >= 1 && missingFrames >= 1)
        self.stableFrames = stableFrames
        self.missingFrames = missingFrames
        self.similarity = similarity
    }

    /// Bir kareyi işler. `nil` boş kare demektir.
    public mutating func observe(_ text: String?) -> [StabilizerEvent] {
        frame += 1
        var events: [StabilizerEvent] = []
        let text = text.flatMap { $0.isEmpty ? nil : $0 }

        // Ekrandaki altyazı hâlâ görünüyor mu?
        if let current = shown {
            if let text, similar(text, current) {
                shownMissing = 0
                candidate = nil
                candidateCount = 0
                emptyRun = 0
                return events
            }
            shownMissing += 1
            if shownMissing >= missingFrames {
                events.append(.disappeared(text: current))
                shown = nil
                shownMissing = 0
            }
        }

        // Aday.
        guard let text else {
            emptyRun += 1
            if emptyRun >= missingFrames {
                candidate = nil
                candidateCount = 0
            }
            return events
        }
        emptyRun = 0
        if let existing = candidate, similar(text, existing) {
            candidateCount += 1
        } else {
            candidateCount = 1
        }
        candidate = text

        if candidateCount >= stableFrames {
            if let current = shown {
                events.append(.disappeared(text: current))
            }
            events.append(.stabilized(text: text, frame: frame))
            shown = text
            shownMissing = 0
            candidate = nil
            candidateCount = 0
        }
        return events
    }

    private func similar(_ a: String, _ b: String) -> Bool {
        TextSimilarity.isSame(a, b, threshold: similarity)
    }
}
