// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import XCTest
import NinoCore
@testable import NinoMacKit

/// AppSupport/'un saf kuralları ve sahte güncelleyiciyle kurma zamanı. Ağ, kullanıcı verisi, gerçek süreç yok.
@MainActor
final class AppSupportTests: XCTestCase {
    // MARK: Kurma zamanı

    func testInstallTimingDecision() {
        typealias T = UpdateInstallTiming
        XCTAssertEqual(T.decide(translation: .off, setupComplete: true, translationJustStopped: false), .installNow)
        XCTAssertEqual(T.decide(translation: .off, setupComplete: true, translationJustStopped: true), .installAfter(2))
        XCTAssertEqual(T.decide(translation: .on, setupComplete: true, translationJustStopped: false), .wait)
        XCTAssertEqual(T.decide(translation: .starting, setupComplete: true, translationJustStopped: false), .wait)
        XCTAssertEqual(T.decide(translation: .off, setupComplete: false, translationJustStopped: false), .wait)
        XCTAssertEqual(T.restart(translation: .on), .markResumeThenStopThenInstall)
        XCTAssertEqual(T.restart(translation: .off), .installNow)
        XCTAssertTrue(T.shouldResume(markedAt: 1_000, now: 1_120))
        XCTAssertFalse(T.shouldResume(markedAt: 1_000, now: 1_121))
        XCTAssertFalse(T.shouldResume(markedAt: 1_000, now: 999))
    }

    func testCoordinatorInstallsImmediatelyWhenIdle() async {
        let state = AppState()
        state.setupStep = .done
        let auto = FakeAutoUpdater()
        let c = UpdateCoordinator(checker: FakeUpdateService(), auto: auto, state: state,
                                  stopTranslation: {}, markResume: {}, sleep: { _ in })
        auto.onEvent?(.found(version: "4.2.0"))
        XCTAssertEqual(state.update, .downloading(version: "4.2.0", progress: nil))
        auto.onEvent?(.downloaded(version: "4.2.0"))
        XCTAssertEqual(auto.installs, 1)
        XCTAssertEqual(c.installRequests, 1)
    }

    func testCoordinatorWaitsForTranslationThenInstallsAfterStop() async throws {
        let state = AppState()
        state.setupStep = .done
        state.translation = .on
        let auto = FakeAutoUpdater()
        let c = UpdateCoordinator(checker: FakeUpdateService(), auto: auto, state: state,
                                  stopTranslation: {}, markResume: {}, sleep: { _ in })
        auto.onEvent?(.downloaded(version: "4.2.0"))
        XCTAssertEqual(auto.installs, 0)
        XCTAssertEqual(state.update, .waitingForTranslationToStop(version: "4.2.0"))
        state.translation = .off
        for _ in 0..<50 where auto.installs == 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(auto.installs, 1)
        _ = c
    }

    func testRestartWhileTranslatingMarksResumeAndStopsFirst() async throws {
        let state = AppState()
        state.setupStep = .done
        state.translation = .on
        let auto = FakeAutoUpdater()
        var order: [String] = []
        let c = UpdateCoordinator(checker: FakeUpdateService(), auto: auto, state: state,
                                  stopTranslation: { order.append("stop") }, markResume: { order.append("mark") },
                                  sleep: { _ in })
        auto.onEvent?(.downloaded(version: "4.2.0"))
        auto.onInstall = { order.append("install") }
        c.install()
        for _ in 0..<50 where auto.installs == 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(order, ["mark", "stop", "install"])
    }

    func testDownloadingButtonDoesNothingAndUnknownOpensWindow() async {
        let state = AppState()
        state.setupStep = .done
        let auto = FakeAutoUpdater()
        let c = UpdateCoordinator(checker: FakeUpdateService(), auto: auto, state: state,
                                  stopTranslation: {}, markResume: {}, sleep: { _ in try? await Task.sleep(for: .seconds(60)) })
        c.install()
        XCTAssertEqual(auto.windows, 1)
        auto.onEvent?(.found(version: "4.2.0"))
        c.install()
        XCTAssertEqual(auto.windows, 1)
        XCTAssertEqual(auto.installs, 0)
        // İniyorken denetim durumu bozmaz.
        let r = await c.check(force: true)
        XCTAssertEqual(r, .skipped)
    }

    func testNoAutoUpdaterFallsBackToBrowserInstall() async {
        let state = AppState()
        let checker = FakeUpdateService()
        let c = UpdateCoordinator(checker: checker, auto: nil, state: state, stopTranslation: {}, markResume: {})
        c.install()
        XCTAssertEqual(checker.installs, 1)
    }

    // MARK: Kısayollar

    func testHotKeyConditions() {
        XCTAssertEqual(HotKeyRules.wanted(translation: .off, subtitlesOnComputer: true), [])
        XCTAssertEqual(HotKeyRules.wanted(translation: .starting, subtitlesOnComputer: true), [])
        XCTAssertEqual(HotKeyRules.wanted(translation: .on, subtitlesOnComputer: false), [.translateScreen])
        XCTAssertEqual(HotKeyRules.wanted(translation: .on, subtitlesOnComputer: true), [.translateScreen, .clickThrough])
        let d = HotKeyRules.diff(held: [.translateScreen, .clickThrough], wanted: [.translateScreen])
        XCTAssertEqual(d.release, [.clickThrough])
        XCTAssertEqual(d.register, [])
    }

    func testHotKeyControllerFollowsStateAndReleasesScreenJob() async throws {
        let state = AppState()
        var held: Set<GlobalHotKey> = []
        var released = 0
        let c = HotKeyController(state: state, register: { k, _ in held.insert(k); return true },
                                 unregister: { held.remove($0) }, onTranslateScreenReleased: { released += 1 })
        XCTAssertEqual(held, [])
        state.translation = .on
        for _ in 0..<50 where held.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(held.contains(.translateScreen))
        state.translation = .off
        for _ in 0..<50 where !held.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(held, [])
        XCTAssertEqual(released, 1)
        _ = c
    }

    func testClickThroughHotKeyTogglesSetting() {
        let state = AppState()
        let c = HotKeyController(state: state, register: { _, _ in true }, unregister: { _ in },
                                 onTranslateScreenReleased: {})
        let before = state.settings.overlayClickThrough
        c.pressed(.clickThrough)
        XCTAssertEqual(state.settings.overlayClickThrough, !before)
    }

    func testCarbonKeyCodes() {
        XCTAssertEqual(GlobalHotKey.translateScreen.keyCode, 0x11)
        XCTAssertEqual(GlobalHotKey.clickThrough.keyCode, 0x25)
    }

    // MARK: Ekranı çevir

    func testScreenPressRules() {
        XCTAssertEqual(ScreenTranslationRules.press(running: false, showing: false), .start)
        XCTAssertEqual(ScreenTranslationRules.press(running: true, showing: false), .cancelRunning)
        XCTAssertEqual(ScreenTranslationRules.press(running: false, showing: true), .removeShown)
        XCTAssertTrue(ScreenTranslationRules.isUnchanged(source: ["OPTIONS"], translated: ["Options"]))
        XCTAssertFalse(ScreenTranslationRules.isUnchanged(source: ["Continue"], translated: ["Devam et"]))
        XCTAssertEqual(ScreenTranslationRules.Message.noPicture.durationMs, 4_000)
        XCTAssertEqual(ScreenTranslationRules.Message.translating.durationMs, 2_500)
    }

    func testScreenGroupTranslationKeepsIcons() async {
        let line = GameReading.Line("Press ✕ to continue.", box: GameReading.Box(left: 0.1, top: 0.1, right: 0.5, bottom: 0.14))
        let group = GameReading.ScreenGroups.groups([line]).first!
        let out = await ScreenTranslationRules.translateGroup(group) { text in
            text.replacingOccurrences(of: "Press", with: "Bas").replacingOccurrences(of: "to continue.", with: "devam et.")
        }
        XCTAssertEqual(out?.text.first?.contains("✕"), true)
        XCTAssertEqual(out?.text.first?.hasPrefix("Bas"), true)
    }

    func testScreenMessagesAreLocalized() {
        let tr = NinoL10n.string(ScreenTranslationRules.Message.noText.key, table: "AppSupport", language: "tr")
        let en = NinoL10n.string(ScreenTranslationRules.Message.noText.key, table: "AppSupport", language: "en")
        XCTAssertNotEqual(tr, en)
        XCTAssertFalse(tr.hasPrefix("support."))
    }

    // MARK: Debug kareleri

    func testDebugFrameLimitAndInterval() {
        var names: [String] = ["latest.jpg"]
        for i in 0..<130 { names.append(String(format: "f-2026-11-22T10-00-%03d.jpg", i)) }
        for i in 0..<5 { names.append(String(format: "r-2026-11-22T10-00-%03d.jpg", i)) }
        let gone = DebugFrameRules.filesToDelete(names)
        XCTAssertEqual(gone.count, 10)
        XCTAssertTrue(gone.allSatisfy { $0.hasPrefix("f-") })
        XCTAssertEqual(gone.first, "f-2026-11-22T10-00-000.jpg")
        XCTAssertFalse(gone.contains("latest.jpg"))
        XCTAssertTrue(DebugFrameRules.isDue(now: 10, last: nil))
        XCTAssertFalse(DebugFrameRules.isDue(now: 11.9, last: 10))
        XCTAssertTrue(DebugFrameRules.isDue(now: 12, last: 10))
        XCTAssertTrue(DebugFrameRules.isVideoFrameDue(nowMs: 1_100, lastMs: 1_000))
        XCTAssertFalse(DebugFrameRules.isVideoFrameDue(nowMs: 1_050, lastMs: 1_000))
        XCTAssertFalse(DebugFrameRules.stamp(Date(timeIntervalSince1970: 0)).contains(":"))
    }

    func testDebugFramesWriteAndPrune() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nino-frames-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let recorder = DebugFrameRecorder(folder: dir) {
            DebugFrameContext(readingArea: GameReading.Box(left: 0.1, top: 0.7, right: 0.9, bottom: 0.95),
                              textBox: GameReading.Box(left: 0.3, top: 0.8, right: 0.7, bottom: 0.85),
                              read: "Hello", translation: "Merhaba")
        }
        recorder.offer(Self.image(width: 320, height: 180))
        let latest = dir.appendingPathComponent("latest.jpg")
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: latest.path) { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: latest.path))
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("f-") })
        XCTAssertTrue(names.contains { $0.hasPrefix("r-") })
        XCTAssertFalse(recorder.isRecording)
    }

    // MARK: Admin modu

    func testAdminModeNeverAutoStartsInDevelopment() {
        XCTAssertTrue(AdminModeRules.isOn(flavor: .development, flag: false))
        XCTAssertFalse(AdminModeRules.isOn(flavor: .release, flag: false))
        XCTAssertTrue(AdminModeRules.isOn(flavor: .release, flag: true))
        XCTAssertFalse(AdminModeRules.isOn(flavor: .testing, flag: true))
        // Görünür admin etiketleri yalnız geliştirici kimliğinde; yayında admin modu açıkken de gizli.
        XCTAssertTrue(AdminModeRules.showsBadges(flavor: .development, adminOn: true))
        XCTAssertFalse(AdminModeRules.showsBadges(flavor: .release, adminOn: true))
        XCTAssertFalse(AdminModeRules.showsBadges(flavor: .development, adminOn: false))
        XCTAssertFalse(AdminModeRules.showsBadges(flavor: .testing, adminOn: true))
        XCTAssertFalse(AdminModeRules.autoStarts(flavor: .development, flag: true, setupComplete: true, translation: .off))
        XCTAssertFalse(AdminModeRules.autoStarts(flavor: .testing, flag: true, setupComplete: true, translation: .off))
        XCTAssertTrue(AdminModeRules.autoStarts(flavor: .release, flag: true, setupComplete: true, translation: .off))
        XCTAssertFalse(AdminModeRules.autoStarts(flavor: .release, flag: true, setupComplete: false, translation: .off))
        XCTAssertFalse(AdminModeRules.autoStarts(flavor: .release, flag: true, setupComplete: true, translation: .on))
        XCTAssertTrue(AdminModeRules.shouldWakeTV(subtitlesOnTV: true, tvPaired: true, connectedDisplays: 0, translation: .on))
        // Dağıtılan deneme yapısı: admin kipi bayrakla da açılmaz.
        XCTAssertFalse(AdminModeRules.isOn(flavor: .release, flag: true, disabled: true))
        XCTAssertFalse(AdminModeRules.isOn(flavor: .development, flag: true, disabled: true))
        XCTAssertFalse(AdminModeRules.autoStarts(flavor: .release, flag: true, setupComplete: true, translation: .off, disabled: true))
        XCTAssertFalse(AdminModeRules.shouldWakeTV(subtitlesOnTV: true, tvPaired: true, connectedDisplays: 1, translation: .on))
        // TV bekleme süresinde bir kez bile bağlandıysa TV'de Nino öne getirilmez (kullanıcı HDMI'dan çıkmasın).
        XCTAssertFalse(AdminModeRules.shouldWakeTV(subtitlesOnTV: true, tvPaired: true, connectedDisplays: 0, translation: .on,
                                                   everConnected: true))
        // En fazla 10 dakikada bir.
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertFalse(AdminModeRules.shouldWakeTV(subtitlesOnTV: true, tvPaired: true, connectedDisplays: 0, translation: .on,
                                                   lastWake: now.addingTimeInterval(-599), now: now))
        XCTAssertTrue(AdminModeRules.shouldWakeTV(subtitlesOnTV: true, tvPaired: true, connectedDisplays: 0, translation: .on,
                                                  lastWake: now.addingTimeInterval(-600), now: now))
        XCTAssertGreaterThanOrEqual(AdminModeRules.tvWakeDelay, 60)
        XCTAssertTrue(StuckRecoveryRules.mayRelaunch(lastRelaunch: nil, now: 100))
        XCTAssertFalse(StuckRecoveryRules.mayRelaunch(lastRelaunch: 100, now: 600))
        XCTAssertTrue(StuckRecoveryRules.mayRelaunch(lastRelaunch: 100, now: 700))
    }

    // MARK: Yedek OCR ileti biçimi

    func testWireRequestRoundTripInPieces() throws {
        let image = Self.image(width: 7, height: 3)
        let req = try XCTUnwrap(OCRWire.Request(id: 42, image: image))
        let bytes = req.encoded()
        XCTAssertEqual(bytes.prefix(4), Data("NOQ1".utf8))
        XCTAssertEqual(bytes.count, 4 + 4 + 4 + 4 + 1 + 4 + 7 * 3 * 4)
        var d = OCRWire.Decoder()
        d.append(bytes.prefix(10))
        XCTAssertNil(try d.nextRequest())
        d.append(bytes.dropFirst(10))
        let back = try XCTUnwrap(try d.nextRequest())
        XCTAssertEqual(back, req)
        XCTAssertEqual(back.image()?.width, 7)
        XCTAssertNil(try d.nextRequest())
        XCTAssertEqual(d.pendingBytes, 0)
    }

    func testWireResponseRoundTripAndErrors() throws {
        let lines = [GameReading.Line("Hold ✕ — çok iyi", confidence: 0.75,
                                      box: GameReading.Box(left: 0.125, top: 0.5, right: 0.875, bottom: 0.625)),
                     GameReading.Line("no box", confidence: 1)]
        let resp = OCRWire.Response(id: 7, ok: true, lines: lines)
        var d = OCRWire.Decoder()
        let two = resp.encoded() + OCRWire.Response(id: 8, ok: false, lines: []).encoded()
        for b in two { d.append(Data([b])) }
        XCTAssertEqual(try d.nextResponse(), resp)
        XCTAssertEqual(try d.nextResponse(), OCRWire.Response(id: 8, ok: false, lines: []))
        var bad = OCRWire.Decoder()
        bad.append(Data("XXXX0000".utf8))
        XCTAssertThrowsError(try bad.nextResponse())
        var huge = OCRWire.Decoder()
        var h = Data("NOQ1".utf8)
        h.append(contentsOf: [1, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 1, 0xFF, 0xFF, 0xFF, 0x7F])
        huge.append(h)
        XCTAssertThrowsError(try huge.nextRequest())
    }

    func testHelperDropRules() {
        XCTAssertEqual(HelperOCRReader.DropRules.afterDrop(drops: 0).drops, 1)
        XCTAssertFalse(HelperOCRReader.DropRules.afterDrop(drops: 1).giveUp)
        XCTAssertTrue(HelperOCRReader.DropRules.afterDrop(drops: 2).giveUp)
    }

    func testHelperServerAnswersOverPipe() async throws {
        // Sunucunun döngüsü gerçek boru ile; Vision boş görüntüde satır bulmaz.
        let toServer = Pipe(), fromServer = Pipe()
        let thread = Thread { OCRHelperServer.serve(input: toServer.fileHandleForReading, output: fromServer.fileHandleForWriting) }
        thread.start()
        let req = try XCTUnwrap(OCRWire.Request(id: 5, image: Self.image(width: 64, height: 32)))
        try toServer.fileHandleForWriting.write(contentsOf: req.encoded())
        var d = OCRWire.Decoder()
        var response: OCRWire.Response?
        while response == nil {
            let chunk = fromServer.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            d.append(chunk)
            response = try d.nextResponse()
        }
        try toServer.fileHandleForWriting.close()
        XCTAssertEqual(response?.id, 5)
    }

    func testHelperReaderSkipsUntilWarmThenReads() async throws {
        let fake = FakeHelperProcess()
        let reader = HelperOCRReader(onGiveUp: {}, launch: { fake.channel() })
        let frame = GameReading.ImageFrame(Self.image(width: 40, height: 20))
        do {
            _ = try await reader.read(frame, area: .full, scale: 1)
            XCTFail("ısınmadan okumamalı")
        } catch let e as HelperOCRReader.HelperError {
            XCTAssertEqual(e, .notWarm)
        }
        for _ in 0..<100 where await !reader.warm { try await Task.sleep(for: .milliseconds(10)) }
        let warm = await reader.warm
        XCTAssertTrue(warm)
        let lines = try await reader.read(frame, area: .full, scale: 1)
        XCTAssertEqual(lines.map(\.text), ["ok"])
    }

    func testHelperReaderTimeoutCountsAsDrop() async throws {
        let fake = FakeHelperProcess()
        var limits = HelperOCRReader.Limits()
        limits.readSeconds = 0.05
        let reader = HelperOCRReader(limits: limits, onGiveUp: {}, launch: { fake.channel() })
        let frame = GameReading.ImageFrame(Self.image(width: 40, height: 20))
        await reader.warmUp(with: frame.cgImage)
        for _ in 0..<100 where await !reader.warm { try await Task.sleep(for: .milliseconds(10)) }
        fake.silent = true
        do {
            _ = try await reader.read(frame, area: .full, scale: 1)
            XCTFail("cevapsız okuma zaman aşımına düşmeli")
        } catch let e as HelperOCRReader.HelperError {
            XCTAssertEqual(e, .timedOut)
        }
        let drops = await reader.drops
        XCTAssertEqual(drops, 1)
        let given = await reader.gaveUp
        XCTAssertFalse(given)
    }

    // MARK: Yardımcılar

    static func image(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }
}

@MainActor
final class FakeAutoUpdater: AutoUpdater {
    var onEvent: ((AutoUpdaterEvent) -> Void)?
    var onInstall: (() -> Void)?
    private(set) var started = 0, checks = 0, windows = 0, installs = 0
    var ready = true
    func start() { started += 1 }
    func checkInBackground() { checks += 1 }
    func showUpdateWindow() { windows += 1 }
    func installReadyUpdate() -> Bool {
        guard ready else { return false }
        installs += 1
        onInstall?()
        return true
    }
}

/// Sahte yardımcı süreç: isteği çözer, "ok" satırıyla cevaplar (`silent` iken cevap vermez).
final class FakeHelperProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var _silent = false
    var silent: Bool {
        get { lock.withLock { _silent } }
        set { lock.withLock { _silent = newValue } }
    }

    func channel() -> HelperChannel {
        let box = ChannelBox()
        let ch = HelperChannel(send: { [weak self] data in
            guard let self else { return }
            box.decoder.append(data)
            while let req = try? box.decoder.nextRequest() {
                guard !self.silent else { continue }
                let resp = OCRWire.Response(id: req.id, ok: true, lines: [GameReading.Line("ok")])
                let ch = box.channel
                DispatchQueue.global().async { ch?.onData?(resp.encoded()) }
            }
        }, terminate: {})
        box.channel = ch
        return ch
    }

    private final class ChannelBox: @unchecked Sendable {
        weak var channel: HelperChannel?
        var decoder = OCRWire.Decoder()
    }
}
