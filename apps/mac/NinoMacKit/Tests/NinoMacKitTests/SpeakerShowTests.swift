// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import NinoCore
import XCTest
@testable import NinoMacKit

/// Konuşan adı `show.speaker` ile ayrı gider (protokol.md); `text` adsız çeviri.
final class SpeakerShowTests: XCTestCase {
    struct ArabicTranslator: SubtitleTranslating {
        func translate(_ sentence: String) async -> SessionTranslation { SessionTranslation(text: "أمسك الباب.", origin: .engine) }
    }

    struct FixedReader: GameReading.TextReader {
        let lines: [GameReading.Line]
        func read(_ frame: GameReading.Frame, area: GameReading.Box, scale: Double) async throws -> [GameReading.Line] { lines }
    }

    final class Shows: DisplayOutput, @unchecked Sendable {
        private let lock = NSLock()
        private var items: [ShowPayload] = []
        func show(_ payload: ShowPayload) async throws { lock.withLock { items.append(payload) } }
        func clear(id: Int?) async throws {}
        func send(_ event: NinoEvent) async throws {}
        var all: [ShowPayload] { lock.withLock { items } }
    }

    static func image() -> CGImage {
        let ctx = CGContext(data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 36))
        return ctx.makeImage()!
    }

    func shown(_ text: String, showNames: Bool) async throws -> ShowPayload {
        let clock = GameReading.ManualClock()
        var cfg = GameReading.Reader.Configuration(gameKey: "test")
        cfg.region = GameReading.Region(preset: .fullFrame)
        cfg.plan = .always
        let lines = text.split(separator: "\n").enumerated().map { i, l in
            GameReading.Line(String(l), confidence: 0.95,
                             box: GameReading.Box(left: 0.3, top: 0.80 + Double(i) * 0.04, right: 0.7, bottom: 0.83 + Double(i) * 0.04))
        }
        let reader = GameReading.Reader(textReader: FixedReader(lines: lines), clock: clock, configuration: cfg)
        let out = Shows()
        var o = SubtitleSession.Options()
        o.showSpeakerNames = showNames
        let session = SubtitleSession(reader: reader, translator: ArabicTranslator(), output: out, clock: clock, options: o) { _ in }
        for _ in 0..<40 where out.all.isEmpty {
            await session.process(Self.image())
            try await Task.sleep(for: .milliseconds(20))
            clock.advance(100)
        }
        return try XCTUnwrap(out.all.last)
    }

    func testSpeakerIsSeparateAndTextHasNoName() async throws {
        let p = try await shown("BRENNA: Hold the door.", showNames: true)
        XCTAssertEqual(p.speaker, "BRENNA")
        XCTAssertEqual(p.text, "أمسك الباب.")
        XCTAssertEqual(p.source, "BRENNA: Hold the door.")
        // Eski 8787: tek metin, adla.
        var legacy = LegacyTranslator()
        XCTAssertTrue(legacy.subtitle(p).data.contains("BRENNA: أمسك الباب."))
    }

    func testNoSpeakerWhenSettingOff() async throws {
        let p = try await shown("BRENNA: Hold the door.", showNames: false)
        XCTAssertNil(p.speaker)
        XCTAssertEqual(p.text, "أمسك الباب.")
    }

    func testSplitRules() {
        let one = SubtitleSession.splitSpeaker("BRENNA: Kapıyı tut.", source: "BRENNA: Hold the door.", showSpeakerNames: true)
        XCTAssertEqual(one.speaker, "BRENNA"); XCTAssertEqual(one.text, "Kapıyı tut.")
        // İki konuşan: adlar metinde kalır.
        let two = SubtitleSession.splitSpeaker("A: Evet.\nB: Hayır.", source: "ANNA: Yes.\nBO: No.", showSpeakerNames: true)
        XCTAssertNil(two.speaker); XCTAssertEqual(two.text, "A: Evet.\nB: Hayır.")
        // Çeviri adla başlamıyor (paket çevirisi): bölünmez.
        let pack = SubtitleSession.splitSpeaker("Kapıyı tut.", source: "BRENNA: Hold the door.", showSpeakerNames: true)
        XCTAssertNil(pack.speaker); XCTAssertEqual(pack.text, "Kapıyı tut.")
        // Adsız satır.
        XCTAssertNil(SubtitleSession.splitSpeaker("Selam.", source: "Hi.", showSpeakerNames: true).speaker)
    }

    func testSubtitlesOnlySettingDefaultsOffForOldRecord() throws {
        let s = try XCTUnwrap(MacSettings.decode(Data(#"{"showSpeakerNames":true}"#.utf8)))
        XCTAssertFalse(s.subtitlesOnly)
        var on = MacSettings()
        on.subtitlesOnly = true
        XCTAssertEqual(MacSettings.decode(on.encoded())?.subtitlesOnly, true)
    }
}
