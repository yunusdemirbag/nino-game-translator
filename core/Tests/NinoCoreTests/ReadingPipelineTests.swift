// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import XCTest
@testable import NinoCore

/// Sırayla önceden yazılmış satırları döndüren sahte okuyucu.
final class FakeRecognizer: TextRecognizer {
    private var script: [[RecognizedLine]]
    private(set) var requestedRegions: [NormalizedRect] = []

    init(_ script: [[RecognizedLine]]) { self.script = script }

    func recognize(_ image: CGImage, in region: NormalizedRect) async throws -> [RecognizedLine] {
        requestedRegions.append(region)
        return script.isEmpty ? [] : script.removeFirst()
    }
}

final class ReadingPipelineTests: XCTestCase {
    private let box = NormalizedRect(x: 0.3, y: 0.8, width: 0.4, height: 0.05)

    private func frame(_ text: String?) -> [RecognizedLine] {
        guard let text else { return [] }
        return [RecognizedLine(text: text, confidence: 0.9, box: box)]
    }

    private func blankImage() -> CGImage {
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    private func run(_ pipeline: ReadingPipeline, _ texts: [String?]) -> [SubtitleEvent] {
        texts.flatMap { pipeline.process(lines: frame($0)) }
    }

    func testStartedAndEndedWithSentences() {
        let p = ReadingPipeline()
        let events = run(p, ["Come here. Now!", "Come here. Now!", "Come here. Now!", nil, nil])
        XCTAssertEqual(events.count, 2)
        guard case let .started(sub) = events[0], case let .ended(endSub) = events[1] else {
            return XCTFail("beklenen: started, ended")
        }
        XCTAssertEqual(sub.id, 1)
        XCTAssertEqual(sub.text, "Come here. Now!")
        XCTAssertEqual(sub.sentences, ["Come here.", "Now!"])
        XCTAssertEqual(sub.newSentences, ["Come here.", "Now!"])
        XCTAssertFalse(sub.isRepeat)
        XCTAssertFalse(sub.isContinuation)
        XCTAssertEqual(sub.startFrame, 3)
        XCTAssertEqual(endSub, sub)
    }

    func testNoiseIsIgnored() {
        let p = ReadingPipeline()
        let events = run(p, ["MENU", "MENU", "MENU", "A", "A", "A"])
        XCTAssertEqual(events, [])
    }

    func testRepeatIsMarked() {
        let p = ReadingPipeline()
        let events = run(p, ["Run!", "Run!", "Run!", nil, nil, "Run!", "Run!", "Run!"])
        let started = events.compactMap { if case let .started(s) = $0 { return s } else { return nil } }
        XCTAssertEqual(started.map(\.id), [1, 2])
        XCTAssertEqual(started.map(\.isRepeat), [false, true])
    }

    func testContinuationOnlyNewSentences() {
        let p = ReadingPipeline()
        let a = "Hello there."
        let b = "Hello there. How are you?"
        let events = run(p, [a, a, a, b, b, b])
        let started = events.compactMap { if case let .started(s) = $0 { return s } else { return nil } }
        XCTAssertEqual(started.count, 2)
        XCTAssertTrue(started[1].isContinuation)
        XCTAssertEqual(started[1].sentences, ["Hello there.", "How are you?"])
        XCTAssertEqual(started[1].newSentences, ["How are you?"])
    }

    func testUnrelatedNextSubtitleIsNotContinuation() {
        let p = ReadingPipeline()
        let events = run(p, ["Come here.", "Come here.", "Come here.", "Go away.", "Go away.", "Go away."])
        let started = events.compactMap { if case let .started(s) = $0 { return s } else { return nil } }
        XCTAssertEqual(started.map(\.isContinuation), [false, false])
        XCTAssertEqual(started[1].newSentences, ["Go away."])
    }

    func testAsyncPathUsesRecognizerAndRegion() async throws {
        let fake = FakeRecognizer(Array(repeating: frame("Come here."), count: 3))
        let p = ReadingPipeline(recognizer: fake)
        var events: [SubtitleEvent] = []
        for _ in 0..<3 { events += try await p.process(blankImage()) }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(fake.requestedRegions, Array(repeating: .defaultSubtitle, count: 3))
    }

    func testAsyncWithoutRecognizerThrows() async {
        let p = ReadingPipeline()
        do {
            _ = try await p.process(blankImage())
            XCTFail("hata bekleniyordu")
        } catch {
            XCTAssertEqual(error as? ReadingPipelineError, .noRecognizer)
        }
    }
}

final class ReadingPipelineEdgeTests: XCTestCase {
    private let box = NormalizedRect(x: 0.3, y: 0.8, width: 0.4, height: 0.05)
    private func run(_ p: ReadingPipeline, _ texts: [String?]) -> [Subtitle] {
        texts.flatMap { t in p.process(lines: t.map { [RecognizedLine(text: $0, confidence: 0.9, box: box)] } ?? []) }
            .compactMap { if case let .started(s) = $0 { return s } else { return nil } }
    }

    func testShortAppendIsContinuation() {
        let a = "Hello there, my friend.", b = "Hello there, my friend. Go."
        let started = run(ReadingPipeline(), [a, a, a, b, b, b, b])
        XCTAssertEqual(started.count, 2)
        XCTAssertTrue(started[1].isContinuation)
        XCTAssertEqual(started[1].newSentences, ["Go."])
    }

    func testLongGapIsNotContinuation() {
        let gap: [String?] = Array(repeating: nil, count: 30)
        let started = run(ReadingPipeline(), ["No.", "No.", "No."] + gap + ["No. Not again.", "No. Not again.", "No. Not again."])
        XCTAssertEqual(started.count, 2)
        XCTAssertFalse(started[1].isContinuation)
        XCTAssertEqual(started[1].newSentences, ["No.", "Not again."])
    }

    func testRepeatWithOCRWobbleIsMarked() {
        let started = run(ReadingPipeline(), ["Hello there, traveler", "Hello there, traveler", "Hello there, traveler",
                                              nil, nil,
                                              "Hel1o there, traveler", "Hel1o there, traveler", "Hel1o there, traveler"])
        XCTAssertEqual(started.map(\.isRepeat), [false, true])
    }
}
