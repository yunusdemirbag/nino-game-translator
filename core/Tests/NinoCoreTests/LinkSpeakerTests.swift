// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import XCTest
@testable import NinoCore

/// `show.speaker` (protokol.md, isteğe bağlı, sürüm 1).
final class LinkSpeakerTests: XCTestCase {
    func testSpeakerIsSentSeparately() throws {
        let p = ShowPayload(id: 7, text: "Kapıyı tut.", source: "BRENNA: Hold the door.", speaker: "BRENNA")
        XCTAssertEqual(NinoMessage.show(p).jsonString,
                       #"{"app":"nino","durationMs":0,"id":7,"position":"bottom","source":"BRENNA: Hold the door.","speaker":"BRENNA","text":"Kapıyı tut.","type":"show"}"#)
        guard case let .show(back) = try NinoMessage(string: NinoMessage.show(p).jsonString) else { return XCTFail() }
        XCTAssertEqual(back, p)
    }

    func testNoSpeakerKeepsOldJSON() throws {
        XCTAssertEqual(NinoMessage.show(ShowPayload(id: 1, text: "Selam")).jsonString,
                       #"{"app":"nino","durationMs":0,"id":1,"position":"bottom","text":"Selam","type":"show"}"#)
        // Boş ad gönderilmez; eski JSON'da alan yoksa nil.
        XCTAssertFalse(NinoMessage.show(ShowPayload(id: 1, text: "Selam", speaker: "  ")).jsonString.contains("speaker"))
        guard case let .show(old) = try NinoMessage(string: #"{"app":"nino","type":"show","id":3,"text":"Selam"}"#) else { return XCTFail() }
        XCTAssertNil(old.speaker)
    }

    func testLongSpeakerIsClipped() throws {
        let long = String(repeating: "A", count: 80)
        let json = NinoMessage.show(ShowPayload(id: 1, text: "x", speaker: long)).jsonString
        guard case let .show(p) = try NinoMessage(string: json) else { return XCTFail() }
        XCTAssertEqual(p.speaker?.count, ShowPayload.speakerMaxLength)
    }

    func testLegacyGetsPrefixedSingleText() {
        var t = LegacyTranslator()
        let at = Date(timeIntervalSince1970: 1_732_233_600)
        let e = t.subtitle(ShowPayload(id: 1, text: "Kapıyı tut.", durationMs: 2500, speaker: "BRENNA"), now: at)
        XCTAssertEqual(e.data, #"{"at":1732233600000,"duration":2500,"text":"BRENNA: Kapıyı tut."}"#)
        // Metin zaten adla başlıyorsa iki kez eklenmez.
        let same = t.subtitle(ShowPayload(id: 2, text: "BRENNA: Kapıyı tut.", durationMs: 2500, speaker: "BRENNA"), now: at)
        XCTAssertEqual(same.data, #"{"at":1732233600000,"duration":2500,"text":"BRENNA: Kapıyı tut."}"#)
    }
}
