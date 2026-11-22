// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
#if canImport(Vision)
import Vision
#endif

// MARK: - Telefonu karede bulma (tarif §3.1, §3.3, §3.4)

extension GameReading {
    public enum PhoneFinder {
        public static let gridWidth = 240, gridHeight = 135

        /// Ekran ve gövde noktası kuralları (açık ekran ya da koyu tema).
        struct Rules {
            var isScreen: (Int, Int) -> Bool        // (düşük, yayılma)
            var isFrame: (Int, Int) -> Bool
            var dark: Bool
        }

        static let light = Rules(isScreen: { low, spread in low >= 118 && spread <= 45 },
                                 isFrame: { low, _ in low < 90 }, dark: false)
        static let darkTheme = Rules(isScreen: { low, spread in low + spread <= 75 && spread <= 40 },
                                     isFrame: { low, spread in low + spread >= 85 }, dark: true)

        struct Strip { var y: Int; var start: Int; var length: Int }

        /// Açık ekran → kararmış ekran → koyu tema sırasıyla arar. `pixels` 240 × 135 olmalı (değilse küçültülür).
        public static func find(_ input: PhonePixels) -> PhoneLocation? {
            let p = input.resized(width: gridWidth, height: gridHeight)
            if let f = search(p, rules: light) { return f }
            if let k = dimGain(p), let f = search(p.scaled(k), rules: light) { return f }
            return search(p, rules: darkTheme)
        }

        /// Kararmış ekran: ortadaki düşük değerlerin %95'lik dilimi 40–117 ise `225 / dilim`.
        static func dimGain(_ p: PhonePixels) -> Double? {
            var lows: [Double] = []
            var y = Int(Double(p.height) * 0.10)
            while y < Int(Double(p.height) * 0.90) {
                var x = Int(Double(p.width) * 0.15)
                while x < Int(Double(p.width) * 0.85) { lows.append(Double(p.low(x, y))); x += 2 }
                y += 2
            }
            guard let q = Text.quantile(lows, 0.95), q >= 40, q <= 117 else { return nil }
            return 225 / q
        }

        // MARK: Şeritler

        static func strips(_ p: PhonePixels, rules: Rules) -> [[Strip]] {
            let minLen = Int(ceil(0.12 * Double(p.width))), maxLen = Int(floor(0.30 * Double(p.width)))
            var rows: [[Strip]] = Array(repeating: [], count: p.height)
            for y in 0..<p.height {
                var x = 0
                while x < p.width {
                    guard rules.isScreen(p.low(x, y), p.spread(x, y)) else { x += 1; continue }
                    // Beyaz parçalar ve aralarındaki ≤ 3 noktalık boşluklar.
                    var segments: [(Int, Int)] = []   // (başlangıç, bitiş hariç)
                    var segStart = x, cur = x
                    while true {
                        while cur < p.width, rules.isScreen(p.low(cur, y), p.spread(cur, y)) { cur += 1 }
                        segments.append((segStart, cur))
                        var gap = 0
                        while cur + gap < p.width, gap <= 3, !rules.isScreen(p.low(cur + gap, y), p.spread(cur + gap, y)) { gap += 1 }
                        if gap >= 1, gap <= 3, cur + gap < p.width { segStart = cur + gap; cur = segStart; continue }
                        break
                    }
                    x = cur + 1
                    // Uçlardaki ≤ 2 noktalık parlak kırıntı (ardından ≥ 2 beyaz olmayan nokta) atılır.
                    if segments.count >= 2, segments[0].1 - segments[0].0 <= 2, segments[1].0 - segments[0].1 >= 2 { segments.removeFirst() }
                    if segments.count >= 2, let last = segments.last, last.1 - last.0 <= 2,
                       last.0 - segments[segments.count - 2].1 >= 2 { segments.removeLast() }
                    let start = segments.first!.0, end = segments.last!.1
                    let len = end - start
                    if len >= minLen, len <= maxLen { rows[y].append(Strip(y: y, start: start, length: len)) }
                }
            }
            return rows
        }

        // MARK: Oylama ve sınama

        struct Candidate { var slope: Double; var intercept: Double; var width: Double; var votes: Int; var order: Int }

        static var slopes: [Double] {
            var s: [Double] = [0]
            for i in 1...15 { s.append(Double(i) * 0.02); s.append(-Double(i) * 0.02) }
            return s
        }

        static func search(_ p: PhonePixels, rules: Rules) -> PhoneLocation? {
            let rows = strips(p, rules: rules)
            let all = rows.flatMap { $0 }
            guard all.count >= 8 else { return nil }
            var candidates: [Candidate] = []
            for s in slopes {
                var votes: [Int: (count: Int, order: Int)] = [:]
                for st in all {
                    let ib = Int(floor((Double(st.start) - s * Double(st.y)) / 2)), wb = st.length / 2
                    let k = ib * 1_000 + wb
                    votes[k] = ((votes[k]?.count ?? 0) + 1, votes[k]?.order ?? votes.count)
                }
                let top = votes.filter { $0.value.count >= 8 }.sorted { ($0.value.count, -$0.value.order) > ($1.value.count, -$1.value.order) }.prefix(3)
                for (k, v) in top {
                    let ib = Int((Double(k) / 1_000).rounded(.down)), wb = k - ib * 1_000
                    candidates.append(Candidate(slope: s, intercept: Double(ib * 2) + 1, width: Double(wb * 2) + 1,
                                                votes: v.count, order: candidates.count))
                }
            }
            candidates.sort { ($0.votes, -$0.order) > ($1.votes, -$1.order) }
            for c in candidates.prefix(16) {
                if let f = test(c, rows: rows, pixels: p, rules: rules) { return f }
            }
            return nil
        }

        static func test(_ c: Candidate, rows: [[Strip]], pixels p: PhonePixels, rules: Rules) -> PhoneLocation? {
            // Uyan satırlar.
            var matched: [Strip] = []
            for (y, list) in rows.enumerated() {
                let expected = c.intercept + c.slope * Double(y)
                if let st = list.filter({ abs(Double($0.start) - expected) < 3.5 && abs(Double($0.length) - c.width) < 4 })
                    .min(by: { abs(Double($0.start) - expected) < abs(Double($1.start) - expected) }) {
                    matched.append(st)
                }
            }
            // Parçalar.
            var chunks: [[Strip]] = []
            for st in matched {
                if let last = chunks.last?.last, st.y - last.y <= 10 { chunks[chunks.count - 1].append(st) } else { chunks.append([st]) }
            }
            if chunks.count > 1 {
                chunks.removeAll { $0.first!.y == 0 || $0.last!.y == p.height - 1 }
            }
            guard let chunk = chunks.max(by: { $0.count < $1.count }), chunk.count >= 8 else { return nil }
            let intercept = Text.median(chunk.map { Double($0.start) - c.slope * Double($0.y) })!
            let width = Text.median(chunk.map { Double($0.length) })!
            func left(_ y: Int) -> Int { Int((intercept + c.slope * Double(y)).rounded()) }
            let w = Int(width.rounded())

            // Çerçeve.
            var darkBoth = 0, nonWhiteBoth = 0
            for st in chunk {
                let l = left(st.y), r = l + w - 1
                func side(_ xs: [Int], _ test: (Int, Int) -> Bool) -> Bool {
                    xs.contains { x in x >= 0 && x < p.width && test(p.low(x, st.y), p.spread(x, st.y)) }
                }
                let lx = (1...4).map { l - $0 }, rx = (1...4).map { r + $0 }
                if side(lx, rules.isFrame), side(rx, rules.isFrame) { darkBoth += 1 }
                let nonWhite: (Int, Int) -> Bool = { !rules.isScreen($0, $1) }
                if side(lx, nonWhite), side(rx, nonWhite) { nonWhiteBoth += 1 }
            }
            let n = Double(chunk.count)
            guard Double(darkBoth) >= 0.70 * n || (Double(nonWhiteBoth) >= 0.85 * n && Double(darkBoth) >= 0.35 * n) else { return nil }

            // Üst/alt kenar uzatma.
            func mostlyWhite(_ y: Int) -> Bool {
                guard y >= 0, y < p.height else { return false }
                let l = left(y)
                var white = 0, total = 0
                for x in max(0, l)..<min(p.width, l + w) { total += 1; if rules.isScreen(p.low(x, y), p.spread(x, y)) { white += 1 } }
                return total > 0 && white * 2 > total
            }
            var top = chunk.first!.y, bottom = chunk.last!.y
            while mostlyWhite(top - 1) { top -= 1 }
            while mostlyWhite(bottom + 1) { bottom += 1 }
            let rowsH = bottom - top + 1
            let H = Double(p.height), W = Double(p.width)
            let hFrac = Double(rowsH) / H, wFrac = width / W
            guard hFrac >= 0.38, hFrac <= 0.86, Double(matched.filter { $0.y >= top && $0.y <= bottom }.count) >= 0.25 * Double(rowsH) else { return nil }
            let aspect = (hFrac * 9) / (wFrac * 16)
            guard aspect >= 1.2, aspect <= 2.6 else { return nil }

            let topFrac = Double(top) / H, bottomFrac = Double(bottom + 1) / H
            let slopeFrac = c.slope * H / W
            let topLeft = (intercept + c.slope * Double(top)) / W
            let bottomLeft = topLeft + slopeFrac * (bottomFrac - topFrac)
            let mid = (topLeft + bottomLeft) / 2 + wFrac / 2
            guard mid >= 0.30, mid <= 0.80, topFrac >= 0.04, bottomFrac <= 0.96 || topFrac >= 0.2 else { return nil }
            if rules.dark {
                guard bottomFrac <= 0.96 else { return nil }
                // Koyu kıyafet elemesi: ekran satırlarının ≥ %15'inde parlak yazı noktaları.
                var texty = 0
                for y in top...bottom {
                    let l = left(y) + 2, r = left(y) + w - 2
                    guard r > l else { continue }
                    var bright = 0
                    for x in max(0, l)..<min(p.width, r) where p.low(x, y) + p.spread(x, y) >= 110 { bright += 1 }
                    if bright >= 2, Double(bright) <= 0.6 * Double(r - l) { texty += 1 }
                }
                guard Double(texty) >= 0.15 * Double(rowsH) else { return nil }
            }
            let box = Box(left: min(topLeft, bottomLeft), top: topFrac, right: max(topLeft, bottomLeft) + wFrac, bottom: bottomFrac)
            return PhoneLocation(box: box, topLeft: topLeft, slope: slopeFrac, screenWidth: wFrac, shapeOnly: false, dark: rules.dark)
        }

        // MARK: Ekran hâlâ orada mı (tarif §3.5)

        /// Son yerin 14 × 7 noktasının oranı: koyu ekranda koyu, açıkta beyaz ekran rengi.
        public static func screenShare(_ input: PhonePixels, at phone: PhoneLocation) -> Double {
            let p = input.resized(width: gridWidth, height: gridHeight)
            let rules = phone.dark ? darkTheme : light
            var hit = 0, total = 0
            for j in 0..<7 {
                let y = phone.box.top + phone.box.height * (Double(j) + 0.5) / 7
                for i in 0..<14 {
                    let x = phone.left(at: y) + phone.screenWidth * (Double(i) + 0.5) / 14
                    let px = Int(x * Double(p.width)), py = Int(y * Double(p.height))
                    guard px >= 0, py >= 0, px < p.width, py < p.height else { continue }
                    total += 1
                    if rules.isScreen(p.low(px, py), p.spread(px, py)) { hit += 1 }
                }
            }
            return total == 0 ? 0 : Double(hit) / Double(total)
        }
    }
}

// MARK: - Şekille bulma (tarif §3.2)

extension GameReading {
    /// Dört köşe (kare oranı, sol üstten): sol üst, sağ üst, sağ alt, sol alt.
    public struct PhoneQuad: Equatable, Sendable {
        public var topLeft: (x: Double, y: Double)
        public var topRight: (x: Double, y: Double)
        public var bottomRight: (x: Double, y: Double)
        public var bottomLeft: (x: Double, y: Double)
        public init(topLeft: (Double, Double), topRight: (Double, Double), bottomRight: (Double, Double), bottomLeft: (Double, Double)) {
            self.topLeft = topLeft; self.topRight = topRight; self.bottomRight = bottomRight; self.bottomLeft = bottomLeft
        }
        public static func == (a: PhoneQuad, b: PhoneQuad) -> Bool {
            a.topLeft == b.topLeft && a.topRight == b.topRight && a.bottomRight == b.bottomRight && a.bottomLeft == b.bottomLeft
        }
    }

    /// Dikdörtgen bulucusu (Vision; testlerde sahte).
    public protocol PhoneRectangleDetector: Sendable {
        func rectangles(in image: CGImage) -> [PhoneQuad]
    }

    #if canImport(Vision)
    public struct VisionRectangleDetector: PhoneRectangleDetector {
        public init() {}
        public func rectangles(in image: CGImage) -> [PhoneQuad] {
            let request = VNDetectRectanglesRequest()
            request.minimumAspectRatio = 0.35
            request.maximumAspectRatio = 0.75
            request.minimumSize = 0.25
            request.maximumObservations = 4
            request.quadratureTolerance = 25
            request.minimumConfidence = 0.6
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try? handler.perform([request])
            return (request.results ?? []).map { o in
                PhoneQuad(topLeft: (o.topLeft.x, 1 - o.topLeft.y), topRight: (o.topRight.x, 1 - o.topRight.y),
                          bottomRight: (o.bottomRight.x, 1 - o.bottomRight.y), bottomLeft: (o.bottomLeft.x, 1 - o.bottomLeft.y))
            }
        }
    }
    #endif
}

extension GameReading.PhoneFinder {
        /// Koyu çerçevesi görünmeyen telefon (altın/gümüş gövde). Yalnız telefon paneli kullanır.
        public static func findByShape(_ quads: [GameReading.PhoneQuad], pixels: GameReading.PhonePixels) -> GameReading.PhoneLocation? {
            let W = Double(pixels.width), H = Double(pixels.height)
            for q in quads {
                let topWidth = q.topRight.x - q.topLeft.x
                guard topWidth >= 0.12, topWidth <= 0.30 else { continue }
                let heightPx = ((q.bottomLeft.y - q.topLeft.y) + (q.bottomRight.y - q.topRight.y)) / 2 * H
                guard heightPx >= topWidth * W * 1.4 else { continue }
                let top = min(q.topLeft.y, q.topRight.y), bottom = max(q.bottomLeft.y, q.bottomRight.y)
                let slope = (q.bottomLeft.x - q.topLeft.x) / max(1e-6, q.bottomLeft.y - q.topLeft.y)
                let loc = GameReading.PhoneLocation(box: GameReading.Box(left: min(q.topLeft.x, q.bottomLeft.x), top: top,
                                                 right: max(q.topRight.x, q.bottomRight.x), bottom: bottom).clamped,
                                        topLeft: q.topLeft.x, slope: slope, screenWidth: topWidth, shapeOnly: true)
                // İçi: kenarlardan %10 / %12 içeride.
                var mid = 0, dark = 0, total = 0
                let y0 = top + (bottom - top) * 0.12, y1 = bottom - (bottom - top) * 0.12
                for py in max(0, Int(y0 * H))..<min(pixels.height, Int(y1 * H)) {
                    let y = Double(py) / H
                    let l = loc.left(at: y) + topWidth * 0.10, r = loc.left(at: y) + topWidth * 0.90
                    for px in max(0, Int(l * W))..<min(pixels.width, Int(r * W)) {
                        let c = pixels.color(px, py)
                        total += 1
                        if c.low >= 80, c.spread <= 35 { mid += 1 }
                        if c.high < 70 { dark += 1 }
                    }
                }
                guard total > 0, Double(mid) >= 0.40 * Double(total), dark >= 1, Double(dark) <= 0.35 * Double(total) else { continue }
                return loc
            }
            return nil
        }
}

// MARK: - Takip ve yazılardan tahmin (tarif §3.5)

extension GameReading {
    public struct PhoneTrack: Sendable {
        public private(set) var last: PhoneLocation?
        public private(set) var lastFoundAt = Int.min / 2
        public var holdMs = 3_000
        public var shareNeeded = 0.45

        public init() {}

        /// Bu karedeki bulunuş (ya da `nil`). Dönen yer takipten gelebilir.
        public mutating func update(found: PhoneLocation?, pixels: PhonePixels?, now: Int) -> PhoneLocation? {
            if let f = found { last = f; lastFoundAt = now; return f }
            guard let l = last else { return nil }
            if now - lastFoundAt <= holdMs, let p = pixels, PhoneFinder.screenShare(p, at: l) >= shareNeeded { return l }
            last = nil
            return nil
        }

        public mutating func reset() { last = nil; lastFoundAt = Int.min / 2 }

        /// Telefon uygulaması yazılarının kutularından yer. Telefon yoksa ya da 2 sn'den eskiyse.
        public mutating func estimate(fromAppTexts boxes: [Box], pixels: PhonePixels?, now: Int) -> PhoneLocation? {
            guard !boxes.isEmpty, last == nil || now - lastFoundAt > 2_000 else { return nil }
            let u = Box.union(boxes)!
            let left = max(0.02, u.left - 0.015)
            let right = min(0.98, max(u.right + 0.015, left + 0.21))
            let top = max(0.04, min(0.2, u.top - 0.02))
            let bottom = min(0.95, max(0.82, u.bottom + 0.03))
            var loc = PhoneLocation(box: Box(left: left, top: top, right: right, bottom: bottom))
            if let p = pixels {
                loc.dark = true
                loc.dark = PhoneFinder.screenShare(p, at: loc) >= shareNeeded
            }
            last = loc
            lastFoundAt = now
            return loc
        }
    }
}
