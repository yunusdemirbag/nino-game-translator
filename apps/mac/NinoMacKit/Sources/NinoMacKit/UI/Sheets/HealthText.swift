// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Sistem sağlığının metinleri (seviye, sebep, denetim satırları). Arayüz dilinde.
enum HealthText {
    static func s(_ key: String, _ locale: Locale, _ args: CVarArg...) -> String {
        NinoL10n.string(key, table: SheetsText.table, language: NinoL10n.languageCode(for: locale), arguments: args)
    }

    static func level(_ level: HealthLevel, _ locale: Locale) -> String {
        switch level {
        case .notMeasured: return s("sheets.health.level.notMeasured", locale)
        case .good: return s("sheets.health.level.good", locale)
        case .fair: return s("sheets.health.level.fair", locale)
        case .problem: return s("sheets.health.level.problem", locale)
        }
    }

    static func levelColor(_ level: HealthLevel) -> NinoColor {
        switch level {
        case .notMeasured: return .textSecondary
        case .good: return .success
        case .fair: return .warning
        case .problem: return .danger
        }
    }

    static func causeTitle(_ cause: ProbableCause, _ locale: Locale) -> String {
        s("sheets.health.cause.\(causeID(cause)).title", locale)
    }

    static func causeAction(_ cause: ProbableCause, _ locale: Locale) -> String {
        let key = "sheets.health.cause.\(causeID(cause)).action"
        switch cause {
        case .networkDropped(let n), .frequentDrops(let n), .tvDropped(let n):
            return s(key + " %d", locale, n)
        case .slowTranslation(let seconds):
            return s(key + " %@", locale, String(format: "%.1f", locale: locale, seconds))
        default:
            return s(key, locale)
        }
    }

    static func causeID(_ cause: ProbableCause) -> String {
        switch cause {
        case .noNetwork: return "noNetwork"
        case .droppedAfterNetworkLoss: return "afterNetworkLoss"
        case .ps5Asleep: return "asleep"
        case .usedElsewhere: return "elsewhere"
        case .ps5DroppedGeneral: return "dropped"
        case .couldNotConnect: return "couldNotConnect"
        case .networkDropped: return "networkDropped"
        case .pictureLossWifi: return "pictureLossWifi"
        case .pictureLossWired: return "pictureLossWired"
        case .frequentDrops: return "frequentDrops"
        case .slowTranslation: return "slow"
        case .tvDropped: return "tvDropped"
        }
    }

    static func network(_ kind: NetworkKind, _ locale: Locale) -> String {
        switch kind {
        case .wired: return s("sheets.health.network.wired", locale)
        case .wifi: return s("sheets.health.network.wifi", locale)
        case .other: return s("sheets.health.network.other", locale)
        case .offline: return s("sheets.health.network.offline", locale)
        case .unknown: return s("sheets.health.network.unknown", locale)
        }
    }

    static func problem(_ kind: ProblemKind, _ locale: Locale) -> String {
        s("sheets.health.problem.\(kind.rawValue)", locale)
    }

    /// "Son kopma" satırı: saat (bugün değilse tarih de) dil biçiminde, neden kendi cümlesiyle.
    static func lastTVDrop(_ note: TVDropNote?, _ locale: Locale, now: Date) -> String? {
        guard let note else { return nil }
        let f = DateFormatter()
        f.locale = locale
        f.timeStyle = .short
        f.dateStyle = Calendar.current.isDate(note.date, inSameDayAs: now) ? .none : .short
        return s("sheets.health.tv.lastDrop %@ %@", locale, f.string(from: note.date),
                 s("sheets.health.tv.dropCause.\(note.cause.rawValue)", locale))
    }

    static func consoleAdvice(_ reason: HealthDropReason?, _ locale: Locale) -> String {
        s("sheets.health.consoleAdvice.\((reason ?? .other).rawValue)", locale)
    }
}

/// Bir denetim satırı (§3.2).
struct HealthCheckRow: Identifiable {
    var id: String
    var symbol: String
    var title: String
    var value: String
    var level: HealthLevel
    var advice: String?
}

@MainActor
enum HealthChecks {
    static func rows(_ m: HealthMetrics, state: AppState, locale: Locale, now: Date) -> [HealthCheckRow] {
        let s = { (key: String) in HealthText.s(key, locale) }
        var rows: [HealthCheckRow] = []

        let networkLevel = HealthRules.network(m)
        rows.append(HealthCheckRow(
            id: "network", symbol: m.network == .wired ? "cable.connector" : "wifi",
            title: s("sheets.health.row.network"), value: HealthText.network(m.network, locale), level: networkLevel,
            advice: m.network == .offline ? s("sheets.health.advice.noNetwork") : s("sheets.health.advice.networkLoss")))

        let consoleValue: String
        if !m.hasMeasurements {
            consoleValue = s("sheets.health.value.notStarted")
        } else if HealthRules.ps5Down(m) {
            consoleValue = HealthText.s("sheets.health.value.downFor %d", locale, HealthRules.downMinutes(m, now: now))
        } else if HealthRules.neverConnected(m) {
            consoleValue = HealthText.s("sheets.health.value.couldNotConnect %d", locale, m.connectAttempts)
        } else if m.dropsWhileStreaming == 0 {
            consoleValue = s("sheets.health.value.noDrops")
        } else {
            consoleValue = HealthText.s("sheets.health.value.drops %d", locale, m.dropsWhileStreaming)
        }
        rows.append(HealthCheckRow(id: "console", symbol: "gamecontroller", title: s("sheets.health.row.console"),
                                   value: consoleValue, level: HealthRules.console(m),
                                   advice: HealthText.consoleAdvice(m.lastDropReason, locale)))

        let videoValue: String
        if !m.hasMeasurements {
            videoValue = s("sheets.health.value.notStarted")
        } else if !m.receivingVideo, m.translating {
            videoValue = s("sheets.health.value.noPicture")
        } else if let loss = m.lossPerMinute, let stalls = m.stallsPerMinute {
            videoValue = HealthText.s("sheets.health.value.video %@ %@", locale,
                                      String(format: "%.0f", locale: locale, loss),
                                      String(format: "%.1f", locale: locale, stalls))
        } else {
            videoValue = s("sheets.health.value.measuring")
        }
        rows.append(HealthCheckRow(id: "video", symbol: "play.rectangle", title: s("sheets.health.row.video"),
                                   value: videoValue, level: HealthRules.video(m), advice: s("sheets.health.advice.video")))

        let speedValue: String
        if !m.hasMeasurements {
            speedValue = s("sheets.health.value.notStarted")
        } else if m.subtitleLines == 0 {
            speedValue = s("sheets.health.value.noSubtitle")
        } else if let median = m.medianTranslationMs {
            speedValue = HealthText.s("sheets.health.value.speed %@ %d", locale,
                                      String(format: "%.1f", locale: locale, Double(median) / 1000), m.translatedLines)
        } else {
            speedValue = HealthText.s("sheets.health.value.allReady %d", locale, m.subtitleLines)
        }
        rows.append(HealthCheckRow(
            id: "speed", symbol: "globe", title: s("sheets.health.row.speed"), value: speedValue,
            level: HealthRules.translation(m),
            advice: m.usesOnlineOrLocalEngine ? s("sheets.health.advice.speedEngine") : s("sheets.health.advice.speedMac")))
        rows.append(translatorRow(state, locale: locale))

        let tvValue: String
        if !m.subtitlesOnTV {
            tvValue = s("sheets.health.value.tvNotUsed")
        } else if !m.translating {
            tvValue = s("sheets.health.value.notStarted")
        } else {
            tvValue = s(m.connectedTVs > 0 ? "sheets.health.value.connected" : "sheets.health.value.notConnected")
                + (HealthText.lastTVDrop(state.health.lastTVDrop, locale, now: now).map { "\n" + $0 } ?? "")
        }
        rows.append(HealthCheckRow(id: "tv", symbol: "tv", title: s("sheets.health.row.tv"), value: tvValue,
                                   level: HealthRules.tv(m), advice: s("sheets.health.advice.tv")))

        if let row = tvAppRow(state.sheetsStatus.tvApp, locale: locale) { rows.append(row) }
        return rows
    }

    /// Çevirinin yolu: anahtarlı motor ya da anahtarsız (havuz + bu Mac'in çevirisi), dil paketi durumu.
    static func translatorRow(_ state: AppState, locale: Locale) -> HealthCheckRow {
        let s = { (key: String) in HealthText.s(key, locale) }
        let path = state.translationPath
        let value: String
        var advice: String?
        let packAdvice = HealthText.s("sheets.health.advice.languagePack %@ %@", locale,
                                      HomeStatus.languageName(state.settings.sourceLanguage, locale),
                                      HomeStatus.languageName(state.settings.targetLanguage, locale))
        switch path {
        case .engine(let engine):
            value = HealthText.s("sheets.health.path.engine %@", locale, HomeStatus.engineName(engine))
        case .poolAndDevice: value = s("sheets.health.path.poolAndDevice")
        case .deviceOnly: value = s("sheets.health.path.deviceOnly")
        case .poolOnly(let packMissing):
            value = s(packMissing ? "sheets.health.path.poolOnly.pack" : "sheets.health.path.poolOnly.unsupported")
            advice = packMissing ? packAdvice : s("sheets.health.advice.addKey")
        case .none(let packMissing):
            value = s(packMissing ? "sheets.health.path.none.pack" : "sheets.health.path.none.unsupported")
            advice = packMissing ? packAdvice : s("sheets.health.advice.addKey")
        }
        return HealthCheckRow(id: "translator", symbol: "character.bubble", title: s("sheets.health.row.translator"),
                              value: value, level: path.level, advice: advice)
    }

    /// Yapılacak bir şey yoksa satır yok (bilinmiyor, kuruluyor, giriş, parola bekleniyor).
    static func tvAppRow(_ app: TVAppHealth, locale: Locale) -> HealthCheckRow? {
        let s = { (key: String) in HealthText.s(key, locale) }
        let title = s("sheets.health.row.tvApp")
        let symbol = "square.and.arrow.down.on.square"
        switch app {
        case .unknown, .installing, .samsungSignIn, .waitingForPassword:
            return nil
        case .installed(let version):
            return HealthCheckRow(id: "tvApp", symbol: symbol, title: title,
                                  value: HealthText.s("sheets.health.tvApp.installed %@", locale, version), level: .good)
        case .waitingForApproval:
            return HealthCheckRow(id: "tvApp", symbol: symbol, title: title, value: s("sheets.health.tvApp.approval"),
                                  level: .fair, advice: s("sheets.health.tvApp.approvalAdvice"))
        case .developerModeOff:
            return HealthCheckRow(id: "tvApp", symbol: symbol, title: title, value: s("sheets.health.tvApp.notInstalled"),
                                  level: .fair, advice: s("sheets.health.tvApp.developerModeAdvice"))
        case .failed(_, _, let message):
            return HealthCheckRow(id: "tvApp", symbol: symbol, title: title, value: s("sheets.health.tvApp.failed"),
                                  level: .problem, advice: message)
        case .hostIPMismatch(let tv, let mac):
            return HealthCheckRow(id: "tvApp", symbol: symbol, title: title, value: s("sheets.health.tvApp.notInstalled"),
                                  level: .fair,
                                  advice: HealthText.s("sheets.health.tvApp.hostIPAdvice %@ %@", locale, tv, mac))
        }
    }
}
