// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import CoreText
import Foundation
import NinoCore
import NinoDebugKit
import UniformTypeIdentifiers

// Sürekli hata ayıklama kaydı (yalnız admin modu / Debug yapısı; kullanıcıya hiçbir yerde görünmez).
// Halka tampon `~/Library/Logs/<Nino>/debug-kayit/`; çıkarma `nino-debug` ile (Sources/nino-debug).

/// Kaydın saf kuralları.
public enum DebugRecordingRules {
    /// Kayıt açık mı: admin modunun kuralıyla aynı (deneme yapısında her zaman, yayında yalnız `ninoAdminMode`).
    public static func isEnabled(flavor: AppIdentity.Flavor, adminFlag: Bool) -> Bool {
        AdminModeRules.isOn(flavor: flavor, flag: adminFlag)
    }

    /// Hedef aralıklar (bütçe çarpanıyla uzar).
    public static let ps5Interval: TimeInterval = 0.5
    public static let macInterval: TimeInterval = 1
    /// Olay karesi (tam boy) en sık bu aralıkla; bütçe çarpanı 4'e çıkınca hiç alınmaz.
    public static let eventGap: TimeInterval = 5
    public static let eventMaxScale: Double = 2
    public static let eventQuality = 0.6
    /// TV ekran görüntüsü aralığı, hatadan sonra bekleme.
    public static let tvShotInterval: TimeInterval = 60
    public static let tvShotBackoff: TimeInterval = 300
    /// Bakım (halka tampon) ve ölçüm dosyası.
    public static let maintenanceInterval: TimeInterval = 5
    public static let pruneEvery: TimeInterval = 30

    public static let ps5Video = DebugVideoSegment.Settings(width: 960, height: 540, bitRate: 900_000)
    public static let macVideo = DebugVideoSegment.Settings(width: 1280, height: 800, bitRate: 500_000)

    public static func isDue(now: TimeInterval, last: TimeInterval?, interval: TimeInterval, scale: Double) -> Bool {
        guard let last else { return true }
        return now - last >= interval * scale
    }

    /// Olay karesi alınacak satırlar: okunan/gösterilen altyazı, TV ve PS5 bağlantısı, oyun tanıma, okuma takılması.
    public static func isEventLine(_ m: String) -> Bool {
        if m.hasPrefix("#") { return m.contains(" okundu") || m.contains(" gösterildi") || m.contains(" atıldı") }
        return m.hasPrefix("TV ") || m.hasPrefix("PS5") || m.hasPrefix("durum: PS5") || m.hasPrefix("Oyun ")
            || m.hasPrefix("Okuma takıldı") || m.hasPrefix("Yazı okunamıyor")
    }

    /// TV ekran görüntüsü zamanı mı: yalnız Android TV, çeviri açıkken, hata beklemesi bitmişse.
    public static func shouldShootTV(now: TimeInterval, last: TimeInterval?, blockedUntil: TimeInterval?,
                                     disabled: Bool, isAndroidTV: Bool, translating: Bool, scale: Double) -> Bool {
        guard isAndroidTV, translating, !disabled else { return false }
        if let blockedUntil, now < blockedUntil { return false }
        return isDue(now: now, last: last, interval: tvShotInterval, scale: scale)
    }
}

/// Kareye çizilecekler (kare oranında kutular).
public struct DebugAnnotation: Sendable {
    public var readingArea: GameReading.Box?
    public var subtitleBox: GameReading.Box?
    /// TV'ye giden kutular: altyazı, ekran öğeleri, ek alanlar.
    public var tvBoxes: [NinoBox] = []
    public var read = ""
    public var translation = ""
    public init(readingArea: GameReading.Box? = nil, subtitleBox: GameReading.Box? = nil, tvBoxes: [NinoBox] = [],
                read: String = "", translation: String = "") {
        self.readingArea = readingArea
        self.subtitleBox = subtitleBox
        self.tvBoxes = tvBoxes
        self.read = read
        self.translation = translation
    }

    /// Resmi `rect`'e çizer, üstüne kutular: okuma bölgesi sarı kesikli, okunan altyazı kırmızı, TV kutuları camgöbeği;
    /// alt şeritte okunan ve çeviri (CG düzeni: y yukarı).
    public func draw(_ image: CGImage, in ctx: CGContext, rect: CGRect, fontSize: CGFloat) {
        ctx.draw(image, in: rect)
        func r(_ l: Double, _ t: Double, _ rr: Double, _ b: Double) -> CGRect {
            CGRect(x: rect.minX + l * rect.width, y: rect.minY + (1 - b) * rect.height,
                   width: (rr - l) * rect.width, height: (b - t) * rect.height)
        }
        let line = max(1.5, rect.width / 480)
        if let a = readingArea {
            ctx.setStrokeColor(CGColor(red: 1, green: 0.85, blue: 0, alpha: 1))
            ctx.setLineWidth(line)
            ctx.setLineDash(phase: 0, lengths: [line * 4, line * 3])
            ctx.stroke(r(a.left, a.top, a.right, a.bottom))
        }
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setStrokeColor(CGColor(red: 0, green: 0.85, blue: 1, alpha: 1))
        ctx.setLineWidth(line)
        for b in tvBoxes { ctx.stroke(r(b.left, b.top, b.right, b.bottom)) }
        if let b = subtitleBox {
            ctx.setStrokeColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 1))
            ctx.setLineWidth(line * 1.5)
            ctx.stroke(r(b.left, b.top, b.right, b.bottom))
        }
        let texts = [read.isEmpty ? nil : "OKUNAN: " + read, translation.isEmpty ? nil : "ÇEVİRİ: " + translation].compactMap { $0 }
        guard !texts.isEmpty else { return }
        let h = fontSize * 1.4
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.65))
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h * CGFloat(texts.count) + fontSize * 0.4))
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        ]
        for (i, t) in texts.reversed().enumerated() {
            let l = CTLineCreateWithAttributedString(NSAttributedString(string: String(t.prefix(160)), attributes: attrs))
            ctx.textPosition = CGPoint(x: rect.minX + fontSize * 0.5, y: rect.minY + fontSize * 0.5 + CGFloat(i) * h)
            CTLineDraw(l, ctx)
        }
    }
}

/// Kayıtçı: dört akışı tek, düşük öncelikli seri kuyrukta yazar. Kareler oranla seyreltilir; her akışta en çok bir
/// bekleyen iş vardır (yetişemezse kare atılır, birikmez). CPU ve bellek bütçesi aşılınca oranlar kendiliğinden düşer.
public final class DebugRecorder: @unchecked Sendable {
    public let layout: DebugRecordLayout
    public let limit: Int64
    private let queue = DispatchQueue(label: "nino.debug-kayit", qos: .utility)
    private let lock = NSLock()
    private let now: @Sendable () -> Date
    private let context: @Sendable () async -> DebugAnnotation

    // Kuyrukta kullanılanlar
    private let ps5: DebugVideoSegment
    private let mac: DebugVideoSegment
    private let log: DebugJournal
    private let messages: DebugJournal
    private var timer: DispatchSourceTimer?
    private var lastPrune: TimeInterval = 0
    private var lastRingTotal: Int64?
    private var lastRingAt: TimeInterval = 0
    private var freedSince: Int64 = 0
    private var started: Date

    // Kilitle korunanlar
    private var budget: DebugBudget
    private var measurement = DebugMeasurement()
    private var lastPS5: TimeInterval?
    private var lastMac: TimeInterval?
    private var lastEvent: TimeInterval?
    private var ps5Pending = false
    private var macPending = false
    private var pendingBytes: Int64 = 0
    private var eventWanted = false
    private var stopped = false

    public init(layout: DebugRecordLayout, limit: Int64 = DebugRing.defaultLimit, budget: DebugBudget.Limits = .init(),
                now: @escaping @Sendable () -> Date = { Date() },
                context: @escaping @Sendable () async -> DebugAnnotation) {
        self.layout = layout
        self.limit = limit
        self.now = now
        self.context = context
        self.budget = DebugBudget(limits: budget)
        ps5 = DebugVideoSegment(layout: layout, stream: .ps5, settings: DebugRecordingRules.ps5Video)
        mac = DebugVideoSegment(layout: layout, stream: .mac, settings: DebugRecordingRules.macVideo)
        log = DebugJournal(layout: layout, stream: .gunluk)
        messages = DebugJournal(layout: layout, stream: .mesaj)
        started = now()
        layout.createFolders()
        measurement.since = Self.ms(started)
        measurement.ringLimit = limit
    }

    deinit { timer?.cancel() }

    static func ms(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1000).rounded()) }

    public var scale: Double { lock.withLock { budget.scale } }
    public var currentMeasurement: DebugMeasurement { lock.withLock { measurement } }

    /// Bakım zamanlayıcısını açar (bütçe kararı, halka tampon, ölçüm dosyası).
    public func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + DebugRecordingRules.maintenanceInterval, repeating: DebugRecordingRules.maintenanceInterval,
                   leeway: .seconds(1))
        t.setEventHandler { [weak self] in self?.maintain() }
        t.resume()
        timer = t
    }

    /// Açık parçaları kapatır (uygulama kapanırken).
    public func stop() {
        lock.withLock { stopped = true }
        timer?.cancel()
        queue.sync {
            ps5.close()
            mac.close()
            log.close()
            messages.close()
            writeMeasurement()
        }
    }

    /// Bekleyen işlerin (kare çizimi dahil) bitmesini bekler, en çok `timeout` (testler).
    public func drain(timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while lock.withLock({ ps5Pending || macPending }), Date() < deadline { usleep(1000) }
        queue.sync {}
    }

    // MARK: Akışlar

    /// PS5 karesi (kaynaktan gelen her karede; çağıran beklemez).
    public func offerPS5(_ image: CGImage) {
        let date = now()
        let t = date.timeIntervalSince1970
        let (take, event) = lock.withLock { () -> (Bool, Bool) in
            guard !stopped,
                  DebugRecordingRules.isDue(now: t, last: lastPS5, interval: DebugRecordingRules.ps5Interval, scale: budget.scale)
            else { return (false, false) }
            // Zamanı gelmiş kare önceki iş bitmediği için alınmadı: yetişememe (kaynağın fazladan kareleri sayılmaz).
            guard !ps5Pending else {
                measurement.ps5Busy += 1
                return (false, false)
            }
            lastPS5 = t
            ps5Pending = true
            pendingBytes += Int64(image.width * image.height * 4)
            var e = false
            if eventWanted, budget.scale <= DebugRecordingRules.eventMaxScale,
               DebugRecordingRules.isDue(now: t, last: lastEvent, interval: DebugRecordingRules.eventGap, scale: 1) {
                eventWanted = false
                lastEvent = t
                e = true
            }
            return (true, e)
        }
        guard take else { return }
        let context = self.context
        Task.detached(priority: .utility) { [weak self] in
            let a = await context()
            self?.queue.async { self?.writePS5(image, annotation: a, at: date, event: event) }
        }
    }

    private func writePS5(_ image: CGImage, annotation a: DebugAnnotation, at date: Date, event: Bool) {
        let cpu = DebugMeasure.cpu {
            let ok = ps5.append(atMs: Self.ms(date)) { ctx, canvas in
                let rect = DebugVideoSegment.fit(CGSize(width: image.width, height: image.height), in: canvas)
                a.draw(image, in: ctx, rect: rect, fontSize: 15)
            }
            if event { writeEventFrame(image, annotation: a, at: date) }
            lock.withLock { if ok { measurement.ps5Frames += 1 } else { measurement.ps5Dropped += 1 } }
        }
        lock.withLock {
            budget.add(work: cpu)
            ps5Pending = false
            pendingBytes -= Int64(image.width * image.height * 4)
        }
    }

    private func writeEventFrame(_ image: CGImage, annotation a: DebugAnnotation, at date: Date) {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        a.draw(image, in: ctx, rect: CGRect(x: 0, y: 0, width: w, height: h), fontSize: CGFloat(max(14, h / 36)))
        guard let drawn = ctx.makeImage() else { return }
        let url = layout.folder(.olay).appendingPathComponent("\(Self.ms(date)).jpg")
        if DebugImageIO.write(drawn, to: url, type: .jpeg, quality: DebugRecordingRules.eventQuality) {
            lock.withLock { measurement.eventFrames += 1 }
        }
    }

    /// Mac penceresi zamanı geldi mi (ana iş parçacığı görüntü almadan önce sorar).
    public func wantsWindowFrame() -> Bool {
        let t = now().timeIntervalSince1970
        return lock.withLock {
            !stopped && !macPending
                && DebugRecordingRules.isDue(now: t, last: lastMac, interval: DebugRecordingRules.macInterval, scale: budget.scale)
        }
    }

    /// Mac penceresinin görüntüsü (`cpu`: ana iş parçacığında görüntü almanın süresi, bütçeye eklenir).
    public func offerWindow(_ image: CGImage, captureCPU: TimeInterval = 0) {
        let date = now()
        let take = lock.withLock { () -> Bool in
            budget.add(work: captureCPU)
            guard !stopped, !macPending else { return false }
            lastMac = date.timeIntervalSince1970
            macPending = true
            pendingBytes += Int64(image.width * image.height * 4)
            return true
        }
        guard take else { return }
        queue.async { [self] in
            let cpu = DebugMeasure.cpu {
                let ok = mac.append(atMs: Self.ms(date)) { ctx, canvas in
                    ctx.interpolationQuality = .medium
                    ctx.draw(image, in: DebugVideoSegment.fit(CGSize(width: image.width, height: image.height), in: canvas))
                }
                if ok { lock.withLock { measurement.macFrames += 1 } }
            }
            lock.withLock {
                budget.add(work: cpu)
                macPending = false
                pendingBytes -= Int64(image.width * image.height * 4)
            }
        }
    }

    /// Pencere zamanı geldi ama kaydedilecek pencere yok (pencere kapalı).
    public func windowMissing() {
        lock.withLock {
            lastMac = now().timeIntervalSince1970
            measurement.macMissing += 1
        }
    }

    /// TV'ye giden protokol mesajı (JSON) ve o an bağlı TV sayısı.
    public func tvMessage(_ json: String, tvCount: Int) {
        let t = Self.ms(now())
        queue.async { [self] in
            let cpu = DebugMeasure.cpu { messages.append(DebugTVMessage.line(t: t, tv: tvCount, json: json), atMs: t) }
            lock.withLock {
                budget.add(work: cpu)
                measurement.tvMessages += 1
            }
        }
    }

    /// Günlük satırı (`altyazi`, `remoteplay`, `durum`), günlüğün kendi zamanıyla.
    public func logLine(_ message: String, kind: String, at date: Date) {
        let t = Self.ms(date)
        if DebugRecordingRules.isEventLine(message) { lock.withLock { eventWanted = true } }
        queue.async { [self] in
            let line = "{\"t\":\(t),\"k\":\(DebugJournal.quote(kind)),\"m\":\(DebugJournal.quote(message))}"
            let cpu = DebugMeasure.cpu { log.append(line, atMs: t) }
            lock.withLock {
                budget.add(work: cpu)
                measurement.logLines += 1
            }
        }
    }

    /// Android TV ekran görüntüsü (PNG verisi olduğu gibi).
    public func tvShot(_ png: Data, at date: Date) {
        guard DebugImageIO.isPNG(png) else { return }
        queue.async { [self] in
            let url = layout.folder(.tv).appendingPathComponent("\(Self.ms(date)).png")
            if (try? png.write(to: url)) != nil { lock.withLock { measurement.tvShots += 1 } }
        }
    }

    // MARK: Bakım

    /// Bütçe kararı; 30 sn'de bir halka tampon ve `olcum.json` (kuyrukta).
    func maintain() {
        let date = now()
        let t = date.timeIntervalSince1970
        let memory = lock.withLock { pendingBytes } + ps5.bufferBytes * 4 + mac.bufferBytes * 4
        lock.withLock {
            budget.tick(now: t, memoryBytes: memory)
            measurement.recorderBytes = memory
        }
        guard t - lastPrune >= DebugRecordingRules.pruneEvery else { return }
        lastPrune = t
        prune(now: t)
        writeMeasurement()
    }

    func prune(now t: TimeInterval) {
        let protected = Set([ps5.openName, mac.openName, log.openName, messages.openName].compactMap { $0 })
        let freed = DebugRing.prune(layout, limit: limit, protected: protected)
        let total = DebugRecordIndex.scan(layout).reduce(Int64(0)) { $0 + $1.bytes }
        lock.withLock {
            if let last = lastRingTotal, t > lastRingAt {
                let grown = total - last + freed + freedSince
                measurement.bytesPerMinute = max(0, Int64(Double(grown) / (t - lastRingAt) * 60))
                measurement.bytesWritten += max(0, grown)
            }
            freedSince = 0
            lastRingTotal = total
            lastRingAt = t
            measurement.ringTotal = total
        }
    }

    func writeMeasurement() {
        let m = lock.withLock { () -> DebugMeasurement in
            measurement.at = Self.ms(now())
            measurement.cpuAverage = budget.averageFraction
            measurement.cpuLast = budget.lastFraction
            measurement.cpuPeak = budget.peakFraction
            measurement.scale = budget.scale
            measurement.slowDowns = budget.slowDowns
            measurement.processFootprint = DebugMeasure.footprint()
            return measurement
        }
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? e.encode(m) { try? d.write(to: layout.measureFile, options: .atomic) }
    }

    /// Testler: bakımı elle çalıştırır.
    func maintainNow() { queue.sync { maintain() } }
    func pruneNow() { queue.sync { prune(now: now().timeIntervalSince1970); writeMeasurement() } }
}
