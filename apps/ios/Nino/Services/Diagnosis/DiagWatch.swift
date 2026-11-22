// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// Bekçinin bir bildirimi (ölçüm kanalına `diag` olayı olarak gider).
struct DiagReport: Equatable {
    var rule: String
    var cause: String
    var severity: TelemetryEvent.DiagSeverity
    /// Tetiklendiği an (bekçinin saatiyle, saniye).
    var at: Double
    var state: [String: TelemetryValue]
    var trail: [TelemetryEvent.DiagStep]
}

/// Otomatik teşhis bekçisi (tarif: NinoCore docs/tarif/otomatik-teshis.md). Saatten bağımsızdır: her girdi kendi
/// anını taşır, zamana bağlı kurallar `tick(at:)` ile denetlenir. Bu yüzden senaryolar birim testinde birebir oynatılır.
/// Serbest metin tutmaz: iz yalnız kod ve sayıdır.
final class DiagWatch {
    enum Rule: String, CaseIterable {
        // Öncelik sırası (tarif): öndeki daha önemli.
        case appHang = "app.hang", ps5NoReturn = "ps5.no_return", tvFlapping = "tv.flapping", ocrStalled = "ocr.stalled"
        case trErrors = "tr.errors", trSlow = "tr.slow", ocrSilent = "ocr.silent", appResources = "app.resources"
        case packDownload = "pack.download"

        var priority: Int { Rule.allCases.firstIndex(of: self)! }

        var severity: TelemetryEvent.DiagSeverity {
            switch self {
            case .appHang, .ps5NoReturn, .ocrStalled: .error
            case .ocrSilent: .info
            default: .warn
            }
        }

        /// Ağ tamamen gidince susan kurallar (ağın kendisini bildirenler susmaz).
        var needsNetwork: Bool { self == .ocrSilent || self == .ocrStalled || self == .trSlow || self == .appResources }
    }

    /// Eşikler: tarifteki varsayılanlar; sunucu `telemetry.diag.limits` ile değiştirebilir.
    struct Limits {
        var ps5NoReturnSec = 180.0
        var tvFlapWindowMin = 10.0
        var tvFlapCount = 3.0
        var ocrSilentMin = 15.0
        var ocrStallSec = 10.0
        var trSlowP90Ms = 3000.0
        var trErrorRate = 0.30
        var hangSec = 5.0
        var memHighMB = 800.0

        init(_ config: TelemetryRemoteConfig.DiagConfig? = nil) {
            guard let c = config else { return }
            func read(_ camel: String, _ dotted: String, _ value: Double) -> Double {
                c.limits[camel] ?? c.limits[dotted] ?? value
            }
            ps5NoReturnSec = read("ps5NoReturnSec", "ps5.no_return.sec", ps5NoReturnSec)
            tvFlapWindowMin = read("tvFlapWindowMin", "tv.flapping.windowMin", tvFlapWindowMin)
            tvFlapCount = read("tvFlapCount", "tv.flapping.count", tvFlapCount)
            ocrSilentMin = read("ocrSilentMin", "ocr.silent.min", ocrSilentMin)
            ocrStallSec = read("ocrStallSec", "ocr.stalled.sec", ocrStallSec)
            trSlowP90Ms = read("trSlowP90Ms", "tr.slow.p90Ms", trSlowP90Ms)
            trErrorRate = read("trErrorRate", "tr.errors.rate", trErrorRate)
            hangSec = read("hangSec", "app.hang.sec", hangSec)
            memHighMB = read("memHighMB", "app.resources.memMB", memHighMB)
        }
    }

    /// Günlük sınır sayaçları (uygulama kalıcı saklar).
    struct DayCount: Codable, Equatable {
        var day = ""
        var total = 0
        var perRule: [String: Int] = [:]
    }

    /// Bildirime eklenen o anki durum (ağ türü, bellek, parlaklık…). Uygulama verir; testte senaryonun `state`'i.
    var context: () -> [String: TelemetryValue] = { [:] }
    /// Günün anahtarı (yyyy-MM-dd); testte sabit.
    var today: () -> String = { DiagWatch.dayKey(Date()) }
    var dayCount = DayCount()
    private(set) var limits: Limits
    private var off: Set<String>

    init(config: TelemetryRemoteConfig.DiagConfig? = nil, launchedAt: Double) {
        limits = Limits(config)
        off = Set(config?.off ?? [])
        self.launchedAt = launchedAt
    }

    func apply(_ config: TelemetryRemoteConfig.DiagConfig?) {
        limits = Limits(config)
        off = Set(config?.off ?? [])
    }

    // MARK: İz

    private var trail: [(t: Double, code: String, value: Int?)] = []

    /// Her satırda gelen kodlar art arda gelirse tek adımda toplanır (sayı: kaç kez); kare hızı son değeri tutar.
    private static let merged: Set<String> = ["ocr.text", "tr.ok", "ps5.frame"]

    private func step(_ code: String, _ value: Int?, at t: Double) {
        if Self.merged.contains(code), let last = trail.last, last.code == code {
            trail[trail.count - 1] = (t, code, code == "ps5.frame" ? value : (last.value ?? 1) + 1)
            return
        }
        trail.append((t, code, value))
        trail.removeAll { t - $0.t > 600 }
        if trail.count > 200 { trail.removeFirst(trail.count - 200) }
    }

    // MARK: Durum

    private let launchedAt: Double
    private var quietUntil = 0.0
    private var inSession = false
    private var sessionStart = 0.0
    private var sentThisSession: Set<Rule> = []
    private var lastSent: (rule: Rule, at: Double)?

    private var netDown = false
    private var netKind = "wifi"

    private var ps5Up = false
    private var dropAt: Double?
    private var dropCause: String?
    private var retries = 0
    private var fps = 0
    private var lastFrame: Double?

    private var lastText = 0.0

    private var tvDrops: [(t: Double, cause: String)] = []
    private var tvUp = false

    private var ocrPendingSince: Double?
    private var ocrStallCounted = false
    private var ocrStalls: [Double] = []
    private var ocrTimes: [Int] = []

    private var trTotals: [Int] = []
    private var trResults: [Int] = []   // 0 = başarılı, aksi HTTP durumu (−1 zaman aşımı, −2 ağ yok)
    private var providerTimes: [Int] = []

    private var memHighSince: Double?
    private var thermalSince: Double?
    private var thermal = "nominal"
    private var memMB = 0

    /// Paket başına art arda başarısız indirme (uygulama kalıcı saklar: güncelleme günde bir yapılır).
    var packFails: [String: Int] = [:]
    private var lastTick: Double?

    // MARK: Girdiler

    /// İz kodlu olay (tarifteki kodlar). `detail`: kopma nedeni gibi kısa kod (yalnız sebep seçimi için).
    @discardableResult
    func note(_ code: String, _ value: Int? = nil, at t: Double, detail: String? = nil) -> [DiagReport] {
        step(code, value, at: t)
        var out: [DiagReport] = []
        switch code {
        case "session.start":
            inSession = true
            sessionStart = t
            lastText = t
            sentThisSession = []
            dropAt = nil
            retries = 0
            tvDrops = []
            trTotals = []
            trResults = []
        case "session.stop":
            inSession = false
            dropAt = nil
            quiet(at: t)
        case "sys.sleep", "sys.wake", "app.background", "app.foreground":
            quiet(at: t)
        case "net.down":
            netDown = true
        case "net.up":
            netDown = false
        case "net.change":
            netDown = false
        case "ps5.connect":
            ps5Up = true
            dropAt = nil
            lastFrame = t
        case "ps5.drop":
            ps5Up = false
            fps = 0
            if inSession, dropAt == nil {
                dropAt = t
                dropCause = detail
                retries = 0
            }
        case "ps5.retry":
            retries = value ?? retries + 1
        case "ps5.frame":
            fps = value ?? fps
            lastFrame = t
        case "ocr.text":
            lastText = t
        case "tv.connect":
            tvUp = true
        case "tv.drop":
            tvUp = false
            if inSession {
                tvDrops.append((t, detail ?? "closed"))
                out += evaluateTV(at: t)
            }
        case "tr.ok", "tr.error":
            if inSession {
                trResults.append(code == "tr.ok" ? 0 : (value ?? -1))
                if trResults.count > 40 { trResults.removeFirst(trResults.count - 40) }
                out += evaluateErrors(at: t)
            }
        case "mem.high":
            memHighSince = memHighSince ?? t - 120 // işletim sisteminin bellek uyarısı: hemen sayılır
            out += evaluateResources(at: t)
        default:
            break
        }
        return out
    }

    /// Ağ türü değişti (`wifi`/`ethernet`/`cellular`/`none`).
    @discardableResult
    func network(_ kind: String, at t: Double) -> [DiagReport] {
        let wasDown = netDown
        if kind == "none" {
            if !wasDown { step("net.down", nil, at: t) }
            netDown = true
        } else {
            if wasDown { step("net.up", nil, at: t) } else if kind != netKind { step("net.change", nil, at: t) }
            netDown = false
        }
        netKind = kind
        return []
    }

    /// Her kare (iz yazılmaz; saniyelik kare sayısı ayrıca `ps5.frame` ile gelir).
    func frame(at t: Double) { lastFrame = t }

    /// Yazı tanıma isteği başladı / bitti.
    func ocrStarted(at t: Double) {
        ocrPendingSince = t
        ocrStallCounted = false
    }

    func ocrFinished(ms: Int, at t: Double) {
        ocrPendingSince = nil
        ocrTimes.append(ms)
        if ocrTimes.count > 50 { ocrTimes.removeFirst(ocrTimes.count - 50) }
        if Double(ms) >= limits.ocrStallSec * 1000 / 4 { step("ocr.slow", ms, at: t) }
    }

    /// Bir altyazı satırının okunmasından çevirisinin hazır olmasına kadar geçen süre.
    @discardableResult
    func translated(totalMs: Int, at t: Double) -> [DiagReport] {
        guard inSession else { return [] }
        trTotals.append(totalMs)
        if trTotals.count > 50 { trTotals.removeFirst(trTotals.count - 50) }
        if Double(totalMs) > limits.trSlowP90Ms { step("tr.slow", totalMs, at: t) }
        return evaluateSlow(at: t)
    }

    /// Çeviri hizmetinin tek isteği (ms; başarısızsa HTTP durumu ya da −1 zaman aşımı, −2 ağ yok).
    @discardableResult
    func providerRequest(ms: Int, failure: Int?, at t: Double) -> [DiagReport] {
        providerTimes.append(ms)
        if providerTimes.count > 50 { providerTimes.removeFirst(providerTimes.count - 50) }
        if let failure { return note("tr.error", failure, at: t) }
        return note("tr.ok", at: t)
    }

    /// Ana iş parçacığı `blockedSec` boyunca yanıt vermedi.
    @discardableResult
    func hang(blockedSec: Double, at t: Double) -> [DiagReport] {
        guard blockedSec >= limits.hangSec else { return [] }
        step("app.hang", Int(blockedSec), at: t)
        var s = context()
        s["blockedSec"] = .int(Int(blockedSec))
        return fire(.appHang, cause: "main_thread", at: t, state: s)
    }

    /// Bellek (MB) ve ısı durumu (`nominal`/`fair`/`serious`/`critical`) örneği.
    @discardableResult
    func resources(memMB: Int, thermal: String, at t: Double) -> [DiagReport] {
        self.memMB = memMB
        self.thermal = thermal
        if Double(memMB) > limits.memHighMB {
            if memHighSince == nil { step("mem.high", memMB, at: t) }
            memHighSince = memHighSince ?? t
        } else {
            memHighSince = nil
        }
        if thermal == "serious" || thermal == "critical" { thermalSince = thermalSince ?? t } else { thermalSince = nil }
        return evaluateResources(at: t)
    }

    /// Oyun paketi indirme sonucu (paket kimliği yalnız sayaç için; gönderilmez). `http`: 0 ağ yok.
    @discardableResult
    func packResult(_ id: String, ok: Bool, http: Int? = nil, at t: Double) -> [DiagReport] {
        guard !ok else { packFails[id] = nil; return [] }
        step("pack.fail", http, at: t)
        packFails[id, default: 0] += 1
        guard packFails[id]! >= 3 else { return [] }
        packFails[id] = 0
        let cause: String
        switch http {
        case .some(0): cause = "offline"
        case .some(let h) where (400..<500).contains(h): cause = "http_4xx"
        case .some(let h) where h >= 500: cause = "http_5xx"
        default: cause = netDown ? "offline" : "unknown"
        }
        var s = context()
        s["attempts"] = .int(3)
        if let http { s["http"] = .int(http) }
        return fire(.packDownload, cause: cause, at: t, state: s)
    }

    /// Zamana bağlı kurallar.
    @discardableResult
    func tick(at t: Double) -> [DiagReport] {
        var out: [DiagReport] = []
        // Saatte boşluk: uygulama askıya alınmış ya da cihaz uyumuş (iOS'ta arka plana geçiş olayı geç gelebilir).
        // Uyanma gibi sayılır: susturulur, beklemedeki sayaçlar baştan başlar.
        if let last = lastTick, t - last > 5 {
            step("sys.wake", nil, at: t)
            quiet(at: t)
            if dropAt != nil { dropAt = t }
            if lastFrame != nil { lastFrame = t }
            ocrPendingSince = nil
        }
        lastTick = t
        if t < quietUntil {
            // Uyku, arka plan ya da kullanıcının durdurması: sayaçlar baştan başlar.
            if dropAt != nil { dropAt = t }
            if inSession { lastText = max(lastText, t) }
            return out
        }
        // Açılışın ilk dakikası yalnız bildirimi engeller (fire), sayaçlar sürer.
        if inSession, let since = dropAt, t - since >= limits.ps5NoReturnSec {
            dropAt = nil
            let cause: String
            if netDown { cause = "network_lost" } else if let c = dropCause, ["ps5_standby", "ps5_closed", "kicked", "stalled"].contains(c) { cause = c } else { cause = "timeout" }
            var s = context()
            s["ps5"] = .string("down")
            s["net"] = .string(netDown ? "none" : netKind)
            s["sessionMin"] = .int(Int((t - sessionStart) / 60))
            s["retries"] = .int(retries)
            out += fire(.ps5NoReturn, cause: cause, at: t, state: s)
        }
        if inSession, fps >= 1, ps5Up || lastFrame != nil, dropAt == nil, t - lastText >= limits.ocrSilentMin * 60 {
            lastText = t
            var s = context()
            s["fps"] = .int(fps)
            let luma = s["frameLuma"].flatMap { v -> Int? in if case let .int(n) = v { n } else { nil } }
            let same: Bool = { if case .bool(true) = s["frameSame"] { true } else { false } }()
            let manual: Bool = { if case .string("manual") = s["region"] { true } else { false } }()
            let cause = (luma.map { $0 <= 16 } ?? false) || same ? "video_black" : manual ? "region_wrong" : "no_text"
            out += fire(.ocrSilent, cause: cause, at: t, state: s)
        }
        if inSession, let since = ocrPendingSince, !ocrStallCounted, t - since >= limits.ocrStallSec {
            ocrStallCounted = true
            ocrStalls.append(t)
            ocrStalls.removeAll { t - $0 > 300 }
            step("ocr.slow", Int((t - since) * 1000), at: t)
            if ocrStalls.count >= 3 {
                ocrStalls = []
                var s = context()
                s["ocrMs"] = .int(Int((t - since) * 1000))
                out += fire(.ocrStalled, cause: "ocr_hang", at: t, state: s)
            }
        }
        if inSession, ps5Up, let last = lastFrame, t - last >= 30 {
            lastFrame = t
            var s = context()
            s["fps"] = .int(0)
            out += fire(.ocrStalled, cause: "frames_stopped", at: t, state: s)
        }
        out += evaluateResources(at: t)
        return out
    }

    // MARK: Kurallar

    private func evaluateTV(at t: Double) -> [DiagReport] {
        let window = limits.tvFlapWindowMin * 60
        tvDrops.removeAll { t - $0.t > window }
        guard Double(tvDrops.count) >= limits.tvFlapCount else { return [] }
        var counts: [String: Int] = [:]
        for d in tvDrops { counts[d.cause, default: 0] += 1 }
        let top = counts.max { $0.value < $1.value }!
        let known = ["write_error", "timeout", "closed", "resume", "network_change"]
        let cause = top.value * 2 > tvDrops.count && known.contains(top.key) ? top.key : "mixed"
        var s = context()
        s["drops"] = .int(tvDrops.count)
        s["net"] = .string(netDown ? "none" : netKind)
        let reports = fire(.tvFlapping, cause: cause, at: t, state: s)
        if !reports.isEmpty { tvDrops = [] }
        return reports
    }

    private func evaluateErrors(at t: Double) -> [DiagReport] {
        let requests = trResults.count
        let failures = trResults.filter { $0 != 0 }
        guard requests >= 10, Double(failures.count) / Double(requests) > limits.trErrorRate else { return [] }
        var counts: [Int: Int] = [:]
        for f in failures { counts[f, default: 0] += 1 }
        let http = counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }!.key
        let cause: String
        if netDown || http == -2 { cause = "offline" } else if http == 429 { cause = "quota" } else if http == 401 || http == 403 { cause = "auth" } else if http >= 500 { cause = "server" } else if http == -1 { cause = "timeout" } else { cause = "unknown" }
        var s = context()
        s["errors"] = .int(failures.count)
        s["requests"] = .int(requests)
        if http > 0 { s["http"] = .int(http) }
        let reports = fire(.trErrors, cause: cause, at: t, state: s)
        if !reports.isEmpty { trResults = [] }
        return reports
    }

    private func evaluateSlow(at t: Double) -> [DiagReport] {
        guard trTotals.count >= 20 else { return [] }
        let p90 = Self.percentile(trTotals, 0.9), p50 = Self.percentile(trTotals, 0.5)
        guard Double(p90) > limits.trSlowP90Ms else { return [] }
        let ocrP90 = ocrTimes.isEmpty ? 0 : Self.percentile(ocrTimes, 0.9)
        let providerP90 = providerTimes.isEmpty ? 0 : Self.percentile(providerTimes, 0.9)
        let cause = ocrP90 > 1500 ? "device_busy" : Double(providerP90) > limits.trSlowP90Ms * 0.8 ? "provider_slow" : "network_slow"
        var s = context()
        s["p50"] = .int(p50)
        s["p90"] = .int(p90)
        s["ocrP90"] = .int(ocrP90)
        let reports = fire(.trSlow, cause: cause, at: t, state: s)
        if !reports.isEmpty { trTotals = [] }
        return reports
    }

    private func evaluateResources(at t: Double) -> [DiagReport] {
        let cause: String
        if let since = thermalSince, t - since >= 120 { cause = "thermal" } else if let since = memHighSince, t - since >= 120 { cause = "memory_high" } else { return [] }
        var s = context()
        s["memMB"] = .int(memMB)
        s["thermal"] = .string(thermal)
        if inSession { s["sessionMin"] = .int(Int((t - sessionStart) / 60)) }
        let reports = fire(.appResources, cause: cause, at: t, state: s)
        memHighSince = nil
        thermalSince = nil
        return reports
    }

    // MARK: Gönderim kuralları

    private func quiet(at t: Double) { quietUntil = max(quietUntil, t + 120) }

    private func quieted(at t: Double) -> Bool { t < quietUntil || t - launchedAt < 60 }

    private func fire(_ rule: Rule, cause: String, at t: Double, state: [String: TelemetryValue]) -> [DiagReport] {
        guard !off.contains(rule.rawValue) else { return [] }
        if rule != .appHang, quieted(at: t) { return [] }
        if rule.needsNetwork, netDown { return [] }
        if inSession || rule != .packDownload, sentThisSession.contains(rule) { return [] }
        // Tek kök, tek bildirim: 5 dakika içinde daha önemli ya da eşit bir bildirim gittiyse bu yalnız ize yazılır.
        if let last = lastSent, t - last.at < 300, last.rule.priority <= rule.priority {
            step("diag." + rule.rawValue, nil, at: t)
            return []
        }
        let day = today()
        if dayCount.day != day { dayCount = DayCount(day: day) }
        guard dayCount.total < 5, dayCount.perRule[rule.rawValue, default: 0] < 2 else { return [] }
        dayCount.total += 1
        dayCount.perRule[rule.rawValue, default: 0] += 1
        sentThisSession.insert(rule)
        lastSent = (rule, t)
        let steps = trail.suffix(40).map { TelemetryEvent.DiagStep(Int(($0.t - t).rounded()), $0.code, $0.value) }
        return [DiagReport(rule: rule.rawValue, cause: cause, severity: rule.severity, at: t, state: state, trail: steps)]
    }

    static func percentile(_ values: [Int], _ p: Double) -> Int {
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count) * p).rounded(.up)) - 1))
        return sorted[index]
    }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
