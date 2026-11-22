// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Nino ölçüm istemcisi (tarif: docs/tarif/olcum.md). Olaylar diskte bir kuyrukta birikir, toplu ve gzip'li olarak
/// `POST /v1/events`'e gider. Altyazı metni, IP, ad ya da serbest yazı hiçbir olaya girmez.
///
/// Kullanım (uygulama):
/// ```
/// let telemetry = Telemetry(options: .init(endpoint: ..., installID: ..., context: .current(app: "4.0.0"),
///                                          directory: dirs.root.appendingPathComponent("telemetry"),
///                                          enabled: true))
/// await telemetry.appLaunched()
/// await telemetry.record(.ps5Connect(result: "ok", ms: 2840, via: .lan))
/// ```
/// Kullanıcı kararıyla ayarlarda kapatma düğmesi yoktur: uygulamalar `enabled: true` verir. `enabled`/`setEnabled`
/// testler ve geliştirici yapıları içindir; ölçümü bütün uygulamalarda sunucu durdurur (`applyRemoteConfig`).
public actor Telemetry {
    public struct Options: Sendable {
        public var endpoint: URL
        public var installID: String
        public var context: TelemetryContext
        public var directory: URL
        public var enabled: Bool
        /// Kuyrukta bu kadar olay birikince beklemeden gönderilir.
        public var flushThreshold = 100
        /// Diskteki kuyruğun en büyük boyu; dolunca en eski (çökme olmayan) olay atılır.
        public var maxQueued = 2000
        /// Bir parçada en çok olay (sunucu sınırı 300).
        public var maxBatch = 300

        public init(endpoint: URL, installID: String, context: TelemetryContext, directory: URL, enabled: Bool) {
            self.endpoint = endpoint
            self.installID = installID
            self.context = context
            self.directory = directory
            self.enabled = enabled
        }
    }

    public enum FlushResult: Equatable, Sendable {
        case disabled, empty, waiting, busy
        case sent(Int)
        case duplicate
        case dropped(Int)
        case split
        case retryLater(Int)
    }

    struct Pending: Codable, Equatable {
        var id: String
        var events: [TelemetryEvent]
    }

    struct State: Codable, Equatable {
        var queue: [TelemetryEvent] = []
        var pending: Pending?
        var day = 0
        var recordedToday = 0
        var droppedToday = 0
        var remote = TelemetryRemoteConfig()
        var nextAttempt = 0
        var backoff = 0
        var lastFlush = 0
        var batchLimit = 0
    }

    public private(set) var options: Options
    private let transport: TelemetryTransport
    private let clock: @Sendable () -> Date
    private let marker: CrashMarker
    private var state: State
    private var flushing = false
    private var loop: Task<Void, Never>?

    private var stateURL: URL { options.directory.appendingPathComponent("queue.json") }

    public init(options: Options, transport: TelemetryTransport = URLSessionTelemetryTransport(),
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.options = options
        self.transport = transport
        self.clock = clock
        self.marker = CrashMarker(directory: options.directory)
        let url = options.directory.appendingPathComponent("queue.json")
        if options.enabled, let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            state = State()
        }
        if !options.enabled {
            try? FileManager.default.removeItem(at: url)
            marker.clear()
        }
    }

    // MARK: - Durum

    /// Kullanıcı ayarı açık ve sunucu kapatmamış.
    public var isActive: Bool { options.enabled && state.remote.enabled }
    public var queuedCount: Int { state.queue.count + (state.pending?.events.count ?? 0) }
    public var queued: [TelemetryEvent] { (state.pending?.events ?? []) + state.queue }
    public var remoteConfig: TelemetryRemoteConfig { state.remote }
    public var isSampled: Bool { TelemetryRemoteConfig.isSampled(install: options.installID, sample: state.remote.sample) }
    public var crashMarker: CrashMarker { marker }

    /// Kapatınca kuyruk ve işaret hemen silinir. Kullanıcıya düğme olarak sunulmaz (testler, geliştirici yapıları).
    public func setEnabled(_ enabled: Bool) {
        guard enabled != options.enabled else { return }
        options.enabled = enabled
        if enabled {
            marker.markRunning(version: options.context.app, now: now())
        } else {
            let remote = state.remote
            state = State()
            state.remote = remote
            try? FileManager.default.removeItem(at: stateURL)
            marker.clear()
        }
    }

    /// Bağlı TV değişince (`ctx.tv`).
    public func setTVBrand(_ brand: TelemetryEvent.TVBrand?) {
        options.context.tv = brand?.rawValue ?? ""
    }

    /// `/v1/config` cevabındaki `telemetry` bloğu. Sunucu kapatırsa kuyruk silinir.
    public func applyRemoteConfig(_ config: TelemetryRemoteConfig) {
        state.remote = config
        if !config.enabled {
            state.queue.removeAll()
            state.pending = nil
            marker.clear()
        }
        save()
    }

    // MARK: - Uygulama yaşam döngüsü

    /// Açılışta: önceki çalışma çöktüyse `crash`, sonra `launch`; "çalışıyor" işareti yazılır.
    public func appLaunched(launchMs: Int? = nil) {
        guard isActive else { marker.clear(); return }
        if let crash = marker.takeCrash() { record(crash) }
        marker.markRunning(version: options.context.app, now: now())
        record(.launch(ms: launchMs))
    }

    /// Düzgün kapanış: işaret silinir. Ardından kısa bir gönderim denenebilir (`flush`).
    public func appWillTerminate() {
        marker.clear()
    }

    /// Arka plana geçerken: işletim sistemi uygulamayı kapatırsa çökme sayılmasın.
    public func appDidEnterBackground() {
        marker.clear()
    }

    public func appWillEnterForeground() {
        guard isActive else { return }
        marker.markRunning(version: options.context.app, now: now())
    }

    /// Arka planda dakikada bir `flushIfDue` çağıran döngü.
    public func start(interval: TimeInterval = 60) {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await self?.tick()
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    private func tick() async {
        if isActive { marker.touch(now: now()) }
        _ = await flushIfDue()
    }

    // MARK: - Kayıt

    /// Olayı kuyruğa ekler. Kapalıysa hiçbir şey yapmaz. Günlük sınır dolduysa yalnız çökme eklenir.
    public func record(_ event: TelemetryEvent) {
        guard isActive else { return }
        let t = now()
        rollDay(t)
        var e = event
        if e.time == 0 { e.time = t }
        if e.kind == .session, !isSampled { e.fields["h"] = nil }

        if e.kind == .error, coalesce(e) { save(); return }
        // Çökme ve otomatik teşhis günlük sınırdan muaf (teşhisin kendi sınırları bekçide ve sunucuda).
        if e.kind != .crash, e.kind != .diag, state.recordedToday >= state.remote.maxPerDay {
            state.droppedToday += 1
            return
        }
        state.recordedToday += 1
        state.queue.append(e)
        while state.queue.count > options.maxQueued {
            if let i = state.queue.firstIndex(where: { $0.kind != .crash }) { state.queue.remove(at: i) }
            else { state.queue.removeFirst() }
        }
        save()
        if state.queue.count >= options.flushThreshold {
            Task { _ = await self.flushIfDue() }
        }
    }

    /// Yakalanan hata (kod geçersizse atılır).
    public func recordError(_ code: String, http: Int? = nil) {
        if let e = TelemetryEvent.error(code, http: http) { record(e) }
    }

    /// Kuyruktaki aynı kodlu hataya ekler (`n`). Gönderilmekte olan parçaya dokunmaz.
    private func coalesce(_ e: TelemetryEvent) -> Bool {
        let added = e.fields["n"]?.intValue ?? 1
        guard let i = state.queue.lastIndex(where: {
            $0.kind == .error && $0.fields["code"] == e.fields["code"] && $0.fields["http"] == e.fields["http"]
        }) else { return false }
        let n = (state.queue[i].fields["n"]?.intValue ?? 1) + added
        state.queue[i].fields["n"] = .int(min(n, 10_000))
        return true
    }

    // MARK: - Gönderim

    /// Zamanı geldiyse (aralık doldu ya da kuyruk kabardı) gönderir.
    public func flushIfDue() async -> FlushResult {
        guard isActive else { return .disabled }
        let t = now()
        let due = state.queue.count >= options.flushThreshold || state.pending != nil
            || t - state.lastFlush >= state.remote.flushSeconds
        return due ? await flush() : .waiting
    }

    /// Bir parça gönderir. `force`: bekleme süresini (429/5xx sonrası) yok sayar.
    @discardableResult
    public func flush(force: Bool = false) async -> FlushResult {
        guard isActive else { return .disabled }
        guard !flushing else { return .busy }
        let t = now()
        if !force && t < state.nextAttempt { return .waiting }
        if state.pending == nil {
            guard !state.queue.isEmpty else { state.lastFlush = t; return .empty }
            let limit = state.batchLimit > 0 ? min(state.batchLimit, options.maxBatch) : options.maxBatch
            let take = Array(state.queue.prefix(limit))
            state.queue.removeFirst(take.count)
            state.pending = Pending(id: UUID().uuidString.lowercased(), events: take)
            save()
        }
        guard let pending = state.pending, let body = encode(pending) else {
            state.pending = nil
            save()
            return .dropped(0)
        }

        flushing = true
        defer { flushing = false }
        let compressed = TelemetryGzip.compress(body)
        let response: TelemetryResponse
        do {
            response = try await transport.send(compressed ?? body, gzip: compressed != nil, to: options.endpoint)
        } catch {
            return retry(after: nil, at: now())
        }
        // Gönderim sürerken ayar kapatıldıysa parça zaten silinmiştir.
        guard isActive, state.pending?.id == pending.id else { return .disabled }

        let done = now()
        switch response.status {
        case 200..<300:
            state.pending = nil
            state.backoff = 0
            state.nextAttempt = 0
            state.batchLimit = 0
            state.lastFlush = done
            let reply = try? JSONDecoder().decode(Reply.self, from: response.body)
            if let config = reply?.config { applyRemoteConfig(config) } else { save() }
            return reply?.duplicate == true ? .duplicate : .sent(pending.events.count)
        case 413:
            state.pending = nil
            if pending.events.count > 1 {
                state.queue.insert(contentsOf: pending.events, at: 0)
                state.batchLimit = max(1, pending.events.count / 2)
                save()
                return .split
            }
            save()
            return .dropped(1)
        case 400:
            // Yalnız "gövde bozuk" siler. 404 (sunucu henüz yayında değil), 429 ve 5xx: saklanır, beklenir.
            state.pending = nil
            save()
            return .dropped(pending.events.count)
        default:
            return retry(after: response.retryAfter, at: done)
        }
    }

    private struct Reply: Decodable {
        var duplicate: Bool?
        var config: TelemetryRemoteConfig?
    }

    private struct Batch: Encodable {
        var v = 1
        var batch: String
        var install: String
        var ctx: TelemetryContext
        var events: [TelemetryEvent]
    }

    private func encode(_ pending: Pending) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(Batch(batch: pending.id, install: options.installID.lowercased(), ctx: options.context,
                                         events: pending.events))
    }

    /// 404 / 429 / 5xx / ağ yok: parça saklanır (aynı kimlikle yeniden denenir); 1 dk, 2 dk, 4 dk… en çok 1 saat.
    private func retry(after: Int?, at t: Int) -> FlushResult {
        state.backoff = min(3600, max(60, state.backoff * 2))
        let wait = after.map { max(1, $0) } ?? state.backoff
        state.nextAttempt = t + wait
        save()
        return .retryLater(wait)
    }

    // MARK: - Yardımcılar

    private func now() -> Int { Int(clock().timeIntervalSince1970) }

    private func rollDay(_ t: Int) {
        let local = t + TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(t)))
        let day = local / 86400
        if day != state.day {
            state.day = day
            state.recordedToday = 0
            state.droppedToday = 0
        }
    }

    private func save() {
        guard options.enabled else { return }
        do {
            try FileManager.default.createDirectory(at: options.directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        } catch {
            // Disk dolu ya da yazılamıyor: ölçüm uygulamayı asla bozmamalı.
        }
    }
}
