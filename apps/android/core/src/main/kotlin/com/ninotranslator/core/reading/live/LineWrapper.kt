// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

/** Telefondaki altyazı ekranı için satır kaydırma (okuma.md 14). */
object LineWrapper {
    const val MAX_CHARS = 42
    const val MAX_LINES = 3
    const val MIN_SCALE = 0.75
    const val MIN_PHONE_MS = 1200L

    data class Wrapped(val lines: List<String>, val scale: Double) {
        val text: String get() = lines.joinToString("\n")
    }

    fun wrap(text: String, maxChars: Int = MAX_CHARS, maxLines: Int = MAX_LINES): Wrapped {
        if (text.length <= maxChars || text.contains('\n')) return Wrapped(listOf(text), 1.0)
        val words = units(text)
        var best: List<String>? = null
        for (n in 2..maxLines) {
            val c = balanced(words, n) ?: continue
            best = c
            if (c.maxOf { it.length } <= maxChars) return Wrapped(c, 1.0)
        }
        val lines = best ?: listOf(text)
        val longest = lines.maxOf { it.length }
        return Wrapped(lines, (maxChars.toDouble() / longest).coerceIn(MIN_SCALE, 1.0))
    }

    /** Sözcükler; konuşan adı ("ARTHUR:") sonraki sözcükle birlikte tutulur. */
    private fun units(text: String): List<String> {
        val t = LiveText.tokens(text)
        val sp = SpeakerPrefix.parse(text)
        if (sp == null || t.size < 2) return t
        val nameWords = sp.name.split(' ').size
        if (t.size <= nameWords) return t
        return listOf(t.subList(0, nameWords + 1).joinToString(" ")) + t.drop(nameWords + 1)
    }

    /** En uzun satırı en kısa yapan bölme; eşitlikte kareler toplamı küçük olan. */
    private fun balanced(words: List<String>, n: Int): List<String>? {
        if (words.size < n) return null
        var best: List<String>? = null
        var bestMax = Int.MAX_VALUE; var bestSq = Long.MAX_VALUE
        fun consider(lines: List<String>) {
            val mx = lines.maxOf { it.length }
            val sq = lines.sumOf { it.length.toLong() * it.length }
            if (mx < bestMax || (mx == bestMax && sq < bestSq)) { best = lines; bestMax = mx; bestSq = sq }
        }
        fun join(a: Int, b: Int) = words.subList(a, b).joinToString(" ")
        if (n == 2) for (i in 1 until words.size) consider(listOf(join(0, i), join(i, words.size)))
        else for (i in 1 until words.size - 1) for (j in i + 1 until words.size)
            consider(listOf(join(0, i), join(i, j), join(j, words.size)))
        return best
    }

    /** Telefon ekranındaki süre: bildirilen (en az 1200 ms) ya da en çok 8000, 2000 + harf × 60. */
    fun phoneDisplayMs(text: String, reportedMs: Long? = null): Long =
        reportedMs?.coerceAtLeast(MIN_PHONE_MS) ?: LiveTranslationQueue.lateDisplayMs(text)
}
