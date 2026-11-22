// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// Eşli PS5'e Remote Play ile bağlanır ve kareleri okuma hattına verir (kaynaklar.md §1).
///
/// `frames()` uzun ömürlü tek bir akıştır: oturumlar kopup yeniden kurulsa da akış sürer;
/// yalnız `stop()` (ya da akışın tüketicisi bırakınca) biter. Durum değişiklikleri `onStatus` ile,
/// PS5'in yeni adresi `onPairingChanged` ile bildirilir. İkisi de arka iş parçacığından çağrılır.
public final class ConsoleSessionController: FrameSource, @unchecked Sendable {
    public struct Configuration: Sendable {
        /// Kayıtlı adrese arama süresi.
        public var probeDuration: TimeInterval = 2
        /// Tüm ağ taraması süresi.
        public var scanDuration: TimeInterval = 3
        /// Dinlenmedeki PS5'in uyanması için en çok beklenen süre ve aramalar arası.
        public var wakeWait: TimeInterval = 20
        public var wakePollInterval: TimeInterval = 2
        /// Bağlıyken bu kadar kare gelmezse oturum yeniden kurulur.
        public var watchdog: TimeInterval = 8
        /// PS5 bu sürede "bağlandı" demezse deneme kapatılır.
        public var connectTimeout: TimeInterval = 30
        /// Okuma hattına en çok saniyede 20 kare.
        public var minFrameInterval: TimeInterval = 0.05
        /// Bekçinin bakma aralığı.
        public var tick: TimeInterval = 1

        public init() {}
    }

    public let store: ConsoleRecordStore
    public let discovery: ConsoleDiscovering
    public let connector: RemotePlayConnecting
    public let clock: ConsoleClock
    public let log: ConsoleLog
    public let configuration: Configuration

    private let lock = NSLock()
    private var loop: Task<Void, Never>?
    private var frameContinuation: AsyncStream<Frame>.Continuation?
    private var currentLink: RemotePlayLink?
    private var policy = ReconnectPolicy()
    private var lastScan: TimeInterval?
    private var statusHandler: (@Sendable (SourceStatus.ConsoleLink) -> Void)?
    private var pairingHandler: (@Sendable (PS5Pairing) -> Void)?
    private var _status: SourceStatus.ConsoleLink = .idle

    public init(store: ConsoleRecordStore, discovery: ConsoleDiscovering, connector: RemotePlayConnecting,
                clock: ConsoleClock = SystemConsoleClock(), log: ConsoleLog = .discard,
                configuration: Configuration = Configuration()) {
        self.store = store
        self.discovery = discovery
        self.connector = connector
        self.clock = clock
        self.log = log
        self.configuration = configuration
    }

    // MARK: Dışarıya açık

    public var onStatus: (@Sendable (SourceStatus.ConsoleLink) -> Void)? {
        get { lock.withLock { statusHandler } }
        set { lock.withLock { statusHandler = newValue } }
    }

    /// PS5 başka bir adreste bulundu; kayıt kasaya yeni adresle yazıldı.
    public var onPairingChanged: (@Sendable (PS5Pairing) -> Void)? {
        get { lock.withLock { pairingHandler } }
        set { lock.withLock { pairingHandler = newValue } }
    }

    public var status: SourceStatus.ConsoleLink { lock.withLock { _status } }

    /// Kareler. Çağrılınca bağlanma başlar; öncekiler durdurulur.
    public func frames() -> AsyncStream<Frame> {
        stop()
        let (stream, continuation) = AsyncStream<Frame>.makeStream(bufferingPolicy: .bufferingNewest(1))
        lock.withLock {
            frameContinuation = continuation
            policy.reset()
            lastScan = nil
        }
        continuation.onTermination = { [weak self] _ in self?.stop() }
        startLoop()
        return stream
    }

    /// Bağlantıyı kapatır, kare akışını bitirir.
    public func stop() {
        let (task, link, continuation) = lock.withLock { () -> (Task<Void, Never>?, RemotePlayLink?, AsyncStream<Frame>.Continuation?) in
            defer {
                loop = nil
                currentLink = nil
                frameContinuation = nil
            }
            return (loop, currentLink, frameContinuation)
        }
        guard task != nil || link != nil || continuation != nil else { return }
        task?.cancel()
        if let link { Task.detached { link.close() } }
        continuation?.finish()
        setStatus(.idle)
    }

    /// Uygulamadan "hemen yeniden bağlan" (Mac uyandı, ağ değişti): sayaçlar sıfırlanır, oturum baştan kurulur.
    public func reconnectNow() {
        let (task, link, running) = lock.withLock { () -> (Task<Void, Never>?, RemotePlayLink?, Bool) in
            policy.reset()
            lastScan = nil
            defer {
                loop = nil
                currentLink = nil
            }
            return (loop, currentLink, frameContinuation != nil)
        }
        task?.cancel()
        if let link { Task.detached { link.close() } }
        guard running else { return }
        log.write("PS5: hemen yeniden bağlanılıyor")
        startLoop()
    }

    // MARK: Döngü

    private func startLoop() {
        let task = Task.detached { [weak self] in
            guard let self else { return }
            await self.run()
        }
        lock.withLock { loop = task }
    }

    private func run() async {
        while !Task.isCancelled {
            setStatus(.connecting)
            let outcome = await attempt()
            if Task.isCancelled { return }
            let decision = lock.withLock { policy.next(after: outcome) }
            switch decision {
            case let .giveUp(reason):
                log.write("PS5 bağlantısı bırakıldı: \(describe(reason))")
                setStatus(.dropped(reason))
                return
            case let .retry(delay, reason):
                log.write("PS5 bağlantısı yok: \(describe(reason)); \(Int(delay)) sn sonra yeniden denenecek")
                setStatus(.dropped(reason))
                do { try await clock.sleep(seconds: delay) } catch { return }
            }
        }
    }

    /// Bir bağlanma denemesi: adres, uyandırma, oturum.
    private func attempt() async -> ConsoleAttemptOutcome {
        guard let stored = try? store.loadPairing(), stored.hasUsableKeys else {
            return ConsoleAttemptOutcome(reason: .pairingInvalid)
        }
        var pairing = stored
        let saved = ConsoleInput.isUsableAddress(pairing.host) ? pairing.host : nil

        var found: DiscoveredPS5?
        if let saved {
            found = try? await discovery.probe(address: saved, duration: configuration.probeDuration)
        }
        if Task.isCancelled { return ConsoleAttemptOutcome(reason: .other(detail: nil)) }
        let mayScan = lock.withLock { ConsoleLocator.mayScanWholeNetwork(lastScan: lastScan, now: clock.now()) }
        if found == nil, mayScan {
            lock.withLock { lastScan = clock.now() }
            let all = (try? await discovery.search(duration: configuration.scanDuration)) ?? []
            if let pick = ConsoleLocator.pick(from: all, name: pairing.name) {
                found = pick
                if pick.address != pairing.host, ConsoleInput.isUsableAddress(pick.address) {
                    log.write("PS5 adresi değişti: \(pairing.host) → \(pick.address)")
                    pairing.host = pick.address
                    try? store.savePairing(pairing)
                    let handler = lock.withLock { pairingHandler }
                    handler?(pairing)
                }
            }
        }
        if Task.isCancelled { return ConsoleAttemptOutcome(reason: .other(detail: nil)) }
        guard let address = found?.address ?? saved else {
            return ConsoleAttemptOutcome(reason: .network)
        }

        if let console = found, console.asleep {
            log.write("PS5: \(pairing.name) \(address) dinlenmede, uyandırılıyor")
            do { try connector.wake(address: address, pairing: pairing) } catch {
                log.write("PS5 uyandırma hatası: \(error)")
            }
            guard let awake = await waitUntilAwake(address: address) else {
                return ConsoleAttemptOutcome(reason: .asleep)
            }
            found = awake
        } else {
            log.write("PS5: \(pairing.name) \(address)" + (found == nil ? " (aramaya cevap yok)" : " uyanık"))
        }
        if Task.isCancelled { return ConsoleAttemptOutcome(reason: .other(detail: nil)) }
        return await runSession(address: address, pairing: pairing, console: found, probeAnswered: found != nil)
    }

    private func waitUntilAwake(address: String) async -> DiscoveredPS5? {
        let deadline = clock.now() + configuration.wakeWait
        while clock.now() < deadline {
            do { try await clock.sleep(seconds: configuration.wakePollInterval) } catch { return nil }
            if let c = try? await discovery.probe(address: address, duration: configuration.probeDuration), !c.asleep {
                return c
            }
        }
        return nil
    }

    private enum Input: Sendable {
        case event(RemotePlayLinkEvent)
        case closed
        case tick
    }

    private func runSession(address: String, pairing: PS5Pairing, console: DiscoveredPS5?,
                            probeAnswered: Bool) async -> ConsoleAttemptOutcome {
        let link: RemotePlayLink
        do {
            link = try connector.open(address: address, pairing: pairing, console: console)
        } catch {
            let reason = DropClassifier.classify(quitReason: "\(error)", log: [], probeAnswered: probeAnswered,
                                                 address: address) ?? .other(detail: nil)
            return ConsoleAttemptOutcome(reason: reason)
        }
        lock.withLock { currentLink = link }
        if Task.isCancelled {
            link.close()
            return ConsoleAttemptOutcome(reason: .other(detail: nil))
        }

        let (inputs, input) = AsyncStream<Input>.makeStream()
        let events = link.events
        let forward = Task {
            for await e in events { input.yield(.event(e)) }
            input.yield(.closed)
        }
        let clock = self.clock
        let tick = configuration.tick
        let ticker = Task {
            while !Task.isCancelled {
                do { try await clock.sleep(seconds: tick) } catch { break }
                input.yield(.tick)
            }
        }

        let start = clock.now()
        var connectedAt: TimeInterval?
        var frameCount = 0
        var lastFrame: TimeInterval?
        var lastYield = -Double.infinity
        var sentPasscode = false
        var reason: SourceStatus.DropReason?

        loop: for await item in inputs {
            if Task.isCancelled { break }
            let now = clock.now()
            switch item {
            case .event(.connected):
                connectedAt = now
                log.write("PS5: bağlandı")
            case let .event(.frame(frame)):
                if connectedAt == nil { connectedAt = now }
                frameCount += 1
                lastFrame = now
                if frameCount == 1 { setStatus(.streaming) }
                if now - lastYield >= configuration.minFrameInterval {
                    lastYield = now
                    let c = lock.withLock { frameContinuation }
                    c?.yield(frame)
                }
            case let .event(.passcodeRequested(incorrect)):
                if incorrect || sentPasscode {
                    reason = sentPasscode ? .passcodeWrong : .passcodeRequired
                    break loop
                }
                let saved = (try? store.loadLoginPasscode())?.flatMap(ConsoleInput.loginPasscode)
                guard link.canSubmitPasscode, let code = saved else {
                    reason = .passcodeRequired
                    break loop
                }
                log.write("PS5 giriş şifresi istedi; kayıtlı şifre gönderildi")
                link.submitPasscode(code)
                sentPasscode = true
            case let .event(.ended(quitReason, lines)):
                log.write("PS5 oturumu kapandı: \(quitReason)")
                reason = DropClassifier.classify(quitReason: quitReason, log: lines, probeAnswered: probeAnswered,
                                                 address: address) ?? .other(detail: nil)
                break loop
            case .closed:
                break loop
            case .tick:
                if let c = connectedAt {
                    if now - (lastFrame ?? c) >= configuration.watchdog {
                        log.write("PS5: \(Int(configuration.watchdog)) sn kare gelmedi, oturum yeniden kurulacak")
                        reason = .other(detail: nil)
                        break loop
                    }
                } else if now - start >= configuration.connectTimeout {
                    log.write("PS5: \(Int(configuration.connectTimeout)) sn içinde bağlanılamadı")
                    reason = probeAnswered ? .other(detail: nil) : .notFound(address: address)
                    break loop
                }
            }
        }
        forward.cancel()
        ticker.cancel()
        input.finish()
        link.close()
        lock.withLock { if currentLink === link { currentLink = nil } }

        let end = clock.now()
        return ConsoleAttemptOutcome(reason: reason ?? .other(detail: nil), connected: connectedAt != nil,
                                     gotFrames: frameCount > 0, duration: connectedAt.map { end - $0 } ?? 0)
    }

    // MARK: Yardımcılar

    private func setStatus(_ s: SourceStatus.ConsoleLink) {
        let handler = lock.withLock { () -> (@Sendable (SourceStatus.ConsoleLink) -> Void)? in
            guard _status != s else { return nil }
            _status = s
            return statusHandler
        }
        handler?(s)
    }

    private func describe(_ r: SourceStatus.DropReason) -> String { "\(r)" }
}
