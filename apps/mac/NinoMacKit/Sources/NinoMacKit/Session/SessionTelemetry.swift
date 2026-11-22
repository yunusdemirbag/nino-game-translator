// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import Foundation
import NinoCore

/// Ölçüm (NinoCore docs/tarif/olcum.md): anonim hata ve hız istatistikleri. Kapatma düğmesi yoktur; ölçümü yalnız
/// sunucu durdurur. Yalnız kod gider: altyazı metni, ad, adres, yol, hata mesajı hiçbir olaya girmez.
///
/// Oturum boyunca PS5/TV bağlantıları ve süreler burada tutulur; olaylar `Telemetry` aktörüne gider.
@MainActor
final class SessionMeter {
    let telemetry: Telemetry
    private var connectStarted: Date?
    private var streamingSince: Date?
    private var tvAttemptStarted: Date?
    private var sessionStarted: Date?
    private var firstFrameSeen = false
    private var firstSubtitleSeen = false
    private(set) var timings = SessionTimings()
    private(set) var lines = 0

    init(telemetry: Telemetry) { self.telemetry = telemetry }

    func record(_ e: TelemetryEvent?) {
        guard let e else { return }
        let t = telemetry
        Task { await t.record(e) }
    }

    // MARK: Oturum

    func sessionStarted(at date: Date = Date()) {
        sessionStarted = date
        timings = SessionTimings()
        lines = 0
        firstFrameSeen = false
        firstSubtitleSeen = false
        tvAttemptStarted = date
    }

    /// Oturum bitti (durdur, kopma, kapanış): tek `session` olayı.
    func sessionEnded(game: String?, source: TelemetryEvent.SessionSource, at date: Date = Date()) {
        record(takeSessionEvent(game: game, source: source, at: date))
    }

    /// Oturum olayını kurar ve oturumu kapatır (kapanışta eşzamanlı kaydetmek için).
    func takeSessionEvent(game: String?, source: TelemetryEvent.SessionSource, at date: Date = Date()) -> TelemetryEvent? {
        guard let start = sessionStarted else { return nil }
        sessionStarted = nil
        let event = TelemetryEvent.session(duration: Int(date.timeIntervalSince(start)), game: game, source: source,
                                           lines: lines, timings: timings)
        connectStarted = nil
        streamingSince = nil
        tvAttemptStarted = nil
        return event
    }

    func frameSeen(at date: Date = Date()) {
        guard !firstFrameSeen else { return }
        firstFrameSeen = true
        if let s = connectStarted ?? sessionStarted { timings.record(SessionTimings.Metric.firstFrame, ms: ms(s, date)) }
    }

    func ocr(ms: Int) { timings.record(SessionTimings.Metric.ocr, ms: ms) }

    func lineShown(_ line: LiveLine, at date: Date = Date()) {
        lines += 1
        if !firstSubtitleSeen, let s = sessionStarted {
            firstSubtitleSeen = true
            timings.record(SessionTimings.Metric.firstSubtitle, ms: ms(s, date))
        }
        guard let latency = line.latencyMs, line.origin != .untranslated else { return }
        timings.record(SessionTimings.Metric.total, ms: latency)
    }

    // MARK: PS5

    func ps5Status(_ link: SourceStatus.ConsoleLink, before: SourceStatus.ConsoleLink?, at date: Date = Date()) {
        switch link {
        case .connecting:
            if connectStarted == nil { connectStarted = date }
        case .streaming:
            if streamingSince == nil {
                record(.ps5Connect(result: "ok", ms: ms(connectStarted ?? date, date), via: .lan))
                streamingSince = date
            }
            connectStarted = nil
        case let .dropped(reason):
            if let since = streamingSince {
                record(.ps5Drop(Self.dropCode(reason), after: Int(date.timeIntervalSince(since))))
                streamingSince = nil
            } else if let started = connectStarted {
                record(.ps5Connect(result: Self.connectCode(reason), ms: ms(started, date), via: .lan))
                connectStarted = nil
            }
        case .idle:
            break
        }
    }

    /// Bağlanırken düşme sebebi → `ps5_connect.r`.
    static func connectCode(_ r: SourceStatus.DropReason) -> String {
        switch r {
        case .asleep: return TelemetryCode.ps5SessionStandby
        case .inUseElsewhere: return TelemetryCode.ps5SessionBusy
        case .refused, .rejected, .passcodeRequired, .passcodeWrong: return TelemetryCode.ps5AuthRejected
        case .pairingInvalid: return TelemetryCode.ps5AuthExpired
        case .notFound: return TelemetryCode.ps5DiscoverNone
        case .network: return TelemetryCode.ps5SessionTimeout
        case .noPicture: return TelemetryCode.ps5StreamDecoder
        case .remotePlayDisabled, .other: return TelemetryCode.ps5Other
        }
    }

    /// Bağlıyken kopma sebebi → `ps5_drop.code`.
    static func dropCode(_ r: SourceStatus.DropReason) -> String {
        switch r {
        case .asleep: return TelemetryCode.Drop.standby
        case .inUseElsewhere: return TelemetryCode.Drop.kicked
        case .network: return TelemetryCode.Drop.networkLost
        case .noPicture: return TelemetryCode.Drop.stalled
        case .notFound: return TelemetryCode.Drop.timeout
        case .refused, .rejected: return TelemetryCode.Drop.ps5Closed
        case .passcodeRequired, .passcodeWrong, .pairingInvalid, .remotePlayDisabled, .other: return TelemetryCode.Drop.other
        }
    }

    // MARK: TV

    /// Tek bir TV bağlantısının olayı → `tv_connect` / `tv_drop` (tarif: olcum.md). Adres ve ad gitmez; model ve TV
    /// uygulama sürümü kurucunun kuralına uyarsa gider. Bu tarafın kapattıkları (durdurma, sunucu kapanışı) sayılmaz.
    func tvLink(_ e: DisplayLinkEvent, brand: TelemetryEvent.TVBrand?, wokeAt: Date?) {
        let proto: TelemetryEvent.TVProtocol = e.route == .legacySSE ? .legacy : .nino
        switch e.kind {
        case .connected:
            record(.tvConnect(result: "ok", ms: ms(tvAttemptStarted ?? e.at, e.at), brand: brand, proto: proto,
                              model: e.model, tvApp: e.appVersion))
            tvAttemptStarted = nil
        case .disconnected, .timedOut:
            guard let reason = e.reason, !reason.isLocal else { return }
            record(.tvDrop(Self.tvDropCode(reason, at: e.at, wokeAt: wokeAt), brand: brand,
                           after: Int(e.duration ?? 0), model: e.model, tvApp: e.appVersion))
            tvAttemptStarted = e.at
        }
    }

    /// Kopma nedeni → `tv_drop.code`. Uyanıştan sonraki 60 sn içindeki kopma `resume` sayılır.
    /// TODO: `network_change` için Session'da ağ değişimi işareti yok (NWPathMonitor bağlanınca eklenecek).
    static func tvDropCode(_ r: DisplayLinkEvent.Reason, at: Date = Date(), wokeAt: Date? = nil) -> String {
        if let wokeAt, at >= wokeAt, at.timeIntervalSince(wokeAt) <= 60 { return TelemetryCode.Drop.resume }
        switch r {
        case .peerClosed, .replaced: return TelemetryCode.Drop.closed
        case .writeFailed: return TelemetryCode.Drop.writeError
        case .writeStalled, .heartbeatTimeout: return TelemetryCode.Drop.timeout
        case .readFailed, .protocolError, .serverStopped, .localClose: return TelemetryCode.Drop.other
        }
    }

    private func ms(_ a: Date, _ b: Date) -> Int { max(0, Int(b.timeIntervalSince(a) * 1_000)) }
}

extension LiveEngine {
    static func telemetryChannel(_ identity: AppIdentity, version: String) -> String {
        guard identity.flavor == .release else { return "dev" }
        return version.lowercased().contains("beta") ? "beta" : "release"
    }

    static func telemetryBrand(_ tv: PairedTV?) -> TelemetryEvent.TVBrand? {
        switch tv?.brand {
        case .androidTV?: return .androidtv
        case .lg?: return .lg
        case .samsung?: return .samsung
        case nil: return nil
        }
    }

    var telemetrySource: TelemetryEvent.SessionSource {
        switch state.settings.videoSource {
        case .ps5: return .remoteplay
        case .card: return .capture
        case .window: return state.settings.gameConsole == .xbox ? .xbox : .screen
        }
    }

    /// Ölçüm istemcisi (dizin `<veri klasörü>/telemetry`, kurulum kimliği havuzdakiyle aynı). Gönderim yolu yoksa nil.
    func makeTelemetry() -> Telemetry? {
        guard let transport = env.telemetryTransport, let base = env.poolBaseURL else { return nil }
        var ctx = TelemetryContext.current(app: env.appVersion, channel: Self.telemetryChannel(env.identity, version: env.appVersion))
        ctx.tv = Self.telemetryBrand(state.pairedTV)?.rawValue ?? ""
        let options = Telemetry.Options(endpoint: PoolServer.endpoint(base, "v1/events"), installID: installID,
                                        context: ctx, directory: env.folder.support.appendingPathComponent("telemetry"),
                                        enabled: true)
        return Telemetry(options: options, transport: transport)
    }

    /// Açılış: önceki çalışma çöktüyse `crash`, sonra `launch`; dakikalık gönderim döngüsü ve yaşam döngüsü olayları.
    func startTelemetry() {
        guard let telemetry = meter?.telemetry else { return }
        Task {
            await telemetry.appLaunched()
            await telemetry.start()
        }
        let center = NotificationCenter.default
        let ws = NSWorkspace.shared.notificationCenter
        // Nino öndeyken de arkadayken de çevirir: öne/arkaya geçmek çökme işaretini silmez, yalnız gönderimi tetikler.
        // İşaret yalnız uykuda silinir (uyku arasında sistem kapatırsa çökme sayılmasın) ve uyanınca yeniden yazılır.
        lifecycleObservers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil,
                                                     queue: .main) { _ in
            Task { _ = await telemetry.flush() }
        })
        lifecycleObservers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                                     queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appWillTerminate() }
        })
        lifecycleObservers.append(ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task {
                await telemetry.appDidEnterBackground()
                _ = await telemetry.flush()
            }
        })
        lifecycleObservers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { await telemetry.appWillEnterForeground() }
        })
    }

    /// Düzgün kapanış: süren oturum biter, işaret silinir, kısa bir gönderim denenir (en çok 2 sn).
    func appWillTerminate() {
        let diagEvents = diag.stop()
        guard let meter else { return }
        // Olay burada kurulur ve gönderimden önce kaydedilir (ana iş parçacığı aşağıda bekler).
        let session = state.isTranslating ? meter.takeSessionEvent(game: games.current?.id, source: telemetrySource) : nil
        let telemetry = meter.telemetry
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            for e in diagEvents { await telemetry.record(e) }
            if let session { await telemetry.record(session) }
            await telemetry.appWillTerminate()
            _ = await telemetry.flush(force: true)
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }

    /// Yakalanan hata (yalnız kod).
    func recordError(_ code: String, http: Int? = nil) {
        guard let telemetry = meter?.telemetry else { return }
        Task { await telemetry.recordError(code, http: http) }
    }

    static func telemetryCode(_ kind: OnlineEngineProblem.Kind) -> String {
        switch kind {
        case .badKey: return TelemetryCode.providerAuth
        case .quota: return TelemetryCode.providerQuota
        case .network: return TelemetryCode.providerOffline
        case .server: return TelemetryCode.providerHTTP
        case .model, .other: return TelemetryCode.providerHTTP
        }
    }
}
