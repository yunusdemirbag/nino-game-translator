// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics

/// Karenin oranı olarak verilen dikdörtgen (0–1). Başlangıç noktası sol üst köşedir.
public struct NormalizedRect: Equatable, Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px <= x + width && py >= y && py <= y + height
    }

    /// Varsayılan altyazı bölgesi: altta ve ortada.
    public static let defaultSubtitle = NormalizedRect(x: 0.10, y: 0.62, width: 0.80, height: 0.36)
}

/// OCR'nin okuduğu tek satır.
public struct RecognizedLine: Equatable, Sendable {
    public var text: String
    /// Güven, 0–1.
    public var confidence: Float
    public var box: NormalizedRect

    public init(text: String, confidence: Float, box: NormalizedRect) {
        self.text = text
        self.confidence = confidence
        self.box = box
    }
}

/// Bir kareden yazı okuyan her şey. Gerçek okuyucu Apple Vision kullanır,
/// testler sahte okuyucu kullanır.
public protocol TextRecognizer {
    func recognize(_ image: CGImage, in region: NormalizedRect) async throws -> [RecognizedLine]
}
