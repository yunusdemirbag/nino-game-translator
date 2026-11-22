// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import CoreGraphics
import Darwin
import Foundation
import Network
import NinoCore

/// Otomatik teşhisin canlı tarafı: `DiagWatch`'a olayları verir, saati saniyede bir ilerletir, bellek/işlemci/ısı,
/// ağ, uyku ve ana iş parçacığı donmasını izler; tetiklenen kuralı ölçüm kuyruğuna `diag` olayı olarak ekler.
/// Gönderim `send` ile (canlıda `Telemetry.record`, testte sahte). Yerel `altyazi.log`'a yalnız kural ve sebep yazılır.
@MainActor
final class DiagMonitor {
    struct TVInfo: Sendable {
        var brand: TelemetryEvent.TVBrand?
        var model: String?
        var app: String?
    }

    private(set) var watch = DiagWatch()
    var send: (TelemetryEvent) -> Void
    var log: (String) -> Void
    var now: () -> Date = { Date() }
    /// Bildirime eklenecek TV (marka, model, TV'deki Nino sürümü) ve oyun kimliği.
    var tvInfo: () -> TVInfo? = { nil }
    var game: () -> String? = { nil }
    /// Donma yalnız bu doğruyken bildirilir (uygulama öndeyse ya da çeviri sürerken; App Nap yanlış alarm vermesin).
    var hangRelevant: () -> Bool = { true }
    /// Bildirim gidebilir mi (ayar: ortak havuz ve otomatik bildirim açık). Kapalıyken tetik atılır.
    var allowed: () -> Bool = { true }
    /// Sunucunun teşhis ayarı (dakikada bir).
    var remoteConfig: (() async -> TelemetryRemoteConfig.DiagConfig?)?

    private let directory: URL?
    private var lastTime: Double = 0
    private var loop: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var path: NWPathMonitor?
    private var lastNet: String?
    private var watchdog: HangWatchdog?
    private var resources = ResourceSampler()
    private var reportedFps = 0
    private var lastFpsAt: Date?
    private var frameProbe = FrameProbe()
    private var ticks = 0

    init(directory: URL?, send: @escaping (TelemetryEvent) -> Void, log: @escaping (String) -> Void) {
        self.directory = directory
        self.send = send
        self.log = log
        if let q = loadQuota() { watch.quota = q }
    }

    // MARK: Olaylar

    func record(_ signal: DiagSignal, at date: Date? = nil) {
        watch.enabled = allowed()
        let t = time(date)
        let before = watch.pending.count
        let out = watch.record(signal, at: t)
        noteNewTriggers(before: before)
        deliver(out)
    }

    /// Saat ilerledi (saniyede bir; testte elle).
    func tick(at date: Date? = nil) {
        watch.enabled = allowed()
        let t = time(date)
        let before = watch.pending.count
        let out = watch.advance(to: t)
        noteNewTriggers(before: before)
        deliver(out)
    }

    /// Bekleyen "tek kök" grubunu hemen gönderir (kapanış).
    func flush() {
        watch.enabled = allowed()
        deliver(watch.flush())
    }

    var context: DiagContext {
        get { watch.context }
        set { watch.context = newValue }
    }

    func apply(_ config: TelemetryRemoteConfig.DiagConfig?) { watch.apply(config) }

    private func time(_ date: Date?) -> Double {
        lastTime = max(lastTime, (date ?? now()).timeIntervalSince1970)
        return lastTime
    }

    private func noteNewTriggers(before: Int) {
        guard watch.pending.count > before else { return }
        for t in watch.pending[before...] {
            log("Otomatik teşhis: \(t.rule.rawValue) (\(t.cause)); bildirim 5 dk içinde kuyruğa")
        }
    }

    private func deliver(_ triggers: [DiagTrigger]) {
        for e in events(triggers) { send(e) }
    }

    /// Tetikler → ölçüm olayları (`t` = tetik anı); günlük sayaç diske yazılır.
    private func events(_ triggers: [DiagTrigger]) -> [TelemetryEvent] {
        guard !triggers.isEmpty else { return [] }
        saveQuota()
        var out: [TelemetryEvent] = []
        for t in triggers {
            let tv = tvInfo()
            var versions: [String: String] = [:]
            if let v = tv?.app { versions["tvApp"] = v }
            versions["core"] = NinoCore.version
            guard var event = TelemetryEvent.diag(rule: t.rule.rawValue, cause: t.cause, severity: t.severity,
                                                  state: t.state, trail: t.trail,
                                                  tv: tv.map { ($0.brand, $0.model, $0.app) }, game: game(),
                                                  versions: versions) else { continue }
            event.time = Int(t.at)
            out.append(event)
        }
        return out
    }

    // MARK: Kare, okuma, çeviri yardımcıları

    /// Oturumun saniyelik kare sayısı. Yalnız belirgin değişim (±5, ya da 0/1 sınırı) iz adımı olur.
    func framesPerSecond(_ fps: Int, at date: Date? = nil) {
        lastFpsAt = date ?? now()
        let crossed = (fps >= 1) != (reportedFps >= 1)
        guard crossed || abs(fps - reportedFps) >= 5 else { return }
        reportedFps = fps
        record(.ps5Frame(fps: fps), at: date)
    }

    /// Ara sıra gelen kare (≤ 1/sn): 5 sn'de bir parlaklık ve "hep aynı" ölçülür.
    func sampleFrame(_ image: CGImage, at date: Date? = nil) {
        let d = date ?? now()
        guard let r = frameProbe.sample(image, at: d) else { return }
        watch.context.frameLuma = r.luma
        watch.context.frameSame = r.same
    }

    // MARK: Canlı izleme

    /// Saniyelik döngü, ağ, uyku, kaynaklar ve donma bekçisi (uygulama ömrünce bir kez).
    func start() {
        guard loop == nil else { return }
        record(.appLaunch)
        if let previous = HangWatchdog.previousRunHang(directory: directory) {
            record(.hang(blockedSec: previous, previousRun: true))
        }
        let wd = HangWatchdog(directory: directory, hangSec: watch.limits.hangSec) { [weak self] sec in
            MainActor.assumeIsolated {
                guard let self, self.hangRelevant() else { return }
                // Tetik anı: donmanın başı + eşik.
                let at = self.now().addingTimeInterval(self.watch.limits.hangSec - Double(sec))
                self.record(.hang(blockedSec: sec, previousRun: false), at: at)
            }
        }
        wd.start()
        watchdog = wd
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.record(.sysSleep) }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.record(.sysWake) }
        })
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] p in
            let up = p.status == .satisfied
            let code = Self.netCode(p)
            Task { @MainActor in self?.netChanged(up: up, code: code) }
        }
        monitor.start(queue: DispatchQueue(label: "nino.diag.net"))
        path = monitor
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                await self.second()
            }
        }
    }

    /// Düzgün kapanış: donma işareti silinir, izleme durur; bekleyen "tek kök" bildirimi olay olarak döner (kapanışta
    /// ana iş parçacığı beklerken `send`'in görevi çalışamaz, çağıran doğrudan kaydeder).
    @discardableResult
    func stop() -> [TelemetryEvent] {
        loop?.cancel()
        loop = nil
        path?.cancel()
        path = nil
        watchdog?.stop()
        watchdog = nil
        for o in observers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        observers = []
        watch.enabled = allowed()
        return events(watch.flush())
    }

    private func second() async {
        ticks += 1
        // Kare gelmiyor: son saniyelik sayımdan 2 sn sonra 0 bildirilir (zamanı son karenin anı).
        if reportedFps >= 1, let last = lastFpsAt, now().timeIntervalSince(last) > 2 {
            reportedFps = 0
            record(.ps5Frame(fps: 0), at: last)
        }
        if ticks % 10 == 0, let s = resources.sample() {
            record(.memory(mb: s.memMB))
            if let c = s.cpu { record(.cpu(pct: c)) }
            record(.thermal(s.thermal))
        }
        if ticks % 60 == 1, let remote = remoteConfig {
            let config = await remote()
            if config != nil { apply(config) }
        }
        tick()
    }

    private func netChanged(up: Bool, code: String) {
        if !up {
            if lastNet != "none" { record(.netDown) }
            lastNet = "none"
            return
        }
        if lastNet == nil || lastNet == "none" {
            record(.netUp(code))
        } else if lastNet != code {
            record(.netChange(code))
        }
        lastNet = code
    }

    nonisolated static func netCode(_ p: NWPath) -> String {
        if p.usesInterfaceType(.wiredEthernet) { return "ethernet" }
        if p.usesInterfaceType(.wifi) { return "wifi" }
        if p.usesInterfaceType(.cellular) { return "cellular" }
        return "other"
    }

    // MARK: Günlük sınır sayacı (kurulum başına; telemetry/diag.json)

    private var quotaURL: URL? { directory?.appendingPathComponent("diag.json") }

    private func loadQuota() -> DiagQuota? {
        guard let url = quotaURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DiagQuota.self, from: data)
    }

    private func saveQuota() {
        guard let url = quotaURL, let data = try? JSONEncoder().encode(watch.quota) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Kare parlaklığı

/// Kareyi 8×8'e küçültüp ortalama parlaklığı ölçer; art arda 3 örnek aynıysa "donuk".
struct FrameProbe {
    private var lastAt: Date?
    private var previous: [UInt8] = []
    private var sameRun = 0

    mutating func sample(_ image: CGImage, at: Date) -> (luma: Int, same: Bool)? {
        if let l = lastAt, at.timeIntervalSince(l) < 5 { return nil }
        lastAt = at
        guard let pixels = Self.gray8x8(image) else { return nil }
        let luma = pixels.reduce(0) { $0 + Int($1) } / pixels.count
        let same = !previous.isEmpty && zip(previous, pixels).allSatisfy { abs(Int($0) - Int($1)) <= 1 }
        sameRun = same ? sameRun + 1 : 0
        previous = pixels
        return (luma, sameRun >= 2)
    }

    static func gray8x8(_ image: CGImage) -> [UInt8]? {
        var buf = [UInt8](repeating: 0, count: 64)
        let ok = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 8,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                return false
            }
            ctx.interpolationQuality = .low
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            return true
        }
        return ok ? buf : nil
    }
}

// MARK: - Bellek, işlemci, ısı

struct ResourceSampler {
    struct Sample { var memMB: Int; var cpu: Int?; var thermal: String }
    private var lastCPU: Double?
    private var lastWall: Double?

    mutating func sample() -> Sample? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let mem = Int(info.phys_footprint / 1_048_576)
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpuTime = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
            + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        let wall = ProcessInfo.processInfo.systemUptime
        var cpu: Int?
        if let c = lastCPU, let w = lastWall, wall > w {
            // Bütün çekirdeklere göre yüzde (tek çekirdeği dolduran okuma %90 sayılmasın).
            cpu = Int(((cpuTime - c) / (wall - w) / Double(max(1, ProcessInfo.processInfo.activeProcessorCount))) * 100)
        }
        lastCPU = cpuTime
        lastWall = wall
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "nominal"
        }
        return Sample(memMB: mem, cpu: cpu, thermal: thermal)
    }
}

// MARK: - Donma bekçisi

/// Ayrı iş parçacığından ana iş parçacığına yarım saniyede bir dokunur; `hangSec` boyunca yanıt gelmezse donma sayılır,
/// ana iş parçacığı dönünce süresiyle bildirilir. 5 sn'de bir `telemetry/hang.json`'a iki damga yazar (ana iş
/// parçacığının son yanıtı ve bekçinin son turu); düzgün kapanışta silinir. Bir sonraki açılışta dosya duruyor ve ana
/// damga bekçininkinden 60 sn'den eskiyse önceki çalışma askıda bitmiştir. Süre ölçümü uyku saymayan saatle.
final class HangWatchdog: @unchecked Sendable {
    private struct Stamp: Codable { var main: Double; var watch: Double }

    private let lock = NSLock()
    private let url: URL?
    private let hangNs: UInt64
    private let onHang: @Sendable (Int) -> Void
    private var lastPong = DispatchTime.now().uptimeNanoseconds
    private var lastPongWall = Date().timeIntervalSince1970
    private var blockedFrom: UInt64?
    private var pingOut = false
    private var running = false
    private var lastStamp: UInt64 = 0

    init(directory: URL?, hangSec: Double, onHang: @escaping @Sendable (Int) -> Void) {
        url = directory?.appendingPathComponent("hang.json")
        hangNs = UInt64(max(1, hangSec) * 1e9)
        self.onHang = onHang
    }

    /// Önceki çalışma askıda bittiyse donma süresi (sn); dosya okunup silinir.
    static func previousRunHang(directory: URL?) -> Int? {
        guard let url = directory?.appendingPathComponent("hang.json"), let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        guard let s = try? JSONDecoder().decode(Stamp.self, from: data), s.watch - s.main > 60 else { return nil }
        return Int(s.watch - s.main)
    }

    func start() {
        lock.withLock { running = true }
        let t = Thread { [weak self] in
            while true {
                do {
                    guard let s = self, s.lock.withLock({ s.running }) else { return }
                    s.turn()
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        t.name = "nino.diag.hang"
        t.qualityOfService = .utility
        t.start()
    }

    func stop() {
        lock.withLock { running = false }
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private func turn() {
        let now = DispatchTime.now().uptimeNanoseconds
        let (send, stampDue, stamp): (Bool, Bool, Stamp) = lock.withLock {
            if now - lastPong >= hangNs, blockedFrom == nil { blockedFrom = lastPong }
            let send = !pingOut
            if send { pingOut = true }
            let due = now - lastStamp >= 5_000_000_000
            if due { lastStamp = now }
            return (send, due, Stamp(main: lastPongWall, watch: Date().timeIntervalSince1970))
        }
        if send { DispatchQueue.main.async { [weak self] in self?.pong() } }
        if stampDue, let url, let data = try? JSONEncoder().encode(stamp) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    private func pong() {
        let now = DispatchTime.now().uptimeNanoseconds
        let blocked: Int? = lock.withLock {
            pingOut = false
            lastPong = now
            lastPongWall = Date().timeIntervalSince1970
            guard let from = blockedFrom else { return nil }
            blockedFrom = nil
            return Int((now - from) / 1_000_000_000)
        }
        if let blocked { onHang(blocked) }
    }
}
