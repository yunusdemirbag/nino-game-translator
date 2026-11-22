// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore
import NinoRemotePlay

// NinoRemotePlay'e bağlanan gerçek kapılar. Testler bunları HİÇ kurmaz (arama bile ağa paket yollar).

extension DiscoveredPS5 {
    init(_ info: ConsoleInfo) {
        self.init(hostID: info.hostID, name: info.name, address: info.address, asleep: info.state == .standby,
                  isPS5: info.isPS5, runningApp: info.runningAppName, target: info.target,
                  runningAppID: info.runningAppTitleID)
    }
}

/// Kitaplığın arama nesnesi `ConsoleInfo` verir; kayıt için gerektiğinden adresine göre saklanır.
private final class ConsoleInfoCache: @unchecked Sendable {
    static let shared = ConsoleInfoCache()
    private let lock = NSLock()
    private var byAddress: [String: ConsoleInfo] = [:]

    func put(_ infos: [ConsoleInfo]) { lock.withLock { for i in infos { byAddress[i.address] = i } } }
    func get(_ address: String) -> ConsoleInfo? { lock.withLock { byAddress[address] } }
}

private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var byKey: [String: ConsoleInfo] = [:]
    func merge(_ list: [ConsoleInfo]) {
        lock.withLock { for i in list { byKey[i.hostID.isEmpty ? i.address : i.hostID] = i } }
    }
    var all: [ConsoleInfo] { lock.withLock { Array(byKey.values) } }
}

/// Yerel ağda PS5 arar. Kitaplık yalnız genel yayınla arar; adrese arama, sonuçları süzerek yapılır.
public struct RemotePlayDiscovery: ConsoleDiscovering {
    public init() {}

    public func search(duration: TimeInterval) async throws -> [DiscoveredPS5] {
        let discovery = ConsoleDiscovery()
        let stream = try discovery.consoles(pingInterval: 0.5)
        let collected = Collected()
        let collector = Task { for await list in stream { collected.merge(list) } }
        try? await Task.sleep(nanoseconds: UInt64(max(0, duration) * 1_000_000_000))
        discovery.stop()
        collector.cancel()
        let infos = collected.all
        ConsoleInfoCache.shared.put(infos)
        return infos.map(DiscoveredPS5.init).sorted { $0.name < $1.name }
    }

    public func probe(address: String, duration: TimeInterval) async throws -> DiscoveredPS5? {
        // Yalnız o adrese sorulur (bütün ağa yayın yapılmaz).
        guard let info = try await ConsoleDiscovery().probe(host: address, timeout: duration) else { return nil }
        ConsoleInfoCache.shared.put([info])
        return DiscoveredPS5(info)
    }
}

/// Eşleştirme isteği. Kitaplık PS5'in `ConsoleInfo`'sunu ister; bu yüzden adres aramada görülmüş olmalı.
public struct RemotePlayRegistrar: ConsoleRegistering {
    public let discovery: RemotePlayDiscovery

    public init(discovery: RemotePlayDiscovery = RemotePlayDiscovery()) {
        self.discovery = discovery
    }

    public func register(address: String, console: DiscoveredPS5?, accountID: Data, pin: UInt32) async throws
        -> RegistrationResult {
        var info = ConsoleInfoCache.shared.get(address)
        if info == nil {
            _ = try? await discovery.search(duration: 3)
            info = ConsoleInfoCache.shared.get(address)
        }
        guard let info else { throw RegistrationFailure(consoleNotFound: true) }
        do {
            let reg = try await ConsoleRegistration.register(console: info, accountID: Array(accountID), pin: pin)
            return RegistrationResult(name: reg.nickname, registKey: Data(reg.registKey), morning: Data(reg.rpKey),
                                      hostID: reg.hostID)
        } catch let e as RegistrationError {
            throw RegistrationFailure(reasonCode: e.applicationReason, logLines: e.log, timedOut: e.reason == .timeout,
                                      consoleNotFound: e.reason == .unreachable || e.reason == .badAddress,
                                      message: e.description)
        } catch let e as RemotePlayError {
            switch e {
            case .timeout: throw RegistrationFailure(timedOut: true, message: e.description)
            case .registrationCanceled: throw RegistrationFailure(canceled: true, message: e.description)
            case let .library(message): throw RegistrationFailure(logLines: [message], message: message)
            default: throw RegistrationFailure(message: e.description)
            }
        }
    }
}

extension PS5Pairing {
    /// Kitaplığın biçimi. Eski kayıtta olmayan kimlik ve hedef, aramadan geldiyse oradan tamamlanır.
    func registeredConsole(discovered: DiscoveredPS5?) throws -> RegisteredConsole {
        RegisteredConsole(hostID: discovered?.hostID ?? "", nickname: name, isPS5: true,
                          target: discovered?.target ?? PS5Target.default,
                          registKey: Array(registKey), rpKey: Array(morning), serverMAC: [])
    }
}

/// Oturum açar ve uyandırır.
public struct RemotePlayConnector: RemotePlayConnecting {
    /// 1080p, 30 kare/sn; okuma hattına saniyede en çok 20 kare.
    public var options = RemotePlaySession.Options(resolution: 4, fps: 30, maxFrameRate: 20)

    public init() {}

    public func open(address: String, pairing: PS5Pairing, console: DiscoveredPS5?) throws -> RemotePlayLink {
        RemotePlaySessionLink(session: RemotePlaySession(address: address,
                                                         console: try pairing.registeredConsole(discovered: console),
                                                         options: options))
    }

    public func wake(address: String, pairing: PS5Pairing) throws {
        try RemotePlaySession.wake(address: address, console: pairing.registeredConsole(discovered: nil))
    }
}

/// `RemotePlaySession`'ı olay akışına çevirir.
///
/// Giriş şifresi isteği kitaplığın olayıyla gelir, şifre `sendLoginPIN` ile gönderilir.
final class RemotePlaySessionLink: RemotePlayLink, @unchecked Sendable {
    let session: RemotePlaySession
    let events: AsyncStream<RemotePlayLinkEvent>
    private let continuation: AsyncStream<RemotePlayLinkEvent>.Continuation
    private let lock = NSLock()
    private var tasks: [Task<Void, Never>] = []
    private var closed = false

    var canSubmitPasscode: Bool { true }

    init(session: RemotePlaySession) {
        self.session = session
        (events, continuation) = AsyncStream<RemotePlayLinkEvent>.makeStream()
        let cont = continuation
        // Olaylar önce alınır: `frames()` oturumu başlatır, erken olaylar kaçmasın.
        let sessionEvents = session.events()
        let frames = session.frames()
        let eventTask = Task {
            for await e in sessionEvents {
                switch e {
                case .connected: cont.yield(.connected)
                case let .loginPINRequested(incorrect): cont.yield(.passcodeRequested(incorrect: incorrect))
                case let .quit(reason):
                    cont.yield(.ended(quitReason: reason, log: session.recentLog))
                    cont.finish()
                case .log: break
                }
            }
        }
        let frameTask = Task { for await f in frames { cont.yield(.frame(f)) } }
        tasks = [eventTask, frameTask]
    }

    func submitPasscode(_ code: String) { try? session.sendLoginPIN(code) }

    func close() {
        let shouldStop = lock.withLock { () -> Bool in
            defer { closed = true }
            return !closed
        }
        guard shouldStop else { return }
        tasks.forEach { $0.cancel() }
        continuation.finish()
        // Kitaplık kapanışta kendi kilidini tutarken akışı bitirir ve `stop()`'a geri döner; o iş parçacığı
        // kilitlenebilir. Burada beklenirse yeniden bağlanma da durur; bu yüzden ayrı görevde durdurulur.
        let session = self.session
        Task.detached { session.stop() }
    }
}

public extension ConsolePairer {
    /// Gerçek ağla çalışan eşleştirici.
    static func live(store: ConsoleRecordStore, log: ConsoleLog) -> ConsolePairer {
        let discovery = RemotePlayDiscovery()
        return ConsolePairer(discovery: discovery, registrar: RemotePlayRegistrar(discovery: discovery), store: store,
                             log: log)
    }
}

public extension ConsoleSessionController {
    /// Gerçek ağla çalışan oturum denetleyicisi.
    static func live(store: ConsoleRecordStore, log: ConsoleLog) -> ConsoleSessionController {
        ConsoleSessionController(store: store, discovery: RemotePlayDiscovery(), connector: RemotePlayConnector(), log: log)
    }
}
