// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// TV uygulaması kurulum hatası (tv-kurulumu.md §7).
public struct TVInstallError: Error, Equatable, Sendable {
    public enum Problem: String, Equatable, Sendable, CaseIterable {
        case keyServerOff, wrongPassphrase, keyRejected, unreachable, installFailed, noSpace, tooOld, loginFailed
        case certificateFailed, notApproved, certificateMismatch, certificateRejected, tvClockWrong, packageBlocked
        case connectionLost
    }

    public var problem: Problem
    /// TV'nin ya da yardımcının verdiği sebep (kartta gösterilir).
    public var reason: String?

    public init(_ problem: Problem, reason: String? = nil) {
        self.problem = problem
        let r = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reason = (r?.isEmpty ?? true) ? nil : r
    }

    /// Yardımcının hata kodu. Tanınmayan kod "kurulamadı".
    public static func problem(forHelperCode code: String) -> Problem {
        switch code {
        case "Unreachable": return .unreachable
        case "NotApproved": return .notApproved
        case "LoginFailed": return .loginFailed
        case "CertificateFailed": return .certificateFailed
        case "TooOld": return .tooOld
        case "InstallFailed": return .installFailed
        case "NotEnoughSpace": return .noSpace
        case "CertificateMismatch": return .certificateMismatch
        case "CertificateRejected": return .certificateRejected
        case "TvClockWrong": return .tvClockWrong
        case "PackageBlocked": return .packageBlocked
        case "ConnectionLost": return .connectionLost
        default: return .installFailed
        }
    }

    /// LG kurulum yanıtında yer sorunu geçiyor mu.
    public static func mentionsNoSpace(_ text: String) -> Bool {
        let l = text.lowercased()
        let needles = ["no space", "not enough space", "not enough storage", "insufficient", "out of space",
                       "storage full", "disk full", "enospc", "lack of space"]
        return needles.contains { l.contains($0) }
    }
}

/// Kurulum ve eşleşme iletileri (`Resources/TVSetup.xcstrings`).
public enum TVSetupText {
    static let table = "TVSetup"

    public static func string(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), table: table, bundle: .module)
    }

    public static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: args)
    }

    // MARK: Kurulum (tv-kurulumu.md §7)

    static func mainKey(_ e: TVInstallError, brand: PairedTV.Brand) -> String {
        switch e.problem {
        case .keyServerOff: return "tv.install.error.keyServerOff"
        case .wrongPassphrase: return "tv.install.error.wrongPassphrase"
        case .keyRejected: return "tv.install.error.keyRejected"
        case .unreachable: return brand == .samsung ? "tv.install.error.unreachableSamsung" : "tv.install.error.unreachable"
        case .installFailed: return e.reason == nil ? "tv.install.error.failed" : "tv.install.error.failedWithReason"
        case .noSpace: return "tv.install.error.noSpace"
        case .tooOld: return "tv.install.error.tooOld"
        case .loginFailed: return "tv.install.error.loginFailed"
        case .certificateFailed: return "tv.install.error.certificateFailed"
        case .notApproved: return "tv.install.error.notApproved"
        case .certificateMismatch: return "tv.install.error.certificateMismatch"
        case .certificateRejected: return "tv.install.error.certificateRejected"
        case .tvClockWrong: return "tv.install.error.tvClockWrong"
        case .packageBlocked: return "tv.install.error.packageBlocked"
        case .connectionLost: return "tv.install.error.connectionLost"
        }
    }

    /// Kartta gösterilecek bütün metin: ana ileti, (varsa) boş satır + sebep, sonra markaya göre ek satırlar.
    public static func installMessage(_ e: TVInstallError, brand: PairedTV.Brand, logPath: String,
                                      appStoreBuild: Bool = false) -> String {
        var blocks = [string(mainKey(e, brand: brand))]
        if let reason = e.reason {
            let label = brand == .samsung ? string("tv.install.detailsLabel") : string("tv.install.tvSaysLabel")
            blocks.append(label + " " + reason)
        }
        if appStoreBuild, e.problem == .installFailed { blocks.append(string("tv.install.error.appStoreHint")) }
        if brand == .samsung {
            if e.problem == .installFailed || e.problem == .certificateRejected {
                blocks.append(string("tv.install.samsung.maintenanceHint"))
            }
            if [.unreachable, .installFailed, .certificateRejected].contains(e.problem) {
                blocks.append(string("tv.install.samsung.holdPowerHint"))
            }
            if e.problem == .connectionLost { blocks.append(string("tv.install.samsung.anynetHint")) }
            if !logPath.isEmpty { blocks.append(format("tv.install.sendLog", logPath)) }
        }
        return blocks.joined(separator: "\n\n")
    }

    /// Samsung "koptu" hâlinin metni (eksik adım yokken TV bağlantıyı kesti).
    public static func samsungDroppedMessage(hostMatches: Bool, macAddress: String?, reason: String?,
                                             logPath: String) -> String {
        var blocks: [String] = []
        if hostMatches {
            blocks.append(string("tv.install.samsung.droppedSettingsRight"))
        } else {
            blocks.append(string("tv.install.error.unreachableSamsung"))
            if let macAddress { blocks.append(format("tv.install.samsung.thisAddress", macAddress)) }
            blocks.append(string("tv.install.samsung.holdPowerHint"))
        }
        if let reason, !reason.isEmpty { blocks.append(string("tv.install.detailsLabel") + " " + reason) }
        if !logPath.isEmpty { blocks.append(format("tv.install.sendLog", logPath)) }
        return blocks.joined(separator: "\n\n")
    }

    // MARK: Yardımcının iç ayrıntıları

    static func helperMissing() -> String { string("tv.helper.missing") }

    static func helperEndedWithoutResult(exitCode: Int32?, stderrTail: String) -> String {
        let code = exitCode.map { String($0) } ?? string("tv.helper.didNotExit")
        return format("tv.helper.endedWithoutResult", code, stderrTail)
    }

    static func versionNotVisible(_ version: String, reply: String) -> String {
        format("tv.lg.versionNotVisible", version, reply)
    }
}
