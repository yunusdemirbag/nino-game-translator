// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.remoteplay

/** chiaki-ng'nin `ChiakiQuitReason` değerleri (sayılar kütüphanede sabittir). */
object QuitReason {
    const val NONE = 0
    const val STOPPED = 1
    const val SESSION_REQUEST_UNKNOWN = 2
    const val SESSION_REQUEST_CONNECTION_REFUSED = 3
    const val SESSION_REQUEST_RP_IN_USE = 4
    const val SESSION_REQUEST_RP_CRASH = 5
    const val SESSION_REQUEST_RP_VERSION_MISMATCH = 6
    const val CTRL_UNKNOWN = 7
    const val CTRL_CONNECT_FAILED = 8
    const val CTRL_CONNECTION_REFUSED = 9
    const val STREAM_CONNECTION_UNKNOWN = 10
    const val STREAM_CONNECTION_REMOTE_DISCONNECTED = 11
    const val STREAM_CONNECTION_REMOTE_SHUTDOWN = 12
    const val PSN_REGIST_FAILED = 13
}

/** Oturumun bitiş türü. [retry] false ise döngüye girilmez, kullanıcı uyarılır. */
enum class EndKind(val retry: Boolean) {
    STOPPED(false),
    IN_USE(true),
    REFUSED(true),
    NETWORK(true),
    REGISTRATION_INVALID(false),
    REMOTE_PLAY_DISABLED(false),
    REJECTED(true),
    OTHER(true),
}

/** Sınıflanmış bitiş: tür, varsa PS5 kodu ve kütüphanenin metni. */
data class SessionEnd(val kind: EndKind, val appCode: Long? = null, val text: String? = null)

object SessionEndReasons {
    private val REASON = Regex("Reported Application Reason:\\s*0x([0-9a-fA-F]+)")
    private val NETWORK_LINES = listOf(
        "Session request connect failed eventually",
        "Failed to send session request",
        "Failed to receive session request response",
    )
    private const val UNKNOWN_SESSION_REQUEST = "Unknown Session Request Error"

    /** Kaba grup + "Session Request" içeren diğerlerinde oturumun hata satırları (eskiden yeniye). */
    fun classify(reason: Int, text: String?, errorLines: List<String>): SessionEnd {
        val group = when (reason) {
            QuitReason.STOPPED -> EndKind.STOPPED
            QuitReason.SESSION_REQUEST_RP_IN_USE -> EndKind.IN_USE
            QuitReason.SESSION_REQUEST_CONNECTION_REFUSED, QuitReason.CTRL_CONNECTION_REFUSED,
            QuitReason.PSN_REGIST_FAILED -> EndKind.REFUSED
            QuitReason.STREAM_CONNECTION_REMOTE_DISCONNECTED, QuitReason.STREAM_CONNECTION_REMOTE_SHUTDOWN,
            QuitReason.CTRL_CONNECT_FAILED, QuitReason.STREAM_CONNECTION_UNKNOWN -> EndKind.NETWORK
            else -> EndKind.OTHER
        }
        if (group != EndKind.OTHER || text == null || !text.contains("Session Request")) {
            return SessionEnd(group, text = text)
        }
        var found: SessionEnd? = null
        for (line in errorLines) {
            val m = REASON.find(line)
            if (m != null) {
                val code = m.groupValues[1].toLongOrNull(16) ?: continue
                found = when (code) {
                    0x80108b12L -> SessionEnd(EndKind.REMOTE_PLAY_DISABLED, code, text)
                    0x80108b09L, 0x80108b02L, 0x80108b26L -> SessionEnd(EndKind.REGISTRATION_INVALID, code, text)
                    else -> SessionEnd(EndKind.REJECTED, code, text)
                }
            } else if (NETWORK_LINES.any { line.contains(it) }) {
                found = SessionEnd(EndKind.NETWORK, text = text)
            }
        }
        if (found != null) return found
        if (text == UNKNOWN_SESSION_REQUEST) return SessionEnd(EndKind.REJECTED, text = text)
        return SessionEnd(EndKind.OTHER, text = text)
    }

    /**
     * Kullanıcıya gösterilecek strings anahtarı. Son aramada PS5 yanıt vermediyse ve neden "ağ" ya da "diğer"
     * ise "bulunamadı" gösterilir.
     */
    fun phaseKey(end: SessionEnd, lastSearchAnswered: Boolean, host: String?): String? = when {
        end.kind == EndKind.STOPPED -> null
        !lastSearchAnswered && (end.kind == EndKind.NETWORK || end.kind == EndKind.OTHER) ->
            if (host.isNullOrBlank()) "phase_not_found" else "phase_not_found_host"
        else -> when (end.kind) {
            EndKind.IN_USE -> "phase_in_use"
            EndKind.REFUSED -> "phase_refused"
            EndKind.NETWORK -> "phase_network"
            EndKind.REGISTRATION_INVALID -> "phase_registration_invalid"
            EndKind.REMOTE_PLAY_DISABLED -> "phase_remote_play_disabled"
            EndKind.REJECTED -> if (end.appCode != null) "phase_rejected_code" else "phase_rejected"
            EndKind.OTHER -> "phase_reconnecting"
            EndKind.STOPPED -> null
        }
    }

    /** Anahtarın biçim değeri (%1$s): kodlu redde `0x%08x`, bulunamadıda adres, diğerinde kütüphane metni. */
    fun phaseDetail(key: String?, end: SessionEnd, host: String?): String? = when (key) {
        "phase_rejected_code" -> end.appCode?.let { String.format("0x%08x", it) }
        "phase_not_found_host" -> host
        "phase_reconnecting" -> end.text
        else -> null
    }
}
