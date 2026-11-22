// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

/**
 * Bir ek alanın kararlılık kuralları (okuma.md 11). İzi değişmeyen alan yeniden okunmaz. Yazı ancak kararlıysa
 * çevrilir: ya iz bir tur değişmedi ya da iki okuma aynı yazıyı verdi. Okuma hatası eski kutuyu bırakır; yazı
 * değişmedikçe yeniden çevrilmez; boşalan alanın kutusu kalkar.
 */
class ExtraAreaTracker {
    sealed interface Decision {
        data object Nothing : Decision
        /** Yazı kararlı: çevrilsin. [parts] cümle parçaları. */
        data class Translate(val parts: List<String>, val box: LiveBox?, val lineHeight: Double?) : Decision
        data object Clear : Decision
    }

    private var trace: CoarseTrace? = null
    private var lastRead: Reading? = null
    private var decided: String? = null

    private data class Reading(val text: String, val parts: List<String>, val box: LiveBox?, val lineHeight: Double?)

    /** Tur başı: true ise alan okunmalı; false ise iz aynı, okuma gerekmez ([unchangedRound] kararını verir). */
    fun shouldRead(t: CoarseTrace): Boolean {
        if (t == trace && lastRead != null) return false
        trace = t
        return true
    }

    /** İz değişmedi: bekleyen yazı bu tur kararlı sayılır. */
    fun unchangedRound(): Decision {
        val r = lastRead ?: return Decision.Nothing
        return decide(r)
    }

    /** Okuma sonucu; [lines] null ise okuma hata verdi (kutu kalır, sonraki turda yeniden okunur). */
    fun onRead(lines: List<LiveLine>?, region: LiveRegion): Decision {
        if (lines == null) { trace = null; return Decision.Nothing }
        val kept = AreaLines.filter(lines)
        val parts = AreaLines.joinParts(kept.map { it.text })
        val boxes = kept.mapNotNull { it.box?.let(region::toFrame) }
        val box = boxes.takeIf { it.isNotEmpty() }?.reduce(LiveBox::union)
        val lh = boxes.map { it.height }.sorted().let { if (it.isEmpty()) null else it[it.size / 2] }
        val r = Reading(parts.joinToString("\n"), parts, box, lh)
        val prev = lastRead
        lastRead = r
        return if (prev != null && prev.text == r.text) decide(r) else Decision.Nothing
    }

    private fun decide(r: Reading): Decision {
        if (r.text == decided) return Decision.Nothing
        decided = r.text
        return if (r.text.isEmpty()) Decision.Clear else Decision.Translate(r.parts, r.box, r.lineHeight)
    }

    /** Çeviri gösterilemedi (benzer ya da hata): sonraki kararlı okumada yeniden denensin. */
    fun forget() { decided = null }
}

/** "Ekranı çevir" planı (okuma.md 12): süzülmüş, gruplanmış, en çok 30 grup. Kutular kareye göre. */
object ScreenPlan {
    data class Group(val text: String, val box: LiveBox, val lineHeight: Double, val lines: Int)

    fun groups(lines: List<LiveLine>, max: Int = AreaLines.MAX_SCREEN_GROUPS): List<Group> =
        AreaLines.groupForScreen(AreaLines.filter(lines), max).map { g ->
            val boxes = g.map { it.box!! }
            Group(g.joinToString(" ") { it.text.trim() }, boxes.reduce(LiveBox::union), boxes.map { it.height }.average(), g.size)
        }

    /** TV'ye giden öğe (tv.md `screen`). */
    fun item(g: Group, translation: String): Map<String, Any?> = linkedMapOf(
        "text" to translation,
        "box" to box(g.box),
        "line" to g.lineHeight,
        "paragraphs" to if (g.lines > 1) true else null,
    )

    /** Kalma süresi: bütün kaynak yazıların harfleriyle. */
    fun durationMs(groups: List<Group>): Long = AreaLines.screenDisplayMs(groups.joinToString(" ") { it.text })

    fun box(b: LiveBox): Map<String, Double> = linkedMapOf("left" to b.left, "top" to b.top, "right" to b.right, "bottom" to b.bottom)
}
