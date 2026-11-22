// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore
import NinoRemotePlay

/// PS5 bulma, eşleme ve oturum için NinoRemotePlay'e köprü.
enum Consoles {
    /// PS5'in hedef kodu (Remote Play kütüphanesinde PS5 1).
    static let ps5Target: Int32 = 1_000_100

    struct Found: Equatable, Hashable {
        let name: String
        let address: String
        let info: ConsoleInfo?
    }

    /// Ağda PS5 arar (yaklaşık `seconds` sn). İlk aramada iOS yerel ağ izni sorar; boş dönerse bir kez daha denenir.
    static func discover(seconds: Double = 3) async -> [Found] {
        let first = await discoverOnce(seconds: seconds)
        return first.isEmpty ? await discoverOnce(seconds: seconds) : first
    }

    private static func discoverOnce(seconds: Double) async -> [Found] {
        let discovery = ConsoleDiscovery()
        defer { discovery.stop() }
        guard let stream = try? discovery.consoles() else { return [] }
        let box = LatestBox<[ConsoleInfo]>()
        let task = Task {
            for await list in stream { box.set(list) }
        }
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
        task.cancel()
        return (box.get() ?? []).filter(\.isPS5).map { Found(name: $0.name, address: $0.address, info: $0) }
    }

    enum PairFailure: Error, Equatable {
        case noAddress, badCode, notSignedIn, wrongAccount, wrongCode, noAnswer, timedOut, inUse, crashed, version,
             notFoundAtAddress, other

        var message: String {
            switch self {
            case .noAddress: L("pair.error.notfound")
            case .badCode: L("pair.error.codelength")
            case .notSignedIn: L("psn.error.signinfirst")
            case .wrongAccount: L("pair.error.wrongAccount")
            case .wrongCode: L("pair.error.wrongCode")
            case .noAnswer: L("session.error.noanswer")
            case .timedOut: L("pair.error.late")
            case .inUse: L("pair.error.inUse")
            case .crashed: L("pair.error.crashed")
            case .version: L("pair.error.version")
            case .notFoundAtAddress: L("pair.error.notatAddress")
            case .other: L("pair.error.badcode")
            }
        }

        init(_ reason: RegistrationError.Reason) {
            switch reason {
            case .wrongPIN, .linkScreenNotOpen: self = .wrongCode
            case .invalidAccount: self = .wrongAccount
            case .consoleBusy: self = .inUse
            case .consoleCrashed: self = .crashed
            case .versionMismatch: self = .version
            case .unreachable: self = .noAnswer
            case .badAddress: self = .notFoundAtAddress
            case .timeout: self = .timedOut
            case .unknown: self = .other
            }
        }
    }

    /// PIN metnini okur: boşluk ve ayraçlar atlanır, her yazı sisteminin rakamları kabul edilir; tam 8 hane.
    static func parsePIN(_ text: String) -> UInt32? {
        var digits = ""
        for ch in text {
            if " -–._".contains(ch) { continue }
            guard ch.unicodeScalars.count == 1, let v = ch.wholeNumberValue, ch.isNumber else { return nil }
            digits.append(String(v))
        }
        guard digits.count == 8 else { return nil }
        return UInt32(digits)
    }

    /// PS5'i bu telefona eşler. Elle yazılan adreste önce o adresteki PS5 sorulur.
    static func pair(address: String, info known: ConsoleInfo?, pin: String, accountID: Data?) async throws -> PairedConsole {
        let host = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { throw PairFailure.noAddress }
        guard let code = parsePIN(pin) else { throw PairFailure.badCode }
        guard let accountID, accountID.count == 8 else { throw PairFailure.notSignedIn }
        var info = known?.address == host ? known : nil
        if info == nil { info = try? await ConsoleDiscovery().probe(host: host) }
        let target = info ?? ConsoleInfo(name: "PS5", address: host)
        do {
            let reg = try await ConsoleRegistration.register(console: target, accountID: Array(accountID), pin: code)
            return PairedConsole(host: host, name: reg.nickname.isEmpty ? target.name : reg.nickname,
                                 registKey: Data(reg.registKey), morning: Data(reg.rpKey))
        } catch let e as RegistrationError {
            throw PairFailure(e.reason)
        } catch RemotePlayError.timeout {
            throw PairFailure.timedOut
        } catch {
            throw PairFailure.other
        }
    }

    /// Kayıtlı PS5'ten oturum bilgisi.
    static func registered(_ c: PairedConsole) -> RegisteredConsole? {
        func bytes(_ d: Data) -> [UInt8] { Array(d.prefix(16)) + Array(repeating: 0, count: max(0, 16 - d.count)) }
        return RegisteredConsole(hostID: c.host, nickname: c.name, isPS5: true, target: ps5Target,
                                 registKey: bytes(c.registKey), rpKey: bytes(c.morning), serverMAC: [])
    }
}

/// Bir akıştan gelen son değeri tutar.
final class LatestBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?
    func set(_ v: T) { lock.withLock { value = v } }
    func get() -> T? { lock.withLock { value } }
}
