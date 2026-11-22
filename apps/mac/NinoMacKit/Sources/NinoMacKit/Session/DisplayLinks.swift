// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// TV'ye giden bütün yollar tek `DisplayHub` arkasında (protokol.md "Bütün çıkışlar"):
/// - giden bağlantı (`NinoSender`): dinleyen TV'ye (Android TV uygulaması, 47800),
/// - gelen TV'ler (`NinoSenderIngress`, 47800): dinleyemeyen web TV'ler (LG, Samsung) bize bağlanır,
/// - eski 8787 sunucusu (`LegacyEventServer`): eski TV uygulamaları ve OBS.
///
/// Sunucular yalnız `start()` ile (çeviri başlarken) açılır: açılışta port tutulmaz, yanında açık başka bir Nino'nun
/// TV'si çalınmaz.
public final class DisplayLinks: @unchecked Sendable {
    public struct Ports: Sendable, Equatable {
        /// Gelen TV'ler (0: sistem seçer; testler).
        public var ingress: UInt16
        /// Eski sunucu.
        public var legacy: UInt16
        /// Dinleyen TV'nin portu.
        public var tv: UInt16
        /// Port doluysa rastgele porta geçilsin mi (yalnız testler; TV sabit portu tarar).
        public var randomFallback: Bool

        public init(ingress: UInt16 = NinoLink.defaultPort, legacy: UInt16 = LegacyEventServer.defaultPort,
                    tv: UInt16 = NinoLink.defaultPort, randomFallback: Bool = true) {
            self.ingress = ingress
            self.legacy = legacy
            self.tv = tv
            self.randomFallback = randomFallback
        }

        public static let standard = Ports()
        /// Testler: hepsi sistemin seçtiği port.
        public static let ephemeral = Ports(ingress: 0, legacy: 0, tv: NinoLink.defaultPort, randomFallback: false)
    }

    public let hub = DisplayHub()
    /// Oturumun ve deneme altyazısının yazdığı çıkış: hub'a iletir, son altyazının yerini tutar.
    public let recorder: RecordingOutput
    public var output: any DisplayOutput { recorder }
    public let ports: Ports
    public let senderName: String
    public let appVersion: String
    public private(set) var ingress: NinoSenderIngress?
    public private(set) var legacy: LegacyEventServer?
    /// Gerçek portlar (açıldıktan sonra).
    public private(set) var ingressPort: UInt16?
    public private(set) var legacyPort: UInt16?
    public private(set) var notes: [String] = []

    private let lock = NSLock()
    private var senders: [String: NinoSender] = [:]
    private var ingressCount = 0
    private var legacyCount = 0
    private var senderConnected: Set<String> = []
    private var watch: Task<Void, Never>?
    private var countHandler: (@Sendable (Int) -> Void)?
    private var linkHandler: DisplayLinkEventHandler?
    /// Web TV'lere yeni protokolün girişi (47800) mi verilsin; varsayılan eski sunucu (8787).
    public var webTVUsesIngress = false

    public init(ports: Ports = .standard, senderName: String = "Nino", appVersion: String) {
        self.ports = ports
        self.senderName = senderName
        self.appVersion = appVersion
        self.recorder = RecordingOutput(hub: hub)
    }

    private let serverGate = SerialGate()

    /// Bağlı TV sayısı değişince (her kuyruktan çağrılabilir).
    public var onCountChange: (@Sendable (Int) -> Void)? {
        get { lock.withLock { countHandler } }
        set { lock.withLock { countHandler = newValue } }
    }

    /// Her TV bağlantısının bağlandı / koptu / zaman aşımı olayı (üç yoldan; her kuyruktan çağrılabilir).
    public var onLinkEvent: DisplayLinkEventHandler? {
        get { lock.withLock { linkHandler } }
        set { lock.withLock { linkHandler = newValue } }
    }

    private var forwardLinkEvent: DisplayLinkEventHandler {
        { [weak self] e in
            guard let self else { return }
            let h = self.lock.withLock { self.linkHandler }
            h?(e)
        }
    }

    public var connectedCount: Int { lock.withLock { ingressCount + legacyCount + senderConnected.count } }

    // MARK: Aç / kapat

    /// Sunucuları açar ve dinleyen TV'lere bağlanır. Açılamayan sunucu not edilir, ötekiler sürer.
    public func start(tvHosts: [String]) async {
        await startServers()
        // Dinleyen TV kapalıysa bağlanma beklemesi kaynağı geciktirmesin.
        for host in tvHosts { Task { await self.connect(tvHost: host) } }
        startWatch()
    }

    /// Yalnız sunucular (kapalıysa açar; açıksa bir şey yapmaz).
    public func startServers() async {
        await serverGate.run { await self.openServers() }
    }

    private func openServers() async {
        if ingress == nil {
            let options = NinoSenderIngress.Options(name: senderName, port: ports.ingress, device: "Mac",
                                                    client: "nino-mac", appVersion: appVersion)
            let server = NinoSenderIngress(options: options)
            server.onDisplaysChange = { [weak self] list in self?.update { $0.ingressCount = list.count } }
            server.onLinkEvent = forwardLinkEvent
            do {
                ingressPort = try await server.start()
                ingress = server
                await hub.add(server, key: "ingress")
            } catch {
                note("TV girişi (\(ports.ingress)) açılamadı: \(error)")
            }
        }
        if legacy == nil {
            let server = LegacyEventServer(options: .init(port: ports.legacy, randomPortFallback: ports.randomFallback))
            server.onViewersChange = { [weak self] viewers in
                self?.update { $0.legacyCount = viewers.filter { !$0.isOBS }.count }
            }
            server.onLinkEvent = forwardLinkEvent
            do {
                legacyPort = try await server.start()
                legacy = server
                await hub.add(server, key: "legacy")
            } catch {
                note("Eski TV sunucusu (\(ports.legacy)) açılamadı: \(error)")
            }
        }
    }

    public var isRunning: Bool { ingress != nil || legacy != nil }

    /// Dinleyen bir TV'ye bağlanır (kopunca kendisi yeniden dener).
    public func connect(tvHost host: String, port: UInt16? = nil) async {
        let key = "tv:\(host)"
        guard lock.withLock({ senders[key] }) == nil else { return }
        let sender = NinoSender(host: host, port: port ?? ports.tv, device: "Mac", client: "nino-mac")
        lock.withLock { senders[key] = sender }
        await sender.setLinkEventHandler(forwardLinkEvent)
        _ = try? await sender.connect()
        await sender.startKeepAlive()
        await hub.add(sender, key: key)
        await refreshSenders()
    }

    /// Dinleyen TV'lerden kopar (sunucular açık kalır: TV kurulumu ve yeniden bağlanan TV'ler için).
    public func disconnectTVs() async {
        watch?.cancel()
        watch = nil
        let all = lock.withLock { () -> [(String, NinoSender)] in
            defer { senders = [:]; senderConnected = [] }
            return Array(senders)
        }
        for (key, s) in all {
            await s.disconnect()
            await hub.remove(key: key)
        }
        emitCount()
    }

    public func stop() async {
        watch?.cancel()
        watch = nil
        let all = lock.withLock { () -> [(String, NinoSender)] in
            defer { senders = [:]; senderConnected = []; ingressCount = 0; legacyCount = 0 }
            return Array(senders)
        }
        for (key, s) in all {
            await s.disconnect()
            await hub.remove(key: key)
        }
        if let ingress {
            await hub.remove(key: "ingress")
            ingress.stop()
        }
        if let legacy {
            await hub.remove(key: "legacy")
            legacy.stop()
        }
        ingress = nil
        legacy = nil
        ingressPort = nil
        legacyPort = nil
        emitCount()
    }

    // MARK: İç

    private func startWatch() {
        watch?.cancel()
        watch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await self?.refreshSenders()
            }
        }
    }

    private func refreshSenders() async {
        let all = lock.withLock { Array(senders) }
        var connected = Set<String>()
        for (key, s) in all {
            if case .connected = await s.state { connected.insert(key) }
        }
        update { $0.senderConnected = connected }
    }

    private func update(_ change: (DisplayLinks) -> Void) {
        let (before, after, handler) = lock.withLock { () -> (Int, Int, (@Sendable (Int) -> Void)?) in
            let b = ingressCount + legacyCount + senderConnected.count
            change(self)
            return (b, ingressCount + legacyCount + senderConnected.count, countHandler)
        }
        if before != after { handler?(after) }
    }

    private func emitCount() {
        let (n, handler) = lock.withLock { (ingressCount + legacyCount + senderConnected.count, countHandler) }
        handler?(n)
    }

    private func note(_ s: String) { lock.withLock { notes.append(s) } }
}

// MARK: - TV kurulumunun sunucusu

extension DisplayLinks: TVSubtitleServer {
    public func ensureRunning() async throws { await startServers() }

    /// LG/Samsung uygulamasına verilen sunucu portu. Bugünkü web TV uygulamaları eski düzeni (8787 SSE) bekliyor;
    /// yeni protokole geçen web TV için `webTVUsesIngress` açılır (47800).
    public func port() async -> UInt16 {
        if webTVUsesIngress { return ingressPort ?? ports.ingress }
        return legacyPort ?? ports.legacy
    }

    public func connectedTVApps() async -> [String?] {
        var out: [String?] = []
        if let ingress { out += ingress.displays.map(\.appVersion) }
        if let legacy { out += legacy.connectedTVs.map(\.appVersion) }
        out += Array(repeating: nil, count: lock.withLock { senderConnected.count })
        return out
    }

    public func lastSubtitleBox() async -> NinoBox? { await recorder.lastBox }
}

/// Hub'a ileten ve son altyazının yerini tutan çıkış.
public actor RecordingOutput: DisplayOutput {
    public let hub: DisplayHub
    public private(set) var lastBox: NinoBox?
    public init(hub: DisplayHub) { self.hub = hub }

    public func show(_ payload: ShowPayload) async throws {
        if let b = payload.box { lastBox = b }
        try await hub.show(payload)
    }

    public func clear(id: Int?) async throws { try await hub.clear(id: id) }
    public func send(_ event: NinoEvent) async throws { try await hub.send(event) }
}

/// Aynı anda tek iş (sunucuların iki kez açılmaması için).
actor SerialGate {
    private var running: Task<Void, Never>?
    func run(_ work: @escaping @Sendable () async -> Void) async {
        if let r = running { await r.value }
        let t = Task { await work() }
        running = t
        await t.value
    }
}

// MARK: - Ayardan TV görünümü

public extension NinoStyle {
    /// Ayarlardaki altyazı görünümü (veri-uyumu.md `style`) → TV'nin `style` mesajı.
    init(_ s: SubtitleStyle) {
        self.init(fontSize: s.fontSize, bottomPercent: s.bottomPercent, placement: s.placement.rawValue,
                  background: s.background, backgroundShape: s.backgroundShape.rawValue, bold: s.bold,
                  textColor: s.textColor.rawValue, displayMode: s.displayMode.rawValue,
                  stackPrevious: s.stackPrevious, theme: s.theme.rawValue, autoSize: s.autoSize,
                  font: s.font.rawValue, watermark: s.watermark)
    }
}
