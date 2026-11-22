// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

// Otomatik teşhis bekçisi (NinoCore docs/tarif/otomatik-teshis.md). Saf yapı: zaman dışarıdan verilir (Unix saniye ya
// da testte senaryo saniyesi), ağ, dosya, saat yok. Canlı bağlantı DiagMonitor.swift'te.
//
// Gizlilik: iz adımları yalnız [kaç sn önce, kod, sayı?]; `state` yalnız sayı, doğru/yanlış ve kod. Adres, ad, metin,
// günlük satırı buraya hiç girmez (paket kimliği yalnız bellekte sayaç anahtarıdır, olaya yazılmaz).

/// Kural kodları ve "tek kök" önceliği (baştaki en önemli).
enum DiagRule: String, CaseIterable, Sendable {
    case appHang = "app.hang"
    case ps5NoReturn = "ps5.no_return"
    case tvFlapping = "tv.flapping"
    case ocrStalled = "ocr.stalled"
    case trErrors = "tr.errors"
    case trSlow = "tr.slow"
    case ocrSilent = "ocr.silent"
    case appResources = "app.resources"
    case packDownload = "pack.download"

    var priority: Int { Self.allCases.firstIndex(of: self) ?? 99 }

    var severity: TelemetryEvent.DiagSeverity {
        switch self {
        case .ps5NoReturn, .ocrStalled, .appHang: return .error
        case .ocrSilent: return .info
        case .tvFlapping, .trSlow, .trErrors, .appResources, .packDownload: return .warn
        }
    }

    /// Yalnız çeviri oturumu sürerken bakılan kurallar.
    var needsSession: Bool {
        switch self {
        case .ps5NoReturn, .tvFlapping, .ocrSilent, .ocrStalled, .trSlow, .trErrors: return true
        case .appHang, .appResources, .packDownload: return false
        }
    }

    /// Ağ kuralları: ağ tamamen gidince susmazlar (sebepleri ağdır; gönderimi kuyruk bekletir).
    var isNetworkRule: Bool { self == .ps5NoReturn || self == .trErrors || self == .packDownload }
}

/// Eşikler: tarifteki varsayılanlar; sunucu `telemetry.diag.limits` ile değiştirir.
struct DiagLimits: Equatable, Sendable {
    var ps5NoReturnSec: Double = 180
    var tvFlapWindowMin: Double = 10
    var tvFlapCount: Int = 3
    var ocrSilentMin: Double = 15
    var ocrStallSec: Double = 10
    var ocrStallCount: Int = 3
    var ocrStallWindowMin: Double = 5
    var framesStoppedSec: Double = 30
    var trSlowP90Ms: Double = 3000
    var trSlowLines: Int = 50
    var trSlowMinLines: Int = 20
    var trErrorRate: Double = 0.30
    var trErrorWindow: Int = 40
    var trErrorMinRequests: Int = 10
    var hangSec: Double = 5
    var memHighMB: Double = 1500
    var cpuHighPct: Double = 90
    var resourcesSec: Double = 120
    var packFailCount: Int = 3
    var packFailHours: Double = 24
    var quietSec: Double = 120
    var launchQuietSec: Double = 60
    var resumeWindowSec: Double = 10
    var rootWindowSec: Double = 300
    var perDay: Int = 5
    /// Aynı sorun (kural) günde en çok bir kez bildirilir (tarifte 2; Mac'te kullanıcı kararıyla 1).
    var perRulePerDay: Int = 1

    init() {}

    /// Sunucu ayarı. Anahtar tarifteki adla (`ps5NoReturnSec`) ya da kural önekiyle (`tr.slow.p90Ms`) gelebilir;
    /// bilinmeyenler yok sayılır.
    init(_ config: TelemetryRemoteConfig.DiagConfig?) {
        self.init()
        guard let config else { return }
        func v(_ names: String...) -> Double? {
            for n in names { if let x = config.limits[n], x.isFinite, x >= 0 { return x } }
            return nil
        }
        if let x = v("ps5NoReturnSec", "ps5.no_return.sec") { ps5NoReturnSec = x }
        if let x = v("tvFlapWindowMin", "tv.flapping.windowMin") { tvFlapWindowMin = x }
        if let x = v("tvFlapCount", "tv.flapping.count") { tvFlapCount = max(1, Int(x)) }
        if let x = v("ocrSilentMin", "ocr.silent.min") { ocrSilentMin = x }
        if let x = v("ocrStallSec", "ocr.stalled.sec") { ocrStallSec = x }
        if let x = v("trSlowP90Ms", "tr.slow.p90Ms") { trSlowP90Ms = x }
        if let x = v("trErrorRate", "tr.errors.rate") { trErrorRate = x > 1 ? x / 100 : x }
        if let x = v("hangSec", "app.hang.sec") { hangSec = x }
        if let x = v("memHighMB", "app.resources.memMB") { memHighMB = x }
        if let x = v("cpuHighPct", "app.resources.cpu") { cpuHighPct = x }
    }
}

/// PS5 kopma sebebi işareti (bağlantı katmanının bildirdiği).
enum DiagPS5Cause: String, Sendable { case networkLost = "network_lost", standby = "ps5_standby", closed = "ps5_closed",
                                          kicked, stalled }

/// Çevirinin nereden geldiği (tr.slow payları).
enum DiagOrigin: String, Sendable { case pack, pool, cache, provider, device }

/// Bekçinin gördüğü olaylar. Çoğu iz adımı olarak da halkaya girer.
enum DiagSignal: Equatable, Sendable {
    case sessionStart, sessionStop
    case appLaunch, appBackground, appForeground, sysSleep, sysWake
    case netUp(String?), netDown, netChange(String?)
    case ps5Connect, ps5Drop(DiagPS5Cause?), ps5Retry(Int)
    /// Kopmadan sonra öğrenilen sebep (yeniden denemede PS5 "dinlenmede" dedi gibi): bekleyen kopmanın sebebi boşsa doldurur.
    case ps5Cause(DiagPS5Cause)
    /// Kare hızı değişti (0: kare gelmiyor).
    case ps5Frame(fps: Int)
    case tvConnect
    /// Bu tarafın kapattığı TV bağlantısı: kopma sayılmaz, yalnız bağlı TV sayısı düşer.
    case tvLocalClose
    /// TV kopması: ölçümdeki `tv_drop.code` ve bağlı kalınan süre.
    case tvDrop(code: String?, upSec: Int)
    case ocrText, ocrEmpty
    /// Bir okumanın süresi (eşiği aşanlar takılma sayılır).
    case ocrSlow(ms: Int)
    /// Okuma bekçisi isteği bıraktı (dönmedi).
    case ocrStuck
    /// Çeviri hizmetinin bir isteği: başarılı ya da HTTP durumu (0: ağ yok, 408: zaman aşımı).
    case trOK, trError(http: Int)
    /// Gösterilen satırın toplam gecikmesi.
    case line(ms: Int, origin: DiagOrigin)
    case memory(mb: Int), cpu(pct: Int)
    /// `nominal` · `fair` · `serious` · `critical`.
    case thermal(String)
    /// Ana iş parçacığı yanıt vermedi; `previousRun`: önceki çalışma askıda bitti (açılışta bildirilir).
    case hang(blockedSec: Int, previousRun: Bool)
    /// Paket indirilemedi / indi (kimlik yalnız sayaç anahtarı; `*`: hepsi indi).
    case packFail(id: String, http: Int?), packOK(id: String)

    /// Halkadaki iz adımı (kod, sayı); nil: iz adımı değil.
    func step(limits: DiagLimits) -> (String, Int?)? {
        switch self {
        case .sessionStart: return ("session.start", nil)
        case .sessionStop: return ("session.stop", nil)
        case .appLaunch: return ("app.launch", nil)
        case .appBackground: return ("app.background", nil)
        case .appForeground: return ("app.foreground", nil)
        case .sysSleep: return ("sys.sleep", nil)
        case .sysWake: return ("sys.wake", nil)
        case .netUp: return ("net.up", nil)
        case .netDown: return ("net.down", nil)
        case .netChange: return ("net.change", nil)
        case .ps5Connect: return ("ps5.connect", nil)
        case .ps5Cause, .tvLocalClose: return nil
        case .ps5Drop: return ("ps5.drop", nil)
        case let .ps5Retry(n): return ("ps5.retry", n)
        case let .ps5Frame(fps): return ("ps5.frame", fps)
        case .tvConnect: return ("tv.connect", nil)
        case let .tvDrop(_, up): return ("tv.drop", up)
        case .ocrText: return ("ocr.text", nil)
        case .ocrEmpty: return ("ocr.empty", nil)
        case let .ocrSlow(ms): return Double(ms) >= limits.ocrStallSec * 1000 / 2 ? ("ocr.slow", ms) : nil
        case .ocrStuck: return ("ocr.slow", Int(limits.ocrStallSec * 1000))
        case .trOK: return ("tr.ok", nil)
        case let .trError(http): return ("tr.error", http)
        case let .line(ms, _): return Double(ms) > limits.trSlowP90Ms ? ("tr.slow", ms) : nil
        case let .memory(mb): return Double(mb) > limits.memHighMB ? ("mem.high", mb) : nil
        case let .cpu(pct): return Double(pct) > limits.cpuHighPct ? ("cpu.high", pct) : nil
        case let .thermal(t): return t == "serious" || t == "critical" ? ("sys.thermal", t == "critical" ? 3 : 2) : nil
        case let .hang(sec, _): return ("app.hang", sec)
        case let .packFail(_, http): return ("pack.fail", http)
        case .packOK: return nil
        }
    }

    /// Senaryo dosyasındaki iz kodundan olay (`diag-scenarios.json`); tanınmayan kod nil.
    init?(code: String, value: Int?, dropCode: String? = nil) {
        switch code {
        case "session.start": self = .sessionStart
        case "session.stop": self = .sessionStop
        case "app.launch": self = .appLaunch
        case "app.background": self = .appBackground
        case "app.foreground": self = .appForeground
        case "sys.sleep": self = .sysSleep
        case "sys.wake": self = .sysWake
        case "net.up": self = .netUp(nil)
        case "net.down": self = .netDown
        case "net.change": self = .netChange(nil)
        case "ps5.connect": self = .ps5Connect
        case "ps5.drop": self = .ps5Drop(nil)
        case "ps5.retry": self = .ps5Retry(value ?? 1)
        case "ps5.frame": self = .ps5Frame(fps: value ?? 0)
        case "tv.connect": self = .tvConnect
        case "tv.drop": self = .tvDrop(code: dropCode, upSec: value ?? 0)
        case "ocr.text": self = .ocrText
        case "ocr.empty": self = .ocrEmpty
        case "ocr.slow": self = .ocrSlow(ms: value ?? 0)
        case "tr.ok": self = .trOK
        case "tr.error": self = .trError(http: value ?? 0)
        case "tr.slow": self = .line(ms: value ?? 0, origin: .provider)
        case "mem.high": self = .memory(mb: value ?? 0)
        case "cpu.high": self = .cpu(pct: value ?? 0)
        case "pack.fail": self = .packFail(id: "pack", http: value)
        default: return nil
        }
    }
}

/// Bekçinin dışarıdan öğrendiği sabit durum (kare parlaklığı, okuma alanı, TV yolu, çevirmen).
struct DiagContext: Equatable, Sendable {
    /// Karelerin ortalama parlaklığı (0–255).
    var frameLuma: Int?
    /// Kareler hep aynı mı.
    var frameSame = false
    /// Okuma alanı elle seçildi.
    var regionManual = false
    /// `nino` · `legacy`.
    var proto: String?
    /// En çok kullanılan çevirmenin kodu (`deepl`, `gemini`, `device`…).
    var provider: String?
}

/// Tetiklenen kural: gönderilecek bildirimin bütün alanları (ölçüm olayına `DiagMonitor` çevirir).
struct DiagTrigger: Equatable, Sendable {
    var rule: DiagRule
    var cause: String
    /// Koşulun ilk sağlandığı an.
    var at: Double
    var state: [String: TelemetryValue]
    var trail: [TelemetryEvent.DiagStep]
    var severity: TelemetryEvent.DiagSeverity { rule.severity }
}

/// Günlük sınır sayacı (kurulum başına; DiagMonitor diske yazar).
struct DiagQuota: Codable, Equatable, Sendable {
    var day = 0
    var total = 0
    var perRule: [String: Int] = [:]
}

struct DiagWatch: Sendable {
    struct Step: Equatable, Sendable {
        var at: Double
        var code: String
        var value: Int?
    }

    static let ringSeconds: Double = 600
    static let ringMax = 200
    static let trailMax = 40

    var limits = DiagLimits()
    /// Sunucunun kapattığı kurallar.
    var off: Set<String> = []
    var context = DiagContext()
    var quota = DiagQuota()
    /// Kullanıcı ayarı: kapalıyken tetikler gönderilmez ve günlük sayaçtan düşmez (ortak havuz ya da otomatik
    /// bildirim kapalı).
    var enabled = true

    private(set) var ring: [Step] = []
    private(set) var pending: [DiagTrigger] = []
    private var groupStart: Double?

    // Genel durum
    private(set) var sessionOn = false
    private var sessionStartAt: Double?
    private var launchAt: Double?
    private var asleep = false
    private var sleepWakeAt: Double?
    private var stopAt: Double?
    private var inBackground = false
    private var foregroundAt: Double?
    private(set) var netDown = false
    private var net = "unknown"
    private var firedSession: Set<DiagRule> = []
    private var lines = 0
    private var memMB: Int?
    private var cpuPct: Int?
    private var thermal: String?

    // PS5 ve kareler
    private var ps5Up = false
    private var ps5Pending: (at: Double, cause: DiagPS5Cause?)?
    private var retries = 0
    private var fps = 0
    private var lastFps = 0
    private var silenceFrom: Double?
    private var zeroSince: Double?
    private var ocrStalls: [Double] = []
    private var lastOcrMs: Int?
    private var ocrSamples: [Int] = []

    // TV
    private var tvCount = 0
    private var tvDrops: [(at: Double, code: String, up: Int)] = []

    // Çeviri
    private var trResults: [(at: Double, http: Int?)] = []
    private var latencies: [(ms: Int, origin: DiagOrigin)] = []

    // Kaynaklar ve paketler
    private var memHighSince: Double?
    private var cpuHighSince: Double?
    private var thermalSince: Double?
    private var packFails: [String: (count: Int, first: Double, http: Int?)] = [:]

    init(limits: DiagLimits = DiagLimits(), off: Set<String> = []) {
        self.limits = limits
        self.off = off
    }

    /// Sunucu ayarı (`telemetry.diag`).
    mutating func apply(_ config: TelemetryRemoteConfig.DiagConfig?) {
        limits = DiagLimits(config)
        off = Set(config?.off ?? [])
    }

    // MARK: Olaylar

    /// Olayı kaydeder. Önce saat `at`'e ilerletilir; gönderilmesi gereken bildirimler döner.
    mutating func record(_ signal: DiagSignal, at: Double) -> [DiagTrigger] {
        var out = advance(to: at)
        if let (code, value) = signal.step(limits: limits) { push(Step(at: at, code: code, value: value)) }
        switch signal {
        case .sessionStart:
            sessionOn = true
            sessionStartAt = at
            firedSession = []
            tvCount = 0
            lines = 0
            tvDrops = []
            trResults = []
            latencies = []
            ocrStalls = []
            ps5Pending = nil
            silenceFrom = fps >= 1 ? at : nil
        case .sessionStop:
            sessionOn = false
            stopAt = at
            ps5Pending = nil
            silenceFrom = nil
            zeroSince = nil
        case .appLaunch:
            launchAt = at
        case .sysSleep:
            asleep = true
            sleepWakeAt = at
            resetCounters(at: at)
        case .sysWake:
            asleep = false
            sleepWakeAt = at
            resetCounters(at: at)
        case .appBackground:
            inBackground = true
            resetCounters(at: at, keepTV: true)
        case .appForeground:
            inBackground = false
            foregroundAt = at
        case let .netUp(code):
            netDown = false
            if let code { net = code } else if net == "none" { net = "unknown" }
        case .netDown:
            netDown = true
            net = "none"
        case let .netChange(code):
            if let code { net = code }
        case .ps5Connect:
            ps5Up = true
            ps5Pending = nil
            retries = 0
        case let .ps5Drop(cause):
            ps5Up = false
            zeroSince = nil
            if ps5Pending == nil, sessionOn, !isQuiet(.ps5NoReturn, at: at) { ps5Pending = (at, cause) }
        case let .ps5Retry(n):
            retries = n
        case let .ps5Cause(cause):
            if let p = ps5Pending, p.cause == nil { ps5Pending = (p.at, cause) }
        case .tvLocalClose:
            tvCount = max(0, tvCount - 1)
        case let .ps5Frame(newFps):
            if newFps >= 1, fps < 1 { silenceFrom = sessionOn ? at : nil }
            if newFps < 1 {
                silenceFrom = nil
                if fps >= 1 || zeroSince == nil { zeroSince = at }
            } else {
                zeroSince = nil
                lastFps = newFps
            }
            fps = newFps
        case .ocrText:
            if fps >= 1, sessionOn { silenceFrom = at }
        case .ocrEmpty:
            break
        case let .ocrSlow(ms):
            lastOcrMs = ms
            ocrSamples.append(ms)
            if ocrSamples.count > 50 { ocrSamples.removeFirst(ocrSamples.count - 50) }
            if Double(ms) >= limits.ocrStallSec * 1000 { out += stall(at: at) }
        case .ocrStuck:
            out += stall(at: at)
        case .trOK, .trError:
            guard sessionOn, !isQuiet(.trErrors, at: at) else { break }
            var http: Int?
            if case let .trError(h) = signal { http = h }
            trResults.append((at, http))
            if trResults.count > limits.trErrorWindow { trResults.removeFirst(trResults.count - limits.trErrorWindow) }
            out += checkErrors(at: at)
        case let .line(ms, origin):
            lines += 1
            guard sessionOn, !isQuiet(.trSlow, at: at) else { break }
            latencies.append((ms, origin))
            if latencies.count > limits.trSlowLines { latencies.removeFirst(latencies.count - limits.trSlowLines) }
            out += checkSlow(at: at)
        case .tvConnect:
            tvCount += 1
        case let .tvDrop(code, up):
            tvCount = max(0, tvCount - 1)
            guard sessionOn, !isQuiet(.tvFlapping, at: at) else { break }
            tvDrops.append((at, tvCode(code, at: at), up))
            out += checkFlapping(at: at)
        case let .memory(mb):
            memMB = mb
            memHighSince = Double(mb) > limits.memHighMB ? (memHighSince ?? at) : nil
        case let .cpu(pct):
            cpuPct = pct
            cpuHighSince = Double(pct) > limits.cpuHighPct ? (cpuHighSince ?? at) : nil
        case let .thermal(t):
            thermal = t
            thermalSince = (t == "serious" || t == "critical") ? (thermalSince ?? at) : nil
        case let .hang(sec, previous):
            if Double(sec) >= limits.hangSec {
                var s = common(at: at)
                s["blockedSec"] = .int(sec)
                out += trigger(.appHang, cause: "main_thread", at: at, state: s, ignoreQuiet: previous)
            }
        case let .packFail(id, http):
            var f = packFails[id] ?? (0, at, nil)
            f.count += 1
            f.http = http ?? f.http
            packFails[id] = f
            if f.count >= limits.packFailCount || at - f.first >= limits.packFailHours * 3600 {
                packFails[id] = nil
                var s = common(at: at)
                s["attempts"] = .int(f.count)
                if let h = f.http { s["http"] = .int(h) }
                out += trigger(.packDownload, cause: packCause(f.http), at: at, state: s)
            }
        case let .packOK(id):
            if id == "*" { packFails = [:] } else { packFails[id] = nil }
        }
        return out
    }

    /// Saat ilerledi: süreye bağlı kurallar (kopma + 180 sn, 15 dk sessizlik, 30 sn kare yok, 2 dk kaynak) ve
    /// "tek kök" penceresinin dolması.
    mutating func advance(to t: Double) -> [DiagTrigger] {
        var out: [DiagTrigger] = []
        if let p = ps5Pending, t >= p.at + limits.ps5NoReturnSec {
            ps5Pending = nil
            let at = p.at + limits.ps5NoReturnSec
            var s = common(at: at)
            s["retries"] = .int(retries)
            s["lastFps"] = .int(lastFps)
            out += trigger(.ps5NoReturn, cause: ps5Cause(p), at: at, state: s)
        }
        if sessionOn, fps >= 1, let from = silenceFrom, t >= from + limits.ocrSilentMin * 60 {
            let at = from + limits.ocrSilentMin * 60
            silenceFrom = at
            var s = common(at: at)
            if let l = context.frameLuma { s["frameLuma"] = .int(l) }
            s["frameSame"] = .bool(context.frameSame)
            s["region"] = .string(context.regionManual ? "manual" : "auto")
            if let ms = lastOcrMs { s["ocrMs"] = .int(ms) }
            out += trigger(.ocrSilent, cause: silentCause, at: at, state: s)
        }
        if sessionOn, ps5Up, fps < 1, let z = zeroSince, t >= z + limits.framesStoppedSec {
            zeroSince = nil
            let at = z + limits.framesStoppedSec
            out += trigger(.ocrStalled, cause: "frames_stopped", at: at, state: stalledState(at: at))
        }
        for (since, cause) in [(thermalSince, "thermal"), (memHighSince, "memory_high"), (cpuHighSince, "cpu_high")] {
            guard let since, t >= since + limits.resourcesSec else { continue }
            let at = since + limits.resourcesSec
            switch cause {
            case "thermal": thermalSince = nil
            case "memory_high": memHighSince = nil
            default: cpuHighSince = nil
            }
            var s = common(at: at)
            if let c = cpuPct { s["cpu"] = .int(c) }
            if let th = thermal { s["thermal"] = .string(th) }
            out += trigger(.appResources, cause: cause, at: at, state: s)
        }
        if let g = groupStart, t >= g + limits.rootWindowSec { out += emitGroup() }
        return out
    }

    /// Bekleyen "tek kök" grubunu hemen bırakır (kapanış ve testler).
    mutating func flush() -> [DiagTrigger] { emitGroup() }

    // MARK: Kurallar

    private mutating func stall(at: Double) -> [DiagTrigger] {
        ocrStalls.append(at)
        ocrStalls.removeAll { at - $0 > limits.ocrStallWindowMin * 60 }
        guard ocrStalls.count >= limits.ocrStallCount else { return [] }
        ocrStalls = []
        return trigger(.ocrStalled, cause: "ocr_hang", at: at, state: stalledState(at: at))
    }

    private func stalledState(at: Double) -> [String: TelemetryValue] {
        var s = common(at: at)
        if let ms = lastOcrMs { s["ocrMs"] = .int(ms) }
        if let c = cpuPct { s["cpu"] = .int(c) }
        return s
    }

    private mutating func checkErrors(at: Double) -> [DiagTrigger] {
        let n = trResults.count
        let errors = trResults.compactMap(\.http)
        guard n >= limits.trErrorMinRequests, Double(errors.count) / Double(n) > limits.trErrorRate else { return [] }
        var s = common(at: at)
        s["errors"] = .int(errors.count)
        s["requests"] = .int(n)
        if let p = context.provider { s["provider"] = .string(p) }
        if let h = Self.mostCommon(errors) { s["http"] = .int(h) }
        return trigger(.trErrors, cause: errorCause(errors), at: at, state: s)
    }

    private func errorCause(_ errors: [Int]) -> String {
        if netDown { return "offline" }
        func kind(_ h: Int) -> String {
            switch h {
            case 0: return "offline"
            case 401, 403: return "auth"
            case 402, 429, 456: return "quota"
            case 408, 504, 524: return "timeout"
            case 500...599: return "server"
            default: return "unknown"
            }
        }
        return Self.mostCommon(errors.map(kind), order: ["quota", "auth", "offline", "server", "timeout"]) ?? "unknown"
    }

    private mutating func checkSlow(at: Double) -> [DiagTrigger] {
        guard latencies.count >= limits.trSlowMinLines else { return [] }
        let all = latencies.map(\.ms)
        guard let p90 = Self.percentile(all, 0.9), Double(p90) > limits.trSlowP90Ms else { return [] }
        let n = Double(latencies.count)
        let providerLines = latencies.filter { $0.origin == .provider || $0.origin == .device }.map(\.ms)
        let poolLines = latencies.filter { $0.origin == .pool }.map(\.ms)
        let providerShare = Double(providerLines.count) / n, poolShare = Double(poolLines.count) / n
        let ocrP90 = Self.percentile(ocrSamples, 0.9)
        let cause: String
        if providerShare >= 0.5, let p = Self.percentile(providerLines, 0.9), Double(p) > limits.trSlowP90Ms {
            cause = "provider_slow"
        } else if poolShare >= 0.5, let p = Self.percentile(poolLines, 0.9), Double(p) > limits.trSlowP90Ms {
            cause = "pool_slow"
        } else if let o = ocrP90, o > 1500 {
            cause = "device_busy"
        } else {
            cause = "network_slow"
        }
        var s = common(at: at)
        s["p50"] = .int(Self.percentile(all, 0.5) ?? 0)
        s["p90"] = .int(p90)
        if let p = context.provider { s["provider"] = .string(p) }
        s["providerShare"] = .double((providerShare * 100).rounded() / 100)
        s["poolShare"] = .double((poolShare * 100).rounded() / 100)
        if let o = ocrP90 { s["ocrP90"] = .int(o) }
        return trigger(.trSlow, cause: cause, at: at, state: s)
    }

    /// Kopma nedeni → kural sebebi. `resume`: öne gelişten sonraki 10 sn içinde ve katman nedeni bilmiyorsa.
    private func tvCode(_ raw: String?, at: Double) -> String {
        switch raw {
        case "write_error", "timeout", "closed", "resume", "network_change", "replaced": return raw!
        case "tv_closed", "close": return "closed"
        case "network_lost": return "network_change"
        default:
            if let f = foregroundAt, at >= f, at - f <= limits.resumeWindowSec { return "resume" }
            return "other"
        }
    }

    private mutating func checkFlapping(at: Double) -> [DiagTrigger] {
        tvDrops.removeAll { at - $0.at >= limits.tvFlapWindowMin * 60 }
        guard tvDrops.count >= limits.tvFlapCount else { return [] }
        let codes = tvDrops.map(\.code)
        var cause = "mixed"
        if let best = Self.mostCommon(codes), codes.filter({ $0 == best }).count * 2 > codes.count {
            cause = best == "other" ? "unknown" : best
        }
        var s = common(at: at)
        s["drops"] = .int(tvDrops.count)
        s["tvCount"] = .int(tvCount)
        if let p = context.proto { s["proto"] = .string(p) }
        s["avgUpSec"] = .int(tvDrops.map(\.up).reduce(0, +) / max(1, tvDrops.count))
        let fired = trigger(.tvFlapping, cause: cause, at: at, state: s)
        if !fired.isEmpty || firedSession.contains(.tvFlapping) { tvDrops = [] }
        return fired
    }

    private func ps5Cause(_ p: (at: Double, cause: DiagPS5Cause?)) -> String {
        if let c = p.cause { return c.rawValue }
        if netDown { return DiagPS5Cause.networkLost.rawValue }
        return "timeout"
    }

    private var silentCause: String {
        if let l = context.frameLuma, l <= 16 { return "video_black" }
        if context.frameSame { return "video_black" }
        if context.regionManual { return "region_wrong" }
        return "no_text"
    }

    private func packCause(_ http: Int?) -> String {
        if netDown { return "offline" }
        switch http {
        case let h? where (400...499).contains(h): return "http_4xx"
        case let h? where (500...599).contains(h): return "http_5xx"
        case 0?: return "offline"
        default: return "unknown"
        }
    }

    // MARK: Susturma, tetik, tek kök, sınırlar

    /// Uyku/uyanma, arka plan (TV kuralı hariç), kullanıcının durdurması, açılışın ilk 60 sn'si ve (ağ dışı kurallarda)
    /// ağın tamamen gitmesi.
    func isQuiet(_ rule: DiagRule, at: Double) -> Bool {
        if let l = launchAt, at >= l, at - l < limits.launchQuietSec { return true }
        if asleep { return true }
        if let w = sleepWakeAt, at - w < limits.quietSec { return true }
        if let s = stopAt, at - s < limits.quietSec { return true }
        if rule != .tvFlapping {
            if inBackground { return true }
            if let f = foregroundAt, at - f < limits.quietSec { return true }
        }
        if netDown, !rule.isNetworkRule { return true }
        return false
    }

    private mutating func resetCounters(at: Double, keepTV: Bool = false) {
        ps5Pending = nil
        if !keepTV { tvDrops = [] }
        trResults = []
        latencies = []
        ocrStalls = []
        zeroSince = nil
        silenceFrom = (sessionOn && fps >= 1) ? at : nil
        memHighSince = nil
        cpuHighSince = nil
        thermalSince = nil
    }

    private mutating func trigger(_ rule: DiagRule, cause: String, at: Double, state: [String: TelemetryValue],
                                  ignoreQuiet: Bool = false) -> [DiagTrigger] {
        guard !off.contains(rule.rawValue), !firedSession.contains(rule) else { return [] }
        if rule.needsSession, !sessionOn { return [] }
        if !ignoreQuiet, isQuiet(rule, at: at) { return [] }
        firedSession.insert(rule)
        let t = DiagTrigger(rule: rule, cause: cause, at: at, state: state, trail: trail(at: at))
        var out: [DiagTrigger] = []
        if let g = groupStart, at >= g + limits.rootWindowSec { out = emitGroup() }
        if groupStart == nil { groupStart = at }
        pending.append(t)
        return out
    }

    /// Penceredeki en öncelikli kural gider; öbürleri onun izine adım olarak eklenir.
    private mutating func emitGroup() -> [DiagTrigger] {
        defer { pending = []; groupStart = nil }
        guard var winner = pending.min(by: { ($0.rule.priority, $0.at) < ($1.rule.priority, $1.at) }) else { return [] }
        for other in pending where other.rule != winner.rule {
            winner.trail.append(TelemetryEvent.DiagStep(max(-3600, min(0, Int((other.at - winner.at).rounded()))),
                                                        other.rule.rawValue))
        }
        winner.trail = Array(winner.trail.suffix(Self.trailMax))
        guard enabled else { return [] }
        let day = Int((winner.at / 86_400).rounded(.down))
        if quota.day != day { quota = DiagQuota(day: day) }
        guard quota.total < limits.perDay, quota.perRule[winner.rule.rawValue, default: 0] < limits.perRulePerDay else {
            return []
        }
        quota.total += 1
        quota.perRule[winner.rule.rawValue, default: 0] += 1
        return [winner]
    }

    /// Tetikten önceki son adımlar (en çok 40, eskiden yeniye, saniye −3600…0).
    private func trail(at: Double) -> [TelemetryEvent.DiagStep] {
        ring.filter { $0.at <= at && at - $0.at <= 3600 }.suffix(Self.trailMax).map {
            TelemetryEvent.DiagStep(Int(($0.at - at).rounded()), $0.code, $0.value)
        }
    }

    private mutating func push(_ s: Step) {
        ring.append(s)
        ring.removeAll { s.at - $0.at > Self.ringSeconds }
        if ring.count > Self.ringMax { ring.removeFirst(ring.count - Self.ringMax) }
    }

    /// Her bildirimde olan durum: PS5, TV, ağ, oturum süresi, satır, kare hızı, bellek.
    private func common(at: Double) -> [String: TelemetryValue] {
        var s: [String: TelemetryValue] = [
            "ps5": .string(ps5Up ? "up" : "down"),
            "tv": .string(tvCount > 0 ? "up" : "down"),
            "net": .string(net),
            "lines": .int(lines),
            "fps": .int(fps),
        ]
        if let start = sessionStartAt, sessionOn { s["sessionMin"] = .int(max(0, Int((at - start) / 60))) }
        if let m = memMB { s["memMB"] = .int(m) }
        return s
    }

    // MARK: Yardımcılar

    static func percentile(_ values: [Int], _ p: Double) -> Int? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let i = min(s.count - 1, max(0, Int((Double(s.count) * p).rounded(.up)) - 1))
        return s[i]
    }

    static func mostCommon<T: Hashable>(_ values: [T], order: [T] = []) -> T? {
        guard !values.isEmpty else { return nil }
        var counts: [T: Int] = [:]
        var first: [T: Int] = [:]
        for (i, v) in values.enumerated() {
            counts[v, default: 0] += 1
            if first[v] == nil { first[v] = i }
        }
        return counts.keys.max { a, b in
            if counts[a]! != counts[b]! { return counts[a]! < counts[b]! }
            let ra = order.firstIndex(of: a) ?? order.count, rb = order.firstIndex(of: b) ?? order.count
            if ra != rb { return ra > rb }
            return first[a]! > first[b]!
        }
    }
}
