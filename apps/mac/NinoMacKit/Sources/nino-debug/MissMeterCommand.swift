// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import NinoCore
import NinoDebugKit

// nino-debug kacan <aralık>: kaçırma ölçer (NinoCore oyun-okuma.md "Kaçırma ölçer").
// Kayıttaki PS5 kareleri bastırma kuralları kapalı okunur; çıkan diyalog satırları aynı aralıktaki günlüğün
// "okundu" satırlarıyla karşılaştırılır. Kurallar açık okuyucu da aynı kareleri sahte saatle okur: kaçan satırın
// o anki nedeni ve bu sürümün yakalama oranı. Kayıt yalnız okunur.

enum MissMeterCommand {
    static func run(layout: DebugRecordLayout, from: Date, to: Date, out: URL, stepMs: Int = 250) async throws {
        let fromMs = Int64(from.timeIntervalSince1970 * 1000), toMs = Int64(to.timeIntervalSince1970 * 1000)
        let files = DebugRecordIndex.files(layout, fromMs: fromMs, toMs: toMs, streams: [.ps5, .gunluk])
        let videos = files.filter { $0.stream == .ps5 && !$0.isOpen }.sorted { $0.startMs < $1.startMs }
        let log = DebugExport.readLog(files.filter { $0.stream == .gunluk }).filter { $0.t >= fromMs - 5_000 && $0.t <= toMs + 5_000 }
        var reads: [GameReading.MissMeter.LogEntry] = []
        var notes: [GameReading.MissMeter.LogEntry] = []
        var elementLog: [GameReading.MissMeter.LogEntry] = []
        for l in log {
            switch GameReading.MissMeter.classify(l.m) {
            case let .read(t)?: reads.append(.init(ms: Int(l.t), text: t))
            case let .note(t)?: notes.append(.init(ms: Int(l.t), text: t))
            case let .element(t)?: elementLog.append(.init(ms: Int(l.t), text: t))
            case nil: break
            }
        }
        // Telefon oyunu kuralları günlükte GTA 6 geçiyorsa (Mac'teki karar gibi).
        var cfg = GameReading.Reader.Configuration()
        let gta6 = log.contains { $0.m.contains("GTA 6") }
        GameReading.GTA6Rules.apply(gta6, packGame: gta6 ? "gta-6" : nil, to: &cfg)
        // İki yeniden oynatma: o geceki sürümün kuralları (kaçanın nedeni) ve bu sürüm (yakalama oranı).
        var old = cfg
        old.menuClearsOnExit = false
        old.lowercaseContinuation = false
        let scanner = GameReading.MissMeter.Scanner(textReader: GameReading.VisionTextReader(),
                                                    replayConfigurations: [("eski", old), ("yeni", cfg)], startMs: Int(fromMs))
        await scanner.setReplayStep(stepMs)
        var count = 0
        for v in videos {
            try await readFrames(v.url) { pts, image in
                let ms = v.startMs + pts
                guard ms >= fromMs, ms <= toMs else { return }
                await scanner.scan(GameReading.ImageFrame(image), at: Int(ms))
                count += 1
                if count % 100 == 0 { FileHandle.standardError.write(Data("\(count) kare…\n".utf8)) }
            }
        }
        let candidates = await scanner.collector.candidates
        let menuFrames = await scanner.menuFrames
        let replays = await scanner.replays
        let elements = GameReading.MissMeter.compareElements(await scanner.elements.candidates, logged: elementLog)
        let before = GameReading.MissMeter.compare(candidates, reads: reads, notes: notes, replayNotes: replays["eski"]?.notes ?? [])
        let after = GameReading.MissMeter.compare(candidates, reads: replays["yeni"]?.reads ?? [], replayNotes: replays["yeni"]?.notes ?? [])

        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        let stamp: (Int) -> String = { f.string(from: Date(timeIntervalSince1970: TimeInterval($0) / 1000)) }
        var text = "Aralık: \(stamp(Int(fromMs)))–\(stamp(Int(toMs))), \(videos.count) video, \(count) kare (\(menuFrames) menü karesi sayılmadı)"
        text += gta6 ? ", GTA 6 kuralları\n\n" : "\n\n"
        text += GameReading.MissMeter.format(before, title: "Günlük (o sırada çalışan sürüm)", stamp: stamp)
        text += "\n(\"yeniden oynatmada\": o geceki sürümün kurallarıyla aynı karelerin notları.)\n\n"
        text += GameReading.MissMeter.format(after, title: "Bu sürüm (aynı kareler, kurallar açık, sahte saat)", stamp: stamp)
        text += "\n" + GameReading.MissMeter.formatElements(elements, stamp: stamp)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let file = out.appendingPathComponent("kacan.md")
        try text.write(to: file, atomically: true, encoding: .utf8)
        print("Diyalog satırı \(before.dialogue.count): günlükte okunan \(before.caught.count), bu sürüm \(after.caught.count)")
        for m in after.misses {
            let why = m.replayReasons.joined(separator: "; ")
            print("BU SÜRÜMDE KAÇAN \(stamp(m.candidate.firstMs)) \"\(m.candidate.text.replacingOccurrences(of: "\n", with: " / "))\"\(why.isEmpty ? "" : " — " + why)")
        }
        for m in before.misses {
            let c = m.candidate
            let why = (m.loggedReasons + m.replayReasons.map { "yeniden oynatma: " + $0 }).joined(separator: "; ")
            print("KAÇAN \(stamp(c.firstMs)) \"\(c.text.replacingOccurrences(of: "\n", with: " / "))\"\(why.isEmpty ? "" : " — " + why)")
        }
        print("Ekran öğesi \(elements.dialogue.count): günlükte karşılığı olan \(elements.caught.count)")
        for m in elements.misses {
            print("ÖĞE KARŞILIKSIZ \(stamp(m.candidate.firstMs)) [\(m.candidate.kind)] \"\(m.candidate.text.replacingOccurrences(of: "\n", with: " / "))\"")
        }
        print("Rapor: \(file.path)")
    }

    /// Videonun kareleri sırayla (sunum zamanı ms, görüntü). AVFoundation; kayıt değiştirilmez.
    static func readFrames(_ url: URL, _ body: (Int64, CGImage) async -> Void) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return }
        reader.add(output)
        guard reader.startReading() else { return }
        while let s = output.copyNextSampleBuffer() {
            guard CMSampleBufferGetNumSamples(s) > 0, let pb = CMSampleBufferGetImageBuffer(s), let img = image(pb) else { continue }
            await body(Int64((CMSampleBufferGetPresentationTimeStamp(s).seconds * 1000).rounded()), img)
        }
    }

    static func image(_ pb: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: CVPixelBufferGetWidth(pb),
                                  height: CVPixelBufferGetHeight(pb), bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        return ctx.makeImage()
    }
}
