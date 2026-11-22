// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// PS5 oturumunun saf kuralları (kaynaklar.md §1): kopma nedenleri, yeniden bağlanma aralıkları,
// PS5'i ağda yeniden bulma. Ağ ya da saat yok; hepsi doğrudan sınanır.



public enum DropClassifier {
    /// Kitaplığın kapanış nedeni ve son günlük satırlarından kopma nedeni. Bizim durdurmamızsa `nil`.
    ///
    /// - Parameters:
    ///   - quitReason: Kitaplığın kapanış metni (ör. "Remote Play on Console is already in use").
    ///   - probeAnswered: Bu denemede PS5 arama paketine cevap verdi mi.
    ///   - address: Bağlanılan adres (bulunamadı iletisi için).
    public static func classify(quitReason: String, log: [String], probeAnswered: Bool, address: String) -> SourceStatus.DropReason? {
        let q = quitReason.lowercased()
        if q == "stopped" { return nil }

        let code = RemotePlayReason.code(inLog: log)
        switch code {
        case RemotePlayReason.registFailed, RemotePlayReason.invalidPSNID, RemotePlayReason.pairingInvalid26:
            return .pairingInvalid
        case RemotePlayReason.remotePlayDisabled:
            return .remotePlayDisabled
        case RemotePlayReason.inUse:
            return .inUseElsewhere
        default:
            break
        }

        if q.contains("already in use") { return .inUseElsewhere }
        if q.contains("registration using psn") { return .pairingInvalid }
        if q.contains("server shut down") { return .asleep }
        if q.contains("refused in ctrl") || q.contains("ctrl refused") { return .refused }
        if q.contains("session request") {
            // Oturum isteği (TCP 9295). PS5'in kodu varsa kodlu ret.
            if let code { return .rejected(code: code) }
            // Bağlantı hiç kurulamadıysa (PS5 kapalı ya da adres yanlış) ret değil, ulaşılamıyor.
            let connectFailed = log.contains { $0.localizedCaseInsensitiveContains("session request connect failed") }
            if !probeAnswered && !address.isEmpty { return .notFound(address: address) }
            if connectFailed && !q.contains("refused") { return .network }
            return .rejected(code: nil)
        }

        let reason: SourceStatus.DropReason
        if q.contains("ctrl failed to connect") || q.contains("stream connection") || q.contains("network") {
            reason = .network
        } else if q.isEmpty || q == "none" || q == "unknown" {
            reason = .other(detail: nil)
        } else {
            reason = .other(detail: quitReason)
        }
        if !probeAnswered && !address.isEmpty { return .notFound(address: address) }
        return reason
    }

    /// Bu nedenlerde oturum durur, yeniden denenmez.
    public static func isFinal(_ reason: SourceStatus.DropReason) -> Bool {
        switch reason {
        case .pairingInvalid, .remotePlayDisabled, .passcodeRequired, .passcodeWrong, .noPicture: return true
        default: return false
        }
    }
}

/// Bir bağlanma denemesinin sonucu.
public struct ConsoleAttemptOutcome: Equatable, Sendable {
    public var reason: SourceStatus.DropReason
    /// PS5 "bağlandı" dedi mi.
    public var connected: Bool
    /// Bağlıyken en az bir kare geldi mi.
    public var gotFrames: Bool
    /// Oturumun açık kaldığı süre (bağlanmadıysa 0).
    public var duration: TimeInterval

    public init(reason: SourceStatus.DropReason, connected: Bool = false, gotFrames: Bool = false, duration: TimeInterval = 0) {
        self.reason = reason
        self.connected = connected
        self.gotFrames = gotFrames
        self.duration = duration
    }
}

/// Yeniden bağlanma sırası: 2, 4, 8, 16, sonra hep 30 sn; "başka cihazda" için 8, 16, 30.
public struct ReconnectPolicy: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case retry(after: TimeInterval, showing: SourceStatus.DropReason)
        case giveUp(SourceStatus.DropReason)
    }

    public static let delays: [TimeInterval] = [2, 4, 8, 16, 30]
    public static let inUseDelays: [TimeInterval] = [8, 16, 30]
    /// Bu süreden uzun açık kalan oturum kapanınca aralık baştan başlar.
    public static let longSession: TimeInterval = 60
    /// Art arda bu kadar görüntüsüz oturumda vazgeçilir.
    public static let maxFramelessSessions = 3

    public private(set) var step = 0
    public private(set) var framelessSessions = 0

    public init() {}

    public mutating func next(after outcome: ConsoleAttemptOutcome) -> Decision {
        if DropClassifier.isFinal(outcome.reason) { return .giveUp(outcome.reason) }
        if outcome.connected {
            framelessSessions = outcome.gotFrames ? 0 : framelessSessions + 1
            if framelessSessions >= Self.maxFramelessSessions { return .giveUp(.noPicture) }
        }
        if outcome.duration > Self.longSession { step = 0 }
        let table = outcome.reason == .inUseElsewhere ? Self.inUseDelays : Self.delays
        let delay = table[min(step, table.count - 1)]
        step += 1
        return .retry(after: delay, showing: outcome.reason)
    }

    /// "Hemen yeniden bağlan" (uyanma, ağ değişimi): sayaçlar sıfırlanır.
    public mutating func reset() {
        step = 0
        framelessSessions = 0
    }
}

/// PS5'i ağda yeniden bulma kuralları.
public enum ConsoleLocator {
    /// Tüm ağ taramasında hangisi bizim PS5: tek PS5 varsa o; birden çoksa adı tek eşleşen; yoksa `nil`.
    public static func pick(from found: [DiscoveredPS5], name: String) -> DiscoveredPS5? {
        let ps5s = found.filter(\.isPS5)
        if ps5s.count == 1 { return ps5s[0] }
        let wanted = name.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return nil }
        let matches = ps5s.filter { $0.name.compare(wanted, options: .caseInsensitive) == .orderedSame }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Tüm ağ taraması pahalıdır: bu oturumda hiç yapılmadıysa ya da son taramadan beri bu kadar geçtiyse yapılır.
    public static let fullScanInterval: TimeInterval = 60

    public static func mayScanWholeNetwork(lastScan: TimeInterval?, now: TimeInterval) -> Bool {
        guard let lastScan else { return true }
        return now - lastScan >= fullScanInterval
    }
}
