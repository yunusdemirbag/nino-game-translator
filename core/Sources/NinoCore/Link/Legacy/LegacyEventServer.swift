// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Network

/// Eski TV uygulamaları için kalıcı uyumluluk sunucusu: 8787'de düz HTTP + SSE.
///
/// Kurulu eski TV uygulamaları yalnız bunu konuşur (bkz. docs/tarif/protokol.md "Eski uyumluluk").
/// `DisplayHub`'a bir çıkış olarak eklenir; protokol mesajları eski olaylara çevrilir.
public final class LegacyEventServer: SubtitleRoutingOutput, @unchecked Sendable {
    public static let defaultPort: UInt16 = 8787

    public struct Options: Sendable {
        public var port: UInt16
        /// Port doluysa (önceki süreç geç bırakabilir) kaç kez denenir.
        public var portAttempts: Int
        public var portRetryDelay: TimeInterval
        /// Denemeler tutmazsa rastgele porta geçilsin mi? (TV yalnız 8787'yi tarar; pratikte ulaşmaz.)
        public var randomPortFallback: Bool
        /// Yalnız özel IP aralıklarından kabul. Varsayılan kapalı: eski sunucuda adres süzgeci yoktu,
        /// alışılmadık ağlardaki (ör. 100.64/10) kurulu TV'ler kesilmesin.
        public var localOnly: Bool
        public var pingInterval: TimeInterval
        /// Bağlanan TV'ye `started` yalnız çeviri bu kadar süre önce başladıysa yollanır.
        public var startedReplayWindow: TimeInterval
        /// `durationMs: 0` altyazının eski TV'deki süresi.
        public var untilClearedDurationMs: Int
        /// Gönderilen bir çerçeve bu kadar süre karşıya geçmezse (okumayı bırakmış TV) izleyici düşürülür.
        /// `ping` turunda denetlenir (ping çerçevesi `: ping` yorum satırıyla başlar, eski TV'ler yok sayar).
        public var writeTimeout: TimeInterval
        /// Karşıya geçmeyi bekleyen bayt bu sınırı aşarsa izleyici hemen düşürülür (kapaklı altyazı 512 KB olabilir).
        public var maxPendingBytes: Int
        /// Gönderilen veri bu kadar saniye onaylanmazsa (ağdan kaybolan TV) çekirdek bağlantıyı düşürür
        /// (`NWProtocolTCP.Options.connectionDropTime`). Küçük çerçeveler tampona sığdığı için `writeTimeout` bunu görmez.
        public var connectionDropTime: Int

        public init(port: UInt16 = LegacyEventServer.defaultPort, portAttempts: Int = 5, portRetryDelay: TimeInterval = 0.6,
                    randomPortFallback: Bool = true, localOnly: Bool = false, pingInterval: TimeInterval = 15,
                    startedReplayWindow: TimeInterval = 20, untilClearedDurationMs: Int = 15_000,
                    writeTimeout: TimeInterval = 20, maxPendingBytes: Int = 4 * 1_048_576,
                    connectionDropTime: Int = 25) {
            self.connectionDropTime = connectionDropTime
            self.writeTimeout = writeTimeout
            self.maxPendingBytes = maxPendingBytes
            self.port = port
            self.portAttempts = portAttempts
            self.portRetryDelay = portRetryDelay
            self.randomPortFallback = randomPortFallback
            self.localOnly = localOnly
            self.pingInterval = pingInterval
            self.startedReplayWindow = startedReplayWindow
            self.untilClearedDurationMs = untilClearedDurationMs
        }
    }

    /// `/events`'e bağlı bir izleyici.
    public struct Viewer: Equatable, Hashable, Sendable, Identifiable {
        public let id: String
        public let host: String
        /// TV markası/modeli (yalnız harf, rakam, boşluk, `.-_()`; en çok 60 karakter).
        public let model: String?
        /// TV uygulamasının sürümü.
        public let appVersion: String?
        /// OBS katmanı: olayları alır ama "TV bağlı" sayılmaz.
        public let isOBS: Bool
    }

    public let options: Options

    private let queue = DispatchQueue(label: "com.ninotranslator.legacy-events")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: Connection] = [:]
    private var translator: LegacyTranslator
    private var lastStyle: LegacyEvent?
    private var startedAt: Date?
    private var pingTimer: DispatchSourceTimer?
    private var _subtitlesOnTV = true
    private var _onViewersChange: (@Sendable ([Viewer]) -> Void)?
    private var _onLinkEvent: DisplayLinkEventHandler?
    private var serial = 0
    /// Aynı adres için son yerine geçme anı; `replaceCooldown` içinde ikincisi geri çevrilir.
    private var replacedAt: [String: Date] = [:]
    /// Aynı TV'nin art arda yerine geçmesini kesen süre.
    var replaceCooldown: TimeInterval = 5

    public init(options: Options = Options()) {
        self.options = options
        self.translator = LegacyTranslator(untilClearedDurationMs: options.untilClearedDurationMs)
    }

    /// `false`: "altyazı yalnız bilgisayarda". Altyazı olayları TV'lere gitmez, OBS'ye gider;
    /// `started`/`stopped`/`ping` herkese gider.
    public var subtitlesOnTV: Bool {
        get { queue.sync { _subtitlesOnTV } }
        set { queue.sync { _subtitlesOnTV = newValue } }
    }

    public func setSubtitlesOnTV(_ on: Bool) async { subtitlesOnTV = on }

    /// İzleyici listesi değişince (sunucu kuyruğunda). Kuyruk dışından kurun.
    public var onViewersChange: (@Sendable ([Viewer]) -> Void)? {
        get { queue.sync { _onViewersChange } }
        set { queue.sync { _onViewersChange = newValue } }
    }

    /// TV izleyicisi bağlandı / koptu / zaman aşımıyla düşürüldü (sunucu kuyruğunda; OBS hariç). Kuyruk dışından kurun.
    public var onLinkEvent: DisplayLinkEventHandler? {
        get { queue.sync { _onLinkEvent } }
        set { queue.sync { _onLinkEvent = newValue } }
    }

    /// Bütün izleyiciler (OBS dahil).
    public var viewers: [Viewer] { queue.sync { currentViewers() } }
    /// "TV bağlı" sayılanlar (OBS hariç).
    public var connectedTVs: [Viewer] { viewers.filter { !$0.isOBS } }

    /// Dinlemeye başlar, gerçek portu döner. Port doluysa birkaç kez dener, sonra (izin varsa) rastgele port.
    public func start() async throws -> UInt16 {
        var lastError: Error?
        let attempts = max(1, options.portAttempts)
        for attempt in 0..<attempts {
            do {
                return try await listen(on: options.port)
            } catch {
                lastError = error
                if options.port == 0 { break }
                if attempt < attempts - 1 { try? await Task.sleep(for: .seconds(options.portRetryDelay)) }
            }
        }
        if options.randomPortFallback, options.port != 0 { return try await listen(on: 0) }
        throw lastError ?? CancellationError()
    }

    public func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            pingTimer?.cancel()
            pingTimer = nil
            let had = !connections.values.filter(\.isViewer).isEmpty
            for c in connections.values.sorted(by: { $0.serial < $1.serial }) {
                if c.isViewer { emitDrop(c, reason: .serverStopped) }
                c.connection.stateUpdateHandler = nil
                c.connection.cancel()
            }
            connections.removeAll()
            if had { _onViewersChange?([]) }
        }
    }

    // MARK: DisplayOutput

    public func show(_ payload: ShowPayload) async throws {
        queue.async { self.broadcast(self.translator.subtitle(payload)) }
    }

    public func clear(id: Int?) async throws {
        queue.async {
            if let e = self.translator.clear(id: id) { self.broadcast(e) }
        }
    }

    public func send(_ event: NinoEvent) async throws {
        queue.async {
            let e = self.translator.event(event)
            switch event {
            case .style: self.lastStyle = e
            case .started: self.startedAt = Date()
            case .stopped: self.startedAt = nil
            default: break
            }
            self.broadcast(e)
        }
    }

    // MARK: İç

    private func listen(on port: UInt16) async throws -> UInt16 {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        tcp.noDelay = true
        if options.connectionDropTime > 0 { tcp.connectionDropTime = options.connectionDropTime }
        let params = NWParameters(tls: nil, tcp: tcp)
        // Aynı portu ikinci bir süreçle paylaşmayalım (gerçek Nino açıkken deneme kopyası gibi).
        params.allowLocalEndpointReuse = false
        let listener = try NWListener(using: params, on: port == 0 ? .any : NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        let bound = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            let once = Once()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { cont.resume(returning: listener.port?.rawValue ?? 0) }
                case let .failed(error):
                    if once.claim() { cont.resume(throwing: error) }
                    listener.cancel()
                case let .waiting(error):
                    // Port dolu: bekleme yerine hata say, yeniden denensin.
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
        queue.sync {
            self.listener = listener
            startPingTimer()
        }
        return bound
    }

    private func startPingTimer() {
        pingTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + options.pingInterval, repeating: options.pingInterval)
        timer.setEventHandler { [weak self] in self?.pingTick() }
        timer.resume()
        pingTimer = timer
    }

    /// Kalp atışı: asılı yazması olanı düşürür, ötekilere `ping` (yorum satırı + olay) yollar.
    private func pingTick(now: Date = Date()) {
        for c in connections.values.sorted(by: { $0.serial < $1.serial }) where c.isViewer {
            if let since = c.oldestPendingSince, now.timeIntervalSince(since) > options.writeTimeout {
                drop(c, reason: .writeStalled)
            } else {
                c.send(LegacyEvent.pingFrame)
            }
        }
    }

    /// Bağlantıyı hemen bırakır (ilk neden geçerli); liste ve olay `remove`'da.
    fileprivate func drop(_ c: Connection, reason: DisplayLinkEvent.Reason) {
        if c.dropReason == nil { c.dropReason = reason }
        remove(c)
        c.connection.stateUpdateHandler = nil
        c.connection.cancel()
    }

    private func emitDrop(_ c: Connection, reason: DisplayLinkEvent.Reason) {
        guard let v = c.viewer, !v.isOBS, !c.emittedDrop else { return }
        c.emittedDrop = true
        _onLinkEvent?(.dropped(.legacySSE, host: v.host, id: v.id, model: v.model, appVersion: v.appVersion,
                               since: c.openedAt, reason: c.dropReason ?? reason))
    }

    private func broadcast(_ e: LegacyEvent) {
        let frame = e.frame
        let toTV = _subtitlesOnTV || !e.isSubtitleEvent
        for c in connections.values where c.isViewer {
            if c.viewer?.isOBS == true || toTV { c.send(frame) }
        }
    }

    private func currentViewers() -> [Viewer] {
        connections.values.filter(\.isViewer).sorted { $0.serial < $1.serial }.compactMap(\.viewer)
    }

    private func accept(_ nw: NWConnection) {
        var host = ""
        if case let .hostPort(h, _) = nw.endpoint { host = "\(h)" }
        if !host.contains(":"), let p = host.firstIndex(of: "%") { host = String(host[..<p]) }
        if options.localOnly, !NinoLink.isLocalAddress(host) {
            nw.cancel()
            return
        }
        serial += 1
        let c = Connection(connection: nw, host: host, server: self, serial: serial)
        connections[ObjectIdentifier(c)] = c
        nw.stateUpdateHandler = { [weak self, weak c] state in
            guard let self, let c else { return }
            switch state {
            case let .failed(error):
                if c.dropReason == nil { c.dropReason = LegacyEventServer.reason(for: error) }
                self.remove(c)
            case .cancelled:
                if c.dropReason == nil { c.dropReason = .localClose }
                self.remove(c)
            default: break
            }
        }
        nw.start(queue: queue)
        c.read()
    }

    fileprivate func remove(_ c: Connection) {
        guard connections.removeValue(forKey: ObjectIdentifier(c)) != nil else { return }
        if c.isViewer {
            emitDrop(c, reason: .localClose)
            _onViewersChange?(currentViewers())
        }
    }

    /// Yeni izleyici: retry, son style, (yakında başladıysa ve OBS değilse) started.
    fileprivate func opened(_ c: Connection) {
        var out = LegacyEvent.retryFrame
        let isOBS = c.viewer?.isOBS == true
        c.openedAt = Date()
        if !isOBS {
            // Aynı adresten yeni TV akışı: eskisi (kapanışı bize ulaşmamış ölü bağlantı) yer tutmasın.
            let stale = connections.values.filter { $0 !== c && $0.isViewer && $0.viewer?.isOBS == false && $0.host == c.host }
            let now = Date()
            if !stale.isEmpty, let last = replacedAt[c.host], now.timeIntervalSince(last) < replaceCooldown {
                // Döngü: aynı adres kısa sürede yine yeni akış açıyor (iki istemci birbirini kovalıyor).
                // Sağlam eski akış kalır; yeni gelen sessizce kapatılır (olay yok, günlük dolmasın).
                replacedAt[c.host] = now
                c.emittedDrop = true
                drop(c, reason: .replaced)
                return
            }
            if !stale.isEmpty { replacedAt[c.host] = now }
            for old in stale.sorted(by: { $0.serial < $1.serial }) { drop(old, reason: .replaced) }
            if let v = c.viewer {
                _onLinkEvent?(.connected(.legacySSE, host: v.host, id: v.id, model: v.model, appVersion: v.appVersion,
                                         at: c.openedAt ?? Date()))
            }
        }
        if let lastStyle, _subtitlesOnTV || isOBS { out.append(lastStyle.frame) }
        if !isOBS, let startedAt, Date().timeIntervalSince(startedAt) <= options.startedReplayWindow {
            out.append(LegacyEvent(name: LegacyEvent.Name.started, body: [:]).frame)
        }
        c.send(out)
        _onViewersChange?(currentViewers())
    }

    /// Çekirdeğin zaman aşımı (onaylanmayan veri, keepalive) `write-stalled`; gerisi okuma hatası.
    static func reason(for error: NWError) -> DisplayLinkEvent.Reason {
        if case let .posix(code) = error, code == .ETIMEDOUT { return .writeStalled }
        return .readFailed
    }

    fileprivate func isTracked(_ c: Connection) -> Bool { connections[ObjectIdentifier(c)] != nil }

    /// Yalnız harf, rakam, boşluk ve `.-_()`; en çok 60 karakter.
    public static func sanitizeModel(_ raw: String) -> String {
        let allowed = Set(" .-_()")
        let kept = raw.filter { $0.isLetter || $0.isNumber || allowed.contains($0) }
        return String(kept.prefix(60)).trimmingCharacters(in: .whitespaces)
    }

    fileprivate static let corsHeaders = [
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, OPTIONS",
        "Access-Control-Allow-Headers": "*",
    ]

    // MARK: Tek bağlantı

    fileprivate final class Connection {
        let connection: NWConnection
        let host: String
        let serial: Int
        unowned let server: LegacyEventServer
        private(set) var viewer: Viewer?
        private var buffer = Data()
        private var done = false
        var openedAt: Date?
        var dropReason: DisplayLinkEvent.Reason?
        var emittedDrop = false
        /// Karşıya geçmeyi bekleyen yazmalar (gönderim anı, bayt), sırayla.
        private var pending: [(at: Date, bytes: Int)] = []
        private var pendingBytes = 0
        var oldestPendingSince: Date? { pending.first?.at }

        var isViewer: Bool { viewer != nil }

        init(connection: NWConnection, host: String, server: LegacyEventServer, serial: Int) {
            self.connection = connection
            self.host = host
            self.server = server
            self.serial = serial
        }

        func read() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let data, !data.isEmpty, !self.isViewer, !self.done {
                    self.buffer.append(data)
                    self.process()
                }
                if isComplete || error != nil {
                    if self.dropReason == nil { self.dropReason = error.map(LegacyEventServer.reason(for:)) ?? .peerClosed }
                    self.connection.cancel()
                    return
                }
                self.read() // SSE açıkken gelen baytlar yok sayılır; kapanışı fark etmek için okunur.
            }
        }

        private func process() {
            do {
                guard let (r, used) = try HTTPRequest.parse(buffer, maxBytes: 16 * 1024) else { return }
                buffer.removeFirst(used)
                handle(r)
            } catch {
                respond(400, "Bad Request", type: "text/plain; charset=utf-8", body: Data("bad request".utf8))
            }
        }

        private func handle(_ r: HTTPRequest) {
            switch (r.method, r.path) {
            case ("OPTIONS", _):
                respond(204, "No Content", type: nil, body: Data())
            case ("GET", "/hello"):
                respond(200, "OK", type: "application/json; charset=utf-8", body: LegacyCompatName.helloBody)
            case ("GET", "/events"):
                let q = r.queryItems
                let model = q["model"].map(LegacyEventServer.sanitizeModel).flatMap { $0.isEmpty ? nil : $0 }
                let app = q["app"].map { String($0.prefix(40)) }.flatMap { $0.isEmpty ? nil : $0 }
                viewer = Viewer(id: UUID().uuidString.lowercased(), host: host, model: model, appVersion: app,
                                isOBS: q["viewer"] == "obs")
                var head = "HTTP/1.1 200 OK\r\n"
                var headers = LegacyEventServer.corsHeaders
                headers["Content-Type"] = "text/event-stream; charset=utf-8"
                headers["Cache-Control"] = "no-cache"
                headers["Connection"] = "keep-alive"
                for (k, v) in headers.sorted(by: { $0.key < $1.key }) { head += "\(k): \(v)\r\n" }
                head += "\r\n"
                send(Data(head.utf8))
                server.opened(self)
            case ("GET", "/obs"):
                respond(200, "OK", type: "text/html; charset=utf-8", body: Data(LegacyOBSPage.html.utf8))
            default:
                respond(404, "Not Found", type: "text/plain; charset=utf-8", body: Data("not found".utf8))
            }
        }

        private func respond(_ status: Int, _ reason: String, type: String?, body: Data) {
            done = true
            var headers = LegacyEventServer.corsHeaders
            headers["Connection"] = "close"
            if let type { headers["Content-Type"] = type }
            let data = HTTPRequest.response(status: status, reason: reason, headers: headers, body: body)
            connection.send(content: data, isComplete: true, completion: .contentProcessed { [weak self] _ in
                self?.connection.cancel()
            })
        }

        /// Yazma hatası ya da birikme sınırı: izleyici hemen düşer, kaynaklar bırakılır.
        func send(_ data: Data) {
            guard server.isTracked(self) else { return }
            pending.append((Date(), data.count))
            pendingBytes += data.count
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if !self.pending.isEmpty {
                    self.pendingBytes -= self.pending.removeFirst().bytes
                }
                if error != nil, self.isViewer { self.server.drop(self, reason: .writeFailed) }
            })
            if isViewer, pendingBytes > server.options.maxPendingBytes { server.drop(self, reason: .writeStalled) }
        }
    }
}
