// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import XCTest
@testable import NinoCore

/// Satır içindeki kumanda tuşu simgesi (oyun-okuma.md §4.4, protokol.md "Tuş simgeleri").
///
/// GTA 6, 23 Kasım 00:26 (deneme-4): görev şeridinde `Hold [D-pad sağ] to interact with your partner`. Vision simgeyi
/// hiç okumadı (`Hold to interact …`); çeviri `… için tuşu basılı tut` oldu, bindirme simgeyi örttü, kullanıcı hangi
/// tuşa basacağını anlamadı.
final class ButtonIconTests: XCTestCase {
    // MARK: Yer tutucu ve protokol

    func testPlaceholderIDs() {
        XCTAssertEqual(IconPlaceholders.ids(in: "a ⟦T1⟧ b ⟦T12⟧ ⟦Arabana⟧ ⟦3⟧"), ["T1", "T12"])
        XCTAssertTrue(LinkIcon.isValidID("T99"))
        XCTAssertFalse(LinkIcon.isValidID("T100"))
        XCTAssertFalse(LinkIcon.isValidID("t1"))
    }

    func testEnsureTurkishReplacesGenericButtonWord() {
        let out = IconPlaceholders.ensure("Ortağınla etkileşime geçmek için tuşu basılı tut", ids: ["T1"], language: "tr")
        XCTAssertEqual(out, "Ortağınla etkileşime geçmek için ⟦T1⟧ basılı tut")
    }

    func testEnsureTurkishBeforeFirstVerb() {
        XCTAssertEqual(IconPlaceholders.ensure("Ortağınla etkileşime geçmek için basılı tut", ids: ["T1"], language: "tr"),
                       "Ortağınla etkileşime geçmek için ⟦T1⟧ basılı tut")
        XCTAssertEqual(IconPlaceholders.ensure("Kapıyı açmak için bas.", ids: ["T1"], language: "tr"), "Kapıyı açmak için ⟦T1⟧ bas.")
        // Fiil yoksa satır sonuna (noktalamanın önüne).
        XCTAssertEqual(IconPlaceholders.ensure("Haritayı aç.", ids: ["T1"], language: "tr"), "Haritayı aç ⟦T1⟧.")
        // Yer tutucu korunduysa dokunulmaz.
        XCTAssertEqual(IconPlaceholders.ensure("⟦T1⟧ tuşunu basılı tut", ids: ["T1"], language: "tr"), "⟦T1⟧ tuşunu basılı tut")
    }

    func testEnsureOtherLanguages() {
        XCTAssertEqual(IconPlaceholders.ensure("Halte die Taste gedrückt", ids: ["T1"], language: "de"), "Halte die ⟦T1⟧ gedrückt")
        XCTAssertEqual(IconPlaceholders.ensure("Mantén para interactuar", ids: ["T1"], language: "es"), "⟦T1⟧ Mantén para interactuar")
    }

    func testReadableForOldDisplays() {
        let icons = [LinkIcon(id: "T1", name: "dpad-right"), LinkIcon(id: "T2", png: "AAAA")]
        XCTAssertEqual(IconPlaceholders.readable("Bas ⟦T1⟧ ya da ⟦T2⟧", icons: icons), "Bas [→] ya da [■]")
        // Simgesi olmayan yer tutucu atılır; vurgu işareti kalır.
        XCTAssertEqual(IconPlaceholders.readable("⟦Arabana⟧ git ⟦T3⟧", icons: icons), "⟦Arabana⟧ git")
    }

    func testShowJSONWithAndWithoutIcons() throws {
        // Simge yoksa JSON eskisiyle aynı.
        XCTAssertEqual(NinoMessage.show(ShowPayload(id: 1, text: "Selam", icons: [])).jsonString,
                       #"{"app":"nino","durationMs":0,"id":1,"position":"bottom","text":"Selam","type":"show"}"#)
        let p = ShowPayload(id: 2, text: "Ortağınla etkileşime geçmek için ⟦T1⟧ basılı tut",
                            icons: [LinkIcon(id: "T1", name: "dpad-right")])
        XCTAssertEqual(NinoMessage.show(p).jsonString,
                       #"{"app":"nino","durationMs":0,"icons":[{"id":"T1","name":"dpad-right"}],"id":2,"position":"bottom","text":"Ortağınla etkileşime geçmek için ⟦T1⟧ basılı tut","type":"show"}"#)
        guard case let .show(back) = try NinoMessage(string: NinoMessage.show(p).jsonString) else { return XCTFail() }
        XCTAssertEqual(back, p)
        // Eski 8787: okunur metin, simge alanı yok.
        var legacy = LegacyTranslator()
        let e = legacy.subtitle(p, now: Date(timeIntervalSince1970: 1_732_233_600))
        XCTAssertEqual(e.data, #"{"at":1732233600000,"duration":15000,"text":"Ortağınla etkileşime geçmek için [→] basılı tut"}"#)
    }

    func testScreenAndRegionIcons() throws {
        let item = ScreenItem(box: NinoBox(left: 0.3, top: 0.9, right: 0.7, bottom: 0.95), text: "⟦T1⟧ bas",
                              icons: [LinkIcon(id: "T1", png: "iVBORw0KGgo=")])
        let screen = NinoEvent.screen(ScreenPayload(items: [item], durationMs: 1000))
        XCTAssertTrue(screen.jsonString.contains(#""icons":[{"id":"T1","png":"iVBORw0KGgo="}]"#), screen.jsonString)
        XCTAssertEqual(try NinoEvent(string: screen.jsonString), screen)
        let region = NinoEvent.region(RegionPayload(id: "a", text: "⟦T1⟧ bas", icons: [LinkIcon(id: "T1", name: "cross")]))
        XCTAssertEqual(try NinoEvent(string: region.jsonString), region)
        // Eski 8787: okunur metin.
        var legacy = LegacyTranslator()
        XCTAssertTrue(legacy.event(screen).data.contains(#""text":"[■] bas""#), legacy.event(screen).data)
        XCTAssertFalse(legacy.event(screen).data.contains("icons"))
        XCTAssertTrue(legacy.event(region).data.contains(#""text":"[✕] bas""#))
        // Simgesiz öğe eskisi gibi.
        let plain = ScreenItem(box: NinoBox(left: 0, top: 0, right: 1, bottom: 1), text: "x")
        XCTAssertNil(plain.jsonObject["icons"])
    }

    func testInvalidIconsAreDropped() throws {
        let json = #"{"app":"nino","type":"show","id":1,"text":"x","icons":[{"id":"X1","name":"cross"},{"id":"T2"},{"id":"T3","name":"circle"}]}"#
        guard case let .show(p) = try NinoMessage(string: json) else { return XCTFail() }
        XCTAssertEqual(p.icons, [LinkIcon(id: "T3", name: "circle")])
        let many = (1...10).map { LinkIcon(id: "T\($0)", name: "cross") }
        XCTAssertEqual(LinkIcon.encode(many)?.count, LinkIcon.maxCount)
    }

    // MARK: Çeviri yer tutucuyu korur

    func testTranslatorKeepsPlaceholderAndTerms() async {
        let provider = FakeProvider("p", .transform { s in
            s.replacingOccurrences(of: "Hold", with: "Basılı tut").replacingOccurrences(of: "to interact with", with: "ile konuş")
        })
        let t = Translator(chain: ProviderChain(providers: [provider]), userTerms: [Term("Lucia")])
        let out = await t.translate("Hold ⟦T1⟧ to interact with Lucia")
        XCTAssertTrue(out.text.contains("⟦T1⟧"), out.text)
        XCTAssertTrue(out.text.contains("Lucia"), out.text)
        XCTAssertEqual(provider.calls.first, "Hold ⟦T1⟧ to interact with ⟦0⟧")
    }

    func testAccentMarkKeepsIconPlaceholder() {
        let out = GameReading.Accent.mark("⟦T1⟧ ile arabana bin", term: "arabana")
        XCTAssertEqual(out, "⟦T1⟧ ile ⟦arabana⟧ bin")
    }

    // MARK: Metindeki tuş adları

    func testTextButtonsBecomePlaceholders() {
        let p = GameReading.ButtonIcons.prepare([GameReading.Line("Hold L2 to interact with Moses")], image: nil)
        XCTAssertEqual(p.text, "Hold ⟦T1⟧ to interact with Moses")
        XCTAssertEqual(p.icons, [LinkIcon(id: "T1", name: "L2")])
        let two = GameReading.ButtonIcons.prepare([GameReading.Line("Press ✕ or (R1) to skip")], image: nil)
        XCTAssertEqual(two.text, "Press ⟦T1⟧ or ⟦T2⟧ to skip")
        XCTAssertEqual(two.icons.map(\.name), ["cross", "R1"])
        // Simgesiz satır olduğu gibi.
        let none = GameReading.ButtonIcons.prepare([GameReading.Line("Light the torch, kid.")], image: nil)
        XCTAssertEqual(none.text, "Light the torch, kid.")
        XCTAssertTrue(none.icons.isEmpty)
    }

    // MARK: Çizilmiş simge

    /// Koyu zeminde beyaz yazı ve arasında halkalı, renkli simge (görüntü tanınmazsa PNG gider).
    func drawn(iconColor: CGColor?) -> (CGImage, GameReading.Line) {
        let w = 1280, h = 720
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        // "Press" ve "to jump" yerine yazı yüksekliğinde dikdörtgen harfler (22 px), arada 30 px'lik halka.
        let base = 80.0
        var x = 500.0
        for word in [5, 2, 4] {
            for _ in 0..<word { ctx.fill(CGRect(x: x, y: base, width: 9, height: 16)); x += 12 }
            x += 10
            if word == 5 {
                ctx.setStrokeColor(iconColor ?? CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1))
                ctx.setLineWidth(3)
                ctx.strokeEllipse(in: CGRect(x: x, y: base - 6, width: 30, height: 30))
                if let iconColor {
                    ctx.setFillColor(iconColor)
                    ctx.fill(CGRect(x: x + 9, y: base + 3, width: 12, height: 12))
                    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                }
                x += 40
            }
        }
        let line = GameReading.Line("Press to jump", box: GameReading.Box(left: 495 / 1280.0, top: 1 - (base + 20) / 720.0,
                                                                               right: (x + 4) / 1280.0, bottom: 1 - (base - 2) / 720.0))
        return (ctx.makeImage()!, line)
    }

    func testDrawnColoredIconIsNamed() {
        let (img, line) = drawn(iconColor: CGColor(red: 0.1, green: 0.8, blue: 0.3, alpha: 1))
        let p = GameReading.ButtonIcons.prepare([line], image: img)
        XCTAssertEqual(p.text, "Press ⟦T1⟧ to jump")
        XCTAssertEqual(p.icons.first?.name, "triangle")
    }

    func testDrawnUnknownIconIsSentAsSmallPNG() throws {
        let (img, line) = drawn(iconColor: nil)
        let p = GameReading.ButtonIcons.prepare([line], image: img)
        XCTAssertEqual(p.text, "Press ⟦T1⟧ to jump")
        let png = try XCTUnwrap(p.icons.first?.png.flatMap { Data(base64Encoded: $0) })
        XCTAssertLessThanOrEqual(png.count, GameReading.ButtonIcons.maxPNGBytes)
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }
}

#if canImport(Vision)
import ImageIO

/// Gerçek kare: 23 Kasım 00:26:35, Mac'in ham karesi (1920 × 1080).
final class ButtonIconRealFrameTests: XCTestCase {
    static func frame(width: Int) throws -> CGImage {
        GameReadingMenuExitTests.scaled(try GameReadingMenuExitTests.image("hold-dpad-00-26-35", dir: "gta6-button-icon"), width: width)
    }

    /// Mac'teki yol: köşe turu görev şeridini okur → yer tutuculu metin → çeviri → ekran öğesi.
    func questStrip(width: Int) async throws -> [GameReading.Line] {
        let img = try Self.frame(width: width)
        let clock = GameReading.ManualClock(10_000)
        var cfg = GameReading.Reader.Configuration()
        GameReading.GTA6Rules.apply(true, packGame: "gta-6", to: &cfg)
        let reader = GameReading.Reader(textReader: GameReading.VisionTextReader(), clock: clock, configuration: cfg)
        let frame = GameReading.ImageFrame(img)
        _ = await reader.process(frame)
        for e in await reader.readCorners(frame) {
            if case let .corner(.questStrip, lines) = e, !lines.isEmpty { return lines }
        }
        throw XCTSkip("Vision bu ortamda görev şeridini okumadı")
    }

    func testDpadRightInQuestStrip() async throws {
        for width in [1920, 1280] {
            let lines = try await questStrip(width: width)
            let img = try Self.frame(width: width)
            let p = GameReading.ButtonIcons.prepare(lines, image: img)
            // Kaynak (önbellek/havuz anahtarı): simge yer tutucuyla, tuştan bağımsız.
            XCTAssertEqual(p.text, "Hold ⟦T1⟧ to interact with your partner", "genişlik \(width)")
            // Simge: D-pad, sağ ok yanık (TV temiz vektör çizer).
            XCTAssertEqual(p.icons, [LinkIcon(id: "T1", name: "dpad-right")], "genişlik \(width)")

            // Çevirmen yer tutucuyu korursa olduğu gibi; düşürürse (`tuşu`) yerine konur.
            for raw in ["Ortağınla etkileşime geçmek için ⟦T1⟧ basılı tut", "Ortağınla etkileşime geçmek için tuşu basılı tut"] {
                let text = IconPlaceholders.ensure(raw, ids: p.ids, language: "tr")
                XCTAssertEqual(text, "Ortağınla etkileşime geçmek için ⟦T1⟧ basılı tut")
            }
            let item = ScreenItem(box: NinoBox(left: 0.37, top: 0.94, right: 0.63, bottom: 0.98),
                                  text: "Ortağınla etkileşime geçmek için ⟦T1⟧ basılı tut", icons: p.icons)
            XCTAssertEqual(item.jsonObject["icons"] as? [[String: String]], [["id": "T1", "name": "dpad-right"]])
        }
    }

    /// Simge tanınmasa da yeri bulunur: kesilmiş küçük PNG (≤ 8 KB) gider.
    func testCroppedIconIsSmall() throws {
        let img = try Self.frame(width: 1920)
        let line = GameReading.Line("Hold to interact with your partner",
                                    box: GameReading.Box(left: 0.3744, top: 0.9448, right: 0.6243, bottom: 0.9754))
        let found = GameReading.ButtonIcons.find(in: img, line: line)
        XCTAssertEqual(found.count, 1)
        let f = try XCTUnwrap(found.first)
        XCTAssertEqual(f.wordIndex, 1)
        XCTAssertEqual(f.box.midX, 0.42, accuracy: 0.01)
        let png = try XCTUnwrap(GameReading.ButtonIcons.png(img, box: f.box))
        XCTAssertLessThanOrEqual(png.count, GameReading.ButtonIcons.maxPNGBytes)
    }

    /// Simgesiz altyazı satırlarında (gerçek GTA 6 kareleri) simge bulunmaz.
    func testNoIconsInDialogue() async throws {
        for name in ["exit-23-41-21-439", "exit-23-41-23-514", "exit-23-41-27-618"] {
            let img = try GameReadingMenuExitTests.image(name)
            let area = GameReading.Box(left: 0.05, top: 0.6, right: 0.95, bottom: 0.98)
            let lines = try await GameReading.VisionTextReader().read(GameReading.ImageFrame(img), area: area, scale: 1)
                .map { $0.mapped(into: area) }
            for l in lines where GameReading.Text.hasLowercase(l.text) {
                XCTAssertTrue(GameReading.ButtonIcons.prepare([l], image: img).icons.isEmpty, "\(name): \(l.text)")
            }
        }
    }
}
#endif
