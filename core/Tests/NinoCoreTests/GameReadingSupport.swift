// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
@testable import NinoCore

typealias GR = GameReading

/// Görüntüsüz sahte kare: "kare N" aynı N ise iz aynıdır.
struct FakeFrame: GameReading.Frame {
    var id: Int
    var fingerprintOverride: GameReading.Fingerprint?
    var pixelWidth = 1920
    var pixelHeight = 1080
    var image: CGImage? { nil }

    init(_ id: Int, fingerprint: GameReading.Fingerprint? = nil) {
        self.id = id; fingerprintOverride = fingerprint
    }

    func fingerprint(of box: GameReading.Box) -> GameReading.Fingerprint {
        fingerprintOverride ?? .uniform(UInt8(truncatingIfNeeded: id * 37))
    }

    func crop(_ box: GameReading.Box, scale: Double) -> CGImage? { nil }
}

/// Sırayla önceden yazılmış satırları döndüren okuyucu. Çağrıları kaydeder.
final class ScriptedReader: GameReading.TextReader, @unchecked Sendable {
    struct Call: Equatable { var area: GameReading.Box; var scale: Double }
    private let lock = NSLock()
    private var script: [[GameReading.Line]]
    private var handler: ((Call) -> [GameReading.Line])?
    private(set) var calls: [Call] = []
    var error: Error?

    init(_ script: [[GameReading.Line]] = []) { self.script = script }
    init(handler: @escaping (Call) -> [GameReading.Line]) { script = []; self.handler = handler }

    func push(_ lines: [GameReading.Line]) { lock.lock(); script.append(lines); lock.unlock() }

    func read(_ frame: GameReading.Frame, area: GameReading.Box, scale: Double) async throws -> [GameReading.Line] {
        try next(Call(area: area, scale: scale))
    }

    private func next(_ call: Call) throws -> [GameReading.Line] {
        lock.lock(); defer { lock.unlock() }
        calls.append(call)
        if let error { throw error }
        if let handler { return handler(call) }
        return script.isEmpty ? [] : script.removeFirst()
    }

    var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls.count }
}

func gbox(_ l: Double, _ t: Double, _ r: Double, _ b: Double) -> GameReading.Box {
    GameReading.Box(left: l, top: t, right: r, bottom: b)
}

func gline(_ text: String, _ b: GameReading.Box? = nil, conf: Float = 0.95) -> GameReading.Line {
    GameReading.Line(text, confidence: conf, box: b)
}

/// Düz renkli bir görüntü (renk ölçümleri için).
func solidImage(width: Int, height: Int, gray: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}
