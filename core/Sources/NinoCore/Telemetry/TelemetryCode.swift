// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Hata kodları (tarif: docs/tarif/olcum.md). Liste kapalı değildir; yeni kod `alan.konu.sebep` biçiminde eklenir.
/// Hata mesajı, istisna metni ya da dosya yolu asla kod yerine gönderilmez: `clean` onları reddeder.
public enum TelemetryCode {
    // PS5
    public static let ps5DiscoverNone = "ps5.discover.none"
    public static let ps5DiscoverTimeout = "ps5.discover.timeout"
    public static let ps5RegisterFailed = "ps5.register.failed"
    public static let ps5AuthExpired = "ps5.auth.expired"
    public static let ps5AuthRejected = "ps5.auth.rejected"
    public static let ps5SessionTimeout = "ps5.session.timeout"
    public static let ps5SessionBusy = "ps5.session.busy"
    public static let ps5SessionStandby = "ps5.session.standby"
    public static let ps5RemoteBlocked = "ps5.remote.blocked"
    public static let ps5StreamDecoder = "ps5.stream.decoder"
    public static let ps5Other = "ps5.other"

    /// PS5 / TV kopma sebepleri (`ps5_drop.code`, `tv_drop.code`).
    public enum Drop {
        public static let networkLost = "network_lost"
        public static let ps5Closed = "ps5_closed"
        /// TV kopmaları (tarif tablosu). `tvClosed` eski adıdır, sunucu `closed` sayar.
        public static let closed = "closed"
        public static let writeError = "write_error"
        public static let resume = "resume"
        public static let networkChange = "network_change"
        /// Başka bir gönderici TV'yi aldı.
        public static let replaced = "replaced"
        public static let tvClosed = "tv_closed"
        public static let timeout = "timeout"
        public static let stalled = "stalled"
        public static let standby = "standby"
        public static let kicked = "kicked"
        public static let other = "other"
    }

    // TV
    public static let tvDiscoverNone = "tv.discover.none"
    public static let tvConnectRefused = "tv.connect.refused"
    public static let tvConnectTimeout = "tv.connect.timeout"
    public static let tvProtocolMismatch = "tv.protocol.mismatch"
    public static let tvOverlayDenied = "tv.overlay.denied"
    public static let tvOther = "tv.other"

    // Okuma ve çeviri
    public static let ocrFailed = "ocr.failed"
    public static let ocrTimeout = "ocr.timeout"
    public static let providerHTTP = "tr.provider.http"
    public static let providerTimeout = "tr.provider.timeout"
    public static let providerQuota = "tr.provider.quota"
    public static let providerAuth = "tr.provider.auth"
    public static let providerOffline = "tr.provider.offline"
    public static let poolUnreachable = "tr.pool.unreachable"
    public static let packCorrupt = "tr.pack.corrupt"
    public static let onDeviceMissing = "tr.ondevice.missing"

    // Uygulama
    public static let settingsCorrupt = "app.settings.corrupt"
    public static let storageFull = "app.storage.full"
    public static let updateFailed = "app.update.failed"
    public static let captureDenied = "app.capture.denied"
    public static let networkOffline = "app.network.offline"

    private static let code = try! NSRegularExpression(pattern: #"^[A-Za-z0-9_.$-]{1,64}$"#)
    private static let place = try! NSRegularExpression(pattern: #"^[A-Za-z0-9_.:$<>+-]{1,120}$"#)

    /// Kod kurala uyuyorsa kendisi, uymuyorsa nil.
    public static func clean(_ raw: String?) -> String? {
        guard let raw, matches(code, raw) else { return nil }
        return raw
    }

    /// Çökme yeri: yalnız sembol adı. Boşluk, `/`, `\` ya da başka işaret varsa nil (dosya yolu gitmesin).
    public static func cleanWhere(_ raw: String?) -> String? {
        guard let raw, matches(place, raw) else { return nil }
        return raw
    }

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
}
