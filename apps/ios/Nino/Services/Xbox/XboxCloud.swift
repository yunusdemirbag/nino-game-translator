// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// WebRTC ICE adayı (Xbox'ın beklediği JSON biçimiyle).
struct XboxCandidate: Equatable, Sendable {
    var candidate: String
    var sdpMid: String?
    var sdpMLineIndex: Int32

    var json: XboxJSON.Object {
        ["candidate": candidate, "sdpMid": sdpMid.map { $0 as Any } ?? NSNull(), "sdpMLineIndex": Int(sdpMLineIndex)]
    }

    init(candidate: String, sdpMid: String?, sdpMLineIndex: Int32) {
        self.candidate = candidate
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
    }

    init(json: XboxJSON.Object) {
        candidate = XboxJSON.string(json, "candidate")
        sdpMid = json["sdpMid"] as? String
        sdpMLineIndex = Int32(XboxJSON.number(json, "sdpMLineIndex") ?? 0)
    }

    /// WebRTC'ye verilen satır ("a=" öneki olmadan); aday değilse (ör. "end-of-candidates") nil.
    var line: String? {
        var text = candidate.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("a=") { text = String(text.dropFirst(2)) }
        return text.hasPrefix("candidate:") ? text : nil
    }

    /// Adayın adres alanı (5. sözcük).
    var address: String? {
        let words = candidate.split(separator: " ", omittingEmptySubsequences: false)
        return words.count > 4 ? String(words[4]) : nil
    }
}

/// Teredo (2001:0::/32) adresinin içindeki istemci IPv4 adresi ve UDP bağlantı noktası. Xbox bazı ağlarda yalnız Teredo
/// adayı verir; aynı ağdaki telefon ona doğrudan IPv4 ile ulaşır.
enum TeredoAddress {
    static func decode(_ address: String) -> (ipv4: String, port: Int)? {
        guard let words = ipv6Words(address), words[0] == 0x2001, words[1] == 0 else { return nil }
        let port = (~words[5]) & 0xFFFF
        let high = (~words[6]) & 0xFFFF, low = (~words[7]) & 0xFFFF
        let ip = [high >> 8, high & 0xFF, low >> 8, low & 0xFF].map(String.init).joined(separator: ".")
        return (ip, port)
    }

    /// Sekiz 16 bitlik sözcük; geçersizse nil.
    static func ipv6Words(_ address: String) -> [Int]? {
        var text = address.trimmingCharacters(in: CharacterSet(charactersIn: " []"))
        if let zone = text.firstIndex(of: "%") { text = String(text[..<zone]) }
        guard text.contains(":") else { return nil }
        let parts = text.components(separatedBy: "::")
        guard parts.count <= 2 else { return nil }
        func words(_ part: String) -> [Int]? {
            guard !part.isEmpty else { return [] }
            var out: [Int] = []
            for piece in part.split(separator: ":", omittingEmptySubsequences: false) {
                guard (1...4).contains(piece.count), let value = Int(piece, radix: 16) else { return nil }
                out.append(value)
            }
            return out
        }
        guard let head = words(parts[0]) else { return nil }
        if parts.count == 1 { return head.count == 8 ? head : nil }
        guard let tail = words(parts[1]), head.count + tail.count < 8 else { return nil }
        return head + Array(repeating: 0, count: 8 - head.count - tail.count) + tail
    }
}

/// Ev yayını oturumunun `/state` yanıtı.
struct XboxStreamState: Equatable, Sendable {
    let state: String
    /// Boş ya da yalnız boş alanlı nesneyse nil.
    let errorDetails: String?

    init(state: String, errorDetails: String?) {
        self.state = state
        self.errorDetails = errorDetails
    }

    init(response: XboxJSON.Object) {
        state = XboxJSON.string(response, "state")
        errorDetails = Self.meaningful(response["errorDetails"])
    }

    /// `errorDetails` gerçek bir hata taşıyor mu: null, boş metin, `{}` ve tüm alanları boş/null nesne sayılmaz.
    static func meaningful(_ value: Any?) -> String? {
        switch value {
        case nil, is NSNull: return nil
        case let text as String:
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty || t == "null" || t == "{}" { return nil }
            if let object = try? XboxJSON.object(t) { return meaningful(object) }
            return t
        case let object as XboxJSON.Object:
            let filled = object.values.contains { v in
                if v is NSNull { return false }
                if let s = v as? String { return !s.isEmpty }
                return true
            }
            return filled ? XboxJSON.text(object) : nil
        case let other?:
            return "\(other)"
        }
    }
}

/// Xbox'ın bulut uçları: hesaptaki Xbox listesi ve ev yayını sinyalleşmesi (oturum aç, hazır olmasını bekle, konsola
/// bağla, SDP ve ICE değiş tokuşu, canlı tut, kapat).
struct XboxCloud: Sendable {
    /// Ev yayını yalnız Windows/tarayıcı istemcisi olarak tanıtılan istekleri kabul ediyor.
    static let deviceInfo = XboxJSON.text([
        "appInfo": ["env": ["clientAppId": "Microsoft.GamingApp", "clientAppType": "native", "clientAppVersion": "2203.1001.4.0",
                            "clientSdkVersion": "8.5.2", "httpEnvironment": "prod", "sdkInstallId": ""]],
        "dev": ["hw": ["make": "Microsoft", "model": "Surface Pro", "sdktype": "native"],
                "os": ["name": "Windows 11", "ver": "22631.2715", "platform": "desktop"],
                "displayInfo": ["dimensions": ["widthInPixels": 1920, "heightInPixels": 1080],
                                "pixelDensity": ["dpiX": 1, "dpiY": 1]]],
    ] as XboxJSON.Object)

    let account: XboxAccount
    let web: XboxWeb
    var exchangeAttempts = 30
    var exchangeInterval: TimeInterval = 0.25
    var pause: @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }

    init(account: XboxAccount, web: XboxWeb) {
        self.account = account
        self.web = web
    }

    // MARK: Xbox listesi

    func consoles() async throws -> [XboxConsole] {
        let xsts = try await account.xsts(for: XboxAccount.Wire.xboxLiveParty)
        let r = try await web.send(XboxWebRequest(
            url: "https://xccs.xboxlive.com/lists/devices?queryCurrentDevice=false&includeStorageDevices=true",
            headers: ["Authorization": xsts.authorization, "x-xbl-contract-version": "4", "skillplatform": "RemoteManagement",
                      "Accept": "application/json", "Accept-Language": "en-US", "Content-Type": "application/json"]))
        if r.status == 401 || r.status == 403 { throw XboxFailure(.needsSignIn, "Xbox listesi: HTTP \(r.status)") }
        return XboxConsole.list(from: try r.object("Xbox listesi"))
    }

    // MARK: Ev yayını

    /// Oturum açar; dönüş oturum kimliği.
    func play(console: String, timezoneMinutes: Int = TimeZone.current.secondsFromGMT() / 60) async throws -> String {
        let settings: XboxJSON.Object = [
            "nanoVersion": "V3;WebrtcTransport.dll", "enableOptionalDataCollection": false, "enableTextToSpeech": false,
            "highContrast": 0, "locale": "en-US", "useIceConnection": false, "timezoneOffsetMinutes": timezoneMinutes,
            "sdkType": "web", "osName": "windows",
        ]
        let body: XboxJSON.Object = ["serverId": console, "titleId": "", "clientSessionId": "", "systemUpdateGroup": "",
                                     "fallbackRegionNames": [String](), "settings": settings]
        let reply = try await call("/v5/sessions/home/play", method: "POST", body: body) ?? [:]
        guard let id = XboxJSON.string(reply, "sessionPath").split(separator: "/").last.map(String.init), !id.isEmpty else {
            throw XboxFailure(.unexpected, "oturum kimliği gelmedi")
        }
        return id
    }

    func state(_ session: String) async throws -> XboxStreamState {
        XboxStreamState(response: try await call("/v5/sessions/home/\(session)/state") ?? [:])
    }

    func connect(_ session: String) async throws {
        let transfer = try await account.consoleTransferToken()
        try await call("/v5/sessions/home/\(session)/connect", method: "POST", body: ["userToken": transfer])
    }

    /// Teklifi gönderir, Xbox'ın yanıt SDP'sini döner.
    func exchangeSDP(_ session: String, offer: String) async throws -> String {
        func version(_ low: Int, _ high: Int) -> XboxJSON.Object { ["minVersion": low, "maxVersion": high] }
        let chat: XboxJSON.Object = ["bytesPerSample": 2, "expectedClipDurationMs": 20, "numChannels": 1, "sampleFrequencyHz": 24000,
                                     "format": ["codec": "opus", "container": "webm"]]
        let body: XboxJSON.Object = ["messageType": "offer", "sdp": offer, "configuration": [
            "chatConfiguration": chat, "chat": version(1, 1), "control": version(1, 3), "input": version(1, 8), "message": version(1, 1),
        ] as XboxJSON.Object]
        let text = try await exchange("/v5/sessions/home/\(session)/sdp", body)
        let answer = XboxJSON.string(try XboxJSON.object(text), "sdp")
        guard !answer.isEmpty else { throw XboxFailure(.unexpected, "SDP yanıtı boş") }
        return answer
    }

    /// Yerel adayları gönderir, Xbox'ınkileri döner (Teredo adaylarının IPv4 karşılıkları önde).
    func exchangeICE(_ session: String, local: [XboxCandidate]) async throws -> [XboxCandidate] {
        let text = try await exchange("/v5/sessions/home/\(session)/ice",
                                      ["messageType": "iceCandidate", "candidate": local.map(\.json)])
        guard let list = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [XboxJSON.Object] else {
            throw XboxFailure(.unexpected, "ICE yanıtı okunamadı")
        }
        return Self.withTeredoShortcuts(list.map(XboxCandidate.init(json:)))
    }

    func keepAlive(_ session: String) async throws {
        try await call("/v5/sessions/home/\(session)/keepalive", method: "POST", body: [:])
    }

    func close(_ session: String) async throws {
        try await call("/v5/sessions/home/\(session)", method: "DELETE")
    }

    /// Teredo adresli her adayın önüne, aynı ağdan doğrudan ulaşılabilecek iki IPv4 adayı (9002 ve Teredo portu) konur.
    static func withTeredoShortcuts(_ candidates: [XboxCandidate]) -> [XboxCandidate] {
        candidates.flatMap { c -> [XboxCandidate] in
            guard let address = c.address, address.hasPrefix("2001"), let teredo = TeredoAddress.decode(address) else { return [c] }
            let direct = [9002, teredo.port].map { port in
                XboxCandidate(candidate: "a=candidate:10 1 UDP 1 \(teredo.ipv4) \(port) typ host ", sdpMid: c.sdpMid,
                              sdpMLineIndex: c.sdpMLineIndex)
            }
            return direct + [c]
        }
    }

    /// Hizmet hata yanıtının anlamı.
    static func problem(status: Int, text: String) -> XboxProblem {
        let t = text.lowercased()
        if status == 401 || status == 403 { return .needsSignIn }
        if t.contains("inuse") || t.contains("busy") { return .busy }
        if status == 404 || t.contains("notfound") || t.contains("offline") { return .unreachable }
        return .unexpected
    }

    // MARK: İstek

    @discardableResult
    private func call(_ path: String, method: String = "GET", body: XboxJSON.Object? = nil) async throws -> XboxJSON.Object? {
        let login = try await account.streamingLogin()
        let r = try await web.send(XboxWebRequest(
            method: method, url: login.baseURL + path,
            headers: ["Authorization": "Bearer \(login.token)", "Accept": "application/json", "Content-Type": "application/json",
                      "X-Gssv-Client": "XboxComBrowser", "X-MS-Device-Info": Self.deviceInfo],
            body: body.map(XboxJSON.text)))
        guard r.succeeded else {
            throw XboxFailure(Self.problem(status: r.status, text: r.text), "HTTP \(r.status) \(r.text.prefix(300))")
        }
        return r.body.isEmpty ? nil : try XboxJSON.object(r.body)
    }

    /// Gönder, sonra yanıt gelene kadar kısa aralıkla sor.
    private func exchange(_ path: String, _ body: XboxJSON.Object) async throws -> String {
        try await call(path, method: "POST", body: body)
        for _ in 0..<exchangeAttempts {
            let reply = XboxJSON.string(try await call(path) ?? [:], "exchangeResponse")
            if !reply.isEmpty { return reply }
            try await pause(exchangeInterval)
        }
        throw XboxFailure(.timeout, "\(path) yanıtı gelmedi")
    }
}
