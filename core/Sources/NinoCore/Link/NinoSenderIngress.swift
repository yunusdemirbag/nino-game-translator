// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Network

/// Gönderici girişi (ters yön): web TV'ler (LG webOS, Samsung Tizen) dinleyemediği için
/// gönderici 47800'de dinler, TV ona bağlanır. Bağlantı açılınca ilk `hello`'yu gönderici yollar;
/// sonrası protokolle aynıdır. Birden çok TV aynı anda bağlanabilir, her mesaj hepsine gider.
/// Aynı TV (welcome'daki `id`; yoksa aynı uzak adres) yeniden el sıkışınca eski bağlantısına
/// `error` (`code: "replaced"`) yollanır ve o kapatılır (olay nedeni `replaced`).
///
/// Bonjour yayını yoktur: `_nino._tcp` TV'lerindir; web TV göndericiyi açılış parametresiyle
/// ya da `/nino/info` (`role:"sender"`) taramasıyla bulur. Bkz. docs/tarif/protokol.md.
public final class NinoSenderIngress: DisplayOutput, @unchecked Sendable {
    public struct Options: Sendable {
        /// `info` ve TV'ye görünen gönderici adı.
        public var name: String
        public var id: String
        public var port: UInt16
        public var localOnly: Bool
        /// `hello` içindeki alanlar.
        public var device: String?
        public var client: String?
        /// `info.appVersion`.
        public var appVersion: String?
        public var versions: [Int]
        public var handshakeTimeout: TimeInterval
        public var pingInterval: TimeInterval
        /// TV'den bu kadar süre hiçbir şey gelmezse bağlantı kapatılır.
        public var silenceTimeout: TimeInterval
        /// Port doluysa (önceki süreç geç bırakabilir) kaç kez denenir. Rastgele porta geçilmez: TV 47800'ü tarar.
        public var portAttempts: Int
        public var portRetryDelay: TimeInterval
        /// Aynı TV bu süre içinde ikinci kez yerine geçmeye kalkarsa (iki istemci birbirini kovalıyor) eski, sağlam
        /// bağlantı kalır, yeni gelen `duplicate` ile geri çevrilir. Döngüyü kırar.
        public var replaceCooldown: TimeInterval = 5

        public init(name: String, id: String = UUID().uuidString.lowercased(), port: UInt16 = NinoLink.defaultPort,
                    localOnly: Bool = true, device: String? = nil, client: String? = nil, appVersion: String? = nil,
                    versions: [Int] = NinoLink.supportedVersions,
                    handshakeTimeout: TimeInterval = NinoLink.handshakeTimeout,
                    pingInterval: TimeInterval = NinoLink.pingInterval,
                    silenceTimeout: TimeInterval = NinoLink.pongTimeout,
                    portAttempts: Int = 5, portRetryDelay: TimeInterval = 0.6) {
            self.portAttempts = portAttempts
            self.portRetryDelay = portRetryDelay
            self.name = name
            self.id = id
            self.port = port
            self.localOnly = localOnly
            self.device = device
            self.client = client
            self.appVersion = appVersion
            self.versions = versions
            self.handshakeTimeout = handshakeTimeout
            self.pingInterval = pingInterval
            self.silenceTimeout = silenceTimeout
        }
    }

    /// Bağlı (el sıkışmış) bir TV.
    public struct Display: Equatable, Hashable, Sendable, Identifiable {
        /// Bu bağlantının kimliği (TV yeniden bağlanınca değişir).
        public let id: String
        public let host: String
        public let version: Int
        public let name: String?
        /// `welcome` içinde gelirse.
        public let model: String?
        public let appVersion: String?
        /// TV'nin kalıcı kimliği (`welcome.id`; yeniden bağlanınca aynı kalır). Gelmezse nil.
        public let tvID: String?

        /// Aynı TV mi? Kimlik varsa kimlik, yoksa uzak adres karşılaştırılır.
        var sameTVKey: String { tvID.map { "id:" + $0 } ?? "host:" + host }
    }

    public let options: Options
    /// Bağlı TV listesi değişince. Giriş kuyruğunda çağrılır.
    public var onDisplaysChange: (@Sendable ([Display]) -> Void)? {
        get { queue.sync { _onDisplaysChange } }
        set { queue.sync { _onDisplaysChange = newValue } }
    }

    /// TV bağlandı (el sıkıştı) / koptu / zaman aşımıyla düşürüldü. Giriş kuyruğunda çağrılır.
    public var onLinkEvent: DisplayLinkEventHandler? {
        get { queue.sync { _onLinkEvent } }
        set { queue.sync { _onLinkEvent = newValue } }
    }

    private let queue = DispatchQueue(label: "com.ninotranslator.sender-ingress")
    private var _onDisplaysChange: (@Sendable ([Display]) -> Void)?
    private var _onLinkEvent: DisplayLinkEventHandler?
    private var listener: NWListener?
    private var peers: [ObjectIdentifier: Peer] = [:]
    private var replay = DisplayReplay()
    private var pingTimer: DispatchSourceTimer?
    private var pingCounter: Int64 = 0

    public init(options: Options) {
        self.options = options
    }

    /// Bağlı TV'ler (bağlanma sırasıyla).
    public var displays: [Display] { queue.sync { readyDisplays() } }

    /// Dinlemeye başlar ve gerçek bağlantı noktasını döner (port 0 verildiyse sistem seçer).
    /// Port doluysa `portAttempts` kez dener.
    public func start() async throws -> UInt16 {
        var lastError: Error?
        let attempts = options.port == 0 ? 1 : max(1, options.portAttempts)
        for attempt in 0..<attempts {
            do {
                return try await listen()
            } catch {
                lastError = error
                if attempt < attempts - 1 { try? await Task.sleep(for: .seconds(options.portRetryDelay)) }
            }
        }
        throw lastError ?? CancellationError()
    }

    private func listen() async throws -> UInt16 {
        let params = NWParameters.tcp
        // İkinci bir Nino aynı portu paylaşmasın (TV yanlış kopyaya bağlanır); dolu port hata verir.
        params.allowLocalEndpointReuse = false
        let listener = try NWListener(using: params, on: options.port == 0 ? .any : NWEndpoint.Port(rawValue: options.port)!)
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        queue.sync { self.listener = listener }

        let port = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            let once = Once()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { cont.resume(returning: listener.port?.rawValue ?? 0) }
                case let .failed(error):
                    if once.claim() { cont.resume(throwing: error) }
                    listener.cancel()
                case let .waiting(error):
                    if once.claim() { cont.resume(throwing: error) }
                    listener.cancel()
                case .cancelled:
                    if once.claim() { cont.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        queue.sync { startPingTimer() }
        return port
    }

    /// Dinlemeyi ve bütün TV bağlantılarını kapatır.
    public func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            pingTimer?.cancel()
            pingTimer = nil
            let had = !readyDisplays().isEmpty
            for p in peers.values.sorted(by: { $0.serial < $1.serial }) {
                p.setReason(.serverStopped)
                emitDrop(p)
                p.shutdown()
            }
            peers.removeAll()
            if had { _onDisplaysChange?([]) }
        }
    }

    // MARK: Gönderme (DisplayOutput)

    /// Bağlı bütün TV'lere yollar. TV yoksa yalnız son durum saklanır (bağlanan TV'ye yollanır).
    public func show(_ payload: ShowPayload) async throws {
        let payload = payload.fittingLimit()
        queue.async {
            self.replay.record(show: payload)
            self.broadcast(NinoMessage.show(payload).jsonString)
        }
    }

    public func clear(id: Int?) async throws {
        queue.async {
            self.replay.record(clear: id)
            self.broadcast(NinoMessage.clear(id: id).jsonString)
        }
    }

    public func send(_ event: NinoEvent) async throws {
        queue.async {
            self.replay.record(event)
            self.broadcast(event.jsonString)
        }
    }

    // MARK: İç

    private func broadcast(_ text: String) {
        let frame = WebSocketFrame.text(text).encoded()
        for p in peers.values where p.phase == .ready { p.sendEncoded(frame) }
    }

    private func readyDisplays() -> [Display] {
        peers.values.filter { $0.phase == .ready }.sorted { $0.serial < $1.serial }.compactMap(\.display)
    }

    private func accept(_ connection: NWConnection) {
        var host = ""
        if case let .hostPort(h, _) = connection.endpoint { host = "\(h)" }
        if !host.contains(":"), let p = host.firstIndex(of: "%") { host = String(host[..<p]) }
        if options.localOnly, !NinoLink.isLocalAddress(host) {
            connection.cancel()
            return
        }
        pingCounter += 1
        let peer = Peer(connection: connection, host: host, ingress: self, serial: pingCounter)
        peers[ObjectIdentifier(peer)] = peer
        connection.stateUpdateHandler = { [weak self, weak peer] state in
            guard let self, let peer else { return }
            switch state {
            case .failed:
                peer.setReason(.readFailed)
                self.remove(peer)
            case .cancelled:
                peer.setReason(.localClose)
                self.remove(peer)
            default: break
            }
        }
        connection.start(queue: queue)
        peer.read()
    }

    fileprivate func remove(_ peer: Peer) {
        guard peers.removeValue(forKey: ObjectIdentifier(peer)) != nil else { return }
        if peer.wasReady {
            if !peer.quietClose { emitDrop(peer) }
            _onDisplaysChange?(readyDisplays())
        }
    }

    /// Aynı TV için son yerine geçme anı (`sameTVKey`).
    private var replacedAt: [String: Date] = [:]

    fileprivate func becameReady(_ peer: Peer) {
        if let key = peer.display?.sameTVKey {
            // Aynı TV yeniden bağlandı: eskisi bırakılır, önce nedeni ona söylenir.
            let stale = peers.values.filter { $0 !== peer && $0.phase == .ready && $0.display?.sameTVKey == key }
            let now = Date()
            if !stale.isEmpty, let last = replacedAt[key], now.timeIntervalSince(last) < options.replaceCooldown {
                // Döngü: aynı TV kısa sürede yine yerine geçmek istiyor. Eskisi kalır, yeni gelen geri çevrilir.
                replacedAt[key] = now
                peer.quietClose = true
                peer.setReason(.replaced)
                peer.fail(NinoLink.ErrorCode.duplicate)
                return
            }
            if !stale.isEmpty { replacedAt[key] = now }
            for old in stale.sorted(by: { $0.serial < $1.serial }) {
                old.setReason(.replaced)
                emitDrop(old)
                old.fail(NinoLink.ErrorCode.replaced)
            }
        }
        for text in replay.messages() { peer.send(text) }
        if let d = peer.display {
            _onLinkEvent?(.connected(.ingress, host: d.host, id: d.id, model: d.model, appVersion: d.appVersion,
                                     at: peer.readyAt ?? Date()))
        }
        _onDisplaysChange?(readyDisplays())
    }

    private func emitDrop(_ peer: Peer) {
        guard peer.wasReady, !peer.emittedDrop, let d = peer.display else { return }
        peer.emittedDrop = true
        _onLinkEvent?(.dropped(.ingress, host: d.host, id: d.id, model: d.model, appVersion: d.appVersion,
                               since: peer.readyAt, reason: peer.closeReason ?? .localClose))
    }

    private func startPingTimer() {
        pingTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + options.pingInterval, repeating: options.pingInterval)
        timer.setEventHandler { [weak self] in self?.pingAll() }
        timer.resume()
        pingTimer = timer
    }

    private func pingAll() {
        let now = Date()
        for p in peers.values where p.phase == .ready {
            if now.timeIntervalSince(p.lastHeard) > options.silenceTimeout {
                p.setReason(.heartbeatTimeout)
                p.close()
            } else {
                pingCounter += 1
                p.send(NinoMessage.ping(t: Int64(now.timeIntervalSince1970 * 1000) * 1000 + pingCounter % 1000).jsonString)
            }
        }
    }

    fileprivate var infoBody: Data {
        NinoInfo(name: options.name, id: options.id, appVersion: options.appVersion, role: NinoLink.senderRole).encoded()
    }

    fileprivate static let corsHeaders = [
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, OPTIONS",
        "Access-Control-Allow-Headers": "*",
    ]

    // MARK: Tek TV bağlantısı

    fileprivate final class Peer {
        enum Phase { case http, awaitingWelcome, ready, closed }

        let connection: NWConnection
        let host: String
        let serial: Int64
        unowned let ingress: NinoSenderIngress
        private(set) var phase = Phase.http
        private(set) var wasReady = false
        private(set) var display: Display?
        var lastHeard = Date()
        /// Döngüyü kırmak için geri çevrilen bağlantı: kopma olayı yayınlanmaz (günlük ve ölçüm dolmasın).
        var quietClose = false
        private(set) var readyAt: Date?
        private(set) var closeReason: DisplayLinkEvent.Reason?
        var emittedDrop = false

        /// İlk neden geçerli.
        func setReason(_ r: DisplayLinkEvent.Reason) { if closeReason == nil { closeReason = r } }
        private var buffer = Data()
        private var assembler = WebSocketAssembler(maxMessage: NinoLink.maxMessageBytes)
        private var handshakeTimer: DispatchWorkItem?
        private var triedVersions = Set<Int>()
        private let connectionID = UUID().uuidString.lowercased()

        init(connection: NWConnection, host: String, ingress: NinoSenderIngress, serial: Int64) {
            self.connection = connection
            self.host = host
            self.ingress = ingress
            self.serial = serial
        }

        func read() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let data, !data.isEmpty {
                    self.buffer.append(data)
                    self.process()
                }
                if isComplete || error != nil {
                    self.setReason(error == nil ? .peerClosed : .readFailed)
                    self.connection.cancel()
                    return
                }
                if self.phase != .closed { self.read() }
            }
        }

        private func process() {
            while phase != .closed {
                if phase == .http {
                    do {
                        guard let (request, used) = try HTTPRequest.parse(buffer, maxBytes: 16 * 1024) else { return }
                        buffer.removeFirst(used)
                        handle(request)
                        if phase == .http { return }
                    } catch {
                        respond(400, "Bad Request", body: NinoMessage.error(code: NinoLink.ErrorCode.badMessage, message: nil, versions: nil).encoded())
                        return
                    }
                } else {
                    do {
                        guard let (frame, used) = try WebSocketFrame.decode(buffer, maxPayload: NinoLink.maxMessageBytes, requireMask: true) else { return }
                        buffer.removeFirst(used)
                        handle(frame)
                    } catch WebSocketFrame.DecodeError.tooLarge {
                        setReason(.protocolError)
                        fail(NinoLink.ErrorCode.tooLarge)
                        return
                    } catch {
                        setReason(.protocolError)
                        close()
                        return
                    }
                }
            }
        }

        // MARK: HTTP

        private func handle(_ r: HTTPRequest) {
            switch (r.method, r.path) {
            case ("OPTIONS", _):
                respond(204, "No Content", body: Data())
            case ("GET", NinoLink.Path.info):
                respond(200, "OK", body: ingress.infoBody)
            case ("GET", NinoLink.Path.webSocket):
                guard r.header("upgrade")?.lowercased() == "websocket", let key = r.header("sec-websocket-key") else {
                    respond(400, "Bad Request", body: NinoMessage.error(code: NinoLink.ErrorCode.badHandshake, message: nil, versions: nil).encoded())
                    return
                }
                let head = HTTPRequest.response(status: 101, reason: "Switching Protocols", headers: [
                    "Upgrade": "websocket", "Connection": "Upgrade",
                    "Sec-WebSocket-Accept": WebSocketFrame.acceptKey(for: key),
                ])
                connection.send(content: head, completion: .contentProcessed { _ in })
                phase = .awaitingWelcome
                sendHello(version: ingress.options.versions.max() ?? NinoLink.version)
                let timer = DispatchWorkItem { [weak self] in
                    guard let self, self.phase == .awaitingWelcome else { return }
                    self.close()
                }
                handshakeTimer = timer
                ingress.queue.asyncAfter(deadline: .now() + ingress.options.handshakeTimeout, execute: timer)
            default:
                respond(404, "Not Found", body: NinoMessage.error(code: NinoLink.ErrorCode.badMessage, message: "unknown path", versions: nil).encoded())
            }
        }

        private func respond(_ status: Int, _ reason: String, body: Data) {
            var headers = NinoSenderIngress.corsHeaders
            headers["Connection"] = "close"
            if !body.isEmpty { headers["Content-Type"] = "application/json; charset=utf-8" }
            let data = HTTPRequest.response(status: status, reason: reason, headers: headers, body: body)
            phase = .closed
            connection.send(content: data, isComplete: true, completion: .contentProcessed { [weak self] _ in
                self?.connection.cancel()
            })
        }

        // MARK: WebSocket

        private func sendHello(version: Int) {
            triedVersions.insert(version)
            send(NinoMessage.hello(version: version, device: ingress.options.device, client: ingress.options.client).jsonString)
        }

        private func handle(_ frame: WebSocketFrame) {
            switch assembler.add(frame) {
            case .none:
                break
            case let .message(.text, data):
                lastHeard = Date()
                receive(data)
            case .message:
                lastHeard = Date()
                send(NinoMessage.error(code: NinoLink.ErrorCode.badMessage, message: "text only", versions: nil).jsonString)
            case let .control(f):
                lastHeard = Date()
                switch f.opcode {
                case .ping: sendEncoded(WebSocketFrame(opcode: .pong, payload: f.payload).encoded())
                case .close:
                    setReason(.peerClosed)
                    close()
                default: break
                }
            case .tooLarge:
                setReason(.protocolError)
                fail(NinoLink.ErrorCode.tooLarge)
            case .protocolError:
                setReason(.protocolError)
                close()
            }
        }

        private func receive(_ data: Data) {
            guard let message = try? NinoMessage(data: data) else {
                if phase == .awaitingWelcome { close() }
                return
            }
            switch (phase, message) {
            case let (.awaitingWelcome, .welcome(version, name)):
                handshakeTimer?.cancel()
                let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let tvID = (o?["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                display = Display(id: connectionID, host: host, version: version, name: name,
                                  model: o?["model"] as? String, appVersion: o?["appVersion"] as? String, tvID: tvID)
                phase = .ready
                wasReady = true
                readyAt = Date()
                ingress.becameReady(self)
            case let (.awaitingWelcome, .error(code, _, theirs)) where code == NinoLink.ErrorCode.versionUnsupported:
                if let next = NinoLink.bestCommonVersion(theirs ?? [], ours: ingress.options.versions), !triedVersions.contains(next) {
                    sendHello(version: next)
                } else {
                    close()
                }
            case (.awaitingWelcome, _):
                close()
            case let (.ready, .ping(t)):
                send(NinoMessage.pong(t: t).jsonString)
            default:
                break // pong, error ve bilinmeyenler: yalnız canlılık sayılır.
            }
        }

        func send(_ text: String) {
            sendEncoded(WebSocketFrame.text(text).encoded())
        }

        func sendEncoded(_ data: Data) {
            guard phase == .awaitingWelcome || phase == .ready else { return }
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self, error != nil, self.phase != .closed else { return }
                self.setReason(.writeFailed)
                self.close()
            })
        }

        /// Hata kodunu yollar, sonra kapatır (çerçeve sırası korunur).
        func fail(_ code: String) {
            send(NinoMessage.error(code: code, message: nil, versions: nil).jsonString)
            close()
        }

        func close() {
            guard phase != .closed else { return }
            handshakeTimer?.cancel()
            let wasWS = phase != .http
            phase = .closed
            if wasWS {
                let frame = WebSocketFrame(opcode: .close, payload: Data([0x03, 0xE8]))
                connection.send(content: frame.encoded(), isComplete: true, completion: .contentProcessed { [weak self] _ in
                    self?.connection.cancel()
                })
            } else {
                connection.cancel()
            }
        }

        /// Giriş dururken: sessizce kapat (liste bildirimi giriş tarafında).
        func shutdown() {
            close()
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
    }
}
