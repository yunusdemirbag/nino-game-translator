// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import NinoRemotePlay
import XCTest
@testable import NinoMacKit

final class StorageVaultTests: XCTestCase {
    private func raw(_ s: String) -> Data { Data(s.utf8) }

    // MARK: Eski biçim

    func testWritesLegacyByteFormat() throws {
        let v = MemoryVault()
        try v.setString("abc", for: "s")
        try v.setBool(true, for: "b")
        try v.setBytes(Data([0, 1, 2, 3, 4, 5, 6, 7]), for: "d")
        XCTAssertEqual(try v.data(for: "s"), raw("\"abc\""))
        XCTAssertEqual(try v.data(for: "b"), raw("true"))
        XCTAssertEqual(try v.data(for: "d"), raw("\"AAECAwQFBgc=\""))
    }

    func testReadsBothSlashSpellings() throws {
        // base64 içinde "/" geçen değer: kaçışlı ve kaçışsız yazım aynı okunur.
        let bytes = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertEqual(bytes.base64EncodedString(), "//////////8=")
        let escaped = MemoryVault(["accountId": raw("\"\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/8=\"")])
        let plain = MemoryVault(["accountId": raw("\"//////////8=\"")])
        XCTAssertEqual(try SecureRecords(vault: escaped).accountID(), bytes)
        XCTAssertEqual(try SecureRecords(vault: plain).accountID(), bytes)
    }

    func testReadsLegacyConsoleAndTV() throws {
        let regist = Data("1a2b3c4d".utf8) + Data(repeating: 0, count: 8)
        let morning = Data((0..<16).map { UInt8($0) })
        let consoleJSON = "{\"name\":\"PS5-123\",\"morning\":\"\(morning.base64EncodedString())\",\"host\":\"192.168.0.20\",\"registKey\":\"\(regist.base64EncodedString())\"}"
        let v = MemoryVault([
            "console": raw(consoleJSON),
            "tv": raw("{\"name\":\"Salon\",\"host\":\"192.168.0.110\"}"),
            "setupComplete": raw("true"),
            "tvKey": raw("\"k1\""),
        ])
        let r = SecureRecords(vault: v)
        let c = try XCTUnwrap(r.console())
        XCTAssertEqual(c.host, "192.168.0.20")
        XCTAssertEqual(c.name, "PS5-123")
        XCTAssertEqual(c.registKey, regist)
        XCTAssertEqual(c.morning, morning)
        XCTAssertEqual(c.wakeCredential, 0x1a2b3c4d)
        // brand yoksa lg
        XCTAssertEqual(try r.tv(), TVRecord(name: "Salon", host: "192.168.0.110", brand: .lg))
        XCTAssertTrue(try r.setupComplete())
        XCTAssertEqual(try r.pairedTV(), PairedTV(name: "Salon", host: "192.168.0.110", brand: .lg, hasKey: true))
        XCTAssertEqual(try r.pairedConsole(), PairedConsole(name: "PS5-123", host: "192.168.0.20"))
    }

    func testConsoleRoundTripAndHostRule() throws {
        let r = SecureRecords(vault: MemoryVault())
        let rec = ConsoleRecord(host: "10.0.0.5", name: "PS5", registKey: Data(repeating: 0x31, count: 16),
                                morning: Data(repeating: 7, count: 16))
        try r.setConsole(rec)
        XCTAssertEqual(try r.console(), rec)
        for bad in ["0.0.0.0", "255.255.255.255", "192.168.0.255", ""] {
            var b = rec
            b.host = bad
            XCTAssertThrowsError(try r.setConsole(b), bad)
        }
        XCTAssertEqual(try r.console(), rec)
    }

    func testUnknownBrandFallsBackToLG() throws {
        let r = SecureRecords(vault: MemoryVault(["tv": raw("{\"name\":\"a\",\"host\":\"b\",\"brand\":\"sony\"}")]))
        XCTAssertEqual(try r.tv()?.brand, .lg)
        let s = SecureRecords(vault: MemoryVault(["tv": raw("{\"name\":\"a\",\"host\":\"b\",\"brand\":\"androidTV\"}")]))
        XCTAssertEqual(try s.tv()?.brand, .androidTV)
    }

    func testCorruptValuesReadAsMissing() throws {
        let v = MemoryVault(["console": raw("not json"), "accountId": raw("\"AAEC\""), "setupComplete": raw("\"x\"")])
        let r = SecureRecords(vault: v)
        XCTAssertNil(try r.console())
        XCTAssertNil(try r.accountID()) // 3 bayt: 8 değil
        XCTAssertFalse(try r.setupComplete())
        XCTAssertNotNil(try v.data(for: "console"), "bozuk kayıt silinmez")
    }

    func testAccountIDMustBeEightBytes() throws {
        let r = SecureRecords(vault: MemoryVault())
        XCTAssertThrowsError(try r.setAccountID(Data([1, 2, 3])))
        try r.setAccountID(Data(repeating: 9, count: 8))
        XCTAssertEqual(try r.accountID(), Data(repeating: 9, count: 8))
    }

    // MARK: TV kuralları

    func testEmptyTVKeyDoesNotOverwrite() throws {
        let v = MemoryVault()
        let r = SecureRecords(vault: v)
        try r.setTVKey("")
        XCTAssertEqual(try r.tvKey(), "")
        try r.setTVKey("secret")
        try r.setTVKey("")
        XCTAssertEqual(try r.tvKey(), "secret")
        try r.setTVKey("new")
        XCTAssertEqual(try r.tvKey(), "new")
    }

    func testEmptyTVKeyNotWrittenWhenReadFails() throws {
        let v = MemoryVault(["tvKey": raw("\"old\"")])
        v.readFailure = VaultError(status: -25308)
        XCTAssertThrowsError(try SecureRecords(vault: v).setTVKey(""))
        v.readFailure = nil
        XCTAssertEqual(try SecureRecords(vault: v).tvKey(), "old")
    }

    func testTVAppVersionClearedWhenBrandOrHostChanges() throws {
        let r = SecureRecords(vault: MemoryVault())
        try r.setTV(TVRecord(name: "a", host: "1.1.1.1", brand: .samsung))
        try r.setTVAppVersion("1.0")
        try r.setTV(TVRecord(name: "renamed", host: "1.1.1.1", brand: .samsung))
        XCTAssertEqual(try r.tvAppVersion(), "1.0")
        try r.setTV(TVRecord(name: "a", host: "1.1.1.2", brand: .samsung))
        XCTAssertNil(try r.tvAppVersion())
        try r.setTVAppVersion("2.0")
        try r.setTV(TVRecord(name: "a", host: "1.1.1.2", brand: .androidTV))
        XCTAssertNil(try r.tvAppVersion())
    }

    // MARK: Çeviri anahtarları

    func testTranslationKeysTrimmedAndDeletedWhenEmpty() throws {
        let v = MemoryVault()
        let r = SecureRecords(vault: v)
        try r.setTranslationKey("  abc \n", for: .deepl)
        XCTAssertEqual(try v.data(for: "deepLKey"), raw("\"abc\""))
        XCTAssertEqual(try r.translationKey(.deepl), "abc")
        try r.setTranslationKey("   ", for: .deepl)
        XCTAssertNil(try v.data(for: "deepLKey"))
        XCTAssertEqual(VaultAccount.key(for: .local).rawValue, "localAIKey")
        XCTAssertEqual(VaultAccount.key(for: .openai).rawValue, "openAIKey")
    }

    // MARK: Sıfırlama

    private func fullVault() throws -> MemoryVault {
        let v = MemoryVault()
        for a in VaultAccount.allCases { try v.setString("x", for: a.rawValue) }
        return v
    }

    func testResetEverythingKeepsTranslationKeys() throws {
        let v = try fullVault()
        try SecureRecords(vault: v).resetEverything()
        XCTAssertEqual(v.accounts, ["deepLKey", "geminiKey", "openAIKey", "claudeKey", "localAIKey"])
    }

    func testChangeTV() throws {
        let v = try fullVault()
        try SecureRecords(vault: v).changeTV()
        XCTAssertEqual(v.accounts, ["accountId", "console", "loginPasscode",
                                    "deepLKey", "geminiKey", "openAIKey", "claudeKey", "localAIKey"])
    }

    func testSignOutPSN() throws {
        let v = try fullVault()
        try SecureRecords(vault: v).signOutPSN()
        XCTAssertEqual(v.accounts, Set(VaultAccount.allCases.map(\.rawValue)).subtracting(["accountId"]))
    }

    // MARK: NinoCore köprüsü

    func testSecretStoreAdapterMapsProviderAccounts() throws {
        let v = MemoryVault(["geminiKey": raw("\" g-key \"")])
        let store = LegacySecretStore(vault: v)
        XCTAssertEqual(try store.get("provider.gemini.key"), "g-key")
        XCTAssertEqual(try store.get("provider.Gemini.key"), "g-key")
        XCTAssertNil(try store.get("provider.deepl.key"))
        try store.set("d", for: "provider.DeepL.key")
        XCTAssertEqual(try v.data(for: "deepLKey"), raw("\"d\""))
        try store.delete("provider.deepl.key")
        XCTAssertNil(try v.data(for: "deepLKey"))
        // Başka hesaplar Mac kasasına yazılmaz.
        XCTAssertNil(try store.get("remoteplay.ABC"))
        XCTAssertThrowsError(try store.set("x", for: "remoteplay.ABC"))
        XCTAssertEqual(v.accounts, ["geminiKey"])
        XCTAssertNil(LegacySecretStore.engine(forAccount: "provider..key"))
        XCTAssertEqual(LegacySecretStore.engine(forAccount: "provider.local.key"), .local)
    }

    func testConsoleConvertsToRegisteredConsole() throws {
        let rec = ConsoleRecord(host: "10.0.0.5", name: "PS5-9", registKey: Data(repeating: 0x41, count: 16),
                                morning: Data((0..<16).map { UInt8($0) }))
        let mac: [UInt8] = [1, 2, 3, 4, 5, 6]
        let rc = rec.registeredConsole(hostID: "HOSTID", serverMAC: mac)
        XCTAssertEqual(rc.hostID, "HOSTID")
        XCTAssertEqual(rc.nickname, "PS5-9")
        XCTAssertTrue(rc.isPS5)
        XCTAssertEqual(rc.target, ConsoleRecord.defaultPS5Target)
        XCTAssertEqual(rc.registKey, Array(rec.registKey))
        XCTAssertEqual(rc.rpKey, Array(rec.morning))
        XCTAssertEqual(rc.serverMAC, mac)
        XCTAssertEqual(rec.registeredConsole(hostID: "H", serverMAC: mac, target: 1_000_000).target, 1_000_000)
        XCTAssertEqual(ConsoleRecord(rc, host: "10.0.0.5"), rec)
    }

    // MARK: Gerçek Anahtarlık (yalnız NINO_KEYCHAIN_TESTS=1)

    func testRealKeychainRoundTrip() throws {
        guard ProcessInfo.processInfo.environment["NINO_KEYCHAIN_TESTS"] == "1" else {
            throw XCTSkip("Gerçek Anahtarlık denemesi kapalı (NINO_KEYCHAIN_TESTS=1 ile açılır)")
        }
        let vault = KeychainVault(service: "com.ninotranslator.mac.test")
        let account = "storage-test-\(UUID().uuidString)"
        defer { try? vault.remove(account) }
        XCTAssertNil(try vault.data(for: account))
        try vault.setString("bir", for: account)
        try vault.setString("iki", for: account) // sil + ekle
        XCTAssertEqual(try vault.data(for: account), raw("\"iki\""))
        try vault.remove(account)
        XCTAssertNil(try vault.data(for: account))
        try vault.remove(account)
    }
}
