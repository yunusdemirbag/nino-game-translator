// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import XCTest
@testable import NinoCore

actor FakeOutput: SubtitleOutput {
    enum Call: Equatable { case show(ShowPayload), clear(Int?) }
    private(set) var calls: [Call] = []
    var failing = false

    func setFailing(_ v: Bool) { failing = v }

    func show(_ payload: ShowPayload) async throws {
        if failing { throw URLError(.notConnectedToInternet) }
        calls.append(.show(payload))
    }

    func clear(id: Int?) async throws {
        if failing { throw URLError(.notConnectedToInternet) }
        calls.append(.clear(id))
    }
}

final class NinoEngineTests: XCTestCase {
    private let box = NormalizedRect(x: 0.3, y: 0.8, width: 0.4, height: 0.05)

    private func lines(_ t: String?) -> [RecognizedLine] {
        t.map { [RecognizedLine(text: $0, confidence: 0.9, box: box)] } ?? []
    }

    private func feed(_ engine: NinoEngine, _ frames: [String?]) async {
        for f in frames { await engine.process(lines: lines(f)) }
    }

    private func translator(_ dict: [String: String]) -> (Translator, FakeProvider) {
        let p = FakeProvider("p", .dictionary(dict))
        return (Translator(chain: ProviderChain(providers: [p])), p)
    }

    func testReadTranslateShowClear() async {
        let (t, _) = translator(["Come here.": "Buraya gel.", "Now!": "Hemen!"])
        let out = FakeOutput()
        let engine = NinoEngine(pipeline: ReadingPipeline(), translator: t, output: out)
        let s = "Come here. Now!"
        await feed(engine, [s, s, s])
        await engine.waitUntilIdle()
        await feed(engine, [nil, nil])
        try? await waitUntil { await out.calls.count == 2 }
        let calls = await out.calls
        XCTAssertEqual(calls, [.show(ShowPayload(id: 1, text: "Buraya gel. Hemen!", source: s)), .clear(1)])
    }

    func testEventsStream() async {
        let (t, _) = translator(["Come here.": "Buraya gel."])
        let engine = NinoEngine(pipeline: ReadingPipeline(), translator: t, output: FakeOutput())
        let stream = await engine.events()
        let collector = Task { () -> [EngineEvent] in
            var got: [EngineEvent] = []
            for await e in stream {
                got.append(e)
                if case .shown = e { break }
            }
            return got
        }
        await feed(engine, ["Come here.", "Come here.", "Come here."])
        let events = await collector.value
        XCTAssertEqual(events.count, 3)
        guard case .subtitleStarted = events[0], case let .translated(id, text, _) = events[1], case .shown(1) = events[2] else {
            return XCTFail("\(events)")
        }
        XCTAssertEqual(id, 1)
        XCTAssertEqual(text, "Buraya gel.")
    }

    func testLateTranslationIsDropped() async {
        let gate = FakeProvider("gate", .slow(.milliseconds(300)))
        let t = Translator(chain: ProviderChain(providers: [gate]))
        let out = FakeOutput()
        let engine = NinoEngine(pipeline: ReadingPipeline(), translator: t, output: out)
        let stream = await engine.events()
        await feed(engine, ["Come here.", "Come here.", "Come here.", nil, nil])
        await engine.waitUntilIdle()
        var sawDropped = false
        for await e in stream {
            if case .dropped(1) = e { sawDropped = true; break }
            if case .shown = e { break }
        }
        XCTAssertTrue(sawDropped)
        let calls = await out.calls
        XCTAssertEqual(calls, [])
    }

    func testUntranslatedShownAsEnglish() async {
        let t = Translator(chain: ProviderChain(providers: [FakeProvider("a", .fail)]))
        let out = FakeOutput()
        let engine = NinoEngine(pipeline: ReadingPipeline(), translator: t, output: out)
        await feed(engine, ["Come here.", "Come here.", "Come here."])
        await engine.waitUntilIdle()
        let calls = await out.calls
        XCTAssertEqual(calls, [.show(ShowPayload(id: 1, text: "Come here.", source: "Come here."))])

        let quietOut = FakeOutput()
        let quiet = NinoEngine(pipeline: ReadingPipeline(), translator: t, output: quietOut,
                               options: .init(showUntranslated: false))
        await feed(quiet, ["Come here.", "Come here.", "Come here."])
        await quiet.waitUntilIdle()
        let quietCalls = await quietOut.calls
        XCTAssertEqual(quietCalls, [])
    }

    func testContinuationShowsFullText() async {
        let (t, provider) = translator(["Hello there.": "Selam.", "How are you?": "Nasılsın?"])
        let out = FakeOutput()
        let engine = NinoEngine(pipeline: ReadingPipeline(), translator: t, output: out)
        let a = "Hello there.", b = "Hello there. How are you?"
        await feed(engine, [a, a, a])
        await engine.waitUntilIdle()
        await feed(engine, [b, b, b])
        await engine.waitUntilIdle()
        try? await waitUntil { await out.calls.count >= 3 }

        let shows = await out.calls.compactMap { if case let .show(p) = $0 { return p.text } else { return nil } }
        XCTAssertEqual(shows, ["Selam.", "Selam. Nasılsın?"])
        XCTAssertEqual(provider.calls, ["Hello there.", "How are you?"], "eski cümle önbellekten gelir")
    }

    func testOutputFailureReported() async {
        let (t, _) = translator(["Come here.": "Buraya gel."])
        let out = FakeOutput()
        await out.setFailing(true)
        let engine = NinoEngine(pipeline: ReadingPipeline(), translator: t, output: out)
        let stream = await engine.events()
        await feed(engine, ["Come here.", "Come here.", "Come here."])
        await engine.waitUntilIdle()
        var failed = false
        for await e in stream { if case .outputFailed(1, _) = e { failed = true; break } }
        XCTAssertTrue(failed)
    }

    func testRunWithFrameSourceAndFakeRecognizer() async throws {
        let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = ctx.makeImage()!
        let recognizer = FakeRecognizer(Array(repeating: lines("Come here."), count: 3))
        let (t, _) = translator(["Come here.": "Buraya gel."])
        let out = FakeOutput()
        let engine = NinoEngine(pipeline: ReadingPipeline(recognizer: recognizer), translator: t, output: out)
        await engine.run(StaticFrameSource(images: [image, image, image, image]))
        let calls = await out.calls
        XCTAssertEqual(calls, [.show(ShowPayload(id: 1, text: "Buraya gel.", source: "Come here."))])
    }

    func testEndToEndOverRealLink() async throws {
        let tv = NinoDisplayServer(options: .init(name: "Deneme TV", port: 0, advertise: false))
        let port = try await tv.start()
        defer { tv.stop() }
        let sender = NinoSender(host: "127.0.0.1", port: port)
        try await sender.connect()
        let (t, _) = translator(["Come here.": "Buraya gel."])
        let engine = NinoEngine(pipeline: ReadingPipeline(), translator: t, output: sender)
        await feed(engine, ["Come here.", "Come here.", "Come here."])
        await engine.waitUntilIdle()
        try await waitUntil { tv.current?.text == "Buraya gel." }
        await feed(engine, [nil, nil])
        try await waitUntil { tv.current == nil }
        await sender.disconnect()
    }
}
