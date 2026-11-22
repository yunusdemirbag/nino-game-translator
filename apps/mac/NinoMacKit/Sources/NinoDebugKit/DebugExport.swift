// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import UniformTypeIdentifiers

/// Bir zaman aralığını tek klasöre çıkarır (nino-debug):
/// `ps5/` ve `pencere/` (video parçalarından PNG kareler), `olay/` (PNG), `tv-ekran/` (PNG), `gunluk.txt`,
/// `tv-mesajlari.jsonl`, `ozet.md`. Dosya adları yerel saattir (`16-05-01.234`).
public struct DebugExport {
    public struct Result: Sendable, Equatable {
        public var folder: URL
        public var counts = DebugSummary.Counts()
        public var summary = DebugSummary()
    }

    public let layout: DebugRecordLayout
    public var timeZone: TimeZone = .current
    /// Akış başına en çok bu kadar kare (fazlası eşit aralıkla seyreltilir).
    public var maxFramesPerStream = 3000

    public init(layout: DebugRecordLayout) { self.layout = layout }

    public func run(from: Date, to: Date, into out: URL) throws -> Result {
        let fromMs = Int64(from.timeIntervalSince1970 * 1000), toMs = Int64(to.timeIntervalSince1970 * 1000)
        let fm = FileManager.default
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        let files = DebugRecordIndex.files(layout, fromMs: fromMs, toMs: toMs)
        var r = Result(folder: out)

        for (stream, name) in [(DebugStream.ps5, "ps5"), (.mac, "pencere")] {
            let segs = files.filter { $0.stream == stream }
            guard !segs.isEmpty else { continue }
            let dir = out.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let n = extractVideo(segs, fromMs: fromMs, toMs: toMs, into: dir, prefix: name)
            if stream == .ps5 { r.counts.ps5Frames = n } else { r.counts.macFrames = n }
        }

        let events = files.filter { $0.stream == .olay && $0.startMs >= fromMs && $0.startMs <= toMs }
        if !events.isEmpty {
            let dir = out.appendingPathComponent("olay", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for f in events {
                guard let img = DebugImageIO.read(f.url) else { continue }
                if DebugImageIO.write(img, to: dir.appendingPathComponent("olay-\(stamp(f.startMs)).png"), type: .png) {
                    r.counts.eventFrames += 1
                }
            }
        }

        let shots = files.filter { $0.stream == .tv && $0.startMs >= fromMs && $0.startMs <= toMs }
        if !shots.isEmpty {
            let dir = out.appendingPathComponent("tv-ekran", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for f in shots where (try? fm.copyItem(at: f.url, to: dir.appendingPathComponent("tv-\(stamp(f.startMs)).png"))) != nil {
                r.counts.tvShots += 1
            }
        }

        let logs = Self.readLog(files.filter { $0.stream == .gunluk }).filter { $0.t >= fromMs && $0.t <= toMs }
        r.counts.logLines = logs.count
        let full = DateFormatter()
        full.timeZone = timeZone
        full.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let text = logs.map { "[\(full.string(from: Date(timeIntervalSince1970: TimeInterval($0.t) / 1000)))] (\($0.k)) \($0.m)" }
            .joined(separator: "\n")
        try (text.isEmpty ? "" : text + "\n").write(to: out.appendingPathComponent("gunluk.txt"), atomically: true, encoding: .utf8)

        let messages = Self.readMessages(files.filter { $0.stream == .mesaj }).filter { $0.t >= fromMs && $0.t <= toMs }
        r.counts.tvMessages = messages.count
        let mtext = messages.map(\.line).joined(separator: "\n")
        try (mtext.isEmpty ? "" : mtext + "\n").write(to: out.appendingPathComponent("tv-mesajlari.jsonl"), atomically: true, encoding: .utf8)

        r.summary = DebugSummary.compute(lines: logs, messages: messages)
        let measurement = (try? Data(contentsOf: layout.measureFile)).flatMap { try? JSONDecoder().decode(DebugMeasurement.self, from: $0) }
        let md = r.summary.markdown(from: from, to: to, counts: r.counts, measurement: measurement, timeZone: timeZone)
        try md.write(to: out.appendingPathComponent("ozet.md"), atomically: true, encoding: .utf8)
        return r
    }

    func stamp(_ ms: Int64) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.dateFormat = "HH-mm-ss.SSS"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000))
    }

    /// Parçalardaki karelerin aralıktakilerini PNG yazar (açık parçalar da okunur: film parçacıkları).
    func extractVideo(_ segs: [DebugRecordFile], fromMs: Int64, toMs: Int64, into dir: URL, prefix: String) -> Int {
        var times: [(DebugRecordFile, Int64)] = []
        for s in segs.sorted(by: { $0.startMs < $1.startMs }) {
            for pts in Self.frameTimes(s.url) {
                let wall = s.startMs + pts
                if wall >= fromMs, wall <= toMs { times.append((s, pts)) }
            }
        }
        guard !times.isEmpty else { return 0 }
        let step = max(1, Int((Double(times.count) / Double(maxFramesPerStream)).rounded(.up)))
        var wanted: [URL: Set<Int64>] = [:]
        for (i, t) in times.enumerated() where i % step == 0 { wanted[t.0.url, default: []].insert(t.1) }
        var written = 0
        for s in segs {
            guard let want = wanted[s.url], !want.isEmpty else { continue }
            Self.readFrames(s.url) { pts, image in
                guard want.contains(pts) else { return }
                let name = "\(prefix)-\(stamp(s.startMs + pts)).png"
                if DebugImageIO.write(image, to: dir.appendingPathComponent(name), type: .png) { written += 1 }
            }
        }
        return written
    }

    /// Parçadaki karelerin sunum zamanları (ms), çözmeden.
    public static func frameTimes(_ url: URL) -> [Int64] {
        var out: [Int64] = []
        read(url, decode: false) { sample in
            out.append(Int64((CMSampleBufferGetPresentationTimeStamp(sample).seconds * 1000).rounded()))
        }
        return out
    }

    public static func readFrames(_ url: URL, _ body: (Int64, CGImage) -> Void) {
        read(url, decode: true) { sample in
            let pts = Int64((CMSampleBufferGetPresentationTimeStamp(sample).seconds * 1000).rounded())
            guard let pb = CMSampleBufferGetImageBuffer(sample), let img = image(pb) else { return }
            body(pts, img)
        }
    }

    private static func read(_ url: URL, decode: Bool, _ body: (CMSampleBuffer) -> Void) {
        let asset = AVURLAsset(url: url)
        let tracks = loadTracks(asset)
        guard let track = tracks.first, let reader = try? AVAssetReader(asset: asset) else { return }
        let settings: [String: Any]? = decode ? [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA] : nil
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return }
        reader.add(output)
        guard reader.startReading() else { return }
        while let s = output.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(s) > 0 { body(s) }
        }
    }

    private static func loadTracks(_ asset: AVURLAsset) -> [AVAssetTrack] {
        final class Box: @unchecked Sendable { var tracks: [AVAssetTrack] = [] }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        asset.loadTracks(withMediaType: .video) { t, _ in
            box.tracks = t ?? []
            done.signal()
        }
        _ = done.wait(timeout: .now() + 10)
        return box.tracks
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

    // MARK: JSONL okuma

    public static func readLog(_ files: [DebugRecordFile]) -> [DebugLogLine] {
        let d = JSONDecoder()
        return lines(files).compactMap { try? d.decode(DebugLogLine.self, from: Data($0.utf8)) }.sorted { $0.t < $1.t }
    }

    public static func readMessages(_ files: [DebugRecordFile]) -> [DebugTVMessage] {
        lines(files).compactMap(DebugTVMessage.parse).sorted { $0.t < $1.t }
    }

    static func lines(_ files: [DebugRecordFile]) -> [String] {
        files.sorted { $0.startMs < $1.startMs }.flatMap { f -> [String] in
            guard let s = try? String(contentsOf: f.url, encoding: .utf8) else { return [] }
            return s.split(separator: "\n").map(String.init)
        }
    }
}

/// Kayıt kökü: `--kok` verilmezse `~/Library/Logs/Nino/debug-kayit` ile `~/Library/Logs/Nino Dev/debug-kayit`'tan
/// en son yazılanı.
public enum DebugRootFinder {
    public static func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [DebugRecordLayout] {
        ["Nino", "Nino Dev"].map {
            DebugRecordLayout(logsFolder: home.appendingPathComponent("Library/Logs", isDirectory: true)
                .appendingPathComponent($0, isDirectory: true))
        }
    }

    public static func newest(_ list: [DebugRecordLayout]) -> DebugRecordLayout? {
        list.map { l -> (DebugRecordLayout, Int64) in (l, DebugRecordIndex.scan(l).map(\.endMs).max() ?? -1) }
            .filter { $0.1 >= 0 }
            .max { $0.1 < $1.1 }?.0
    }
}
