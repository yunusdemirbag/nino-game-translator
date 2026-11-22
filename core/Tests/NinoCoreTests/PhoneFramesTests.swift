// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import ImageIO
import XCTest
@testable import NinoCore

/// TV'ye giden telefon öğeleri: süreyle tutma, kutu oynaması, yazısız öğe.
final class PhoneSenderTests: XCTestCase {
    private func el(_ id: String, _ text: String, top: Double = 0.3, backdrop: Bool = false) -> GR.ScreenElement {
        var s = GR.ScreenElement.Style(lineHeight: 0.02)
        s.backdrop = backdrop
        return GR.ScreenElement(kind: .phone, id: id, box: GR.Box(left: 0.1, top: top, right: 0.3, bottom: top + 0.05), text: text, style: s)
    }

    func testPhoneHeldBrieflyDroppedOnRequest() {
        var s = GR.ScreenItemSender()
        let panel = [el("00-zemin", "", backdrop: true), el("02", "Merhaba")]
        XCTAssertEqual(s.update(panel, nowMs: 0), .screen(panel))
        // Panel bir an yok (yeniden kuruluyor): TV'de kalır.
        XCTAssertNil(s.update([], nowMs: 1_000))
        XCTAssertTrue(s.isHoldingTimed(.phone))
        // Yenisi gelince hemen değişir.
        let next = [el("00-zemin", "", backdrop: true), el("02", "Selam")]
        XCTAssertEqual(s.update(next, nowMs: 1_500), .screen(next))
        // Telefon kapandı: hemen kalkar.
        XCTAssertEqual(s.update([], nowMs: 2_000, drop: [.phone]), .clear)
        // Bir an kaybolup gelmezse süre dolunca (`refresh`) kalkar.
        _ = s.update(next, nowMs: 10_000)
        XCTAssertNil(s.update([], nowMs: 10_500))
        XCTAssertNil(s.refresh(nowMs: 12_000))
        XCTAssertEqual(s.refresh(nowMs: 13_000), .clear)
    }

    func testSmallBoxJitterAndEmptyText() {
        var s = GR.ScreenItemSender()
        let a = [el("00-zemin", "", backdrop: true), el("02", "Merhaba", top: 0.300), el("03", "")]
        guard case let .screen(sent)? = s.update(a, nowMs: 0) else { return XCTFail() }
        XCTAssertEqual(sent.map(\.id), ["00-zemin", "02"], "yazısız öğe gitmez, zemin gider")
        XCTAssertNil(s.update([el("00-zemin", "", backdrop: true), el("02", "Merhaba", top: 0.303)], nowMs: 1_000), "3 px oynama")
        XCTAssertNotNil(s.update([el("00-zemin", "", backdrop: true), el("02", "Merhaba", top: 0.32)], nowMs: 2_000))
    }

    /// Grup sohbetinde iki kez geçen gönderen adı kaydırma sayılmaz (eskiden ikinci "Cal" birincisiyle eşleşiyordu).
    func testScrollMatchIsOneToOne() {
        let phone = GR.PhoneLocation(box: GR.Box(left: 0.55, top: 0.2, right: 0.78, bottom: 0.87))
        func m(_ t: String, _ top: Double) -> GR.PhoneMessage { GR.PhoneMessage(text: t, box: GR.Box(left: 0.6, top: top, right: 0.75, bottom: top + 0.02), lineHeight: 0.02) }
        let items = [("Yes", 0.35), ("Hello there friend.", 0.45), ("Yes", 0.70)].map { GR.PhonePanelItem(source: $0.0, translation: "Evet", message: m($0.0, $0.1)) }
        let read = [m("Yes", 0.352), m("Hello there friend.", 0.451), m("Yes", 0.703)]
        let pairs = GR.PhonePanel.match(items, phone, read, phone)
        XCTAssertEqual(pairs.map(\.1.box.top), [0.352, 0.451, 0.703])
    }
}

#if canImport(Vision)
/// Kullanıcının GTA 6 grup sohbeti kareleri (22 Kasım, 1280 genişlik): panel her birkaç saniyede TV'den kalkıp geliyordu.
final class PhoneFramesTests: XCTestCase {
    static func image(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Resources/gta6-phone"))
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
    }

    /// Mac'teki `ScreenOverlays` telefon akışı: tur + takip → tahta → gönderici (sahte saat, 1 sn aralık).
    func testGroupChatStaysAndLeavesWithPhone() async throws {
        let clock = GR.ManualClock(0)
        let t = FakePhoneTranslator(); t.asksPool = false
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let w = GR.PhoneWatcher(textReader: GR.CPUTextReader(), clock: clock, memory: .init(directory: dir, language: "tr"), translator: t)
        _ = await w.setPhoneGame(true)
        var board = GR.ElementsBoard()
        var sender = GR.ScreenItemSender()
        var messages: [(String, GR.ScreenItemSender.Message)] = []

        func play(_ name: String) async throws {
            clock.nowMs += 1_000
            let f = GR.ImageFrame(try Self.image(name))
            var drop: Set<GR.ScreenElement.Kind> = []
            for u in [await w.trackPhone(f), await w.round(f)].compactMap({ $0 }) {
                guard let els = u.elements else { continue }
                board.removeAll(kind: .phone)
                for e in els { board.set(e) }
                if els.isEmpty, !u.mayHold { drop.insert(.phone) }
            }
            if let m = sender.update(board.list, nowMs: clock.nowMs, drop: drop) { messages.append((name, m)) }
            if let m = sender.refresh(nowMs: clock.nowMs) { messages.append((name, m)) }
        }

        let chat = ["phone-13-43-03", "phone-13-43-03", "phone-13-43-19", "phone-13-43-21", "phone-13-43-33",
                    "phone-13-43-35", "phone-13-43-37", "phone-13-43-39", "phone-13-43-03", "phone-13-43-21"]
        for n in chat { try await play(n) }
        guard !messages.isEmpty else { throw XCTSkip("Vision bu ortamda yazı okumadı") }
        XCTAssertFalse(messages.contains { $0.1 == .clear }, "telefon açıkken kalktı: \(messages.map(\.0))")
        XCTAssertEqual(messages.count, 1, "aynı panel yeniden gönderildi: \(messages.map(\.0))")
        guard case let .screen(list) = messages[0].1 else { return XCTFail() }
        let texts = list.map(\.text)
        // Gönderen adı balonun başlığı; kırpılmış üst balon yok; yazısız öğe yalnız zemin.
        // (1280 genişlikte Vision ilk "Cal"ı okumuyor, ikincisini "Call" okuyor.)
        XCTAssertTrue(texts.contains { $0.hasPrefix("Cal") && $0.contains("\nTR Shit okay") }, "\(texts)")
        XCTAssertFalse(texts.contains { $0.contains("shitty motel") }, "\(texts)")
        XCTAssertEqual(list.filter { $0.text.isEmpty }.map(\.id), ["00-zemin"])
        // Başlık sütunun ortasında.
        let zemin = try XCTUnwrap(list.first { $0.id == "00-zemin" }), title = try XCTUnwrap(list.first { $0.id == "01-baslik" })
        XCTAssertEqual(title.text, "Cal, Jason, Lucia")
        XCTAssertEqual(title.box.midX, zemin.box.midX, accuracy: 0.002)
        XCTAssertLessThan(title.box.width, zemin.box.width * 0.8)

        // Sohbet listesine dönüldü (ekran türü değişti): hemen kalkar.
        let before = messages.count
        try await play("phone-13-43-01")
        XCTAssertEqual(messages.dropFirst(before).map(\.1), [.clear])
        XCTAssertFalse(sender.isShowing(.phone))
    }
    /// Jason sohbeti (üstte "…" ile kesik resimli bağlantı kartı, son balon çerçeveli): sohbet listesi sanılıp hiç
    /// çevrilmiyordu ("Jason" + "Dante Fresh" iki ad ve "…" ile biten satır zayıf liste işaretiydi).
    func testChatWithLinkCardIsChat() async throws {
        func read(_ name: String) async throws -> GR.PhoneScreenResult? {
            let img = try Self.image(name)
            guard let px = GR.PhonePixels.from(img, width: GR.PhoneFinder.gridWidth, height: GR.PhoneFinder.gridHeight),
                  let loc = GR.PhoneFinder.find(px) else { return nil }
            let lines = try await GR.CPUTextReader().read(GR.ImageFrame(img), area: loc.box, scale: 1).map { $0.mapped(into: loc.box) }
            return lines.isEmpty ? nil : GR.PhoneScreen.classify(lines, phone: loc)
        }
        var read_ = 0
        for n in ["jason-14-47-04", "jason-14-47-06", "jason-14-47-20"] {
            guard let r = try await read(n) else { continue }
            read_ += 1
            guard case let .screen(s) = r else { XCTFail("\(n): \(r)"); continue }
            XCTAssertEqual(s.kind, .chat, n)
            XCTAssertEqual(s.header, "Jason", n)
            let texts = s.messages.map(\.text)
            XCTAssertFalse(texts.contains { $0.contains("Dante") || $0.contains("throws hell") }, "\(n): \(texts)")
            XCTAssertTrue(texts.first?.hasPrefix("No way. What makes you think") == true, "\(n): \(texts)")
            XCTAssertTrue(texts.last?.hasPrefix("That's something babe") == true, "çerçeveli son balon: \(texts)")
        }
        if read_ == 0 { throw XCTSkip("Vision bu ortamda yazı okumadı") }
        // Gerçek sohbet listesi hâlâ liste.
        if let r = try await read("jason-14-47-02") { XCTAssertEqual(r, .list) }

        // İzleyici paneli kurar (ikinci okumada onaylanıp çevrilir).
        let clock = GR.ManualClock(0)
        let t = FakePhoneTranslator(); t.asksPool = false
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let w = GR.PhoneWatcher(textReader: GR.CPUTextReader(), clock: clock, memory: .init(directory: dir, language: "tr"), translator: t)
        _ = await w.setPhoneGame(true)
        var shown: [GR.ScreenElement] = []
        for n in ["jason-14-47-04", "jason-14-47-06", "jason-14-47-20"] {
            clock.nowMs += 1_000
            if let els = await w.round(GR.ImageFrame(try Self.image(n)))?.elements { shown = els }
        }
        XCTAssertEqual(shown.first { $0.id == "01-baslik" }?.text, "Jason")
        XCTAssertEqual(shown.filter { $0.text.hasPrefix("TR ") }.count, 6, "\(shown.map(\.text))")
    }
}
#endif
