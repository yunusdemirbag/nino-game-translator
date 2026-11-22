// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import CoreGraphics
import Foundation
import NinoCore
import NinoDebugKit
import XCTest
@testable import NinoMacKit

/// Admin bileşik karesi: gizli TV sayfası, f-/latest.jpg bileşimi, video kaydı.
final class CompositeFrameTests: XCTestCase {
    /// Saydam olmayan piksel oranı.
    static func opaqueFraction(_ image: CGImage) -> Double {
        let w = 192, h = 108
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var n = 0
        for i in stride(from: 3, to: px.count, by: 4) where px[i] > 20 { n += 1 }
        return Double(n) / Double(w * h)
    }

    /// Ana iş parçacığında koşul gerçekleşene dek döngüyü çevirir (WKWebView için; async test XCTest'te çöküyor).
    @MainActor
    static func spin(until cond: () -> Bool, timeout: TimeInterval = 15) {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    @MainActor
    static func snap(_ r: TVPageRenderer) -> CGImage? {
        var out: CGImage?
        var done = false
        r.snapshot { out = $0; done = true }
        spin(until: { done }, timeout: 10)
        return out
    }

    @MainActor
    func testTVPageDrawsShowOnTransparentLayer() throws {
        XCTAssertNotNil(TVPageRenderer.pageFolder(), "TVPage paketin içinde olmalı")
        let r = TVPageRenderer()
        Self.spin(until: { r.isReady })
        XCTAssertTrue(r.isReady, "sayfa açılmalı")
        let empty = try XCTUnwrap(Self.snap(r))
        XCTAssertLessThan(Self.opaqueFraction(empty), 0.02, "boş katman saydam")
        r.receive(NinoMessage.show(ShowPayload(id: 1, text: "Merhaba dünya, bu bir deneme altyazısı", durationMs: 0)).jsonString)
        Self.spin(until: { false }, timeout: 0.8)
        let shown = try XCTUnwrap(Self.snap(r))
        let f = Self.opaqueFraction(shown)
        // Ekran öğesi (kart) de çizilir.
        let card = ScreenItem(box: NinoBox(left: 0.62, top: 0.1, right: 0.95, bottom: 0.3), text: "Mesaj: Yarın görüşürüz", card: true)
        r.receive(NinoEvent.screen(ScreenPayload(items: [card], durationMs: 0)).jsonString)
        Self.spin(until: { false }, timeout: 0.8)
        let withCard = try XCTUnwrap(Self.snap(r))
        XCTAssertGreaterThan(Self.opaqueFraction(withCard), f, "kart da çizilmeli")
        if let dump = ProcessInfo.processInfo.environment["NINO_TVPAGE_DUMP"] {
            DebugImageIO.write(withCard, to: URL(fileURLWithPath: dump), type: .png)
        }
        XCTAssertGreaterThan(f, 0.005, "altyazı çizilmeli")
        XCTAssertLessThan(f, 0.5, "zemin saydam kalmalı")
        r.close()
    }

    @MainActor
    func testTVPageReplaysLastStateAndScreenCards() throws {
        let r = TVPageRenderer()
        // Sayfa açılmadan gelenler: açılınca son durum kurulur.
        r.receive(NinoEvent.style(NinoStyle(SubtitleStyle())).jsonString)
        r.receive(NinoMessage.show(ShowPayload(id: 2, text: "Önceden gelen satır", durationMs: 0)).jsonString)
        r.receive(NinoMessage.clear(id: 2).jsonString)
        r.receive(NinoMessage.show(ShowPayload(id: 3, text: "Son satır", durationMs: 0)).jsonString)
        XCTAssertEqual(r.replayMessages.count, 2, "style + son show")
        Self.spin(until: { r.isReady })
        Self.spin(until: { false }, timeout: 0.8)
        let img = try XCTUnwrap(Self.snap(r))
        XCTAssertGreaterThan(Self.opaqueFraction(img), 0.001, "tekrarlanan altyazı çizilmeli")
        r.receive(NinoEvent.stopped.jsonString)
        XCTAssertEqual(r.replayMessages.count, 1, "durunca yalnız style kalır")
        r.close()
    }

    func testLayerRules() {
        XCTAssertTrue(TVLayerRules.changesLayer(NinoMessage.show(ShowPayload(id: 1, text: "x")).jsonString))
        XCTAssertTrue(TVLayerRules.changesLayer(NinoEvent.screenClear.jsonString))
        XCTAssertFalse(TVLayerRules.changesLayer(NinoEvent.started.jsonString))
        XCTAssertFalse(TVLayerRules.changesLayer("bozuk"))
    }

    func testCompositeAndChangeTriggeredFrames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nino-frames-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let rec = DebugFrameRecorder(folder: root) { DebugFrameContext(readingArea: nil, textBox: nil, read: "a", translation: "b") }
        // Katman: üst yarısı opak kırmızı, alt yarısı saydam.
        let layer: CGImage = {
            let ctx = CGContext(data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 18, width: 64, height: 18))
            return ctx.makeImage()!
        }()
        rec.overlay = { layer }
        final class Got: @unchecked Sendable { var images: [CGImage] = []; let lock = NSLock() }
        let got = Got()
        rec.onComposite = { img in got.lock.withLock { got.images.append(img) } }
        let frame = DebugRecordTests.image(width: 640, height: 360)
        rec.offer(frame)
        rec.drain()
        rec.offer(frame) // 2 sn dolmadı: yazılmaz
        rec.drain()
        XCTAssertEqual(got.lock.withLock { got.images.count }, 1)
        rec.requestSoon(now: Date().addingTimeInterval(-1)) // değişiklik: bekleme geçmiş
        rec.offer(frame)
        rec.drain()
        XCTAssertEqual(got.lock.withLock { got.images.count }, 2, "değişince hemen yeni kare")
        let latest = try XCTUnwrap(DebugImageIO.read(root.appendingPathComponent("latest.jpg")))
        let composite = try XCTUnwrap(got.lock.withLock { got.images.last })
        XCTAssertEqual(latest.width, 640)
        // Bileşikte üst kısım kırmızı (katman), alt kısım karenin rengi.
        func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
            var p = [UInt8](repeating: 0, count: 4)
            let ctx = CGContext(data: &p, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img, in: CGRect(x: -x, y: -(img.height - 1 - y), width: img.width, height: img.height))
            return (p[0], p[1], p[2])
        }
        let top = pixel(composite, 10, composite.height / 2 - 40)
        XCTAssertGreaterThan(top.0, 200); XCTAssertLessThan(top.1, 40)
        let bottom = pixel(composite, 10, composite.height - 5)
        XCTAssertLessThan(bottom.0, 120, "katmanın saydam yeri karenin kendisi")
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(names.filter { $0.hasPrefix("f-") }.count, 2)
    }

    func testVideoRecordingWithFlagAndRing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nino-frames-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let rec = DebugFrameRecorder(folder: root) { DebugFrameContext(readingArea: nil, textBox: nil, read: "", translation: "") }
        let frame = DebugRecordTests.image(width: 640, height: 360)
        rec.offer(frame)
        rec.drain()
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: rec.videoFolder.path).contains { $0.hasSuffix(".mov") },
                       "KAYIT yokken video yok")
        FileManager.default.createFile(atPath: rec.recordFlag.path, contents: nil)
        let deadline = Date().addingTimeInterval(3)
        while !rec.isRecording, Date() < deadline { usleep(20_000) }
        XCTAssertTrue(rec.isRecording)
        for _ in 0..<5 {
            rec.offer(frame)
            rec.drain()
            usleep(110_000)
        }
        rec.finishVideo()
        let movs = try FileManager.default.contentsOfDirectory(atPath: rec.videoFolder.path).filter { $0.hasSuffix(".mov") }
        XCTAssertEqual(movs.count, 1)
        let mov = rec.videoFolder.appendingPathComponent(movs[0])
        XCTAssertGreaterThanOrEqual(DebugExport.frameTimes(mov).count, 4)
        XCTAssertNotNil(DebugRecordLayout.parseName(movs[0])?.end, "kapanan parçanın adında bitiş var")
        // Halka: sınır küçükse eski parça gider, KAYIT kalır.
        FileManager.default.createFile(atPath: rec.videoFolder.appendingPathComponent("1000-2000.mov").path, contents: Data(count: 50_000))
        rec.pruneVideo(limit: 10)
        let left = try FileManager.default.contentsOfDirectory(atPath: rec.videoFolder.path)
        XCTAssertTrue(left.contains("KAYIT"))
        XCTAssertFalse(left.contains("1000-2000.mov"))
    }

    /// Bileşik kare: okuma kutuları ince kesikli ve TV katmanının ALTINDA (kutu TV'nin çizdiği sanılmasın); harita kartı
    /// kutusuna tam oturur ve opaktır, görev şeridi orijinali örter, vurgu pembe (22 Kasım, GTA 6 "Go to the docks").
    /// `NINO_COMPOSITE_FRAME=<ham kare>` ve `NINO_COMPOSITE_DUMP=<çıktı.jpg>` ile gerçek kareyle görsel doğrulama.
    @MainActor
    func testCompositeKeepsTVLayerOverReadingBoxes() throws {
        let r = TVPageRenderer()
        Self.spin(until: { r.isReady })
        let card = ScreenItem(box: NinoBox(left: 0.530, top: 0.357, right: 0.820, bottom: 0.640),
                              text: "UNCLE JACK'S LIQUOR - PORT GELLHORN\nBira, atıştırmalık ve sigara satan içki dükkânı.\n"
                                  + "ÖZELLİKLER\nGÜVENLİK: DÜŞÜK\nKAZANÇ: $100 - $1,000",
                              line: 0.0302, paragraphs: true, card: true)
        let strip = ScreenItem(box: NinoBox(left: 0.4454, top: 0.9339, right: 0.5547, bottom: 0.9561), text: "⟦Limanlara⟧ git",
                               line: 0.0222)
        r.receive(NinoEvent.screen(ScreenPayload(items: [card, strip], durationMs: 0, overlay: true)).jsonString)
        Self.spin(until: { false }, timeout: 1.2)
        let layer = try XCTUnwrap(Self.snap(r))
        r.close()
        var frame: CGImage
        if let path = ProcessInfo.processInfo.environment["NINO_COMPOSITE_FRAME"], let img = DebugImageIO.read(URL(fileURLWithPath: path)) {
            frame = img
        } else {
            let ctx = CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.5, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 1280, height: 720))
            frame = ctx.makeImage()!
        }
        // Okunan kutu kartın ortasından geçer: TV katmanı onu örtmeli.
        let c = DebugFrameContext(readingArea: GameReading.Box(left: 0.1, top: 0.2, right: 0.9, bottom: 0.98),
                                  textBox: GameReading.Box(left: 0.55, top: 0.45, right: 0.80, bottom: 0.50),
                                  read: "Go to the docks", translation: "Limanlara git")
        let drawn = try XCTUnwrap(DebugFrameRecorder.annotate(frame, context: c, overlay: layer))
        if let dump = ProcessInfo.processInfo.environment["NINO_COMPOSITE_DUMP"] {
            _ = DebugImageIO.write(drawn, to: URL(fileURLWithPath: dump), type: .jpeg, quality: 0.85)
        }
        // Kartın içindeki kırmızı kutu kenarı görünmez (kart opak ve üstte).
        let w = drawn.width, h = drawn.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(drawn, in: CGRect(x: 0, y: 0, width: w, height: h))
        var red = 0
        let y0 = Int(0.45 * Double(h)) - 2, y1 = Int(0.45 * Double(h)) + 2
        for y in y0...y1 {
            for x in Int(0.56 * Double(w))..<Int(0.79 * Double(w)) {
                let i = (y * w + x) * 4
                if px[i] > 200, px[i + 1] < 80, px[i + 2] < 80 { red += 1 }
            }
        }
        XCTAssertEqual(red, 0, "okuma kutusu TV kartının üstüne çizilmez")
    }
}
