// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import kotlin.math.max
import kotlin.math.min

/** Ek alanlar ve "ekranı çevir" için satır süzme ve gruplama (okuma.md 11–12). */
object AreaLines {
    const val MAX_SCREEN_GROUPS = 30
    const val EXTRA_READ_INTERVAL_MS = 1000L

    /** Kumanda ipuçları ve çöpler atılır; en az 2 harf ve 2 harfli bir sözcük kalmalı. */
    fun filter(lines: List<LiveLine>): List<LiveLine> = lines
        .filter { !ControllerHints.isHint(it.text) }
        .map { it.copy(text = WordCleanup.clean(it.text)) }
        .filter { l -> LiveText.letterCount(l.text) >= 2 && LiveText.tokens(l.text).any { t -> t.count { it.isLetter() } >= 2 } }

    /**
     * Ek alan satırlarını parçalara birleştirir. Önceki parça cümleyi bitirdiyse ya da kısa bir
     * başlıksa (en çok 3 sözcük, virgülsüz) ve yeni satır büyük harfle başlıyorsa yeni parça başlar.
     */
    fun joinParts(lines: List<String>): List<String> {
        val out = ArrayList<String>()
        for (l in lines.map { it.trim() }.filter { it.isNotEmpty() }) {
            val prev = out.lastOrNull()
            val upper = l.firstOrNull { it.isLetter() }?.isUpperCase() == true
            val heading = prev != null && LiveText.tokens(prev).size <= 3 && !prev.contains(',')
            if (prev == null || (upper && (LiveText.endsSentence(prev) || heading))) out += l
            else out[out.size - 1] = "$prev $l"
        }
        return out
    }

    /** Çevirisi aslıyla 0.90 ve üstü benzeyen alan/grup gösterilmez. */
    fun worthShowing(source: String, translation: String) = LiveText.similarity(source, translation) < LiveStabilizer.ALREADY_TRANSLATED

    /** Ekran çevirisinin kalma süresi: en az 12000, en çok 60000, 8000 + harf × 50. */
    fun screenDisplayMs(text: String): Long = (8000L + LiveText.letterCount(text) * 50L).coerceIn(12000L, 60000L)

    /**
     * Ekranı çevir: kutulu satırları yerlerine göre gruplar (en çok 30 grup). Satır üstündeki grubun
     * son satırına şu koşullarla katılır: boşluk satır boyunun 0.8 katından az, yatay örtüşme dar olanın
     * en az yarısı, boylar en çok 1.6 kat farklı. İki ayrı grubu birden örten geniş satır katılmaz.
     */
    fun groupForScreen(lines: List<LiveLine>, maxGroups: Int = MAX_SCREEN_GROUPS): List<List<LiveLine>> {
        val groups = ArrayList<ArrayList<LiveLine>>()
        for (l in lines.filter { it.box != null }.sortedBy { it.box!!.top }) {
            val b = l.box!!
            val fits = groups.filter { g ->
                val p = g.last().box!!
                val gap = b.top - p.bottom
                val ov = min(p.right, b.right) - max(p.left, b.left)
                val ratio = max(p.height, b.height) / min(p.height, b.height).coerceAtLeast(1e-9)
                gap < 0.8 * max(p.height, b.height) && gap > -0.5 * min(p.height, b.height) &&
                    ov >= 0.5 * min(p.width, b.width) && ratio <= 1.6
            }
            val spans = groups.count { g ->
                val p = g.last().box!!
                b.top - p.bottom < 0.8 * max(p.height, b.height) && b.top >= p.top && min(p.right, b.right) - max(p.left, b.left) > 0
            }
            if (fits.size == 1 && spans <= 1) fits[0] += l else groups += arrayListOf(l)
        }
        return groups.take(maxGroups)
    }
}
