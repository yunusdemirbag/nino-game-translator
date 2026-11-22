// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Gönderici tarafı (Mac/telefon): TV'ye WebSocket ile bağlanır, el sıkışır,
/// altyazı gönderir. Bağlantı koparsa `keepAlive` yeniden bağlanır.
public actor NinoSender {
    public enum SenderError: Error, Equatable {
        case versionUnsupported(theirs: [Int])
        case rejected(code: String)
        case unexpectedReply
        case notConnected
        case timeout
    }

    public enum State: Equatable, Sendable {
        case disconnected
        case connected(version: Int, displayName: String?)
    }

    public let host: String
    public let port: UInt16
    public let device: String?
    public let client: String?
    public let versions: [Int]
    private let session: URLSession

    public private(set) var state: State = .disconnected
    /// TV'den gelen son hata (ör. `replaced`).
    public private(set) var lastError: NinoMessage?
    /// Son gönderilen ve hâlâ ekranda olması gereken altyazı; yeniden bağlanınca tekrar gönderilir.
    public internal(set) var lastShown: ShowPayload?
    /// Son gönderilen `style`; yeniden bağlanınca önce o gönderilir (uzantı).
    public internal(set) var lastStyle: NinoStyle?
    /// `started`'ın gönderildiği an (`stopped` gelince nil). Yeniden bağlanınca, yakın zamandaysa
    /// (`NinoLink.startedReplayWindow`) `started` tekrar gönderilir (uzantı).
    public internal(set) var startedAt: Date?

    private var task: URLSessionWebSocketTask?
    private var pendingPings: [Int64: CheckedContinuation<Void, Error>] = [:]
    private var keepAliveTask: Task<Void, Never>?
    private var pingCounter: Int64 = 0
    private var linkHandler: DisplayLinkEventHandler?
    private var connectedAt: Date?
    private var connectionID = ""

    /// Bağlandı / koptu / zaman aşımı olayları (bkz. `DisplayLinkEvent`, yol `outgoing`).
    public func setLinkEventHandler(_ handler: DisplayLinkEventHandler?) { linkHandler = handler }

    public init(host: String, port: UInt16 = NinoLink.defaultPort, device: String? = nil, client: String? = nil,
                versions: [Int] = NinoLink.supportedVersions, session: URLSession = .shared) {
        self.host = host
        self.port = port
        self.device = device
        self.client = client
        self.versions = versions
        self.session = session
    }

    var url: URL {
        get throws { try NinoLink.url(scheme: "ws", host: host, port: port, path: NinoLink.Path.webSocket) }
    }

    /// Bağlanır ve el sıkışır. TV'nin adını döner.
    @discardableResult
    public func connect(timeout: TimeInterval = NinoLink.handshakeTimeout) async throws -> String? {
        disconnectTask(reason: .localClose)
        var version = versions.max() ?? NinoLink.version
        var tried = Set<Int>()
        while true {
            tried.insert(version)
            let task = session.webSocketTask(with: try url)
            task.maximumMessageSize = NinoLink.maxMessageBytes
            task.resume()
            do {
                try await task.send(.string(NinoMessage.hello(version: version, device: device, client: client).jsonString))
                let reply = try await Self.receiveMessage(task, timeout: timeout)
                switch reply {
                case let .welcome(v, name):
                    self.task = task
                    state = .connected(version: v, displayName: name)
                    lastError = nil
                    connectedAt = Date()
                    connectionID = UUID().uuidString.lowercased()
                    linkHandler?(.connected(.outgoing, host: host, id: connectionID, model: nil, appVersion: nil,
                                            at: connectedAt ?? Date()))
                    startReceiving(task)
                    return name
                case let .error(code, _, theirs) where code == NinoLink.ErrorCode.versionUnsupported:
                    task.cancel(with: .normalClosure, reason: nil)
                    let theirs = theirs ?? []
                    guard let next = NinoLink.bestCommonVersion(theirs, ours: versions), !tried.contains(next) else {
                        throw SenderError.versionUnsupported(theirs: theirs)
                    }
                    version = next
                case let .error(code, _, _):
                    task.cancel(with: .normalClosure, reason: nil)
                    throw SenderError.rejected(code: code)
                default:
                    task.cancel(with: .normalClosure, reason: nil)
                    throw SenderError.unexpectedReply
                }
            } catch {
                task.cancel(with: .goingAway, reason: nil)
                throw error
            }
        }
    }

    public func show(_ payload: ShowPayload) async throws {
        let payload = payload.fittingLimit()
        try await send(.show(payload))
        lastShown = payload.durationMs == 0 ? payload : nil
    }

    public func clear(id: Int? = nil) async throws {
        try await send(.clear(id: id))
        if id == nil || id == lastShown?.id { lastShown = nil }
    }

    /// Ping yollar, `pong` bekler. Gidiş-dönüş süresini saniye olarak döner.
    @discardableResult
    public func ping(timeout: TimeInterval = NinoLink.pongTimeout) async throws -> TimeInterval {
        pingCounter += 1
        let t = Int64(Date().timeIntervalSince1970 * 1000) * 1000 + pingCounter % 1000
        let started = Date()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pendingPings[t] = cont
            Task {
                do { try await self.send(.ping(t: t)) } catch { self.resolvePing(t, error: error) }
            }
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                self.resolvePing(t, error: SenderError.timeout)
            }
        }
        return Date().timeIntervalSince(started)
    }

    public func disconnect() {
        keepAliveTask?.cancel()
        keepAliveTask = nil
        disconnectTask(reason: .localClose)
    }

    /// Düzenli ping atar; cevap gelmezse yeniden bağlanır ve son altyazıyı yeniden yollar.
    public func startKeepAlive(interval: TimeInterval = NinoLink.pingInterval,
                               pongTimeout: TimeInterval = NinoLink.pongTimeout,
                               backoff: ReconnectBackoff = ReconnectBackoff()) {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            var backoff = backoff
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !Task.isCancelled else { return }
                do {
                    if await self.task == nil { throw SenderError.notConnected }
                    try await self.ping(timeout: pongTimeout)
                    backoff.reset()
                } catch {
                    if case SenderError.timeout? = error as? SenderError { await self.dropForTimeout() }
                    let delay = backoff.next()
                    try? await Task.sleep(for: .seconds(delay))
                    if Task.isCancelled { return }
                    await self.reconnect()
                }
            }
        }
    }

    private func dropForTimeout() { if task != nil { disconnectTask(reason: .heartbeatTimeout) } }

    private func reconnect() async {
        do {
            try await connect()
            if let s = lastStyle { try await sendRaw(NinoEvent.style(s).jsonString) }
            if let at = startedAt, Date().timeIntervalSince(at) <= NinoLink.startedReplayWindow {
                try await sendRaw(NinoEvent.started.jsonString)
            }
            if let p = lastShown { try await send(.show(p)) }
        } catch {
            // Bir sonraki turda yeniden denenir.
        }
    }

    // MARK: İç

    private func send(_ m: NinoMessage) async throws {
        try await sendRaw(m.jsonString)
    }

    /// Hazır JSON metnini yollar (uzantı mesajları için; bkz. DisplayHub.swift).
    func sendRaw(_ text: String) async throws {
        guard let task else { throw SenderError.notConnected }
        do {
            try await task.send(.string(text))
        } catch {
            connectionLost(task, reason: .writeFailed)
            throw error
        }
    }

    private func resolvePing(_ t: Int64, error: Error?) {
        guard let cont = pendingPings.removeValue(forKey: t) else { return }
        if let error { cont.resume(throwing: error) } else { cont.resume() }
    }

    private func startReceiving(_ task: URLSessionWebSocketTask) {
        Task { [weak self] in
            while true {
                guard let message = try? await task.receive() else {
                    await self?.connectionLost(task, reason: task.closeCode != .invalid ? .peerClosed : .readFailed)
                    return
                }
                guard case let .string(text) = message, let m = try? NinoMessage(string: text) else { continue }
                await self?.handle(m, from: task)
            }
        }
    }

    private func handle(_ m: NinoMessage, from task: URLSessionWebSocketTask) {
        guard task === self.task else { return }
        switch m {
        case let .pong(t):
            resolvePing(t, error: nil)
        case .error:
            lastError = m
        default:
            break
        }
    }

    private func connectionLost(_ task: URLSessionWebSocketTask, reason: DisplayLinkEvent.Reason) {
        guard task === self.task else { return }
        disconnectTask(reason: reason)
    }

    private func disconnectTask(reason: DisplayLinkEvent.Reason) {
        if task != nil, let since = connectedAt {
            linkHandler?(.dropped(.outgoing, host: host, id: connectionID, model: nil, appVersion: nil,
                                  since: since, reason: reason))
        }
        connectedAt = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        state = .disconnected
        for (_, c) in pendingPings { c.resume(throwing: SenderError.notConnected) }
        pendingPings.removeAll()
    }

    private static func receiveMessage(_ task: URLSessionWebSocketTask, timeout: TimeInterval) async throws -> NinoMessage {
        let raw = try await withTimeout(.seconds(timeout)) { try await task.receive() }
        switch raw {
        case let .string(s): return try NinoMessage(string: s)
        case let .data(d): return try NinoMessage(data: d)
        @unknown default: throw SenderError.unexpectedReply
        }
    }
}

/// Yeniden bağlanma bekleme süreleri: 1, 2, 4, 8, 8, ... saniye.
public struct ReconnectBackoff: Sendable, Equatable {
    public var initial: TimeInterval
    public var maximum: TimeInterval
    private var attempt = 0

    public init(initial: TimeInterval = 1, maximum: TimeInterval = 8) {
        self.initial = initial
        self.maximum = maximum
    }

    public mutating func next() -> TimeInterval {
        defer { attempt += 1 }
        return min(maximum, initial * pow(2, Double(attempt)))
    }

    public mutating func reset() { attempt = 0 }
}

/// WebSocket kullanamayanlar için tek seferlik HTTP çağrıları.
public enum NinoHTTPClient {
    public enum ClientError: Error, Equatable { case status(Int), badReply }


    public static func info(host: String, port: UInt16 = NinoLink.defaultPort, session: URLSession = .shared) async throws -> NinoMessage {
        let (data, response) = try await session.data(from: try NinoLink.url(scheme: "http", host: host, port: port, path: NinoLink.Path.info))
        try check(response)
        let m = try NinoMessage(data: data)
        guard case .info = m else { throw ClientError.badReply }
        return m
    }

    public static func show(_ p: ShowPayload, host: String, port: UInt16 = NinoLink.defaultPort, session: URLSession = .shared) async throws {
        try await post(.show(p), path: NinoLink.Path.show, host: host, port: port, session: session)
    }

    public static func clear(id: Int?, host: String, port: UInt16 = NinoLink.defaultPort, session: URLSession = .shared) async throws {
        try await post(.clear(id: id), path: NinoLink.Path.clear, host: host, port: port, session: session)
    }

    private static func post(_ m: NinoMessage, path: String, host: String, port: UInt16, session: URLSession) async throws {
        var r = URLRequest(url: try NinoLink.url(scheme: "http", host: host, port: port, path: path))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = m.encoded()
        let (data, response) = try await session.data(for: r)
        try check(response)
        guard (try? NinoMessage(data: data)) == .ok else { throw ClientError.badReply }
    }

    private static func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.status(http.statusCode)
        }
    }
}
