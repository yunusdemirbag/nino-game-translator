// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation

// MARK: - Küçültülmüş kare (tarif §3.1, §3.6)

extension GameReading {
    /// Renk (0–255).
    public struct RGB: Equatable, Hashable, Sendable {
        public var r: Double, g: Double, b: Double
        public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
        public var low: Double { min(r, g, b) }
        public var high: Double { max(r, g, b) }
        public var spread: Double { high - low }
        /// Parlaklık (0–255).
        public var luma: Double { 0.299 * r + 0.587 * g + 0.114 * b }
        /// Maviliği: `B − (R+G)/2`.
        public var blueness: Double { b - (r + g) / 2 }
        public func scaled(_ k: Double) -> RGB { RGB(min(255, r * k), min(255, g * k), min(255, b * k)) }
        /// Beyaza `t` oranında yaklaştırılmış.
        public func toward(white t: Double) -> RGB { RGB(r + (255 - r) * t, g + (255 - g) * t, b + (255 - b) * t) }
        public var hex: String {
            func c(_ v: Double) -> String { String(format: "%02x", Int(min(255, max(0, v.rounded())))) }
            return "#" + c(r) + c(g) + c(b)
        }
        public init?(hex: String) {
            let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
            self.init(Double((v >> 16) & 255), Double((v >> 8) & 255), Double(v & 255))
        }
    }

    /// Bir karenin küçük RGB kopyası.
    public struct PhonePixels: Sendable {
        public let width: Int
        public let height: Int
        /// Satır satır RGB (nokta başına 3 bayt).
        public private(set) var rgb: [UInt8]

        public init(width: Int, height: Int, rgb: [UInt8]) {
            precondition(rgb.count == width * height * 3)
            self.width = width; self.height = height; self.rgb = rgb
        }

        /// Düz renkli kopya (testler).
        public init(width: Int, height: Int, fill: RGB) {
            self.width = width; self.height = height
            rgb = Array(repeating: 0, count: width * height * 3)
            for i in 0..<(width * height) { set(i % width, i / width, fill) }
        }

        public static func from(_ image: CGImage, width: Int, height: Int) -> PhonePixels? {
            guard let px = ImageFrame.rgba(image, width: width, height: height) else { return nil }
            var out = [UInt8](repeating: 0, count: width * height * 3)
            for i in 0..<(width * height) {
                out[i * 3] = px[i * 4]; out[i * 3 + 1] = px[i * 4 + 1]; out[i * 3 + 2] = px[i * 4 + 2]
            }
            return PhonePixels(width: width, height: height, rgb: out)
        }

        @inline(__always) public func color(_ x: Int, _ y: Int) -> RGB {
            let i = (y * width + x) * 3
            return RGB(Double(rgb[i]), Double(rgb[i + 1]), Double(rgb[i + 2]))
        }

        @inline(__always) func low(_ x: Int, _ y: Int) -> Int {
            let i = (y * width + x) * 3
            return Int(min(rgb[i], rgb[i + 1], rgb[i + 2]))
        }

        @inline(__always) func spread(_ x: Int, _ y: Int) -> Int {
            let i = (y * width + x) * 3
            return Int(max(rgb[i], rgb[i + 1], rgb[i + 2])) - Int(min(rgb[i], rgb[i + 1], rgb[i + 2]))
        }

        public mutating func set(_ x: Int, _ y: Int, _ c: RGB) {
            let i = (y * width + x) * 3
            rgb[i] = UInt8(min(255, max(0, c.r))); rgb[i + 1] = UInt8(min(255, max(0, c.g))); rgb[i + 2] = UInt8(min(255, max(0, c.b)))
        }

        /// Dikdörtgeni (kare oranı) bir renkle boyar (testler).
        public mutating func fill(_ box: Box, _ c: RGB) {
            let x0 = Int((box.left * Double(width)).rounded()), x1 = Int((box.right * Double(width)).rounded())
            let y0 = Int((box.top * Double(height)).rounded()), y1 = Int((box.bottom * Double(height)).rounded())
            for y in max(0, y0)..<min(height, y1) { for x in max(0, x0)..<min(width, x1) { set(x, y, c) } }
        }

        /// Bütün değerler `k` ile çarpılmış (en çok 255).
        public func scaled(_ k: Double) -> PhonePixels {
            var c = self
            for i in 0..<c.rgb.count { c.rgb[i] = UInt8(min(255, (Double(rgb[i]) * k).rounded())) }
            return c
        }

        /// En yakın komşuyla yeniden boyutlanmış kopya.
        public func resized(width w: Int, height h: Int) -> PhonePixels {
            if w == width && h == height { return self }
            var out = [UInt8](repeating: 0, count: w * h * 3)
            for y in 0..<h {
                let sy = min(height - 1, y * height / h)
                for x in 0..<w {
                    let sx = min(width - 1, x * width / w)
                    let s = (sy * width + sx) * 3, d = (y * w + x) * 3
                    out[d] = rgb[s]; out[d + 1] = rgb[s + 1]; out[d + 2] = rgb[s + 2]
                }
            }
            return PhonePixels(width: w, height: h, rgb: out)
        }
    }
}

// MARK: - Renk örnekleme (tarif §3.6)

extension GameReading {
    /// Kare oranında bir noktanın rengi. Gerçeği `PhoneColorSampler`, testler sahte renk verir.
    public protocol PhoneColorSource: Sendable {
        func color(x: Double, y: Double) -> RGB?
    }

    /// Kare bir kez 960 × 540'a küçültülür; nokta rengi çevresindeki 3 × 3'ün ortalaması.
    public struct PhoneColorSampler: PhoneColorSource {
        public static let width = 960, height = 540
        public let pixels: PhonePixels
        /// Aydınlatma çarpanı (kararmış açık ekran).
        public var gain: Double = 1

        public init(pixels: PhonePixels) {
            self.pixels = pixels.resized(width: Self.width, height: Self.height)
        }

        public init?(image: CGImage) {
            guard let p = PhonePixels.from(image, width: Self.width, height: Self.height) else { return nil }
            pixels = p
        }

        public func color(x: Double, y: Double) -> RGB? {
            let px = Int(x * Double(pixels.width)), py = Int(y * Double(pixels.height))
            guard px >= 1, py >= 1, px < pixels.width - 1, py < pixels.height - 1 else { return nil }
            var r = 0.0, g = 0.0, b = 0.0
            for dy in -1...1 { for dx in -1...1 { let c = pixels.color(px + dx, py + dy); r += c.r; g += c.g; b += c.b } }
            let c = RGB(r / 9, g / 9, b / 9)
            return gain == 1 ? c : c.scaled(gain)
        }

        /// Kararmış açık ekranı aydınlatır (koyu temaya dokunmaz).
        public func illuminated(for phone: PhoneLocation) -> PhoneColorSampler {
            guard !phone.dark else { return self }
            var samples: [RGB] = []
            var y = phone.box.top
            while y <= phone.box.bottom {
                let l = phone.left(at: y)
                var f = 0.05
                while f <= 0.95 + 1e-9 {
                    if let c = color(x: l + phone.screenWidth * f, y: y) { samples.append(c) }
                    f += 0.1
                }
                y += 0.02
            }
            guard samples.count >= 4 else { return self }
            let sorted = samples.sorted { $0.high < $1.high }
            let p80 = sorted[Int(Double(sorted.count - 1) * 0.8)]
            let screen = p80.high
            let median = sorted[sorted.count / 2].high
            let gray = p80.high > 0 ? p80.low / p80.high : 0
            guard screen >= 40, screen <= 231, median >= screen * 0.8, gray >= 0.8, sorted.last!.high <= screen * 1.3 else { return self }
            var c = self
            c.gain = 238 / screen
            return c
        }
    }
}
