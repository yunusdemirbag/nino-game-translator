// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import CoreText
import Foundation
import XCTest
@testable import NinoCore

final class NinoSetupTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nino-setup-\(UUID().uuidString)")
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private let box = NormalizedRect(x: 0.3, y: 0.8, width: 0.4, height: 0.05)

    private func feed(_ e: NinoEngine, _ text: String) async {
        for _ in 0..<3 { await e.process(lines: [RecognizedLine(text: text, confidence: 0.9, box: box)]) }
        await e.waitUntilIdle()
    }

    func testCachePersistsAcrossEnginesAndPackIsUsed() async throws {
        let directories = NinoDirectories(root: dir)
        try directories.prepare()
        try TranslationPack(game: .init(id: "ornek-oyun"), lines: [.init(source: "Bye.", target: "Hoşça kal.")])
            .write(to: directories.packsDirectory.appendingPathComponent("o.ninopack.json"))

        var settings = NinoSettings()
        settings.translation.selectedGameID = "ornek-oyun"
        settings.translation.providers = [.init(name: "http-1", urlTemplate: "http://127.0.0.1:9/t?q={text}", method: "GET",
                                                headers: [:], responsePath: ["t"])]
        final class Counter: @unchecked Sendable { var n = 0 }
        let counter = Counter()
        StubURLProtocol.handler = { _ in counter.n += 1; return (200, Data(#"{"t":"Buraya gel."}"#.utf8)) }

        let out1 = FakeOutput()
        let e1 = try NinoSetup.makeEngine(settings: settings, directories: directories, secrets: MemorySecretStore(),
                                          recognizer: nil, output: out1, session: StubURLProtocol.session(), onDevice: nil)
        await feed(e1, "Come here.")
        await e1.flush()
        XCTAssertEqual(counter.n, 1)

        let out2 = FakeOutput()
        let e2 = try NinoSetup.makeEngine(settings: settings, directories: directories, secrets: MemorySecretStore(),
                                          recognizer: nil, output: out2, session: StubURLProtocol.session(), onDevice: nil)
        await feed(e2, "Come here.")
        await feed(e2, "Bye.")
        XCTAssertEqual(counter.n, 1, "ikinci motor önbellekten okur")
        let texts = await out2.calls.compactMap { if case let .show(p) = $0 { return p.text } else { return nil } }
        XCTAssertEqual(texts, ["Buraya gel.", "Hoşça kal."])
    }
}

/// Gerçek Apple Vision okuyucusu: çizilmiş bir altyazıyı okur mu, kutusu doğru yerde mi?
final class VisionRecognizerTests: XCTestCase {
    private func renderSubtitle(_ text: String, width: Int = 1280, height: Int = 720) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.1, green: 0.12, blue: 0.15, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 44, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let w = CTLineGetTypographicBounds(line, nil, nil, nil)
        // CoreGraphics'te y aşağıdan yukarı: altyazı alttan ~%12 yukarıda.
        ctx.textPosition = CGPoint(x: (Double(width) - w) / 2, y: Double(height) * 0.12)
        CTLineDraw(line, ctx)
        // Üstte, bölge dışında bir arayüz yazısı.
        let top = CTLineCreateWithAttributedString(NSAttributedString(string: "Health 100", attributes: attrs))
        ctx.textPosition = CGPoint(x: 40, y: Double(height) * 0.9)
        CTLineDraw(top, ctx)
        return ctx.makeImage()!
    }

    #if canImport(Vision)
    func testReadsBottomSubtitleWithCorrectBox() async throws {
        let image = renderSubtitle("The ferry leaves at dawn.")
        let lines = try await VisionTextRecognizer().recognize(image, in: .defaultSubtitle)
        let hit = try XCTUnwrap(lines.first { $0.text.lowercased().contains("ferry") }, "okunanlar: \(lines.map(\.text))")
        XCTAssertTrue(NormalizedRect.defaultSubtitle.contains(x: hit.box.midX, y: hit.box.midY), "kutu: \(hit.box)")
        XCTAssertGreaterThan(hit.box.midY, 0.8, "sol üst düzende altta olmalı: \(hit.box)")
        XCTAssertEqual(hit.box.midX, 0.5, accuracy: 0.1)
        XCTAssertFalse(lines.contains { $0.text.contains("Health") }, "bölge dışı okunmamalı")

        let pipeline = ReadingPipeline(recognizer: VisionTextRecognizer())
        var events: [SubtitleEvent] = []
        for _ in 0..<3 { events += try await pipeline.process(image) }
        guard case let .started(sub)? = events.first else { return XCTFail("\(events)") }
        XCTAssertEqual(TextSimilarity.key(sub.text), "the ferry leaves at dawn")
    }
    #endif
}

final class OnDeviceTranslationTests: XCTestCase {
    func testOnDeviceGoesFirstWhenEnabled() {
        var s = NinoSettings()
        s.translation.providers = [.init(name: "http-1", urlTemplate: "http://127.0.0.1:9/", responsePath: ["t"])]
        let device = FakeProvider("device", .echo)
        XCTAssertEqual(s.makeProviders(secrets: MemorySecretStore(), onDevice: device).map(\.name), ["device", "http-1"])
        s.translation.useOnDevice = false
        XCTAssertEqual(s.makeProviders(secrets: MemorySecretStore(), onDevice: device).map(\.name), ["http-1"])
    }

    /// Cihazda İngilizce→Türkçe dil paketi yüklüyse gerçekten çevirir.
    /// Yalnız NINO_DEVICE_TRANSLATION_TESTS=1 ise çalışır.
    func testRealOnDeviceTranslation() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NINO_DEVICE_TRANSLATION_TESTS"] == "1")
        guard #available(macOS 26.0, iOS 26.0, *) else { throw XCTSkip("macOS 26+ gerekir") }
        let ready = await OnDeviceTranslationProvider.isInstalled(from: "en", to: "tr")
        try XCTSkipUnless(ready, "en→tr dil paketi yüklü değil")
        let out = try await OnDeviceTranslationProvider().translate("Come here.", from: "en", to: "tr")
        XCTAssertFalse(out.isEmpty)
        XCTAssertNotEqual(out, "Come here.")
    }
}
