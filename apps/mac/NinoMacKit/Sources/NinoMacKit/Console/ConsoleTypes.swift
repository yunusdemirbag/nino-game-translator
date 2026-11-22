// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

// PS5 tarafının ortak tipleri ve dış dünyaya açılan kapılar (ağ, kasa, saat, günlük).
// Ağ gerektiren her şey bir protokolün arkasındadır; testler sahtesini verir.

/// Eşli PS5'in kaydı (veri-uyumu.md §2, `console`): adres, ad ve iki 16 baytlık anahtar.
///
/// Eski kayıtta PS5'in ana bilgisayar kimliği, MAC adresi ve hedef sürüm yoktur; bunlar
/// bağlanırken ağdaki arama cevabından tamamlanır.
public struct PS5Pairing: Equatable, Sendable {
    public var host: String
    public var name: String
    /// 16 bayt: ASCII onaltılık rakamlar, sonu sıfırla dolu. Uyandırma kimliği bundan çıkar.
    public var registKey: Data
    /// 16 baytlık oturum anahtarı.
    public var morning: Data

    public init(host: String, name: String,
                registKey key: Data, morning secret: Data) {
        (self.host, self.name) = (host, name)
        (registKey, morning) = (key, secret)
    }

    /// İki anahtar da 16 bayt ve hiçbiri tamamen sıfır değil.
    public var hasUsableKeys: Bool {
        registKey.count == 16 && morning.count == 16
            && registKey.contains { $0 != 0 } && morning.contains { $0 != 0 }
    }
}

/// Ağdaki aramada bulunan bir konsol.
public struct DiscoveredPS5: Equatable, Hashable, Sendable, Identifiable {
    public var hostID: String
    public var name: String
    public var address: String
    /// Dinlenme modunda mı.
    public var asleep: Bool
    public var isPS5: Bool
    public var runningApp: String?
    /// Çalışan uygulamanın kimliği (`PPSA01234`, `CUSA00419_00`); ana ekran ve sistem uygulamalarında başka biçim.
    public var runningAppID: String?
    /// Kayıt için kütüphanenin sürüm hedefi.
    public var target: Int32

    public var id: String { hostID.isEmpty ? address : hostID }

    public init(hostID: String, name: String, address: String, asleep: Bool, isPS5: Bool = true,
                runningApp: String? = nil, target: Int32 = PS5Target.default, runningAppID: String? = nil) {
        self.hostID = hostID
        self.name = name
        self.address = address
        self.asleep = asleep
        self.isPS5 = isPS5
        self.runningApp = runningApp
        self.runningAppID = runningAppID
        self.target = target
    }
}

public enum PS5Target {
    /// Kütüphanenin PS5 hedefi. Eski uygulama da kayıtlı konsolu PS5 sayar.
    public static let `default`: Int32 = 1_000_100
}

/// PS5 tarafının ihtiyaç duyduğu kasa. Uygulamada Anahtarlık kayıtlarına bağlanır
/// (veri-uyumu.md §2: `console`, `accountId`, `loginPasscode`); testlerde bellekte durur.
public protocol ConsoleRecordStore: Sendable {
    func loadPairing() throws -> PS5Pairing?
    func savePairing(_ pairing: PS5Pairing) throws
    /// İkinci PSN hesabının 8 baytlık kimliği.
    func loadAccountID() throws -> Data?
    func saveAccountID(_ id: Data) throws
    func deleteAccountID() throws
    /// İkinci hesabın PS5'teki 4 haneli giriş şifresi (isteğe bağlı).
    func loadLoginPasscode() throws -> String?
}

/// Bellekte duran kasa (testler ve önizlemeler).
public final class MemoryConsoleRecordStore: ConsoleRecordStore, @unchecked Sendable {
    private let lock = NSLock()
    private var pairing: PS5Pairing?
    private var accountID: Data?
    private var passcode: String?

    public init(pairing: PS5Pairing? = nil, accountID: Data? = nil, passcode: String? = nil) {
        self.pairing = pairing
        self.accountID = accountID
        self.passcode = passcode
    }

    public func loadPairing() throws -> PS5Pairing? { lock.withLock { pairing } }
    public func savePairing(_ pairing: PS5Pairing) throws { lock.withLock { self.pairing = pairing } }
    public func loadAccountID() throws -> Data? { lock.withLock { accountID } }
    public func saveAccountID(_ id: Data) throws { lock.withLock { accountID = id } }
    public func deleteAccountID() throws { lock.withLock { accountID = nil } }
    public func loadLoginPasscode() throws -> String? { lock.withLock { passcode } }
    public func setLoginPasscode(_ code: String?) { lock.withLock { passcode = code } }
}

/// Remote Play günlüğü (`remoteplay.log`). Yolu hata iletilerinin sonuna eklenir.
public struct ConsoleLog: Sendable {
    public let path: String
    private let sink: @Sendable (String) -> Void

    public init(path: String, write: @escaping @Sendable (String) -> Void) {
        self.path = path
        self.sink = write
    }

    public func write(_ line: String) { sink(line) }

    public static let discard = ConsoleLog(path: "", write: { _ in })
}

// MARK: Ağ kapıları

/// Ağda PS5 arar.
public protocol ConsoleDiscovering: Sendable {
    /// Bütün yerel ağda `duration` saniye arar; bulunanların hepsini verir.
    func search(duration: TimeInterval) async throws -> [DiscoveredPS5]
    /// Yalnız verilen adrese arar.
    func probe(address: String, duration: TimeInterval) async throws -> DiscoveredPS5?
}

/// Kayıt (eşleştirme) isteği gönderir.
public protocol ConsoleRegistering: Sendable {
    func register(address: String, console: DiscoveredPS5?, accountID: Data, pin: UInt32) async throws
        -> RegistrationResult
}

public struct RegistrationResult: Equatable, Sendable {
    public var name: String
    public var registKey: Data
    public var morning: Data
    public var hostID: String

    public init(name: String, registKey: Data, morning: Data, hostID: String = "") {
        self.name = name
        self.registKey = registKey
        self.morning = morning
        self.hostID = hostID
    }
}

/// Kaydın başarısızlığı: PS5'in bildirdiği neden, kitaplığın hata satırları ve süre/iptal bilgisi.
public struct RegistrationFailure: Error, Equatable, Sendable {
    public var reasonCode: UInt32?
    public var logLines: [String]
    public var timedOut: Bool
    public var canceled: Bool
    /// Adres aramaya hiç cevap vermedi (kod PS5'e ulaşmadı).
    public var consoleNotFound: Bool
    public var message: String?

    public init(reasonCode: UInt32? = nil, logLines: [String] = [], timedOut: Bool = false, canceled: Bool = false,
                consoleNotFound: Bool = false, message: String? = nil) {
        self.reasonCode = reasonCode
        self.logLines = logLines
        self.timedOut = timedOut
        self.canceled = canceled
        self.consoleNotFound = consoleNotFound
        self.message = message
    }
}

/// Açık bir Remote Play oturumunun olayları.
public enum RemotePlayLinkEvent: Sendable {
    case connected
    case frame(Frame)
    /// PS5 ikinci hesabın giriş şifresini istiyor. `incorrect`: önceki şifre kabul edilmedi.
    case passcodeRequested(incorrect: Bool)
    /// Oturum kapandı. `quitReason`: kitaplığın kapanış nedeni; `log`: son günlük satırları.
    case ended(quitReason: String, log: [String])
}

/// Açık oturum. `close()` bloklayabilir; ana iş parçacığından çağrılmaz.
public protocol RemotePlayLink: AnyObject, Sendable {
    var events: AsyncStream<RemotePlayLinkEvent> { get }
    var canSubmitPasscode: Bool { get }
    func submitPasscode(_ code: String)
    func close()
}

/// Oturum açar ve uyandırma paketi gönderir.
public protocol RemotePlayConnecting: Sendable {
    func open(address: String, pairing: PS5Pairing, console: DiscoveredPS5?) throws -> RemotePlayLink
    func wake(address: String, pairing: PS5Pairing) throws
}

/// Saat. Testler sanal saat verir.
public protocol ConsoleClock: Sendable {
    /// Tekdüze saniye.
    func now() -> TimeInterval
    func sleep(seconds: TimeInterval) async throws
}

public struct SystemConsoleClock: ConsoleClock {
    public init() {}
    public func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
    public func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}
