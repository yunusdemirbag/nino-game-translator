// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import NinoCore
import NinoDebugKit
import UniformTypeIdentifiers

// Debug kareleri ve video kaydı (guncelleme-admin.md §7). Yalnız admin modunda; klasör
// `~/Library/Logs/<Nino>/frames/`. Çizimli kareler bileşiktir (PS5 + TV katmanı; TVPageRenderer).

/// Saf kurallar: aralık, köşe bölgeleri, dosya adları, dosya sınırı.
public enum DebugFrameRules {
    /// Çizimli kare en çok bu aralıkla.
    public static let interval: TimeInterval = 2
    /// `f-` ve `r-` türlerinin her birinden tutulan dosya.
    public static let keepPerKind = 120
    /// Kayıt açık mı denetimi.
    public static let recordPoll: TimeInterval = 0.5
    /// Kayıtta saniyedeki ham kare.
    public static let videoFPS: Double = 10
    public static let annotatedQuality: Double = 0.7
    public static let rawQuality: Double = 0.92
    public static let videoQuality: Double = 0.85
    /// Kayıt videosu: 1920×1080 tuval, H.264, 8 Mbit/sn, 2 dk'lık parçalar (sessiz).
    public static let videoSettings = DebugVideoSegment.Settings(width: 1920, height: 1080, bitRate: 8_000_000)

    /// Köşe bölgeleri (kare oranında): sol üst ve alt şerit.
    public static let cornerBoxes: [GameReading.Box] = [
        GameReading.Box(left: 0, top: 0, right: 0.40, bottom: 0.36),
        GameReading.Box(left: 0.08, top: 0.885, right: 0.92, bottom: 0.995),
    ]

    public static func isDue(now: TimeInterval, last: TimeInterval?, interval: TimeInterval = interval) -> Bool {
        guard let last else { return true }
        return now - last >= interval
    }

    /// ISO 8601 zaman, `:` yerine `-` (dosya adında).
    public static func stamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date).replacingOccurrences(of: ":", with: "-")
    }

    /// Silinecek dosyalar: her önekten (`f-`, `r-`) en yeni `keep` kalır. Adlar zamanla sıralanır.
    public static func filesToDelete(_ names: [String], prefixes: [String] = ["f-", "r-"], keep: Int = keepPerKind) -> [String] {
        prefixes.flatMap { prefix -> [String] in
            let mine = names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".jpg") }.sorted()
            return mine.count > keep ? Array(mine.prefix(mine.count - keep)) : []
        }
    }

    /// Kayıtta bu karenin yazılma zamanı mı (saniyede 10).
    public static func isVideoFrameDue(nowMs: Int64, lastMs: Int64?) -> Bool {
        guard let lastMs else { return true }
        return Double(nowMs - lastMs) >= 1_000 / videoFPS
    }
}

/// Çizim için o anki bilgiler.
public struct DebugFrameContext: Sendable {
    public var readingArea: GameReading.Box?
    public var textBox: GameReading.Box?
    public var read: String
    public var translation: String
    public init(readingArea: GameReading.Box?, textBox: GameReading.Box?, read: String, translation: String) {
        self.readingArea = readingArea
        self.textBox = textBox
        self.read = read
        self.translation = translation
    }
}

/// Kareleri alır; 2 sn'de bir (ve TV'deki altyazı ya da ekran öğesi değişince) çizimli kare yazar. Çizimli kare
/// (`f-`, `latest.jpg`) bileşiktir: PS5 karesi + TV'nin çizdiği katmanın aynısı (`overlay`, gizli TV sayfası) +
/// okuma kutuları. Kayıt açıkken (`video/KAYIT`) saniyede 10 ham kare `video/<başlangıç>-<bitiş>.mov` parçalarına
/// (H.264) yazılır; klasör 2 GB'ı geçince en eski parça silinir.
public final class DebugFrameRecorder: @unchecked Sendable {
    public let folder: URL
    public var videoFolder: URL { folder.appendingPathComponent("video", isDirectory: true) }
    public var recordFlag: URL { videoFolder.appendingPathComponent("KAYIT") }
    /// `video/` klasörünün sınırı.
    public static let videoLimit: Int64 = 2 * 1024 * 1024 * 1024
    /// Değişiklikten sonra katman çizimi otursun diye bekleme.
    public static let changeDelay: TimeInterval = 0.35

    private let queue = DispatchQueue(label: "nino.debug-frames", qos: .utility)
    private let lock = NSLock()
    private var lastAnnotated: TimeInterval?
    private var soonAt: TimeInterval?
    private var lastVideoMs: Int64?
    private var busy = false
    private var videoBusy = false
    private var recording = false
    private var pollTimer: DispatchSourceTimer?
    private var audio: FileHandle?
    private var lastVideoPrune: TimeInterval = 0
    private let context: @Sendable () async -> DebugFrameContext
    private var overlayProvider: (@Sendable () async -> CGImage?)?
    private var compositeHandler: (@Sendable (CGImage) -> Void)?
    private lazy var video = DebugVideoSegment(folder: videoFolder, settings: DebugFrameRules.videoSettings)

    public init(folder: URL, context: @escaping @Sendable () async -> DebugFrameContext) {
        self.folder = folder
        self.context = context
        try? FileManager.default.createDirectory(at: videoFolder, withIntermediateDirectories: true)
        startPolling()
    }

    deinit { pollTimer?.cancel() }

    public var isRecording: Bool { lock.withLock { recording } }

    /// TV katmanının o anki görüntüsü (saydam zeminli; nil: katman yok).
    public var overlay: (@Sendable () async -> CGImage?)? {
        get { lock.withLock { overlayProvider } }
        set { lock.withLock { overlayProvider = newValue } }
    }

    /// Her bileşik karede (kutusuz, PS5 + TV katmanı; en çok 960 genişlik): admin önizlemesi.
    public var onComposite: (@Sendable (CGImage) -> Void)? {
        get { lock.withLock { compositeHandler } }
        set { lock.withLock { compositeHandler = newValue } }
    }

    /// TV'deki altyazı ya da ekran öğeleri değişti: kısa bir beklemeden sonraki kare yazılır.
    public func requestSoon(now: Date = Date()) {
        lock.withLock {
            let at = now.timeIntervalSince1970 + Self.changeDelay
            if soonAt == nil || at < soonAt! { soonAt = at }
        }
    }

    /// Kaynaktan gelen her karede çağrılır (her iş parçacığından).
    public func offer(_ image: CGImage) {
        let now = Date()
        let t = now.timeIntervalSince1970
        let nowMs = Int64(t * 1000)
        let (wantAnnotated, wantVideo) = lock.withLock { () -> (Bool, Bool) in
            var a = false, v = false
            let soon = soonAt.map { t >= $0 } ?? false
            if !busy, soon || DebugFrameRules.isDue(now: t, last: lastAnnotated) {
                lastAnnotated = t
                soonAt = nil
                busy = true
                a = true
            }
            if recording, !videoBusy, DebugFrameRules.isVideoFrameDue(nowMs: nowMs, lastMs: lastVideoMs) {
                lastVideoMs = nowMs
                videoBusy = true
                v = true
            }
            return (a, v)
        }
        if wantVideo {
            queue.async { [self] in
                video.append(atMs: nowMs) { ctx, canvas in
                    ctx.interpolationQuality = .medium
                    ctx.draw(image, in: DebugVideoSegment.fit(CGSize(width: image.width, height: image.height), in: canvas))
                }
                lock.withLock { videoBusy = false }
            }
        }
        if wantAnnotated {
            let context = self.context
            let overlay = self.overlay
            Task.detached(priority: .utility) { [weak self] in
                let c = await context()
                let layer = await overlay?()
                self?.queue.async {
                    self?.writeAnnotated(image, overlay: layer, context: c, date: now)
                    self?.lock.withLock { self?.busy = false }
                }
            }
        }
    }

    /// PS5 sesi (48 kHz, iki kanal, 32 bit float, art arda). Kayıt kapalıysa atılır.
    /// Not: Remote Play kitaplığı şu an sesi kapalı açıyor; çağıran yok, video sessiz.
    public func appendAudio(_ samples: [Float]) {
        guard isRecording, !samples.isEmpty else { return }
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        queue.async { [weak self] in
            guard let self else { return }
            if self.audio == nil {
                let url = self.videoFolder.appendingPathComponent("ses.f32")
                if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
                self.audio = try? FileHandle(forWritingTo: url)
                _ = try? self.audio?.seekToEnd()
                let start = self.videoFolder.appendingPathComponent("ses-baslangic.txt")
                if !FileManager.default.fileExists(atPath: start.path) {
                    try? "\(Int64(Date().timeIntervalSince1970 * 1000))".write(to: start, atomically: true, encoding: .utf8)
                }
            }
            try? self.audio?.write(contentsOf: data)
        }
    }

    // MARK: Kayıt bayrağı

    private func startPolling() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: DebugFrameRules.recordPoll)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let on = FileManager.default.fileExists(atPath: self.recordFlag.path)
            let was = self.lock.withLock { () -> Bool in
                let w = self.recording
                self.recording = on
                return w
            }
            if was, !on {
                try? self.audio?.close()
                self.audio = nil
                self.video.close()
            }
            let now = Date().timeIntervalSince1970
            if now - self.lastVideoPrune >= 30 {
                self.lastVideoPrune = now
                self.pruneVideo()
            }
        }
        t.resume()
        pollTimer = t
    }

    func pruneVideo(limit: Int64 = DebugFrameRecorder.videoLimit) {
        let keep = Set(["KAYIT", "ses.f32", "ses-baslangic.txt"] + [video.openName].compactMap { $0 })
        DebugRing.pruneFolder(videoFolder, limit: limit, protected: keep)
    }

    /// Açık video parçasını kapatır (testler ve kapanış).
    public func finishVideo() { queue.sync { video.close() } }
    /// Bekleyen işler (testler).
    public func drain(timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while lock.withLock({ busy || videoBusy }), Date() < deadline { usleep(1000) }
        queue.sync {}
    }

    // MARK: Yazma

    private func writeAnnotated(_ image: CGImage, overlay: CGImage?, context c: DebugFrameContext, date: Date) {
        let stamp = DebugFrameRules.stamp(date)
        Self.writeJPEG(image, to: folder.appendingPathComponent("r-\(stamp).jpg"), quality: DebugFrameRules.rawQuality)
        let composite = Self.composite(image, overlay: overlay)
        if let composite, let handler = onComposite, let small = Self.scaled(composite, maxWidth: 960) { handler(small) }
        // Okuma kutuları PS5 karesine ince kesikli çizilir, TV katmanı onların üstüne olduğu gibi konur (kutular TV'nin
        // çizdiği sanılmasın; kartın kırmızı-beyaz üst çizgisi TV'nindir).
        if let drawn = Self.annotate(image, context: c, overlay: overlay) {
            Self.writeJPEG(drawn, to: folder.appendingPathComponent("f-\(stamp).jpg"), quality: DebugFrameRules.annotatedQuality)
            Self.writeJPEG(drawn, to: folder.appendingPathComponent("latest.jpg"), quality: DebugFrameRules.annotatedQuality)
        }
        prune()
    }

    /// PS5 karesi + TV katmanı (katman kare boyuna ölçeklenir). Katman yoksa yalnız kare.
    static func composite(_ image: CGImage, overlay: CGImage?) -> CGImage? {
        guard let overlay else { return image }
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(image, in: rect)
        ctx.interpolationQuality = .high
        ctx.draw(overlay, in: rect)
        return ctx.makeImage()
    }

    static func scaled(_ image: CGImage, maxWidth: Int) -> CGImage? {
        guard image.width > maxWidth else { return image }
        let w = maxWidth, h = Int((Double(image.height) * Double(maxWidth) / Double(image.width)).rounded())
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    func prune() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in DebugFrameRules.filesToDelete(names) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    static func writeJPEG(_ image: CGImage, to url: URL, quality: Double) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    /// Okuma bölgesi sarı, köşeler mavi, yazının kutusu kırmızı: hepsi ince kesikli ve TV katmanının (`overlay`)
    /// altında; üstte iki satırlık şerit.
    static func annotate(_ image: CGImage, context c: DebugFrameContext, overlay: CGImage? = nil) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let size = CGSize(width: w, height: h)
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        func rect(_ b: GameReading.Box) -> CGRect {
            CGRect(x: b.left * size.width, y: (1 - b.bottom) * size.height,
                   width: (b.right - b.left) * size.width, height: (b.bottom - b.top) * size.height)
        }
        let line = max(1, CGFloat(w) / 1280)
        ctx.setLineWidth(line)
        ctx.setLineDash(phase: 0, lengths: [line * 5, line * 5])
        if let area = c.readingArea {
            ctx.setStrokeColor(CGColor(red: 1, green: 0.85, blue: 0, alpha: 0.8))  // sarı
            ctx.stroke(rect(area))
        }
        ctx.setStrokeColor(CGColor(red: 0.2, green: 0.5, blue: 1, alpha: 0.7))
        for b in DebugFrameRules.cornerBoxes { ctx.stroke(rect(b)) }
        if let box = c.textBox {
            ctx.setStrokeColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.9))
            ctx.setLineDash(phase: 0, lengths: [line * 3, line * 3])
            ctx.stroke(rect(box))
        }
        ctx.setLineDash(phase: 0, lengths: [])
        if let overlay {
            ctx.interpolationQuality = .high
            ctx.draw(overlay, in: CGRect(origin: .zero, size: size))
        }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.7))
        ctx.fill(CGRect(x: 0, y: size.height - 90, width: size.width, height: 90))
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 26, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, 26, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        ]
        for (i, text) in ["OKUNAN: \(c.read)", "ÇEVİRİ: \(c.translation)"].enumerated() {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
            ctx.textPosition = CGPoint(x: 16, y: size.height - 38 - CGFloat(i) * 38)
            CTLineDraw(line, ctx)
        }
        return ctx.makeImage()
    }
}
