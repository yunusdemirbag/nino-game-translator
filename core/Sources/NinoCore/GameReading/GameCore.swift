// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation

/// Zamanlı, zengin oyun okuma hattı. Bütün türler bu adın altındadır.
/// Tarif: `docs/tarif/oyun-okuma.md`.
public enum GameReading {}

// MARK: - Saat

extension GameReading {
    /// Milisaniye saati. Hat saate yalnız bundan bakar.
    public protocol Clock: Sendable {
        var nowMs: Int { get }
    }

    /// Gerçek saat: açılıştan beri geçen ms.
    public struct SystemClock: Clock {
        public init() {}
        public var nowMs: Int { Int(DispatchTime.now().uptimeNanoseconds / 1_000_000) }
    }

    /// Elle ilerleyen saat (testler, deneme).
    public final class ManualClock: Clock, @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int
        public init(_ start: Int = 0) { value = start }
        public var nowMs: Int {
            get { lock.lock(); defer { lock.unlock() }; return value }
            set { lock.lock(); value = newValue; lock.unlock() }
        }
        public func advance(_ ms: Int) { lock.lock(); value += ms; lock.unlock() }
    }
}

// MARK: - Kutu

extension GameReading {
    /// Karenin (ya da okunan alanın) oranı olarak kutu; sol üstten, 0–1.
    public struct Box: Equatable, Hashable, Sendable, Codable {
        public var left: Double
        public var top: Double
        public var right: Double
        public var bottom: Double

        public init(left: Double, top: Double, right: Double, bottom: Double) {
            self.left = left; self.top = top; self.right = right; self.bottom = bottom
        }

        public init(_ rect: NormalizedRect) {
            self.init(left: rect.x, top: rect.y, right: rect.x + rect.width, bottom: rect.y + rect.height)
        }

        public static let full = Box(left: 0, top: 0, right: 1, bottom: 1)

        public var width: Double { right - left }
        public var height: Double { bottom - top }
        public var midX: Double { (left + right) / 2 }
        public var midY: Double { (top + bottom) / 2 }
        public var rect: NormalizedRect { NormalizedRect(x: left, y: top, width: width, height: height) }

        /// Bu kutu `area` içindeki oransa, kare oranına taşır.
        public func mapped(into area: Box) -> Box {
            Box(left: area.left + left * area.width, top: area.top + top * area.height,
                right: area.left + right * area.width, bottom: area.top + bottom * area.height)
        }

        /// Kare oranındaki kutuyu `area` içindeki orana çevirir.
        public func local(in area: Box) -> Box {
            let w = max(area.width, 1e-9), h = max(area.height, 1e-9)
            return Box(left: (left - area.left) / w, top: (top - area.top) / h,
                       right: (right - area.left) / w, bottom: (bottom - area.top) / h)
        }

        public func union(_ o: Box) -> Box {
            Box(left: min(left, o.left), top: min(top, o.top), right: max(right, o.right), bottom: max(bottom, o.bottom))
        }

        public func insetBy(dx: Double, dy: Double) -> Box {
            Box(left: left + dx, top: top + dy, right: right - dx, bottom: bottom - dy)
        }

        /// 0–1 içine kırpılmış.
        public var clamped: Box {
            Box(left: min(max(left, 0), 1), top: min(max(top, 0), 1),
                right: min(max(right, 0), 1), bottom: min(max(bottom, 0), 1))
        }

        public func intersects(_ o: Box, padding: Double = 0) -> Bool {
            left - padding < o.right && o.left < right + padding && top - padding < o.bottom && o.top < bottom + padding
        }

        public func contains(x: Double, y: Double, padding: Double = 0) -> Bool {
            x >= left - padding && x <= right + padding && y >= top - padding && y <= bottom + padding
        }

        public static func union(_ boxes: [Box]) -> Box? {
            guard var u = boxes.first else { return nil }
            for b in boxes.dropFirst() { u = u.union(b) }
            return u
        }
    }

    /// OCR'nin okuduğu satır. Kutu yoksa yeri bilinmiyordur.
    public struct Line: Equatable, Sendable {
        public var text: String
        public var confidence: Float
        public var box: Box?

        public init(_ text: String, confidence: Float = 1, box: Box? = nil) {
            self.text = text; self.confidence = confidence; self.box = box
        }

        /// Kutuyu alan içinden kareye taşır.
        public func mapped(into area: Box) -> Line {
            Line(text, confidence: confidence, box: box?.mapped(into: area))
        }
    }
}

// MARK: - Kare ve okuyucu

extension GameReading {
    /// Okuma hattının kareden istediği iki şey: kesme ve iz.
    public protocol Frame: Sendable {
        /// Piksel boyu (en/boy oranı için).
        var pixelWidth: Int { get }
        var pixelHeight: Int { get }
        /// Kare oranındaki `box` alanının 64 × 12 gri izi.
        func fingerprint(of box: Box) -> Fingerprint
        /// Alanı keser ve `scale` katına büyütür. Görüntüsüz karede `nil`.
        func crop(_ box: Box, scale: Double) -> CGImage?
        /// Alanın tamamı (renkli); buzlu zemin ve renk ölçümü için.
        var image: CGImage? { get }
    }

    /// Bir karenin bir alanını okuyan her şey. Dönen kutular **alanın içindeki** orandır.
    public protocol TextReader: Sendable {
        func read(_ frame: Frame, area: Box, scale: Double) async throws -> [Line]
    }

    /// Yan yana iki sözcük arasındaki boşlukta ya da şüpheli sözcükte kumanda simgesi tanır.
    /// Tarif §4.4; tanıyıcı sonraya bırakıldı, arayüz hazır.
    public protocol IconRecognizer: Sendable {
        /// `box` kare oranında; `strict` kenar simgeleri için sıkı kural.
        func icon(in frame: Frame, box: Box, strict: Bool) -> String?
    }
}

// MARK: - Metin yardımcıları

extension GameReading {
    enum Text {
        static let closers: Set<Character> = ["\"", "'", "”", "’", "»", ")", "]"]
        static let enders: Set<Character> = [".", "!", "?", "…"]

        /// Sondaki kapanan tırnak/parantez atıldıktan sonra son karakter `. ! ? …` mi?
        static func endsSentence(_ text: String) -> Bool {
            var t = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
            while let last = t.last, closers.contains(last) { t = t.dropLast() }
            return t.last.map { enders.contains($0) } ?? false
        }

        static func key(_ text: String) -> String { TextSimilarity.key(text) }

        static func ratio(_ a: String, _ b: String) -> Double {
            let x = key(a), y = key(b)
            if x.isEmpty || y.isEmpty { return 0 }
            return TextSimilarity.ratio(x, y)
        }

        static func words(_ text: String) -> [String] {
            text.split(whereSeparator: \.isWhitespace).map(String.init)
        }

        static func keyWords(_ text: String) -> [String] {
            key(text).split(separator: " ").map(String.init)
        }

        static func letterCount(_ text: String) -> Int { text.filter(\.isLetter).count }

        static func hasLowercase(_ text: String) -> Bool { text.contains { $0.isLowercase } }

        static func squeeze(_ text: String) -> String { words(text).joined(separator: " ") }

        static func lines(_ text: String) -> [String] {
            text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }

        /// Sıralı listede `round((n−1) × q)` sırasındaki değer.
        static func quantile(_ values: [Double], _ q: Double) -> Double? {
            guard !values.isEmpty else { return nil }
            let s = values.sorted()
            return s[Int(((Double(s.count) - 1) * q).rounded())]
        }

        static func median(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            let s = values.sorted()
            return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
        }

        /// Sözcük dizileri arasında düzenleme uzaklığı oranı (0–1).
        static func sequenceRatio(_ a: [String], _ b: [String]) -> Double {
            let longest = max(a.count, b.count)
            if longest == 0 { return 1 }
            if a.isEmpty || b.isEmpty { return 0 }
            var prev = Array(0...b.count), cur = Array(repeating: 0, count: b.count + 1)
            for i in 1...a.count {
                cur[0] = i
                for j in 1...b.count {
                    cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                }
                swap(&prev, &cur)
            }
            return 1 - Double(prev[b.count]) / Double(longest)
        }

        static func regex(_ pattern: String, _ text: String, caseInsensitive: Bool = true) -> Bool {
            text.range(of: pattern, options: caseInsensitive ? [.regularExpression, .caseInsensitive] : [.regularExpression]) != nil
        }
    }
}
