// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import NinoCore
import NinoDebugKit
import SwiftUI
import XCTest
@testable import NinoMacKit

/// Hata ayıklama kaydı: halka tampon, indeks, aralık, özet, bütçe, video parçaları, kapalı kalma, kıyas.
final class DebugRecordTests: XCTestCase {
    private var root: URL!
    private var layout: DebugRecordLayout!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("nino-debugkayit-\(UUID().uuidString)")
        layout = DebugRecordLayout(logsFolder: root)
        layout.createFolders()
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func put(_ s: DebugStream, _ name: String, bytes: Int) {
        FileManager.default.createFile(atPath: layout.folder(s).appendingPathComponent(name).path, contents: Data(count: bytes))
    }

    static func image(width: Int = 1920, height: Int = 1080, shade: CGFloat = 0.3) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: shade, green: 0.4, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: width / 4, y: height / 10, width: width / 2, height: height / 14))
        return ctx.makeImage()!
    }

    static func noise(width: Int = 1920, height: Int = 1080, seed: UInt64) -> CGImage {
        var x = seed &* 0x9E3779B97F4A7C15
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            x ^= x << 13; x ^= x >> 7; x ^= x << 17
            bytes[i] = UInt8(truncatingIfNeeded: x)
            bytes[i + 1] = UInt8(truncatingIfNeeded: x >> 8)
            bytes[i + 2] = UInt8(truncatingIfNeeded: x >> 16)
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    // MARK: İndeks ve halka tampon

    func testNameParsingAndOverlap() {
        XCTAssertEqual(DebugRecordLayout.parseName("1700000000000.mov")?.start, 1_700_000_000_000)
        XCTAssertNil(DebugRecordLayout.parseName("1700000000000.mov")?.end)
        XCTAssertEqual(DebugRecordLayout.parseName("100-250.jsonl")?.end, 250)
        XCTAssertNil(DebugRecordLayout.parseName("250-100.jsonl"), "bitiş başlangıçtan önce olamaz")
        XCTAssertNil(DebugRecordLayout.parseName("latest.jpg"))
        put(.ps5, "1000-2000.mov", bytes: 10)
        put(.tv, "1500.png", bytes: 10)
        put(.gunluk, "3000-4000.jsonl", bytes: 10)
        put(.ps5, "notes.txt", bytes: 10)
        let all = DebugRecordIndex.scan(layout)
        XCTAssertEqual(all.map(\.url.lastPathComponent), ["1000-2000.mov", "1500.png", "3000-4000.jsonl"])
        XCTAssertEqual(all[1].endMs, 1500, "anlık dosyanın bitişi kendi zamanı")
        XCTAssertEqual(DebugRecordIndex.files(layout, fromMs: 1600, toMs: 2500).map(\.url.lastPathComponent), ["1000-2000.mov"])
        XCTAssertEqual(DebugRecordIndex.files(layout, fromMs: 2001, toMs: 2999).count, 0)
    }

    func testOpenSegmentEndIsModificationTime() throws {
        put(.mac, "1000.mov", bytes: 5)
        let url = layout.folder(.mac).appendingPathComponent("1000.mov")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 9)], ofItemAtPath: url.path)
        let f = try XCTUnwrap(DebugRecordIndex.scan(layout).first)
        XCTAssertTrue(f.isOpen)
        XCTAssertEqual(f.endMs, 9000)
    }

    func testRingDeletesOldestUntilUnderLimitAndKeepsProtectedAndOutput() {
        put(.ps5, "1000-1100.mov", bytes: 400)
        put(.gunluk, "1050-1200.jsonl", bytes: 100)
        put(.tv, "2000.png", bytes: 300)
        put(.ps5, "3000.mov", bytes: 400) // yazılmakta
        // Sınıra sayılmayanlar
        try? FileManager.default.createDirectory(at: layout.outputFolder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: layout.outputFolder.appendingPathComponent("eski.png").path, contents: Data(count: 5000))
        FileManager.default.createFile(atPath: layout.measureFile.path, contents: Data(count: 5000))

        let plan = DebugRing.toDelete(DebugRecordIndex.scan(layout), limit: 600, protected: ["3000.mov"])
        XCTAssertEqual(plan.map(\.url.lastPathComponent), ["1000-1100.mov", "1050-1200.jsonl", "2000.png"])
        let freed = DebugRing.prune(layout, limit: 800, protected: ["3000.mov"])
        XCTAssertEqual(freed, 400, "800'e inince durur (sınıra eşit kalabilir)")
        let left = DebugRecordIndex.scan(layout).map(\.url.lastPathComponent)
        XCTAssertEqual(left, ["1050-1200.jsonl", "2000.png", "3000.mov"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.outputFolder.appendingPathComponent("eski.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.measureFile.path))
        XCTAssertEqual(DebugRing.prune(layout, limit: 10_000), 0, "sınırın altında hiçbir şey silinmez")
    }

    // MARK: Aralık

    func testRangeParsing() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 16, minute: 20))!
        let five = try XCTUnwrap(DebugRange.parse(["son", "5dk"], now: now, calendar: cal))
        XCTAssertEqual(five.to.timeIntervalSince(five.from), 300)
        XCTAssertEqual(five.to, now)
        XCTAssertEqual(DebugRange.parse(["son", "30sn"], now: now, calendar: cal).map { $0.to.timeIntervalSince($0.from) }, 30)
        XCTAssertEqual(DebugRange.parse(["son", "2", "sa"], now: now, calendar: cal).map { $0.to.timeIntervalSince($0.from) }, 7200)
        let r = try XCTUnwrap(DebugRange.parse(["16:05-16:10"], now: now, calendar: cal))
        XCTAssertEqual(cal.component(.minute, from: r.from), 5)
        XCTAssertEqual(r.to.timeIntervalSince(r.from), 300)
        XCTAssertEqual(cal.component(.day, from: r.from), 22)
        let sec = try XCTUnwrap(DebugRange.parse(["16:05:30-16:06"], now: now, calendar: cal))
        XCTAssertEqual(sec.to.timeIntervalSince(sec.from), 30)
        let night = try XCTUnwrap(DebugRange.parse(["23:50-00:10"], now: now, calendar: cal))
        XCTAssertEqual(night.to.timeIntervalSince(night.from), 1200, "gece yarısını geçen aralık")
        let future = try XCTUnwrap(DebugRange.parse(["18:00-18:05"], now: now, calendar: cal))
        XCTAssertEqual(cal.component(.day, from: future.from), 21, "gelecekteki saat dün sayılır")
        XCTAssertNil(DebugRange.parse(["son", "5yıl"], now: now, calendar: cal))
        XCTAssertNil(DebugRange.parse(["25:00-26:00"], now: now, calendar: cal))
        XCTAssertNil(DebugRange.parse(["merhaba"], now: now, calendar: cal))
    }

    // MARK: Özet (gerçek günlük biçimleriyle)

    func testSummaryFromRealLogFormats() {
        var lines: [String] = []
        lines.append(LineLogText.read(id: 1, text: "Hello there", kind: .new))
        lines.append(LineLogText.translated(id: 1, origin: "paket", ms: 10, text: "Merhaba"))
        lines.append(LineLogText.shown(id: 1, tvCount: 1, computer: false))
        lines.append(LineLogText.read(id: 2, text: "Second", kind: .new))
        lines.append(LineLogText.read(id: 2, text: "Second line", kind: .updated))
        lines.append(LineLogText.translated(id: 2, origin: "gemini", ms: 400, text: "İkinci"))
        lines.append(LineLogText.dropped(id: 2, reason: .late))
        lines.append(LineLogText.read(id: 3, text: "Third", kind: .new))
        lines.append(LineLogText.failed(id: 3, ms: 900, problem: nil))
        lines.append(LineLogText.read(id: 4, text: "Fourth", kind: .new))
        lines.append(LineLogText.translated(id: 4, origin: "gemini", ms: 600, text: "Dördüncü"))
        lines.append(LineLogText.shown(id: 4, tvCount: 1, computer: true))
        lines.append(LineLogText.read(id: 5, text: "Fifth", kind: .new))
        lines.append(LineLogText.read(id: 1, text: "Hello there", kind: .restored))
        lines.append(TVLinkText.logLine(DisplayLinkEvent(kind: .connected, route: .outgoing, host: "192.168.0.110", connectionID: "a")))
        lines.append(TVLinkText.logLine(DisplayLinkEvent(kind: .disconnected, route: .outgoing, host: "192.168.0.110", connectionID: "a",
                                                         duration: 42, reason: .peerClosed)))
        lines.append("PS5: bağlanıyor")
        lines.append("durum: PS5 ps5(NinoMacKit.SourceStatus.ConsoleLink.streaming)")
        lines.append("Oyun ekrandan tanındı: Test Oyunu")
        let log = lines.enumerated().map { DebugLogLine(t: Int64(1000 + $0.offset), k: "altyazi", m: $0.element) }
        let msgs = [DebugTVMessage.line(t: 1001, tv: 1, json: "{\"type\":\"show\",\"id\":1}"),
                    DebugTVMessage.line(t: 1002, tv: 1, json: "{\"type\":\"clear\"}")].compactMap(DebugTVMessage.parse)
        let s = DebugSummary.compute(lines: log, messages: msgs)
        XCTAssertEqual(s.readLines, 5)
        XCTAssertEqual(s.readUpdates, 1)
        XCTAssertEqual(s.restored, 1)
        XCTAssertEqual(s.shown, 2)
        XCTAssertEqual(s.translationMs["paket"], [10])
        XCTAssertEqual(s.translationMs["gemini"], [400, 600])
        XCTAssertEqual(s.averageMs, 337)
        XCTAssertEqual(s.p95Ms, 600)
        XCTAssertEqual(s.translationFailed, 1)
        XCTAssertEqual(s.dropped, ["satır ekrandan kalktı, çeviri geç kaldı": 1])
        XCTAssertEqual(s.missed["satır ekrandan kalktı, çeviri geç kaldı"], 1)
        XCTAssertEqual(s.missed["çeviri başarısız"], 1)
        XCTAssertEqual(s.missed.values.reduce(0, +), 3)
        XCTAssertEqual(s.tvConnects, 1)
        XCTAssertEqual(s.tvDrops.count, 1)
        XCTAssertEqual(s.ps5.count, 2)
        XCTAssertEqual(s.games.count, 1)
        XCTAssertEqual(s.tvMessages, ["show": 1, "clear": 1])
        let item = ScreenItem(box: NinoBox(left: 0.1, top: 0.1, right: 0.3, bottom: 0.2), text: "Harita")
        let screen = NinoEvent.screen(ScreenPayload(items: [item], durationMs: 0)).jsonString
        let other = NinoEvent.screen(ScreenPayload(items: [ScreenItem(box: item.box, text: "Başka")], durationMs: 0)).jsonString
        let seq = [screen, screen, screen, NinoEvent.screenClear.jsonString, screen, other, other]
        let sm = seq.enumerated().compactMap { DebugTVMessage.parse(DebugTVMessage.line(t: Int64($0.offset), tv: 1, json: $0.element)) }
        let ss = DebugSummary.compute(lines: [], messages: sm)
        XCTAssertEqual(ss.screenRepeats, 3, "aynı liste art arda: 2 + 1; clear'dan sonraki ilk sayılmaz")
        XCTAssertEqual(ss.tvMessages["screen-clear"], 1)
        XCTAssertTrue(ss.markdown(from: Date(), to: Date(), counts: .init(), measurement: nil)
            .contains("screen 6, screen-clear 1, değişmeyen liste yeniden gönderimi 3"))
        let md = s.markdown(from: Date(timeIntervalSince1970: 1), to: Date(timeIntervalSince1970: 2), counts: .init(), measurement: DebugMeasurement())
        XCTAssertTrue(md.contains("ortalama 337 ms, p95 600 ms"))
        XCTAssertTrue(md.contains("Okunan satır: 5"))
        XCTAssertTrue(md.contains("TV koptu"))
    }

    func testPercentile() {
        XCTAssertNil(DebugSummary.percentile([], 0.95))
        XCTAssertEqual(DebugSummary.percentile([5], 0.95), 5)
        XCTAssertEqual(DebugSummary.percentile(Array(1...100), 0.95), 95)
        XCTAssertEqual(DebugSummary.percentile(Array(1...20), 0.95), 19)
    }

    // MARK: Bütçe (sahte saat)

    func testBudgetSlowsDownWhenOverAndRecoversWhenCalm() {
        var b = DebugBudget()
        XCTAssertFalse(b.tick(now: 0, memoryBytes: 0))
        b.add(work: 0.5) // 5 sn'de 0.5 sn = %10
        XCTAssertTrue(b.tick(now: 5, memoryBytes: 0))
        XCTAssertEqual(b.scale, 2)
        b.add(work: 0.5)
        b.tick(now: 10, memoryBytes: 0)
        XCTAssertEqual(b.scale, 4)
        for i in 0..<3 {
            b.add(work: 0.01)
            b.tick(now: 15 + Double(i) * 5, memoryBytes: 0)
        }
        XCTAssertEqual(b.scale, 2, "üç sakin pencereden sonra yarıya")
        b.add(work: 0)
        b.tick(now: 30, memoryBytes: 200 * 1024 * 1024)
        XCTAssertEqual(b.scale, 4, "bellek aşımı da yavaşlatır")
        for _ in 0..<10 { b.add(work: 10); b.tick(now: 30 + 5 * Double(b.slowDowns + 1), memoryBytes: 0) }
        XCTAssertLessThanOrEqual(b.scale, 8, "en çok 8×")
        XCTAssertFalse(b.tick(now: 1000.1, memoryBytes: 0) && b.scale < 1)
        XCTAssertGreaterThan(b.peakFraction, 0.09)
    }

    func testBudgetDoesNotDecideBeforeWindow() {
        var b = DebugBudget()
        b.tick(now: 0, memoryBytes: 0)
        b.add(work: 4)
        XCTAssertFalse(b.tick(now: 4.9, memoryBytes: 0))
        XCTAssertEqual(b.scale, 1)
    }

    // MARK: Kurallar

    func testRules() {
        XCTAssertFalse(DebugRecordingRules.isEnabled(flavor: .release, adminFlag: false))
        XCTAssertTrue(DebugRecordingRules.isEnabled(flavor: .release, adminFlag: true))
        XCTAssertTrue(DebugRecordingRules.isEnabled(flavor: .development, adminFlag: false))
        XCTAssertFalse(DebugRecordingRules.isEnabled(flavor: .testing, adminFlag: true))
        XCTAssertTrue(DebugRecordingRules.isEventLine(LineLogText.read(id: 3, text: "x", kind: .new)))
        XCTAssertTrue(DebugRecordingRules.isEventLine("TV koptu: adres 1.2.3.4"))
        XCTAssertFalse(DebugRecordingRules.isEventLine(LineLogText.translated(id: 3, origin: "paket", ms: 1, text: "x")))
        XCTAssertTrue(DebugRecordingRules.shouldShootTV(now: 100, last: nil, blockedUntil: nil, disabled: false,
                                                       isAndroidTV: true, translating: true, scale: 1))
        XCTAssertFalse(DebugRecordingRules.shouldShootTV(now: 100, last: 50, blockedUntil: nil, disabled: false,
                                                        isAndroidTV: true, translating: true, scale: 1))
        XCTAssertFalse(DebugRecordingRules.shouldShootTV(now: 100, last: nil, blockedUntil: 200, disabled: false,
                                                        isAndroidTV: true, translating: true, scale: 1))
        XCTAssertFalse(DebugRecordingRules.shouldShootTV(now: 100, last: nil, blockedUntil: nil, disabled: false,
                                                        isAndroidTV: false, translating: true, scale: 1), "LG/Samsung: yok")
        XCTAssertFalse(DebugRecordingRules.shouldShootTV(now: 100, last: nil, blockedUntil: nil, disabled: true,
                                                        isAndroidTV: true, translating: true, scale: 1))
        XCTAssertFalse(DebugRecordingRules.shouldShootTV(now: 100, last: nil, blockedUntil: nil, disabled: false,
                                                        isAndroidTV: true, translating: false, scale: 1))
        XCTAssertTrue(DebugImageIO.isPNG(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0])))
        XCTAssertFalse(DebugImageIO.isPNG(Data("error: closed".utf8)))
    }

    func testTVShooterWithoutKeyDisablesSilently() async {
        final class NeverConnector: ADBConnecting, @unchecked Sendable {
            var calls = 0
            func connect(host: String, port: UInt16, timeout: TimeInterval) async throws -> ADBByteStream {
                calls += 1
                throw ADBError.unreachable(host)
            }
        }
        let c = NeverConnector()
        let shooter = DebugTVShooter(keyFile: root.appendingPathComponent("adbkey"), connector: c)
        XCTAssertTrue(shooter.isDue(now: 0, isAndroidTV: true, translating: true, scale: 1))
        let png = await shooter.shoot(host: "192.0.2.1")
        XCTAssertNil(png)
        XCTAssertEqual(c.calls, 0, "anahtar yoksa TV'ye hiç bağlanılmaz (yeni anahtar üretilmez, onay kutusu çıkmaz)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("adbkey").path))
        XCTAssertFalse(shooter.isDue(now: 1000, isAndroidTV: true, translating: true, scale: 1))
    }

    // MARK: Video parçası ve çıkarma

    func testOpenSegmentIsReadableAndExportExtractsRange() throws {
        let seg = DebugVideoSegment(layout: layout, stream: .ps5,
                                    settings: .init(width: 320, height: 180, bitRate: 300_000, segmentLength: 3600))
        let start: Int64 = 1_800_000_000_000
        let img = Self.image(width: 640, height: 360)
        for i in 0..<12 {
            XCTAssertTrue(seg.append(atMs: start + Int64(i) * 500) { ctx, canvas in ctx.draw(img, in: CGRect(origin: .zero, size: canvas)) })
        }
        // Kapatmadan: film parçacıkları sayesinde yazılmakta olan parça da okunur.
        Thread.sleep(forTimeInterval: 1.5)
        let open = try XCTUnwrap(DebugRecordIndex.scan(layout, streams: [.ps5]).first)
        XCTAssertTrue(open.isOpen)
        XCTAssertGreaterThanOrEqual(DebugExport.frameTimes(open.url).count, 6, "açık parça okunabilmeli")
        seg.close()
        let closed = try XCTUnwrap(DebugRecordIndex.scan(layout, streams: [.ps5]).first)
        XCTAssertEqual(closed.url.lastPathComponent, "\(start)-\(start + 5500).mov")
        XCTAssertEqual(DebugExport.frameTimes(closed.url), (0..<12).map { Int64($0) * 500 })

        let journal = DebugJournal(layout: layout, stream: .gunluk)
        journal.append("{\"t\":\(start + 1000),\"k\":\"altyazi\",\"m\":\(DebugJournal.quote(LineLogText.read(id: 1, text: "Hi \"you\"", kind: .new)))}", atMs: start + 1000)
        journal.append("{\"t\":\(start + 9000),\"k\":\"altyazi\",\"m\":\"aralık dışı\"}", atMs: start + 9000)
        let msgs = DebugJournal(layout: layout, stream: .mesaj)
        msgs.append(DebugTVMessage.line(t: start + 1200, tv: 1, json: "{\"type\":\"show\",\"text\":\"Merhaba\"}"), atMs: start + 1200)
        FileManager.default.createFile(atPath: layout.folder(.tv).appendingPathComponent("\(start + 1500).png").path,
                                       contents: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        DebugImageIO.write(img, to: layout.folder(.olay).appendingPathComponent("\(start + 2000).jpg"), type: .jpeg, quality: 0.5)

        let out = root.appendingPathComponent("cikti-test")
        var export = DebugExport(layout: layout)
        export.timeZone = TimeZone(identifier: "UTC")!
        let r = try export.run(from: Date(timeIntervalSince1970: TimeInterval(start + 1000) / 1000),
                               to: Date(timeIntervalSince1970: TimeInterval(start + 3000) / 1000), into: out)
        XCTAssertEqual(r.counts.ps5Frames, 5, "1000…3000 ms arası 5 kare")
        let pngs = try FileManager.default.contentsOfDirectory(atPath: out.appendingPathComponent("ps5").path).sorted()
        XCTAssertEqual(pngs.count, 5)
        XCTAssertEqual(pngs.first, "ps5-08-00-01.000.png")
        XCTAssertEqual(r.counts.logLines, 1)
        XCTAssertEqual(r.counts.tvMessages, 1)
        XCTAssertEqual(r.counts.tvShots, 1)
        XCTAssertEqual(r.counts.eventFrames, 1)
        XCTAssertEqual(r.summary.readLines, 1)
        let log = try String(contentsOf: out.appendingPathComponent("gunluk.txt"), encoding: .utf8)
        XCTAssertTrue(log.contains("#1 okundu \"Hi \"you\"\""), log)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.appendingPathComponent("ozet.md").path))
    }

    // MARK: Kayıtçı (sahte saat)

    func testRecorderRateLimitsFramesAndWritesStreams() throws {
        final class FakeNow: @unchecked Sendable {
            let lock = NSLock()
            var t: TimeInterval = 1_800_000_000
            func get() -> Date { lock.withLock { Date(timeIntervalSince1970: t) } }
            func add(_ d: TimeInterval) { lock.withLock { t += d } }
        }
        let clock = FakeNow()
        let rec = DebugRecorder(layout: layout, limit: 1_000_000_000, now: { clock.get() }) {
            DebugAnnotation(readingArea: GameReading.Box(left: 0.1, top: 0.7, right: 0.9, bottom: 0.95),
                            subtitleBox: GameReading.Box(left: 0.3, top: 0.8, right: 0.7, bottom: 0.9), read: "Hi", translation: "Selam")
        }
        let img = Self.image(width: 640, height: 360)
        // 10 kare/sn, 3 sn → hedef 2 kare/sn: en çok 6–7 kare
        for _ in 0..<30 {
            rec.offerPS5(img)
            clock.add(0.1)
            rec.drain()
        }
        rec.logLine(LineLogText.read(id: 9, text: "Hi", kind: .new), kind: "altyazi", at: clock.get())
        clock.add(0.6)
        rec.offerPS5(img) // olay karesi
        rec.drain()
        rec.tvMessage(NinoMessage.clear(id: 3).jsonString, tvCount: 2)
        rec.drain()
        rec.stop()
        let m = rec.currentMeasurement
        XCTAssertGreaterThanOrEqual(m.ps5Frames, 5)
        XCTAssertLessThanOrEqual(m.ps5Frames, 8)
        XCTAssertEqual(m.eventFrames, 1)
        XCTAssertEqual(m.tvMessages, 1)
        let files = DebugRecordIndex.scan(layout)
        XCTAssertEqual(files.filter { $0.stream == .ps5 }.count, 1)
        XCTAssertFalse(files.contains { $0.isOpen }, "durunca bütün parçalar kapanır")
        let msgs = DebugExport.readMessages(files.filter { $0.stream == .mesaj })
        XCTAssertEqual(msgs.first?.tv, 2)
        XCTAssertEqual(msgs.first?.type, "clear")
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.measureFile.path))
    }

    func testRecorderPrunesWithSmallLimit() {
        put(.ps5, "1000-2000.mov", bytes: 3000)
        put(.ps5, "3000-4000.mov", bytes: 3000)
        let rec = DebugRecorder(layout: layout, limit: 4000) { DebugAnnotation() }
        rec.pruneNow()
        XCTAssertEqual(DebugRecordIndex.scan(layout).map(\.url.lastPathComponent), ["3000-4000.mov"])
        XCTAssertEqual(rec.currentMeasurement.ringTotal, 3000)
    }

    func testHandshakeWithoutOfferingKeyNeverPromptsTheTV() async throws {
        let device = FakeADBDevice()
        let stream = try await FakeADBConnector(device).connect(host: "tv", port: 5555, timeout: 1)
        let adb = ADBConnection(stream: stream)
        let asked = LockedBox(0)
        do {
            _ = try await adb.handshake(key: try ADBKey.generate(), offerKey: false, onApprovalNeeded: { asked.mutate { $0 += 1 } })
            XCTFail("tanınmayan anahtarla bağlanmamalı")
        } catch let e as ADBError {
            XCTAssertEqual(e, .notApproved)
        }
        XCTAssertEqual(asked.value, 0)
        XCTAssertEqual(device.approvalPrompts, 0, "TV'de onay kutusu çıkmaz")
        XCTAssertEqual(device.knownKeys, [])
    }

    func testTVShooterWithUnknownKeyStopsWithoutPrompt() async throws {
        let device = FakeADBDevice()
        let connector = FakeADBConnector(device)
        let keyFile = root.appendingPathComponent("adbkey")
        try ADBKey.generate().pem().write(to: keyFile, atomically: true, encoding: .utf8)
        let shooter = DebugTVShooter(keyFile: keyFile, connector: connector)
        XCTAssertTrue(shooter.isDue(now: 0, isAndroidTV: true, translating: true, scale: 1))
        let png = await shooter.shoot(host: "tv")
        XCTAssertNil(png)
        XCTAssertEqual(device.approvalPrompts, 0)
        XCTAssertFalse(shooter.isDue(now: 10_000, isAndroidTV: true, translating: true, scale: 1), "bu oturumda bir daha denenmez")
    }

    func testWindowPickIgnoresOcclusionAndHiddenHelpers() {
        func c(_ visible: Bool = true, mini: Bool = false, panel: Bool = false, off: Bool = false, main: Bool = false,
               area: CGFloat = 100) -> WindowCandidate {
            WindowCandidate(visible: visible, miniaturized: mini, panel: panel, hasContent: true, offscreen: off,
                            normalLevel: true, main: main, area: area)
        }
        XCTAssertEqual(WindowCandidate.pick([c(area: 10), c(area: 50)]), 1, "en büyük")
        XCTAssertEqual(WindowCandidate.pick([c(area: 50), c(main: true, area: 10)]), 1, "ana pencere önce")
        XCTAssertEqual(WindowCandidate.pick([c(off: true, area: 5000), c(panel: true, area: 900), c(area: 1)]), 2,
                       "gizli TV sayfası ve paneller alınmaz")
        XCTAssertEqual(WindowCandidate.pick([c(false, mini: true)]), 0, "küçültülmüş pencere de çizilir")
        XCTAssertNil(WindowCandidate.pick([c(false)]), "kapalı pencere yok")
    }

    func testBusyFramesAreCountedOnlyWhenDue() {
        let rec = DebugRecorder(layout: layout, now: { Date(timeIntervalSince1970: 1_800_000_000) }) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            return DebugAnnotation()
        }
        let img = Self.image(width: 64, height: 36)
        for _ in 0..<20 { rec.offerPS5(img) } // aynı an: ilk alınır, gerisinin zamanı gelmemiş
        rec.drain()
        rec.stop()
        XCTAssertEqual(rec.currentMeasurement.ps5Busy, 0, "zamanı gelmemiş kareler yetişememe sayılmaz")
        XCTAssertEqual(rec.currentMeasurement.ps5Frames, 1)
    }

    // MARK: Hub dinleyicisi

    func testHubTapRecordsWhatTVsGetAndTracksBoxes() async throws {
        let rec = DebugRecorder(layout: layout) { DebugAnnotation() }
        let tap = DebugHubTap()
        tap.recorder = rec
        tap.tvCount = { 1 }
        let hub = DisplayHub()
        await hub.add(tap, key: "debug-kayit")
        let box = NinoBox(left: 0.2, top: 0.8, right: 0.8, bottom: 0.9)
        try await hub.show(ShowPayload(id: 7, text: "Merhaba", durationMs: 0, box: box))
        XCTAssertEqual(tap.boxes, [box])
        try await hub.clear(id: 7)
        XCTAssertEqual(tap.boxes, [])
        await hub.setSubtitlesOnTV(false)
        try await hub.show(ShowPayload(id: 8, text: "Yalnız bilgisayarda", durationMs: 0))
        rec.stop()
        let msgs = DebugExport.readMessages(DebugRecordIndex.scan(layout, streams: [.mesaj]))
        let types = msgs.map(\.type)
        XCTAssertEqual(types.first, "show")
        XCTAssertTrue(types.contains("clear"))
        XCTAssertFalse(msgs.contains { $0.line.contains("Yalnız bilgisayarda") }, "TV'ye gitmeyen altyazı kayda da girmez")
        XCTAssertTrue(msgs[0].line.contains("Merhaba"))
    }

    // MARK: Admin olmadan kapalı

    @MainActor
    func testNothingRunsWithoutAdminMode() throws {
        let suite = "nino-debugkayit-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let logs = root.appendingPathComponent("logs")
        let env = LiveEngineEnvironment(
            identity: AppIdentity(flavor: .testing, defaultsDomain: suite, keychainService: "test", folderName: "test"),
            folder: DataFolder(support: root.appendingPathComponent("support"), logs: logs), settingsStore: SettingsStore(defaults: defaults),
            vault: MemoryVault(), ports: .ephemeral, appVersion: "4.5.0", poolBaseURL: nil, packsBaseURL: nil, poolTransport: nil,
            providerTransport: URLSession.shared, deviceProvider: { nil }, textReader: SessionOverlaysTests.FailingReader(fail: false),
            clock: GameReading.SystemClock(), checksTranslatorReadiness: false)
        let engine = LiveEngine(state: AppState(), environment: env)
        XCTAssertNil(DebugRecording.makeIfEnabled(engine: engine, adminMode: false))
        XCTAssertNil(engine.subtitleLog.mirror)
        XCTAssertFalse(FileManager.default.fileExists(atPath: logs.appendingPathComponent(DebugRecordLayout.folderName).path))
        let support = NinoAppSupport(engine: engine, autoUpdater: nil, globalHotKeys: false)
        XCTAssertFalse(support.adminMode)
        XCTAssertNil(support.recording)
        XCTAssertFalse(FileManager.default.fileExists(atPath: logs.appendingPathComponent(DebugRecordLayout.folderName).path))
        _ = env
    }

    /// Uygulamadaki bağlantılar: günlük aynası, hub dinleyicisi, başlangıç durum satırı.
    @MainActor
    func testLiveWiringRecordsLogLinesAndTVMessages() async throws {
        let suite = "nino-debugkayit-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let logs = root.appendingPathComponent("logs")
        let env = LiveEngineEnvironment(
            identity: AppIdentity(flavor: .testing, defaultsDomain: suite, keychainService: "test", folderName: "test"),
            folder: DataFolder(support: root.appendingPathComponent("support"), logs: logs), settingsStore: SettingsStore(defaults: defaults),
            vault: MemoryVault(), ports: .ephemeral, appVersion: "4.5.0", poolBaseURL: nil, packsBaseURL: nil, poolTransport: nil,
            providerTransport: URLSession.shared, deviceProvider: { nil }, textReader: SessionOverlaysTests.FailingReader(fail: false),
            clock: GameReading.SystemClock(), checksTranslatorReadiness: false)
        let engine = LiveEngine(state: AppState(), environment: env)
        let recording = try XCTUnwrap(DebugRecording.makeIfEnabled(engine: engine, adminMode: true))
        let deadline = Date().addingTimeInterval(5)
        while await !engine.links.hub.keys.contains("debug-kayit"), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let keys = await engine.links.hub.keys
        XCTAssertTrue(keys.contains("debug-kayit"))
        engine.subtitleLog.write(LineLogText.read(id: 1, text: "Hello", kind: .new))
        engine.remotePlayLog.write("rp satırı")
        try await engine.links.output.show(ShowPayload(id: 1, text: "Merhaba", durationMs: 0))
        recording.tick()
        recording.recorder.stop()
        engine.subtitleLog.flush()
        let kayit = DebugRecordLayout(logsFolder: logs)
        let lines = DebugExport.readLog(DebugRecordIndex.scan(kayit, streams: [.gunluk]))
        XCTAssertTrue(lines.contains { $0.k == "altyazi" && $0.m.hasPrefix("#1 okundu") })
        XCTAssertTrue(lines.contains { $0.k == "remoteplay" && $0.m == "rp satırı" })
        XCTAssertTrue(lines.contains { $0.k == "durum" && $0.m.hasPrefix("hata ayıklama kaydı başladı") })
        XCTAssertTrue(lines.contains { $0.k == "durum" && $0.m.hasPrefix("durum: PS5") })
        let msgs = DebugExport.readMessages(DebugRecordIndex.scan(kayit, streams: [.mesaj]))
        XCTAssertTrue(msgs.contains { $0.type == "show" && $0.line.contains("Merhaba") })
        // Aynı satır altyazi.log'da da (ayna günlüğü değiştirmez).
        let file = try String(contentsOf: env.folder.subtitleLog, encoding: .utf8)
        XCTAssertTrue(file.contains("#1 okundu"))
        engine.subtitleLog.mirror = nil
        engine.remotePlayLog.mirror = nil
    }

    /// Ana pencere kapalıyken (kapatıldı ya da kapalıyken çıkılıp açılışta geri gelmedi; NSApp.windows'ta hiç yok) kayıt
    /// boş kalmaz: ana pencerenin içeriği ekran dışında çizilir ve günlüğe kaynak bir kez yazılır.
    @MainActor
    func testClosedMainWindowIsDrawnOffscreen() throws {
        let suite = "nino-debugkayit-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let logs = root.appendingPathComponent("logs")
        let env = LiveEngineEnvironment(
            identity: AppIdentity(flavor: .testing, defaultsDomain: suite, keychainService: "test", folderName: "test"),
            folder: DataFolder(support: root.appendingPathComponent("support"), logs: logs), settingsStore: SettingsStore(defaults: defaults),
            vault: MemoryVault(), ports: .ephemeral, appVersion: "4.5.0", poolBaseURL: nil, packsBaseURL: nil, poolTransport: nil,
            providerTransport: URLSession.shared, deviceProvider: { nil }, textReader: SessionOverlaysTests.FailingReader(fail: false),
            clock: GameReading.SystemClock(), checksTranslatorReadiness: false)
        let engine = LiveEngine(state: AppState(), environment: env)
        let recording = try XCTUnwrap(DebugRecording.makeIfEnabled(engine: engine, adminMode: true))
        defer {
            engine.subtitleLog.mirror = nil
            engine.remotePlayLog.mirror = nil
        }
        XCTAssertNil(DebugRecording.windowImage(), "testte gerçek pencere yok (eski hâlde burada kayıt boş kalıyordu)")
        let ui = HomeUIState()
        ui.splashFinished = true
        recording.offscreenContent = { AnyView(MainWindowView(state: engine.state, ui: ui)) }
        recording.tick()
        recording.recorder.stop()
        let m = recording.recorder.currentMeasurement
        XCTAssertEqual(m.macFrames, 1)
        XCTAssertEqual(m.macMissing, 0)
        let lines = DebugExport.readLog(DebugRecordIndex.scan(DebugRecordLayout(logsFolder: logs), streams: [.gunluk]))
        XCTAssertTrue(lines.contains { $0.k == "durum" && $0.m.hasPrefix("pencere: ana pencere kapalı") })
    }

    /// Ekran dışı çizim gerçek içerik verir (tek renk boş kare değil), ana pencere boyunda.
    @MainActor
    func testOffscreenImageIsNotBlank() throws {
        let ui = HomeUIState()
        ui.splashFinished = true
        let image = try XCTUnwrap(DebugRecording.offscreenImage(AnyView(MainWindowView(state: AppState(), ui: ui))))
        XCTAssertEqual(image.width, Int(NinoSize.windowWidth))
        XCTAssertEqual(image.height, Int(NinoSize.windowHeight))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64 * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        let data = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        var colors = Set<UInt32>()
        for i in stride(from: 0, to: 64 * 64 * 4, by: 4) {
            colors.insert(UInt32(data[i]) << 16 | UInt32(data[i + 1]) << 8 | UInt32(data[i + 2]))
        }
        XCTAssertGreaterThan(colors.count, 20, "boş kare")
    }

    // MARK: Kıyas (gerçek ölçüm; yapay 1080p kareler)

    func testBenchmarkRecorderCost() throws {
        let seg = DebugVideoSegment(layout: layout, stream: .ps5, settings: DebugRecordingRules.ps5Video)
        // En kötü durum: her kare gürültü (kodlayıcı için en zor; disk hızı bit hızı sınırına dayanır).
        let frames = (0..<6).map { Self.noise(seed: UInt64($0 + 1)) }
        let annotation = DebugAnnotation(readingArea: GameReading.Box(left: 0.1, top: 0.7, right: 0.9, bottom: 0.95),
                                         subtitleBox: GameReading.Box(left: 0.3, top: 0.8, right: 0.7, bottom: 0.9),
                                         read: "Follow the river to the bridge.", translation: "Nehri köprüye kadar izle.")
        let n = 60
        let mem0 = DebugMeasure.footprint()
        let proc0 = DebugMeasure.processCPU()
        let wall0 = Date()
        var thread: TimeInterval = 0
        for i in 0..<n {
            let img = frames[i % frames.count]
            thread += DebugMeasure.cpu {
                seg.append(atMs: 1_800_000_000_000 + Int64(i) * 500) { ctx, canvas in
                    annotation.draw(img, in: ctx, rect: DebugVideoSegment.fit(CGSize(width: img.width, height: img.height), in: canvas),
                                    fontSize: 15)
                }
            }
        }
        seg.close()
        let wall = Date().timeIntervalSince(wall0)
        // Olay karesi: tam boy çizim + JPEG.
        var eventCPU: TimeInterval = 0
        for i in 0..<5 {
            let img = frames[i]
            eventCPU += DebugMeasure.cpu {
                let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
                annotation.draw(img, in: ctx, rect: CGRect(x: 0, y: 0, width: img.width, height: img.height), fontSize: 30)
                DebugImageIO.write(ctx.makeImage()!, to: layout.folder(.olay).appendingPathComponent("\(i + 1).jpg"), type: .jpeg,
                                   quality: DebugRecordingRules.eventQuality)
            }
        }
        let eventBytes = DebugRecordIndex.scan(layout, streams: [.olay]).reduce(Int64(0)) { $0 + $1.bytes } / 5
        let proc = DebugMeasure.processCPU() - proc0
        let mem = DebugMeasure.footprint() - mem0
        let bytes = DebugRecordIndex.scan(layout, streams: [.ps5]).reduce(Int64(0)) { $0 + $1.bytes }
        let perFrameMs = thread / Double(n) * 1000
        // 2 kare/sn'de kayıtçının CPU oranı = kare başı süre × 2.
        let cpuAt2fps = thread / Double(n) * 2
        let mbPerMinute = Double(bytes) / Double(n) * 2 * 60 / 1_048_576
        print(String(format: "KIYAS debug-kayit: kare başı %.2f ms (iş parçacığı), süreç CPU %.2f ms/kare, 2 fps'de %%%.2f CPU, " +
                     "bellek farkı %.1f MB, disk %.2f MB/dk, %d kare %.2f sn",
                     perFrameMs, proc / Double(n) * 1000, cpuAt2fps * 100, Double(mem) / 1_048_576, mbPerMinute, n, wall))
        print(String(format: "KIYAS olay karesi: %.1f ms, %d KB", eventCPU / 5 * 1000, eventBytes / 1024))
        XCTAssertLessThan(cpuAt2fps, 0.05, "2 fps'de %5 CPU bütçesi")
        XCTAssertLessThan(mem, 150 * 1024 * 1024)
    }
}
