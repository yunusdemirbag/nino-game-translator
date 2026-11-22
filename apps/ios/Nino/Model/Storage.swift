// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Security

/// Anahtar Zinciri'ndeki ve UserDefaults'taki kayıtların adları. Önceki sürümle aynıdır; değiştirilmez.
enum Keys {
    // Anahtar Zinciri
    static let accountID = "accountId"
    static let console = "console"
    static let tv = "tv"
    static let tvKey = "tvKey"
    static let setupComplete = "setupComplete"
    static let loginPasscode = "loginPasscode"
    static let deepLKey = "deepLKey"
    static let geminiKey = "geminiKey"
    static let openAIKey = "openAIKey"
    static let claudeKey = "claudeKey"
    static let localAIKey = "localAIKey"
    static let xboxUserToken = "xboxUserToken"
    static let xboxConsole = "xboxConsole"

    // UserDefaults
    static let settings = "settings"
    static let welcomeSeen = "welcomeSeen"
    static let platform = "platform"
    static let setupSkipped = "setupSkipped"
    static let disabledPacks = "disabledPacks"
    static let notifyDisconnect = "notifyDisconnect"
    static let notifyPackUpdates = "notifyPackUpdates"
    static let coachTourDone = "coachTourDone"
    static let lastSessionSeconds = "lastSessionSeconds"
    static let lastGamePoolFirst = "ninoLastGamePoolFirst"
    static let lastGames = "lastGames"
    static let tvAppInstalled = "tvAppInstalled"
    static let downloadTotal = "ninoDownloadTotal"
}

/// Değerleri JSON olarak saklayan güvenli depo.
protocol SecureStore: AnyObject {
    func data(for account: String) -> Data?
    func setData(_ data: Data, for account: String)
    func remove(_ account: String)
}

extension SecureStore {
    func load<T: Decodable>(_ type: T.Type, for account: String) -> T? {
        guard let data = data(for: account) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func save<T: Encodable>(_ value: T, for account: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        setData(data, for: account)
    }
}

/// Anahtar Zinciri: hizmet `com.ninotranslator.ios`; eski hizmetteki kayıt okunduğu anda yeni hizmete taşınır.
final class KeychainStore: SecureStore {
    let service: String
    let legacyService: String?

    init(service: String = "com.ninotranslator.ios", legacyService: String? = LegacyNames.keychainService) {
        self.service = service
        self.legacyService = legacyService
    }

    private func query(_ service: String, _ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    private func read(_ service: String, _ account: String) -> Data? {
        var q = query(service, account)
        q[kSecReturnData] = true
        q[kSecMatchLimit] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    @discardableResult
    private func write(_ data: Data, _ service: String, _ account: String) -> Bool {
        let q = query(service, account)
        SecItemDelete(q as CFDictionary)
        var item = q
        item[kSecValueData] = data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func data(for account: String) -> Data? {
        if let data = read(service, account) { return data }
        guard let legacyService, let old = read(legacyService, account) else { return nil }
        if write(old, service, account) {
            SecItemDelete(query(legacyService, account) as CFDictionary)
        }
        return old
    }

    func setData(_ data: Data, for account: String) { write(data, service, account) }

    func remove(_ account: String) { SecItemDelete(query(service, account) as CFDictionary) }
}

/// Bellekte duran depo (testler, PS5'siz deneme).
final class MemoryStore: SecureStore {
    private var values: [String: Data] = [:]
    init(_ values: [String: Data] = [:]) { self.values = values }
    func data(for account: String) -> Data? { values[account] }
    func setData(_ data: Data, for account: String) { values[account] = data }
    func remove(_ account: String) { values[account] = nil }
}

// MARK: Kayıtlı tipler

/// Eşlenen PS5 (önceki sürümle aynı JSON: host, name, registKey, morning).
struct PairedConsole: Codable, Equatable {
    var host: String
    var name: String
    /// 16 bayt: ASCII onaltılık metin, sonu sıfırla doldurulmuş.
    var registKey: Data
    /// 16 bayt oturum anahtarı.
    var morning: Data
}

/// Altyazının gideceği TV (önceki sürümle aynı JSON: name, host, brand).
struct PairedTV: Codable, Equatable, Hashable {
    enum Brand: String, Codable, CaseIterable { case lg, samsung, androidTV }
    var name: String
    var host: String
    var brand: Brand = .lg

    init(name: String, host: String, brand: Brand = .lg) {
        self.name = name
        self.host = host
        self.brand = brand
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        host = try c.decode(String.self, forKey: .host)
        brand = try c.decodeIfPresent(Brand.self, forKey: .brand) ?? .lg
    }

    var brandName: String {
        switch brand {
        case .lg: "LG"
        case .samsung: "Samsung"
        case .androidTV: "Android TV"
        }
    }
}

/// Seçilen Xbox (önceki sürümle aynı JSON).
struct XboxConsole: Codable, Equatable {
    var id: String
    var name: String
    var model: String
    var streamingEnabled: Bool
    var powerState: String
}

/// Telefonun TV uygulamasını kurduğu ya da sürümünü okuduğu son TV.
struct InstalledTVApp: Codable, Equatable {
    var brand: PairedTV.Brand
    var host: String
    var port: UInt16?
    var version: String
}

/// Konsol türü (UserDefaults `platform`).
enum ConsoleKind: String {
    case playstation, xbox
}
