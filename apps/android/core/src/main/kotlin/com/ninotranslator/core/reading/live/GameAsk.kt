// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

/**
 * "Hangi oyunu oynuyorsunuz?" kartı (servis.md 4, okuma.md 13). Her 15 sn'de bir [check] çağrılır: oyun hâlâ
 * bilinmiyorsa, çeviri en az 2 dakikadır sürüyorsa, "oyunu sor" ve ortak havuz açıksa oturumda bir kez açılır. Oyun
 * bir yoldan tanınınca kart kapanır. "Sorma" bu oturumda bir daha sormaz; "Değiştir" kartı elle açar.
 */
class GameAskCard(private val startedAtMs: Long) {
    var open = false; private set
    private var askedOnce = false
    private var dismissed = false
    private var manual = false

    /** Kart durumu değiştiyse true. */
    fun check(nowMs: Long, gameKnown: Boolean, askGame: Boolean, sharePool: Boolean): Boolean {
        val before = open
        if (gameKnown && open && !manual) open = false
        else if (!open && !askedOnce && !dismissed && !gameKnown && askGame && sharePool && nowMs - startedAtMs >= AFTER_MS) {
            open = true; askedOnce = true
        }
        return before != open
    }

    /** Oyun tanındı (her yoldan): elle açılmadıysa kart kapanır. */
    fun onGameKnown(): Boolean { if (open && !manual) { open = false; return true }; return false }

    /** "Değiştir": kart elle açılır (oyun bilinse de). */
    fun openManually() { open = true; manual = true; askedOnce = true }

    /** Seçim yapıldı ya da kapatıldı. [neverAgain] "Sorma". */
    fun close(neverAgain: Boolean) { open = false; manual = false; if (neverAgain) dismissed = true }

    companion object {
        const val AFTER_MS = 120_000L
        const val CHECK_MS = 15_000L

        /** Öneriler: önce bu konsolda son seçilen, sonra kurulu paketlerin oyun adları (tekrarsız, en çok 8). */
        fun suggestions(lastGame: String?, packTitles: List<String>, max: Int = 8): List<String> {
            val out = ArrayList<String>()
            for (n in listOfNotNull(lastGame) + packTitles) {
                val t = n.trim()
                if (t.isEmpty() || out.any { GameNames.sameGame(it, t) }) continue
                out += t
                if (out.size >= max) break
            }
            return out
        }
    }
}

/**
 * Ekrandan oyun tanıma kapısı (okuma.md 13, ceviri.md 6.7): ortak havuz açık, elle oyun seçilmemiş, deneme
 * görüntüsü değil ve oyun paket aramasından belli değilken; zamanlama [com.ninotranslator.core.pool.IdentifySchedule].
 */
object ScreenIdentifyGate {
    fun allowed(sharePool: Boolean, manualGame: Boolean, fromClip: Boolean, ps5Game: Boolean, packGame: Boolean): Boolean =
        sharePool && !manualGame && !fromClip && !ps5Game && !packGame

    /** Küçültülmüş genişlik: en çok 768. */
    fun scaledSize(width: Int, height: Int, maxW: Int = 768): Pair<Int, Int> {
        if (width <= maxW) return width to height
        val h = (height.toLong() * maxW / width).toInt().coerceAtLeast(1)
        return maxW to h
    }
}
