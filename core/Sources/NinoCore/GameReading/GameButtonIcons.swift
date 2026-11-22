// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
#if canImport(ImageIO)
import ImageIO
#endif

// MARK: - Satır içindeki kumanda tuşu simgesi (§4.4)

extension GameReading {
    /// Satırın içindeki tuş simgesini (`Hold [D-pad] to interact`) bulur, tanır ve metne `⟦T1⟧` yer tutucusu koyar.
    ///
    /// Vision simgeyi çoğu zaman hiç okumaz (`Hold to interact`) ya da çöp okur (`Hold ® to`); sözcük kutuları da
    /// kaba (eşit bölünmüş) gelir. Bu yüzden simge görüntüden aranır: satırın kutusunda sütun sütun mürekkep izi,
    /// sözcüklerden **daha uzun** (yazı bandının üstüne ve altına taşan) ve kabaca kare bir leke simgedir.
    ///
    /// Bilinen PS5 tuşları adıyla gider (`dpad-right`, `cross`, `L2`; TV temiz vektör çizer), tanınmayan simge
    /// oyundan kesilmiş küçük PNG olarak. Okuma hattının metnine dokunulmaz: yer tutucu, köşe/altyazı çevrilmeden
    /// hemen önce konur (`prepare`); böylece ipucu süzgeçleri ve kararlılık eskisi gibi çalışır.
    public enum ButtonIcons {
        /// Bulunan simge (kare oranında kutu).
        public struct Found: Equatable, Sendable {
            public var box: Box
            public var name: String?
            public var png: Data?
            /// Simgenin önünde kaç sözcük var (satır metninde).
            public var wordIndex: Int
        }

        /// Çevirmene gidecek yer tutuculu metin ve simgeleri.
        public struct Prepared: Equatable, Sendable {
            /// `Hold ⟦T1⟧ to interact with your partner` (simge yoksa satırların kendisi).
            public var text: String
            public var icons: [LinkIcon]
            public var ids: [String] { icons.map(\.id) }
        }

        // MARK: Metinden tanınan tuşlar

        /// Vision'ın yazı olarak okuduğu tuş adları ve simgeleri → protokol adı.
        public static func name(forWord word: String) -> String? {
            let w = word.trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}"))
            switch w {
            case "L1", "L2", "L3", "R1", "R2", "R3": return w
            case "✕", "✖", "⨯": return "cross"
            case "○", "◯": return "circle"
            case "□", "▢", "◻": return "square"
            case "△", "▲": return "triangle"
            case "↑": return "dpad-up"
            case "↓": return "dpad-down"
            case "←": return "dpad-left"
            case "→": return "dpad-right"
            case "✜": return "dpad"
            case "OPTIONS": return "options"
            case "TOUCHPAD": return "touchpad"
            default: return nil
            }
        }

        /// Vision'ın simge yerine okuduğu anlamsız kırıntı (`®`, `&`, `)`, `OC`): görüntüde simge bulunursa yerine geçer.
        /// En çok 3 karakter, hepsi simge okuyuşlarında görülen işaretlerden.
        static func isJunk(_ word: String) -> Bool {
            let chars: Set<Character> = ["®", "©", "@", "&", "⊗", "Ⓧ", "ⓧ", "⨂", "◆", "*", "•", "●", "■", "(", ")", "[", "]",
                                         "{", "}", "O", "o", "0", "C", "c", "Q", "X", "x", "+", "©", "|", "/", "\\", "<", ">"]
            return (1...3).contains(word.count) && word.allSatisfy { chars.contains($0) }
        }

        /// Aynı sıradaki satır parçalarını (Vision simgede bölebilir: `Hold OC` + `) to interact …`) tek satıra birleştirir.
        static func rows(_ lines: [Line]) -> [Line] {
            var out: [Line] = []
            for l in lines {
                if let b = l.box, let i = out.lastIndex(where: { o in
                    guard let ob = o.box else { return false }
                    let overlap = min(ob.bottom, b.bottom) - max(ob.top, b.top)
                    return overlap >= 0.5 * min(ob.height, b.height)
                }) {
                    let ob = out[i].box!
                    let parts = ob.left <= b.left ? [out[i].text, l.text] : [l.text, out[i].text]
                    out[i] = Line(parts.joined(separator: " "), confidence: min(out[i].confidence, l.confidence), box: ob.union(b))
                } else {
                    out.append(l)
                }
            }
            return out
        }

        // MARK: Hazırlık

        /// Satırları (alt alta, kare oranında kutulu) yer tutuculu metne çevirir. `image` verilirse simge görüntüde de
        /// aranır. Yer tutucular soldan sağa, üstten alta `T1`, `T2` … (en çok 8).
        public static func prepare(_ lines: [Line], image: CGImage?) -> Prepared {
            var icons: [LinkIcon] = []
            var outLines: [String] = []
            for line in rows(lines) {
                var words = Text.words(line.text)
                var slots: [(index: Int, replace: Bool, name: String?, png: Data?)] = []
                for (i, w) in words.enumerated() {
                    if let n = name(forWord: w) { slots.append((i, true, n, nil)) }
                }
                if let image, line.box != nil {
                    for f in find(in: image, line: line) {
                        // Simge sözcük olarak okunduysa (tuş adı ya da çöp) o sözcüğün yerine geçer.
                        // `wordIndex` kırıntısız sözcük sayısıdır; satırdaki sıraya çevrilir.
                        let real = words.indices.filter { !isJunk(words[$0]) }
                        let at = f.wordIndex < real.count ? real[f.wordIndex] : words.count
                        if let s = slots.firstIndex(where: { abs($0.index - at) <= 1 && $0.replace }) {
                            // Yazıdan okunan ad (`L2`) önce gelir; yoksa görüntünün adı ya da görüntü.
                            if slots[s].name == nil { slots[s].name = f.name; slots[s].png = f.png }
                            continue
                        }
                        // Simgenin yanındaki kırıntılar (`OC )`) atılır, simge ilkinin yerine geçer.
                        var lo = at, hi = at
                        while lo > 0, isJunk(words[lo - 1]) { lo -= 1 }
                        while hi < words.count, isJunk(words[hi]) { hi += 1 }
                        if lo < hi {
                            slots.append((lo, true, f.name, f.png))
                            for k in (lo + 1)..<hi { slots.append((k, true, nil, nil)) }
                            continue
                        }
                        slots.append((at, false, f.name, f.png))
                    }
                }
                // Sondan başa uygula ki sırası kaymasın; kimlikler soldan sağa.
                slots.sort { $0.index < $1.index || ($0.index == $1.index && $0.replace && !$1.replace) }
                var tags: [Int: [String]] = [:]
                var replaced = Set<Int>()
                for s in slots {
                    // Yalnız silinecek kırıntı.
                    if s.replace, s.name == nil, s.png == nil { replaced.insert(s.index); continue }
                    guard icons.count < LinkIcon.maxCount, s.name != nil || s.png != nil else { continue }
                    let id = "T\(icons.count + 1)"
                    icons.append(LinkIcon(id: id, name: s.name, png: s.png?.base64EncodedString()))
                    tags[s.index, default: []].append(IconPlaceholders.tag(id))
                    if s.replace { replaced.insert(s.index) }
                }
                var out: [String] = []
                for i in 0...words.count {
                    if let t = tags[i] { out += t }
                    if i < words.count, !replaced.contains(i) { out.append(words[i]) }
                }
                words = out
                outLines.append(words.joined(separator: " "))
            }
            return Prepared(text: outLines.joined(separator: "\n"), icons: icons)
        }

        // MARK: Görüntüde arama

        /// Ölçek: satır yüksekliği bu kadar piksele getirilir (eşikler buna göre).
        static let unit = 32.0


        /// Mürekkep lekesi (bağlı bileşen ya da bileşen kümesi), kesilen alanın pikselinde.
        struct Blob: Equatable {
            var x0: Int, x1: Int, y0: Int, y1: Int, ink: Int
            var width: Int { x1 - x0 + 1 }
            var height: Int { y1 - y0 + 1 }
            var midX: Double { Double(x0 + x1) / 2 }
            func contains(_ o: Blob) -> Bool { o.x0 >= x0 && o.x1 <= x1 && o.y0 >= y0 && o.y1 <= y1 }
        }

        struct Scan {
            /// Bağlı bileşenler (soldan sağa).
            var parts: [Blob]
            /// Kesilen alan (kare oranında) ve boyu.
            var area: Box
            var w: Int, h: Int
        }

        /// Satırın kutusunu (üstüne/altına 0,45, yanlarına 1,8 satır boyu payla) keser, satır boyunu 32 piksele
        /// getirir, zeminden belirgin ayrılan pikselleri (mürekkep) bağlı bileşenlere ayırır.
        static func scan(_ image: CGImage, box line: Box) -> Scan? {
            let fw = Double(image.width), fh = Double(image.height)
            let hpx = line.height * fh
            guard hpx >= 8, line.width > 0 else { return nil }
            let padY = line.height * 0.45, padX = line.height * fh / fw * 1.8
            let area = Box(left: line.left - padX, top: line.top - padY, right: line.right + padX, bottom: line.bottom + padY).clamped
            let scale = unit / hpx
            let w = max(8, Int((area.width * fw * scale).rounded())), h = max(8, Int((area.height * fh * scale).rounded()))
            guard w <= 4_000, let cut = ImageFrame(image).crop(area, scale: 1), let px = ImageFrame.rgba(cut, width: w, height: h) else { return nil }
            var gray = [Double](repeating: 0, count: w * h)
            for i in 0..<(w * h) { gray[i] = 0.299 * Double(px[i * 4]) + 0.587 * Double(px[i * 4 + 1]) + 0.114 * Double(px[i * 4 + 2]) }
            let bg = Text.median(gray) ?? 0
            // Açık yazı mı koyu yazı mı: zeminden hangi yöne daha çok sapma var?
            let light = (Text.quantile(gray, 0.98) ?? bg) - bg >= bg - (Text.quantile(gray, 0.02) ?? bg)
            var mask = [Bool](repeating: false, count: w * h)
            for i in 0..<(w * h) { mask[i] = light ? gray[i] - bg > 60 : bg - gray[i] > 60 }
            var label = [Int](repeating: -1, count: w * h)
            var parts: [Blob] = []
            var stack: [Int] = []
            for start in 0..<(w * h) where mask[start] && label[start] < 0 {
                var b = Blob(x0: w, x1: -1, y0: h, y1: -1, ink: 0)
                label[start] = parts.count
                stack.append(start)
                while let p = stack.popLast() {
                    let x = p % w, y = p / w
                    b.x0 = min(b.x0, x); b.x1 = max(b.x1, x); b.y0 = min(b.y0, y); b.y1 = max(b.y1, y); b.ink += 1
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                        let q = ny * w + nx
                        if mask[q], label[q] < 0 { label[q] = parts.count; stack.append(q) }
                    }
                }
                parts.append(b)
            }
            return Scan(parts: parts.filter { $0.ink >= 3 }.sorted { $0.x0 < $1.x0 }, area: area, w: w, h: h)
        }

        /// Satırın içindeki simgeler. Simge: harflerden belirgin uzun (`≥ 1,15 ×` satır boyu, `≥ 1,6 ×` harflerin
        /// ortanca boyu), kabaca kare (en/boy 0,6–1,6), kesilen alanın kenarına değmeyen bağlı leke (halka ya da
        /// çerçeve); içindeki parçalar ona katılır. Önündeki sözcük sayısı soldaki sözcük kümelerinden bulunur.
        public static func find(in image: CGImage, line: Line) -> [Found] {
            guard let box = line.box, let s = scan(image, box: box) else { return [] }
            let parts = s.parts.filter { $0.y0 > 0 && $0.y1 < s.h - 1 && $0.x0 > 0 && $0.x1 < s.w - 1 }
            guard parts.count >= 2 else { return [] }
            let letter = Text.median(parts.map { Double($0.height) }) ?? unit
            var icons = parts.filter { b in
                let hgt = Double(b.height), ratio = Double(b.width) / hgt
                return hgt >= 1.15 * unit && hgt <= 2.2 * unit && hgt >= 1.6 * letter && (0.6...1.6).contains(ratio)
            }
            icons = icons.filter { i in !icons.contains { $0 != i && $0.contains(i) } }
            guard !icons.isEmpty else { return [] }
            // Yazı: simgelerin içinde ve üstünde olmayan parçalar; sözcüklere kümelenir (harf arası < 0,2 satır boyu).
            let text = parts.filter { p in !icons.contains { $0.contains(p) || $0 == p } }
            var words: [Blob] = []
            for p in text {
                if var last = words.last, p.x0 - last.x1 <= Int(unit * 0.2) {
                    last.x1 = max(last.x1, p.x1); last.y0 = min(last.y0, p.y0); last.y1 = max(last.y1, p.y1); last.ink += p.ink
                    words[words.count - 1] = last
                } else {
                    words.append(p)
                }
            }
            let wordCount = Text.words(line.text).filter { !isJunk($0) }.count
            return icons.map { b in
                let fb = Box(left: s.area.left + Double(b.x0) / Double(s.w) * s.area.width,
                             top: s.area.top + Double(b.y0) / Double(s.h) * s.area.height,
                             right: s.area.left + Double(b.x1 + 1) / Double(s.w) * s.area.width,
                             bottom: s.area.top + Double(b.y1 + 1) / Double(s.h) * s.area.height)
                var index = words.filter { $0.midX < b.midX }.count
                if words.count != wordCount {
                    // Kümeler sözcüklerle tutmuyor: satırdaki konumundan oranla.
                    let t = (fb.midX - box.left) / max(box.width, 1e-6)
                    index = Int((Double(wordCount) * t).rounded())
                }
                let name = classify(image, box: fb)
                return Found(box: fb, name: name, png: name == nil ? png(image, box: fb) : nil,
                             wordIndex: max(0, min(wordCount, index)))
            }
        }

        // MARK: Tanıma (renk ve şekil; model yok)

        /// Bilinen PS5 tuşu mu? D-pad (halka + dört kol; parlak kol yönü verir) ve renkli yüz tuşları
        /// (yeşil üçgen, kırmızı daire, mavi çarpı, pembe kare). Emin değilse `nil` (görüntü gider).
        public static func classify(_ image: CGImage, box: Box) -> String? {
            let n = 21
            guard let cut = ImageFrame(image).crop(box, scale: 1), let px = ImageFrame.rgba(cut, width: n, height: n) else { return nil }
            func lum(_ x: Int, _ y: Int) -> Double {
                let i = (y * n + x) * 4
                return 0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2])
            }
            func mean(_ cx: Int, _ cy: Int, _ r: Int = 1) -> Double {
                var s = 0.0, k = 0.0
                for y in max(0, cy - r)...min(n - 1, cy + r) { for x in max(0, cx - r)...min(n - 1, cx + r) { s += lum(x, y); k += 1 } }
                return s / max(k, 1)
            }
            if let face = faceColor(px, n: n) { return face }
            // D-pad: kollar (merkezden 0,3 uzakta) köşegenlerden (0,3 uzakta) belirgin açık, halka var.
            let c = n / 2, d = Int((Double(n) * 0.3).rounded())
            let arms: [(String, Double)] = [("up", mean(c, c - d)), ("down", mean(c, c + d)), ("left", mean(c - d, c)), ("right", mean(c + d, c))]
            let dd = Int((Double(d) * 0.75).rounded())
            let diagonals = [mean(c - dd, c - dd), mean(c + dd, c - dd), mean(c - dd, c + dd), mean(c + dd, c + dd)]
            let ring = (0..<16).map { k -> Double in
                let a = Double(k) / 16 * 2 * Double.pi, r = Double(n) * 0.44
                return lum(min(n - 1, max(0, Int((Double(c) + r * cos(a)).rounded()))), min(n - 1, max(0, Int((Double(c) + r * sin(a)).rounded()))))
            }
            let armValues = arms.map(\.1).sorted()
            let darkest = diagonals.max() ?? 0
            let ringLow = ring.sorted()[3]
            guard armValues[0] - darkest >= 30, ringLow - darkest >= 30 else { return nil }
            // Yön: en açık kol ötekilerin en açığından belirgin açıksa.
            let brightest = arms.max { $0.1 < $1.1 }!
            if brightest.1 - armValues[2] >= 35 { return "dpad-" + brightest.0 }
            return "dpad"
        }

        /// Yüz tuşu rengi: doygun piksellerin çoğu tek renkteyse.
        static func faceColor(_ px: [UInt8], n: Int) -> String? {
            var counts: [String: Int] = [:]
            var saturated = 0
            for i in 0..<(n * n) {
                let r = Double(px[i * 4]) / 255, g = Double(px[i * 4 + 1]) / 255, b = Double(px[i * 4 + 2]) / 255
                let mx = max(r, g, b), mn = min(r, g, b)
                guard mx > 0.35, mx - mn > 0.3 * mx else { continue }
                saturated += 1
                var hue: Double
                if mx == r { hue = (g - b) / (mx - mn) } else if mx == g { hue = 2 + (b - r) / (mx - mn) } else { hue = 4 + (r - g) / (mx - mn) }
                hue = (hue * 60).truncatingRemainder(dividingBy: 360); if hue < 0 { hue += 360 }
                let name: String
                switch hue {
                case 90..<170: name = "triangle"
                case 190..<250: name = "cross"
                case 290..<345: name = "square"
                case 345..<360, 0..<20: name = "circle"
                default: continue
                }
                counts[name, default: 0] += 1
            }
            guard saturated >= n * n / 12, let top = counts.max(by: { $0.value < $1.value }), top.value >= saturated * 3 / 4 else { return nil }
            return top.key
        }

        // MARK: Kesilmiş görüntü

        /// En çok bu kadar bayt (TV'ye her mesajda gider).
        public static let maxPNGBytes = 8_000

        /// Simgenin kendi arka planıyla küçük PNG'si: en uzun kenar en çok 48 piksel; 8 KB'ı aşarsa küçültülür.
        public static func png(_ image: CGImage, box: Box) -> Data? {
            let pad = box.height * 0.08
            let b = Box(left: box.left - pad * Double(image.height) / Double(image.width), top: box.top - pad,
                        right: box.right + pad * Double(image.height) / Double(image.width), bottom: box.bottom + pad).clamped
            guard let cut = ImageFrame(image).crop(b, scale: 1) else { return nil }
            for side in [48, 36, 28, 20] {
                let s = min(1, Double(side) / Double(max(cut.width, cut.height)))
                let w = max(1, Int((Double(cut.width) * s).rounded())), h = max(1, Int((Double(cut.height) * s).rounded()))
                guard let small = ImageFrame.draw(cut, width: w, height: h), let data = encodePNG(small) else { return nil }
                if data.count <= maxPNGBytes { return data }
            }
            return nil
        }

        static func encodePNG(_ image: CGImage) -> Data? {
            #if canImport(ImageIO)
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, image, nil)
            return CGImageDestinationFinalize(dest) ? data as Data : nil
            #else
            return nil
            #endif
        }
    }

    /// `IconRecognizer` (§4.4): Vision'ın böldüğü satır parçaları arasındaki boşlukta tuş simgesi tanır ve okunur
    /// işaretini verir (`✕`, `→`, `✜`); ipucu süzgeci bunları tuş sayar, `ButtonIcons.prepare` yer tutucuya çevirir.
    public struct ButtonIconRecognizer: IconRecognizer {
        public init() {}

        public func icon(in frame: Frame, box: Box, strict: Bool) -> String? {
            guard let image = frame.image, let name = ButtonIcons.classify(image, box: box) else { return nil }
            let symbol = LinkIcon(id: "T1", name: name).readable
            return String(symbol.dropFirst().dropLast())
        }
    }
}
