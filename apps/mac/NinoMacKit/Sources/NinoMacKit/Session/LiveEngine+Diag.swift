// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import Foundation
import NinoCore

// Otomatik teşhis bağlantıları: oturum, PS5, kareler, okuma, çeviri, TV, paketler → DiagMonitor.
// Bekçiye yalnız kod ve sayı gider; adres, ad ve metin hiçbir zaman.
extension LiveEngine {
    func makeDiag() -> DiagMonitor {
        let m = DiagMonitor(directory: env.folder.support.appendingPathComponent("telemetry"),
                            send: { [weak self] e in self?.meter?.record(e) },
                            log: { [weak self] line in self?.subtitleLog.write(line) })
        m.tvInfo = { [weak self] in self?.diagTVInfo() }
        m.game = { [weak self] in self?.games.current?.id }
        // Otomatik bildirim (yalnız teşhis özeti, kayıt dosyası yok): ortak havuz ya da otomatik bildirim kapalıysa gitmez.
        m.allowed = { [weak self] in self.map { Self.autoReportAllowed($0.state.settings) } ?? false }
        m.hangRelevant = { [weak self] in (self?.state.isTranslating ?? false) || NSApp?.isActive == true }
        m.remoteConfig = { [weak self] in
            guard let telemetry = self?.meter?.telemetry else { return nil }
            return await telemetry.remoteConfig.diag
        }
        return m
    }

    static func autoReportAllowed(_ s: MacSettings) -> Bool { s.autoReport && s.sharePool }

    /// Canlı izleme yalnız gerçek gönderim yolu varken ve test kimliği dışında (testlerde döngü, ağ izleyici ve donma
    /// bekçisi açılmaz; olaylar yine bekçiye gider).
    func startDiag() {
        guard env.telemetryTransport != nil, env.identity.flavor != .testing else { return }
        diag.start()
    }

    func diagSessionStarted(_ s: MacSettings) {
        diag.record(.sessionStart)
        // Oturumdan önce bağlanmış TV'ler (ölçümdeki gibi oturum başında sayılır).
        for _ in liveTVLinks { diag.record(.tvConnect) }
        diagPS5Streaming = false
        diagPS5Retries = 0
        var c = diag.context
        c.regionManual = s.areaPreset == .custom
        c.provider = activeOnlineEngine?.rawValue ?? "device"
        c.proto = state.pairedTV?.brand == .androidTV ? "nino" : (state.pairedTV == nil ? nil : "legacy")
        c.frameLuma = nil
        c.frameSame = false
        diag.context = c
    }

    func diagLineShown(_ line: LiveLine) {
        guard let ms = line.latencyMs else { return }
        let origin: DiagOrigin
        switch line.origin {
        case .pack: origin = .pack
        case .pool: origin = .pool
        case .cache: origin = .cache
        case .engine: origin = activeOnlineEngine == nil ? .device : .provider
        case .untranslated: return
        }
        diag.record(.line(ms: ms, origin: origin))
    }

    /// PS5 bağlantısı: akış başladı → `ps5.connect`; akarken düştü → `ps5.drop` (sebep işaretiyle); kopmadan sonraki
    /// her bağlanma denemesi → `ps5.retry`.
    func diagPS5Status(_ link: SourceStatus.ConsoleLink) {
        switch link {
        case .streaming:
            if !diagPS5Streaming { diag.record(.ps5Connect) }
            diagPS5Streaming = true
            diagPS5Retries = 0
        case let .dropped(reason):
            if diagPS5Streaming {
                diag.record(.ps5Drop(Self.diagCause(reason)))
            } else if let cause = Self.diagCause(reason) {
                diag.record(.ps5Cause(cause))
            }
            diagPS5Streaming = false
        case .connecting:
            guard !diagPS5Streaming, state.sheetsStatus.healthMetrics.ps5DownSince != nil else { return }
            diagPS5Retries += 1
            diag.record(.ps5Retry(diagPS5Retries))
        case .idle:
            break
        }
    }

    static func diagCause(_ r: SourceStatus.DropReason) -> DiagPS5Cause? {
        switch r {
        case .network: return .networkLost
        case .asleep: return .standby
        case .refused, .rejected: return .closed
        case .inUseElsewhere: return .kicked
        case .noPicture: return .stalled
        case .notFound, .passcodeRequired, .passcodeWrong, .pairingInvalid, .remotePlayDisabled, .other: return nil
        }
    }

    /// TV bağlantı olayı (çeviri sürerken; bu tarafın kapattıkları sayılmaz).
    func diagTVLink(_ e: DisplayLinkEvent) {
        if e.kind == .connected {
            diag.record(.tvConnect, at: e.at)
            return
        }
        guard let reason = e.reason, !reason.isLocal else {
            diag.record(.tvLocalClose, at: e.at)
            return
        }
        let code = reason == .replaced ? TelemetryCode.Drop.replaced
            : SessionMeter.tvDropCode(reason, at: e.at, wokeAt: lastWake)
        diag.record(.tvDrop(code: code, upSec: Int(e.duration ?? 0)), at: e.at)
    }

    func diagPacks(_ r: PackUpdater.Result) {
        if r.listFailed { diag.record(.packFail(id: "list", http: nil)) }
        for id in r.failed { diag.record(.packFail(id: id, http: nil)) }
        if !r.listFailed, r.failed.isEmpty { diag.record(.packOK(id: "*")) }
    }

    func diagTVInfo() -> DiagMonitor.TVInfo? {
        let brand = Self.telemetryBrand(state.pairedTV)
        let link = liveTVLinks.values.sorted { $0.at < $1.at }.last
        guard brand != nil || link != nil else { return nil }
        return DiagMonitor.TVInfo(brand: brand, model: link?.model, app: link?.appVersion)
    }
}
