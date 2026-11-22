// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Network

/// ADB bağlantısının hataları.
public enum ADBError: Error, Equatable, Sendable {
    /// TCP bağlantısı kurulamadı.
    case unreachable(String)
    /// Bağlantı koptu ya da karşı taraf kapattı.
    case connectionClosed(String)
    /// Okuma/yazma süresi doldu.
    case timeout
    /// TV'de hata ayıklama onayı verilmedi (süre doldu ya da bağlantı kesildi).
    case notApproved
    /// TV TLS istedi (Android 11+ "kablosuz hata ayıklama" eşleştirmesi; 5555'te beklenmez).
    case tlsRequired
    /// Hizmet açılamadı (TV OPEN'ı CLSE ile geri çevirdi).
    case openRefused(String)
    case protocolError(String)
}

/// Bayt akışı (TCP ya da testte bellek içi boru).
public protocol ADBByteStream: AnyObject, Sendable {
    func write(_ data: Data) async throws
    /// En az 1, en çok `max` bayt. Akış kapanınca `connectionClosed`, süre dolunca `timeout` (ve akış kapanır).
    func read(max: Int, timeout: TimeInterval) async throws -> Data
    func close()
}

public protocol ADBConnecting: Sendable {
    func connect(host: String, port: UInt16, timeout: TimeInterval) async throws -> ADBByteStream
}

/// Tek kez çalışan geri çağrı için kilit.
final class ADBOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

// MARK: Network.framework ile TCP

public struct NWADBConnector: ADBConnecting {
    public init() {}

    public func connect(host: String, port: UInt16, timeout: TimeInterval) async throws -> ADBByteStream {
        guard let p = NWEndpoint.Port(rawValue: port) else { throw ADBError.unreachable("port") }
        let options = NWProtocolTCP.Options()
        options.noDelay = true
        options.connectionTimeout = max(1, Int(timeout.rounded(.up)))
        let connection = NWConnection(host: NWEndpoint.Host(host), port: p, using: NWParameters(tls: nil, tcp: options))
        let queue = DispatchQueue(label: "nino.adb.\(host)")
        let once = ADBOnce()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { cont.resume() }
                case let .failed(e), let .waiting(e):
                    if once.claim() { connection.cancel(); cont.resume(throwing: ADBError.unreachable("\(e)")) }
                case .cancelled:
                    if once.claim() { cont.resume(throwing: ADBError.unreachable("cancelled")) }
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                if once.claim() { connection.cancel(); cont.resume(throwing: ADBError.unreachable("timeout")) }
            }
        }
        connection.stateUpdateHandler = nil
        return NWADBStream(connection: connection, queue: queue)
    }
}

final class NWADBStream: ADBByteStream, @unchecked Sendable {
    let connection: NWConnection
    let queue: DispatchQueue

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    func write(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: ADBError.connectionClosed("\(error)")) } else { cont.resume() }
            })
        }
    }

    func read(max: Int, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            let once = ADBOnce()
            let timer = DispatchWorkItem { [connection] in
                if once.claim() { connection.cancel(); cont.resume(throwing: ADBError.timeout) }
            }
            queue.asyncAfter(deadline: .now() + timeout, execute: timer)
            connection.receive(minimumIncompleteLength: 1, maximumLength: max) { data, _, isComplete, error in
                timer.cancel()
                guard once.claim() else { return }
                if let data, !data.isEmpty { cont.resume(returning: data); return }
                if let error { cont.resume(throwing: ADBError.connectionClosed("\(error)")); return }
                cont.resume(throwing: ADBError.connectionClosed(isComplete ? "eof" : "no data"))
            }
        }
    }

    func close() { connection.cancel() }
}
