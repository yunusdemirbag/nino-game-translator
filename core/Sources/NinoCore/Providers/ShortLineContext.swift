// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Kısa cümleyi (`Boy!`, `Do it.`) önceki cümleyle birlikte çevirme kuralı.
public enum ShortLineContext {
    public static let marker = "***"

    /// Harf içeren sözcük sayısı 1–3 mü?
    public static func isShort(_ sentence: String) -> Bool {
        let n = sentence.split(whereSeparator: \.isWhitespace).filter { $0.contains(where: \.isLetter) }.count
        return (1...3).contains(n)
    }

    /// `önceki *** kısa`
    public static func join(previous: String, short: String) -> String {
        "\(previous) \(marker) \(short)"
    }

    /// Çıktıdan `***` sonrasını alır; kurala uymazsa `nil` (kısa cümle tek başına çevrilir).
    public static func extract(_ output: String, source: String) -> String? {
        guard !output.contains("****") else { return nil }
        let parts = output.components(separatedBy: marker)
        guard parts.count == 2 else { return nil }
        let left = parts[0], right = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard left.contains(where: \.isLetter), right.contains(where: \.isLetter) else { return nil }
        guard right.utf16.count <= 3 * source.utf16.count + 20 else { return nil }
        return right
    }
}

/// Bir önceki gösterilen satırın son cümlesini 20 sn hatırlar.
public struct ShortLineMemory: Sendable {
    public let maxAge: TimeInterval
    private var last: (sentence: String, at: Date)?

    public init(maxAge: TimeInterval = 20) { self.maxAge = maxAge }

    /// Gösterilen satırın cümlelerini kaydeder.
    public mutating func shown(_ sentences: [String], at date: Date) {
        if let s = sentences.last(where: { $0.contains(where: \.isLetter) }) { last = (s, date) }
    }

    /// `index`. cümle için bağlam: aynı satırdaki önceki cümle, yoksa son gösterilen satırın son cümlesi.
    public func previous(for sentences: [String], index: Int, now: Date) -> String? {
        if index > 0 { return sentences[index - 1] }
        guard let last, now.timeIntervalSince(last.at) <= maxAge else { return nil }
        return last.sentence
    }
}
