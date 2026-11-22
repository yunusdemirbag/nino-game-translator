// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.remoteplay

/**
 * Görüntü bekçisi: bağlıyken saniyede bir [tick] çağrılır. Saat dışarıdan verilir.
 * - Bağlandıktan sonra 5 sn içinde ilk kare gelmezse takılma (görüntüsüz oturum).
 * - Görüntü gelmişken 8 sn yeni kare gelmezse takılma (aynı çözücüyle yeniden kur).
 * - Art arda 3 görüntüsüz oturumda vazgeç.
 */
class FrameWatchdog(
    private val firstFrameTimeoutMs: Long = 5_000,
    private val stallTimeoutMs: Long = 8_000,
    private val maxNoPictureSessions: Int = 3,
) {
    sealed interface Verdict {
        data object Ok : Verdict
        /** Görüntü gelmişti, durdu: oturumu aynı çözücü türüyle yeniden kur. */
        data object Stalled : Verdict
        /** Bu oturumda hiç görüntü gelmedi: öbür çözücü türüyle yeniden kur. */
        data class NoPicture(val sessions: Int) : Verdict
        /** Art arda çok görüntüsüz oturum: dur, `phase_no_picture`. */
        data class GiveUp(val sessions: Int) : Verdict
    }

    var noPictureSessions = 0
        private set
    var connected = false
        private set
    private var connectedAt = 0L
    private var lastFrameAt = 0L
    private var lastCount = 0L
    private var sawPicture = false

    /** Yeni oturum bağlandı (yerel kare sayacı her oturumda sıfırdan başlar). */
    fun onConnected(nowMs: Long) {
        connected = true
        connectedAt = nowMs
        lastFrameAt = 0
        lastCount = 0
        sawPicture = false
    }

    fun onDisconnected() { connected = false }

    /** Kullanıcı başlatınca ya da elle yeniden bağlanınca. */
    fun resetAll() {
        connected = false
        noPictureSessions = 0
    }

    /** [frameCount]: bu oturumda çözülen toplam kare (seyreltmeden önce). */
    fun tick(nowMs: Long, frameCount: Long): Verdict {
        if (!connected) return Verdict.Ok
        if (frameCount > lastCount) {
            lastCount = frameCount
            lastFrameAt = nowMs
            if (!sawPicture) {
                sawPicture = true
                noPictureSessions = 0
            }
        }
        if (!sawPicture) {
            if (nowMs - connectedAt < firstFrameTimeoutMs) return Verdict.Ok
            connected = false
            noPictureSessions++
            return if (noPictureSessions >= maxNoPictureSessions) Verdict.GiveUp(noPictureSessions)
            else Verdict.NoPicture(noPictureSessions)
        }
        if (nowMs - lastFrameAt >= stallTimeoutMs) {
            connected = false
            return Verdict.Stalled
        }
        return Verdict.Ok
    }
}
