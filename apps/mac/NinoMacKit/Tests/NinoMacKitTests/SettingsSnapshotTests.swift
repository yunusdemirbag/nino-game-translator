// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI
import XCTest
@testable import NinoMacKit

/// Ayarlar penceresinin kuralları, metinleri ve her bölümün ekran görüntüsü (`apps/mac/snapshots/settings-*.png`).
/// Ağa, kullanıcının verisine ve Anahtarlığa dokunmaz.
@MainActor
final class SettingsSnapshotTests: XCTestCase {
    override func setUp() async throws {
        NinoFonts.registerBundledFonts()
    }

    // MARK: Kurallar

    /// Ayarlar › Bağlantı: TV hazırken ve eski TV uygulaması kuruluyken "Yeni Sürümü Kur" kartı görünür.
    func testTVSectionWithLegacyApp() throws {
        let state = PreviewEngine.sampleState()
        _ = PreviewEngine(state: state)
        state.pairedTV = PairedTV(name: "Samsung Q60", host: "192.168.1.59", brand: .samsung, hasKey: true)
        state.connectedDisplays = 1
        state.setup.tvApp = .legacyApp(version: "4.0.3")
        XCTAssertTrue(state.tvReady)
        try render(VStack(alignment: .leading, spacing: 16) {
            ConnectionSettings(state: state, detailed: true)
            TVSettingsSection(state: state)
        }.padding(24), size: CGSize(width: 720, height: 760), scheme: .light, name: "settings-connection-tv-legacy")
    }

    /// Android TV'de Televizyon kartında "Görüntü gelmiyorsa: Katman kipi" anahtarı (gösterim modu).
    func testTVSectionAndroidOverlaySwitch() throws {
        let state = PreviewEngine.sampleState()
        _ = PreviewEngine(state: state)
        state.connectedDisplays = 1
        state.settings.style.displayMode = .overlay
        try render(TVSettingsSection(state: state).padding(24), size: CGSize(width: 720, height: 460),
                   scheme: .light, name: "settings-tv-overlay")
    }

    func testPasscodeRule() {
        XCTAssertEqual(SettingsRules.passcode(" 12 34 "), "1234")
        XCTAssertNil(SettingsRules.passcode("123"))
        XCTAssertNil(SettingsRules.passcode("12a4"))
        XCTAssertNil(SettingsRules.passcode("١٢٣٤"), "ASCII olmayan rakam kabul edilmez")
    }

    func testConsoleAndSourceRules() {
        var s = MacSettings()
        s = SettingsRules.choosing(console: .xbox, in: s)
        XCTAssertEqual(s.gameConsole, .xbox)
        XCTAssertEqual(s.videoSource, .window, "Xbox'a geçerken PS5 kaynağı pencere olur")
        s.videoSource = .card
        s.output = .computer
        let same = SettingsRules.choosing(console: .xbox, in: s)
        XCTAssertEqual(same, s, "Aynı konsol tekrar seçilince değişmez")
        s = SettingsRules.choosing(source: .ps5, in: s)
        XCTAssertEqual(s.output, .tv, "PS5'e dönülünce altyazı TV'ye")
    }

    func testEngineChoice() {
        var s = SettingsRules.choosing(engine: .gemini, in: MacSettings())
        XCTAssertTrue(s.onlineTranslation)
        XCTAssertEqual(SettingsRules.selectedEngine(s), .gemini)
        s = SettingsRules.choosing(engine: nil, in: s)
        XCTAssertFalse(s.onlineTranslation)
        XCTAssertEqual(s.onlineEngine, .gemini, "Son çevrimiçi motor hatırlanır")
        XCTAssertNil(SettingsRules.selectedEngine(s))
    }

    func testLocalServerKindAndGeminiReset() {
        XCTAssertEqual(SettingsRules.localServerKind("localhost:1234"), .lmStudio)
        XCTAssertEqual(SettingsRules.localServerKind("http://10.0.0.2:8080/v1"), .other)
        XCTAssertEqual(SettingsRules.localServerKind("ftp://x"), .ollama, "Geçersiz adres Ollama sayılır")
        // 2026-11-22 10:00 UTC = 02:00 PST → sıradaki gece yarısı 23 Kasım 08:00 UTC.
        let now = Date(timeIntervalSince1970: 1_795_341_600)
        let reset = SettingsRules.nextPacificMidnight(after: now)
        XCTAssertEqual(reset.timeIntervalSince1970, 1_795_420_800)
    }

    func testPreviewEngineSettingsActions() {
        let state = PreviewEngine.sampleState()
        let engine = PreviewEngine(state: state)
        state.savePS5Passcode("12a4")
        XCTAssertFalse(state.settingsStatus.passcodeSaved)
        state.savePS5Passcode("1234")
        XCTAssertTrue(state.settingsStatus.passcodeSaved)
        state.saveTranslationKey("abc", for: .gemini)
        XCTAssertTrue(state.settingsStatus.savedKeys.contains(.gemini))
        if case .works = state.settingsStatus.engineTests[.gemini] {} else { XCTFail("deneme sonucu yok") }
        state.removeTranslationKey(for: .gemini)
        XCTAssertNil(state.settingsStatus.engineTests[.gemini])
        state.resetFromTV()
        XCTAssertEqual(state.setupStep, .tv)
        XCTAssertNotNil(state.pairedConsole, "PS5 eşleşmesi kalır")
        state.resetEverything()
        XCTAssertEqual(state.setupStep, .welcome)
        XCTAssertNil(state.pairedConsole)
        _ = engine
    }

    // MARK: Metinler

    func testEverySettingsKeyHasTurkishAndEnglish() throws {
        let url = HomeSnapshotTests.snapshotFolder.deletingLastPathComponent()
            .appendingPathComponent("NinoMacKit/Sources/NinoMacKit/Resources/Settings.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let keys = try XCTUnwrap(json?["strings"] as? [String: Any]).keys
        XCTAssertGreaterThan(keys.count, 200)
        for key in keys {
            XCTAssertNotEqual(NinoL10n.string(key, table: "Settings", language: "tr"), key, key)
            XCTAssertNotEqual(NinoL10n.string(key, table: "Settings", language: "en"), key, key)
        }
        // Görünümlerin kurduğu anahtarlar da tabloda olmalı.
        var used = SettingsSection.allCases.map(\.titleKey)
        used += SettingsRules.suggestedLocalModels.map(\.detailKey)
        used += LanguageRows.gameLanguages.map { "settings.translation.lang.\($0)" }
        used += ["quest", "notification", "phone"].flatMap { ["settings.area.place.\($0)", "settings.area.default.\($0)"] }
        for key in used { XCTAssertTrue(keys.contains(key), key) }
        XCTAssertEqual(NinoL10n.string("settings.area.percent %lld", table: "Settings", language: "tr", arguments: [40]),
                       "%40")
    }

    func testEngineFailureTexts() {
        var settings = MacSettings()
        let tr = Locale(identifier: "tr")
        XCTAssertTrue(SettingsEngineText.failure(.badKey, engine: .openai, settings: settings, locale: tr)
            .hasPrefix("OpenAI"))
        settings.localAIBaseURL = "http://localhost:1234/v1"
        settings.localAIModel = "qwen3"
        let text = SettingsEngineText.failure(.localModelMissing, engine: .local, settings: settings, locale: tr)
        XCTAssertTrue(text.contains("LM Studio") && text.contains("qwen3"), text)
    }

    // MARK: Ekran görüntüleri

    private func sampleState() -> AppState {
        let state = PreviewEngine.sampleState()
        state.version = AppVersionInfo(short: "V4.1", full: "4.1.0")
        state.settingsStatus.networkAddress = "192.168.0.42"
        state.settingsStatus.installedLocalModels = ["translategemma:4b"]
        state.settingsStatus.ollama = .running
        return state
    }

    private func snap(_ name: String, section: SettingsSection?, height: CGFloat = SettingsView.size.height,
                      configure: (AppState, SettingsUIState) -> Void = { _, _ in }) throws {
        for scheme in [ColorScheme.light, .dark] {
            let state = sampleState()
            let engine = PreviewEngine(state: state)
            let ui = SettingsUIState(section: section)
            configure(state, ui)
            let size = CGSize(width: SettingsView.size.width, height: height)
            try render(SettingsView(state: state, ui: ui, size: size), size: size, scheme: scheme,
                       name: "settings-\(name)-\(scheme == .dark ? "dark" : "light")")
            _ = engine
        }
    }

    /// Arapça ve Tayca görüntüler (`apps/mac/snapshots/l10n-settings-*.png`): taşma/kesilme denetimi için.
    func testLocalizedSnapshots() throws {
        let sections: [(String, SettingsSection?)] = [("list", nil), ("translation", .translation), ("appearance", .appearance)]
        for language in ["ar", "th"] {
            for (name, section) in sections {
                let state = sampleState()
                state.settings.targetLanguage = language
                let engine = PreviewEngine(state: state)
                let ui = SettingsUIState(section: section)
                let size = CGSize(width: SettingsView.size.width, height: section == .translation ? 1000 : SettingsView.size.height)
                try render(SettingsView(state: state, ui: ui, size: size)
                               .environment(\.layoutDirection, NinoL10n.isRightToLeft(languageCode: language) ? .rightToLeft : .leftToRight),
                           size: size, scheme: .light, locale: language, name: "l10n-settings-\(name)-\(language)")
                _ = engine
            }
        }
    }

    func testListSnapshot() throws {
        try snap("list", section: nil)
    }

    /// Ayarlar › Nino Hakkında: Ayarlar'ın içinde bölüm ("‹ Ayarlar" + "Bitti"); uzun sayfa kesilmeden çizilir.
    func testAboutSectionSnapshot() throws {
        XCTAssertNil(SettingsSection.about.externalSheet)
        try snap("about", section: .about, height: 1260)
    }

    func testConnectionSnapshots() throws {
        try snap("connection", section: .connection)
        try snap("connection-card", section: .connection, height: 900) { state, _ in
            state.settings.videoSource = .card
            state.settings.output = .both
            state.setup.captureCard.status = .noCard
        }
        try snap("connection-xbox", section: .connection) { state, _ in
            state.settings = SettingsRules.choosing(console: .xbox, in: state.settings)
        }
    }

    func testPasscodeSnapshots() throws {
        try snap("passcode", section: .passcode)
        try snap("passcode-saved", section: .passcode) { state, _ in state.settingsStatus.passcodeSaved = true }
    }

    /// Altyazının görünüşü: üç seçenek (yazı boyu, arka plan, konuşanın adı). Otomatik boy açık ve kapalı;
    /// uzun dil (nl) ve sağdan sola (ar). Kapalıda arka plan yok (eski "Sinema" teması gibi) ve İngilizce
    /// satırın üstüne binmiyor: kaydırıcı 0'dan başlar.
    func testAppearanceSnapshots() throws {
        try snap("appearance", section: .appearance)
        let manual: (AppState, SettingsUIState) -> Void = { state, _ in
            state.settings.style.autoSize = false
            state.settings.style.fontSize = 58
            state.settings.style.placement = .below
            state.settings.style.background = 0
            state.settings.showSpeakerNames = false
        }
        try snap("appearance-manual", section: .appearance, configure: manual)
        for language in ["nl", "ar"] {
            for (suffix, configure) in [("auto", { (_: AppState, _: SettingsUIState) in }), ("manual", manual)] {
                let state = sampleState()
                state.settings.targetLanguage = language
                let ui = SettingsUIState(section: .appearance)
                configure(state, ui)
                let engine = PreviewEngine(state: state)
                let size = SettingsView.size
                try render(SettingsView(state: state, ui: ui, size: size)
                               .environment(\.layoutDirection, NinoL10n.isRightToLeft(languageCode: language) ? .rightToLeft : .leftToRight),
                           size: size, scheme: .light, locale: language, name: "settings-appearance-\(suffix)-\(language)")
                _ = engine
            }
        }
    }

    /// Çeviri: kütüphane kartı + dil + API akordiyonu. Anahtarsız, bir satır açık, Gemini kullanılırken,
    /// yerel model ve DeepL açık; uzun dil (nl) ve sağdan sola (ar) arayüz.
    func testTranslationSnapshots() throws {
        try snap("translation-nokey", section: .translation, height: 1000)
        try snap("translation-open", section: .translation, height: 1100) { state, ui in
            state.settingsStatus.gamePacks = [GamePackInfo(id: "gta6", name: "GTA 6", lines: 40_000),
                                              GamePackInfo(id: "rdr2", name: "Red Dead Redemption 2", lines: 61_203)]
            state.game = RecognizedGame(id: "gta6", name: "GTA 6", poolFirst: true, evidence: .console)
            ui.openProvider = .gemini
        }
        try snap("translation", section: .translation, height: 1100) { state, ui in
            state.settings = SettingsRules.choosing(engine: .gemini, in: state.settings)
            state.settingsStatus.savedKeys = [.gemini, .deepl]
            state.settingsStatus.engineTests[.gemini] = .works(sample: "BATMAN: Ben Batman'im.")
            ui.openProvider = .gemini
        }
        try snap("translation-local", section: .translation, height: 1500) { state, ui in
            state.settings = SettingsRules.choosing(engine: .local, in: state.settings)
            state.settingsStatus.localDownload = LocalModelDownload(model: "translategemma:12b", progress: 0.42)
            state.settingsStatus.engineTests[.local] = .failed(.localUnreachable)
            ui.openProvider = .local
            ui.localAdvancedExpanded = true
        }
        try snap("translation-deepl", section: .translation, height: 1100) { state, ui in
            state.settingsStatus.savedKeys = [.deepl]
            state.settingsStatus.deepLUsage = .used(characters: 12_480, limit: 500_000)
            ui.openProvider = .deepl
        }
        for language in ["nl", "ar"] {
            let state = sampleState()
            state.settings.targetLanguage = language
            state.settingsStatus.savedKeys = [.claude]
            state.game = RecognizedGame(id: "gta6", name: "GTA 6", poolFirst: true, evidence: .console)
            let engine = PreviewEngine(state: state)
            let ui = SettingsUIState(section: .translation)
            ui.openProvider = .claude
            let size = CGSize(width: SettingsView.size.width, height: 1100)
            try render(SettingsView(state: state, ui: ui, size: size)
                           .environment(\.layoutDirection, NinoL10n.isRightToLeft(languageCode: language) ? .rightToLeft : .leftToRight),
                       size: size, scheme: .light, locale: language, name: "settings-translation-\(language)")
            _ = engine
        }
    }

    /// Akordiyon: aynı anda bir satır açık; durum noktası kullanılıyor / kayıtlı / yok / kapalı.
    func testProviderRowStatus() {
        let state = sampleState()
        let ui = SettingsUIState(section: .translation)
        state.settings = SettingsRules.choosing(engine: .gemini, in: state.settings)
        state.settingsStatus.savedKeys = [.gemini, .deepl]
        func status(_ e: MacSettings.OnlineEngine) -> ProviderRow.Status { ProviderRow(state: state, ui: ui, engine: e).status }
        XCTAssertEqual(status(.gemini), .inUse)
        XCTAssertEqual(status(.deepl), .saved)
        XCTAssertEqual(status(.openai), .none)
        XCTAssertEqual(status(.local), .off)
        XCTAssertEqual(ProviderCard.providers.count, 5)
    }

    func testOtherSectionSnapshots() throws {
        try snap("obs", section: .obs) { state, _ in state.streamWindowOpen = true }
        try snap("updates", section: .updates) { state, _ in state.update = .available(version: "4.2.0") }
        try snap("updates-latest", section: .updates) { state, _ in state.update = .upToDate }
        try snap("reset", section: .reset)
        try snap("interface", section: .interface)
        try snap("language", section: .language) { state, _ in state.settings.targetLanguage = "ar" }
        try snap("packs", section: .packs) { state, _ in
            state.settingsStatus.gamePacks = [GamePackInfo(id: "rdr2", name: "Red Dead Redemption 2", lines: 61_203),
                                              GamePackInfo(id: "gow", name: "God of War Ragnarök", lines: 18_450)]
        }
        try snap("area", section: .area, height: 1100) { state, _ in
            state.settings.areaPreset = .custom
            state.settings.extraAreas = [ExtraArea(name: "Görev", region: ExtraArea.questPreset)]
        }
    }

    // MARK: Yardımcı

    func render<V: View>(_ view: V, size: CGSize, scheme: ColorScheme, locale: String = "tr", name: String) throws {
        let content = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: locale))
            .environment(\.ninoStaticRendering, true)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(size)
        let image: NSImage = try XCTUnwrap(renderer.nsImage, "\(name) çizilemedi")
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let folder = HomeSnapshotTests.snapshotFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent(name + ".png"))
    }
}
