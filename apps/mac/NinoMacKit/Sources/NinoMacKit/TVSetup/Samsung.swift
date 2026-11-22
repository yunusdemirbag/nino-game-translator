// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// MARK: 8001 cihaz bilgisi

/// `http://<adres>:8001/api/v2/` yanıtı (tv-kurulumu.md §2, §5.2).
public struct SamsungDeviceInfo: Equatable, Sendable {
    public var name: String?
    /// "1"/"true" açık, "0" kapalı, yoksa nil.
    public var developerMode: Bool?
    /// Boş ya da "0.0.0.0" ise nil.
    public var developerIP: String?
    public var model: String?

    public init(name: String? = nil, developerMode: Bool? = nil, developerIP: String? = nil, model: String? = nil) {
        self.name = name
        self.developerMode = developerMode
        self.developerIP = developerIP
        self.model = model
    }

    public static func parse(_ data: Data) -> SamsungDeviceInfo? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let device = o["device"] as? [String: Any] ?? [:]
        func text(_ any: Any?) -> String? {
            switch any {
            case let s as String: return s
            case let n as NSNumber: return n.stringValue
            default: return nil
            }
        }
        var info = SamsungDeviceInfo()
        let rawName = text(device["name"]) ?? text(o["name"])
        info.name = rawName.map { $0.replacingOccurrences(of: "&quot;", with: "\"") }.flatMap { $0.isEmpty ? nil : $0 }
        switch text(device["developerMode"])?.lowercased() {
        case "1", "true": info.developerMode = true
        case "0", "false": info.developerMode = false
        default: info.developerMode = nil
        }
        let ip = text(device["developerIP"])?.trimmingCharacters(in: .whitespaces) ?? ""
        info.developerIP = ip.isEmpty || ip == "0.0.0.0" ? nil : ip
        info.model = text(device["model"])
        return info
    }

    /// "23_KANTSU2E_QLED" → 2023 (ilk iki hane 15–60 arasıysa).
    public var modelYear: Int? {
        guard let model, model.count >= 2 else { return nil }
        let two = model.prefix(2)
        guard two.allSatisfy(\.isNumber), let n = Int(two), (15...60).contains(n) else { return nil }
        return 2000 + n
    }
}

// MARK: Kurulu uygulama sorgusu

/// `http://<adres>:8001/api/v2/applications/<kimlik>`: 200 kurulu, 404 kurulu değil, başka her şey bilinmiyor (nil).
/// Bazı modeller bu yolu kapatır; o yüzden yalnız ipucudur.
public enum SamsungAppQuery {
    public static func url(host: String, appID: String) -> URL? {
        URL(string: "http://\(host):8001/api/v2/applications/\(appID)")
    }

    public static func isInstalled(_ http: TVHTTP, host: String, appID: String, timeout: TimeInterval = 2) async -> Bool? {
        guard let url = url(host: host, appID: appID), let r = try? await http.get(url, timeout: timeout) else { return nil }
        switch r.status {
        case 200: return true
        case 404: return false
        default: return nil
        }
    }
}

// MARK: Eksik adım

/// Samsung geliştirici modu denetiminde ilk tutan eksik adım.
public enum SamsungMissingStep: Equatable, Sendable {
    case tvNotResponding
    case developerModeOff
    case hostLoopback
    case hostLeadingZeros
    case hostReversed
    case hostWrong
    case notRestarted
    /// Kurulum denenebilir.
    case none

    public var isAddressProblem: Bool {
        switch self {
        case .hostLoopback, .hostLeadingZeros, .hostReversed, .hostWrong: return true
        default: return false
        }
    }
}

/// Denetimin ham sonucu ve hesaplanan eksik adım (kart için `SamsungCheck`e çevrilir).
public struct SamsungInspection: Equatable, Sendable {
    /// 8001 yanıtı (yoksa nil).
    public var info: SamsungDeviceInfo?
    /// Kurulum kapısı (TCP 26101) açık mı.
    public var installGateOpen: Bool
    /// Mac'in TV'ye giden adresi.
    public var macAddress: String?

    public init(info: SamsungDeviceInfo?, installGateOpen: Bool, macAddress: String?) {
        self.info = info
        self.installGateOpen = installGateOpen
        self.macAddress = macAddress
    }

    public var tvResponds: Bool { info != nil || installGateOpen }
    /// 8001 söylemezse kapıya bakılır.
    public var developerModeOn: Bool { info?.developerMode ?? installGateOpen }
    public var hostIP: String? { info?.developerIP }

    public var missingStep: SamsungMissingStep {
        if info == nil && !installGateOpen { return .tvNotResponding }
        if !developerModeOn { return .developerModeOff }
        if let tvIP = hostIP, let addressProblem = Self.addressProblem(tvIP: tvIP, macIP: macAddress) {
            return addressProblem
        }
        if !installGateOpen { return .notRestarted }
        return .none
    }

    /// Host PC IP Mac'in adresiyle eşleşiyor mu (bilinmiyorsa nil).
    public var hostMatches: Bool? {
        guard let tvIP = hostIP, let mac = macAddress else { return nil }
        return tvIP == mac
    }

    static func addressProblem(tvIP: String, macIP: String?) -> SamsungMissingStep? {
        if tvIP == "127.0.0.1" { return .hostLoopback }
        guard let macIP, tvIP != macIP else { return nil }
        let parts = tvIP.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let valid = parts.count == 4 && parts.allSatisfy { p in
            (1...3).contains(p.count) && p.allSatisfy(\.isNumber) && (Int(p) ?? 999) <= 255
        }
        if valid {
            let stripped = parts.map { String(Int($0)!) }
            if stripped.joined(separator: ".") == macIP { return .hostLeadingZeros }
            if stripped.reversed().joined(separator: ".") == macIP { return .hostReversed }
        }
        return .hostWrong
    }
}

// MARK: Uzaktan kumanda soketi

/// Samsung uzaktan kumanda WebSocket'i (tv-kurulumu.md §3, §5.2).
public actor SamsungRemote {
    public struct Timing: Sendable {
        public var approval: TimeInterval = 60
        public var connect: TimeInterval = 5
        public var keyStartDelay: TimeInterval = 0.7
        public var pressToRelease: TimeInterval = 0.09
        public var betweenKeys: TimeInterval = 0.28
        public init() {}
    }

    public let host: String
    private let sockets: TVWebSocketConnecting
    private let clock: TVClock
    private let timing: Timing
    private var socket: TVWebSocket?

    public init(host: String, sockets: TVWebSocketConnecting, clock: TVClock = SystemTVClock(), timing: Timing = Timing()) {
        self.host = host
        self.sockets = sockets
        self.clock = clock
        self.timing = timing
    }

    /// "Nino"nun base64'ü.
    public static let clientName = Data("Nino".utf8).base64EncodedString()

    public nonisolated func url(token: String?) -> URL {
        var s = "wss://\(host):8002/api/v2/channels/samsung.remote.control?name=\(Self.clientName)"
        if let token, !token.isEmpty { s += "&token=\(token)" }
        return URL(string: s)!
    }

    /// Bağlanır; TV onayını en çok 60 sn bekler. Dönen jeton boş olabilir (o zaman eldeki korunmalı).
    public func connect(token: String?) async throws -> String {
        let ws: TVWebSocket
        do {
            ws = try await sockets.connect(url: url(token: token), trustedHost: host, timeout: timing.connect)
        } catch {
            throw TVPairingError.unreachable("\(error)")
        }
        do {
            let newToken = try await withTimeout(timing.approval) { () -> String in
                while true {
                    let text = try await ws.receive()
                    guard let o = LGSSAPClient.object(text) else { continue }
                    switch o["event"] as? String {
                    case "ms.channel.connect":
                        let data = o["data"] as? [String: Any]
                        switch data?["token"] {
                        case let s as String: return s
                        case let n as NSNumber: return n.stringValue
                        default: return ""
                        }
                    case "ms.channel.unauthorized":
                        throw TVPairingError.refused(nil)
                    case "ms.channel.timeOut":
                        throw TVPairingError.timedOut
                    default:
                        continue
                    }
                }
            }
            socket = ws
            return newToken
        } catch is TVTimeoutError {
            ws.close()
            throw TVPairingError.timedOut
        } catch let e as TVPairingError {
            ws.close()
            throw e
        } catch {
            ws.close()
            throw TVPairingError.unreachable("\(error)")
        }
    }

    static func launchMessage(server: String, appID: String = TVApp.samsungID) -> String {
        let meta = LGSSAPClient.jsonText(["server": server])
        return LGSSAPClient.jsonText([
            "method": "ms.channel.emit",
            "params": [
                "event": "ed.apps.launch",
                "to": "host",
                "data": ["appId": appID, "action_type": "DEEP_LINK", "metaTag": meta] as [String: Any],
            ] as [String: Any],
        ])
    }

    static func keyMessage(_ key: String, press: Bool) -> String {
        LGSSAPClient.jsonText([
            "method": "ms.remote.control",
            "params": ["Cmd": press ? "Press" : "Release", "DataOfCmd": key, "Option": "false",
                       "TypeOfRemote": "SendRemoteKey"],
        ])
    }

    /// Açma iletisini gönderir (TV yanıt vermez; açılıp açılmadığı altyazı sunucusuna bağlanmadan anlaşılır).
    public func launchApp(server: String, appID: String = TVApp.samsungID) async throws {
        guard let socket else { throw TVPairingError.unreachable("not connected") }
        try await socket.send(Self.launchMessage(server: server, appID: appID))
    }

    /// Geliştirici modu penceresi için `KEY_1`…`KEY_5`: bas, 90 ms sonra bırak, tuşlar arası 280 ms.
    public func typeDeveloperCode() async throws {
        guard let socket else { throw TVPairingError.unreachable("not connected") }
        try await clock.sleep(timing.keyStartDelay)
        for n in 1...5 {
            try await socket.send(Self.keyMessage("KEY_\(n)", press: true))
            try await clock.sleep(timing.pressToRelease)
            try await socket.send(Self.keyMessage("KEY_\(n)", press: false))
            if n < 5 { try await clock.sleep(timing.betweenKeys) }
        }
    }

    public func close() {
        socket?.close()
        socket = nil
    }
}
