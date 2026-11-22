// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CRemotePlay
import Foundation
import NinoCore

/// Kayıttan dönen ve oturum açmak için gereken bilgiler. Keychain'de saklanır.
public struct RegisteredConsole: Codable, Equatable, Sendable {
    public var hostID: String
    public var nickname: String
    public var isPS5: Bool
    public var target: Int32
    /// 16 bayt.
    public var registKey: [UInt8]
    /// 16 bayt ("morning" anahtarı).
    public var rpKey: [UInt8]
    public var serverMAC: [UInt8]

    public init(hostID: String, nickname: String, isPS5: Bool, target: Int32,
                registKey: [UInt8], rpKey: [UInt8], serverMAC: [UInt8]) {
        self.hostID = hostID
        self.nickname = nickname
        self.isPS5 = isPS5
        self.target = target
        self.registKey = registKey
        self.rpKey = rpKey
        self.serverMAC = serverMAC
    }

    /// Konsolun MAC adresinden keşifteki kimlik (host-id) biçimi: 12 büyük onaltılık hane.
    public static func hostID(fromMAC mac: [UInt8]) -> String {
        mac.prefix(6).map { String(format: "%02X", $0) }.joined()
    }

    /// Keychain hesap adı.
    public static func secretAccount(hostID: String) -> String { "remoteplay.\(hostID)" }

    public func save(to store: SecretStore) throws {
        let data = try JSONEncoder().encode(self)
        try store.set(data.base64EncodedString(), for: Self.secretAccount(hostID: hostID))
    }

    public static func load(hostID: String, from store: SecretStore) throws -> RegisteredConsole? {
        guard let s = try store.get(secretAccount(hostID: hostID)), let data = Data(base64Encoded: s) else { return nil }
        return try JSONDecoder().decode(RegisteredConsole.self, from: data)
    }
}

/// Eşleştirme hatası: PS5'in bildirdiği neden ve kütüphanenin günlük satırları.
public struct RegistrationError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Reason: Equatable, Sendable {
        /// PS5 kodu kabul etmedi (yanlış ya da süresi geçmiş 8 haneli kod).
        case wrongPIN
        /// PSN hesap kimliği geçersiz.
        case invalidAccount
        /// Uzaktan Oynatma şu an başka bir cihazda kullanılıyor.
        case consoleBusy
        /// PS5'te Uzaktan Oynatma çöktü.
        case consoleCrashed
        /// Sürüm uyuşmazlığı (PS5 yazılımı güncel değil ya da hedef yanlış).
        case versionMismatch
        /// PS5 isteği reddetti: "Cihaz Bağla" ekranı açık değil.
        case linkScreenNotOpen
        /// PS5'e ulaşılamadı (yanlış adres, kapalı ya da başka ağda).
        case unreachable
        /// Adres çözümlenemedi.
        case badAddress
        /// Süre doldu.
        case timeout
        /// Nedeni bilinmiyor; `log` satırlarına bakın.
        case unknown
    }

    public let reason: Reason
    /// PS5'in bildirdiği "RP-Application-Reason" kodu (ör. 0x80108b09).
    public let applicationReason: UInt32?
    /// PS5'in HTTP cevap kodu (200 dışı).
    public let httpStatus: Int?
    /// Bu eşleştirmeye ait son günlük satırları.
    public let log: [String]

    public init(reason: Reason, applicationReason: UInt32? = nil, httpStatus: Int? = nil, log: [String] = []) {
        self.reason = reason
        self.applicationReason = applicationReason
        self.httpStatus = httpStatus
        self.log = log
    }

    /// Kütüphanenin günlük satırlarından nedeni çıkarır.
    public static func parse(log lines: [String], timedOut: Bool = false) -> RegistrationError {
        var appReason: UInt32?
        var http: Int?
        var reason: Reason?
        for line in lines {
            if let r = line.range(of: "Reported Application Reason: ") {
                let hex = line[r.upperBound...].prefix { !$0.isWhitespace }
                let digits = hex.hasPrefix("0x") || hex.hasPrefix("0X") ? hex.dropFirst(2) : hex[...]
                appReason = UInt32(digits, radix: 16)
            } else if let r = line.range(of: "Regist received HTTP code ") {
                http = Int(line[r.upperBound...].prefix { $0.isNumber })
            } else if line.contains("refused the registration search") {
                reason = reason ?? .linkScreenNotOpen
            } else if line.contains("failed to getaddrinfo") {
                reason = reason ?? .badAddress
            } else if line.contains("timed out waiting for search response")
                        || line.contains("failed to connect for search")
                        || line.contains("failed to connect for request")
                        || line.contains("connect failed: tried all addresses") {
                reason = reason ?? .unreachable
            }
        }
        if let code = appReason {
            switch code {
            case 0x8010_8B09: reason = .wrongPIN
            case 0x8010_8B02: reason = .invalidAccount
            case 0x8010_8B10: reason = .consoleBusy
            case 0x8010_8B15: reason = .consoleCrashed
            case 0x8010_8B11: reason = .versionMismatch
            default: break
            }
        }
        return RegistrationError(reason: reason ?? (timedOut ? .timeout : .unknown),
                                 applicationReason: appReason, httpStatus: http, log: Array(lines.suffix(30)))
    }

    public var description: String {
        let text: String
        switch reason {
        case .wrongPIN: text = "PS5 kodu kabul etmedi (kod yanlış ya da süresi geçmiş)"
        case .invalidAccount: text = "PSN hesap kimliği geçersiz"
        case .consoleBusy: text = "Uzaktan Oynatma başka bir cihazda kullanılıyor"
        case .consoleCrashed: text = "PS5'te Uzaktan Oynatma çöktü"
        case .versionMismatch: text = "Sürüm uyuşmuyor"
        case .linkScreenNotOpen: text = "PS5'te \"Cihaz Bağla\" ekranı açık değil"
        case .unreachable: text = "PS5'e ulaşılamadı"
        case .badAddress: text = "Adres geçersiz"
        case .timeout: text = "Zaman aşımı"
        case .unknown: text = "Eşleştirme başarısız"
        }
        if let a = applicationReason { return text + String(format: " (0x%08x)", a) }
        return text
    }
}

/// PS5'i bu cihaza bir kez bağlar (eşleştirme).
public enum ConsoleRegistration {
    /// PSN hesap kimliği: base64 ile yazılmış 8 bayt.
    public static func decodeAccountID(_ base64: String) throws -> [UInt8] {
        guard let d = Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)), d.count == 8 else {
            throw RemotePlayError.badInput("PSN hesap kimliği 8 baytlık base64 olmalı")
        }
        return Array(d)
    }

    /// Konsolun gösterdiği 8 haneli kod.
    public static func parsePIN(_ text: String) throws -> UInt32 {
        let digits = text.filter(\.isNumber)
        guard digits.count == 8, let v = UInt32(digits) else { throw RemotePlayError.badInput("Kod 8 haneli olmalı") }
        return v
    }

    /// Kayıt yapar. `pin`: PS5 → Ayarlar → Sistem → Uzaktan Oynatma → Cihaz Bağla.
    /// Elle IP ile eşleştirmede `ConsoleInfo(address:)` yeter; `hostID` boşsa
    /// sonuçtaki kimlik PS5'in MAC adresinden çıkarılır.
    /// Hata: `RegistrationError` (neden + günlük), iptalde `RemotePlayError.registrationCanceled`.
    public static func register(console: ConsoleInfo, accountID: [UInt8], pin: UInt32,
                                timeout: TimeInterval = 30) async throws -> RegisteredConsole {
        RemotePlayLib.initialize()
        guard accountID.count == 8 else { throw RemotePlayError.badInput("hesap kimliği 8 bayt olmalı") }
        let box = RegistBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<RegisteredConsole, Error>) in
                box.start(console: console, accountID: accountID, pin: pin, timeout: timeout, cont: cont)
            }
        } onCancel: {
            box.cancel()
        }
    }
}

private final class RegistBox: @unchecked Sendable {
    let log = RemotePlayLog()
    let regist = UnsafeMutablePointer<ChiakiRegist>.allocate(capacity: 1)
    private let once = Once2()
    private let timedOut = Once2()
    private var cont: CheckedContinuation<RegisteredConsole, Error>?
    private var console: ConsoleInfo?
    private var started = false
    private var host: UnsafeMutablePointer<CChar>?

    func start(console: ConsoleInfo, accountID: [UInt8], pin: UInt32, timeout: TimeInterval,
               cont: CheckedContinuation<RegisteredConsole, Error>) {
        self.cont = cont
        self.console = console
        host = strdup(console.address)
        var info = ChiakiRegistInfo()
        info.target = ChiakiTarget(rawValue: UInt32(bitPattern: console.target))
        info.host = UnsafePointer(host)
        info.broadcast = false
        info.psn_online_id = nil
        writeFixed(&info.psn_account_id, accountID)
        info.pin = pin
        info.console_pin = 0
        info.holepunch_info = nil
        // Kütüphane kendi sayacını tutar; nesne kayıt bitene kadar yaşar.
        let me = Unmanaged.passRetained(self).toOpaque()
        let err = chiaki_regist_start(regist, log.pointer, &info, { event, user in
            guard let user, let event else { return }
            let box = Unmanaged<RegistBox>.fromOpaque(user).takeRetainedValue()
            box.finish(event.pointee)
        }, me)
        guard err == CHIAKI_ERR_SUCCESS else {
            Unmanaged<RegistBox>.fromOpaque(me).release()
            resume(.failure(RemotePlayError.library(RemotePlayLib.message(err))))
            return
        }
        started = true
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self else { return }
            // Önce durdurulur (fini'den önce stop gerekir); iptal olayı zaman aşımı sayılır.
            self.timedOut.claim()
            self.cancel()
            self.resume(.failure(RegistrationError.parse(log: self.log.recent, timedOut: true)))
        }
    }

    func finish(_ event: ChiakiRegistEvent) {
        switch event.type {
        case CHIAKI_REGIST_EVENT_TYPE_FINISHED_SUCCESS:
            guard let h = event.registered_host?.pointee, let console else {
                resume(.failure(RegistrationError.parse(log: log.recent))); return
            }
            let mac: [UInt8] = readFixed(h.server_mac)
            let reg = RegisteredConsole(hostID: console.hostID.isEmpty ? RegisteredConsole.hostID(fromMAC: mac) : console.hostID,
                                        nickname: String(fixedCString: h.server_nickname),
                                        isPS5: chiaki_target_is_ps5(h.target),
                                        target: Int32(bitPattern: h.target.rawValue),
                                        registKey: readFixed(h.rp_regist_key),
                                        rpKey: readFixed(h.rp_key),
                                        serverMAC: mac)
            resume(.success(reg))
        case CHIAKI_REGIST_EVENT_TYPE_FINISHED_CANCELED:
            if timedOut.isClaimed {
                resume(.failure(RegistrationError.parse(log: log.recent, timedOut: true)))
            } else {
                resume(.failure(RemotePlayError.registrationCanceled))
            }
        default:
            resume(.failure(RegistrationError.parse(log: log.recent)))
        }
    }

    func cancel() {
        if started { chiaki_regist_stop(regist) }
    }

    private func resume(_ r: Result<RegisteredConsole, Error>) {
        guard once.claim() else { return }
        cont?.resume(with: r)
        cont = nil
        DispatchQueue.global().async { [self] in
            if started { chiaki_regist_fini(regist) }
            started = false
            free(host)
            host = nil
        }
    }

    deinit { regist.deallocate() }
}

final class Once2: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    @discardableResult
    func claim() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
    var isClaimed: Bool { lock.withLock { done } }
}
