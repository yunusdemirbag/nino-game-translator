// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// MARK: - Yalnız altyazı (oyun-okuma.md "Yalnız altyazı")

extension GameReading.Filters {
    /// "Yalnız altyazıyı çevir" açıkken ana bloğa karışan görev, ipucu, sekme ve menü satırlarını atar.
    /// Kurallar dil bağımsızdır: konum, simge/tuş ve satırın biçimi. Konuşan etiketli satırlar korunur.
    public enum SubtitlesOnly {
        /// Altyazı ekranın ortasındadır: satırın ortası kare ortasına bundan uzaksa altyazı değildir.
        public static let centerTolerance = 0.15
        /// Öğrenilen şeridin üstünden bu kadar yukarıda biten satır altyazı değildir (kare oranı).
        public static let aboveStripMargin = 0.08

        /// Satırın neden atıldığı (teşhis günlüğü).
        public enum Drop: String, Equatable, Hashable, Sendable {
            case button, icon, offCenter, aboveStrip, tabLike

            public var label: String {
                switch self {
                case .button: return "tuş ipucu"
                case .icon: return "simgeli satır"
                case .offCenter: return "ortada değil"
                case .aboveStrip: return "şeridin üstünde"
                case .tabLike: return "sekme/menü"
                }
            }
        }

        /// Satırları süzer. `area` okunan alan; `strip` öğrenilen altyazı şeridi (kare oranı).
        public static func filter(_ lines: [GameReading.Line], area: GameReading.Box,
                                  strip: (top: Double, bottom: Double)?) -> [GameReading.Line] {
            filterWithDrops(lines, area: area, strip: strip).kept
        }

        /// `filter` ile aynı; atılan satırlar nedenleriyle birlikte döner.
        public static func filterWithDrops(_ lines: [GameReading.Line], area: GameReading.Box,
                                           strip: (top: Double, bottom: Double)?)
            -> (kept: [GameReading.Line], dropped: [(GameReading.Line, Drop)]) {
            var dropped: [(GameReading.Line, Drop)] = []
            // 1. Satır kuralları.
            let frames = lines.compactMap { $0.box?.mapped(into: area) }
            // Aynı sıradaki parçalar birlikte ölçülür (uzun satırın sol parçası tek başına ortada değildir).
            func row(_ b: GameReading.Box) -> GameReading.Box {
                frames.reduce(b) { u, o in
                    let overlap = min(o.bottom, b.bottom) - max(o.top, b.top)
                    return overlap >= 0.6 * min(o.height, b.height) ? u.union(o) : u
                }
            }
            func reason(_ l: GameReading.Line) -> Drop? {
                if hasButton(l.text) { return .button }
                if GameReading.Speaker.split(l.text) != nil { return nil }
                // Simgeli satır; cümle bitiren satırın başındaki işaret çoğu kez OCR kırıntısıdır (`• And shut … up.`).
                if startsWithIcon(l.text), !GameReading.Text.endsSentence(l.text) { return .icon }
                guard let b = l.box?.mapped(into: area) else { return nil }
                if abs(row(b).midX - 0.5) > centerTolerance { return .offCenter }
                if let s = strip, b.bottom < s.top - aboveStripMargin { return .aboveStrip }
                return nil
            }
            var kept: [GameReading.Line] = []
            for l in lines {
                if let r = reason(l) { dropped.append((l, r)) } else { kept.append(l) }
            }
            // 2. Blok kuralı: bütün satırları sekme/menü adı gibi olan blok atılır (devam satırı korunur).
            guard !kept.isEmpty, kept.allSatisfy({ $0.box != nil }) else { return (kept, dropped) }
            let drop = GameReading.Filters.blocks(kept).filter { $0.allSatisfy { isTabLike($0.text) } }.flatMap { $0 }
            dropped += drop.map { ($0, .tabLike) }
            kept.removeAll { drop.contains($0) }
            return (kept, dropped)
        }

        /// Kumanda tuşu adı ya da simgesi içeren satır (`Press ✕ to open`, `R2 Aim`, `[1] Map`).
        public static func hasButton(_ text: String) -> Bool {
            if text.contains(where: { GameReading.Filters.faceButtons.contains(String($0)) }) { return true }
            if text.range(of: #"\[\d\]"#, options: .regularExpression) != nil { return true }
            let parts = GameReading.Filters.hintParts(text)
            return parts.contains { GameReading.Filters.strongButtons.contains($0.uppercased()) || $0.uppercased() == "TOUCHPAD" || $0.uppercased() == "OPTIONS" }
        }

        /// Harf, rakam, tırnak, ayraç, tire, üç nokta ya da nota dışında bir işaretle başlayan satır (görev simgesi, madde imi).
        public static func startsWithIcon(_ text: String) -> Bool {
            guard let f = text.trimmingCharacters(in: .whitespaces).first else { return false }
            if f.isLetter || f.isNumber { return false }
            return !"\"'“”‘’«»„([¿¡-–—….*♪♫".contains(f)
        }

        /// Sekme/menü adı biçimi: 1–3 sözcük, cümle işareti yok, ya tamamı büyük harf ya da (≥ 2 sözcük) her sözcük
        /// büyük harfle başlıyor (`MAP`, `SKILLS`, `Main Quest`). Tek büyük harfli sözcük (`Hey`) sayılmaz.
        public static func isTabLike(_ text: String) -> Bool {
            let t = text.trimmingCharacters(in: .whitespaces)
            let words = GameReading.Text.words(t)
            guard (1...3).contains(words.count), t.contains(where: \.isLetter) else { return false }
            if t.contains(where: { ".,!?…:;\"“”".contains($0) }) { return false }
            if !GameReading.Text.hasLowercase(t) { return true }
            guard words.count >= 2 else { return false }
            return words.allSatisfy { w in w.first(where: \.isLetter).map(\.isUppercase) ?? true }
        }
    }
}
