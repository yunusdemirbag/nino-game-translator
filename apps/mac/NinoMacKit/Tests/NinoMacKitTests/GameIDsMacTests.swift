// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore
import XCTest
@testable import NinoMacKit

/// Oyunun asıl kimliği (NinoCore `GameIDs`): izleyicide asıl kimlik, eski kayıtlar asıl ada.
final class GameIDsMacTests: XCTestCase {
    func testTrackerUsesCanonicalIDs() {
        var g = GameTracker()
        g.startSession(at: Date())
        g.seed("GTA 6")
        XCTAssertEqual(g.current?.id, "gta-6")
        g.choose("Grand Theft Auto VI")
        XCTAssertEqual(g.current?.id, "gta-6")
        g.clearUserChoice()
        g.screenRecognized("GTA VI")
        XCTAssertEqual(g.current?.id, "gta-6")
        // Havuz paketi oyu: zaten tahmin edilen oyun olduğu için bir oy doğrular; kimlik asıl.
        XCTAssertTrue(g.vote(packID: "pool-gta-6", title: nil))
        XCTAssertEqual(g.current?.id, "gta-6")
        XCTAssertEqual(g.current?.name, "GTA 6")
        XCTAssertTrue(GameTracker.same("pool-gta-6", "Grand Theft Auto VI"))
        g.consoleReported(name: "Grand Theft Auto V", titleID: "PPSA01234")
        XCTAssertEqual(g.current?.id, "gta-v")
    }

    func testStoredNamesReadAsCanonical() {
        XCTAssertEqual(LiveEngine.storedGameName("pool-gta-6"), "GTA 6")
        XCTAssertEqual(LiveEngine.storedGameName("Grand Theft Auto VI"), "GTA 6")
        XCTAssertEqual(LiveEngine.storedGameName("Grand Theft Auto V"), "GTA 5")
        XCTAssertEqual(LiveEngine.storedGameName("Benim Oyunum"), "Benim Oyunum")
    }
}

extension GameAutoTests {
    func testOldAliasMemoryIsReadAsCanonical() async throws {
        let rig = try makeRig(quick: nil, lastGame: "Grand Theft Auto VI")
        rig.engine.refreshGameMemory()
        XCTAssertEqual(rig.state.sheetsStatus.lastPlayedGame, "GTA 6")
        await rig.engine.links.stop()
    }
}

/// Ayarlar › kütüphane: gömülü ve havuz GTA 6 paketi tek satır.
final class GroupedPacksTests: XCTestCase {
    func testSameGamePacksBecomeOneRow() {
        let rows = LiveEngine.groupedPacks([
            GamePackInfo(id: "gta6", name: "GTA 6", lines: 7000),
            GamePackInfo(id: "pool-gta-6", name: "Grand Theft Auto VI", lines: 7200),
            GamePackInfo(id: "my-game", name: "Benim Oyunum", lines: 10),
        ])
        XCTAssertEqual(rows.map(\.name), ["GTA 6", "Benim Oyunum"])
        XCTAssertEqual(rows.first?.lines, 7200)
    }
}
