// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// Altyazının TV'lere gittiği yol. Üç çıkış birlikte çalışır:
/// - eski TV uygulamaları telefonu 8787'de bulup bağlanır (`LegacyEventServer`),
/// - LG/Samsung web TV'ler 47800'deki gönderici girişine bağlanır (`NinoSenderIngress`),
/// - yeni Android TV uygulaması dinler; telefon ona bağlanır (`NinoSender`, Bonjour ya da kayıtlı adres).
/// Hepsi `DisplayHub` üzerinden aynı anda beslenir.
final class TVLink: @unchecked Sendable {
    let hub = DisplayHub()
    private let lock = NSLock()
    private var legacy: LegacyEventServer?
    private var ingress: NinoSenderIngress?
    private var sender: NinoSender?
    private var senderTask: Task<Void, Never>?
    private var legacyCount = 0
    private var ingressCount = 0
    private var senderUp = false
    /// Bağlı TV sayısı değişince (ana iş parçacığında değil).
    var onChange: (@Sendable (Int) -> Void)?
    /// Bir TV uygulaması bağlandı ve sürümünü bildirdi (eski 8787 ya da 47800 girişi; ana iş parçacığında değil).
    var onTVAppVersion: (@Sendable (_ version: String, _ host: String) -> Void)?

    /// Dinlenen portlar (testler; 0: açılamadı).
    private(set) var legacyPort: UInt16 = 0
    private(set) var ingressPort: UInt16 = 0
    private let legacyOptions: LegacyEventServer.Options
    private let ingressPortWanted: UInt16

    init(legacyPort: UInt16 = LegacyEventServer.defaultPort, ingressPort: UInt16 = NinoLink.defaultPort) {
        legacyOptions = LegacyEventServer.Options(port: legacyPort)
        ingressPortWanted = ingressPort
    }

    var connectedCount: Int { lock.withLock { legacyCount + ingressCount + (senderUp ? 1 : 0) } }

    private func update(_ change: () -> Void) {
        let count: Int = lock.withLock {
            change()
            return legacyCount + ingressCount + (senderUp ? 1 : 0)
        }
        onChange?(count)
    }

    private func linkEvent(_ e: DisplayLinkEvent) {
        guard e.kind == .connected, let v = e.appVersion?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return }
        onTVAppVersion?(v, e.host)
    }

    /// Sunucuları açar ve kayıtlı TV'ye bağlanmayı başlatır. `tv` yoksa yalnız sunucular açılır.
    func start(tv: PairedTV?, deviceName: String, version: String) async {
        let legacy = LegacyEventServer(options: legacyOptions)
        legacy.onViewersChange = { [weak self] viewers in
            self?.update { self?.legacyCount = viewers.filter { !$0.isOBS }.count }
        }
        legacy.onLinkEvent = { [weak self] e in self?.linkEvent(e) }
        if let port = try? await legacy.start() {
            legacyPort = port
            await hub.add(legacy, key: "legacy")
            lock.withLock { self.legacy = legacy }
        }
        let ingress = NinoSenderIngress(options: .init(name: deviceName, port: ingressPortWanted, device: "iPhone",
                                                      client: "nino-ios/\(version)", appVersion: version))
        ingress.onDisplaysChange = { [weak self] list in self?.update { self?.ingressCount = list.count } }
        ingress.onLinkEvent = { [weak self] e in self?.linkEvent(e) }
        if let port = try? await ingress.start() {
            ingressPort = port
            await hub.add(ingress, key: "web")
            lock.withLock { self.ingress = ingress }
        }
        guard let tv else { return }
        senderTask = Task { [weak self] in
            while !Task.isCancelled {
                var target: (String, UInt16)?
                if tv.host.isEmpty {
                    if let found = await Displays.discover().first { target = (found.host, found.port) }
                } else if await Displays.probe(host: tv.host) {
                    target = (tv.host, NinoLink.defaultPort)
                }
                if let target, let sender = try? await Displays.connect(host: target.0, port: target.1) {
                    guard let self, !Task.isCancelled else { await sender.disconnect(); return }
                    await self.hub.add(sender, key: "tv")
                    self.lock.withLock { self.sender = sender }
                    while !Task.isCancelled {
                        let up = await sender.state != .disconnected
                        self.update { self.senderUp = up }
                        try? await Task.sleep(for: .seconds(5))
                    }
                    return
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// Altyazı telefonda gösterilecekse TV'ler temizlenir ve yalnız başladı/durdu olayları gider.
    func setSubtitlesOnTV(_ on: Bool) async { await hub.setSubtitlesOnTV(on) }

    func send(_ event: NinoEvent) async { try? await hub.send(event) }

    func stop() async {
        try? await hub.send(.stopped)
        senderTask?.cancel()
        let (legacy, ingress, sender) = lock.withLock { (self.legacy, self.ingress, self.sender) }
        await sender?.disconnect()
        legacy?.stop()
        ingress?.stop()
        lock.withLock {
            self.legacy = nil
            self.ingress = nil
            self.sender = nil
            legacyCount = 0
            ingressCount = 0
            senderUp = false
        }
        onChange?(0)
    }
}

extension SubtitleStyle {
    /// Protokoldeki görünüm mesajı.
    var ninoStyle: NinoStyle {
        NinoStyle(fontSize: fontSize, bottomPercent: bottomPercent, placement: placement, background: background,
                  backgroundShape: backgroundShape, bold: bold, textColor: textColor, displayMode: displayMode,
                  stackPrevious: stackPrevious, theme: theme, autoSize: autoSize, font: font.rawValue, watermark: watermark)
    }
}
