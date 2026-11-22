// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

final class LineKeyTests: XCTestCase {
    /// Örnek çiftler (girdi, sade metin, anahtar); anahtarlar havuz sunucusunun nino-pool/src/key.js koduyla hesaplandı.
    let vectors: [(String, String, String)] = [
        ("Duck behind the crates, rookie!", "duck behind the crates rookie", "0885d31ab6df7d0a"),
        ("Don’t leave the convoy.", "don t leave the convoy", "411111ea3f2b7b24"),
        ("<i><c>RUSTY LANTERN</></> FOUND", "rusty lantern found", "f8e7d3908b0714fb"),
        ("Move It!", "move it", "2a92733a6f2bf2c2"),
        ("  Where   did\nthey go?  ", "where did they go", "b0da4da3c1d33090"),
        ("Señor, más rápido.", "senor mas rapido", "558a6a04622a42bd"),
        ("İzmir", "izmir", "f3698e3490018159"),
        ("Ｇａｔｅ　７", "gate 7", "a4b972de42a56651"),
        ("Øresund œuvre", "øresund œuvre", "0c867223ed23da1b"),
    ]

    func testVectors() {
        for (input, canon, hex) in vectors {
            XCTAssertEqual(LineKey.canon(input), canon, input)
            XCTAssertEqual(LineKey.key(input).map(LineKey.hex), hex, input)
        }
    }

    func testEmptyHasNoKey() {
        XCTAssertNil(LineKey.key("..."))
        XCTAssertNil(LineKey.key(""))
        XCTAssertNil(LineKey.key("<b></b>"))
    }

    func testPunctuationIgnored() {
        XCTAssertEqual(LineKey.key("Run."), LineKey.key("Run?"))
    }

    func testLongTagIsKept() {
        let inner = String(repeating: "a", count: 41)
        XCTAssertEqual(LineKey.canon("<\(inner)>"), inner)
        XCTAssertEqual(LineKey.canon("<\(String(inner.dropLast()))> x"), "x")
    }

    func testHexRoundTrip() {
        XCTAssertEqual(LineKey.parse("C1AEE1BA1957AEAE"), LineKey.parse("c1aee1ba1957aeae"))
        XCTAssertEqual(LineKey.hex(0x1), "0000000000000001")
        XCTAssertNil(LineKey.parse("c1aee1ba1957aea"))
        XCTAssertNil(LineKey.parse("c1aee1ba1957aeag"))
    }

    func testGameNameKey() {
        XCTAssertEqual(GameName.key("Grand Theft Auto VI"), "gta 6")
        XCTAssertEqual(GameName.key("GTA6"), "gta 6")
        XCTAssertEqual(GameName.key("The Last of Us™ Part II"), "last of us part 2")
        XCTAssertEqual(GameName.key("Marvel’s Spider-Man 2"), "marvels spider man 2")
        XCTAssertEqual(GameName.key("Red Dead Redemption 2"), "rdr 2")
        XCTAssertEqual(GameName.key("EA SPORTS FC™ 25"), "fc 25")
        XCTAssertEqual(GameName.key("The"), "the")
    }

    func testGameID() {
        XCTAssertEqual(GameName.id("Mafia: The Old Country"), "mafia-the-old-country")
        XCTAssertEqual(GameName.id("  --Grand Theft Auto VI.. "), "grand-theft-auto-vi")
        XCTAssertNil(GameName.id("!!!"))
        XCTAssertEqual(GameName.id(String(repeating: "a", count: 70))?.count, 64)
    }
}
