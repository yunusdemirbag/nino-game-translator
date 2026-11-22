// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import NinoCore
import XCTest
@testable import NinoMacKit

final class MacSettingsTests: XCTestCase {
    /// Gerçek bir kullanıcı kaydının biçimi (22 Kasım 2026), kaldırılmış dublaj alanı dahil.
    let realBlob = #"""
    {"showSpeakerNames":true,"frameSource":"ps5","overlayClickThrough":false,"areaPreset":"custom","onlineTranslation":false,"extraAreas":[],"gamePacks":true,"targetLanguage":"tr","videoSource":"ps5","remotePlayApp":"automatic","dubbing":{"cast":{"narrator":"male_1","partner":"male_2","assignments":{}},"output":"tv","enabled":false},"gameConsole":"ps5","openAIModel":"gpt-6-luna","output":"tv","onlineEngine":"local","homeStyle":"livingRoom","translateCorners":true,"sharePool":true,"appearance":"system","sourceLanguage":"en","geminiModel":"gemini-3.5-flash-lite","xboxAudioOnDevice":true,"fastSubtitleDetection":false,"localAIBaseURL":"http://localhost:11434/v1","claudeModel":"claude-haiku-5-5","region":{"left":0.06581337376644739,"bottom":1,"top":0.5667859100877193,"right":0.9815866570723684},"style":{"stackPrevious":true,"placement":"cover","fontSize":30,"theme":"classic","textColor":"white","background":100,"backgroundShape":"fit","displayMode":"inApp","bold":false,"font":"condensed","autoSize":true,"bottomPercent":7},"localAIModel":"hf.co/mradermacher/MiLMMT-46-4B-v1.0-GGUF:Q4_K_M","askGame":true}
    """#

    func testRealBlobReads() throws {
        var s = try XCTUnwrap(MacSettings.decode(Data(realBlob.utf8)))
        s.normalize()
        XCTAssertEqual(s.style.fontSize, 30)
        XCTAssertEqual(s.onlineEngine, .local)
        XCTAssertFalse(s.onlineTranslation)
        XCTAssertEqual(s.areaPreset, .custom)
        XCTAssertEqual(s.region.top, 0.5667859100877193, accuracy: 1e-12)
        XCTAssertEqual(s.region.bottom, 1)
        XCTAssertEqual(s.localAIModel, "hf.co/mradermacher/MiLMMT-46-4B-v1.0-GGUF:Q4_K_M")
        XCTAssertTrue(s.autoReport, "yoksa varsayılan açık")
        XCTAssertTrue(s.style.watermark)
        XCTAssertNotNil(s.unknownFields["dubbing"])
    }

    func testEveryStoredKeySurvivesRoundTrip() throws {
        let original = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(realBlob.utf8)) as? [String: Any])
        let s = try XCTUnwrap(MacSettings.decode(Data(realBlob.utf8)))
        let written = try XCTUnwrap(try JSONSerialization.jsonObject(with: s.encoded()) as? [String: Any])
        for key in original.keys { XCTAssertNotNil(written[key], "\(key) kayboldu") }
        let style = try XCTUnwrap(written["style"] as? [String: Any])
        for key in (original["style"] as! [String: Any]).keys { XCTAssertNotNil(style[key], "style.\(key) kayboldu") }
        XCTAssertEqual(MacSettings.decode(s.encoded()), s)
        XCTAssertEqual(style["fontSize"] as? Int, 30)
    }

    func testBadValueOnlyResetsThatField() throws {
        let blob = #"{"output":"hologram","appearance":"dark","style":{"theme":"neon","fontSize":58}}"#
        let s = try XCTUnwrap(MacSettings.decode(Data(blob.utf8)))
        XCTAssertEqual(s.output, .tv)
        XCTAssertEqual(s.appearance, .dark)
        XCTAssertEqual(s.style.theme, .classic)
        XCTAssertEqual(s.style.fontSize, 58)
    }

    func testCorrections() throws {
        let blob = #"{"output":"both","onlineEngine":"free","localAIModel":"qwen2.5:7b","geminiModel":"gone","style":{"placement":"cover","background":20},"region":{"top":0.62,"bottom":0.97,"left":0.14,"right":0.86},"extraAreas":[{},{},{},{"name":"x"}]}"#
        var s = try XCTUnwrap(MacSettings.decode(Data(blob.utf8)))
        XCTAssertTrue(s.normalize())
        XCTAssertEqual(s.output, .tv)
        XCTAssertEqual(s.onlineEngine, .deepl)
        XCTAssertEqual(s.localAIModel, "translategemma:4b")
        XCTAssertEqual(s.geminiModel, "gemini-3.5-flash-lite")
        XCTAssertEqual(s.style.background, 100)
        XCTAssertEqual(s.extraAreas.count, 3)
        XCTAssertEqual(s.areaPreset, .bottom)
        XCTAssertFalse(s.normalize(), "ikinci kez değişiklik olmaz")
    }

    func testFreshUsesSystemLanguage() {
        XCTAssertEqual(MacSettings.fresh(preferredLanguages: ["ar-SA"]).targetLanguage, "ar")
        XCTAssertEqual(MacSettings.fresh(preferredLanguages: ["fil-PH"]).targetLanguage, "tl")
        XCTAssertEqual(MacSettings.fresh(preferredLanguages: ["de-DE"]).targetLanguage, "tr")
    }

    func testStoreWritesBackCorrections() throws {
        let suite = "nino.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"output":"both"}"#.utf8), forKey: DefaultsKey.settings)
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.load().output, .tv)
        let stored = try XCTUnwrap(defaults.data(forKey: DefaultsKey.settings))
        XCTAssertEqual(MacSettings.decode(stored)?.output, .tv)
    }

    /// Görünüş sadeleşti: yazı tipi, kalınlık, renk, tema, zemin şekli ve Nino işareti kayıttan okunmaz
    /// (TV'ye hep varsayılan gider) ama kayıtta olduğu gibi kalır. Yerleşim, alt boşluk, gösterim modu ve
    /// önceki satırın kalması arayüzden kalktı; kayıtlı değerleri TV'ye gitmeyi sürdürür.
    func testRetiredLookIsIgnoredButKeptFunctionalStylePreserved() throws {
        let blob = #"{"style":{"font":"rounded","bold":true,"textColor":"yellow","theme":"cinema","backgroundShape":"band","watermark":false,"placement":"fixed","bottomPercent":30,"displayMode":"overlay","stackPrevious":false,"background":40,"fontSize":58,"autoSize":false}}"#
        let s = try XCTUnwrap(MacSettings.decode(Data(blob.utf8)))
        let defaults = SubtitleStyle()
        XCTAssertEqual(s.style.font, defaults.font)
        XCTAssertEqual(s.style.bold, defaults.bold)
        XCTAssertEqual(s.style.textColor, defaults.textColor)
        XCTAssertEqual(s.style.theme, defaults.theme)
        XCTAssertEqual(s.style.backgroundShape, defaults.backgroundShape)
        XCTAssertEqual(s.style.watermark, defaults.watermark)
        let tv = NinoStyle(s.style)
        XCTAssertEqual(tv.font, "condensed")
        XCTAssertEqual(tv.bold, false)
        XCTAssertEqual(tv.textColor, "white")
        XCTAssertEqual(tv.theme, "classic")
        XCTAssertEqual(tv.backgroundShape, "fit")
        XCTAssertEqual(tv.watermark, true)
        XCTAssertEqual(tv.placement, "fixed")
        XCTAssertEqual(tv.bottomPercent, 30)
        XCTAssertEqual(tv.displayMode, "overlay")
        XCTAssertEqual(tv.stackPrevious, false)
        XCTAssertEqual(tv.background, 40)
        XCTAssertEqual(tv.fontSize, 58)
        XCTAssertEqual(tv.autoSize, false)

        let written = try XCTUnwrap(try JSONSerialization.jsonObject(with: s.encoded()) as? [String: Any])
        let style = try XCTUnwrap(written["style"] as? [String: Any])
        XCTAssertEqual(style["font"] as? String, "rounded")
        XCTAssertEqual(style["bold"] as? Bool, true)
        XCTAssertEqual(style["textColor"] as? String, "yellow")
        XCTAssertEqual(style["theme"] as? String, "cinema")
        XCTAssertEqual(style["backgroundShape"] as? String, "band")
        XCTAssertEqual(style["watermark"] as? Bool, false)
        XCTAssertEqual(style["placement"] as? String, "fixed")
    }

    func testThemeSetsColorWeightBackground() {
        var style = SubtitleStyle()
        style.fontSize = 72
        style.apply(theme: .cinema)
        XCTAssertEqual(style.textColor, .yellow)
        XCTAssertTrue(style.bold)
        XCTAssertEqual(style.background, 0)
        XCTAssertEqual(style.fontSize, 72)
    }
}
