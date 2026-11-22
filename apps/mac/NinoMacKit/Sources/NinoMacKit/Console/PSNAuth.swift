// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// PSN girişinin ağdan bağımsız parçaları (kurulum.md §5): adresler, istekler, yanıt okuma.
///
/// İstemci bilgileri açık kaynak Remote Play istemcisinin herkesçe bilinen değerleridir.
public enum PSNAuth {
    public static let authorizeURL = URL(string: "https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/authorize")!
    public static let tokenURL = URL(string: "https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/token")!
    public static let redirectURI = "https://remoteplay.dl.playstation.net/remoteplay/redirect"
    public static let clientID = "ba495a24-818c-472b-b12d-ff231c1b5745"
    static let clientSecret = "mvaiZkRsAsI1IBkY"
    public static let scope = "psn:clientapp referenceDataService:countryConfig.read "
        + "pushNotification:webSocket.desktop.connect sessionManager:remotePlaySession.system.update"
    static let timeout: TimeInterval = 30

    // MARK: Giriş sayfası

    /// Gömülü tarayıcının açtığı giriş sayfası.
    public static func signInURL() -> URL {
        var c = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        // Sıra, Sony'nin giriş sayfasının beklediği sıradır.
        let parameters: KeyValuePairs<String, String> = [
            "service_entity": "urn:service-entity:psn", "response_type": "code",
            "client_id": clientID, "redirect_uri": redirectURI, "scope": scope,
            "request_locale": "en_US", "ui": "pr", "service_logo": "ps", "layout_type": "popup",
            "smcid": "remoteplay", "prompt": "always", "PlatformPrivacyWs1": "minimal",
        ]
        c.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        // "+" sorgu içinde boşluk sayılabilir; açıkça kodlanır.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url!
    }

    // MARK: Yönlendirme

    public enum Redirect: Equatable, Sendable {
        case code(String)
        /// "error: açıklama (kod)" biçiminde toplanmış Sony hatası.
        case error(String)
        /// `code` ya da `error` alanı var ama ikisi de boş.
        case empty
    }

    /// Adres yönlendirme önekiyle başlıyor ve içinde `code` ya da `error` varsa onu verir; yoksa `nil`
    /// (gezinme sürer).
    public static func redirect(from url: URL) -> Redirect? {
        guard url.absoluteString.hasPrefix(redirectURI),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.contains(where: { $0.name == "code" || $0.name == "error" }) else { return nil }
        func value(_ name: String) -> String? {
            guard let v = items.first(where: { $0.name == name })?.value else { return nil }
            let text = v.replacingOccurrences(of: "+", with: " ").trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        if let code = value("code") { return .code(code) }
        if let error = value("error") {
            var text = error
            if let description = value("error_description") { text += ": " + description }
            if let code = value("error_code") { text += " (" + code + ")" }
            return .error(text)
        }
        return .empty
    }

    // MARK: Token istekleri

    /// Koddan token almak için POST isteği.
    public static func tokenRequest(code: String) -> URLRequest {
        var r = baseRequest(url: tokenURL)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = Data(formEncode([
            ("grant_type", "authorization_code"),
            ("code", code),
            ("scope", scope),
            ("redirect_uri", redirectURI),
        ]).utf8)
        return r
    }

    /// Token bilgisini (içinde `user_id`) almak için GET isteği: `…/oauth/token/<access_token>`.
    public static func accountRequest(accessToken: String) -> URLRequest {
        let escaped = accessToken.addingPercentEncoding(withAllowedCharacters: unreserved) ?? accessToken
        var r = baseRequest(url: URL(string: tokenURL.absoluteString + "/" + escaped)!)
        r.httpMethod = "GET"
        return r
    }

    private static func baseRequest(url: URL) -> URLRequest {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        r.httpShouldHandleCookies = false
        let basic = Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()
        r.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        return r
    }

    private static let unreserved: CharacterSet = {
        var set = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        set.insert(charactersIn: "-._~")
        return set
    }()

    /// Sıkı form kodlaması: yalnız harf, rakam ve "-._~" olduğu gibi kalır.
    static func formEncode(_ pairs: [(String, String)]) -> String {
        pairs.map { key, value in
            (key.addingPercentEncoding(withAllowedCharacters: unreserved) ?? key) + "="
                + (value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value)
        }.joined(separator: "&")
    }

    // MARK: Yanıtlar

    /// Token yanıtından `access_token`.
    public static func accessToken(status: Int, body: Data) throws -> String {
        try checkStatus(status, body: body)
        guard let json = jsonObject(body), let token = json["access_token"] as? String, !token.isEmpty else {
            throw PSNLoginError.unreadable(detail: bodyPreview(body))
        }
        return token
    }

    /// Token bilgisi yanıtından 8 baytlık hesap kimliği: `user_id` (ondalık) → 64 bit → little-endian.
    public static func accountID(status: Int, body: Data) throws -> Data {
        try checkStatus(status, body: body)
        guard let json = jsonObject(body) else { throw PSNLoginError.unreadable(detail: bodyPreview(body)) }
        let text: String?
        switch json["user_id"] {
        case let s as String: text = s
        case let n as NSNumber: text = n.stringValue
        default: text = nil
        }
        guard let text, let id = accountID(userID: text) else {
            throw PSNLoginError.unreadable(detail: bodyPreview(body))
        }
        return id
    }

    /// Ondalık `user_id` metnini 8 baytlık little-endian diziye çevirir.
    public static func accountID(userID: String) -> Data? {
        guard let value = UInt64(userID.trimmingCharacters(in: .whitespaces)) else { return nil }
        return withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    /// HTTP durumunu sınıflar; 2xx değilse hata fırlatır.
    static func checkStatus(_ status: Int, body: Data) throws {
        guard !(200..<300).contains(status) else { return }
        let sony = sonyErrorText(body)
        let detail = ["HTTP \(status)", sony ?? bodyPreview(body)].compactMap { $0 }.joined(separator: ", ")
        if status == 429 || mentionsRateLimit(sony ?? "") { throw PSNLoginError.tooManyAttempts(detail: detail) }
        if [400, 401, 403].contains(status) { throw PSNLoginError.rejected(detail: detail) }
        throw PSNLoginError.server(detail: detail)
    }

    static func mentionsRateLimit(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("too many") || t.contains("too_many") || t.contains("rate limit")
    }

    private static func jsonObject(_ body: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    /// Sony'nin JSON hata metni ("error_description" ya da "error"; varsa kodla).
    static func sonyErrorText(_ body: Data) -> String? {
        guard let json = jsonObject(body) else { return nil }
        let parts = [json["error"], json["error_description"], json["error_code"]]
            .compactMap { v -> String? in
                if let s = v as? String, !s.isEmpty { return s }
                if let n = v as? NSNumber { return n.stringValue }
                return nil
            }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// JSON değilse gövdenin ilk 200 karakteri.
    static func bodyPreview(_ body: Data) -> String? {
        guard jsonObject(body) == nil else { return nil }
        let text = String(decoding: body.prefix(2000), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(200))
    }

    // MARK: Elle giriş ve gösterim

    /// Elle yazılan hesap kimliği: boşluklar atılır, tam 12 karakter ve base64 çözümü tam 8 bayt.
    public static func manualAccountID(_ text: String) -> Data? {
        let s = text.filter { !$0.isWhitespace }
        guard s.count == 12, let data = Data(base64Encoded: s), data.count == 8 else { return nil }
        return data
    }

    /// Ekrandaki maskeli kimlik: base64 metnin ilk 4 ve son 4 karakteri, arada "••••".
    public static func maskedAccountID(_ id: Data) -> String {
        let s = id.base64EncodedString()
        guard s.count >= 8 else { return s }
        return String(s.prefix(4)) + "••••" + String(s.suffix(4))
    }
}
