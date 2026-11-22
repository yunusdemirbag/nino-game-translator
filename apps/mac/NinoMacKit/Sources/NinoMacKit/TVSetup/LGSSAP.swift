// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// TV ile eşleşmenin sonucu (LG ve Samsung ortak).
public enum TVPairingError: Error, Equatable, Sendable {
    /// TV isteği reddetti (LG `error`, Samsung `ms.channel.unauthorized`). LG'de süre dolunca da.
    case refused(String?)
    /// İzin kutusu süresinde onaylanmadı (Samsung `ms.channel.timeOut` ya da 60 sn).
    case timedOut
    /// Bağlanılamadı.
    case unreachable(String?)
}

/// LG webOS ikinci ekran (SSAP) istemcisi (tv-kurulumu.md §3).
public actor LGSSAPClient {
    public struct Timing: Sendable {
        public var firstMessage: TimeInterval = 5
        public var approval: TimeInterval = 60
        public var request: TimeInterval = 5
        public init() {}
    }

    public static let permissions = ["LAUNCH", "LAUNCH_WEBAPP", "APP_TO_APP", "READ_RUNNING_APPS", "READ_INSTALLED_APPS"]

    public let host: String
    private let sockets: TVWebSocketConnecting
    private let timing: Timing
    private var socket: TVWebSocket?
    private var nextID = 1

    /// `queryApps`: açmadan önce `listApps` sorulsun mu (yanıtsız kalan TV'de kapatılır; yanıtsız istek bağlantıyı
    /// kapatır).
    public init(host: String, sockets: TVWebSocketConnecting, timing: Timing = Timing(), queryApps: Bool = true) {
        self.host = host
        self.sockets = sockets
        self.timing = timing
        self.queryApps = queryApps
    }

    private let queryApps: Bool
    /// `listApps` hata verdi ya da yanıtsız kaldı (bu TV'de yeniden sorulmamalı).
    public private(set) var listAppsFailed = false

    public var isConnected: Bool { socket != nil }

    /// Uçlar: önce `wss://<adres>:3001`, olmazsa `ws://<adres>:3000` (eski webOS).
    nonisolated var endpoints: [URL] {
        [URL(string: "wss://\(host):3001")!, URL(string: "ws://\(host):3000")!]
    }

    static func registerMessage(clientKey: String?) -> String {
        var payload: [String: Any] = [
            "forcePairing": false,
            "pairingType": "PROMPT",
            "manifest": ["manifestVersion": 1, "appVersion": "1.0", "permissions": permissions] as [String: Any],
        ]
        if let clientKey, !clientKey.isEmpty { payload["client-key"] = clientKey }
        return jsonText(["type": "register", "id": "register_0", "payload": payload])
    }

    /// Bağlanır ve eşleşir. Dönen değer saklanacak istemci anahtarı.
    public func connect(clientKey: String?) async throws -> String {
        var lastError: String?
        for url in endpoints {
            let ws: TVWebSocket
            do {
                ws = try await sockets.connect(url: url, trustedHost: host, timeout: timing.firstMessage)
                try await withTimeout(timing.firstMessage) { try await ws.send(Self.registerMessage(clientKey: clientKey)) }
            } catch {
                lastError = "\(url.scheme ?? ""): \(error)"
                continue
            }
            do {
                let key = try await waitForRegistration(ws)
                socket = ws
                return key ?? clientKey ?? ""
            } catch let e as TVPairingError {
                ws.close()
                if case .unreachable(let d) = e { lastError = d; continue }
                throw e
            } catch {
                ws.close()
                lastError = "\(error)"
            }
        }
        throw TVPairingError.unreachable(lastError)
    }

    private func waitForRegistration(_ ws: TVWebSocket) async throws -> String? {
        do {
            return try await withTimeout(timing.approval) {
                while true {
                    let text = try await ws.receive()
                    guard let o = Self.object(text) else { continue }
                    switch o["type"] as? String {
                    case "registered":
                        return (o["payload"] as? [String: Any])?["client-key"] as? String
                    case "error":
                        throw TVPairingError.refused(o["error"] as? String)
                    default:
                        continue
                    }
                }
            }
        } catch is TVTimeoutError {
            throw TVPairingError.refused("timeout")
        } catch let e as TVPairingError {
            throw e
        } catch {
            throw TVPairingError.unreachable("\(error)")
        }
    }

    /// `ssap://…` isteği. Yanıtın `payload`'ı döner.
    public func request(_ uri: String, payload: [String: Any]? = nil) async throws -> [String: Any] {
        guard let ws = socket else { throw TVPairingError.unreachable("not connected") }
        let id = "req_\(nextID)"
        nextID += 1
        var m: [String: Any] = ["type": "request", "id": id, "uri": uri]
        if let payload { m["payload"] = payload }
        do {
            try await ws.send(Self.jsonText(m))
            return try await withTimeout(timing.request) {
                while true {
                    guard let o = Self.object(try await ws.receive()), o["id"] as? String == id else { continue }
                    if o["type"] as? String == "error" {
                        return ["returnValue": false, "errorText": o["error"] as? String ?? ""]
                    }
                    return o["payload"] as? [String: Any] ?? [:]
                }
            }
        } catch {
            close()
            throw error
        }
    }

    /// En son açılabilen TV uygulamasının kimliği (yeni ya da eski). Açık tutma aynı kimlikle sürer.
    public private(set) var launchedAppID: String?

    /// Yeni uygulama kurulunca çağrılır: sonraki açmada sıra yeniden yeni kimlikten başlar.
    public func forgetLaunchedApp() { launchedAppID = nil }

    /// TV uygulamasını sunucu adresiyle açar. `false`: açılamadı (ne yeni ne eski uygulama kurulu).
    public func launchApp(server: String) async throws -> Bool {
        try await launchNino(server: server) != nil
    }

    /// Önce en son açılan kimlik; o yoksa ya da açılmazsa sırayla yeni, sonra eski kimlik. Kurulu uygulamalar
    /// sorulabildiyse (`listApps`) kurulu olmayan kimlik atlanır. Dönen değer açılan kimlik; hiçbiri açılmadıysa nil.
    public func launchNino(server: String) async throws -> String? {
        if let id = launchedAppID {
            if try await launch(id, server: server) { return id }
            launchedAppID = nil
        }
        var candidates = TVApp.lgIDs
        if queryApps, !listAppsFailed {
            do {
                if let installed = try await installedAppIDs() {
                    let present = candidates.filter(installed.contains)
                    if !present.isEmpty { candidates = present }
                }
            } catch {
                listAppsFailed = true
                if socket == nil { throw error }
            }
        }
        for id in candidates where try await launch(id, server: server) {
            launchedAppID = id
            return id
        }
        return nil
    }

    func launch(_ id: String, server: String) async throws -> Bool {
        let r = try await request("ssap://system.launcher/launch", payload: ["id": id, "params": ["server": server]])
        return (r["returnValue"] as? Bool) != false
    }

    /// Kurulu uygulamaların kimlikleri (`listApps`). Liste gelmezse nil (bilinmiyor).
    func installedAppIDs() async throws -> Set<String>? {
        let r = try await request("ssap://com.webos.applicationManager/listApps")
        guard let apps = r["apps"] as? [[String: Any]], !apps.isEmpty else { return nil }
        return Set(apps.compactMap { $0["id"] as? String })
    }

    public func foregroundAppID() async throws -> String? {
        try await request("ssap://com.webos.applicationManager/getForegroundAppInfo")["appId"] as? String
    }

    /// TV kendi girişine geçmiş mi (HDMI, harici giriş, canlı yayın). Netflix gibilerine dokunulmaz.
    public static func isTVOwnInput(_ appID: String?) -> Bool {
        guard let appID else { return false }
        return appID.hasPrefix("com.webos.app.hdmi") || appID.hasPrefix("com.webos.app.externalinput")
            || appID == "com.webos.app.livetv"
    }

    public func close() {
        socket?.close()
        socket = nil
    }

    static func object(_ text: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    static func jsonText(_ o: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: Zaman aşımı

struct TVTimeoutError: Error, Equatable {}

/// İşi süreyle sınırlar; süre dolunca iş iptal edilir, `TVTimeoutError` atılır. İptale yanıt vermeyen
/// işin bitmesi beklenmez (soket okuması gibi).
func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    let once = TVOnce()
    var workTask: Task<Void, Never>?
    var timerTask: Task<Void, Never>?
    defer {
        workTask?.cancel()
        timerTask?.cancel()
    }
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            workTask = Task {
                do {
                    let v = try await work()
                    if once.claim() { cont.resume(returning: v) }
                } catch {
                    if once.claim() { cont.resume(throwing: error) }
                }
            }
            timerTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                if once.claim() { cont.resume(throwing: TVTimeoutError()) }
            }
            once.onCancel = { if once.claim() { cont.resume(throwing: CancellationError()) } }
        }
    } onCancel: {
        once.cancel()
    }
}

/// Bir kez sonuç verme bayrağı.
final class TVOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private var cancelled = false
    private var cancelHandler: (() -> Void)?

    var onCancel: (() -> Void)? {
        get { lock.withLock { cancelHandler } }
        set {
            let fire: Bool = lock.withLock {
                cancelHandler = newValue
                return cancelled
            }
            if fire { newValue?() }
        }
    }

    func claim() -> Bool {
        lock.withLock {
            if done { return false }
            done = true
            return true
        }
    }

    func cancel() {
        let h: (() -> Void)? = lock.withLock {
            cancelled = true
            return cancelHandler
        }
        h?()
    }
}
