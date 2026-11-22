// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// Xbox (Beta) için hizmet yanıtlarının okunması ve saklanan jetonun biçimi. Biçim: docs/yeni/ios/kalicilik.md §3.3–3.4.

/// Xbox tarafında bir şeyin neden olmadığı; ekrandaki metin buna göre seçilir.
enum XboxProblem: String, Sendable, Equatable {
    /// Microsoft girişi yok, süresi doldu ya da Xbox Live kabul etmedi.
    case needsSignIn
    case codeExpired
    case declined
    /// Microsoft hesabının Xbox profili yok (ya da ülke/yaş kısıtı).
    case noProfile
    /// Xbox kapalı, uzaktan oynatma kapalı ya da yayın açılmadı.
    case unreachable
    /// Xbox başka bir uzaktan oynatma oturumunda.
    case busy
    case timeout
    /// İnternete ulaşılamadı.
    case offline
    /// Xbox yayını başlatamadı (`StartStreamingSession` hatası): çoğu zaman Xbox'ın yeniden başlatılması gerekir.
    case startFailed
    /// Beklenmeyen yanıt.
    case unexpected

    /// Yeniden denemenin anlamı olmayanlar.
    var needsUser: Bool { self == .needsSignIn || self == .noProfile || self == .declined }
}

struct XboxFailure: Error, Equatable {
    let problem: XboxProblem
    /// Günlük ve "beklenmeyen yanıt" metni için kısa teknik ayrıntı.
    let detail: String

    init(_ problem: XboxProblem, _ detail: String = "") {
        self.problem = problem
        self.detail = detail
    }
}

/// Microsoft ve Xbox yanıtları için küçük JSON yardımcıları (alanları bilinmeyenler olduğu gibi korunur).
enum XboxJSON {
    typealias Object = [String: Any]

    static func object(_ data: Data) throws -> Object {
        if data.isEmpty { return [:] }
        guard let value = try? JSONSerialization.jsonObject(with: data), let object = value as? Object else {
            throw XboxFailure(.unexpected, "JSON okunamadı")
        }
        return object
    }

    static func object(_ text: String) throws -> Object { try object(Data(text.utf8)) }

    /// Eğik çizgileri kaçışsız, anahtarları sıralı metin.
    static func text(_ value: Any) -> String {
        let options: JSONSerialization.WritingOptions = [.withoutEscapingSlashes, .sortedKeys]
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: options) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func string(_ object: Object, _ key: String) -> String {
        object[key] as? String ?? ""
    }

    static func number(_ object: Object, _ key: String) -> Double? {
        (object[key] as? NSNumber)?.doubleValue ?? Double(object[key] as? String ?? "")
    }
}

/// Microsoft'un tarih biçimleri: `2026-11-22T15:03:05.123Z`, kesir 0–7 hane, saat dilimi `Z` ya da `+hh:mm`.
enum XboxTime {
    static func parse(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        // Kesir ayrı okunur: sistem çözümleyicisi her hane sayısını kabul etmiyor.
        var whole = text
        var fraction: Double = 0
        if let dot = text.firstIndex(of: ".") {
            let rest = text[text.index(after: dot)...]
            let digits = rest.prefix(while: \.isNumber)
            fraction = Double("0." + digits) ?? 0
            whole = String(text[..<dot]) + String(rest.dropFirst(digits.count))
        }
        let reader = ISO8601DateFormatter()
        reader.formatOptions = [.withInternetDateTime]
        return reader.date(from: whole)?.addingTimeInterval(fraction)
    }

    static func format(_ date: Date) -> String {
        let writer = ISO8601DateFormatter()
        writer.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return writer.string(from: date)
    }
}

/// Saklanan tek Xbox jetonu: Microsoft'un kullanıcı jetonu yanıtı + `expires_on`. Alanların hepsi korunur.
struct MicrosoftToken: @unchecked Sendable {
    let fields: XboxJSON.Object

    var accessToken: String { XboxJSON.string(fields, "access_token") }
    var refreshToken: String { XboxJSON.string(fields, "refresh_token") }
    var expiresOn: Date { XboxTime.parse(fields["expires_on"] as? String) ?? .distantPast }

    /// Süresi en az `margin` saniye sonra mı doluyor.
    func fresh(at now: Date, margin: TimeInterval) -> Bool { expiresOn.timeIntervalSince(now) > margin }

    /// Anahtar Zinciri'ne yazılan iç metin.
    var stored: String { XboxJSON.text(fields) }

    /// Saklanan metinden. Okunamıyorsa ya da yenileme jetonu yoksa giriş yok sayılır.
    init?(stored text: String?) {
        guard let text, let object = try? XboxJSON.object(text) else { return nil }
        fields = object
        if refreshToken.isEmpty { return nil }
    }

    /// Microsoft'un jeton yanıtından. Yanıtta yenileme jetonu yoksa eldeki korunur.
    init(response: XboxJSON.Object, receivedAt now: Date, keeping previous: MicrosoftToken? = nil) throws {
        guard !XboxJSON.string(response, "access_token").isEmpty else {
            throw XboxFailure(.unexpected, "jeton yanıtında access_token yok")
        }
        var copy = response
        if XboxJSON.string(response, "refresh_token").isEmpty, let old = previous?.refreshToken, !old.isEmpty {
            copy["refresh_token"] = old
        }
        let lifetime = XboxJSON.number(response, "expires_in") ?? 0
        copy["expires_on"] = XboxTime.format(now.addingTimeInterval(lifetime))
        fields = copy
    }
}

/// Xbox Live'dan gelen jeton: kullanıcıya ait olan ya da XSTS.
struct XboxLiveToken: Equatable, Sendable {
    let token: String
    let userHash: String
    let notAfter: Date

    init(token: String, userHash: String, notAfter: Date) {
        self.token = token
        self.userHash = userHash
        self.notAfter = notAfter
    }

    init(response: XboxJSON.Object) throws {
        let token = XboxJSON.string(response, "Token")
        guard !token.isEmpty else { throw XboxFailure(.unexpected, "Xbox Live yanıtında Token yok") }
        let claims = (response["DisplayClaims"] as? XboxJSON.Object)?["xui"] as? [XboxJSON.Object]
        self.init(token: token, userHash: claims?.first.map { XboxJSON.string($0, "uhs") } ?? "",
                  notAfter: XboxTime.parse(response["NotAfter"] as? String) ?? .distantPast)
    }

    var authorization: String { "XBL3.0 x=\(userHash);\(token)" }
}

/// Ev yayını hizmetinin adresi ve jetonu.
struct StreamingLogin: Equatable, Sendable {
    let baseURL: String
    let token: String
    let expires: Date

    init(response: XboxJSON.Object, receivedAt now: Date) throws {
        let regions = (response["offeringSettings"] as? XboxJSON.Object)?["regions"] as? [XboxJSON.Object] ?? []
        let region = regions.first { $0["isDefault"] as? Bool == true } ?? regions.first
        let base = (region.map { XboxJSON.string($0, "baseUri") } ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty else { throw XboxFailure(.unexpected, "ev yayını bölgesi yok") }
        let token = XboxJSON.string(response, "gsToken")
        guard !token.isEmpty else { throw XboxFailure(.unexpected, "ev yayını jetonu yok") }
        let seconds = XboxJSON.number(response, "durationInSeconds") ?? 0
        baseURL = base
        self.token = token
        expires = now.addingTimeInterval(seconds > 0 ? seconds : 1800)
    }
}

/// Microsoft cihaz kodu girişi: kullanıcıya gösterilen kod ve yoklama bilgisi.
struct DeviceCodeChallenge: Equatable, Sendable {
    let userCode: String
    let deviceCode: String
    let verificationURL: String
    let lifetime: Int
    let interval: Int

    init(userCode: String, deviceCode: String, verificationURL: String, lifetime: Int, interval: Int) {
        self.userCode = userCode
        self.deviceCode = deviceCode
        self.verificationURL = verificationURL
        self.lifetime = lifetime
        self.interval = interval
    }

    init(response: XboxJSON.Object) throws {
        let user = XboxJSON.string(response, "user_code")
        let device = XboxJSON.string(response, "device_code")
        guard !user.isEmpty, !device.isEmpty else { throw XboxFailure(.unexpected, "cihaz kodu gelmedi") }
        let url = XboxJSON.string(response, "verification_uri")
        self.init(userCode: user, deviceCode: device,
                  verificationURL: url.isEmpty ? "https://www.microsoft.com/link" : url,
                  lifetime: Int(XboxJSON.number(response, "expires_in") ?? 900),
                  interval: max(1, Int(XboxJSON.number(response, "interval") ?? 5)))
    }

    /// Ekranda gösterilen adres ("https://" olmadan).
    var displayURL: String {
        verificationURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
    }
}

/// Kod onaylanmadan gelen jeton yanıtının anlamı (RFC 8628 hata adları).
enum DeviceCodeWait: Equatable {
    case keepWaiting, slowDown, expired, declined, failed

    init(status: Int, body: Data) {
        switch XboxJSON.string((try? XboxJSON.object(body)) ?? [:], "error") {
        case "authorization_pending": self = .keepWaiting
        case "slow_down": self = .slowDown
        case "expired_token", "code_expired": self = .expired
        case "authorization_declined", "access_denied": self = .declined
        default: self = status >= 500 ? .keepWaiting : .failed
        }
    }
}

extension XboxConsole {
    /// Hesaptaki Xbox listesi. Yayın için hem ev yayını hem uzaktan yönetim açık olmalı.
    static func list(from response: XboxJSON.Object) -> [XboxConsole] {
        let items = response["result"] as? [XboxJSON.Object] ?? []
        return items.compactMap { item in
            let id = XboxJSON.string(item, "id")
            guard !id.isEmpty else { return nil }
            let streaming = item["consoleStreamingEnabled"] as? Bool == true
            let managed = item["remoteManagementEnabled"] as? Bool == true
            return XboxConsole(id: id, name: XboxJSON.string(item, "name"), model: XboxJSON.string(item, "consoleType"),
                               streamingEnabled: streaming && managed, powerState: XboxJSON.string(item, "powerState"))
        }
    }

    /// Ekranda gösterilen ad (boşsa model).
    var displayName: String { name.isEmpty ? (model.isEmpty ? "Xbox" : model) : name }
}
