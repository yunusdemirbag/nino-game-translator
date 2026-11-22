// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

/// "Yalnız altyazıyı çevir" (oyun-okuma.md "Yalnız altyazı").
final class GameReadingSubtitlesOnlyTests: XCTestCase {
    typealias C = GR.FilterChain
    let area = gbox(0.14, 0.62, 0.86, 0.97)

    /// Kare oranındaki kutuyu alan içine çevirir.
    func line(_ text: String, _ l: Double, _ t: Double, _ r: Double, _ b: Double) -> GR.Line {
        gline(text, gbox(l, t, r, b).local(in: area))
    }

    func run(_ lines: [GR.Line], only: Bool, strip: (top: Double, bottom: Double)? = nil, phone: Bool = false) -> String? {
        var c = C()
        var x = C.Context(now: 0, area: area)
        x.subtitlesOnly = only
        x.strip = strip
        x.phoneGame = phone
        return c.run(lines, x).text
    }

    // MARK: Gerçek altyazılar kalır (yanlış pozitif yok)

    func testRealSubtitlesAreKept() {
        let cases: [[GR.Line]] = [
            [line("BRENNA: Hold the door", 0.33, 0.84, 0.67, 0.87), line("before the storm hits.", 0.35, 0.875, 0.65, 0.905)],
            [line("- Where are you going?", 0.36, 0.86, 0.64, 0.89), line("- Home.", 0.45, 0.895, 0.55, 0.925)],
            [line("[Laughs] You're kidding me.", 0.35, 0.88, 0.65, 0.91)],
            [line("...I don't know anymore.", 0.36, 0.88, 0.64, 0.91)],
            [line("\"Run!\"", 0.46, 0.88, 0.54, 0.91)],
            [line("Meet me at the", 0.38, 0.84, 0.62, 0.87), line("Old Town Gate", 0.40, 0.875, 0.60, 0.905)],
            [line("OK.", 0.47, 0.88, 0.53, 0.91)],
            [line("Thank you, Kratos.", 0.40, 0.88, 0.60, 0.91)],
            [line("♪ Sailing over the sea ♪", 0.38, 0.88, 0.62, 0.91)],
            [line("• And shut the damn dog up.", 0.36, 0.88, 0.64, 0.91)],
            // Uzun satırın iki parçası: sol parça tek başına ortada değil.
            [line("We should get going before", 0.16, 0.88, 0.49, 0.91), line("the guards come back.", 0.50, 0.88, 0.80, 0.91)],
            [line("ATREUS: Father, look!", 0.38, 0.88, 0.62, 0.91)],
        ]
        for lines in cases {
            let off = run(lines, only: false)
            XCTAssertNotNil(off, lines.map(\.text).joined(separator: " / "))
            XCTAssertEqual(run(lines, only: true), off, lines.map(\.text).joined(separator: " / "))
            XCTAssertEqual(run(lines, only: true, strip: (0.84, 0.93)), off, lines.map(\.text).joined(separator: " / "))
        }
    }

    // MARK: Görev, ipucu, sekme, menü atılır

    func testQuestHintTabLinesAreDropped() {
        let subtitle = line("I told you to stay put.", 0.37, 0.86, 0.63, 0.89)
        let noise: [GR.Line] = [
            line("Follow Arthur to the barn", 0.16, 0.66, 0.40, 0.69),     // görev, solda
            line("◆ Find the hidden key", 0.40, 0.70, 0.60, 0.73),          // simgeli görev
            line("Main Quest", 0.44, 0.75, 0.56, 0.78),                     // sekme adı
            line("R2 Aim", 0.47, 0.79, 0.53, 0.82),                         // tuş
        ]
        XCTAssertEqual(run(noise + [subtitle], only: true), subtitle.text)
    }

    func testTabBarAboveSubtitleIsDropped() {
        let subtitle = line("Do you hear that?", 0.40, 0.86, 0.60, 0.89)
        let tabs = [line("MAP", 0.40, 0.81, 0.45, 0.84), line("SKILLS", 0.47, 0.81, 0.53, 0.84), line("Gear", 0.55, 0.81, 0.60, 0.84)]
        XCTAssertEqual(run(tabs + [subtitle], only: true), subtitle.text)
    }

    func testCenteredQuestAboveLearnedStripIsDropped() {
        let quest = line("Reach the lighthouse before nightfall.", 0.36, 0.66, 0.64, 0.69)
        XCTAssertNil(run([quest], only: true, strip: (0.84, 0.93)))
        XCTAssertEqual(run([quest], only: true), quest.text) // şerit bilinmiyorsa konumdan atılmaz
    }

    func testPressHintIsDropped() {
        XCTAssertNil(run([line("Press ✕ to open the door", 0.38, 0.88, 0.62, 0.91)], only: true))
    }

    func testOffInPhoneGame() {
        let quest = line("Follow Arthur to the barn now", 0.45, 0.88, 0.55, 0.91)
        XCTAssertEqual(run([quest], only: true, phone: true), run([quest], only: false, phone: true))
    }

    func testTabLikeShape() {
        typealias S = GR.Filters.SubtitlesOnly
        XCTAssertTrue(S.isTabLike("MAP"))
        XCTAssertTrue(S.isTabLike("Main Quest"))
        XCTAssertFalse(S.isTabLike("Hey"))
        XCTAssertFalse(S.isTabLike("Come here."))
        XCTAssertFalse(S.isTabLike("NO!"))
        XCTAssertFalse(S.isTabLike("Meet me at the"))
    }

    // MARK: Okuyucu: ayar geçer, varsayılan kapalı

    func testReaderConfigurationDefaultOffAndSetter() async {
        XCTAssertFalse(GR.Reader.Configuration().subtitlesOnly)
        let clock = GR.ManualClock()
        let ocr = ScriptedReader(handler: { _ in
            [gline("Follow Arthur", gbox(0.02, 0.10, 0.25, 0.16)), gline("I told you to stay put.", gbox(0.3, 0.80, 0.7, 0.86))]
        })
        var cfg = GR.Reader.Configuration(gameKey: "test")
        cfg.region = GR.Region(preset: .fullFrame)
        cfg.plan = .always
        let reader = GR.Reader(textReader: ocr, clock: clock, configuration: cfg)
        await reader.setSubtitlesOnly(true)
        let out = await reader.process(FakeFrame(0))
        let texts = out.events.compactMap { e -> String? in if case let .subtitleStarted(s) = e { return s.text }; return nil }
        XCTAssertEqual(texts, ["I told you to stay put."])
    }
}
