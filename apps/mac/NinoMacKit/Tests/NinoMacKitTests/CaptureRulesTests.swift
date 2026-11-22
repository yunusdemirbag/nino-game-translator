// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import XCTest
@testable import NinoMacKit

/// Görüntü kaynaklarının saf kuralları (kaynaklar.md §2–§4). Ekran kaydı, kamera ve ağ kullanılmaz.
final class CaptureRulesTests: XCTestCase {
    /// 14 inç MacBook Pro'nun ekranı (nokta).
    let display = CGRect(origin: .zero, size: CGSize(width: 1512, height: 982))

    func win(_ id: UInt32, _ app: String, _ bundle: String = "", title: String = "", w: CGFloat = 1280, h: CGFloat = 720,
             x: CGFloat = 0, y: CGFloat = 0, onScreen: Bool = true, own: Bool = false, layer: Int = 0) -> CaptureWindowInfo {
        CaptureWindowInfo(id: id, appName: app, bundleID: bundle, title: title, frame: CGRect(x: x, y: y, width: w, height: h),
                          layer: layer, isOnScreen: onScreen, isOwn: own)
    }

    // MARK: Pencere seçimi

    func testPlayStationPicksLargestRemotePlayWindow() {
        let windows = [
            win(1, "PS Remote Play", "com.playstation.RemotePlay", w: 800, h: 450),
            win(2, "chiaki-ng", "org.streetpea.chiaking", w: 1600, h: 900),
            win(3, "Nino", "com.ninotranslator.mac", w: 1900, h: 1000, own: true),
            win(4, "Safari", "com.apple.Safari", title: "Remote Play", w: 1800, h: 1000),
            win(5, "PS Remote Play", "com.playstation.RemotePlay", w: 300, h: 170),
            win(6, "PS Remote Play", "com.playstation.RemotePlay", w: 1700, h: 950, onScreen: false),
        ]
        XCTAssertEqual(WindowRules.pick(windows, target: .playStation(.automatic), displays: [display])?.id, 2)
        XCTAssertEqual(WindowRules.pick(windows, target: .playStation(.sony), displays: [display])?.id, 1)
        XCTAssertEqual(WindowRules.pick(windows, target: .playStation(.chiaki), displays: [display])?.id, 2)
        XCTAssertNil(WindowRules.pick([windows[2], windows[4]], target: .playStation(.automatic), displays: [display]))
        // Geliştirici hedefi.
        XCTAssertEqual(WindowRules.pick(windows, target: .playStation(.automatic, customMatch: "Safari"), displays: [display])?.id, 4)
    }

    func testPlayStationIgnoresOtherLayers() {
        let w = win(1, "PS Remote Play", layer: 3)
        XCTAssertNil(WindowRules.pick([w], target: .playStation(.automatic), displays: [display]))
    }

    func testXboxOrder() {
        let stream = win(1, "Greenlight", "com.unknownskl.greenlight", title: "Greenlight - Streaming F4001234ABCD", w: 900, h: 506)
        let menu = win(2, "Greenlight", "com.unknownskl.greenlight", title: "Greenlight - My consoles", w: 1400, h: 800)
        let browser = win(3, "Google Chrome", "com.google.Chrome", title: "Xbox Cloud Gaming", w: 1300, h: 760, onScreen: false)
        let other = win(4, "Firefox", "org.mozilla.firefox", title: "Halo Infinite", w: 1512, h: 950, y: 32)
        let all = [stream, menu, browser, other]
        XCTAssertEqual(WindowRules.pick(all, target: .xbox, displays: [display])?.id, 1, "önce yayın penceresi")
        XCTAssertEqual(WindowRules.pick([menu, browser, other], target: .xbox, displays: [display])?.id, 2,
                       "sonra Greenlight'ın ya da başlığı uyan tarayıcının en büyüğü")
        XCTAssertEqual(WindowRules.pick([browser, other], target: .xbox, displays: [display])?.id, 3,
                       "ekranda olmayan tarayıcı da sayılır")
        XCTAssertEqual(WindowRules.pick([other], target: .xbox, displays: [display])?.id, 4, "ekranı kaplayan tarayıcı")
        let smallBrowser = win(5, "Safari", "com.apple.Safari", title: "Halo", w: 900, h: 600)
        XCTAssertNil(WindowRules.pick([smallBrowser], target: .xbox, displays: [display]))
        let turkish = win(6, "Safari", "com.apple.Safari", title: "Uzaktan oynama | Xbox", w: 900, h: 600)
        XCTAssertEqual(WindowRules.pick([turkish], target: .xbox, displays: [display])?.id, 6)
    }

    func testGreenlightStreamTitle() {
        XCTAssertTrue(WindowRules.isGreenlightStreamTitle("Greenlight - Streaming F4001234ABCD"))
        XCTAssertTrue(WindowRules.isGreenlightStreamTitle("Greenlight - Yayın 0123abcd"))
        XCTAssertFalse(WindowRules.isGreenlightStreamTitle("Greenlight - My consoles"))
        XCTAssertFalse(WindowRules.isGreenlightStreamTitle("Greenlight - Streaming ABCDEFAB"), "rakamsız kimlik")
        XCTAssertFalse(WindowRules.isGreenlightStreamTitle("Greenlight - Streaming 1234ab"), "8'den kısa")
        XCTAssertFalse(WindowRules.isGreenlightStreamTitle("Greenlight - F4001234ABCD"), "orta kelime yok")
        XCTAssertFalse(WindowRules.isGreenlightStreamTitle("Xbox - Streaming F4001234ABCD"))
    }

    func testFullScreen() {
        XCTAssertTrue(WindowRules.isFullScreen(CGRect(x: 0, y: 32, width: 1512, height: 950), displays: [display]),
                      "çentikli ekranda kısa tam ekran")
        XCTAssertTrue(WindowRules.isFullScreen(CGRect(x: 1, y: 1, width: 1511, height: 983), displays: [display]))
        XCTAssertFalse(WindowRules.isFullScreen(CGRect(x: 0, y: 200, width: 1512, height: 782), displays: [display]))
        XCTAssertFalse(WindowRules.isFullScreen(CGRect(x: 100, y: 0, width: 1412, height: 982), displays: [display]))
        let second = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        XCTAssertTrue(WindowRules.isFullScreen(CGRect(x: 1512, y: 0, width: 1920, height: 1080), displays: [display, second]))
    }

    func testGameArea() {
        // Pencere 1280×748: başlık 28 düşülünce 1280×720 kalır, tam 16:9.
        XCTAssertEqual(WindowRules.gameArea(windowSize: CGSize(width: 1280, height: 748), fullScreen: false),
                       CGRect(origin: CGPoint(x: 0, y: 28), size: CGSize(width: 1280, height: 720)))
        // Tam ekranda başlık düşülmez; geniş ekranda yanlarda bant.
        XCTAssertEqual(WindowRules.gameArea(windowSize: CGSize(width: 2000, height: 900), fullScreen: true),
                       CGRect(x: 200, y: 0, width: 1600, height: 900))
        // Uzun pencere: üst ve alt bant, başlık sonrası ortalanır.
        XCTAssertEqual(WindowRules.gameArea(windowSize: CGSize(width: 1600, height: 1228), fullScreen: false),
                       CGRect(x: 0, y: 28 + (1200 - 900) / 2, width: 1600, height: 900))
        // Başlık en çok yüksekliğin ¼'ü.
        let small = WindowRules.gameArea(windowSize: CGSize(width: 320, height: 80), fullScreen: false)
        XCTAssertEqual(small.minY, 20)
        XCTAssertEqual(small.height, 60)
        XCTAssertEqual(small.width, 60 * 16 / 9, accuracy: 0.001)
        XCTAssertEqual(small.midX, 160, accuracy: 0.001)
        XCTAssertEqual(WindowRules.fit16x9(in: .zero), .zero)
    }

    func testAppKitRect() {
        let r = WindowRules.appKitRect(CGRect(x: 10, y: 100, width: 640, height: 360), primaryHeight: 982)
        XCTAssertEqual(r, CGRect(x: 10, y: 982 - 460, width: 640, height: 360))
    }

    func testWindowDecision() {
        let w = win(7, "PS Remote Play", w: 1280, h: 748)
        XCTAssertEqual(WindowDecision.decide(currentID: nil, currentFrame: nil, picked: nil), .keepSearching)
        XCTAssertEqual(WindowDecision.decide(currentID: 7, currentFrame: w.frame, picked: nil), .stop)
        XCTAssertEqual(WindowDecision.decide(currentID: nil, currentFrame: nil, picked: w), .restart)
        XCTAssertEqual(WindowDecision.decide(currentID: 3, currentFrame: w.frame, picked: w), .restart)
        XCTAssertEqual(WindowDecision.decide(currentID: 7, currentFrame: w.frame, picked: w), .keep)
        XCTAssertEqual(WindowDecision.decide(currentID: 7, currentFrame: .zero, picked: w), .updateArea)
    }

    func testCandidateLines() {
        let windows = (0..<20).map { win(UInt32($0), "App\($0)", w: 800, h: 600) }
            + [win(99, "Safari", "com.apple.Safari", title: "x", w: 100, h: 100), win(100, "Tiny", w: 100, h: 100)]
        let lines = WindowRules.candidateLines(windows, target: .xbox, displays: [display])
        XCTAssertEqual(lines.count, 12)
        XCTAssertEqual(lines.first, "App0 \"\" 800x600")
        let full = WindowRules.candidateLines([win(1, "Safari", "com.apple.Safari", title: "Halo", w: 1512, h: 982)],
                                              target: .xbox, displays: [display])
        XCTAssertEqual(full, ["Safari \"Halo\" 1512x982 tam ekran"])
    }

    func testRemotePlayInstalled() {
        let onlyChiaki: (String) -> Bool = { $0 == RemotePlayApps.chiakiBundleID }
        XCTAssertTrue(RemotePlayApps.installed(choice: .automatic, isInstalled: onlyChiaki))
        XCTAssertTrue(RemotePlayApps.installed(choice: .chiaki, isInstalled: onlyChiaki))
        XCTAssertFalse(RemotePlayApps.installed(choice: .sony, isInstalled: onlyChiaki))
        XCTAssertFalse(RemotePlayApps.installed(choice: .automatic, isInstalled: { _ in false }))
    }

    // MARK: Kart

    func testCardDevicePick() {
        let devices = [
            CardDeviceInfo(id: "a", name: "iPhone Camera"),
            CardDeviceInfo(id: "b", name: "Logitech BRIO"),
            CardDeviceInfo(id: "c", name: "Generic Device"),
            CardDeviceInfo(id: "d", name: "Elgato HD60 X"),
        ]
        XCTAssertEqual(CardRules.pickDevice(devices, preferredID: nil)?.id, "d")
        XCTAssertEqual(CardRules.pickDevice(devices, preferredID: "b")?.id, "b", "seçilen takılıysa o")
        XCTAssertEqual(CardRules.pickDevice(devices, preferredID: "gone")?.id, "d")
        XCTAssertEqual(CardRules.pickDevice(Array(devices.prefix(3)), preferredID: nil)?.id, "c", "ipucu yoksa kalan ilki")
        XCTAssertNil(CardRules.pickDevice(Array(devices.prefix(2)), preferredID: nil), "yalnız web kameraları")
    }

    func testCardAudioMatch() {
        let card = CardDeviceInfo(id: "v", name: "USB3.0 Capture", modelID: "UVC 345F:2130")
        let audio = [CardDeviceInfo(id: "m", name: "MacBook Microphone", modelID: "Built-in"),
                     CardDeviceInfo(id: "x", name: "Digital Audio", modelID: "UVC 345F:2130")]
        XCTAssertEqual(CardRules.matchAudio(for: card, in: audio)?.id, "x")
        let named = [CardDeviceInfo(id: "n", name: "USB3.0 Capture Audio")]
        XCTAssertEqual(CardRules.matchAudio(for: CardDeviceInfo(id: "v", name: "USB3.0 Capture"), in: named)?.id, "n")
        XCTAssertNil(CardRules.matchAudio(for: CardDeviceInfo(id: "v", name: "Cam Link"), in: audio))
    }

    func testBlackFrame() {
        let width = 100, height = 70, bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 10, count: bytesPerRow * height)
        pixels.withUnsafeBytes { XCTAssertTrue(CardRules.isBlack(base: $0.baseAddress!, width: width, height: height, bytesPerRow: bytesPerRow)) }
        // Örneklenmeyen pikseldeki parlaklık sayılmaz.
        pixels[(5 * bytesPerRow) + 5 * 4 + 1] = 255
        pixels.withUnsafeBytes { XCTAssertTrue(CardRules.isBlack(base: $0.baseAddress!, width: width, height: height, bytesPerRow: bytesPerRow)) }
        // (64, 32) örneklenir.
        pixels[(32 * bytesPerRow) + 64 * 4 + 2] = 24
        pixels.withUnsafeBytes { XCTAssertFalse(CardRules.isBlack(base: $0.baseAddress!, width: width, height: height, bytesPerRow: bytesPerRow)) }
    }

    func testWatchdogBlack() {
        var dog = CardWatchdog(now: 0)
        XCTAssertNil(dog.frame(now: 0.1, black: true))
        XCTAssertNil(dog.frame(now: 3.9, black: true))
        XCTAssertEqual(dog.frame(now: 4.2, black: true), .black)
        XCTAssertNil(dog.frame(now: 5, black: true))
        XCTAssertEqual(dog.frame(now: 5.1, black: false), .reading)
        XCTAssertNil(dog.frame(now: 5.2, black: true), "siyahlık yeniden 4 sn beklenir")
        XCTAssertNil(dog.frame(now: 9.1, black: true))
        XCTAssertEqual(dog.frame(now: 9.4, black: true), .black)
    }

    func testWatchdogStallBackoff() {
        var dog = CardWatchdog(now: 0)
        XCTAssertFalse(dog.tick(now: 1))
        XCTAssertFalse(dog.tick(now: 2.9))
        XCTAssertTrue(dog.tick(now: 3))
        XCTAssertEqual(dog.stallLimit, 6)
        XCTAssertFalse(dog.tick(now: 8))
        XCTAssertTrue(dog.tick(now: 9))
        XCTAssertTrue(dog.tick(now: 21))
        XCTAssertTrue(dog.tick(now: 45))
        XCTAssertEqual(dog.stallLimit, 30)
        XCTAssertTrue(dog.tick(now: 75))
        XCTAssertEqual(dog.stallLimit, 30, "en çok 30 sn")
        dog.frame(now: 76, black: false)
        XCTAssertEqual(dog.stallLimit, 3, "kare gelince 3 sn'ye döner")
        XCTAssertFalse(dog.tick(now: 78))
        XCTAssertTrue(dog.tick(now: 79))
    }

    func testFrameThrottle() {
        var t = FrameThrottle(rate: 10)
        var passed = 0
        for i in 0..<60 where t.shouldPass(now: Double(i) / 60) { passed += 1 }
        XCTAssertEqual(passed, 10)
    }

    func testCardStatusMapping() {
        XCTAssertEqual(CardRules.link(.reading(cardName: "HD60")), .streaming)
        XCTAssertEqual(CardRules.link(.black), .streaming)
        XCTAssertEqual(CardRules.link(.idle), .disconnected)
        XCTAssertEqual(CardRules.link(.cameraDenied), .connecting)
        XCTAssertEqual(CardRules.link(.noCard), .connecting)
        XCTAssertEqual(CardRules.checkStatus(.reading(cardName: "HD60")), .working(name: "HD60"))
        XCTAssertEqual(CardRules.checkStatus(.cameraDenied), .noPermission)
        XCTAssertEqual(CardRules.checkStatus(.noCard), .noCard)
        XCTAssertEqual(CardRules.checkStatus(.black), .black)
        XCTAssertEqual(CardRules.checkStatus(.idle), .searching)
        XCTAssertEqual(CardRules.checkStatus(.idle, stoppedName: "HD60"), .stopped(name: "HD60"))
    }

    // MARK: Metinler

    func testCaptureStringsHaveEnglishAndTurkish() {
        for key in ["capture.greenlight.error.latest", "capture.greenlight.error.download",
                    "capture.greenlight.error.damaged", "capture.greenlight.error.copy"] {
            let en = NinoL10n.string(key, table: "Capture", language: "en")
            let tr = NinoL10n.string(key, table: "Capture", language: "tr")
            XCTAssertNotEqual(en, key, key)
            XCTAssertNotEqual(tr, key, key)
            XCTAssertNotEqual(en, tr, key)
        }
    }
}
