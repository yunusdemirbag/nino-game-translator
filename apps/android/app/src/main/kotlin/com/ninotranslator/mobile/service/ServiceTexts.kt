// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

/** Yerelleştirilecek metin: strings anahtarı + isteğe bağlı %1$s değeri. */
data class TextRef(val key: String, val arg: String? = null)

/**
 * Hizmetin metin anahtarları (servis.md 2.1). Metinler yalnız `res/values` (Türkçe) ve `res/values-en`'de durur;
 * [ServiceStrings] arayüz dilinde okur. Kaynaklar kendi anahtarlarını da verir (`SessionEndReasons`,
 * `CaptureCardSource`, `XboxTexts`); hepsi [ALL]'da.
 */
object ServiceTexts {
    const val PREPARING = "phase_preparing"
    const val CONNECTING = "phase_connecting"
    const val CAPTURE_OPENING = "capture_phase_opening"
    const val XBOX_CONNECTING = "xbox_phase_connecting"
    const val STREAMING = "phase_streaming"
    const val RECONNECTING = "phase_reconnecting"

    const val ERROR_NOT_PAIRED = "error_not_paired"
    const val ERROR_NATIVE = "error_native"
    const val ERROR_XBOX_SIGN_IN = "error_xbox_sign_in"
    const val ERROR_SOURCE_UNAVAILABLE = "error_source_unavailable"
    const val ERROR_MODEL = "error_model"
    const val ERROR_TRANSLATION = "error_translation"
    const val ERROR_PORT = "error_port"

    const val SCREEN_TRANSLATING = "screen_translating"
    const val SCREEN_NO_PICTURE = "screen_no_picture"
    const val SCREEN_NO_TEXT = "screen_no_text"
    const val SCREEN_FAILED = "screen_failed"

    const val NOTIF_CHANNEL = "notif_channel_translation"
    const val NOTIF_TITLE = "notif_translation_title"
    const val NOTIF_PS5 = "notif_translation_ps5"
    const val NOTIF_CAPTURE = "notif_translation_capture"
    const val NOTIF_XBOX = "notif_translation_xbox"
    const val NOTIF_DEBUG = "notif_translation_debug"
    const val NOTIF_STOP = "notif_translation_stop"

    /** PS5 bağlantısının neden anahtarları (`SessionEndReasons`). */
    val PS5_REASONS = listOf(
        "phase_in_use", "phase_not_found_host", "phase_not_found", "phase_network", "phase_registration_invalid",
        "phase_remote_play_disabled", "phase_rejected_code", "phase_rejected", "phase_no_picture", "phase_asleep",
        "phase_passcode", "phase_passcode_incorrect", "phase_refused",
    )

    /** Biçimli (`%1$s` alan) anahtarlar. */
    val WITH_ARG = setOf("phase_not_found_host", "phase_rejected_code", ERROR_PORT, SCREEN_FAILED, "xbox_phase_stopped", "xbox_error_unexpected")

    /** Hizmetin gösterebileceği bütün anahtarlar (Xbox'unkiler `XboxTexts`'te). */
    val ALL: List<String> = listOf(
        PREPARING, CONNECTING, CAPTURE_OPENING, XBOX_CONNECTING, STREAMING, RECONNECTING,
        ERROR_NOT_PAIRED, ERROR_NATIVE, ERROR_XBOX_SIGN_IN, ERROR_SOURCE_UNAVAILABLE, ERROR_MODEL, ERROR_TRANSLATION, ERROR_PORT,
        SCREEN_TRANSLATING, SCREEN_NO_PICTURE, SCREEN_NO_TEXT, SCREEN_FAILED,
        NOTIF_CHANNEL, NOTIF_TITLE, NOTIF_PS5, NOTIF_CAPTURE, NOTIF_XBOX, NOTIF_DEBUG, NOTIF_STOP,
        CaptureCardSource.KEY_NOT_FOUND, CaptureCardSource.KEY_NO_PERMISSION, CaptureCardSource.KEY_BLACK,
    ) + PS5_REASONS

    fun notificationText(kind: SourceKind): String = when (kind) {
        SourceKind.REMOTE_PLAY -> NOTIF_PS5
        SourceKind.CAPTURE_CARD -> NOTIF_CAPTURE
        SourceKind.XBOX -> NOTIF_XBOX
        SourceKind.DEBUG_FRAMES -> NOTIF_DEBUG
    }
}

/** Kaynağın durumundan aşama metni (servis.md 2.1). */
object PhaseTexts {
    fun phase(state: SourceState, kind: SourceKind): TextRef? = when (state) {
        SourceState.Idle -> null
        SourceState.Preparing -> TextRef(ServiceTexts.PREPARING)
        SourceState.Connecting -> TextRef(when (kind) {
            SourceKind.CAPTURE_CARD -> ServiceTexts.CAPTURE_OPENING
            SourceKind.XBOX -> ServiceTexts.XBOX_CONNECTING
            else -> ServiceTexts.CONNECTING
        })
        SourceState.Streaming -> TextRef(ServiceTexts.STREAMING)
        is SourceState.Reconnecting -> TextRef(state.reasonKey, state.detail)
        is SourceState.Failed -> TextRef(state.reasonKey, state.detail)
    }

    fun isCaptureProblem(key: String) = key.startsWith("capture_") && key != ServiceTexts.CAPTURE_OPENING
}

/**
 * "Bağlanamama nedeni" ve yakalama kartı hata kartı (servis.md 2.2). Aşama her turda değişirken neden ana ekranda
 * bir görünüp bir kaybolmasın diye ayrıca tutulur.
 */
class ConnectReasonBook {
    /** Ana ekranda kalan neden. */
    var reason: TextRef? = null; private set
    /** Yakalama kartı sorunu (hata kartında gösterilir). */
    var captureProblem: TextRef? = null; private set

    fun onState(state: SourceState) {
        val key = when (state) {
            is SourceState.Reconnecting -> state.reasonKey
            is SourceState.Failed -> state.reasonKey
            else -> null
        }
        // Kart sorunu olmayan bir sonraki durumda kart kalkar.
        if (key == null || !PhaseTexts.isCaptureProblem(key)) captureProblem = null
        when (state) {
            SourceState.Streaming -> reason = null
            is SourceState.Reconnecting, is SourceState.Failed -> {
                val detail = if (state is SourceState.Reconnecting) state.detail else (state as SourceState.Failed).detail
                when {
                    PhaseTexts.isCaptureProblem(key!!) -> captureProblem = TextRef(key, detail)
                    // Nedeni bilinmeyen genel kopma: önceki neden kalır.
                    key == ServiceTexts.RECONNECTING && detail.isNullOrBlank() -> Unit
                    else -> reason = TextRef(key, detail)
                }
            }
            // Bağlanırken ve hazırlanırken önceki neden korunur; kullanıcı durdurunca da.
            else -> Unit
        }
    }

    fun reset() { reason = null; captureProblem = null }
}

/**
 * Ana ekrandaki tek hata kartı: birden çok sorun aynı anda olabilir, önemlisi gösterilir.
 * Sıra: ön koşul / kart > port > model > çeviri.
 */
class ErrorBook {
    private val active = LinkedHashMap<String, TextRef>()

    fun set(key: String, ref: TextRef? = TextRef(key)) { if (ref == null) active.remove(key) else active[key] = ref }
    fun clear(key: String) { active.remove(key) }
    fun has(key: String) = key in active

    val top: TextRef? get() {
        val order = listOf(ServiceTexts.ERROR_PORT, ServiceTexts.ERROR_MODEL, ServiceTexts.ERROR_TRANSLATION)
        return active.entries.firstOrNull { it.key !in order }?.value ?: order.firstNotNullOfOrNull { active[it] }
    }

    fun reset() = active.clear()
}
