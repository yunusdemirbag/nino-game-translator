// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// JSONL günlük parçası: satır başına bir kayıt, doğrudan dosyaya (çökmede kaybolmaz). Süre dolunca kapanır ve
/// `<başlangıç>-<bitiş>.jsonl` adını alır. Tek kuyruktan kullanılır.
public final class DebugJournal {
    public let layout: DebugRecordLayout
    public let stream: DebugStream
    public let segmentLength: TimeInterval
    private var handle: FileHandle?
    private var url: URL?
    private var startMs: Int64 = 0
    private var lastMs: Int64 = 0
    public private(set) var bytesWritten: Int64 = 0

    public init(layout: DebugRecordLayout, stream: DebugStream, segmentLength: TimeInterval = 600) {
        self.layout = layout
        self.stream = stream
        self.segmentLength = segmentLength
    }

    public var openName: String? { url?.lastPathComponent }

    public func append(_ line: String, atMs ms: Int64) {
        if handle != nil, Double(ms - startMs) >= segmentLength * 1000 { close() }
        if handle == nil { open(ms) }
        lastMs = max(lastMs, ms)
        let data = Data((line + "\n").utf8)
        try? handle?.write(contentsOf: data)
        bytesWritten += Int64(data.count)
    }

    private func open(_ ms: Int64) {
        try? FileManager.default.createDirectory(at: layout.folder(stream), withIntermediateDirectories: true)
        let u = layout.openFile(stream, startMs: ms)
        if !FileManager.default.fileExists(atPath: u.path) { FileManager.default.createFile(atPath: u.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: u)
        _ = try? handle?.seekToEnd()
        url = u
        startMs = ms
        lastMs = ms
    }

    public func close() {
        guard let h = handle, let u = url else { return }
        try? h.close()
        handle = nil
        url = nil
        let closed = u.deletingLastPathComponent()
            .appendingPathComponent(DebugRecordLayout.closedName(startMs: startMs, endMs: lastMs, ext: stream.fileExtension))
        try? FileManager.default.moveItem(at: u, to: closed)
    }

    /// JSON metni için kaçış.
    public static func quote(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if c.value < 0x20 { out += String(format: "\\u%04x", c.value) } else { out.unicodeScalars.append(c) }
            }
        }
        return out + "\""
    }
}

/// Donanım kodlayıcılı (H.264, VideoToolbox) video parçası. Parça `.mov`, 1 sn'lik film parçacıklarıyla yazılır:
/// yazılırken ve çökmeden sonra da okunabilir. Kare zamanı = duvar saati − başlangıç (ms).
/// Kareler sabit tuvale (ör. 960×540) en-boy korunarak küçültülerek çizilir. Tek kuyruktan kullanılır.
public final class DebugVideoSegment {
    public struct Settings: Sendable, Equatable {
        public var width: Int
        public var height: Int
        public var bitRate: Int
        public var segmentLength: TimeInterval
        public init(width: Int, height: Int, bitRate: Int, segmentLength: TimeInterval = 120) {
            self.width = width
            self.height = height
            self.bitRate = bitRate
            self.segmentLength = segmentLength
        }
    }

    /// Parçaların klasörü (`debug-kayit/<akış>/` ya da `frames/video/`).
    public let folder: URL
    public let settings: Settings
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var url: URL?
    private var startMs: Int64 = 0
    private var lastMs: Int64 = -1
    public private(set) var framesWritten = 0
    public private(set) var framesDropped = 0
    /// Kapanmış parçaların toplam boyu.
    public private(set) var closedBytes: Int64 = 0

    public convenience init(layout: DebugRecordLayout, stream: DebugStream, settings: Settings) {
        self.init(folder: layout.folder(stream), settings: settings)
    }

    public init(folder: URL, settings: Settings) {
        self.folder = folder
        self.settings = settings
    }

    public var openName: String? { url?.lastPathComponent }
    /// Tuvalin bellekteki boyu (havuzda birkaç tane durur).
    public var bufferBytes: Int64 { Int64(settings.width * settings.height * 4) }

    /// Kareyi tuvale çizer (`draw` tuvalin bağlamı ve boyuyla çağrılır; çizim aşağıdan yukarı CG düzenindedir).
    @discardableResult
    public func append(atMs ms: Int64, draw: (CGContext, CGSize) -> Void) -> Bool {
        if writer != nil, Double(ms - startMs) >= settings.segmentLength * 1000 { close() }
        if writer == nil { open(ms) }
        guard let input, let adaptor, let pool = adaptor.pixelBufferPool, ms > lastMs else {
            framesDropped += 1
            return false
        }
        // Kodlayıcı meşgulse kısa bekler (en çok 100 ms); yetişemezse kare atılır, birikmez.
        var waited = 0
        while !input.isReadyForMoreMediaData, waited < 50 {
            usleep(2000)
            waited += 1
        }
        guard input.isReadyForMoreMediaData else {
            framesDropped += 1
            return false
        }
        var pb: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let pb else {
            framesDropped += 1
            return false
        }
        CVPixelBufferLockBaseAddress(pb, [])
        let ok: Bool = {
            guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: settings.width, height: settings.height,
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return false }
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: settings.width, height: settings.height))
            ctx.interpolationQuality = .low
            draw(ctx, CGSize(width: settings.width, height: settings.height))
            return true
        }()
        CVPixelBufferUnlockBaseAddress(pb, [])
        guard ok, adaptor.append(pb, withPresentationTime: CMTime(value: ms - startMs, timescale: 1000)) else {
            framesDropped += 1
            return false
        }
        lastMs = ms
        framesWritten += 1
        return true
    }

    private func open(_ ms: Int64) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let u = folder.appendingPathComponent("\(ms).mov")
        try? FileManager.default.removeItem(at: u)
        guard let w = try? AVAssetWriter(outputURL: u, fileType: .mov) else { return }
        w.movieFragmentInterval = CMTime(value: 1, timescale: 1)
        let i = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: settings.width,
            AVVideoHeightKey: settings.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: settings.bitRate,
                AVVideoMaxKeyFrameIntervalKey: 10,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel,
            ] as [String: Any],
        ])
        i.expectsMediaDataInRealTime = true
        let a = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: i, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: settings.width,
            kCVPixelBufferHeightKey as String: settings.height,
        ])
        guard w.canAdd(i) else { return }
        w.add(i)
        guard w.startWriting() else { return }
        w.startSession(atSourceTime: .zero)
        writer = w
        input = i
        adaptor = a
        url = u
        startMs = ms
        lastMs = -1
    }

    /// Parçayı bitirir ve `<başlangıç>-<bitiş>.mov` adını verir. Hiç kare yoksa siler.
    public func close() {
        guard let w = writer, let i = input, let u = url else { return }
        writer = nil
        input = nil
        adaptor = nil
        url = nil
        let start = startMs, end = lastMs >= 0 ? lastMs : startMs
        let empty = lastMs < 0
        i.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        w.finishWriting { done.signal() }
        _ = done.wait(timeout: .now() + 5)
        if empty {
            try? FileManager.default.removeItem(at: u)
            return
        }
        let closed = u.deletingLastPathComponent()
            .appendingPathComponent(DebugRecordLayout.closedName(startMs: start, endMs: max(start, end), ext: "mov"))
        if (try? FileManager.default.moveItem(at: u, to: closed)) != nil {
            closedBytes += ((try? FileManager.default.attributesOfItem(atPath: closed.path)[.size]) as? NSNumber)?.int64Value ?? 0
        }
    }

    /// Kaynağı tuvale en-boy koruyarak sığdıran dikdörtgen.
    public static func fit(_ source: CGSize, in canvas: CGSize) -> CGRect {
        guard source.width > 0, source.height > 0 else { return CGRect(origin: .zero, size: canvas) }
        let s = min(canvas.width / source.width, canvas.height / source.height)
        let w = source.width * s, h = source.height * s
        return CGRect(x: (canvas.width - w) / 2, y: (canvas.height - h) / 2, width: w, height: h)
    }
}

/// Resim dosyası yazma/okuma.
public enum DebugImageIO {
    @discardableResult
    public static func write(_ image: CGImage, to url: URL, type: UTType, quality: Double? = nil) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
        var props: [CFString: Any] = [:]
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    public static func read(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// PNG imzası (adb `screencap -p` çıktısının doğruluğu).
    public static func isPNG(_ data: Data) -> Bool {
        data.count > 8 && data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
}
