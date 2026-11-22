// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import XCTest
@testable import NinoCore

/// Kaçırma ölçer: diyalog tanımı, toplama, günlükle eşleştirme ve gerçek karelerle tarama.
final class GameMissMeterTests: XCTestCase {
    typealias M = GR.MissMeter

    func testDialogueDefinition() {
        let mid = gbox(0.35, 0.86, 0.65, 0.90)
        XCTAssertTrue(M.isDialogue("And after what we went through,", box: mid))
        XCTAssertTrue(M.isDialogue("OK.", box: mid))
        XCTAssertFalse(M.isDialogue("PHOTO STUDIO SELECT BACK", box: mid), "tamamı büyük harf")
        XCTAssertFalse(M.isDialogue("OKUNAN: And after what we went through,", box: mid), "kayıtçının kendi yazısı")
        XCTAssertFalse(M.isDialogue("And after what we went through,", box: gbox(0.70, 0.86, 0.95, 0.90)), "ortada değil")
        XCTAssertFalse(M.isDialogue("And after what we went through,", box: gbox(0.35, 0.30, 0.65, 0.35)), "alt şeritte değil")
        XCTAssertFalse(M.isDialogue("Hello", box: mid), "tek sözcük")
    }

    func testCollectorJoinsRereadsAndSplitsNewLines() {
        var c = M.Collector()
        c.add("You know, if Cal were here, he- he'd know exactly", at: 0)
        c.add("You know, if Cal were here, he- he'd know exactly what to do.", at: 1_000)
        c.add("Whatever is on this thing is worth a lot of fucking money.", at: 2_000)
        c.add("You know, if Cal were here, he- he'd know exactly what to do.", at: 9_000)
        XCTAssertEqual(c.candidates.map(\.text), ["You know, if Cal were here, he- he'd know exactly what to do.",
                                                  "Whatever is on this thing is worth a lot of fucking money.",
                                                  "You know, if Cal were here, he- he'd know exactly what to do."])
        XCTAssertEqual(c.candidates[0].frames, 2)
    }

    func testLogClassifyAndMatch() {
        XCTAssertEqual(M.classify("#14 okundu \"And after what we went through,\" → çeviriye"), .read("And after what we went through,"))
        XCTAssertEqual(M.classify("#12 okundu (uzadı) \"So, we still don't know shit? ep\" → çeviriye"), .read("So, we still don't know shit? ep"))
        XCTAssertEqual(M.classify("atlandı: menü \"You know…\""), .note("atlandı: menü \"You know…\""))
        XCTAssertNil(M.classify("#14 gösterildi (TV 1)"))
        XCTAssertTrue(M.matches("So, it's, uh...", read: "So? / So, it's, uh..."))
        XCTAssertTrue(M.matches("we deserve to get paid.\nUh-huh.", read: "we deserve to get paid. / Uh-huh."))
        XCTAssertTrue(M.matches("So, we still don't know shit?", read: "So, we still don't know shit? ep"))
        XCTAssertFalse(M.matches("Whatever is on this thing is worth a lot of fucking money.", read: "And after what we went through,"))
    }

    func testCompareReportsMissesWithReasons() {
        let cands = [M.Candidate(text: "You know, if Cal were here.", firstMs: 1_000, lastMs: 3_000, frames: 3),
                     M.Candidate(text: "And after what we went through,", firstMs: 5_000, lastMs: 6_000, frames: 2)]
        let r = M.compare(cands, reads: [M.LogEntry(ms: 5_200, text: "And after what we went through,")],
                          notes: [M.LogEntry(ms: 1_500, text: "atlandı: menü \"You know, if Cal…\"")])
        XCTAssertEqual(r.caught.count, 1)
        XCTAssertEqual(r.misses.map(\.candidate.text), ["You know, if Cal were here."])
        XCTAssertEqual(r.misses.first?.loggedReasons, ["atlandı: menü"])
        XCTAssertEqual(r.rate, 0.5)
        XCTAssertTrue(M.format(r, title: "t", stamp: { "\($0)" }).contains("günlükte: atlandı: menü"))
    }

    func testScreenElements() {
        XCTAssertTrue(M.isElement("SPLIT UP & TAKE\nSLOW DOWN", box: gbox(0.55, 0.53, 0.68, 0.69)))
        XCTAssertEqual(M.elementPlace(gbox(0.55, 0.53, 0.68, 0.69)), "sağ")
        XCTAssertTrue(M.isElement("Map updated", box: gbox(0.02, 0.1, 0.2, 0.15)))
        XCTAssertEqual(M.elementPlace(gbox(0.02, 0.1, 0.2, 0.15)), "sol üst")
        XCTAssertFalse(M.isElement("And after what we went through,", box: gbox(0.35, 0.86, 0.65, 0.9)), "altyazı bandı")
        XCTAssertFalse(M.isElement("R1", box: gbox(0.85, 0.9, 0.88, 0.95)))
        XCTAssertEqual(M.classify("Ekran öğeleri (1): köşe \"Jason ve Lucia'nın…\""), .element("Ekran öğeleri (1): köşe \"Jason ve Lucia'nın…\""))
        XCTAssertNil(M.classify("Ekran öğeleri kalktı"))
        let c = [M.Candidate(text: "Map updated", firstMs: 1_000, lastMs: 2_000, frames: 2, kind: "sol üst"),
                 M.Candidate(text: "BuckMe Family savings", firstMs: 20_000, lastMs: 22_000, frames: 3, kind: "sağ alt")]
        let r = M.compareElements(c, logged: [M.LogEntry(ms: 1_500, text: "Ekran öğeleri (1): köşe \"Harita güncellendi\"")])
        XCTAssertEqual(r.caught.map(\.text), ["Map updated"])
        XCTAssertTrue(M.formatElements(r, stamp: { "\($0)" }).contains("KARŞILIKSIZ 20000–22000 [sağ alt]"))
    }

    #if canImport(Vision)
    /// 22 Kasım 23:41 kareleri: ölçer dört diyalog satırı bulur. Deneme-3 günlüğü yalnız üçüncüsünü okumuştu (3 kaçan);
    /// kurallar açık yeniden oynatma (bu sürüm) dördünü de okur.
    func testScannerOnMenuExitFrames() async throws {
        var cfg = GR.Reader.Configuration()
        GR.GTA6Rules.apply(true, packGame: "gta-6", to: &cfg)
        let frames = GameReadingMenuExitTests.frames
        var old = cfg
        old.menuClearsOnExit = false
        old.lowercaseContinuation = false
        let scanner = M.Scanner(textReader: GR.VisionTextReader(), replayConfigurations: [("eski", old), ("yeni", cfg)],
                                startMs: frames[0].0 - 6_000)
        // Menü dakikalarca açıktı: ilk kare 6 sn önceden.
        await scanner.scan(GR.ImageFrame(try GameReadingMenuExitTests.image(frames[0].1)), at: frames[0].0 - 6_000)
        for (ms, name) in frames {
            await scanner.scan(GR.ImageFrame(try GameReadingMenuExitTests.image(name)), at: ms)
        }
        let menuFrames = await scanner.menuFrames
        XCTAssertGreaterThanOrEqual(menuFrames, 1)
        let cands = await scanner.collector.candidates
        XCTAssertEqual(cands.count, 4, "\(cands.map(\.text))")
        let deneme3 = M.compare(cands, reads: [M.LogEntry(ms: 27_689, text: "And after what we went through,")])
        XCTAssertEqual(deneme3.misses.count, 3)
        let replays = await scanner.replays
        let now = M.compare(cands, reads: replays["yeni"]?.reads ?? [])
        XCTAssertEqual(now.misses.map(\.candidate.text), [])
        // Eski kurallarla yeniden oynatma deneme-3'ün kaçırdığı satırı ve nedenini gösterir.
        let before = M.compare(cands, reads: replays["eski"]?.reads ?? [], replayNotes: replays["eski"]?.notes ?? [])
        XCTAssertTrue(before.misses.contains { $0.replayReasons.contains("atıldı: küçük harfle başlayan blok") }, "\(before.misses)")
    }
    #endif
}
