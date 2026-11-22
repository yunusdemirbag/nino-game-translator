// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

/// Havuz sunucusunun (nino-pool `src/packs.js`) ürettiği paketler `PackUpdater` ile iner ve `LegacyPack` ile okunur mu.
/// Yalnız `NINO_LOCAL_POOL_URL=http://127.0.0.1:8799` verilince çalışır (yerel `wrangler dev`); taşıyıcı yalnız yerel
/// adreslere gider. `NINO_LOCAL_POOL_PACKS=1`: yerel veritabanına "Nino local pack test line." satırı ve Türkçesi konup
/// paketler üretildi (nino-pool `scripts/build-packs.mjs`), satırın paketten çıkması beklenir.
final class PoolPacksLocalServerTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws { dir = try makeLibraryTempDirectory("nino-packs-local") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testLocalServerPacksDownloadAndLoad() async throws {
        guard let raw = ProcessInfo.processInfo.environment["NINO_LOCAL_POOL_URL"], let base = URL(string: raw) else {
            throw XCTSkip("NINO_LOCAL_POOL_URL verilmedi")
        }
        let transport = LoopbackOnlyTransport()
        try transport.check(base)
        let packs = dir.appendingPathComponent("packs")
        let status = dir.appendingPathComponent("packs-remote.json")
        let updater = PackUpdater(packsDirectory: packs, statusFile: status,
                                  configuration: PoolConfiguration(baseURL: base, enabled: true, appVersion: "4.1.0"),
                                  transport: transport)

        let first = await updater.check()
        XCTAssertFalse(first.listFailed)
        XCTAssertTrue(first.failed.isEmpty, "\(first)")
        XCTAssertEqual(transport.statuses["/v1/packs"], 200)
        let recorded = await updater.status().packs
        XCTAssertEqual(recorded.map(\.id).sorted(), first.downloaded.sorted())
        for pack in recorded {
            XCTAssertTrue(PackUpdater.isValidID(pack.id), pack.id)
            XCTAssertGreaterThan(pack.version, 0)
            let file = packs.appendingPathComponent("\(pack.id).json.gz")
            XCTAssertEqual(PackUpdater.sha256(of: file), pack.sha256)
            let loaded = try LegacyPack(contentsOf: file)
            XCTAssertEqual(loaded.id, pack.id)
            XCTAssertEqual(loaded.title, pack.title)
            XCTAssertGreaterThan(loaded.lineCount, 0)
        }

        if ProcessInfo.processInfo.environment["NINO_LOCAL_POOL_PACKS"] == "1" {
            let id = "pool-grand-theft-auto-vi"
            XCTAssertTrue(first.downloaded.contains(id), "\(first)")
            let pack = try LegacyPack(contentsOf: packs.appendingPathComponent("\(id).json.gz"))
            XCTAssertEqual(pack.title, "Grand Theft Auto VI")
            // Sunucunun anahtarı (key.js) istemcinin LineKey'iyle aynı: İngilizce cümleden Türkçesi bulunur.
            XCTAssertEqual(pack.exact("Nino local pack test line."), "Nino yerel paket deneme satırı.")
            XCTAssertEqual(pack.exact("NINO LOCAL PACK TEST LINE"), "Nino yerel paket deneme satırı.")
            // Kütüphane oyun adıyla da bulur (başlık GameName anahtarıyla eşleşir).
            XCTAssertEqual(GameName.key(pack.title), GameName.key("Grand Theft Auto VI"))
        }

        // İkinci bakış: içerik değişmedi, yeniden inmez.
        let second = await updater.check()
        XCTAssertTrue(second.downloaded.isEmpty, "\(second)")
        XCTAssertTrue(second.failed.isEmpty)
        XCTAssertFalse(second.changed)
    }
}
