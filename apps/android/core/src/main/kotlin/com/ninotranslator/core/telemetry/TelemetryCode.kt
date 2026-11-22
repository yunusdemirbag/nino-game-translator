// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.telemetry

/**
 * Ölçüm hata kodları (tarif: NinoCore docs/tarif/olcum.md). Liste kapalı değildir; yeni kod `alan.konu.sebep`
 * biçiminde eklenir. Hata mesajı, istisna metni ya da dosya yolu asla kod yerine gitmez: [clean] onları reddeder.
 */
object TelemetryCode {
    // PS5
    const val PS5_DISCOVER_NONE = "ps5.discover.none"
    const val PS5_DISCOVER_TIMEOUT = "ps5.discover.timeout"
    const val PS5_REGISTER_FAILED = "ps5.register.failed"
    const val PS5_AUTH_EXPIRED = "ps5.auth.expired"
    const val PS5_AUTH_REJECTED = "ps5.auth.rejected"
    const val PS5_AUTH_PASSCODE = "ps5.auth.passcode"
    const val PS5_SESSION_TIMEOUT = "ps5.session.timeout"
    const val PS5_SESSION_BUSY = "ps5.session.busy"
    const val PS5_SESSION_STANDBY = "ps5.session.standby"
    const val PS5_REMOTE_BLOCKED = "ps5.remote.blocked"
    const val PS5_REMOTE_DISABLED = "ps5.remote.disabled"
    const val PS5_STREAM_DECODER = "ps5.stream.decoder"
    const val PS5_STREAM_NO_PICTURE = "ps5.stream.nopicture"
    const val PS5_OTHER = "ps5.other"

    /** PS5 / TV kopma sebepleri (`ps5_drop.code`, `tv_drop.code`). */
    object Drop {
        const val NETWORK_LOST = "network_lost"
        const val PS5_CLOSED = "ps5_closed"
        /** Eski ad; TV için [CLOSED] gönderilir (sunucu `tv_closed`'u `closed` sayar). */
        const val TV_CLOSED = "tv_closed"
        /** Karşı taraf bağlantıyı kapattı (TV). */
        const val CLOSED = "closed"
        /** Gönderilemedi (soket yazma hatası). */
        const val WRITE_ERROR = "write_error"
        /** Uygulama arka plandan öne geldi, bağlantı yenilendi. */
        const val RESUME = "resume"
        /** Cihazın ağı değişti. */
        const val NETWORK_CHANGE = "network_change"
        const val TIMEOUT = "timeout"
        const val STALLED = "stalled"
        const val STANDBY = "standby"
        const val KICKED = "kicked"
        const val OTHER = "other"
    }

    // TV
    const val TV_DISCOVER_NONE = "tv.discover.none"
    const val TV_CONNECT_REFUSED = "tv.connect.refused"
    const val TV_CONNECT_TIMEOUT = "tv.connect.timeout"
    const val TV_PROTOCOL_MISMATCH = "tv.protocol.mismatch"
    const val TV_OVERLAY_DENIED = "tv.overlay.denied"
    const val TV_OTHER = "tv.other"

    // Okuma ve çeviri
    const val OCR_FAILED = "ocr.failed"
    const val OCR_TIMEOUT = "ocr.timeout"
    const val PROVIDER_HTTP = "tr.provider.http"
    const val PROVIDER_TIMEOUT = "tr.provider.timeout"
    const val PROVIDER_QUOTA = "tr.provider.quota"
    const val PROVIDER_AUTH = "tr.provider.auth"
    const val PROVIDER_OFFLINE = "tr.provider.offline"
    /** Satırın bütün çevirmenleri başarısız oldu (cihaz içi yedek dahil). */
    const val LINE_FAILED = "tr.line.failed"
    const val POOL_UNREACHABLE = "tr.pool.unreachable"
    const val PACK_CORRUPT = "tr.pack.corrupt"
    const val ON_DEVICE_MISSING = "tr.ondevice.missing"

    // Uygulama
    const val SETTINGS_CORRUPT = "app.settings.corrupt"
    const val STORAGE_FULL = "app.storage.full"
    const val UPDATE_FAILED = "app.update.failed"
    const val CAPTURE_DENIED = "app.capture.denied"
    const val NETWORK_OFFLINE = "app.network.offline"
    /** Remote Play yerel kitaplığı yüklenemedi. */
    const val NATIVE_MISSING = "app.native.missing"
    /** Çeviri oturumu kurulamadı (beklenmeyen hata). */
    const val SESSION_SETUP = "app.session.setup"
    /** Altyazı sunucusunun kapısı başka uygulamada. */
    const val PORT_BUSY = "app.port.busy"

    /** Çökme kodu bilinmiyorsa. */
    const val UNCLEAN_EXIT = "unclean_exit"

    private val CODE = Regex("^[A-Za-z0-9_.$-]{1,64}$")
    private val PLACE = Regex("^[A-Za-z0-9_.:$<>+-]{1,120}$")

    /** Kod kurala uyuyorsa kendisi, uymuyorsa null. */
    fun clean(raw: String?): String? = raw?.takeIf { CODE.matches(it) }

    /** Çökme yeri: yalnız sembol adı. Boşluk, `/`, `\` ya da başka işaret varsa null (dosya yolu gitmesin). */
    fun cleanWhere(raw: String?): String? = raw?.takeIf { PLACE.matches(it) }

    /**
     * Yakalanmamış istisnanın kodu: yalnız sınıf adı (mesajı değil). Bellek yetmezliği `oom`.
     * 64 karakteri aşan sınıf adı paket kısmı atılarak kısaltılır.
     */
    fun ofThrowable(t: Throwable): String {
        if (t is OutOfMemoryError) return "oom"
        val name = t.javaClass.name
        return clean(name) ?: clean(name.substringAfterLast('.')) ?: UNCLEAN_EXIT
    }

    /** Uygulamanın kendi kodundaki en üst çerçeve: `Sınıf.yöntem` (paket ve dosya adı yok). */
    fun whereOf(t: Throwable, ownPackage: String = "com.ninotranslator."): String? {
        var e: Throwable? = t
        var depth = 0
        while (e != null && depth < 8) {
            val frame = e.stackTrace.firstOrNull { it.className.startsWith(ownPackage) }
            if (frame != null) return cleanWhere(frame.className.substringAfterLast('.') + "." + frame.methodName)
            e = e.cause
            depth++
        }
        return null
    }
}
