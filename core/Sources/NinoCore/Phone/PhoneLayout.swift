// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// MARK: - Telefonun yanındaki Türkçe (tarif §8)

extension GameReading {
    /// Çevirisi olan bir telefon mesajı.
    public struct PhonePanelItem: Equatable, Sendable {
        public var source: String
        public var translation: String
        public var message: PhoneMessage
        public init(source: String, translation: String, message: PhoneMessage) {
            self.source = source; self.translation = translation; self.message = message
        }
    }

    public enum PhoneLayout {
        public static let fallbackBubble = RGB(233, 233, 236)
        public static let fallbackBackdrop = RGB(226, 228, 233)
        public static let fallbackAppGround = RGB(58, 58, 60)
        public static let darkInk = "#2c2c2e", lightInk = "#f5f5f7"
        public static let columnWidth = 0.27
        public static let gap = 0.035
        public static let pad = 0.012

        // MARK: §8.1

        /// Çeviri gösterilmeye değer mi?
        public static func worthShowing(source: String, translation: String) -> Bool {
            let t = Text.key(translation), s = Text.key(source)
            if t.isEmpty || t == s { return false }
            if Text.words(source).count == 1, translation.contains(source.trimmingCharacters(in: .whitespaces)) { return false }
            return true
        }

        /// Oyunun balon rengi: kenar (yazının solu) ve zemin (kutunun parlak %40'ı).
        public static func bubbleColor(_ box: Box, colors: PhoneColorSource?) -> RGB {
            guard let colors else { return fallbackBubble }
            var edge: RGB?
            for dx in [0.0045, 0.0027] {
                for f in [0.15, 0.35, 0.50, 0.65, 0.85] {
                    if let c = colors.color(x: box.left - dx, y: box.top + box.height * f), c.luma > (edge?.luma ?? -1) { edge = c }
                }
            }
            var inside: [RGB] = []
            var fy = 0.15
            while fy <= 0.85 + 1e-9 {
                var fx = 0.1
                while fx <= 0.9 + 1e-9 {
                    if let c = colors.color(x: box.left + box.width * fx, y: box.top + box.height * fy) { inside.append(c) }
                    fx += 0.1
                }
                fy += 0.1
            }
            var ground: RGB?
            if !inside.isEmpty {
                let bright = inside.sorted { $0.luma > $1.luma }.prefix(max(1, Int((Double(inside.count) * 0.4).rounded())))
                let sorted = bright.sorted { $0.luma < $1.luma }
                ground = sorted[sorted.count / 2]
            }
            if let g = ground, let e = edge, g.luma * 4 < e.luma * 3 { return e }
            return ground ?? edge ?? fallbackBubble
        }

        public static func ink(on fill: RGB) -> String { fill.luma > 140 ? darkInk : lightInk }

        /// Oyunun balonunun tam üstüne aynı görünümle yazılan çeviri (§8.1): kutu yazıdan x 0,0035, y 0,004 taşar,
        /// açı telefonun açısıdır. Gösterilmeye değmezse `nil`.
        public static func cover(_ item: PhonePanelItem, phone: PhoneLocation, colors: PhoneColorSource?, id: String) -> ScreenElement? {
            guard worthShowing(source: item.source, translation: item.translation) else { return nil }
            let fill = bubbleColor(item.message.box, colors: colors)
            var style = ScreenElement.Style(background: fill.hex, textColor: ink(on: fill), opacity: 0.95, lineHeight: item.message.lineHeight)
            style.angle = abs(phone.angle) >= 0.3 ? (phone.angle * 10).rounded() / 10 : 0
            return ScreenElement(kind: .phone, id: id, box: item.message.box.insetBy(dx: -0.0035, dy: -0.004), text: item.translation, style: style)
        }

        // MARK: Sarma

        /// Kelime kelime sarma: satır sayısı ve en uzun satırın harf sayısı.
        static func wrap(_ text: String, perLine: Int) -> (lines: Int, longest: Int) {
            var lines = 0, longest = 0, cur = 0
            for w in Text.words(text) {
                let n = w.count
                if cur == 0 { cur = n } else if cur + 1 + n <= perLine { cur += 1 + n } else { lines += 1; longest = max(longest, cur); cur = n }
                while cur > perLine { lines += 1; longest = perLine; cur -= perLine }
            }
            if cur > 0 { lines += 1; longest = max(longest, cur) }
            return (max(1, lines), longest)
        }

        static func column(for phone: PhoneLocation) -> (left: Double, right: Double, onLeft: Bool) {
            let onLeft = phone.centerX > 0.5
            var l: Double, r: Double
            if onLeft { r = phone.box.left - gap; l = r - columnWidth } else { l = phone.box.right + gap; r = l + columnWidth }
            l = max(0.02, l); r = min(0.98, r)
            return (l, r, onLeft)
        }

        // MARK: §8.2 Sohbet paneli

        /// Giden mesajlar (sağa yaslı, girintili ya da mavi).
        public static func outgoing(_ messages: [PhoneMessage], phone: PhoneLocation, fills: [RGB]) -> [Bool] {
            guard !messages.isEmpty else { return [] }
            let indents = messages.map { phone.indent($0.box) }
            let minIndent = indents.min()!, maxRight = messages.map { $0.box.right - phone.left(at: $0.box.midY) }.max()!
            let grayest = fills.map(\.blueness).min() ?? 0
            return messages.indices.map { i in
                let m = messages[i]
                if indents[i] > phone.screenWidth * 0.2 { return true }
                let right = m.box.right - phone.left(at: m.box.midY)
                if indents[i] - minIndent > phone.screenWidth * 0.1, maxRight - right < phone.screenWidth * 0.08 { return true }
                if i < fills.count, fills[i].blueness >= grayest + 14 { return true }
                return false
            }
        }

        public static func chat(_ items: [PhonePanelItem], header: String?, phone: PhoneLocation,
                                colors: PhoneColorSource?) -> [ScreenElement] {
            let col = column(for: phone)
            let inner = (col.right - col.left) - 2 * pad
            let maxBubble = inner * 0.82
            let fills = items.map { bubbleColor($0.message.box, colors: colors) }
            let out = outgoing(items.map(\.message), phone: phone, fills: fills)

            // Zemin rengi.
            var backdropSamples: [RGB] = []
            for (i, it) in items.enumerated() where !out[i] {
                let y = it.message.box.midY
                if let c = colors?.color(x: phone.right(at: y) - pad, y: y) { backdropSamples.append(c) }
            }
            var backdrop = backdropSamples.isEmpty ? fallbackBackdrop : backdropSamples.sorted { $0.luma < $1.luma }[backdropSamples.count / 2]
            let lightChat = backdrop.luma > 150
            if lightChat { backdrop = backdrop.toward(white: 0.6) }

            var bubbles: [ScreenElement] = []
            var base = 0.0
            for (i, it) in items.enumerated() where worthShowing(source: it.source, translation: it.translation) {
                let lh = min(max(it.message.lineHeight, 0.018), 0.028) * 0.97
                let letter = lh * 0.5 * 9 / 16
                let perLine = max(12, Int((maxBubble - 2 * pad) / letter))
                var w = wrap(it.translation, perLine: perLine)
                // Grup sohbetinde gönderen adı balonun ilk satırı (başlığı) olur.
                let sender = it.message.sender.flatMap { $0.isEmpty ? nil : $0 }
                if let sender { w = (w.lines + 1, max(w.longest, min(perLine, sender.count))) }
                let height = lh * Double(w.lines) * 1.3
                let top = min(max(it.message.box.top, base), 0.98 - height)
                base = top + height + lh * 0.6
                let width = min(maxBubble, Double(w.longest) * letter + pad + pad)
                let left = out[i] ? col.right - pad - width : col.left + pad
                var fill = fills[i]
                if lightChat { fill = out[i] ? RGB(min(255, fill.r * 0.86), min(255, fill.g * 0.93), min(255, fill.b * 1.04)) : fill.toward(white: 0.7) }
                var style = ScreenElement.Style(background: fill.hex, textColor: ink(on: fill), opacity: 0.95, bubble: true, lineHeight: lh)
                style.angle = 0
                bubbles.append(ScreenElement(kind: .phone, id: "", box: Box(left: left, top: top, right: left + width, bottom: top + height + lh * 0.3),
                                             text: sender.map { $0 + "\n" + it.translation } ?? it.translation, style: style))
            }
            guard !bubbles.isEmpty else { return [] }
            // Logo payı: en alttaki balon aşarsa hepsi yukarı.
            let limit = phone.box.bottom - pad - 0.03
            if let lowest = bubbles.map(\.box.bottom).max(), lowest > limit {
                let d = lowest - limit
                for i in bubbles.indices { bubbles[i].box.top -= d; bubbles[i].box.bottom -= d }
            }
            var els: [ScreenElement] = []
            var bs = ScreenElement.Style(background: backdrop.hex, textColor: nil, opacity: 0.6, lineHeight: 0.02)
            bs.backdrop = true
            els.append(ScreenElement(kind: .phone, id: "00-zemin", box: Box(left: col.left, top: phone.box.top, right: col.right, bottom: phone.box.bottom),
                                     text: "", style: bs))
            if let header, !header.isEmpty {
                let lh = min(max(items.map(\.message.lineHeight).max() ?? 0.02, 0.02), 0.028)
                var hs = ScreenElement.Style(textColor: ink(on: backdrop), opacity: 1, lineHeight: lh)
                hs.plain = true
                // Telefondaki gibi ortada: protokolde hizalama yok, kutu yazının tahmini genişliğinde ve sütunun ortasında.
                let letter = lh * 0.5 * 9 / 16
                let full = col.right - col.left - 2 * pad
                let width = min(full, Double(header.count) * letter * 1.15 + pad)
                let mid = (col.left + col.right) / 2
                els.append(ScreenElement(kind: .phone, id: "01-baslik",
                                         box: Box(left: mid - width / 2, top: phone.box.top + pad, right: mid + width / 2, bottom: phone.box.top + pad + lh * 1.3),
                                         text: header, style: hs))
            }
            for (i, b) in bubbles.enumerated() {
                var e = b
                e.id = String(format: "%02d", i + 2)
                els.append(e)
            }
            return els
        }

        // MARK: §8.3 Uygulama balonları

        /// Uygulamanın balon zemini ve yazı rengi.
        public static func appColors(_ items: [PhonePanelItem], phone: PhoneLocation, colors: PhoneColorSource?) -> (fill: RGB, ink: String) {
            guard let colors else { return (fallbackAppGround, "#ffffff") }
            func saturated(_ cs: [RGB]) -> RGB? {
                cs.filter { $0.spread > 60 && $0.high >= 120 }.max { $0.spread < $1.spread }
            }
            var head: [RGB] = []
            var y = phone.box.top - 0.04
            while y <= phone.box.top + 0.06 + 1e-9 {
                var f = 0.1
                while f <= 0.9 + 1e-9 { if let c = colors.color(x: phone.left(at: y) + phone.screenWidth * f, y: y) { head.append(c) }; f += 0.1 }
                y += 0.01
            }
            if let c = saturated(head) { return (c, "#ffffff") }
            var around: [RGB] = []
            for it in items {
                let b = it.message.box
                for p in [(b.left - 0.006, b.midY), (b.right + 0.006, b.midY), (b.midX, b.top - 0.006), (b.midX, b.bottom + 0.006)] {
                    if let c = colors.color(x: p.0, y: p.1) { around.append(c) }
                }
            }
            if let c = saturated(around) { return (c, "#ffffff") }
            // Beyaz haber uygulaması: kalabalık kova arka plan, ona en uzak renk yazı.
            var screen: [RGB] = []
            var sy = phone.box.top
            while sy <= phone.box.bottom {
                var f = 0.05
                while f <= 0.95 + 1e-9 { if let c = colors.color(x: phone.left(at: sy) + phone.screenWidth * f, y: sy) { screen.append(c) }; f += 0.1 }
                sy += 0.02
            }
            guard !screen.isEmpty else { return (fallbackAppGround, "#ffffff") }
            var buckets: [Int: [RGB]] = [:]
            for c in screen { buckets[Int(c.r) / 16 * 256 + Int(c.g) / 16 * 16 + Int(c.b) / 16, default: []].append(c) }
            let crowd = buckets.values.max { $0.count < $1.count }!
            let bg = RGB(crowd.map(\.r).reduce(0, +) / Double(crowd.count), crowd.map(\.g).reduce(0, +) / Double(crowd.count),
                         crowd.map(\.b).reduce(0, +) / Double(crowd.count))
            let lightBg = bg.luma > 140
            var inLines: [RGB] = []
            for it in items {
                let b = it.message.box
                var fy = 0.2
                while fy <= 0.8 + 1e-9 {
                    var fx = 0.05
                    while fx <= 0.95 + 1e-9 { if let c = colors.color(x: b.left + b.width * fx, y: b.top + b.height * fy) { inLines.append(c) }; fx += 0.05 }
                    fy += 0.2
                }
            }
            func dist(_ c: RGB) -> Double { abs(c.r - bg.r) + abs(c.g - bg.g) + abs(c.b - bg.b) }
            if let far = inLines.max(by: { dist($0) < dist($1) }), dist(far) >= 90 {
                let ink = lightBg ? RGB(far.r * 0.6, far.g * 0.6, far.b * 0.6) : far.toward(white: 0.5)
                return (bg, ink.hex)
            }
            return (bg, lightBg ? "#1c1c1e" : "#ffffff")
        }

        public static func app(_ items: [PhonePanelItem], phone: PhoneLocation, colors: PhoneColorSource?) -> [ScreenElement] {
            let shown = items.filter { worthShowing(source: $0.source, translation: $0.translation) }
            guard !shown.isEmpty else { return [] }
            let col = column(for: phone)
            let colWidth = col.right - col.left
            let (fill, inkColor) = appColors(shown, phone: phone, colors: colors)
            let lh = min(max(Text.median(shown.map { $0.message.lineHeight / 0.85 }) ?? 0.02, 0.018), 0.028) * 0.95
            let letter = lh * 0.5 * 9 / 16
            let perLine = max(8, Int((colWidth - 0.03) / (letter * 0.85)))
            var base = 0.0
            var els: [ScreenElement] = []
            for (i, it) in shown.enumerated() {
                let w = wrap(it.translation, perLine: perLine)
                let width: Double, height: Double, wantTop: Double
                if w.lines > 1 {
                    width = colWidth; height = lh * (1.22 * Double(w.lines) + 0.45); wantTop = it.message.box.top
                } else {
                    width = min(colWidth, Double(it.translation.count) * letter + 0.03); height = lh * 1.55
                    wantTop = it.message.box.midY - height / 2
                }
                let top = min(max(wantTop, base), 0.98 - height)
                base = top + height + lh * 0.4
                let left = col.onLeft ? col.right - width : col.left
                let style = ScreenElement.Style(background: fill.hex, textColor: inkColor, opacity: 0.95, bubble: true, lineHeight: lh)
                els.append(ScreenElement(kind: .phone, id: String(format: "%02d", i + 2), box: Box(left: left, top: top, right: left + width, bottom: top + height),
                                         text: it.translation, style: style))
            }
            return els
        }

        // MARK: §8.4 Kıpırdamama

        /// Yeni yerleşimde eski kutular korunabilir mi?
        public static func keepBoxes(old: [ScreenElement], oldSources: [String: String], new: [ScreenElement], newSources: [String: String],
                                     kind: PhoneScreenKind) -> [ScreenElement] {
            let (dx, dy) = kind == .chat ? (0.012, 0.015) : (0.04, 0.06)
            var result = new
            for i in result.indices where !result[i].style.backdrop {
                let e = result[i]
                if let o = old.first(where: { $0.text == e.text && oldSources[$0.id] == newSources[e.id]
                    && abs($0.box.left - e.box.left) < dx && abs($0.box.top - e.box.top) < dy }) {
                    result[i].box = o.box
                }
            }
            if kind == .app {
                let ot = old.map(\.text), nt = new.map(\.text)
                if ot == nt, zip(old, new).allSatisfy({ abs($0.box.left - $1.box.left) < 0.06 && abs($0.box.top - $1.box.top) < 0.06 }) { return old }
            }
            return result
        }
    }
}
