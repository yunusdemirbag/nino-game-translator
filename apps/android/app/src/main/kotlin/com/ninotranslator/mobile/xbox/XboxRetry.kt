// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.xbox

import com.ninotranslator.mobile.data.XboxQuality
import com.ninotranslator.mobile.service.SourceState
import com.ninotranslator.mobile.service.TextRef
import java.io.IOException

/** Bağlantı bitince ne yapılacağı (servis.md 10.5). */
sealed interface XboxNext {
    data class Retry(val delayMs: Long, val problem: XboxProblem) : XboxNext
    /** Denemeler bitti ya da konsol reddetti. */
    data class GiveUp(val problem: XboxProblem) : XboxNext
    /** Yeniden giriş gerekiyor ya da profil yok: hiç denenmez. */
    data class Stop(val problem: XboxProblem) : XboxNext
}

/**
 * Yeniden deneme: 5, 15, 45 sn; üç ardışık denemeden sonra durulur. Yayın en az 60 sn ayakta kaldıysa sayaç sıfırlanır.
 * Saf; saat dışarıdan verilir.
 */
class XboxRetryPolicy(
    private val delaysMs: LongArray = longArrayOf(5_000, 15_000, 45_000),
    private val stableMs: Long = 60_000,
) {
    private var retries = 0
    private var streamingSince: Long? = null

    fun onStreaming(nowMs: Long) { if (streamingSince == null) streamingSince = nowMs }

    fun onEnded(problem: XboxProblem, rejected: Boolean, nowMs: Long): XboxNext {
        val since = streamingSince
        streamingSince = null
        if (since != null && nowMs - since >= stableMs) retries = 0
        if (problem == XboxProblem.SIGN_IN || problem == XboxProblem.NO_PROFILE || problem == XboxProblem.WEBRTC) return XboxNext.Stop(problem)
        if (rejected || retries >= delaysMs.size) return XboxNext.GiveUp(problem)
        return XboxNext.Retry(delaysMs[retries++], problem)
    }

    fun reset() { retries = 0; streamingSince = null }
}

/** Sorunların metin anahtarları (strings; servis.md 10.6). */
object XboxTexts {
    const val SIGN_IN = "xbox_error_sign_in"
    const val NO_PROFILE = "xbox_error_no_account"
    const val GAVE_UP = "xbox_phase_stopped"
    const val WEBRTC = "xbox_error_webrtc"
    /** Kısa aşama metni: Xbox oturumu başlatamadı. */
    const val START_FAILED = "xbox_phase_start_failed"
    /** Çözüm adımları (1080p'deyken 720p önerisiyle). */
    const val START_HELP = "xbox_help_start_failed"
    const val START_HELP_720 = "xbox_help_start_failed_720"

    /** Yeniden denenirken gösterilen metin. */
    fun retryKey(p: XboxProblem): String = when (p) {
        XboxProblem.SIGN_IN -> SIGN_IN
        XboxProblem.NO_PROFILE -> NO_PROFILE
        XboxProblem.UNREACHABLE -> "xbox_phase_unreachable"
        XboxProblem.BUSY -> "xbox_phase_busy"
        XboxProblem.TIMEOUT -> "xbox_phase_timeout"
        XboxProblem.NETWORK -> "xbox_phase_network"
        XboxProblem.SERVICE -> "xbox_phase_service"
        XboxProblem.WEBRTC -> WEBRTC
        XboxProblem.START_FAILED -> START_FAILED
    }

    /** "Xbox bağlantısı kesildi: {neden}" içindeki kısa neden. */
    fun reasonKey(p: XboxProblem): String = when (p) {
        XboxProblem.UNREACHABLE -> "xbox_reason_unreachable"
        XboxProblem.BUSY -> "xbox_reason_busy"
        XboxProblem.TIMEOUT -> "xbox_reason_timeout"
        XboxProblem.NETWORK -> "xbox_reason_network"
        XboxProblem.START_FAILED -> "xbox_reason_start_failed"
        else -> "xbox_reason_service"
    }

    /** Denemeler bitince gösterilen durum: oturum başlatılamadıysa kısa metin (çözüm adımları ayrıca), değilse "sona erdi: {neden}". */
    fun giveUp(p: XboxProblem, reason: (String) -> String): SourceState.Failed =
        if (p == XboxProblem.START_FAILED) SourceState.Failed(START_FAILED) else SourceState.Failed(GAVE_UP, reason(reasonKey(p)))

    /** Kaynak durumu "oturum başlatılamadı" ise ana ekrandaki not karosuna giden çözüm adımları; değilse null. */
    fun help(state: SourceState, quality: XboxQuality): TextRef? {
        if (state !is SourceState.Failed || state.reasonKey != START_FAILED) return null
        return TextRef(if (quality == XboxQuality.P720) START_HELP_720 else START_HELP)
    }

    /** Hesap katmanının hatası → yayın sorunu. */
    fun problemOf(e: Throwable): Pair<XboxProblem, Boolean> = when (e) {
        is XboxStreamException -> e.problem to e.rejected
        is XboxException -> when (e.kind) {
            XboxErrorKind.SIGN_IN, XboxErrorKind.EXPIRED -> XboxProblem.SIGN_IN
            XboxErrorKind.NO_ACCOUNT -> XboxProblem.NO_PROFILE
            XboxErrorKind.OFFLINE -> XboxProblem.NETWORK
            else -> XboxProblem.SERVICE
        } to false
        is IOException -> XboxProblem.NETWORK to false
        else -> XboxProblem.SERVICE to false
    }
}
