// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import NinoCore
import XCTest
@testable import NinoMacKit

/// Satırdaki tuş simgesi TV'ye ayrı gider (protokol.md "Tuş simgeleri"): metinde `⟦T1⟧`, `icons` alanında simge.
final class ButtonIconShowTests: XCTestCase {
    /// Yer tutucuyu düşüren çevirmen (cihaz içi çeviri gibi): `tuşunu` der, yer tutucu yok.
    final class DroppingTranslator: SubtitleTranslating, @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        var sentences: [String] { lock.withLock { asked } }
        func translate(_ sentence: String) async -> SessionTranslation {
            lock.withLock { asked.append(sentence) }
            return SessionTranslation(text: "Sonra tuşunu kullanabilirsin, tamam mı?", origin: .engine)
        }
    }

    func testSubtitleWithButtonSendsIcon() async throws {
        let clock = GameReading.ManualClock()
        var cfg = GameReading.Reader.Configuration(gameKey: "test")
        cfg.region = GameReading.Region(preset: .fullFrame)
        cfg.plan = .always
        let line = GameReading.Line("You can use L2 later, okay?", confidence: 0.95,
                                    box: GameReading.Box(left: 0.3, top: 0.80, right: 0.7, bottom: 0.83))
        let reader = GameReading.Reader(textReader: SpeakerShowTests.FixedReader(lines: [line]), clock: clock, configuration: cfg)
        let out = SpeakerShowTests.Shows()
        let translator = DroppingTranslator()
        var shown: [LiveLine] = []
        let lock = NSLock()
        let session = SubtitleSession(reader: reader, translator: translator, output: out, clock: clock) { e in
            if case let .shown(l, _) = e { lock.withLock { shown.append(l) } }
        }
        for _ in 0..<40 where out.all.isEmpty {
            await session.process(SpeakerShowTests.image())
            try await Task.sleep(for: .milliseconds(20))
            clock.advance(100)
        }
        let p = try XCTUnwrap(out.all.last)
        // Çevirmene yer tutuculu metin gitti (önbellek/havuz anahtarı tuştan bağımsız).
        XCTAssertEqual(translator.sentences, ["You can use ⟦T1⟧ later, okay?"])
        // Kaybolan yer tutucu `tuşunu`nun yerine kondu.
        XCTAssertEqual(p.text, "Sonra ⟦T1⟧ kullanabilirsin, tamam mı?")
        XCTAssertEqual(p.icons, [LinkIcon(id: "T1", name: "L2")])
        // Bilgisayardaki pencere ve geçmiş okunur metni görür; eski 8787 de.
        XCTAssertEqual(lock.withLock { shown.last?.translated }, "Sonra [L2] kullanabilirsin, tamam mı?")
        var legacy = LegacyTranslator()
        XCTAssertTrue(legacy.subtitle(p).data.contains("Sonra [L2] kullanabilirsin"))
    }

    func testQuestStripItemCarriesIcons() throws {
        let lines = [GameReading.Line("Hold to interact with your partner",
                                      box: GameReading.Box(left: 0.3744, top: 0.9448, right: 0.6243, bottom: 0.9754))]
        let icons = [LinkIcon(id: "T1", name: "dpad-right"), LinkIcon(id: "T2", name: "cross")]
        let e = try XCTUnwrap(ScreenOverlays.cornerElement(.questStrip, lines: lines,
                                                            translation: "Ortağınla etkileşime geçmek için ⟦T1⟧ basılı tut", icons: icons))
        // Metinde yer tutucusu olmayan simge gitmez.
        XCTAssertEqual(e.icons, [LinkIcon(id: "T1", name: "dpad-right")])
        let item = ScreenOverlays.item(e)
        XCTAssertEqual(item.icons, [LinkIcon(id: "T1", name: "dpad-right")])
        XCTAssertEqual(item.jsonObject["icons"] as? [[String: String]], [["id": "T1", "name": "dpad-right"]])
        // Simgesiz öğe eskisi gibi (alan yok).
        let plain = try XCTUnwrap(ScreenOverlays.cornerElement(.questStrip, lines: lines, translation: "Arabana bin"))
        XCTAssertNil(ScreenOverlays.item(plain).jsonObject["icons"])
        // Günlük okunur biçimi yazar.
        let short = try XCTUnwrap(ScreenOverlays.cornerElement(.questStrip, lines: lines, translation: "⟦T1⟧ basılı tut", icons: icons))
        XCTAssertTrue(LineLogText.elements([short]).contains("[→] basılı tut"), LineLogText.elements([short]))
    }
}
