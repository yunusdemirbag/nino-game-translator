// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// PSN girişinin hataları (kurulum.md §5, "Hatalar ve iletileri").
public enum PSNLoginError: Error, Equatable, Sendable {
    /// Yönlendirmede ne kod ne hata vardı.
    case incomplete
    /// Sony reddetti (yönlendirmede hata ya da token isteği 400/401/403).
    case rejected(detail: String?)
    case tooManyAttempts(detail: String?)
    case server(detail: String?)
    case network(detail: String?)
    /// Yanıt okunamadı (JSON değil, `user_id` yok).
    case unreadable(detail: String?)
    /// Pencere, giriş bitmeden kapatıldı ve sayfada sorun yoktu.
    case windowClosed
    /// Pencere kapandı, giriş sayfası yüklenemiyordu.
    case pageFailed(detail: String?)

    /// Yönlendirmedeki Sony hata metninden.
    static func fromRedirectError(_ text: String) -> PSNLoginError {
        PSNAuth.mentionsRateLimit(text) ? .tooManyAttempts(detail: text) : .rejected(detail: text)
    }

    /// Pencere yönlendirme yakalanmadan kapandı.
    public static func windowClosed(pageProblem: String?) -> PSNLoginError {
        guard let p = pageProblem, !p.isEmpty else { return .windowClosed }
        return p.contains("429") ? .tooManyAttempts(detail: p) : .pageFailed(detail: p)
    }

    public var detail: String? {
        switch self {
        case .incomplete, .windowClosed: return nil
        case let .rejected(d), let .tooManyAttempts(d), let .server(d), let .network(d), let .unreadable(d),
             let .pageFailed(d): return d
        }
    }

    var key: String {
        switch self {
        case .incomplete: return "console.psn.error.incomplete"
        case .rejected: return "console.psn.error.rejected"
        case .tooManyAttempts: return "console.psn.error.tooManyAttempts"
        case .server: return "console.psn.error.server"
        case .network: return "console.psn.error.network"
        case .unreadable: return "console.psn.error.unreadable"
        case .windowClosed: return "console.psn.error.windowClosed"
        case .pageFailed: return "console.psn.error.pageFailed"
        }
    }

    /// Kullanıcıya gösterilen ileti. Pencere kapatıldı iletisi dışındakilere günlük dosyasının yolu eklenir.
    public func message(logPath: String) -> String {
        if self == .windowClosed { return ConsoleText.string(key) }
        return ConsoleText.withDetailAndLog(ConsoleText.string(key), detail: detail, logPath: logPath)
    }

    /// Günlüğe yazılan kısa ad.
    var logName: String {
        switch self {
        case .incomplete: return "tamamlanmadı"
        case .rejected: return "Sony reddetti"
        case .tooManyAttempts: return "çok fazla deneme"
        case .server: return "sunucu hatası"
        case .network: return "ağ hatası"
        case .unreadable: return "yanıt okunamadı"
        case .windowClosed: return "pencere kapandı"
        case .pageFailed: return "sayfa yüklenemedi"
        }
    }
}

// MARK: Ağ

/// HTTP gönderen kapı; testlerde sahte yanıt verir.
public protocol PSNHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

/// Çerezsiz, önbelleksiz URLSession.
public struct PSNEphemeralTransport: PSNHTTPTransport {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = PSNAuth.timeout
        session = URLSession(configuration: config)
    }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// Yönlendirme sonucundan hesap kimliğine giden iki istek. Token hiçbir yerde saklanmaz.
public struct PSNAccountIDFetcher: Sendable {
    public let transport: PSNHTTPTransport

    public init(transport: PSNHTTPTransport = PSNEphemeralTransport()) {
        self.transport = transport
    }

    public func accountID(for redirect: PSNAuth.Redirect) async throws -> Data {
        switch redirect {
        case .empty:
            throw PSNLoginError.incomplete
        case let .error(text):
            throw PSNLoginError.fromRedirectError(text)
        case let .code(code):
            let (tokenBody, tokenStatus) = try await send(PSNAuth.tokenRequest(code: code))
            let token = try PSNAuth.accessToken(status: tokenStatus, body: tokenBody)
            let (infoBody, infoStatus) = try await send(PSNAuth.accountRequest(accessToken: token))
            return try PSNAuth.accountID(status: infoStatus, body: infoBody)
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            return try await transport.send(request)
        } catch let e as PSNLoginError {
            throw e
        } catch {
            throw PSNLoginError.network(detail: error.localizedDescription)
        }
    }
}

// MARK: Gezinme kararları

/// Giriş penceresindeki gömülü tarayıcının kararları; tarayıcıdan bağımsız, saf durum.
public struct PSNLoginFlow: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case allow
        /// Gezinmeyi iptal et; `capture` doluysa pencereyi kapat ve çözümlemeye başla.
        case cancel(capture: PSNAuth.Redirect?)
    }

    public private(set) var captured: PSNAuth.Redirect?
    /// Son sayfa sorunu ("HTTP 503" ya da sistemin hata metni).
    public private(set) var pageProblem: String?

    public init() {}

    /// Her gezinmede adrese bakılır. Yönlendirme yalnız bir kez yakalanır.
    public mutating func decide(url: URL?) -> Decision {
        guard let url, let redirect = PSNAuth.redirect(from: url) else {
            return captured == nil ? .allow : .cancel(capture: nil)
        }
        guard captured == nil else { return .cancel(capture: nil) }
        captured = redirect
        return .cancel(capture: redirect)
    }

    /// Ana çerçevenin HTTP yanıtı: 400 ve üstü sorun, başarı sorunu temizler.
    public mutating func mainFrameResponse(status: Int) {
        if status >= 400 { pageProblem = "HTTP \(status)" } else if (200..<400).contains(status) { pageProblem = nil }
    }

    /// Sayfa yüklenemedi. Bizim iptalimizden doğan hatalar sayılmaz.
    public mutating func loadFailed(domain: String, code: Int, description: String) {
        if domain == NSURLErrorDomain && code == NSURLErrorCancelled { return }
        // WebKit: "çerçeve yüklemesi politika değişikliği yüzünden kesildi".
        if domain == "WebKitErrorDomain" && code == 102 { return }
        pageProblem = description
    }

    /// Pencere kapandı: yakalanan yönlendirme yoksa hangi hata gösterilecek.
    public func closedWithoutRedirect() -> PSNLoginError? {
        captured == nil ? PSNLoginError.windowClosed(pageProblem: pageProblem) : nil
    }
}
