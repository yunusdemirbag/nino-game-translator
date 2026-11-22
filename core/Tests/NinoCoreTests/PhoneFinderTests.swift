// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import XCTest
@testable import NinoCore

/// Çizilmiş karelerle telefon bulma (tarif §3).
final class PhoneFinderTests: XCTestCase {
    struct Drawing {
        let w = 1280, h = 720
        let ctx: CGContext
        init(background: GR.RGB) {
            ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            fill(GR.Box.full, background)
        }
        func color(_ c: GR.RGB) -> CGColor { CGColor(red: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: 1) }
        /// Kare oranında, sol üstten dikdörtgen.
        func fill(_ b: GR.Box, _ c: GR.RGB) {
            ctx.setFillColor(color(c))
            ctx.fill(CGRect(x: b.left * Double(w), y: (1 - b.bottom) * Double(h), width: b.width * Double(w), height: b.height * Double(h)))
        }
        /// Sol kenarı aşağı indikçe `slope` kadar kayan paralelkenar.
        func parallelogram(left: Double, top: Double, width: Double, bottom: Double, slope: Double, _ c: GR.RGB) {
            ctx.setFillColor(color(c))
            let p = CGMutablePath()
            func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * Double(w), y: (1 - y) * Double(h)) }
            let bl = left + slope * (bottom - top)
            p.move(to: pt(left, top)); p.addLine(to: pt(left + width, top))
            p.addLine(to: pt(bl + width, bottom)); p.addLine(to: pt(bl, bottom)); p.closeSubpath()
            ctx.addPath(p); ctx.fillPath()
        }
        var image: CGImage { ctx.makeImage()! }
        var pixels: GR.PhonePixels { GR.PhonePixels.from(image, width: GR.PhoneFinder.gridWidth, height: GR.PhoneFinder.gridHeight)! }
    }

    func lightPhone(slope: Double = 0, screen: GR.RGB = GR.RGB(238, 238, 240), background: GR.RGB = GR.RGB(120, 140, 170)) -> Drawing {
        let d = Drawing(background: background)
        d.parallelogram(left: 0.405, top: 0.15, width: 0.19, bottom: 0.83, slope: slope, GR.RGB(18, 18, 22))
        d.parallelogram(left: 0.42, top: 0.18, width: 0.16, bottom: 0.80, slope: slope, screen)
        // Yazı çizgileri (koyu, kısa).
        for i in 0..<6 {
            let y = 0.30 + Double(i) * 0.07
            let l = 0.43 + slope * (y - 0.18)
            d.fill(gbox(l, y, l + 0.08, y + 0.008), GR.RGB(40, 40, 40))
        }
        return d
    }

    func testFindsUprightLightPhone() throws {
        let f = try XCTUnwrap(GR.PhoneFinder.find(lightPhone().pixels))
        XCTAssertEqual(f.box.left, 0.42, accuracy: 0.015)
        XCTAssertEqual(f.box.right, 0.58, accuracy: 0.015)
        XCTAssertEqual(f.box.top, 0.18, accuracy: 0.02)
        XCTAssertEqual(f.box.bottom, 0.80, accuracy: 0.02)
        XCTAssertEqual(f.slope, 0, accuracy: 0.012)
        XCTAssertFalse(f.dark)
        XCTAssertFalse(f.shapeOnly)
        XCTAssertEqual(f.angle, 0, accuracy: 1.5)
    }

    func testFindsTiltedPhone() throws {
        let f = try XCTUnwrap(GR.PhoneFinder.find(lightPhone(slope: 0.08).pixels))
        XCTAssertEqual(f.slope, 0.08, accuracy: 0.015)
        XCTAssertEqual(f.topLeft, 0.42, accuracy: 0.015)
        XCTAssertEqual(f.left(at: 0.7), 0.42 + 0.08 * (0.7 - 0.18), accuracy: 0.02)
        XCTAssertLessThan(f.angle, -5, "sol kenar aşağıda sağa kayıyor: saat yönünün tersi")
    }

    func testDimmedScreenIsBrightened() throws {
        let d = lightPhone(screen: GR.RGB(95, 95, 98), background: GR.RGB(40, 60, 90))
        XCTAssertNotNil(GR.PhoneFinder.dimGain(d.pixels))
        let f = try XCTUnwrap(GR.PhoneFinder.find(d.pixels))
        XCTAssertEqual(f.box.midX, 0.5, accuracy: 0.02)
        XCTAssertFalse(f.dark)
    }

    func testDarkThemeNeedsTextNotClothes() throws {
        func draw(text: Bool) -> Drawing {
            let d = Drawing(background: GR.RGB(110, 120, 90))
            d.fill(gbox(0.405, 0.15, 0.595, 0.83), GR.RGB(205, 205, 210))
            d.fill(gbox(0.42, 0.18, 0.58, 0.80), GR.RGB(20, 20, 24))
            if text {
                for i in 0..<10 {
                    let y = 0.24 + Double(i) * 0.05
                    d.fill(gbox(0.44, y, 0.50, y + 0.02), GR.RGB(240, 240, 240))
                }
            }
            return d
        }
        let f = try XCTUnwrap(GR.PhoneFinder.find(draw(text: true).pixels))
        XCTAssertTrue(f.dark)
        XCTAssertEqual(f.box.midX, 0.5, accuracy: 0.02)
        XCTAssertNil(GR.PhoneFinder.find(draw(text: false).pixels), "yazısız koyu dikdörtgen kıyafet olabilir")
    }

    func testNoPhoneInPlainSceneOrBareWhiteWall() {
        XCTAssertNil(GR.PhoneFinder.find(Drawing(background: GR.RGB(120, 140, 170)).pixels))
        let wall = Drawing(background: GR.RGB(120, 140, 170))
        wall.fill(gbox(0.42, 0.18, 0.58, 0.80), GR.RGB(238, 238, 240))
        XCTAssertNil(GR.PhoneFinder.find(wall.pixels), "koyu çerçevesiz beyaz alan telefon değil")
    }

    func testTooWideIsNotPhone() {
        let d = Drawing(background: GR.RGB(120, 140, 170))
        d.fill(gbox(0.25, 0.15, 0.75, 0.83), GR.RGB(18, 18, 22))
        d.fill(gbox(0.27, 0.18, 0.73, 0.80), GR.RGB(238, 238, 240))
        XCTAssertNil(GR.PhoneFinder.find(d.pixels))
    }

    // MARK: Takip (§3.5)

    func testTrackHoldsWhileScreenStays() throws {
        let p = lightPhone().pixels
        let f = try XCTUnwrap(GR.PhoneFinder.find(p))
        var t = GR.PhoneTrack()
        // t=0 bulundu
        XCTAssertEqual(t.update(found: f, pixels: p, now: 0), f)
        // t=2000 bulunamadı ama ekran aynı yerde → orada
        XCTAssertEqual(t.update(found: nil, pixels: p, now: 2_000), f)
        // t=3500 süre doldu → bırakılır
        XCTAssertNil(t.update(found: nil, pixels: p, now: 3_500))
        // Yeniden bulunup ekran kaybolunca hemen bırakılır.
        _ = t.update(found: f, pixels: p, now: 4_000)
        XCTAssertNil(t.update(found: nil, pixels: Drawing(background: GR.RGB(120, 140, 170)).pixels, now: 4_500))
    }

    func testEstimateFromAppTexts() throws {
        var t = GR.PhoneTrack()
        let loc = try XCTUnwrap(t.estimate(fromAppTexts: [gbox(0.45, 0.40, 0.55, 0.42), gbox(0.45, 0.45, 0.52, 0.47)], pixels: nil, now: 0))
        XCTAssertEqual(loc.box.left, 0.435, accuracy: 1e-9)
        XCTAssertEqual(loc.box.right, 0.645, accuracy: 1e-9)   // sol + 0,21
        XCTAssertEqual(loc.box.top, 0.2, accuracy: 1e-9)
        XCTAssertEqual(loc.box.bottom, 0.82, accuracy: 1e-9)
        XCTAssertEqual(loc.slope, 0)
        // Yakında bulunan telefon varken tahmin yok.
        var u = GR.PhoneTrack()
        _ = u.update(found: GR.PhoneLocation(box: gbox(0.4, 0.2, 0.6, 0.8)), pixels: nil, now: 0)
        XCTAssertNil(u.estimate(fromAppTexts: [gbox(0.45, 0.40, 0.55, 0.42)], pixels: nil, now: 1_000))
    }

    // MARK: Şekil (§3.2)

    func testShapeNeedsLightInterior() {
        var p = GR.PhonePixels(width: 240, height: 135, fill: GR.RGB(180, 150, 60))
        let quad = GR.PhoneQuad(topLeft: (0.42, 0.2), topRight: (0.58, 0.2), bottomRight: (0.58, 0.8), bottomLeft: (0.42, 0.8))
        XCTAssertNil(GR.PhoneFinder.findByShape([quad], pixels: p), "renkli iç")
        p.fill(gbox(0.42, 0.2, 0.58, 0.8), GR.RGB(200, 200, 205))
        p.fill(gbox(0.45, 0.4, 0.5, 0.42), GR.RGB(30, 30, 30))
        let f = GR.PhoneFinder.findByShape([quad], pixels: p)
        XCTAssertEqual(f?.shapeOnly, true)
        let wide = GR.PhoneQuad(topLeft: (0.2, 0.2), topRight: (0.8, 0.2), bottomRight: (0.8, 0.8), bottomLeft: (0.2, 0.8))
        XCTAssertNil(GR.PhoneFinder.findByShape([wide], pixels: p))
    }

    // MARK: Renk (§3.6)

    func testColorSamplerAveragesAndIlluminates() throws {
        var p = GR.PhonePixels(width: 960, height: 540, fill: GR.RGB(30, 30, 30))
        p.fill(gbox(0.4, 0.2, 0.6, 0.8), GR.RGB(120, 120, 122))
        let s = GR.PhoneColorSampler(pixels: p)
        XCTAssertNil(s.color(x: 0, y: 0.5), "kenar noktası yok")
        XCTAssertEqual(try XCTUnwrap(s.color(x: 0.5, y: 0.5)).r, 120, accuracy: 0.01)
        let lit = s.illuminated(for: GR.PhoneLocation(box: gbox(0.4, 0.2, 0.6, 0.8)))
        XCTAssertEqual(lit.gain, 238 / 122, accuracy: 0.001)
        XCTAssertEqual(lit.illuminated(for: GR.PhoneLocation(box: gbox(0.4, 0.2, 0.6, 0.8), dark: true)).gain, lit.gain)
        XCTAssertEqual(s.illuminated(for: GR.PhoneLocation(box: gbox(0.4, 0.2, 0.6, 0.8), dark: true)).gain, 1)
    }
}
