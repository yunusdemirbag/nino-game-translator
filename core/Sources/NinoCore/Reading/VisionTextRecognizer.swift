// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

#if canImport(Vision)
import CoreGraphics
import Vision

/// Apple Vision ile yazı okuyan gerçek okuyucu.
///
/// Vision kutuları sol alttan verir; burada Nino'nun sol üst düzenine çevrilir.
/// Not: bu dosya derlenir ama birim testi yoktur (gerçek görüntü gerekir).
public struct VisionTextRecognizer: TextRecognizer {
    public var languages: [String]
    public var usesLanguageCorrection: Bool

    public init(languages: [String] = ["en-US"], usesLanguageCorrection: Bool = true) {
        self.languages = languages
        self.usesLanguageCorrection = usesLanguageCorrection
    }

    public func recognize(_ image: CGImage, in region: NormalizedRect) async throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = usesLanguageCorrection
        request.regionOfInterest = Self.visionRect(region)

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let best = observation.topCandidates(1).first else { return nil }
            // Kutu, regionOfInterest içinde oranlanmıştır; önce tüm kareye çevrilir.
            let roi = request.regionOfInterest
            let b = observation.boundingBox
            let full = CGRect(x: roi.minX + b.minX * roi.width,
                              y: roi.minY + b.minY * roi.height,
                              width: b.width * roi.width,
                              height: b.height * roi.height)
            return RecognizedLine(text: best.string, confidence: best.confidence, box: Self.ninoRect(full))
        }
    }

    /// Nino (sol üst) → Vision (sol alt).
    static func visionRect(_ r: NormalizedRect) -> CGRect {
        CGRect(x: r.x, y: 1 - r.y - r.height, width: r.width, height: r.height)
    }

    /// Vision (sol alt) → Nino (sol üst).
    static func ninoRect(_ r: CGRect) -> NormalizedRect {
        NormalizedRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
    }
}
#endif
