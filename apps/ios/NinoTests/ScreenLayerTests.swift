// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import NinoCore
import UIKit
import XCTest
@testable import Nino

/// Ekran öğeleri uçtan uca, gerçek GTA 6 kareleriyle (Fixtures/gta6): kare → yazı tanıma (Vision) → okuma hattı →
/// ekran katmanı → TV mesajı (`screen` / `screen-clear`). Ağa çıkılmaz; PS5'e bağlanılmaz.
@MainActor
final class ScreenLayerTests: XCTestCase {
    private struct EchoProvider: TranslationProvider {
        let name = "deneme"
        func translate(_ text: String, from source: String, to target: String) async throws -> String { "TR: " + text }
    }

    /// Kareyi belli aralıkla tekrar tekrar veren kaynak (okuma hattı zamanla çalışır).
    private struct PacedFrames: FrameSource {
        let image: CGImage
        let count: Int
        let interval: Duration
        func frames() -> AsyncStream<Frame> {
            AsyncStream { c in
                let task = Task {
                    for i in 0..<count {
                        if Task.isCancelled { break }
                        c.yield(Frame(image: image, index: i, time: Double(i)))
                        try? await Task.sleep(for: interval)
                    }
                    c.finish()
                }
                c.onTermination = { _ in task.cancel() }
            }
        }
    }

    /// Alana göre satır veren okuyucu (satırlar kare oranında verilir, alan içine çevrilir).
    private struct AreaReader: GameReading.TextReader {
        let lines: @Sendable (GameReading.Box) -> [GameReading.Line]
        func read(_ frame: GameReading.Frame, area: GameReading.Box, scale: Double) async throws -> [GameReading.Line] {
            lines(area).filter { l in l.box.map { area.contains(x: $0.midX, y: ($0.top + $0.bottom) / 2) } ?? false }
                .map { l in GameReading.Line(l.text, confidence: 0.95, box: l.box?.local(in: area)) }
        }
    }

    nonisolated private static func box(_ l: Double, _ t: Double, _ r: Double, _ b: Double) -> GameReading.Box {
        GameReading.Box(left: l, top: t, right: r, bottom: b)
    }

    /// gta6-harita-buckme.jpg karesindeki yazılar ve yerleri (1920 × 1080 üzerinden ölçüldü).
    nonisolated private static let mapLines = AreaReader { _ in [
        GameReading.Line("DEPOSIT CASH INTO BUCKME", box: box(0.577, 0.407, 0.742, 0.440)),
        GameReading.Line("Use the index or BuckMe to find", box: box(0.569, 0.461, 0.773, 0.489)),
        GameReading.Line("nearby ATMs", box: box(0.569, 0.498, 0.650, 0.524)),
        GameReading.Line("Make a cash deposit into your BuckMe", box: box(0.548, 0.541, 0.791, 0.567)),
        GameReading.Line("checking account at an ATM.", box: box(0.548, 0.576, 0.732, 0.602)),
        GameReading.Line("RECENTER", box: box(0.907, 0.756, 0.959, 0.779)),
        GameReading.Line("2D VIEW", box: box(0.918, 0.805, 0.959, 0.827)),
        GameReading.Line("ADD MARKER", box: box(0.893, 0.853, 0.959, 0.875)),
        GameReading.Line("SET DESTINATION", box: box(0.871, 0.901, 0.959, 0.923)),
    ] }

    private final class Messages: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [NinoEvent] = []
        func add(_ e: NinoEvent) { lock.withLock { items.append(e) } }
        var all: [NinoEvent] { lock.withLock { items } }
        var screens: [ScreenPayload] { all.compactMap { if case let .screen(p) = $0 { p } else { nil } } }
        var clears: Int { all.filter { if case .screenClear = $0 { true } else { false } }.count }
    }

    private func fixture(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(Bundle(for: ScreenLayerTests.self).url(forResource: name, withExtension: "jpg"))
        return try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
    }

    private func model(lastGamePoolFirst: Bool = false) -> AppModel {
        let suite = "nino-screen-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(lastGamePoolFirst, forKey: Keys.lastGamePoolFirst)
        let folders = AppFolders(support: FileManager.default.temporaryDirectory, logs: FileManager.default.temporaryDirectory)
        let model = AppModel(store: MemoryStore(), defaults: defaults, folders: folders, ephemeral: true)
        model.providerOverride = [EchoProvider()]
        // Türkçe havuz öncelikli dil (telefon oyunu hep açık başlar); kararın oyuna bağlı yolu için başka dil.
        model.settings.targetLanguage = "nl"
        model.settings.translateCorners = true
        return model
    }

    private func wait(_ seconds: Double, until done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, !done() { try await Task.sleep(for: .milliseconds(100)) }
    }

    /// Aynı harita karesi, yazı tanıma yerine karenin üzerindeki yazılar (kare oranında kutularıyla) verilerek: oyun
    /// bilinmiyor ve son oyun GTA 6 değil → telefon oyunu kapalı başlar. Köşe turunun menü
    /// araması harita tuşlarını okuyunca oyun ekrandan GTA 6 tanınır, karar açılır ve harita kartı TV'ye gider.
    func testMapCardFromGTA6MapFrame() async throws {
        let messages = Messages()
        let model = model()
        model.screenSink = { messages.add($0) }
        let source = PacedFrames(image: try fixture("gta6-harita-buckme"), count: 600, interval: .milliseconds(50))
        let task = await model.start(with: source, textReader: Self.mapLines)
        let startedOn = await model.phoneGameActive()
        XCTAssertTrue(startedOn, "oyun bilinmezken telefon ve harita okuması açık (NinoCore kuralı)")

        try await wait(25) { messages.screens.contains { $0.items.contains { $0.card == true } } }
        let gameOn = await model.phoneGameActive()
        XCTAssertTrue(gameOn, "harita tuşlarından GTA 6 tanınmalı")
        XCTAssertTrue(model.defaults.bool(forKey: Keys.lastGamePoolFirst), "kesin tanınan oyun hatırlanır")
        let card = try XCTUnwrap(messages.screens.lazy.flatMap(\.items).first { $0.card == true }, "screen: \(messages.screens)")
        XCTAssertTrue(card.text.contains("TR:"), card.text)
        XCTAssertTrue(card.text.lowercased().contains("deposit") || card.text.lowercased().contains("atm"), card.text)
        XCTAssertEqual(messages.screens.first?.durationMs, ScreenChannel.durationMs)
        XCTAssertEqual(messages.screens.first?.overlay, true)

        // Durunca TV'deki öğeler kalkar.
        task?.cancel()
        model.stop()
        try await wait(3) { messages.clears > 0 }
        XCTAssertGreaterThan(messages.clears, 0)
    }

    /// Harita ekranı: oyun bilinmezken telefon oyunu açık başlar. Köşe turunun menü
    /// araması harita tuşlarını okuyunca oyun ekrandan GTA 6 tanınır, karar açılır ve harita kartı TV'ye gider.
    func testMapCardFromGTA6MapFrameWithVision() async throws {
        // Vision tuş simgesini satırın sonunda okuyor ("RECENTER L3", "SET DESTINATION 8"); NinoCore d143e44'ten beri atılır.
        let messages = Messages()
        let model = model()
        model.screenSink = { messages.add($0) }
        let source = PacedFrames(image: try fixture("gta6-harita-buckme"), count: 600, interval: .milliseconds(50))
        let task = await model.start(with: source)
        let startedOn = await model.phoneGameActive()
        XCTAssertTrue(startedOn, "oyun bilinmezken telefon ve harita okuması açık (NinoCore kuralı)")

        try await wait(25) { messages.screens.contains { $0.items.contains { $0.card == true } } }
        let gameOn = await model.phoneGameActive()
        XCTAssertTrue(gameOn, "harita tuşlarından GTA 6 tanınmalı")
        XCTAssertTrue(model.defaults.bool(forKey: Keys.lastGamePoolFirst), "kesin tanınan oyun hatırlanır")
        let card = try XCTUnwrap(messages.screens.lazy.flatMap(\.items).first { $0.card == true }, "screen: \(messages.screens)")
        XCTAssertTrue(card.text.contains("TR:"), card.text)
        XCTAssertTrue(card.text.lowercased().contains("deposit") || card.text.lowercased().contains("atm"), card.text)
        XCTAssertEqual(messages.screens.first?.durationMs, ScreenChannel.durationMs)
        XCTAssertEqual(messages.screens.first?.overlay, true)

        // Durunca TV'deki öğeler kalkar.
        task?.cancel()
        model.stop()
        try await wait(3) { messages.clears > 0 }
        XCTAssertGreaterThan(messages.clears, 0)
    }

    /// Telefon (sohbet) karesi: son oyun GTA 6 olduğu için telefon oyunu açık başlar, telefon paneli TV'ye gider.
    func testPhonePanelFromGTA6PhoneFrame() async throws {
        let messages = Messages()
        let model = model(lastGamePoolFirst: true)
        model.screenSink = { messages.add($0) }
        let source = PacedFrames(image: try fixture("gta6-telefon-shirley"), count: 600, interval: .milliseconds(50))
        let task = await model.start(with: source)
        let on = await model.phoneGameActive()
        XCTAssertTrue(on)
        try await wait(25) { messages.screens.contains { $0.items.contains { $0.text.contains("TR:") } } }
        let items = messages.screens.flatMap(\.items)
        XCTAssertTrue(items.contains { $0.text.contains("TR:") && $0.side == true }, "screen: \(messages.screens)")
        task?.cancel()
        model.stop()
    }

    // MARK: TV kapısı

    /// TV kapısı (NinoCore `ScreenItemSender`): harita kartı tek kaçırmada kalkmaz; 60 sn yenileme; boşalınca clear.
    func testSenderHoldsMapCardAndRefreshes() {
        var sender = GameReading.ScreenItemSender()
        let card = GameReading.ScreenElement(kind: .map, id: "kart", box: GameReading.Box(left: 0.5, top: 0.4, right: 0.8, bottom: 0.6),
                                             text: "TR: kart", style: GameReading.ScreenElement.Style(lineHeight: 0.03))
        XCTAssertNil(sender.update([], nowMs: 0), "boş liste ilk kez gönderilmez")
        guard case let .screen(list)? = sender.update([card], nowMs: 1_000, observed: [.map]) else { return XCTFail("screen beklenir") }
        XCTAssertEqual(ScreenChannel.payload(list).items.map(\.text), ["TR: kart"])
        XCTAssertEqual(ScreenChannel.payload(list).durationMs, 120_000)
        XCTAssertNil(sender.update([], nowMs: 2_000, observed: [.map]), "tek kaçırma kartı kaldırmaz")
        XCTAssertNil(sender.update([], nowMs: 3_000, observed: [.map]))
        guard case .screen? = sender.refresh(nowMs: 61_000) else { return XCTFail("60 sn'de yenilenir") }
        XCTAssertEqual(sender.update([], nowMs: 62_000, observed: [.map]), .clear, "3 kaçırma ve 4 sn sonra kalkar")
        XCTAssertNil(sender.refresh(nowMs: 500_000), "boşken yenileme yok")
        XCTAssertNil(sender.reset())
    }

    func testPhoneGameDecisionSources() {
        let m = model()
        XCTAssertTrue(m.phoneDecision().on, "oyun bilinmezken açık (NinoCore kuralı)")
        m.defaults.set(true, forKey: Keys.lastGamePoolFirst)
        XCTAssertTrue(m.phoneDecision().on, "son oyun GTA 6")
        m.settings.translateCorners = false
        XCTAssertFalse(m.phoneDecision().on, "köşeler kapalıysa yok")
        m.settings.translateCorners = true
        m.defaults.set(false, forKey: Keys.lastGamePoolFirst)
        m.settings.targetLanguage = "tr"
        XCTAssertTrue(m.phoneDecision().on, "Türkçe havuz öncelikli dil")
    }
}
