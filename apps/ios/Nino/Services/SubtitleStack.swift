// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Telefonda görünen altyazı satırları ve zamanlamaları.
///
/// - Yeni satır, önceki satır 1,5 sn'den kısa süre önce geldiyse onu üste iter (en çok iki eski satır); değilse eskiler
///   silinir.
/// - Üste itilen satır 1,5 sn görünür, 0,4 sn soluk kalır, sonra kalkar.
/// - "Temizle" gelince satır okunacak kadar görünmediyse o süre dolunca kalkar.
struct SubtitleStack: Equatable {
    struct Line: Identifiable, Equatable {
        let id: Int
        var text: String
        var source: String?
        let shownAt: Date
        /// Üste itildiği an.
        var pushedAt: Date?
        /// Temizlendiyse en geç kalkacağı an.
        var removeAt: Date?
        var fading = false
    }

    static let keepWindow: TimeInterval = 1.5
    static let fadeDuration: TimeInterval = 0.4
    static let maxOld = 2

    private(set) var all: [Line] = []

    /// Okunacak süre: min(5, 2 + uzunluk × 0,06) sn.
    static func readingTime(_ text: String) -> TimeInterval { min(5, 2 + Double(text.count) * 0.06) }

    mutating func show(id: Int, text: String, source: String?, now: Date = Date()) {
        if let i = all.firstIndex(where: { $0.id == id }) {
            all[i].text = text
            all[i].removeAt = nil
            return
        }
        if let last = all.last, now.timeIntervalSince(last.shownAt) < Self.keepWindow {
            for i in all.indices where all[i].pushedAt == nil { all[i].pushedAt = now }
            let olds = all.filter { $0.pushedAt != nil }
            if olds.count > Self.maxOld { all.removeFirst(olds.count - Self.maxOld) }
        } else {
            all.removeAll()
        }
        all.append(Line(id: id, text: text, source: source, shownAt: now))
    }

    mutating func clear(id: Int?, now: Date = Date()) {
        for i in all.indices where id == nil || all[i].id == id {
            let due = all[i].shownAt.addingTimeInterval(Self.readingTime(all[i].text))
            all[i].removeAt = max(now, due)
        }
        tick(now: now)
    }

    mutating func removeAll() { all.removeAll() }

    /// Süresi dolanları kaldırır, solanları işaretler.
    mutating func tick(now: Date = Date()) {
        all.removeAll { line in
            if let r = line.removeAt, r <= now { return true }
            if let p = line.pushedAt, now.timeIntervalSince(p) >= Self.keepWindow + Self.fadeDuration { return true }
            return false
        }
        for i in all.indices {
            if let p = all[i].pushedAt { all[i].fading = now.timeIntervalSince(p) >= Self.keepWindow }
        }
    }

    /// Bir sonraki değişim anı (zamanlayıcı için).
    func nextChange(after now: Date = Date()) -> Date? {
        var times: [Date] = []
        for line in all {
            if let r = line.removeAt { times.append(r) }
            if let p = line.pushedAt {
                times.append(p.addingTimeInterval(Self.keepWindow))
                times.append(p.addingTimeInterval(Self.keepWindow + Self.fadeDuration))
            }
        }
        return times.filter { $0 > now }.min()
    }

    var lines: [Line] { all }
    var last: Line? { all.last }
}

/// Uzun satırı en çok üç satıra dengeli böler. Konuşan adı ("ARTHUR: …") ilk satırda kalır.
enum BalancedWrap {
    static let limit = 42

    static func wrap(_ text: String) -> String {
        guard text.count > limit, !text.contains("\n") else { return text }
        let words = text.split(separator: " ").map(String.init)
        guard words.count > 1 else { return text }
        let lines = min(3, Int((Double(text.count) / Double(limit)).rounded(.up)))
        let target = Double(text.count) / Double(lines)
        var result: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : current + " " + word
            if !current.isEmpty, Double(candidate.count) > target, result.count < lines - 1,
               !(result.isEmpty && current.hasSuffix(":") && current.split(separator: " ").count == 1) {
                result.append(current)
                current = word
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { result.append(current) }
        return result.joined(separator: "\n")
    }
}
