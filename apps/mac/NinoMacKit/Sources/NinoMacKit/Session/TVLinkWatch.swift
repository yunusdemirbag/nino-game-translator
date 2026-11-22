// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// TV bağlantı olaylarının günlük satırı ve sağlık notu (tekrarlayan kopma: otomatik teşhis `tv.flapping`).
enum TVLinkText {
    /// `altyazi.log` satırı: olay, adres, yol, süre, neden (zamanı günlük kendisi yazar).
    static func logLine(_ e: DisplayLinkEvent) -> String {
        let kind: String
        switch e.kind {
        case .connected: kind = "TV bağlandı"
        case .disconnected: kind = "TV koptu"
        case .timedOut: kind = "TV zaman aşımı"
        }
        var parts = ["\(kind): adres \(e.host)", "yol \(e.route.rawValue)"]
        if let d = e.duration { parts.append("süre \(Int(d.rounded())) sn") }
        if let r = e.reason { parts.append("neden \(r.rawValue)") }
        if let m = e.model { parts.append("model \(RotatingLog.quote(m))") }
        if let v = e.appVersion { parts.append("TV uygulaması \(v)") }
        return parts.joined(separator: ", ")
    }

    /// Sağlık satırındaki kaba neden. Uyanıştan sonraki 60 sn içindeki kopma "uyandı" sayılır.
    static func cause(_ r: DisplayLinkEvent.Reason, at: Date, wokeAt: Date?) -> TVDropNote.Cause {
        if let wokeAt, at >= wokeAt, at.timeIntervalSince(wokeAt) <= 60 { return .resume }
        switch r {
        case .peerClosed, .replaced: return .closed
        case .writeStalled, .heartbeatTimeout: return .timeout
        case .readFailed, .writeFailed, .protocolError, .serverStopped, .localClose: return .network
        }
    }
}

extension LiveEngine {
    /// Çeviri başladı: oturumdan önce bağlanmış TV'ler için de `tv_connect` (bekleme 0) gider.
    func tvLinksSessionStarted(at now: Date = Date()) {
        meteredTVLinks = []
        for e in liveTVLinks.values.sorted(by: { $0.at < $1.at }) {
            var c = e
            c.at = now
            meteredTVLinks.insert(e.connectionID)
            meter?.tvLink(c, brand: Self.telemetryBrand(state.pairedTV), wokeAt: lastWake)
        }
    }

    /// Her TV bağlantı olayı: günlüğe bir satır; çeviri sürerken ölçüm, sağlık notu ve otomatik teşhis.
    func tvLinkEvent(_ e: DisplayLinkEvent) {
        subtitleLog.write(TVLinkText.logLine(e))
        if e.kind == .connected { liveTVLinks[e.connectionID] = e } else { liveTVLinks[e.connectionID] = nil }
        guard state.isTranslating else { return }
        // Ölçümde her kopmanın önünde aynı bağlantının `tv_connect`'i olur.
        if e.kind == .connected {
            meteredTVLinks.insert(e.connectionID)
            meter?.tvLink(e, brand: Self.telemetryBrand(state.pairedTV), wokeAt: lastWake)
        } else if meteredTVLinks.remove(e.connectionID) != nil {
            meter?.tvLink(e, brand: Self.telemetryBrand(state.pairedTV), wokeAt: lastWake)
        }
        // Tekrarlayan kopma otomatik teşhisin `tv.flapping` kuralıdır (10 dk'da 3 kopma; DiagWatch).
        diagTVLink(e)
        guard e.kind != .connected, let reason = e.reason, !reason.isLocal else { return }
        state.sheetsStatus.healthMetrics.tvDrops += 1
        state.health.lastTVDrop = TVDropNote(date: e.at, cause: TVLinkText.cause(reason, at: e.at, wokeAt: lastWake))
    }
}
