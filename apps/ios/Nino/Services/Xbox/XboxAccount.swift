// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Xbox ve Microsoft uçlarına giden tek istek biçimi; testlerde sahte yanıt veren bir sürümü kullanılır.
protocol XboxWeb: Sendable {
    func send(_ request: XboxWebRequest) async throws -> XboxWebResponse
}

struct XboxWebRequest: Sendable, Equatable {
    var method = "GET"
    var url: String
    var headers: [String: String] = [:]
    var body: String?
}

struct XboxWebResponse: Sendable {
    let status: Int
    let body: Data

    init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }

    init(status: Int, text: String) { self.init(status: status, body: Data(text.utf8)) }

    var succeeded: Bool { (200..<300).contains(status) }
    var text: String { String(decoding: body, as: UTF8.self) }

    func object(_ what: String) throws -> XboxJSON.Object {
        guard succeeded else { throw XboxFailure(.unexpected, "\(what): HTTP \(status) \(text.prefix(240))") }
        return try XboxJSON.object(body)
    }
}

/// Gerçek ağ.
struct URLSessionXboxWeb: XboxWeb {
    func send(_ request: XboxWebRequest) async throws -> XboxWebResponse {
        guard let url = URL(string: request.url) else { throw XboxFailure(.unexpected, "adres: \(request.url)") }
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        r.httpMethod = request.method
        for (name, value) in request.headers { r.setValue(value, forHTTPHeaderField: name) }
        r.httpBody = request.body.map { Data($0.utf8) }
        do {
            let (data, response) = try await URLSession.shared.data(for: r)
            return XboxWebResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw XboxFailure(.offline, error.localizedDescription)
        }
    }
}

/// `application/x-www-form-urlencoded` gövdesi.
func xboxForm(_ fields: KeyValuePairs<String, String>) -> String {
    var safe = CharacterSet.alphanumerics
    safe.insert(charactersIn: "-._~")
    return fields.map { key, value in
        let k = key.addingPercentEncoding(withAllowedCharacters: safe) ?? key
        let v = value.addingPercentEncoding(withAllowedCharacters: safe) ?? value
        return "\(k)=\(v)"
    }.joined(separator: "&")
}

/// Microsoft hesabı ve Xbox jeton zinciri: cihaz kodu girişi → kullanıcı jetonu (kalıcı, kendiliğinden yenilenir) →
/// Xbox Live jetonu → XSTS (Xbox Live ve ev yayını için) → ev yayını girişi. Yalnız Microsoft kullanıcı jetonu
/// saklanır; değiştikçe `onToken` çağrılır. Ötekiler bellekte, süresi dolmadan bir dakika önce yenilenir.
actor XboxAccount {
    enum Wire {
        /// Microsoft'un Xbox tarayıcı istemcisi için kayıtlı uygulama kimliği.
        static let clientID = "1f907974-e22b-4810-a9de-d9647380c97e"
        static let scope = "xboxlive.signin openid profile offline_access"
        static let consoleTransferScope = "service::http://Passport.NET/purpose::PURPOSE_XBOX_CLOUD_CONSOLE_TRANSFER_TOKEN"
        static let oauth = "https://login.microsoftonline.com/consumers/oauth2/v2.0"
        static let liveTransfer = "https://login.live.com/oauth20_token.srf"
        static let userAuth = "https://user.auth.xboxlive.com/user/authenticate"
        static let xsts = "https://xsts.auth.xboxlive.com/xsts/authorize"
        static let streamingLogin = "https://xhome.gssv-play-prod.xboxlive.com/v2/login/user"
        static let xboxLiveParty = "http://xboxlive.com"
        static let streamingParty = "http://gssv.xboxlive.com/"
        static let form = "application/x-www-form-urlencoded"
        static let browser = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        /// XSTS 401 `XErr`: profil yok, ülke uygun değil, yetişkin onayı/çocuk hesabı.
        static let profileErrors: Set<Int64> = [2_148_916_233, 2_148_916_235, 2_148_916_236, 2_148_916_237, 2_148_916_238]
    }

    private let web: XboxWeb
    private let now: @Sendable () -> Date
    private let pause: @Sendable (TimeInterval) async throws -> Void
    private let onToken: @Sendable (MicrosoftToken?) -> Void
    private let margin: TimeInterval = 60

    private(set) var token: MicrosoftToken?
    private var userToken: XboxLiveToken?
    private var xstsTokens: [String: XboxLiveToken] = [:]
    private var streaming: StreamingLogin?

    init(web: XboxWeb = URLSessionXboxWeb(), token: MicrosoftToken?,
         now: @escaping @Sendable () -> Date = { Date() },
         pause: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
         onToken: @escaping @Sendable (MicrosoftToken?) -> Void = { _ in }) {
        self.web = web
        self.token = token
        self.now = now
        self.pause = pause
        self.onToken = onToken
    }

    var signedIn: Bool { token != nil }

    // MARK: Giriş

    func requestCode() async throws -> DeviceCodeChallenge {
        let r = try await web.send(XboxWebRequest(method: "POST", url: "\(Wire.oauth)/devicecode", headers: ["Content-Type": Wire.form],
                                                  body: xboxForm(["client_id": Wire.clientID, "scope": Wire.scope])))
        return try DeviceCodeChallenge(response: r.object("cihaz kodu"))
    }

    /// Kullanıcı kodu onaylayana ya da kodun süresi dolana kadar sorar. Kullanıcı kodu tarayıcıda yazarken uygulama
    /// arka plandadır ve istekler kesilebilir; bağlantı hatası girişi bitirmez.
    @discardableResult
    func waitForApproval(_ code: DeviceCodeChallenge) async throws -> MicrosoftToken {
        let deadline = now().addingTimeInterval(TimeInterval(code.lifetime))
        var interval = TimeInterval(code.interval)
        let request = XboxWebRequest(method: "POST", url: "\(Wire.oauth)/token", headers: ["Content-Type": Wire.form],
                                     body: xboxForm(["grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                                                     "client_id": Wire.clientID, "device_code": code.deviceCode]))
        while true {
            try Task.checkCancellation()
            if now() >= deadline { throw XboxFailure(.codeExpired) }
            let response: XboxWebResponse
            do {
                response = try await web.send(request)
            } catch let failure as XboxFailure where failure.problem == .offline {
                try await pause(interval)
                continue
            }
            if response.succeeded {
                let fresh = try MicrosoftToken(response: XboxJSON.object(response.body), receivedAt: now())
                adopt(fresh)
                return fresh
            }
            switch DeviceCodeWait(status: response.status, body: response.body) {
            case .keepWaiting: break
            case .slowDown: interval += 5
            case .expired: throw XboxFailure(.codeExpired)
            case .declined: throw XboxFailure(.declined)
            case .failed: throw XboxFailure(.unexpected, "giriş: HTTP \(response.status)")
            }
            try await pause(interval)
        }
    }

    func signOut() {
        forgetDerived()
        token = nil
        onToken(nil)
    }

    private func adopt(_ fresh: MicrosoftToken) {
        forgetDerived()
        token = fresh
        onToken(fresh)
    }

    private func forgetDerived() {
        userToken = nil
        xstsTokens = [:]
        streaming = nil
    }

    // MARK: Jeton zinciri

    /// Geçerli Microsoft erişim jetonu; süresi bitmek üzereyse yenilenir ve saklanır.
    func accessToken() async throws -> String {
        guard let current = token else { throw XboxFailure(.needsSignIn) }
        if current.fresh(at: now(), margin: margin) { return current.accessToken }
        let r = try await web.send(XboxWebRequest(
            method: "POST", url: "\(Wire.oauth)/token",
            headers: ["Content-Type": Wire.form, "Cache-Control": "no-store, must-revalidate, no-cache"],
            body: xboxForm(["client_id": Wire.clientID, "grant_type": "refresh_token",
                            "refresh_token": current.refreshToken, "scope": Wire.scope])))
        // 400: yenileme jetonu geçersiz (parola değişti, izin geri alındı, uzun süre kullanılmadı).
        if r.status == 400 || r.status == 401 { throw XboxFailure(.needsSignIn, "yenileme reddedildi") }
        let renewed = try MicrosoftToken(response: r.object("jeton yenileme"), receivedAt: now(), keeping: current)
        token = renewed
        onToken(renewed)
        return renewed.accessToken
    }

    private func xboxUserToken() async throws -> XboxLiveToken {
        if let userToken, userToken.notAfter.timeIntervalSince(now()) > margin { return userToken }
        let access = try await accessToken()
        let body: XboxJSON.Object = [
            "RelyingParty": "http://auth.xboxlive.com", "TokenType": "JWT",
            "Properties": ["AuthMethod": "RPS", "SiteName": "user.auth.xboxlive.com", "RpsTicket": "d=\(access)"],
        ]
        let r = try await web.send(XboxWebRequest(method: "POST", url: Wire.userAuth, headers: Self.liveHeaders, body: XboxJSON.text(body)))
        if r.status == 401 { throw XboxFailure(.needsSignIn, "Xbox Live oturumu reddetti (401)") }
        let fresh = try XboxLiveToken(response: r.object("Xbox Live jeton yanıtı"))
        userToken = fresh
        return fresh
    }

    /// Bir hizmet için XSTS jetonu.
    func xsts(for party: String) async throws -> XboxLiveToken {
        if let cached = xstsTokens[party], cached.notAfter.timeIntervalSince(now()) > margin { return cached }
        let user = try await xboxUserToken()
        let body: XboxJSON.Object = [
            "RelyingParty": party, "TokenType": "JWT",
            "Properties": ["SandboxId": "RETAIL", "UserTokens": [user.token]],
        ]
        var headers = Self.liveHeaders
        headers["Accept"] = "*/*"
        headers["ms-cv"] = "0"
        headers["User-Agent"] = Wire.browser
        let r = try await web.send(XboxWebRequest(method: "POST", url: Wire.xsts, headers: headers, body: XboxJSON.text(body)))
        if r.status == 401 {
            let code = ((try? XboxJSON.object(r.body))?["XErr"] as? NSNumber)?.int64Value ?? 0
            throw XboxFailure(Wire.profileErrors.contains(code) ? .noProfile : .needsSignIn, "XErr \(code)")
        }
        let fresh = try XboxLiveToken(response: r.object("XSTS"))
        xstsTokens[party] = fresh
        return fresh
    }

    /// Ev yayını hizmetinin adresi ve jetonu.
    func streamingLogin() async throws -> StreamingLogin {
        if let streaming, streaming.expires.timeIntervalSince(now()) > margin { return streaming }
        let xsts = try await xsts(for: Wire.streamingParty)
        let r = try await web.send(XboxWebRequest(
            method: "POST", url: Wire.streamingLogin,
            headers: ["Content-Type": "application/json", "Cache-Control": "no-store, must-revalidate, no-cache",
                      "x-gssv-client": "XboxComBrowser"],
            body: XboxJSON.text(["offeringId": "xhome", "token": xsts.token])))
        if r.status == 401 || r.status == 403 { throw XboxFailure(.needsSignIn, "ev yayını girişi: HTTP \(r.status)") }
        let fresh = try StreamingLogin(response: r.object("ev yayını girişi"), receivedAt: now())
        streaming = fresh
        return fresh
    }

    /// Yayını konsola bağlamak için tek seferlik aktarım jetonu.
    func consoleTransferToken() async throws -> String {
        _ = try await accessToken()
        guard let refresh = token?.refreshToken else { throw XboxFailure(.needsSignIn) }
        let r = try await web.send(XboxWebRequest(
            method: "POST", url: Wire.liveTransfer, headers: ["Content-Type": Wire.form],
            body: xboxForm(["client_id": Wire.clientID, "scope": Wire.consoleTransferScope,
                            "grant_type": "refresh_token", "refresh_token": refresh])))
        if r.status == 400 || r.status == 401 { throw XboxFailure(.needsSignIn, "aktarım jetonu reddedildi") }
        let value = XboxJSON.string(try r.object("aktarım jetonu"), "access_token")
        guard !value.isEmpty else { throw XboxFailure(.unexpected, "aktarım jetonu boş") }
        return value
    }

    private static let liveHeaders: [String: String] = [
        "Content-Type": "application/json", "x-xbl-contract-version": "1", "Cache-Control": "no-cache",
        "Origin": "https://www.xbox.com", "Referer": "https://www.xbox.com/",
    ]
}
