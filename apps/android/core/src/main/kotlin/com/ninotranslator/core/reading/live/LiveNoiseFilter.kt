// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Canlı gürültü süzgeci (okuma.md 4, adım 1–10). Satırlar bölgeye göre kutuyla gelir; çıktı alt alta
 * satırlardır. Eskiyen satır için durum tutar; tek iş parçacığında kullanılır.
 */
class LiveNoiseFilter(
    private val log: (String) -> Unit = {},
) {
    private val firstSeen = HashMap<String, Long>()
    private val loggedGiants = ArrayDeque<String>()

    /**
     * @param region okunan bölge (kutuları kareye çevirmek için)
     * @param taskLine görev şeridi çizgisi ([TaskStripLine.compute]); null = sınır yok
     */
    fun filter(lines: List<LiveLine>, region: LiveRegion, nowMs: Long, taskLine: Double? = TaskStripLine.DEFAULT): LiveReading {
        // OCR yukarıdan aşağı vermeyebilir: üst kenara göre sırala, boşları at.
        var ls = lines.filter { it.text.isNotBlank() }.map { it.copy(text = it.text.trim()) }
            .sortedBy { it.box?.top ?: Double.MAX_VALUE }
        fun frame(l: LiveLine) = l.box?.let(region::toFrame)

        // 1. Harf sayısı.
        ls = ls.filter { LiveText.letterCount(it.text) >= 2 }
        // 2. Görev şeridi çizgisi.
        if (taskLine != null) ls = applyTaskLine(ls, ::frame, taskLine)
        // 3. Eskiyen satır.
        ls = dropStale(ls, nowMs)
        // 4. Dev satır.
        ls = ls.filter { l ->
            val h = frame(l)?.height ?: return@filter true
            val giant = h > 0.13 || (h > 0.075 && isLabelLike(l.text))
            if (giant) logGiant(l.text)
            !giant
        }
        // 5–6. Kumanda ipucu, yol tarifi.
        ls = ls.filter { !ControllerHints.isHint(it.text) && !Directions.isDirection(it.text) }
        // 7. Sözcük çöpü.
        ls = ls.map { it.copy(text = WordCleanup.clean(it.text)) }.filter { LiveText.letterCount(it.text) >= 2 }
        // 8. Yan yana parçalar.
        ls = mergeSideBySide(ls)
        // 9. Blok seçme.
        if (ls.isEmpty()) return LiveReading.EMPTY
        if (ls.any { it.box == null }) return LiveReading(ls)
        val block = selectBlock(ls, region) ?: return LiveReading.EMPTY
        // 10. Dev blok.
        val fb = block.map { region.toFrame(it.box!!) }.reduce(LiveBox::union)
        if (block.size > 5 || fb.height > 0.26) return LiveReading.EMPTY
        return LiveReading(block)
    }

    fun reset() { firstSeen.clear() }

    private fun applyTaskLine(ls: List<LiveLine>, frame: (LiveLine) -> LiveBox?, line: Double): List<LiveLine> {
        val out = ArrayList<LiveLine>()
        var lastSpeaker: LiveBox? = null
        for (l in ls) {
            val f = frame(l)
            if (f == null) { out += l; continue }
            if (SpeakerPrefix.parse(l.text) != null) { out += l; lastSpeaker = f; continue }
            val sp = lastSpeaker
            lastSpeaker = null
            if (f.top < line) { out += l; continue }
            if (sp != null && f.top - sp.bottom <= max(0.02, f.height * 1.5)) out += l
        }
        return out
    }

    private fun dropStale(ls: List<LiveLine>, now: Long): List<LiveLine> {
        val keys = ls.map { LiveText.key(it.text) }
        firstSeen.keys.retainAll(keys.toSet())
        for (k in keys) firstSeen.putIfAbsent(k, now)
        // NinoCore adım 12: 9 sn'ye ulaşan satır eskidir (yeni: süre < 9 sn).
        val stale = keys.map { now - (firstSeen[it] ?: now) >= STALE_MS }
        if (stale.all { it } || stale.none { it }) return ls
        return ls.filterIndexed { i, _ -> !stale[i] }
    }

    private fun isLabelLike(text: String) = LiveText.tokens(text).size <= 4 && text.none { it in ".,!?…" }

    private fun logGiant(text: String) {
        if (text in loggedGiants) return
        loggedGiants.addLast(text)
        while (loggedGiants.size > 32) loggedGiants.removeFirst()
        log("dev satır atıldı: $text")
    }

    companion object {
        const val STALE_MS = 9000L

        /** Aynı satırdaki parçaları soldan sağa birleştirir (adım 8). */
        fun mergeSideBySide(ls: List<LiveLine>): List<LiveLine> {
            val out = ArrayList<LiveLine>()
            val used = BooleanArray(ls.size)
            for (i in ls.indices) {
                if (used[i]) continue
                val b0 = ls[i].box
                if (b0 == null) { out += ls[i]; continue }
                val row = arrayListOf(ls[i]); used[i] = true
                var grew = true
                while (grew) {
                    grew = false
                    val rb = row.map { it.box!! }.reduce(LiveBox::union)
                    for (j in ls.indices) {
                        if (used[j]) continue
                        val b = ls[j].box ?: continue
                        val ov = min(rb.bottom, b.bottom) - max(rb.top, b.top)
                        val small = min(row.minOf { it.box!!.height }, b.height)
                        val gap = max(b.left - rb.right, rb.left - b.right)
                        if (ov >= 0.6 * small && gap <= 0.05) { row += ls[j]; used[j] = true; grew = true }
                    }
                }
                val sorted = row.sortedBy { it.box!!.left }
                out += LiveLine(sorted.joinToString(" ") { it.text }, sorted.map { it.box!! }.reduce(LiveBox::union))
            }
            return out.sortedBy { it.box?.top ?: Double.MAX_VALUE }
        }

        /** Satırları alt alta bloklara ayırır (adım 9; kutular gerekir). */
        fun blocks(ls: List<LiveLine>): List<List<LiveLine>> {
            val out = ArrayList<ArrayList<LiveLine>>()
            for (l in ls.sortedBy { it.box!!.top }) {
                val b = l.box!!
                val target = out.lastOrNull { blk ->
                    val p = blk.last().box!!
                    val gap = b.top - p.bottom
                    val ov = min(p.right, b.right) - max(p.left, b.left)
                    gap < 0.8 * max(p.height, b.height) && ov >= 0.5 * min(p.width, b.width)
                }
                if (target != null) target += l else out += arrayListOf(l)
            }
            return out
        }

        private fun isMenu(blk: List<LiveLine>) =
            blk.size >= 3 && blk.all { LiveText.tokens(it.text).size <= 3 } && blk.none { LiveText.endsSentence(it.text) }

        fun selectBlock(ls: List<LiveLine>, region: LiveRegion): List<LiveLine>? {
            val cands = blocks(ls).filterNot(::isMenu)
            fun fb(blk: List<LiveLine>) = blk.map { region.toFrame(it.box!!) }.reduce(LiveBox::union)
            val centred = cands.filter { abs(fb(it).midX - 0.5) <= 0.12 }
            centred.maxByOrNull { fb(it).bottom }?.let { return it }
            return cands.filter { blk -> blk.sumOf { LiveText.tokens(it.text).size } >= 3 }.maxByOrNull { fb(it).bottom }
        }
    }
}
