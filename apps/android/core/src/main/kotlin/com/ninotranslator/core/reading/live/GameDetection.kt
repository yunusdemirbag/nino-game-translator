// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import com.ninotranslator.core.packs.GameIds
import java.text.Normalizer

/** Oyun algılama yardımcıları (okuma.md 13). */
object GameNames {
    private val TITLE_ID = Regex("^[A-Z]{4}\\d{5}(_00)?$")
    const val MAX_NAME = 120
    private val ROMAN = mapOf(
        "i" to "1", "ii" to "2", "iii" to "3", "iv" to "4", "v" to "5", "vi" to "6", "vii" to "7", "viii" to "8",
        "ix" to "9", "x" to "10", "xi" to "11", "xii" to "12", "xiii" to "13", "xiv" to "14", "xv" to "15", "xvi" to "16",
    )
    private val SHORT = listOf("grand theft auto" to "gta", "call of duty" to "cod", "red dead redemption" to "rdr")

    /** PS5 kimliği: dört büyük harf + beş rakam, isteğe bağlı "_00". */
    fun isPs5TitleId(id: String): Boolean = TITLE_ID.matches(id)

    /** PS5'in bildirdiği ad: denetim karakterleri atılır, en çok 120 karakter. */
    fun cleanReportedName(name: String): String = name.filterNot { it.isISOControl() }.trim().take(MAX_NAME)

    /** Karşılaştırma için sade ad: "Grand Theft Auto VI" = "GTA 6". */
    fun normalize(name: String): String {
        var s = Normalizer.normalize(name, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").lowercase()
        s = s.replace('ı', 'i')
        s = s.replace(Regex("[^a-z0-9]+"), " ").trim()
        // Harf ve rakam ayrılır.
        s = s.replace(Regex("(?<=[a-z])(?=\\d)|(?<=\\d)(?=[a-z])"), " ")
        s = s.split(' ').filter { it.isNotEmpty() }.joinToString(" ") { ROMAN[it] ?: it }
        for ((long, short) in SHORT) s = s.replace(long, short)
        return s.replace(Regex("\\s+"), " ").trim()
    }

    /** Aynı oyun: sade ad ya da asıl kimlik tutuyor ("GTA 6" = "pool-gta-6"). */
    fun sameGame(a: String, b: String) = normalize(a) == normalize(b) || GameIds.same(a, b)
}

/** Öncelik: PS5 > kullanıcı > paket > ekran. PS5 başka oyun bildirirse kullanıcının seçimi silinir. */
class GameResolver {
    var ps5Game: String? = null; private set
    var userGame: String? = null
    var packGame: String? = null
    var screenGame: String? = null

    fun onPs5Reported(name: String?) {
        val n = name?.let(GameNames::cleanReportedName)?.takeIf { it.isNotEmpty() }
        val u = userGame
        if (n != null && u != null && !GameNames.sameGame(n, u)) userGame = null
        ps5Game = n
    }

    val current: String? get() = ps5Game ?: userGame ?: packGame ?: screenGame
}

/**
 * Paketten tanıma: son 20 gösterilen satırdan en az 5'i yalnız tek bir pakette bulunan anahtarla
 * geldiyse oyun o pakettir. Ortak "genel" paket sayılmaz.
 */
class PackGameGuesser(private val window: Int = 20, private val needed: Int = 5, private val commonPack: String = "genel") {
    private val last = ArrayDeque<String?>()

    /** [packs]: satırın anahtarının bulunduğu paketler. Sonuç: tahmin edilen paket ya da null. */
    fun record(packs: Set<String>): String? {
        val own = packs - commonPack
        last.addLast(if (own.size == 1) own.first() else null)
        while (last.size > window) last.removeFirst()
        return guess()
    }

    fun guess(): String? = last.filterNotNull().groupingBy { it }.eachCount().filter { it.value >= needed }.maxByOrNull { it.value }?.key
}

/** Ekran yazısından GTA 6 işaretleri. */
object Gta6Hints {
    val MAP_BUTTONS = setOf(
        "recenter", "2d view", "3d view", "add marker", "remove marker", "set destination", "remove destination", "close menu",
    )
    val MARKER_VIEW = setOf("view on map", "markers", "cinematic")

    private fun norm(s: String) = s.lowercase().replace(Regex("[^a-z0-9 ]"), " ").replace(Regex("\\s+"), " ").trim()

    /** Harita ekranı: tuş listesinden en az 2 farklı yazı. */
    fun isMapScreen(lines: List<String>): Boolean {
        val all = MAP_BUTTONS + MARKER_VIEW
        val seen = lines.map(::norm).flatMap { l -> all.filter { l.contains(it) } }.toSet()
        return seen.size >= 2
    }

    fun looksLikeGta6(lines: List<String>, phoneRead: Boolean = false): Boolean {
        if (phoneRead || isMapScreen(lines)) return true
        val n = lines.map(::norm)
        val words = n.flatMap { it.split(' ') }.toSet()
        if (n.any { l -> l.split(' ').let { "jason" in it && "lucia" in it } }) return true
        if ("brief" in words && "progress" in words && (words.contains("jason") || words.contains("lucia") || words.contains("map"))) return true
        if ("whatup" in words) return true
        return false
    }
}
