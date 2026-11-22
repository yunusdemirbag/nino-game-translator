// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Observation
import SwiftUI

/// Ekran dışı ve yayın penceresindeki satır yığını (ana-ekran.md §11.3): en çok üç satır.
/// Yeni satır öncekinden 1,5 sn içinde gelirse önceki üstte kalır; üstteki satır 1,5 sn tam görünür,
/// sonra 0,4 sn'de söner. Hiçbir satır, yerini yeni satır almadıkça 1,2 sn'den kısa görünmez.
@MainActor
@Observable
public final class SubtitleStack {
    public struct StackedLine: Identifiable, Equatable {
        public let id: UUID
        public let text: String
        public let arrived: Date
        /// 0 güncel, 1 önceki, 2 iki önceki.
        public var rank: Int
        public var fading: Bool
    }

    public private(set) var visibleLines: [StackedLine] = []
    private var lastArrival: Date?

    public init() {}

    /// Opaklık: güncel 1, önceki 0,6, iki önceki 0,45; sönerken 0.
    public static func opacity(for entry: StackedLine) -> Double {
        if entry.fading { return 0 }
        switch entry.rank {
        case 0: return 1
        case 1: return 0.6
        default: return 0.45
        }
    }

    /// Yeni satır geldi (aynı metin tekrar gelirse yok sayılır).
    public func push(_ text: String, stackPrevious: Bool, now: Date = Date()) {
        guard visibleLines.first(where: { $0.rank == 0 })?.text != text else { return }
        let keep = stackPrevious && lastArrival.map { now.timeIntervalSince($0) <= 1.5 } == true
        lastArrival = now
        if keep {
            visibleLines = visibleLines.compactMap { entry in
                var entry = entry
                entry.rank += 1
                return entry.rank <= 2 ? entry : nil
            }
        } else {
            visibleLines.removeAll()
        }
        visibleLines.append(StackedLine(id: UUID(), text: text, arrived: now, rank: 0, fading: false))
        scheduleFade()
    }

    /// Satır kalktı (çeviri durdu ya da ekran boşaldı); en az 1,2 sn görünmüş olmalı.
    public func clear(now: Date = Date()) {
        guard let current = visibleLines.first(where: { $0.rank == 0 }) else { return }
        let wait = max(0, 1.2 - now.timeIntervalSince(current.arrived))
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, self.visibleLines.contains(where: { $0.id == current.id && $0.rank == 0 }) else { return }
            withAnimation(.linear(duration: 0.4)) { self.visibleLines.removeAll() }
        }
    }

    /// Örnek satır (ayar kipinde satır yokken).
    public func showSample(_ text: String) {
        visibleLines = [StackedLine(id: UUID(), text: text, arrived: Date(), rank: 0, fading: false)]
    }

    private func scheduleFade() {
        let stacked = visibleLines.filter { $0.rank > 0 }.map(\.id)
        guard !stacked.isEmpty else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self else { return }
            withAnimation(.linear(duration: 0.4)) {
                for index in self.visibleLines.indices where stacked.contains(self.visibleLines[index].id) {
                    self.visibleLines[index].fading = true
                }
            }
            try? await Task.sleep(for: .seconds(0.4))
            self.visibleLines.removeAll { stacked.contains($0.id) && $0.fading }
        }
    }
}
