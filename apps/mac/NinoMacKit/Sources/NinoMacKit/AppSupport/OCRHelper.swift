// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import NinoCore

// Yedek okuyucu (okuma-hatti.md §4.6). Vision uzun oyunda arada bir sonsuza dek takılır ve kilit bütün süreci
// etkiler. Takılınca okumalar, uygulamanın `--ocr-helper` ile pencere açmadan açılan ikinci kopyasına gider.
// İki süreç arası basit borudur (girişe istek, çıkışa cevap); biçim `OCRWire`.

// MARK: - İleti biçimi

/// Boru biçimi. Bütün sayılar küçük uçlu (little-endian).
///
/// İstek:  `NOQ1` | kimlik u32 | en u32 | boy u32 | dil düzeltme u8 | piksel boyu u32 | RGBA8 pikseller (en × boy × 4)
/// Cevap:  `NOA1` | kimlik u32 | durum u8 (0 tamam, 1 hata) | satır sayısı u32 |
///         her satır: güven f32 | kutu var u8 | sol, üst, sağ, alt f64 (kutu varsa) | metin boyu u32 | UTF-8 metin
public enum OCRWire {
    public static let requestMagic = Data("NOQ1".utf8)
    public static let responseMagic = Data("NOA1".utf8)
    /// Tek istekte en çok bu kadar piksel verisi (8K kare).
    public static let maxPixelBytes = 7680 * 4320 * 4
    public static let maxLines = 4_096
    public static let maxTextBytes = 64 * 1024

    public enum WireError: Error, Equatable { case badMagic, tooLarge, badText, badImage }

    public struct Request: Equatable, Sendable {
        public var id: UInt32
        public var width: Int
        public var height: Int
        public var languageCorrection: Bool
        /// RGBA8, satır başına `width * 4` bayt.
        public var pixels: Data

        public init(id: UInt32, width: Int, height: Int, languageCorrection: Bool = true, pixels: Data) {
            self.id = id; self.width = width; self.height = height
            self.languageCorrection = languageCorrection; self.pixels = pixels
        }

        /// Görüntüden istek (RGBA8'e çizilir).
        public init?(id: UInt32, image: CGImage, languageCorrection: Bool = true) {
            let w = image.width, h = image.height
            guard w > 0, h > 0, w * h * 4 <= OCRWire.maxPixelBytes else { return nil }
            var data = Data(count: w * h * 4)
            let ok = data.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard ok else { return nil }
            self.init(id: id, width: w, height: h, languageCorrection: languageCorrection, pixels: data)
        }

        public func image() -> CGImage? {
            guard pixels.count == width * height * 4, let provider = CGDataProvider(data: pixels as CFData) else { return nil }
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }

        public func encoded() -> Data {
            var d = OCRWire.requestMagic
            d.appendLE(id)
            d.appendLE(UInt32(width))
            d.appendLE(UInt32(height))
            d.append(languageCorrection ? 1 : 0)
            d.appendLE(UInt32(pixels.count))
            d.append(pixels)
            return d
        }
    }

    public struct Response: Equatable, Sendable {
        public var id: UInt32
        public var ok: Bool
        public var lines: [GameReading.Line]

        public init(id: UInt32, ok: Bool, lines: [GameReading.Line]) {
            self.id = id; self.ok = ok; self.lines = lines
        }

        public func encoded() -> Data {
            var d = OCRWire.responseMagic
            d.appendLE(id)
            d.append(ok ? 0 : 1)
            d.appendLE(UInt32(lines.count))
            for l in lines {
                d.appendLE(l.confidence.bitPattern)
                if let b = l.box {
                    d.append(1)
                    for v in [b.left, b.top, b.right, b.bottom] { d.appendLE(v.bitPattern) }
                } else {
                    d.append(0)
                }
                let text = Data(l.text.utf8.prefix(OCRWire.maxTextBytes))
                d.appendLE(UInt32(text.count))
                d.append(text)
            }
            return d
        }
    }

    /// Parça parça gelen baytlardan tam iletileri çıkarır.
    public struct Decoder: Sendable {
        private var buffer = Data()
        public init() {}

        public mutating func append(_ data: Data) { buffer.append(data) }

        /// Tam bir istek varsa çıkarır; eksikse `nil`.
        public mutating func nextRequest() throws -> Request? {
            var r = Reader(buffer)
            guard let magic = r.bytes(4) else { return nil }
            guard magic == OCRWire.requestMagic else { throw WireError.badMagic }
            guard let id = r.u32(), let w = r.u32(), let h = r.u32(), let lc = r.u8(), let n = r.u32() else { return nil }
            guard Int(n) <= OCRWire.maxPixelBytes, Int(n) == Int(w) * Int(h) * 4 else { throw WireError.tooLarge }
            guard let pixels = r.bytes(Int(n)) else { return nil }
            buffer = Data(buffer.dropFirst(r.offset))
            return Request(id: id, width: Int(w), height: Int(h), languageCorrection: lc != 0, pixels: pixels)
        }

        public mutating func nextResponse() throws -> Response? {
            var r = Reader(buffer)
            guard let magic = r.bytes(4) else { return nil }
            guard magic == OCRWire.responseMagic else { throw WireError.badMagic }
            guard let id = r.u32(), let status = r.u8(), let count = r.u32() else { return nil }
            guard Int(count) <= OCRWire.maxLines else { throw WireError.tooLarge }
            var lines: [GameReading.Line] = []
            for _ in 0..<count {
                guard let conf = r.u32(), let hasBox = r.u8() else { return nil }
                var box: GameReading.Box?
                if hasBox != 0 {
                    guard let a = r.u64(), let b = r.u64(), let c = r.u64(), let e = r.u64() else { return nil }
                    box = GameReading.Box(left: Double(bitPattern: a), top: Double(bitPattern: b),
                                          right: Double(bitPattern: c), bottom: Double(bitPattern: e))
                }
                guard let len = r.u32() else { return nil }
                guard Int(len) <= OCRWire.maxTextBytes else { throw WireError.tooLarge }
                guard let bytes = r.bytes(Int(len)) else { return nil }
                guard let text = String(data: bytes, encoding: .utf8) else { throw WireError.badText }
                lines.append(GameReading.Line(text, confidence: Float(bitPattern: conf), box: box))
            }
            buffer = Data(buffer.dropFirst(r.offset))
            return Response(id: id, ok: status == 0, lines: lines)
        }

        public var pendingBytes: Int { buffer.count }
    }

    struct Reader {
        let data: Data
        var offset = 0
        init(_ data: Data) { self.data = Data(data) }

        mutating func bytes(_ n: Int) -> Data? {
            guard n >= 0, data.count - offset >= n else { return nil }
            defer { offset += n }
            return data.subdata(in: offset..<(offset + n))
        }

        mutating func u8() -> UInt8? { bytes(1)?.first }

        mutating func u32() -> UInt32? {
            guard let b = bytes(4) else { return nil }
            return b.enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
        }

        mutating func u64() -> UInt64? {
            guard let b = bytes(8) else { return nil }
            return b.enumerated().reduce(0) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
        }
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ v: T) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}

// MARK: - Yardımcı süreç (sunucu)

/// `Nino --ocr-helper`: pencere açmadan girişten istek okur, Vision ile okur, çıkışa cevap yazar.
/// Giriş kapanınca (ana uygulama öldü) çıkar.
public enum OCRHelperServer {
    public static let argument = "--ocr-helper"

    public static func isRequested(_ arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(argument)
    }

    /// Hiç dönmez.
    public static func run() -> Never {
        signal(SIGPIPE, SIG_IGN)
        let thread = Thread {
            serve(input: FileHandle.standardInput, output: FileHandle.standardOutput)
            exit(0)
        }
        thread.stackSize = 8 << 20
        thread.start()
        dispatchMain()
    }

    /// İstekleri sırayla işler; giriş bitince döner.
    static func serve(input: FileHandle, output: FileHandle) {
        var decoder = OCRWire.Decoder()
        while true {
            let chunk = input.availableData
            if chunk.isEmpty { return }
            decoder.append(chunk)
            do {
                while let request = try decoder.nextRequest() {
                    let response = handle(request)
                    try output.write(contentsOf: response.encoded())
                }
            } catch {
                return
            }
        }
    }

    static func handle(_ request: OCRWire.Request) -> OCRWire.Response {
        guard let image = request.image() else { return OCRWire.Response(id: request.id, ok: false, lines: []) }
        let reader = GameReading.VisionTextReader(usesLanguageCorrection: request.languageCorrection)
        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.lines = try? await reader.read(GameReading.ImageFrame(image), area: .full, scale: 1)
            done.signal()
        }
        done.wait()
        guard let lines = box.lines else { return OCRWire.Response(id: request.id, ok: false, lines: []) }
        return OCRWire.Response(id: request.id, ok: true, lines: lines)
    }

    private final class ResultBox: @unchecked Sendable { var lines: [GameReading.Line]? }
}

// MARK: - Yedek okuyucu (istemci)

/// Yedek sürece konuşan okuyucu. Kuralları (okuma-hatti.md §4.6):
/// - ilk başarılı asıl okumada o kareyle ısıtılır (en çok 240 sn); ısınmadan gelen okuma atlanır,
/// - her okuma en çok 12 sn; dönmezse süreç öldürülür, yenisi ısıtılır,
/// - art arda 3 düşüşte yedek bırakılır ve "son çare" bildirilir.
public actor HelperOCRReader: GameReading.TextReader {
    public struct Limits: Sendable {
        public var warmUpSeconds: Double = 240
        public var readSeconds: Double = 12
        public var maxDrops = 3
        public init() {}
    }

    public enum HelperError: Error, Equatable { case notWarm, timedOut, crashed, gaveUp, badImage, failed }

    /// Düşüş sayacının kuralı (saf).
    public enum DropRules {
        public static func afterDrop(drops: Int, limits: Limits = Limits()) -> (drops: Int, giveUp: Bool) {
            let n = drops + 1
            return (n, n >= limits.maxDrops)
        }
    }

    private let launch: @Sendable () throws -> HelperChannel
    private let limits: Limits
    private let onGiveUp: @Sendable () -> Void
    private var channel: HelperChannel?
    private var pending: [UInt32: CheckedContinuation<OCRWire.Response, Error>] = [:]
    private var nextID: UInt32 = 1
    private var generation = 0
    public private(set) var warm = false
    private var warming = false
    public private(set) var drops = 0
    public private(set) var gaveUp = false

    public init(limits: Limits = Limits(), onGiveUp: @escaping @Sendable () -> Void,
                launch: @escaping @Sendable () throws -> HelperChannel = { try HelperChannel.launchSelf() }) {
        self.limits = limits
        self.onGiveUp = onGiveUp
        self.launch = launch
    }

    // MARK: TextReader

    public func read(_ frame: GameReading.Frame, area: GameReading.Box, scale: Double) async throws -> [GameReading.Line] {
        if gaveUp { throw HelperError.gaveUp }
        guard let image = frame.crop(area, scale: scale) else { return [] }
        guard warm else {
            warmUp(with: image)
            throw HelperError.notWarm
        }
        do {
            let response = try await request(image, timeout: limits.readSeconds)
            drops = 0
            guard response.ok else { throw HelperError.failed }
            return response.lines
        } catch HelperError.timedOut {
            dropped(rewarmWith: image)
            throw HelperError.timedOut
        } catch HelperError.crashed {
            dropped(rewarmWith: image)
            throw HelperError.crashed
        }
    }

    /// Oturumun ilk başarılı okumasında çağrılır (o kareyle ısıtır). Isınmışsa ya da ısınıyorsa bir şey yapmaz.
    public func warmUp(with image: CGImage) {
        guard !warm, !warming, !gaveUp else { return }
        warming = true
        Task {
            let ok = (try? await self.request(image, timeout: self.limits.warmUpSeconds))?.ok == true
            self.warmFinished(ok)
        }
    }

    public func stop() {
        kill()
    }

    // MARK: İç işler

    private func warmFinished(_ ok: Bool) {
        warming = false
        warm = ok
        if !ok { kill() }
    }

    private func dropped(rewarmWith image: CGImage) {
        kill()
        let r = DropRules.afterDrop(drops: drops, limits: limits)
        drops = r.drops
        if r.giveUp {
            gaveUp = true
            onGiveUp()
        } else {
            warmUp(with: image)
        }
    }

    private func ensureChannel() throws -> HelperChannel {
        if let channel { return channel }
        let c = try launch()
        generation += 1
        let gen = generation
        channel = c
        c.onData = { [weak self] data in Task { await self?.received(data, generation: gen) } }
        c.onExit = { [weak self] in Task { await self?.exited(generation: gen) } }
        c.resume()
        return c
    }

    private var decoder = OCRWire.Decoder()

    private func received(_ data: Data, generation gen: Int) {
        guard gen == generation else { return }
        decoder.append(data)
        while let r = try? decoder.nextResponse() {
            pending.removeValue(forKey: r.id)?.resume(returning: r)
        }
    }

    private func exited(generation gen: Int) {
        guard gen == generation else { return }
        channel = nil
        warm = false
        failAll(HelperError.crashed)
    }

    private func kill() {
        generation += 1
        channel?.terminate()
        channel = nil
        warm = false
        decoder = OCRWire.Decoder()
        failAll(HelperError.crashed)
    }

    private func failAll(_ e: Error) {
        let all = pending
        pending = [:]
        for (_, c) in all { c.resume(throwing: e) }
    }

    private func request(_ image: CGImage, timeout: Double) async throws -> OCRWire.Response {
        let id = nextID
        nextID &+= 1
        guard let req = OCRWire.Request(id: id, image: image) else { throw HelperError.badImage }
        let c = try ensureChannel()
        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            c.send(req.encoded())
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                self.timedOut(id)
            }
        }
    }

    private func timedOut(_ id: UInt32) {
        pending.removeValue(forKey: id)?.resume(throwing: HelperError.timedOut)
    }
}

/// Yardımcı sürecin borusu.
public final class HelperChannel: @unchecked Sendable {
    public var onData: (@Sendable (Data) -> Void)?
    public var onExit: (@Sendable () -> Void)?
    private let sendData: @Sendable (Data) -> Void
    private let terminateProcess: @Sendable () -> Void
    private let start: (HelperChannel) -> Void
    public let pid: Int32

    public init(pid: Int32 = 0, send: @escaping @Sendable (Data) -> Void, terminate: @escaping @Sendable () -> Void,
                start: @escaping (HelperChannel) -> Void = { _ in }) {
        self.pid = pid
        self.sendData = send
        self.terminateProcess = terminate
        self.start = start
    }

    func resume() { start(self) }
    func send(_ data: Data) { sendData(data) }
    func terminate() { terminateProcess() }

    /// Uygulamanın kendisini `--ocr-helper` ile açar.
    public static func launchSelf() throws -> HelperChannel {
        guard let exe = Bundle.main.executableURL else { throw HelperOCRReader.HelperError.crashed }
        let process = Process()
        process.executableURL = exe
        process.arguments = [OCRHelperServer.argument]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let writeQueue = DispatchQueue(label: "nino.ocr-helper.write")
        var channel: HelperChannel!
        process.terminationHandler = { _ in channel?.onExit?() }
        try process.run()
        channel = HelperChannel(pid: process.processIdentifier, send: { data in
            writeQueue.async { try? input.fileHandleForWriting.write(contentsOf: data) }
        }, terminate: {
            output.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
            try? input.fileHandleForWriting.close()
        }, start: { ch in
            output.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil } else { ch.onData?(d) }
            }
        })
        return channel
    }
}

// MARK: - Bekçiye bağlama

/// Asıl okuyucuyu sarar: ilk başarılı okumada yedeği o kareyle ısıtır; uzun süren (takılan) okuma sonunda dönünce
/// bekçiye "asıl döndü" der (okumalar asıla geri geçer).
public struct PrimaryWatchReader: GameReading.TextReader {
    public final class Link: @unchecked Sendable {
        public weak var guarded: GameReading.GuardedTextReader?
        public init() {}
    }

    public let primary: GameReading.TextReader
    public let helper: HelperOCRReader
    public let link: Link
    public let clock: GameReading.Clock
    /// Bundan uzun süren okuma takılma sayılmış olabilir (bekçinin "meşgul" sınırı).
    public var slowMs = 8_000

    public func read(_ frame: GameReading.Frame, area: GameReading.Box, scale: Double) async throws -> [GameReading.Line] {
        let start = clock.nowMs
        let lines = try await primary.read(frame, area: area, scale: scale)
        if await !helper.warm, let image = frame.crop(area, scale: scale) { await helper.warmUp(with: image) }
        if clock.nowMs - start >= slowMs { await link.guarded?.primaryRecovered() }
        return lines
    }
}

public enum OCRFallback {
    private static let hook = HookBox()

    /// Yedek de üç kez düşünce (son çare). Uygulama (`NinoAppSupport`) bağlar.
    public static func setGiveUpHandler(_ h: @escaping @Sendable () -> Void) { hook.set(h) }

    /// Uygulamanın okuyucusu: Vision → (takılırsa) yedek süreç → (o da yoksa) işlemci.
    public static func makeGuardedReader(clock: GameReading.Clock) -> GameReading.GuardedTextReader {
        let helper = HelperOCRReader(onGiveUp: { hook.fire() })
        let link = PrimaryWatchReader.Link()
        let primary = PrimaryWatchReader(primary: GameReading.VisionTextReader(), helper: helper, link: link, clock: clock)
        let guarded = GameReading.GuardedTextReader(primary: primary, fallback: helper,
                                                    cpu: GameReading.CPUTextReader(), clock: clock)
        link.guarded = guarded
        return guarded
    }

    private final class HookBox: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: (@Sendable () -> Void)?
        func set(_ h: @escaping @Sendable () -> Void) { lock.withLock { handler = h } }
        func fire() { lock.withLock { handler }?() }
    }
}
