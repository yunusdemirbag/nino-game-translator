// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore
import NinoRemotePlay

/// NinoCore'un `SecretStore`'unu Mac kasası üzerinden karşılar.
///
/// NinoCore çevirmen anahtarını `provider.<ad>.key` diye sorar; burada `<ad>` büyük/küçük
/// harf gözetmeden `MacSettings.OnlineEngine` adlarıyla eşlenir ve değer eski hesaptan
/// (`deepLKey`, `geminiKey`…) düz dizge olarak döner. Başka hesaplar (ör. `remoteplay.<kimlik>`)
/// bilerek desteklenmez: okumada nil, yazmada hata. Böylece Mac hizmetinde "her şeyi
/// sıfırla"nın silmediği ikinci bir PS5 kaydı oluşmaz; PS5 kaydı `console` hesabındadır.
public struct LegacySecretStore: SecretStore {
    public struct UnsupportedAccount: Error, Equatable { public let account: String }

    public let records: SecureRecords

    public init(vault: Vault) { records = SecureRecords(vault: vault) }

    /// `provider.<ad>.key` → motor.
    public static func engine(forAccount account: String) -> MacSettings.OnlineEngine? {
        let prefix = "provider.", suffix = ".key"
        guard account.hasPrefix(prefix), account.hasSuffix(suffix),
              account.count > prefix.count + suffix.count else { return nil }
        let name = account.dropFirst(prefix.count).dropLast(suffix.count).lowercased()
        return MacSettings.OnlineEngine.allCases.first { $0.rawValue == name }
    }

    public func get(_ account: String) throws -> String? {
        guard let engine = Self.engine(forAccount: account) else { return nil }
        return try records.translationKey(engine)
    }

    public func set(_ value: String, for account: String) throws {
        guard let engine = Self.engine(forAccount: account) else { throw UnsupportedAccount(account: account) }
        try records.setTranslationKey(value, for: engine)
    }

    public func delete(_ account: String) throws {
        guard let engine = Self.engine(forAccount: account) else { return }
        try records.setTranslationKey(nil, for: engine)
    }
}

public extension ConsoleRecord {
    /// Kütüphanenin PS5 hedefi (`CHIAKI_TARGET_PS5_1`). Keşif cevabı varsa onun `target`'ı kullanılmalı.
    static let defaultPS5Target: Int32 = 1_000_100

    /// Eski kaydı NinoRemotePlay'in biçimine çevirir. Eski kayıtta olmayan ana bilgisayar kimliği
    /// ve MAC adresi ağdaki keşiften gelir.
    func registeredConsole(hostID: String, serverMAC: [UInt8], target: Int32 = defaultPS5Target) -> RegisteredConsole {
        RegisteredConsole(hostID: hostID, nickname: name, isPS5: true, target: target,
                          registKey: Array(registKey), rpKey: Array(morning), serverMAC: serverMAC)
    }

    /// Keşiften gelen konsolla tamamlar.
    func registeredConsole(discovered info: ConsoleInfo, serverMAC: [UInt8]) -> RegisteredConsole {
        registeredConsole(hostID: info.hostID, serverMAC: serverMAC, target: info.target)
    }

    /// Yeni eşleşmeden eski biçimli kayıt (adres ayrıca saklanır; yeni kayıtta yok).
    init(_ console: RegisteredConsole, host: String) {
        self.init(host: host, name: console.nickname, registKey: Data(console.registKey), morning: Data(console.rpKey))
    }
}
