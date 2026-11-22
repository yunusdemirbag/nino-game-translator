// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

#if canImport(Vision)
import CoreGraphics
import ImageIO
import XCTest
@testable import NinoCore

/// GTA 6, 22 Kasım 23:36–23:41 (Mac 4.5.0 deneme-3): dakikalarca duraklatma menüsünden sonra ara sahne. Ekranda dört
/// altyazı vardı, günlükte yalnız üçüncüsü okundu. Gerçek PS5 kareleri (Mac'in `frames/r-*.jpg` ham kareleri) gerçek
/// zamanlarıyla, sahte saatle Mac'teki gibi verilir: her 100 ms'de ana okuma, ardından köşe turu (menü araması).
///
/// Kök nedenler: (1) menü bayrağı menü kapandıktan sonra da 5 sn açık kalıyor, `You know, if Cal…` ve `Whatever is…`
/// boşaltılıyordu; (2) `we deserve to get paid.` küçük harfle başladığı için telefon oyununun "küçük harfli blok"
/// kuralına takılıyordu (oysa `And after what we went through,` satırının devamı).
final class GameReadingMenuExitTests: XCTestCase {
    /// (yerel saat ms, kare adı). İlk iki kare duraklatma menüsü.
    static let frames: [(Int, String)] = [
        (19_404, "exit-23-41-19-404"), (21_439, "exit-23-41-21-439"), (23_514, "exit-23-41-23-514"),
        (25_554, "exit-23-41-25-554"), (27_618, "exit-23-41-27-618"), (28_524, "exit-23-41-28-524"),
        (29_526, "exit-23-41-29-526"),
    ]

    static func image(_ name: String, dir: String = "gta6-menu-exit") throws -> CGImage {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Resources/" + dir))
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
    }

    static func scaled(_ img: CGImage, width: Int) -> CGImage {
        guard img.width != width else { return img }
        let h = img.height * width / img.width
        let ctx = CGContext(data: nil, width: width, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: h))
        return ctx.makeImage()!
    }

    struct Replay {
        var texts: [String] = []
        var notes: [GR.Output.Note] = []
        var menuEvents = 0
        var journal: [String] = []
    }

    /// Kareleri sırayla verir: her kare bir sonrakinin zamanına dek ekranda kalır (son kare 1 sn). İlk menü karesi
    /// `menuLeadMs` önceden başlar (dakikalarca süren menünün sonu).
    static func replay(width: Int, subtitlesOnly: Bool = false, legacy: Bool = false, menuLeadMs: Int = 6_000,
                       frames: [(Int, String)] = frames) async throws -> Replay {
        let images = try frames.map { ($0.0, scaled(try image($0.1), width: width)) }
        return await replay(images: images, subtitlesOnly: subtitlesOnly, legacy: legacy, leadMs: menuLeadMs)
    }

    /// Hazır görüntülerle (zaman ms, kare) aynı yeniden oynatma.
    static func replay(images frames: [(Int, CGImage)], subtitlesOnly: Bool = false, legacy: Bool = false,
                       leadMs: Int = 0, stepMs: Int = 100, phone: Bool = false,
                       placements: GR.PlacementStore? = nil) async -> Replay {
        let clock = GR.ManualClock(frames[0].0 - leadMs)
        // Mac'teki gibi telefon izleyicisi (telefon oyunu): ana okumaya telefon bilgisi verir, turu ayrıca döner.
        let watcher: GR.PhoneWatcher? = phone
            ? GR.PhoneWatcher(textReader: GR.CPUTextReader(), clock: clock, memory: .init(directory: nil, language: "tr"),
                              translator: nil, rectangles: GR.VisionRectangleDetector())
            : nil
        if let watcher { _ = await watcher.setPhoneGame(true) }
        var cfg = GR.Reader.Configuration()
        GR.GTA6Rules.apply(true, packGame: "gta-6", to: &cfg)
        cfg.subtitlesOnly = subtitlesOnly
        if legacy { cfg.menuClearsOnExit = false; cfg.lowercaseContinuation = false }
        let reader = GR.Reader(textReader: GR.VisionTextReader(), clock: clock, configuration: cfg,
                               placementStore: placements, phone: watcher)
        var r = Replay()
        var journal = GR.SkipJournal()
        let end = frames.last!.0 + 1_000
        while clock.nowMs < end {
            let i = frames.lastIndex { $0.0 <= clock.nowMs } ?? 0
            let frame = GR.ImageFrame(frames[i].1)
            let out = await reader.process(frame)
            r.notes += out.notes
            r.journal += journal.observe(out.notes, now: clock.nowMs)
            for e in out.events {
                switch e {
                case let .subtitleStarted(s), let .subtitleUpdated(s), let .subtitleCorrected(s), let .subtitleRestored(s):
                    r.texts.append(s.text)
                default: break
                }
            }
            for e in await reader.readCorners(frame) {
                if case .menuOpened = e { r.menuEvents += 1; await watcher?.noteMenu(at: clock.nowMs) }
            }
            if let watcher { _ = await watcher.round(frame) }
            clock.advance(stepMs)
        }
        r.journal += journal.flush()
        return r
    }

    static let expected = [
        "you know if cal were here he he d know exactly what to do",
        "whatever is on this thing is worth a lot of fucking money",
        "and after what we went through",
        "we deserve to get paid",
    ]

    func assertAllRead(_ r: Replay, file: StaticString = #filePath, line: UInt = #line) {
        let keys = r.texts.map(GR.Text.key)
        for want in Self.expected {
            XCTAssertTrue(keys.contains { $0.contains(want) || GR.Text.ratio($0, want) >= 0.85 },
                          "okunmadı: \(want)\nokunanlar: \(r.texts)\nnotlar: \(r.journal)", file: file, line: line)
        }
        // `Uh-huh.` (gri, başka konuşan) oyunda aynı kutuda, aynı anda çıkar ve aynı anda kalkar: tek altyazı olarak
        // birlikte gider (TV'de oyundaki gibi iki satır; günlükte `we deserve to get paid. / Uh-huh.`).
        let paid = r.texts.filter { GR.Text.key($0).contains("we deserve to get paid") }
        XCTAssertTrue(paid.contains { GR.Text.key($0).contains("uh huh") }, "\(paid)", file: file, line: line)
        // Menü yazısı altyazı olarak okunmaz.
        XCTAssertFalse(r.texts.contains { k in ["photo studio", "retry checkpoint", "breakfast run", "quit mission"].contains { GR.Text.key(k).contains($0) } },
                       "\(r.texts)", file: file, line: line)
    }

    /// Mac'in gördüğü boyut (Remote Play 1920×1080; menü araması 0,667 ölçekte).
    func testAllFourLinesAreReadAfterPauseMenuAt1920() async throws {
        assertAllRead(try await Self.replay(width: 1920))
    }

    /// 1280 genişlikte menü araması menüyü her karede tanır: canlıdaki menü bayrağı durumu (kök neden 1).
    func testAllFourLinesAreReadAfterPauseMenuAt1280() async throws {
        let r = try await Self.replay(width: 1280)
        XCTAssertGreaterThan(r.menuEvents, 0, "menü tanınmalı")
        assertAllRead(r)
        // Menü açıkken okuma bastırıldı ve günlüğe nedeniyle yazıldı (aynı neden tek satır + özet).
        XCTAssertTrue(r.notes.contains { $0.reason == .menu }, "\(r.notes)")
        XCTAssertEqual(r.journal.filter { $0.hasPrefix("atlandı: menü") && !$0.hasPrefix("özet") }.count, 1, "\(r.journal)")
    }

    /// Eski kurallar (deneme-3) canlıdaki sonucu verir: yalnız `And after what we went through,` okunur; nedenler
    /// günlükte menü ve küçük harfli blok.
    func testLegacyRulesReproduceDeneme3() async throws {
        let r = try await Self.replay(width: 1280, legacy: true)
        XCTAssertEqual(r.texts.map(GR.Text.key), ["and after what we went through"], "\(r.journal)")
        XCTAssertTrue(r.journal.contains { $0.hasPrefix("atlandı: menü \"You know, if Cal") }, "\(r.journal)")
        XCTAssertTrue(r.journal.contains { $0.hasPrefix("atlandı: menü \"Whatever is on this thing") || $0.hasPrefix("atlandı: menü \"-Whatever") }
                      || r.journal.contains { $0.hasPrefix("özet: atlandı: menü") }, "\(r.journal)")
        XCTAssertTrue(r.journal.contains { $0.hasPrefix("atıldı: küçük harfle başlayan blok \"we deserve to get paid.") }, "\(r.journal)")
    }

    func testAllFourLinesAreReadWithSubtitlesOnly() async throws {
        assertAllRead(try await Self.replay(width: 1280, subtitlesOnly: true))
    }

    /// Uzun menü, menü araması arada bir tutmasa da (1920'de Vision sol sütunu kaçırabiliyor) menü yazısı altyazı
    /// olarak okunmaz ve hiçbir altyazı olayı çıkmaz.
    func testLongMenuEmitsNothing() async throws {
        let menu = [(0, "exit-23-41-19-404"), (3_000, "exit-23-41-21-439"), (6_000, "exit-23-41-19-404"),
                    (9_000, "exit-23-41-21-439"), (12_000, "exit-23-41-19-404")]
        for width in [1920, 1280] {
            let r = try await Self.replay(width: width, menuLeadMs: 0, frames: menu)
            XCTAssertEqual(r.texts, [], "\(width)")
        }
    }
}
#endif
