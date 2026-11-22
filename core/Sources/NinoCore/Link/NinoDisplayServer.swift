// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Network

/// TV tarafı: Nino Bağlantı Protokolü sunucusu. HTTP ve WebSocket aynı
/// bağlantı noktasındadır. İsteğe bağlı olarak kendini Bonjour ile yayınlar.
///
/// Tüm iş tek bir seri kuyrukta yürür. Ekran değişince `onChange` çağrılır.
public final class NinoDisplayServer: @unchecked Sendable {
    public struct Options: Sendable {
        public var name: String
        public var id: String
        public var port: UInt16
        public var advertise: Bool
        public var localOnly: Bool
        public var handshakeTimeout: TimeInterval
        public var idleTimeout: TimeInterval

        public init(name: String, id: String = UUID().uuidString.lowercased(),
                    port: UInt16 = NinoLink.defaultPort, advertise: Bool = true, localOnly: Bool = true,
                    handshakeTimeout: TimeInterval = NinoLink.handshakeTimeout,
                    idleTimeout: TimeInterval = NinoLink.displayIdleTimeout) {
            self.name = name
            self.id = id
            self.port = port
            self.advertise = advertise
            self.localOnly = localOnly
            self.handshakeTimeout = handshakeTimeout
            self.idleTimeout = idleTimeout
        }
    }

    public let options: Options
    /// Ekrandaki altyazı değişince (nil: temizlendi). Sunucu kuyruğunda çağrılır.
    public var onChange: (@Sendable (ShowPayload?) -> Void)?

    private let queue = DispatchQueue(label: "com.ninotranslator.display-server")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    private weak var active: Client?
    private var board = DisplayBoard()
    private var idleTimer: DispatchWorkItem?
    private var durationTimer: DispatchWorkItem?

    public init(options: Options) {
        self.options = options
    }

    /// Ekrandaki altyazı.
    public var current: ShowPayload? { queue.sync { board.current } }

    /// Dinlemeye başlar ve gerçek bağlantı noktasını döner (port 0 verildiyse sistem seçer).
    public func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: options.port == 0 ? .any : NWEndpoint.Port(rawValue: options.port)!)
        if options.advertise {
            let txt = NWTXTRecord(["v": "\(NinoLink.version)", "id": options.id])
            listener.service = NWListener.Service(name: options.name, type: NinoLink.serviceType, domain: nil, txtRecord: txt)
        }
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        self.listener = listener

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            let once = Once()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { cont.resume(returning: listener.port?.rawValue ?? 0) }
                case let .failed(error):
                    if once.claim() { cont.resume(throwing: error) }
                case .cancelled:
                    if once.claim() { cont.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    /// Sunucuyu durdurur. `onChange` içinden çağırmayın.
    public func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            for c in clients.values { c.connection.cancel() }
            clients.removeAll()
            idleTimer?.cancel()
            durationTimer?.cancel()
        }
    }

    // MARK: Bağlantılar

    private func accept(_ connection: NWConnection) {
        if options.localOnly, case let .hostPort(host, _) = connection.endpoint,
           !NinoLink.isLocalAddress("\(host)") {
            connection.cancel()
            return
        }
        let client = Client(connection: connection, server: self)
        clients[ObjectIdentifier(client)] = client
        connection.stateUpdateHandler = { [weak self, weak client] state in
            guard let self, let client else { return }
            switch state {
            case .failed, .cancelled: self.remove(client)
            default: break
            }
        }
        connection.start(queue: queue)
        client.read()
    }

    fileprivate func remove(_ client: Client) {
        clients[ObjectIdentifier(client)] = nil
        if active === client { active = nil }
    }

    fileprivate func becameReady(_ client: Client) {
        if let old = active, old !== client { old.replaced() }
        active = client
        touch()
    }

    /// Göndericiden mesaj geldi: boşta kalma sayacını yeniden kur.
    fileprivate func touch() {
        idleTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.apply(clear: nil) }
        idleTimer = item
        queue.asyncAfter(deadline: .now() + options.idleTimeout, execute: item)
    }

    fileprivate func apply(show p: ShowPayload) {
        durationTimer?.cancel()
        if board.show(p) { onChange?(p) }
        if p.durationMs > 0 {
            let item = DispatchWorkItem { [weak self] in self?.apply(clear: p.id) }
            durationTimer = item
            queue.asyncAfter(deadline: .now() + .milliseconds(p.durationMs), execute: item)
        }
    }

    fileprivate func apply(clear id: Int?) {
        if board.clear(id: id) {
            durationTimer?.cancel()
            onChange?(nil)
        }
    }

    fileprivate var infoMessage: NinoMessage {
        .info(version: NinoLink.version, versions: NinoLink.supportedVersions, name: options.name, id: options.id)
    }

    // MARK: Tek istemci

    fileprivate final class Client {
        enum Phase { case http, webSocket }

        let connection: NWConnection
        unowned let server: NinoDisplayServer
        private var buffer = Data()
        private var phase = Phase.http
        private var session: DisplaySession
        private var assembler = WebSocketAssembler(maxMessage: NinoLink.maxMessageBytes)
        private var handshakeTimer: DispatchWorkItem?

        init(connection: NWConnection, server: NinoDisplayServer) {
            self.connection = connection
            self.server = server
            self.session = DisplaySession(name: server.options.name)
        }

        func read() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let data, !data.isEmpty {
                    self.buffer.append(data)
                    self.process()
                }
                if isComplete || error != nil {
                    self.connection.cancel()
                    return
                }
                self.read()
            }
        }

        private func process() {
            while true {
                switch phase {
                case .http:
                    do {
                        guard let (request, used) = try HTTPRequest.parse(buffer, maxBytes: NinoLink.maxMessageBytes) else { return }
                        buffer.removeFirst(used)
                        handle(request)
                        if phase == .http { return }
                    } catch HTTPRequest.ParseError.tooLarge {
                        respond(413, "Payload Too Large", .error(code: NinoLink.ErrorCode.tooLarge, message: nil, versions: nil))
                        return
                    } catch {
                        respond(400, "Bad Request", .error(code: NinoLink.ErrorCode.badMessage, message: nil, versions: nil))
                        return
                    }
                case .webSocket:
                    do {
                        guard let (frame, used) = try WebSocketFrame.decode(buffer, maxPayload: NinoLink.maxMessageBytes, requireMask: true) else { return }
                        buffer.removeFirst(used)
                        handle(frame)
                    } catch WebSocketFrame.DecodeError.tooLarge {
                        run(session.receive(String(repeating: " ", count: NinoLink.maxMessageBytes + 1)))
                        return
                    } catch {
                        closeWebSocket()
                        return
                    }
                }
            }
        }

        // MARK: HTTP

        private func handle(_ r: HTTPRequest) {
            switch (r.method, r.path) {
            case ("GET", NinoLink.Path.info):
                respond(200, "OK", server.infoMessage)
            case ("GET", NinoLink.Path.webSocket):
                guard r.header("upgrade")?.lowercased() == "websocket", let key = r.header("sec-websocket-key") else {
                    respond(400, "Bad Request", .error(code: NinoLink.ErrorCode.badHandshake, message: nil, versions: nil))
                    return
                }
                let head = HTTPRequest.response(status: 101, reason: "Switching Protocols", headers: [
                    "Upgrade": "websocket", "Connection": "Upgrade",
                    "Sec-WebSocket-Accept": WebSocketFrame.acceptKey(for: key),
                ])
                connection.send(content: head, completion: .contentProcessed { _ in })
                phase = .webSocket
                let timer = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.run(self.session.handshakeTimedOut())
                }
                handshakeTimer = timer
                server.queue.asyncAfter(deadline: .now() + server.options.handshakeTimeout, execute: timer)
            case ("POST", NinoLink.Path.show), ("POST", NinoLink.Path.clear):
                guard r.body.count <= NinoLink.maxMessageBytes else {
                    respond(413, "Payload Too Large", .error(code: NinoLink.ErrorCode.tooLarge, message: nil, versions: nil))
                    return
                }
                let message = try? NinoMessage(data: r.body)
                switch (r.path, message) {
                case let (NinoLink.Path.show, .show(p)?):
                    server.apply(show: p)
                    server.touch()
                    respond(200, "OK", .ok)
                case let (NinoLink.Path.clear, .clear(id)?):
                    server.apply(clear: id)
                    respond(200, "OK", .ok)
                default:
                    respond(400, "Bad Request", .error(code: NinoLink.ErrorCode.badMessage, message: nil, versions: nil))
                }
            default:
                respond(404, "Not Found", .error(code: NinoLink.ErrorCode.badMessage, message: "unknown path", versions: nil))
            }
        }

        private func respond(_ status: Int, _ reason: String, _ message: NinoMessage) {
            let data = HTTPRequest.response(status: status, reason: reason, headers: [
                "Content-Type": "application/json; charset=utf-8", "Connection": "close",
            ], body: message.encoded())
            connection.send(content: data, isComplete: true, completion: .contentProcessed { [weak self] _ in
                self?.connection.cancel()
            })
        }

        // MARK: WebSocket

        private func handle(_ frame: WebSocketFrame) {
            switch assembler.add(frame) {
            case .none:
                break
            case let .message(.text, data):
                run(session.receive(String(decoding: data, as: UTF8.self)))
            case .message:
                send(.error(code: NinoLink.ErrorCode.badMessage, message: "text only", versions: nil))
            case let .control(f):
                switch f.opcode {
                case .ping: sendFrame(WebSocketFrame(opcode: .pong, payload: f.payload))
                case .close: closeWebSocket()
                default: break
                }
            case .tooLarge:
                run(session.receive(String(repeating: " ", count: NinoLink.maxMessageBytes + 1)))
            case .protocolError:
                closeWebSocket()
            }
        }

        func replaced() {
            run(session.replaced())
        }

        private func run(_ outputs: [DisplaySession.Output]) {
            for o in outputs {
                switch o {
                case let .send(m): send(m)
                case let .show(p):
                    server.apply(show: p)
                    server.touch()
                case let .clear(id):
                    server.apply(clear: id)
                    server.touch()
                case .ready:
                    handshakeTimer?.cancel()
                    server.becameReady(self)
                case .close:
                    closeWebSocket()
                }
            }
            if session.state == .ready, !outputs.isEmpty { server.touch() }
        }

        private func send(_ m: NinoMessage) {
            sendFrame(.text(m.jsonString))
        }

        private func sendFrame(_ f: WebSocketFrame) {
            connection.send(content: f.encoded(), completion: .contentProcessed { _ in })
        }

        private func closeWebSocket() {
            handshakeTimer?.cancel()
            let close = WebSocketFrame(opcode: .close, payload: Data([0x03, 0xE8]))
            connection.send(content: close.encoded(), isComplete: true, completion: .contentProcessed { [weak self] _ in
                self?.connection.cancel()
            })
        }
    }
}

/// Bir kez `true` döner; devamlılıkların iki kez sürdürülmesini önler.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.withLock {
            if done { return false }
            done = true
            return true
        }
    }
}
