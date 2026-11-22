// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

#if canImport(Vision)
import CoreGraphics
import XCTest
@testable import NinoCore

/// GTA 6, 23 Kasım 00:19 (Mac deneme-4): `Come on. Let's get some breakfast.` belirirken yalnız sonu (`breakfast.`)
/// okundu, küçük harfli blok sayılıp atıldı; satır ve ardından gelen `Breakfast. Lu, I'm not falling for that again.`
/// hiç okunmadı. Gerçek kareler (`frames/r-*.jpg`) gerçek zamanlarıyla; belirme anı, satırın sol yanı silinmiş kareyle.
final class GameReadingBreakfastTests: XCTestCase {
    static let names: [(Int, String)] = [
        (30_209, "bf-00-19-30-209"), (32_309, "bf-00-19-32-309"), (34_398, "bf-00-19-34-398"),
        (36_497, "bf-00-19-36-497"), (38_499, "bf-00-19-38-499"), (39_197, "bf-00-19-39-197"),
    ]

    static func frames() throws -> [(Int, CGImage)] {
        try names.map { ($0.0, try GameReadingMenuExitTests.image($0.1, dir: "gta6-breakfast")) }
    }

    /// Belirme anı: satırın `breakfast.` dışındaki kısmı arka planla örtülür (yazı soldan sağa beliriyor gibi).
    static func partial(_ img: CGImage, keepFrom x: Double) -> CGImage {
        let w = img.width, h = img.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1))
        // Altyazı satırı ~0,86–0,91 (üstten); CG'de y aşağıdan.
        ctx.fill(CGRect(x: 0, y: Double(h) * 0.07, width: Double(w) * x, height: Double(h) * 0.08))
        return ctx.makeImage()!
    }

    static let expected = ["come on let s get some breakfast", "breakfast lu i m not falling for that again",
                           "not that kinda breakfast the cafeteria up here"]

    func check(_ r: GameReadingMenuExitTests.Replay, file: StaticString = #filePath, line: UInt = #line) {
        let keys = r.texts.map(GR.Text.key)
        for want in Self.expected {
            XCTAssertTrue(keys.contains { $0.contains(want) || GR.Text.ratio($0, want) >= 0.85 },
                          "okunmadı: \(want)\nokunanlar: \(r.texts)\nnotlar: \(r.journal)", file: file, line: line)
        }
    }

    func testAllLinesRead() async throws {
        check(await GameReadingMenuExitTests.replay(images: try Self.frames(), leadMs: 2_000))
    }

    /// Mac'teki gibi telefon izleyicisiyle.
    func testAllLinesReadWithPhoneWatcher() async throws {
        check(await GameReadingMenuExitTests.replay(images: try Self.frames(), leadMs: 2_000, phone: true))
    }

    /// Satır belirirken önce yalnız `breakfast.` okunur (100 ms), sonra tam satır.
    func testPartialLowercaseReadDoesNotLoseLine() async throws {
        var f = try Self.frames()
        let partialFrame = Self.partial(f[1].1, keepFrom: 0.58)
        f.insert((32_165, partialFrame), at: 1)
        f.insert((32_265, partialFrame), at: 2)
        check(await GameReadingMenuExitTests.replay(images: f, leadMs: 2_000))
    }
}
#endif
