// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Çevirmen hatasının türü. Ana ekran uyarısı buradan çıkar.
public enum ProviderFailure: Error, Equatable, Sendable {
    case invalidKey
    case quotaExhausted
    /// Dakikalık sınır: kullanıcıya gösterilmez, satır cihaz içine düşer.
    case minuteLimit(retryAfter: TimeInterval, limit: Int?)
    case modelRejected
    case network
    case server(Int)
    case badResponse
    /// İstek hiç gönderilmedi (hizmet dinlenmede, dakikalık hak yok, ayar eksik).
    case notReady

    /// Ana ekranda gösterilecek uyarı; `nil` ise sessizce yedeğe düşülür.
    public var alert: ProviderAlert? {
        switch self {
        case .invalidKey: return .invalidKey
        case .quotaExhausted: return .quotaExhausted
        case .modelRejected: return .modelRejected
        case .network: return .network
        case .server, .badResponse: return .server
        case .minuteLimit, .notReady: return nil
        }
    }
}

/// "Şu an çevirmiyor" uyarısının nedeni.
public enum ProviderAlert: String, Equatable, Sendable, CaseIterable {
    case invalidKey, quotaExhausted, network, server, modelRejected
}

public enum ProviderErrorClassifier {
    /// Yapay zekâ hizmetlerinin HTTP durumundan hata türü. Gövde yalnız tanınan
    /// kodlarda okunur, hiçbir yere yazılmaz.
    public static func classify(status: Int, body: Data) -> ProviderFailure? {
        if (200..<300).contains(status) { return nil }
        switch status {
        case 401, 403: return .invalidKey
        case 402: return .quotaExhausted
        case 429: return minuteLimit(body) ?? .quotaExhausted
        case 400:
            let text = String(decoding: body, as: UTF8.self).lowercased()
            if text.contains("api_key_invalid") || text.contains("api key not valid") { return .invalidKey }
            if text.contains("credit balance") || text.contains("insufficient_quota") { return .quotaExhausted }
            return .modelRejected
        case 404: return .modelRejected
        default: return .server(status)
        }
    }

    /// DeepL: 401/403 anahtar, 456 kota, diğer sunucu.
    public static func classifyDeepL(status: Int) -> ProviderFailure? {
        if (200..<300).contains(status) { return nil }
        switch status {
        case 401, 403: return .invalidKey
        case 456: return .quotaExhausted
        default: return .server(status)
        }
    }

    /// Taşıyıcı hatası → `network` (zaten tipliyse olduğu gibi).
    public static func classify(transportError error: Error) -> ProviderFailure {
        if let f = error as? ProviderFailure { return f }
        return .network
    }

    /// 429 gövdesinde `error.details[].violations[].quotaId` içinde `PerMinute` var,
    /// `PerDay` yoksa dakikalık sınırdır.
    static func minuteLimit(_ body: Data) -> ProviderFailure? {
        guard let root = ProviderJSON.object(body) as? [String: Any],
              let error = root["error"] as? [String: Any],
              let details = error["details"] as? [[String: Any]] else { return nil }
        var violations: [[String: Any]] = []
        var delay: TimeInterval?
        for d in details {
            if let v = d["violations"] as? [[String: Any]] { violations += v }
            if let r = d["retryDelay"] as? String { delay = parseDelay(r) }
        }
        let ids = violations.compactMap { $0["quotaId"] as? String }
        guard ids.contains(where: { $0.contains("PerMinute") }), !ids.contains(where: { $0.contains("PerDay") }) else {
            return nil
        }
        var limit: Int?
        for v in violations {
            guard let id = v["quotaId"] as? String, id.contains("Requests") else { continue }
            if let n = v["quotaValue"] as? Int { limit = n } else if let s = v["quotaValue"] as? String, let n = Int(s) { limit = n }
        }
        let wait = min(20, max(1, delay ?? 20))
        return .minuteLimit(retryAfter: wait, limit: limit)
    }

    static func parseDelay(_ s: String) -> TimeInterval? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.hasSuffix("s") else { return TimeInterval(t) }
        return TimeInterval(t.dropLast())
    }
}

/// Hizmetin sağlığı: ilk hatada 60 sn dinlenir, uyarıyı yalnız değişince bildirir.
public actor ProviderHealth {
    public let cooldown: TimeInterval
    private let now: @Sendable () -> Date
    private let onChange: (@Sendable (ProviderAlert?) -> Void)?
    private var restingUntil: Date = .distantPast
    public private(set) var alert: ProviderAlert?

    /// `onChange` uyarı yalnız değişince çağrılır (ana ekran için).
    public init(cooldown: TimeInterval = 60, now: @escaping @Sendable () -> Date = { Date() },
                onChange: (@Sendable (ProviderAlert?) -> Void)? = nil) {
        self.cooldown = cooldown
        self.now = now
        self.onChange = onChange
    }

    public var isResting: Bool { restingUntil > now() }

    /// Hatayı kaydeder. Uyarı değiştiyse yeni uyarıyı döner (`.some(nil)` silindi demektir).
    @discardableResult
    public func record(_ failure: ProviderFailure) -> ProviderAlert?? {
        switch failure {
        case .notReady: return nil
        case let .minuteLimit(wait, _):
            restingUntil = now().addingTimeInterval(wait)
            return nil
        default:
            restingUntil = now().addingTimeInterval(cooldown)
            return setAlert(failure.alert)
        }
    }

    /// Başarılı istek uyarıyı kaldırır.
    @discardableResult
    public func recordSuccess() -> ProviderAlert?? {
        restingUntil = .distantPast
        return setAlert(nil)
    }

    private func setAlert(_ new: ProviderAlert?) -> ProviderAlert?? {
        guard new != alert else { return nil }
        alert = new
        onChange?(new)
        return .some(new)
    }
}
