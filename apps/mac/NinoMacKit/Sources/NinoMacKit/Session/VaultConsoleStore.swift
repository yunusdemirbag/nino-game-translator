// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// PS5 tarafının kasası, Anahtarlık kayıtları üzerinden (`console`, `accountId`, `loginPasscode`).
public struct VaultConsoleStore: ConsoleRecordStore {
    public let records: SecureRecords

    public init(records: SecureRecords) { self.records = records }
    public init(vault: Vault) { records = SecureRecords(vault: vault) }

    public func loadPairing() throws -> PS5Pairing? {
        guard let c = try records.console() else { return nil }
        return PS5Pairing(host: c.host, name: c.name, registKey: c.registKey, morning: c.morning)
    }

    public func savePairing(_ pairing: PS5Pairing) throws {
        try records.setConsole(ConsoleRecord(host: pairing.host, name: pairing.name,
                                             registKey: pairing.registKey, morning: pairing.morning))
    }

    public func loadAccountID() throws -> Data? { try records.accountID() }
    public func saveAccountID(_ id: Data) throws { try records.setAccountID(id) }
    public func deleteAccountID() throws { try records.signOutPSN() }
    public func loadLoginPasscode() throws -> String? { try records.loginPasscode() }
}
