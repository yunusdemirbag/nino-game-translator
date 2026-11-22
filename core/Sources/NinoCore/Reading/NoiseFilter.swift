// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

/// Gürültüyü (tek harfler, simgeler, arayüz yazıları) atar ve kalan satırları birleştirir.
public struct NoiseFilter: Sendable {
    public var minConfidence: Float
    public var minLetters: Int
    public var ignoredPhrases: Set<String>

    public static let defaultIgnoredPhrases: Set<String> = [
        "options", "menu", "skip", "pause", "back", "select", "confirm",
        "continue", "loading", "settings", "map", "inventory",
    ]

    public init(minConfidence: Float = 0.40,
                minLetters: Int = 2,
                ignoredPhrases: Set<String> = NoiseFilter.defaultIgnoredPhrases) {
        self.minConfidence = minConfidence
        self.minLetters = minLetters
        self.ignoredPhrases = Set(ignoredPhrases.map(NoiseFilter.collapse))
    }

    public func isNoise(_ line: RecognizedLine) -> Bool {
        if line.confidence < minConfidence { return true }
        let visible = line.text.filter { !$0.isWhitespace }
        let letters = visible.filter(\.isLetter).count
        if letters < minLetters { return true }
        if letters * 2 < visible.count { return true }
        return ignoredPhrases.contains(NoiseFilter.collapse(line.text))
    }

    /// Bölge dışındaki ve gürültü olan satırları atar, kalanları yukarıdan aşağıya sıralar.
    public func clean(_ lines: [RecognizedLine], region: NormalizedRect) -> [RecognizedLine] {
        lines
            .filter { region.contains(x: $0.box.midX, y: $0.box.midY) && !isNoise($0) }
            .sorted { ($0.box.y, $0.box.x) < ($1.box.y, $1.box.x) }
    }

    /// Kalan satırları tek yazı yapar. Hiç satır kalmazsa `nil` döner (boş kare).
    public func text(from lines: [RecognizedLine], region: NormalizedRect) -> String? {
        let joined = NoiseFilter.squeeze(clean(lines, region: region).map(\.text).joined(separator: " "))
        return joined.isEmpty ? nil : joined
    }

    static func squeeze(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func collapse(_ text: String) -> String {
        squeeze(text).lowercased()
    }
}
