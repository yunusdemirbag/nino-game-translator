// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import Network
import NinoCore
import UIKit

/// Uygulamanın bekçisi: olayları `DiagWatch`'a taşır, ağı, belleği, ısıyı ve ana iş parçacığını izler; tetiklenen
/// kuralı ölçüm kuyruğuna `diag` olayı olarak koyar. Ölçümün parçasıdır, ayrı kapatma düğmesi yoktur; sunucu kural
/// kural kapatabilir. Testlerde ve ekran karşılaştırmasında başlatılmaz (çağrılar boşa düşer).
final class AppDiagnosis: @unchecked Sendable {
    static let shared = AppDiagnosis()

    private let lock = NSLock()
    private var watch: DiagWatch?
    private var defaults: UserDefaults = .standard
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "nino.diag")
    private var path: NWPathMonitor?
    private var netKind = "wifi"

    // Kare bilgisi (görüntü bekçisi): saniyelik kare sayısı, ortalama parlaklık, kareler aynı mı.
    private var framesInWindow = 0
    private var windowStart = 0.0
    private var lastSample = 0.0
    private var luma: Int?
    private var lastPrint: [UInt8] = []
    private var frameSame = false

    private static let dayKey = "diagDay"
    private static let packKey = "diagPackFails"

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    func start(defaults: UserDefaults = .standard) {
        lock.lock()
        defer { lock.unlock() }
        guard watch == nil else { return }
        self.defaults = defaults
        let w = DiagWatch(launchedAt: now)
        if let data = defaults.data(forKey: Self.dayKey), let saved = try? JSONDecoder().decode(DiagWatch.DayCount.self, from: data) {
            w.dayCount = saved
        }
        w.packFails = defaults.dictionary(forKey: Self.packKey) as? [String: Int] ?? [:]
        w.context = { [unowned self] in self.contextLocked() }
        watch = w
        startMonitorsLocked()
    }

    // MARK: Girdiler (her iş parçacığından)

    func note(_ code: String, _ value: Int? = nil, detail: String? = nil) {
        run { $0.note(code, value, at: self.now, detail: detail) }
    }

    func frame(_ image: CGImage) {
        let t = now
        var sample = false
        lock.withLock {
            guard let watch else { return }
            watch.frame(at: t)
            framesInWindow += 1
            if t - lastSample >= 5 { lastSample = t; sample = true }
        }
        guard sample else { return }
        let print = Self.fingerprint(image)
        lock.withLock {
            frameSame = !lastPrint.isEmpty && print == lastPrint
            lastPrint = print
            luma = print.isEmpty ? nil : print.reduce(0) { $0 + Int($1) } / print.count
        }
    }

    private var lastTextSeen = 0.0

    /// Yazı tanıma boş olmayan metin döndürdü (`ocr.silent` sayacı; saniyede en çok bir kez).
    func textSeen() {
        let t = now
        let due: Bool = lock.withLock {
            guard t - lastTextSeen >= 1 else { return false }
            lastTextSeen = t
            return true
        }
        if due { note("ocr.text") }
    }

    func ocrStarted() { run { $0.ocrStarted(at: self.now); return [] } }
    func ocrFinished(ms: Int) { run { $0.ocrFinished(ms: ms, at: self.now); return [] } }
    func translated(totalMs: Int) { run { $0.translated(totalMs: totalMs, at: self.now) } }
    func providerRequest(ms: Int, failure: Int?) { run { $0.providerRequest(ms: ms, failure: failure, at: self.now) } }
    func packResult(_ id: String, ok: Bool) {
        run { $0.packResult(id, ok: ok, http: nil, at: self.now) }
        if let fails = lock.withLock({ watch?.packFails }) { defaults.set(fails, forKey: Self.packKey) }
    }

    private func run(_ body: (DiagWatch) -> [DiagReport]) {
        let reports: [DiagReport] = lock.withLock {
            guard let watch else { return [] }
            return body(watch)
        }
        send(reports)
    }

    private func send(_ reports: [DiagReport]) {
        guard !reports.isEmpty else { return }
        let day = lock.withLock { watch?.dayCount }
        if let day, let data = try? JSONEncoder().encode(day) { defaults.set(data, forKey: Self.dayKey) }
        for r in reports {
            AppTelemetry.record(.diag(rule: r.rule, cause: r.cause, severity: r.severity, state: r.state, trail: r.trail,
                                      versions: ["app": AppInfo.version]))
        }
    }

    // MARK: Bağlam

    private func contextLocked() -> [String: TelemetryValue] {
        var s: [String: TelemetryValue] = ["net": .string(netKind), "memMB": .int(Self.memoryMB())]
        if let luma { s["frameLuma"] = .int(luma) }
        s["frameSame"] = .bool(frameSame)
        s["thermal"] = .string(Self.thermal())
        return s
    }

    // MARK: İzleyiciler

    private func startMonitorsLocked() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] p in
            guard let self else { return }
            let kind = p.status != .satisfied ? "none" : p.usesInterfaceType(.wiredEthernet) ? "ethernet"
                : p.usesInterfaceType(.cellular) ? "cellular" : "wifi"
            self.lock.withLock { self.netKind = kind }
            self.run { $0.network(kind, at: self.now) }
        }
        monitor.start(queue: queue)
        path = monitor

        var tick = 0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            tick += 1
            let t = self.now
            self.run { $0.tick(at: t) }
            if tick % 10 == 0 {
                let fps: Int = self.lock.withLock {
                    let span = max(1, t - self.windowStart)
                    let f = Int((Double(self.framesInWindow) / span).rounded())
                    self.framesInWindow = 0
                    self.windowStart = t
                    return f
                }
                if fps > 0 { self.note("ps5.frame", fps) }
            }
            if tick % 30 == 0 {
                self.run { $0.resources(memMB: Self.memoryMB(), thermal: Self.thermal(), at: t) }
            }
            if tick % 120 == 0 {
                Task { [weak self] in
                    let config = await AppTelemetry.diagConfig()
                    self?.lock.withLock { self?.watch?.apply(config) }
                }
            }
        }
        timer.resume()
        self.timer = timer

        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [weak self] _ in
            self?.note("mem.high", Self.memoryMB())
        }
        startHangMonitor()
    }

    /// Ana iş parçacığı yanıt vermezse (5 sn) bir kez bildirir; izleyici ayrı iş parçacığındadır.
    private func startHangMonitor() {
        let thread = Thread { [weak self] in
            let pong = NSLock()
            var answered = ProcessInfo.processInfo.systemUptime
            var reported = false
            while self != nil {
                DispatchQueue.main.async {
                    pong.withLock { answered = ProcessInfo.processInfo.systemUptime }
                }
                let before = ProcessInfo.processInfo.systemUptime
                Thread.sleep(forTimeInterval: 1)
                // Bu iş parçacığı da durduysa (uygulama askıya alındı) ölçüm sayılmaz.
                if ProcessInfo.processInfo.systemUptime - before > 3 {
                    pong.withLock { answered = ProcessInfo.processInfo.systemUptime }
                    continue
                }
                let blocked = ProcessInfo.processInfo.systemUptime - pong.withLock { answered }
                if blocked >= 5, !reported {
                    reported = true
                    self?.run { $0.hang(blockedSec: blocked, at: ProcessInfo.processInfo.systemUptime) }
                } else if blocked < 2 {
                    reported = false
                }
            }
        }
        thread.name = "nino.diag.hang"
        thread.qualityOfService = .utility
        thread.start()
    }

    // MARK: Ölçümler

    static func memoryMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint >> 20) : 0
    }

    static func thermal() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "nominal"
        }
    }

    /// Karenin 8×8 gri küçük hâli (parlaklık ve "kareler aynı mı" için; kare saklanmaz, gönderilmez).
    static func fingerprint(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: 64)
        let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 8,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            return true
        }
        return ok ? pixels : []
    }
}

/// Çeviri hizmetini sarar: istek süresini ve hata durumunu (HTTP kodu; −1 zaman aşımı, −2 ağ yok, −3 başka) bekçiye bildirir.
struct TimedProvider: TranslationProvider {
    let base: TranslationProvider
    var name: String { base.name }

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        let started = ProcessInfo.processInfo.systemUptime
        func ms() -> Int { Int((ProcessInfo.processInfo.systemUptime - started) * 1000) }
        do {
            let result = try await base.translate(text, from: source, to: target)
            AppDiagnosis.shared.providerRequest(ms: ms(), failure: nil)
            return result
        } catch {
            // Zincir süre dolunca isteği iptal eder: uzun süren iptal zaman aşımıdır; kısa iptal (çeviri durdu) sayılmaz.
            let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
            if cancelled {
                if ms() >= 2500 { AppDiagnosis.shared.providerRequest(ms: ms(), failure: -1) }
                throw error
            }
            AppDiagnosis.shared.providerRequest(ms: ms(), failure: Self.code(error))
            throw error
        }
    }

    static func code(_ error: Error) -> Int {
        switch error {
        case TranslationProviderError.http(let status): return status
        case TranslationProviderError.timeout: return -1
        case let e as URLError where e.code == .timedOut: return -1
        case let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed].contains(e.code): return -2
        default: return -3
        }
    }
}
