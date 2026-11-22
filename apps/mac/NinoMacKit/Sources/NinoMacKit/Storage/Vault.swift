// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Security

/// Gizli kayıtların deposu (docs/yeni/mac/veri-uyumu.md §2).
///
/// Ham katman: her hesap bir bayt dizisi tutar. Eski uygulamayla uyum için değerler
/// JSON kodlu yazılır (bkz. `Vault` uzantısı): dizge tırnaklı, Bool çıplak, Data
/// tırnaklı base64, nesne JSON.
public protocol Vault: Sendable {
    /// Kayıt yoksa nil. Okunamazsa (izin, kilit…) hata fırlatır; "yok" ile karışmaz.
    func data(for account: String) throws -> Data?
    func setData(_ data: Data, for account: String) throws
    /// Kayıt yoksa sessizce geçer.
    func remove(_ account: String) throws
}

public struct VaultError: Error, Equatable, Sendable {
    public let status: Int32
    public init(status: Int32) { self.status = status }
}

// MARK: - Eski biçimde JSON kodlama

enum VaultCoding {
    /// Eski uygulamanın kodlayıcısıyla aynı ayar: Foundation varsayılanı (Data → base64,
    /// `/` kaçışlı `\/`). Okurken iki yazım da kabul edilir.
    static func encoder() -> JSONEncoder { JSONEncoder() }
    static func decoder() -> JSONDecoder { JSONDecoder() }
}

public extension Vault {
    func string(_ account: String) throws -> String? {
        guard let raw = try data(for: account) else { return nil }
        return try? VaultCoding.decoder().decode(String.self, from: raw)
    }

    func setString(_ value: String, for account: String) throws {
        try setData(VaultCoding.encoder().encode(value), for: account)
    }

    func bool(_ account: String) throws -> Bool? {
        guard let raw = try data(for: account) else { return nil }
        return try? VaultCoding.decoder().decode(Bool.self, from: raw)
    }

    func setBool(_ value: Bool, for account: String) throws {
        try setData(VaultCoding.encoder().encode(value), for: account)
    }

    func bytes(_ account: String) throws -> Data? {
        guard let raw = try data(for: account) else { return nil }
        return try? VaultCoding.decoder().decode(Data.self, from: raw)
    }

    func setBytes(_ value: Data, for account: String) throws {
        try setData(VaultCoding.encoder().encode(value), for: account)
    }

    func object<T: Decodable>(_ type: T.Type, _ account: String) throws -> T? {
        guard let raw = try data(for: account) else { return nil }
        return try? VaultCoding.decoder().decode(T.self, from: raw)
    }

    func setObject<T: Encodable>(_ value: T, for account: String) throws {
        try setData(VaultCoding.encoder().encode(value), for: account)
    }
}

// MARK: - Bellek kasası (testler, önizleme)

public final class MemoryVault: Vault, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data]
    /// Verilirse her okuma bu hatayla düşer (okuma hatası denemeleri için).
    public var readFailure: VaultError?

    public init(_ values: [String: Data] = [:]) { self.values = values }

    public func data(for account: String) throws -> Data? {
        try lock.withLock {
            if let readFailure { throw readFailure }
            return values[account]
        }
    }

    public func setData(_ data: Data, for account: String) throws { lock.withLock { values[account] = data } }
    public func remove(_ account: String) throws { lock.withLock { values[account] = nil } }

    /// Saklı hesap adları (testler için).
    public var accounts: Set<String> { lock.withLock { Set(values.keys) } }
}

// MARK: - Anahtarlık kasası

/// Genel parola (generic password) kayıtları. Eski uygulamayla aynı yazma kuralı:
/// önce aynı hesap silinir, sonra eklenir; erişim özelliği ve eşitleme bayrağı verilmez.
public struct KeychainVault: Vault {
    public let service: String

    /// Hizmet adı bilerek varsayılansız: yanlışlıkla yayın kaydına yazılmasın.
    public init(service: String) { self.service = service }

    public init(identity: AppIdentity) { self.init(service: identity.keychainService) }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func data(for account: String) throws -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw VaultError(status: status) }
        return data
    }

    public func setData(_ data: Data, for account: String) throws {
        try remove(account)
        var add = query(account)
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError(status: status) }
    }

    public func remove(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError(status: status) }
    }
}
