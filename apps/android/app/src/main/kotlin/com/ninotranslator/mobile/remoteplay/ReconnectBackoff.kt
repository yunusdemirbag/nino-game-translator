// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.remoteplay

/** Yeniden bağlanma bekleyişi: 2, 4, 8, 16, 30, 30… sn. Bağlanınca ya da elle başlatınca sıfırlanır. */
class ReconnectBackoff {
    private var attempt = 0

    fun nextDelayMs(): Long {
        val sec = if (attempt >= STEPS.size) MAX_SEC else STEPS[attempt]
        attempt++
        return sec * 1000L
    }

    fun reset() { attempt = 0 }

    companion object {
        private val STEPS = longArrayOf(2, 4, 8, 16, 30)
        private const val MAX_SEC = 30L
    }
}

/** Çözücü türü: Samsung yazılımla başlar; görüntüsüz oturum sayısı tekse tür ters çevrilir. */
object DecoderChoice {
    fun preferSoftware(manufacturer: String?): Boolean = manufacturer?.trim()?.equals("samsung", ignoreCase = true) == true

    fun startWithSoftware(manufacturer: String?, noPictureSessions: Int): Boolean =
        preferSoftware(manufacturer) xor (noPictureSessions % 2 == 1)
}

/** Kayıtlı adres yanıt vermeyince ağda bulunanlardan PS5 seçimi: aynı adlı tek PS5, yoksa ağdaki tek PS5. */
object HostRelocation {
    fun pick(found: List<FoundPs5>, savedName: String?): FoundPs5? {
        val same = if (savedName.isNullOrBlank()) emptyList() else found.filter { it.name == savedName }
        if (same.size == 1) return same[0]
        if (same.isEmpty() && found.size == 1) return found[0]
        return null
    }
}
