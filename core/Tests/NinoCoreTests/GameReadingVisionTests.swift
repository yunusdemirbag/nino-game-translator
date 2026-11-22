// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

#if canImport(Vision) && canImport(CoreText)
import CoreGraphics
import CoreText
import XCTest
@testable import NinoCore

/// Çizilmiş bir kareyle gerçek Vision okuyucusu: kutular alan içinde ve kareye doğru taşınıyor mu?
final class GameReadingVisionTests: XCTestCase {
    func drawnFrame(_ text: String, width: Int = 1280, height: Int = 720, baselineY: Double = 0.88) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 44, nil)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let w = CTLineGetTypographicBounds(line, nil, nil, nil)
        ctx.textPosition = CGPoint(x: (Double(width) - w) / 2, y: Double(height) * (1 - baselineY))
        CTLineDraw(line, ctx)
        return ctx.makeImage()!
    }

    func testReaderWithVisionOnDrawnFrame() async throws {
        let clock = GameReading.ManualClock()
        let reader = GameReading.Reader(textReader: GameReading.VisionTextReader(), clock: clock)
        let out = await reader.process(GameReading.ImageFrame(drawnFrame("Light the torch, kid.")))
        guard case let .subtitleStarted(s)? = out.events.first(where: { if case .subtitleStarted = $0 { return true }; return false }) else {
            throw XCTSkip("Vision bu ortamda yazı okumadı")
        }
        XCTAssertEqual(GameReading.Text.key(s.text), "light the torch kid")
        let b = try XCTUnwrap(s.box)
        XCTAssertEqual(b.midX, 0.5, accuracy: 0.03)
        XCTAssertTrue(b.top > 0.80 && b.bottom < 0.92, "\(b)")
        XCTAssertNotNil(out.brightness)
    }
}
#endif
