// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Altyazının ve uzantı mesajlarının gidebileceği her çıkış: giden bağlantı (`NinoSender`),
/// gelen TV'ler (`NinoSenderIngress`), eski 8787 sunucusu (`LegacyEventServer`).
public protocol DisplayOutput: SubtitleOutput {
    func send(_ event: NinoEvent) async throws
}

extension NinoSender: DisplayOutput {
    /// Uzantı mesajı yollar. `style` ve `started` yeniden bağlanınca tekrar gönderilmek üzere saklanır.
    public func send(_ event: NinoEvent) async throws {
        switch event {
        case let .style(s): lastStyle = s
        case .started: startedAt = Date()
        case .stopped:
            startedAt = nil
            lastShown = nil
        default: break
        }
        try await sendRaw(event.jsonString)
    }
}

/// Çıkışların ortak "son durumu": yeni bağlanan TV'ye ya da yeni eklenen çıkışa yeniden yollanır.
struct DisplayReplay: Sendable {
    var style: NinoStyle?
    var startedAt: Date?
    /// Hâlâ ekranda olması gereken son altyazı (`durationMs == 0`).
    var shown: ShowPayload?

    mutating func record(show p: ShowPayload) { shown = p.durationMs == 0 ? p : nil }

    mutating func record(clear id: Int?) {
        if id == nil || id == shown?.id { shown = nil }
    }

    mutating func record(_ event: NinoEvent, now: Date = Date()) {
        switch event {
        case let .style(s): style = s
        case .started:
            startedAt = now
        case .stopped:
            startedAt = nil
            shown = nil
        default: break
        }
    }

    /// Çeviri yakın zamanda başladı mı? (balon yeniden gösterilsin mi)
    func recentlyStarted(now: Date = Date(), window: TimeInterval = NinoLink.startedReplayWindow) -> Bool {
        guard let startedAt else { return false }
        return now.timeIntervalSince(startedAt) <= window
    }

    /// Yeni bağlanana yollanacak sıra: style → started (yakın zamandaysa) → show.
    func messages(subtitles: Bool = true) -> [String] {
        var out: [String] = []
        if subtitles, let style { out.append(NinoEvent.style(style).jsonString) }
        if recentlyStarted() { out.append(NinoEvent.started.jsonString) }
        if subtitles, let shown { out.append(NinoMessage.show(shown).jsonString) }
        return out
    }
}

/// Altyazıyı TV'ye göndermeden bilgisayardaki izleyicilere (OBS) verebilen çıkış (eski 8787 sunucusu).
/// "Altyazı yalnız bilgisayarda" iken hub altyazı olaylarını yalnız bunlara yollar; bunlar da TV'lere
/// değil yalnız OBS'ye iletir.
public protocol SubtitleRoutingOutput: DisplayOutput {
    func setSubtitlesOnTV(_ on: Bool) async
}

/// "Bütün TV'lere gönder": birden çok çıkışı tek çıkış gibi kullanır.
///
/// Bir çıkış hata verirse ötekiler yine alır. En az bir çıkış varken hepsi hata
/// verirse `Failure` atılır. Hiç çıkış yoksa sessizce geçer.
public actor DisplayHub: DisplayOutput {
    public struct Failure: Error, Sendable, Equatable {
        /// Çıkış anahtarı → hata açıklaması.
        public let failures: [String: String]
    }

    private var outputs: [String: any DisplayOutput] = [:]
    private var order: [String] = []
    private var replay = DisplayReplay()
    /// `false`: "altyazı yalnız bilgisayarda".
    public private(set) var subtitlesOnTV = true

    public init() {}

    public var keys: [String] { order }

    /// Çıkış ekler (aynı anahtar varsa yerine geçer) ve ona son durumu (style, started yakın zamandaysa,
    /// altyazı) yollar.
    public func add(_ output: any DisplayOutput, key: String) async {
        if outputs[key] == nil { order.append(key) }
        outputs[key] = output
        let routing = output as? any SubtitleRoutingOutput
        if let routing { await routing.setSubtitlesOnTV(subtitlesOnTV) }
        let subtitles = subtitlesOnTV || routing != nil
        if subtitles, let s = replay.style { try? await output.send(.style(s)) }
        if replay.recentlyStarted() { try? await output.send(.started) }
        if subtitles, let p = replay.shown { try? await output.show(p) }
    }

    /// "Altyazı yalnız bilgisayarda" (`false`): altyazı olayları (`show`, `clear`, `style`, `screen`, `region`...)
    /// TV çıkışlarına gitmez, yalnız `SubtitleRoutingOutput`'lara gider (onlar da yalnız OBS'ye verir);
    /// `started`/`stopped` herkese gider. Kapatınca TV'ler temizlenir, açınca son style ve altyazı yollanır.
    public func setSubtitlesOnTV(_ on: Bool) async {
        guard on != subtitlesOnTV else { return }
        subtitlesOnTV = on
        for out in outputs.values {
            if let routing = out as? any SubtitleRoutingOutput { await routing.setSubtitlesOnTV(on) }
        }
        if on {
            if let s = replay.style { try? await fanOut(tvOnly: true) { try await $0.send(.style(s)) } }
            if let p = replay.shown { try? await fanOut(tvOnly: true) { try await $0.show(p) } }
        } else {
            try? await fanOut(tvOnly: true) { try await $0.clear(id: nil) }
            try? await fanOut(tvOnly: true) { try await $0.send(.screenClear) }
            try? await fanOut(tvOnly: true) { try await $0.send(.regionClear) }
        }
    }

    public func remove(key: String) {
        outputs[key] = nil
        order.removeAll { $0 == key }
    }

    public func output(for key: String) -> (any DisplayOutput)? { outputs[key] }

    public func show(_ payload: ShowPayload) async throws {
        let payload = payload.fittingLimit()
        replay.record(show: payload)
        try await fanOut(subtitle: true) { try await $0.show(payload) }
    }

    public func clear(id: Int?) async throws {
        replay.record(clear: id)
        try await fanOut(subtitle: true) { try await $0.clear(id: id) }
    }

    public func send(_ event: NinoEvent) async throws {
        replay.record(event)
        try await fanOut(subtitle: event.isSubtitleEvent) { try await $0.send(event) }
    }

    /// `subtitle`: altyazı olayı (yalnız bilgisayarda iken TV çıkışlarına gitmez).
    /// `tvOnly`: yalnız TV çıkışları (yönlendiren çıkışlar hariç).
    private func fanOut(subtitle: Bool = false, tvOnly: Bool = false,
                        _ op: @escaping @Sendable (any DisplayOutput) async throws -> Void) async throws {
        let targets = order.compactMap { k in outputs[k].map { (k, $0) } }.filter { _, out in
            let routing = out is any SubtitleRoutingOutput
            if tvOnly { return !routing }
            return !subtitle || subtitlesOnTV || routing
        }
        guard !targets.isEmpty else { return }
        let failures = await withTaskGroup(of: (String, String?).self) { group in
            for (key, out) in targets {
                group.addTask {
                    do {
                        try await op(out)
                        return (key, nil)
                    } catch {
                        return (key, "\(error)")
                    }
                }
            }
            var failed: [String: String] = [:]
            for await (key, message) in group { if let message { failed[key] = message } }
            return failed
        }
        if failures.count == targets.count { throw Failure(failures: failures) }
    }
}
