// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Eşleştirmenin başarısız olma nedenleri (kurulum.md §6).
public enum PairingFailure: String, Error, Equatable, Sendable, CaseIterable {
    case noAddress
    case badAddress
    case badCode
    case noAccount
    case accountNotRecognised
    case wrongCode
    case noAnswer
    case lateAnswer
    case inUse
    case crashed
    case unsupportedVersion
    case localNetworkBlocked
    case refused

    var key: String { "console.pair.error.\(rawValue)" }

    /// Hata iletisinin sonuna ayrıntı ve günlük yolu eklenmez: girişteki eksikler.
    var isInputProblem: Bool { [.noAddress, .badAddress, .badCode, .noAccount].contains(self) }
}

public struct PairingError: Error, Equatable, Sendable {
    public var failure: PairingFailure
    /// PS5'in kodu ("0x80108b09") ya da ilk hata satırı.
    public var detail: String?

    public init(_ failure: PairingFailure, detail: String? = nil) {
        self.failure = failure
        self.detail = detail
    }

    public func message(logPath: String) -> String {
        let text = ConsoleText.string(failure.key)
        if failure.isInputProblem && failure != .badAddress { return text }
        return ConsoleText.withDetailAndLog(text, detail: detail, logPath: logPath)
    }
}

/// PS5'in bildirdiği uygulama nedenleri (Remote Play kitaplığının sabitleri).
public enum RemotePlayReason {
    public static let invalidPSNID: UInt32 = 0x8010_8B02
    public static let registFailed: UInt32 = 0x8010_8B09
    public static let inUse: UInt32 = 0x8010_8B10
    public static let rpVersion: UInt32 = 0x8010_8B11
    public static let remotePlayDisabled: UInt32 = 0x8010_8B12
    public static let crash: UInt32 = 0x8010_8B15
    public static let pairingInvalid26: UInt32 = 0x8010_8B26

    /// Günlük satırındaki "Reported Application Reason: 0x80108b09 (…)" kodunu bulur (son geçen).
    public static func code(inLog lines: [String]) -> UInt32? {
        for line in lines.reversed() {
            guard let r = line.range(of: "Application Reason:", options: .caseInsensitive) else { continue }
            let rest = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
            var hex = rest.prefix { !$0.isWhitespace && $0 != "(" }
            if hex.lowercased().hasPrefix("0x") { hex = hex.dropFirst(2) }
            if let v = UInt32(hex, radix: 16) { return v }
        }
        return nil
    }

    static func hex(_ code: UInt32) -> String { String(format: "0x%08x", code) }
}

public enum PairingClassifier {
    /// Kaydın neden başarısız olduğunu bulur. Önce PS5'in bildirdiği neden, yoksa kitaplığın hata satırları.
    public static func classify(_ f: RegistrationFailure) -> PairingError {
        if let code = f.reasonCode ?? RemotePlayReason.code(inLog: f.logLines) {
            let detail = RemotePlayReason.hex(code)
            switch code {
            case RemotePlayReason.invalidPSNID: return PairingError(.accountNotRecognised, detail: detail)
            case RemotePlayReason.registFailed: return PairingError(.wrongCode, detail: detail)
            case RemotePlayReason.inUse: return PairingError(.inUse, detail: detail)
            case RemotePlayReason.crash: return PairingError(.crashed, detail: detail)
            case RemotePlayReason.rpVersion: return PairingError(.unsupportedVersion, detail: detail)
            default: return PairingError(.refused, detail: detail)
            }
        }
        let first = firstErrorLine(f.logLines) ?? f.message
        if f.consoleNotFound { return PairingError(.noAnswer, detail: first) }
        let lower = f.logLines.map { $0.lowercased() }
        if lower.contains(where: { $0.contains("getaddrinfo") }) { return PairingError(.badAddress, detail: first) }
        if lower.contains(where: { $0.contains("send") && ($0.contains("no route to host") || $0.contains("not permitted")) }) {
            return PairingError(.localNetworkBlocked, detail: first)
        }
        if noSearchAnswer(f.logLines) || lower.contains(where: { $0.contains("connect") && $0.contains("fail") }) {
            return PairingError(.noAnswer, detail: first)
        }
        if lower.contains(where: { $0.contains("response") && ($0.contains("header") || $0.contains("content")) }) {
            return PairingError(.lateAnswer, detail: first)
        }
        if f.timedOut || f.canceled { return PairingError(.lateAnswer, detail: first) }
        return PairingError(.refused, detail: first)
    }

    /// Kod PS5'e hiç ulaşmadı mı (arama paketine cevap yok)? Yalnız bu durumda yeniden denenir.
    public static func noSearchAnswer(_ lines: [String]) -> Bool {
        lines.contains { line in
            let l = line.lowercased()
            return l.contains("search") && (l.contains("fail") || l.contains("timeout") || l.contains("timed out"))
        }
    }

    static func shouldRetry(_ f: RegistrationFailure) -> Bool {
        guard f.reasonCode == nil, RemotePlayReason.code(inLog: f.logLines) == nil else { return false }
        return f.consoleNotFound || noSearchAnswer(f.logLines)
    }

    static func firstErrorLine(_ lines: [String]) -> String? {
        lines.first { l in
            let x = l.lowercased()
            return x.contains("fail") || x.contains("error")
        }
    }
}

/// PS5 arar ve eşleştirir; başarıda kaydı kasaya yazar.
public struct ConsolePairer: Sendable {
    public let discovery: ConsoleDiscovering
    public let registrar: ConsoleRegistering
    public let store: ConsoleRecordStore
    public let log: ConsoleLog
    public let clock: ConsoleClock

    /// Arama süresi ve kod PS5'e ulaşmazsa deneme sayısı/arası.
    public var searchDuration: TimeInterval = 3
    public var maxAttempts = 3
    public var retryDelay: TimeInterval = 0.5

    public init(discovery: ConsoleDiscovering, registrar: ConsoleRegistering, store: ConsoleRecordStore,
                log: ConsoleLog = .discard, clock: ConsoleClock = SystemConsoleClock()) {
        self.discovery = discovery
        self.registrar = registrar
        self.store = store
        self.log = log
        self.clock = clock
    }

    /// Ağdaki PS5'ler (yalnız PS5 cevapları). Bulunanlar günlüğe yazılır.
    public func search() async -> [DiscoveredPS5] {
        let found = ((try? await discovery.search(duration: searchDuration)) ?? []).filter(\.isPS5)
        if found.isEmpty { log.write("PS5 araması: bulunamadı") }
        for c in found {
            log.write("PS5 bulundu: \(c.name) \(c.address)" + (c.asleep ? " (dinlenmede)" : ""))
        }
        return found
    }

    /// Eşleştirir. `address`: seçili PS5'in adresi ya da elle yazılan adres. `console`: aramada seçilen PS5.
    public func pair(address rawAddress: String, code rawCode: String, accountID: Data?,
                     console: DiscoveredPS5? = nil) async throws -> PS5Pairing {
        guard !rawAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PairingError(.noAddress)
        }
        guard let address = ConsoleInput.sanitizeAddress(rawAddress) else { throw PairingError(.badAddress) }
        guard let code = ConsoleInput.pairingCode(rawCode), let pin = UInt32(code) else {
            throw PairingError(.badCode)
        }
        guard let accountID, accountID.count == 8 else { throw PairingError(.noAccount) }
        let known = console?.address == address ? console : nil

        var attempt = 0
        while true {
            attempt += 1
            do {
                let result = try await registrar.register(address: address, console: known, accountID: accountID, pin: pin)
                let pairing = PS5Pairing(host: address, name: result.name.isEmpty ? (known?.name ?? "") : result.name,
                                         registKey: result.registKey, morning: result.morning)
                guard pairing.hasUsableKeys else {
                    log.write("PS5 eşleştirmesi başarısız: anahtar boş")
                    throw PairingError(.refused)
                }
                try store.savePairing(pairing)
                log.write("PS5 kaydı kaydedildi: \(pairing.name) \(address)")
                return pairing
            } catch let failure as RegistrationFailure {
                if PairingClassifier.shouldRetry(failure), attempt < maxAttempts {
                    log.write("PS5 eşleştirmesi: arama cevabı yok, yeniden deneniyor (\(attempt)/\(maxAttempts))")
                    try await clock.sleep(seconds: retryDelay)
                    continue
                }
                let error = PairingClassifier.classify(failure)
                log.write("PS5 eşleştirmesi başarısız: \(error.failure.rawValue) \(error.detail ?? "")")
                throw error
            } catch let error as PairingError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                log.write("PS5 eşleştirmesi başarısız: \(error)")
                throw PairingError(.refused, detail: "\(error)")
            }
        }
    }
}
