// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import NinoCore
import SwiftUI
import XCTest
@testable import NinoMacKit

/// Ana ekranda Enter ile fiş; yazı boyunun TV'ye hemen gitmesi (ayarlar.md §6.3).
@MainActor
final class EnterKeyAndStyleTests: XCTestCase {
    // MARK: Enter

    private func readyHome() -> (AppState, PreviewEngine, HomeUIState) {
        var settings = MacSettings()
        settings.videoSource = .window
        settings.gameConsole = .ps5
        let state = AppState(settings: settings)
        state.setupStep = .done
        let engine = PreviewEngine(state: state)
        return (state, engine, HomeUIState(skipIntro: true))
    }

    func testReturnKeyPlugsAndUnplugs() {
        let (state, engine, ui) = readyHome()
        XCTAssertTrue(state.canStart)
        XCTAssertTrue(ui.handleReturnKey(state))
        XCTAssertEqual(state.translation, .on)
        XCTAssertTrue(ui.handleReturnKey(state))
        XCTAssertEqual(state.translation, .off)
        XCTAssertEqual(engine.calls.filter { $0 == "start" || $0 == "stop" }, ["start", "stop"])
    }

    func testReturnKeyIgnoredWhileSheetOpenOrInSetup() {
        let (state, engine, ui) = readyHome()
        state.open(.settings)
        XCTAssertFalse(ui.handleReturnKey(state))
        state.activeSheet = nil
        state.setupStep = .console
        XCTAssertFalse(ui.handleReturnKey(state))
        XCTAssertFalse(engine.calls.contains("start"))
        XCTAssertEqual(state.translation, .off)
    }

    func testReturnKeyFilter() {
        // Return dışı tuş, değiştiricili Enter, basılı tutma ve pencere yokken işlenmez.
        XCTAssertFalse(ReturnKeyShortcut.shouldHandle(keyCode: 49, modifiers: [], isRepeat: false, window: nil, eventWindow: nil))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled],
                              backing: .buffered, defer: true)
        XCTAssertFalse(ReturnKeyShortcut.shouldHandle(keyCode: 36, modifiers: [.command], isRepeat: false,
                                                      window: window, eventWindow: window))
        XCTAssertFalse(ReturnKeyShortcut.shouldHandle(keyCode: 36, modifiers: [], isRepeat: true,
                                                      window: window, eventWindow: window))
        XCTAssertFalse(ReturnKeyShortcut.shouldHandle(keyCode: 36, modifiers: [], isRepeat: false,
                                                      window: nil, eventWindow: window))
        XCTAssertEqual(ReturnKeyShortcut.returnKeyCodes, [36, 76])
    }

    /// Görüntü: fiş balonu tek kısa satır (Enter yazısı yok), ok prizi gösterir, hiçbir görselin üstüne binmez;
    /// takılı ve çıkık, dar (en küçük pencere) ve geniş pencere, uzun dil (nl), Xbox sahnesi.
    func testPlugHintSnapshots() throws {
        NinoFonts.registerBundledFonts()
        let renderer = HomeSnapshotTests()
        let sizes = [("narrow", CGSize(width: NinoSize.windowWidth, height: NinoSize.windowHeight)),
                     ("wide", CGSize(width: NinoSize.windowMaxWidth, height: 860))]
        var cases: [(String, MacSettings.GameConsole, Bool, String, CGSize)] = []
        for (sizeName, size) in sizes {
            for language in ["tr", "nl"] {
                for on in [true, false] { cases.append((language, .ps5, on, sizeName, size)) }
            }
        }
        cases.append(("tr", .xbox, false, "narrow", sizes[0].1))
        for (language, console, on, sizeName, size) in cases {
            let state = PreviewEngine.sampleState()
            state.settings.homeStyle = .livingRoom
            state.settings.targetLanguage = language
            state.settings.gameConsole = console
            if on {
                state.translation = .on
                state.source = .ps5(.streaming)
                state.connectedDisplays = 1
            }
            let ui = HomeUIState(skipIntro: true)
            try renderer.render(MainWindowView(state: state, ui: ui), size: size, scheme: .dark, locale: language,
                                name: "home-plug-hint-\(language)-\(console.rawValue)-\(on ? "on" : "off")-\(sizeName)")
        }
    }

    // MARK: Yazı boyu → TV

    actor FakeOutput: DisplayOutput {
        private(set) var styles: [NinoStyle] = []
        func show(_ payload: ShowPayload) async throws {}
        func clear(id: Int?) async throws {}
        func send(_ event: NinoEvent) async throws {
            if case let .style(s) = event { styles.append(s) }
        }
    }

    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ s: String) { lock.withLock { items.append(s) } }
        var all: [String] { lock.withLock { items } }
    }

    private func makeEngine(_ state: AppState) throws -> (LiveEngine, () -> Void) {
        let suite = "nino-style-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nino-style-\(UUID().uuidString)")
        let env = LiveEngineEnvironment(
            identity: AppIdentity(flavor: .testing, defaultsDomain: suite, keychainService: "test", folderName: "test"),
            folder: DataFolder(support: root, logs: root), settingsStore: SettingsStore(defaults: defaults), vault: MemoryVault(),
            ports: .ephemeral, appVersion: "4.1.0", poolBaseURL: nil, packsBaseURL: nil, poolTransport: nil,
            providerTransport: URLSession.shared, deviceProvider: { nil }, textReader: SessionOverlaysTests.FailingReader(fail: false),
            clock: GameReading.SystemClock(), checksTranslatorReadiness: false)
        let engine = LiveEngine(state: state, environment: env)
        return (engine, {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        })
    }

    /// Çeviri kapalıyken (deneme altyazısı TV'deyken) kaydırıcı: yeni boy hem hub çıkışına (47800 yolları) hem
    /// gerçek 8787 eski SSE istemcisine `fontSize`/`autoSize` ile hemen gider; deneme altyazısı da görünümü yollar.
    func testFontSizeChangeReachesHubAndLegacyClientImmediately() async throws {
        let state = AppState()
        let (engine, cleanup) = try makeEngine(state)
        defer { cleanup() }
        let links = engine.links
        await links.startServers()
        let fake = FakeOutput()
        await links.hub.add(fake, key: "fake")
        let port = try XCTUnwrap(links.legacyPort)
        let lines = Lines()
        let session = URLSession(configuration: .ephemeral)
        let reader = Task {
            guard let (bytes, _) = try? await session.bytes(from: URL(string: "http://127.0.0.1:\(port)/events?model=LG&app=4.0.3")!)
            else { return }
            for try await line in bytes.lines { lines.add(line) }
        }
        defer {
            reader.cancel()
            session.invalidateAndCancel()
        }
        // 47800 gelen yol: web TV gibi WebSocket ile bağlanan istemci (hello → welcome, ping'e pong).
        let wsLines = Lines()
        let ingressPort = try XCTUnwrap(links.ingressPort)
        let ws = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(ingressPort)/nino/ws")!)
        ws.maximumMessageSize = NinoLink.maxMessageBytes
        ws.resume()
        let wsReader = Task {
            var welcomed = false
            while !Task.isCancelled {
                guard case let .string(text)? = try? await ws.receive() else { return }
                if !welcomed {
                    welcomed = true
                    try? await ws.send(.string(#"{"app":"nino","type":"welcome","version":1,"name":"Deneme TV"}"#))
                    continue
                }
                if case let .ping(t)? = try? NinoMessage(string: text) {
                    try? await ws.send(.string(NinoMessage.pong(t: t).jsonString))
                    continue
                }
                wsLines.add(text)
            }
        }
        defer {
            wsReader.cancel()
            ws.cancel(with: .normalClosure, reason: nil)
        }
        for _ in 0..<150 where links.connectedCount < 2 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(links.connectedCount, 2, "eski SSE (8787) ve gelen WebSocket (47800) istemcileri bağlandı")
        XCTAssertEqual(state.translation, .off)

        state.settings.style.autoSize = true
        state.settings.style.fontSize = 70
        await engine.styleSent()
        var got = await fake.styles
        XCTAssertEqual(got.last?.fontSize, 70)
        XCTAssertEqual(got.last?.autoSize, true)

        state.settings.style.autoSize = false
        state.settings.style.fontSize = 30
        await engine.styleSent()
        got = await fake.styles
        XCTAssertEqual(got.last?.fontSize, 30)
        XCTAssertEqual(got.last?.autoSize, false)

        // Kaydırıcı sürüklenmeye başlayınca deneme altyazısı: görünüm de o anki değerle yeniden gider.
        state.settings.style.fontSize = 62
        engine.sendTestSubtitle()
        await engine.styleSent()
        got = await fake.styles
        XCTAssertEqual(got.last?.fontSize, 62)

        func styleData() -> [String] { lines.all.filter { $0.hasPrefix("data:") && $0.contains("fontSize") } }
        for _ in 0..<150 where !(styleData().last?.contains("\"fontSize\":62") ?? false) {
            try await Task.sleep(for: .milliseconds(20))
        }
        let legacy = styleData()
        XCTAssertTrue(legacy.contains { $0.contains("\"fontSize\":70") && $0.contains("\"autoSize\":true") }, "\(legacy)")
        XCTAssertTrue(legacy.contains { $0.contains("\"fontSize\":30") && $0.contains("\"autoSize\":false") }, "\(legacy)")
        XCTAssertTrue(legacy.last?.contains("\"fontSize\":62") ?? false, "\(legacy)")

        func wsStyles() -> [String] { wsLines.all.filter { $0.contains("\"style\"") && $0.contains("fontSize") } }
        for _ in 0..<150 where !(wsStyles().last?.contains("\"fontSize\":62") ?? false) {
            try await Task.sleep(for: .milliseconds(20))
        }
        let ingress = wsStyles()
        XCTAssertTrue(ingress.contains { $0.contains("\"fontSize\":70") && $0.contains("\"autoSize\":true") }, "\(ingress)")
        XCTAssertTrue(ingress.contains { $0.contains("\"fontSize\":30") && $0.contains("\"autoSize\":false") }, "\(ingress)")
        XCTAssertTrue(ingress.last?.contains("\"fontSize\":62") ?? false, "\(ingress)")
        await links.stop()
    }

    /// Önizleme TV ile aynı kuralı izler: otomatik boyda ölçülen × fontSize/46 (0,5–2,5).
    func testPreviewAutoSizeUsesUserSizeAsMultiplier() {
        var style = SubtitleStyle()
        style.autoSize = true
        style.fontSize = 46
        let base = SettingsRules.previewFontSize(style, width: 1920)
        style.fontSize = 92
        XCTAssertEqual(SettingsRules.previewFontSize(style, width: 1920), base * 2, accuracy: 0.01)
        style.fontSize = 200
        XCTAssertEqual(SettingsRules.autoSizeScale(style.fontSize), 2.5)
        XCTAssertEqual(SettingsRules.autoSizeScale(10), 0.5)
        style.autoSize = false
        style.fontSize = 60
        XCTAssertEqual(SettingsRules.previewFontSize(style, width: 1920), 60 * 1.6, accuracy: 0.01)
    }
}
