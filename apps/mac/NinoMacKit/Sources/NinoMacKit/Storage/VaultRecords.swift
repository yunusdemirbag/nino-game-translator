// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Anahtarlıktaki hesap adları (docs/yeni/mac/veri-uyumu.md §2). Eski uygulamayla aynı.
public enum VaultAccount: String, CaseIterable, Sendable {
    case accountID = "accountId"
    case console
    case tv
    case tvKey
    case tvDevKey
    case tvAppVersion
    case loginPasscode
    case setupComplete
    case deepLKey, geminiKey, openAIKey, claudeKey, localAIKey

    /// Çevrimiçi motorun anahtar hesabı.
    public static func key(for engine: MacSettings.OnlineEngine) -> VaultAccount {
        switch engine {
        case .deepl: return .deepLKey
        case .gemini: return .geminiKey
        case .openai: return .openAIKey
        case .claude: return .claudeKey
        case .local: return .localAIKey
        }
    }
}

/// PS5 kaydı (`console`): `{"host", "name", "registKey": base64, "morning": base64}`.
public struct ConsoleRecord: Codable, Equatable, Sendable {
    public var host: String
    public var name: String
    /// 16 bayt: ASCII onaltılık rakamlar, sonu sıfırla dolu.
    public var registKey: Data
    /// 16 baytlık oturum anahtarı.
    public var morning: Data

    public init(host: String, name: String,
                registKey key: Data, morning secret: Data) {
        (self.host, self.name) = (host, name)
        (registKey, morning) = (key, secret)
    }

    /// Uyandırma kimliği: `registKey`'in ilk sıfır bayta kadarki onaltılık metninin sayı değeri.
    public var wakeCredential: UInt64? {
        let text = String(decoding: registKey.prefix { $0 != 0 }, as: UTF8.self)
        guard !text.isEmpty else { return nil }
        return UInt64(text, radix: 16)
    }

    /// PS5 adresi olarak saklanabilir mi? `0.0.0.0` ve yayın adresleri asla saklanmaz.
    public static func isStorableHost(_ host: String) -> Bool {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, h != "0.0.0.0", h != "255.255.255.255" else { return false }
        let parts = h.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }), parts.last == "255" { return false }
        return true
    }
}

/// TV kaydı (`tv`): `{"name", "host", "brand"}`. `brand` yoksa ya da bilinmiyorsa `lg`.
public struct TVRecord: Codable, Equatable, Sendable {
    public var name: String
    public var host: String
    public var brand: PairedTV.Brand

    public init(name: String, host: String, brand: PairedTV.Brand) {
        self.name = name
        self.host = host
        self.brand = brand
    }

    private enum CodingKeys: String, CodingKey { case name, host, brand }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        let raw = (try? c.decodeIfPresent(String.self, forKey: .brand)) ?? nil
        brand = raw.flatMap(PairedTV.Brand.init(rawValue:)) ?? .lg
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(host, forKey: .host)
        try c.encode(brand.rawValue, forKey: .brand)
    }
}

public enum VaultRecordError: Error, Equatable, Sendable {
    case badAccountID(byteCount: Int)
    case unstorableHost(String)
}

/// Kasadaki kayıtların tipli hali ve sıfırlama kuralları.
public struct SecureRecords: Sendable {
    public let vault: Vault

    public init(vault: Vault) { self.vault = vault }

    // MARK: PSN hesabı

    /// 8 baytlık PSN hesap kimliği. Boyu tutmayan kayıt yok sayılır (silinmez).
    public func accountID() throws -> Data? {
        guard let d = try vault.bytes(VaultAccount.accountID.rawValue), d.count == 8 else { return nil }
        return d
    }

    public func setAccountID(_ id: Data) throws {
        guard id.count == 8 else { throw VaultRecordError.badAccountID(byteCount: id.count) }
        try vault.setBytes(id, for: VaultAccount.accountID.rawValue)
    }

    // MARK: PS5

    public func console() throws -> ConsoleRecord? {
        try vault.object(ConsoleRecord.self, VaultAccount.console.rawValue)
    }

    public func setConsole(_ record: ConsoleRecord) throws {
        guard ConsoleRecord.isStorableHost(record.host) else { throw VaultRecordError.unstorableHost(record.host) }
        try vault.setObject(record, for: VaultAccount.console.rawValue)
    }

    // MARK: TV

    public func tv() throws -> TVRecord? {
        try vault.object(TVRecord.self, VaultAccount.tv.rawValue)
    }

    /// TV markası ya da adresi değişince kurulu TV uygulamasının sürümü silinir.
    public func setTV(_ record: TVRecord) throws {
        if let old = try tv(), old.brand != record.brand || old.host != record.host {
            try vault.remove(VaultAccount.tvAppVersion.rawValue)
        }
        try vault.setObject(record, for: VaultAccount.tv.rawValue)
    }

    public func tvKey() throws -> String? { try vault.string(VaultAccount.tvKey.rawValue) }

    /// Boş yeni jeton eskisinin üstüne yazılmaz. Okuma hatasında da yazılmaz (hata yukarı çıkar).
    public func setTVKey(_ key: String) throws {
        if key.isEmpty, try vault.data(for: VaultAccount.tvKey.rawValue) != nil { return }
        try vault.setString(key, for: VaultAccount.tvKey.rawValue)
    }

    public func tvDevKey() throws -> String? { try vault.string(VaultAccount.tvDevKey.rawValue) }
    public func setTVDevKey(_ key: String) throws { try vault.setString(key, for: VaultAccount.tvDevKey.rawValue) }

    public func tvAppVersion() throws -> String? { try vault.string(VaultAccount.tvAppVersion.rawValue) }
    public func setTVAppVersion(_ version: String) throws {
        try vault.setString(version, for: VaultAccount.tvAppVersion.rawValue)
    }

    // MARK: Giriş şifresi, kurulum

    public func loginPasscode() throws -> String? { try vault.string(VaultAccount.loginPasscode.rawValue) }
    public func setLoginPasscode(_ code: String?) throws {
        if let code, !code.isEmpty {
            try vault.setString(code, for: VaultAccount.loginPasscode.rawValue)
        } else {
            try vault.remove(VaultAccount.loginPasscode.rawValue)
        }
    }

    public func setupComplete() throws -> Bool { try vault.bool(VaultAccount.setupComplete.rawValue) ?? false }
    public func setSetupComplete(_ done: Bool) throws {
        try vault.setBool(done, for: VaultAccount.setupComplete.rawValue)
    }

    // MARK: Çeviri anahtarları

    /// Kırpılmış anahtar; boşsa nil.
    public func translationKey(_ engine: MacSettings.OnlineEngine) throws -> String? {
        guard let raw = try vault.string(VaultAccount.key(for: engine).rawValue) else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    /// Kırpılarak yazılır; boş ya da nil anahtar kaydı siler.
    public func setTranslationKey(_ key: String?, for engine: MacSettings.OnlineEngine) throws {
        let account = VaultAccount.key(for: engine).rawValue
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { try vault.remove(account) } else { try vault.setString(trimmed, for: account) }
    }

    // MARK: Sıfırlama

    /// "Her şeyi sıfırla": çeviri anahtarları kalır.
    public func resetEverything() throws {
        for a: VaultAccount in [.accountID, .console, .tv, .tvKey, .tvDevKey, .tvAppVersion, .setupComplete, .loginPasscode] {
            try vault.remove(a.rawValue)
        }
    }

    /// "TV'yi değiştir".
    public func changeTV() throws {
        for a: VaultAccount in [.tv, .tvKey, .tvDevKey, .tvAppVersion, .setupComplete] {
            try vault.remove(a.rawValue)
        }
    }

    /// PSN'den çıkış: yalnız hesap kimliği.
    public func signOutPSN() throws {
        try vault.remove(VaultAccount.accountID.rawValue)
    }

    // MARK: Ekranlar için

    /// AppState'in eşleşmiş TV'si. Android TV'de anahtar her zaman var sayılır.
    public func pairedTV() throws -> PairedTV? {
        guard let tv = try tv() else { return nil }
        let key = try tvKey() ?? ""
        let hasKey = tv.brand == .androidTV || !key.isEmpty
        return PairedTV(name: tv.name, host: tv.host, brand: tv.brand, hasKey: hasKey)
    }

    public func pairedConsole() throws -> PairedConsole? {
        guard let c = try console() else { return nil }
        return PairedConsole(name: c.name, host: c.host)
    }
}
