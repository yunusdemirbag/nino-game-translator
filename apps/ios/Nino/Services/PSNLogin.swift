// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// PlayStation Network girişi: Sony'nin sayfası açılır, yönlendirmedeki kod alınır, hesap kimliği (8 bayt) okunur.
/// İstemci kimliği ve gizlisi açık kaynak Remote Play istemcilerinin herkese açık kullandığı değerlerdir.
enum PSNLogin {
    static let clientID = "ba495a24-818c-472b-b12d-ff231c1b5745"
    static let clientSecret = "mvaiZkRsAsI1IBkY"
    static let redirect = "https://remoteplay.dl.playstation.net/remoteplay/redirect"
    static let scope = "psn:clientapp referenceDataService:countryConfig.read pushNotification:webSocket.desktop.connect sessionManager:remotePlaySession.system.update"
    static let tokenURL = URL(string: "https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/token")!

    enum Failure: Error, Equatable {
        case noCode
        case rejected(String)
        case tooManyAttempts
        case http(Int)
        case network(String)
        case unreadable

        var message: String {
            switch self {
            case .noCode: L("signin.error.incomplete")
            case .rejected: L("psn.error.notcompleted")
            case .tooManyAttempts: L("psn.error.ratelimit")
            case .http: L("psn.error.server")
            case .network: L("psn.error.network")
            case .unreadable: L("psn.error.badresponse")
            }
        }
    }

    static var authorizeURL: URL {
        var c = URLComponents(string: "https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/authorize")!
        c.queryItems = [
            .init(name: "service_entity", value: "urn:service-entity:psn"),
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "scope", value: scope),
            .init(name: "request_locale", value: "en_US"),
            .init(name: "ui", value: "pr"),
            .init(name: "service_logo", value: "ps"),
            .init(name: "layout_type", value: "popup"),
            .init(name: "smcid", value: "remoteplay"),
            .init(name: "prompt", value: "always"),
            .init(name: "PlatformPrivacyWs1", value: "minimal"),
        ]
        return c.url!
    }

    /// Gezinilen adres girişin yönlendirmesi mi (kod ya da hata taşıyor).
    static func isRedirect(_ url: URL) -> Bool {
        guard url.absoluteString.hasPrefix(redirect),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return false }
        return items.contains { $0.name == "code" && !($0.value ?? "").isEmpty }
            || items.contains { $0.name == "error" && !($0.value ?? "").isEmpty }
    }

    private static func classify(_ text: String) -> Failure {
        let lower = text.lowercased()
        return lower.contains("too many") || lower.contains("too_many") || lower.contains("rate limit")
            ? .tooManyAttempts : .rejected(text)
    }

    /// Yönlendirmedeki kod ya da hata.
    static func code(from url: URL) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 } }
        if let code = value("code") { return code }
        if let error = value("error") {
            var text = error
            if let d = value("error_description") { text += ": " + d.replacingOccurrences(of: "+", with: " ") }
            if let c = value("error_code") { text += " (\(c))" }
            throw classify(text)
        }
        throw Failure.noCode
    }

    /// 8 baytlık hesap kimliği (little-endian).
    static func accountID(fromUserID text: String) -> Data? {
        guard let n = UInt64(text) else { return nil }
        return withUnsafeBytes(of: n.littleEndian) { Data($0) }
    }

    private static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }

    private static var basicAuth: String {
        "Basic " + Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()
    }

    private static func send(_ request: URLRequest, using session: URLSession) async throws -> [String: Any] {
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch { throw Failure.network(error.localizedDescription) }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var detail = String(decoding: data.prefix(200), as: UTF8.self)
            if let json {
                detail = [json["error"], json["error_description"], json["error_code"]].compactMap { $0.map { "\($0)" } }.joined(separator: " ")
            }
            let lower = detail.lowercased()
            if status == 429 || lower.contains("too many") || lower.contains("too_many") || lower.contains("rate limit") {
                throw Failure.tooManyAttempts
            }
            if [400, 401, 403].contains(status) { throw Failure.rejected(detail) }
            throw Failure.http(status)
        }
        guard let json else { throw Failure.unreadable }
        return json
    }

    /// Yönlendirme adresinden hesap kimliğine.
    static func accountID(redirect url: URL) async throws -> Data {
        let code = try code(from: url)
        let session = session()
        var token = URLRequest(url: tokenURL)
        token.httpMethod = "POST"
        token.setValue(basicAuth, forHTTPHeaderField: "Authorization")
        token.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "code", value: code),
            .init(name: "scope", value: scope),
            .init(name: "redirect_uri", value: redirect),
        ]
        token.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let tokenReply = try await send(token, using: session)
        guard let access = tokenReply["access_token"] as? String else {
            if let e = tokenReply["error"] { throw classify("\(e)") }
            throw Failure.unreadable
        }
        var info = URLRequest(url: tokenURL.appendingPathComponent(access))
        info.setValue(basicAuth, forHTTPHeaderField: "Authorization")
        let infoReply = try await send(info, using: session)
        guard let user = infoReply["user_id"].map({ "\($0)" }), let id = accountID(fromUserID: user) else {
            throw Failure.unreadable
        }
        return id
    }
}
