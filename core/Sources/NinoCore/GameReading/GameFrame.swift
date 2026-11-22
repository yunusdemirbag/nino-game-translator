// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation

extension GameReading {
    /// Bir alanın 64 × 12 gri küçük kopyası (tarif §3).
    public struct Fingerprint: Equatable, Sendable {
        public static let columns = 64
        public static let rows = 12
        public var values: [UInt8]

        public init(values: [UInt8]) { self.values = values }

        /// Her noktası aynı değerde iz (testler).
        public static func uniform(_ v: UInt8) -> Fingerprint {
            Fingerprint(values: Array(repeating: v, count: columns * rows))
        }

        /// Bir noktası değiştirilmiş kopya (testler). `x`, `y` alan içi oran.
        public func setting(x: Double, y: Double, to v: UInt8) -> Fingerprint {
            var copy = self
            let c = min(Self.columns - 1, max(0, Int(x * Double(Self.columns))))
            let r = min(Self.rows - 1, max(0, Int(y * Double(Self.rows))))
            if copy.values.count == Self.columns * Self.rows { copy.values[r * Self.columns + c] = v }
            return copy
        }

        /// Herhangi bir noktası `threshold`'dan çok farklıysa değişmiştir. `box` verilirse
        /// yalnız onun örttüğü hücrelere bakılır (alan içi oran; en az bir hücre).
        public func changed(from other: Fingerprint, threshold: Int = 16, within box: Box? = nil) -> Bool {
            guard values.count == other.values.count else { return true }
            guard values.count == Self.columns * Self.rows else {
                return zip(values, other.values).contains { abs(Int($0) - Int($1)) > threshold }
            }
            var c0 = 0, c1 = Self.columns, r0 = 0, r1 = Self.rows
            if let box {
                c0 = max(0, min(Self.columns - 1, Int(floor(box.left * Double(Self.columns)))))
                c1 = max(c0 + 1, min(Self.columns, Int(ceil(box.right * Double(Self.columns)))))
                r0 = max(0, min(Self.rows - 1, Int(floor(box.top * Double(Self.rows)))))
                r1 = max(r0 + 1, min(Self.rows, Int(ceil(box.bottom * Double(Self.rows)))))
            }
            for r in r0..<r1 {
                for c in c0..<c1 where abs(Int(values[r * Self.columns + c]) - Int(other.values[r * Self.columns + c])) > threshold {
                    return true
                }
            }
            return false
        }

        /// Değeri `threshold`'dan çok farklı hücrelerin payı (0–1): sahnenin ne kadarı değişti.
        public func changedShare(from other: Fingerprint, threshold: Int = 40) -> Double {
            guard values.count == other.values.count, !values.isEmpty else { return 1 }
            let n = zip(values, other.values).filter { abs(Int($0) - Int($1)) > threshold }.count
            return Double(n) / Double(values.count)
        }

        static func make(from image: CGImage) -> Fingerprint {
            let w = columns, h = rows
            var pixels = [UInt8](repeating: 0, count: w * h)
            let ok = pixels.withUnsafeMutableBytes { buf -> Bool in
                guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                ctx.interpolationQuality = .low
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            return ok ? Fingerprint(values: pixels) : Fingerprint(values: [])
        }
    }

    /// Gerçek kare: bir `CGImage`.
    public struct ImageFrame: Frame, @unchecked Sendable {
        public let cgImage: CGImage
        public init(_ image: CGImage) { cgImage = image }

        public var pixelWidth: Int { cgImage.width }
        public var pixelHeight: Int { cgImage.height }
        public var image: CGImage? { cgImage }

        /// Kare oranındaki kutunun piksel dikdörtgeni (kenarlar tam piksele yuvarlanır).
        public func pixelRect(_ box: Box) -> CGRect {
            let b = box.clamped
            let x0 = (b.left * Double(cgImage.width)).rounded(), x1 = (b.right * Double(cgImage.width)).rounded()
            let y0 = (b.top * Double(cgImage.height)).rounded(), y1 = (b.bottom * Double(cgImage.height)).rounded()
            return CGRect(x: x0, y: y0, width: max(1, x1 - x0), height: max(1, y1 - y0))
        }

        public func crop(_ box: Box, scale: Double) -> CGImage? {
            guard let cut = cgImage.cropping(to: pixelRect(box)) else { return nil }
            guard abs(scale - 1) > 0.001 else { return cut }
            return Self.scaled(cut, by: scale)
        }

        public func fingerprint(of box: Box) -> Fingerprint {
            guard let cut = cgImage.cropping(to: pixelRect(box)) else { return Fingerprint(values: []) }
            return Fingerprint.make(from: cut)
        }

        static func scaled(_ image: CGImage, by scale: Double) -> CGImage? {
            let w = max(1, Int((Double(image.width) * scale).rounded()))
            let h = max(1, Int((Double(image.height) * scale).rounded()))
            return draw(image, width: w, height: h)
        }

        static func draw(_ image: CGImage, width w: Int, height h: Int) -> CGImage? {
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return ctx.makeImage()
        }

        /// RGBA baytları (renk ölçümleri için), en çok `maxWidth` genişliğe küçültülmüş.
        static func rgba(_ image: CGImage, width w: Int, height h: Int) -> [UInt8]? {
            var px = [UInt8](repeating: 0, count: w * h * 4)
            let ok = px.withUnsafeMutableBytes { buf -> Bool in
                guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                ctx.interpolationQuality = .medium
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            return ok ? px : nil
        }
    }
}

// MARK: - Sahne aydınlığı (§4.7)

extension GameReading {
    /// Alanın ortanca parlaklığı (0–1): 160 × 40'a küçültülür, y 0,1…0,9 ve x 0,05…0,95 noktaları.
    public static func sceneBrightness(_ image: CGImage) -> Double? {
        let w = 160, h = 40
        guard let px = ImageFrame.rgba(image, width: w, height: h) else { return nil }
        var values: [Double] = []
        for yi in 1...9 {
            for xi in 1...19 {
                let x = min(w - 1, Int(Double(xi) * 0.05 * Double(w)))
                let y = min(h - 1, Int(Double(yi) * 0.1 * Double(h)))
                let i = (y * w + x) * 4
                values.append(0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2]))
            }
        }
        return Text.median(values).map { $0 / 255 }
    }
}
