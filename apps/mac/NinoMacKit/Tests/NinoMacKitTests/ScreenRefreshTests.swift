// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import NinoCore
import XCTest
@testable import NinoMacKit

/// Ekranda duran ama değişmeyen öğeler (ör. harita kartı) TV'deki süre dolmadan yeniden gönderilir
/// (NinoCore `ScreenItemSender`; ayrıntılı testler NinoCore'da).
final class ScreenRefreshTests: XCTestCase {
    func testRefreshBeforeTVExpiry() {
        var sender = GameReading.ScreenItemSender()
        let half = sender.settings.refreshAfterMs
        XCTAssertEqual(half, ScreenOverlays.layerDurationMs / 2)
        XCTAssertLessThan(half, ScreenOverlays.layerDurationMs, "TV süresi dolmadan yenilenmeli")
        let card = GameReading.ScreenElement(kind: .map, id: "kart", box: GameReading.Box(left: 0.5, top: 0.6, right: 0.8, bottom: 0.7),
                                             text: "AVERY PAWN")
        XCTAssertEqual(sender.update([card], nowMs: 1_000), .screen([card]))
        XCTAssertNil(sender.refresh(nowMs: 1_000 + half - 1))
        XCTAssertEqual(sender.refresh(nowMs: 1_000 + half), .screen([card]))
    }
}
