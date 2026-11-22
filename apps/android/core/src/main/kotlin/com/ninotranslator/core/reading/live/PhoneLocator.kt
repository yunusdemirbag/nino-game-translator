// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import kotlin.math.abs
import kotlin.math.roundToInt

/** Oyundaki telefonun ekranı (0–1 oranları). [slope] sol kenarın eğimi (piksel/piksel); [dark] koyu temalı uygulama. */
data class PhoneRect(val box: LiveBox, val slope: Double = 0.0, val dark: Boolean = false, val guessed: Boolean = false)

/**
 * Oyundaki telefonu bulma (okuma.md 9; yalnız GTA 6). Kare 240×135 renkli küçültülmüş hâliyle verilir. Her satırda
 * telefon genişliğinde beyaz (koyu temada koyu) şerit aranır; şeritlerin sol kenarı bir doğru olmalıdır.
 * Saat dışarıdan verilir; bulunamayan karede son yer en çok 3 sn tutulur.
 */
class PhoneLocator {
    private var last: PhoneRect? = null
    private var lastSeenMs = Long.MIN_VALUE / 2

    /** Telefon ya da null. [appWordsSeen] telefon uygulamasının sözcükleri okundu (yer tahmini için). */
    fun locate(img: RgbImage, nowMs: Long, appWordsSeen: Boolean = false, wordsMidX: Double? = null): PhoneRect? {
        val found = find(img)
        if (found != null) { last = found; lastSeenMs = nowMs; return found }
        val prev = last
        if (prev != null && !prev.guessed && nowMs - lastSeenMs <= HOLD_MS && stillThere(img, prev)) return prev
        if (appWordsSeen) {
            val mid = (wordsMidX ?: prev?.box?.midX ?: 0.5).coerceIn(GUESS_W / 2, 1 - GUESS_W / 2)
            return PhoneRect(LiveBox(mid - GUESS_W / 2, 0.20, mid + GUESS_W / 2, 0.82), guessed = true)
        }
        return null
    }

    fun reset() { last = null; lastSeenMs = Long.MIN_VALUE / 2 }

    companion object {
        const val HOLD_MS = 3_000L
        const val GUESS_W = 0.21

        private const val WHITE_MIN = 118
        private const val WHITE_SPREAD = 45
        private const val SIDE_DARK = 90
        private const val GAP = 3
        /** Ekran öbeğinin en az doluluğu (sohbet balonları ve fotoğraf satırları boşluk bırakır). */
        private const val FILL = 0.30
        /** Aydınlık sahnede gölgedeki telefon için ek aydınlatma. */
        const val SHADE_LIFT = 1.3
        /** Koyu temada gövde (tarif: ≥ 85); ekranın kenarından en çok 10 nokta, üst/alt 3 satır içinde aranır. */
        private const val BODY = 85
        private const val BODY_X = 10
        private const val BODY_Y = 3

        fun isWhite(img: RgbImage, x: Int, y: Int) = img.minChannel(x, y) >= WHITE_MIN && img.spread(x, y) <= WHITE_SPREAD
        private fun isDarkScreen(img: RgbImage, x: Int, y: Int) = img.minChannel(x, y) + img.spread(x, y) <= 75

        /** Karede telefon (karanlık karede aydınlatılıp yeniden; koyu tema ayrı denenir). */
        fun find(img: RgbImage): PhoneRect? {
            search(img, dark = false)?.let { return it }
            val p = brightPercentile(img)
            if (p in 40..117) search(img.scaled(225.0 / p), dark = false)?.let { return it }
            // Gölgedeki telefon (aydınlık sahnede ekran gri kalır): ek olarak biraz aydınlatılıp yeniden aranır.
            if (p > 117) search(img.scaled(SHADE_LIFT), dark = false)?.let { return it }
            search(img, dark = true)?.let { return it }
            // Gölgedeki koyu temalı telefon: ekran asıl karede, gövde aydınlatılmış karede ölçülür.
            return if (p > 117) search(img, dark = true, body = img.scaled(SHADE_LIFT)) else null
        }

        /** Ortadaki %95'lik dilimin üst ucu (parlaklık). */
        fun brightPercentile(img: RgbImage): Int {
            val hist = IntArray(256)
            for (y in 0 until img.height) for (x in 0 until img.width) hist[img.luma(x, y)]++
            val target = (img.width * img.height * 0.975).toInt()
            var acc = 0
            for (v in 0..255) { acc += hist[v]; if (acc >= target) return v }
            return 255
        }

        private data class Run(val y: Int, val left: Int, val right: Int)

        /** Tanı için: reddedilen adayların nedeni (testler). */
        @Volatile internal var debugLog: ((String) -> Unit)? = null

        /**
         * Satırdaki şeritler. İnce yazı çizgileri (≤3 nokta) şeridi bölmez. Ekranın yanındaki açık çerçeve ya da açık zemin
         * ince bir koyu çizgiyle ayrılıp şeride katılabildiği için birleşen öbeğin her alt parçası da şerit başı ve sonu
         * sayılır (en ve boy sınırı içinde).
         */
        private fun runs(img: RgbImage, y: Int, dark: Boolean, minW: Int, maxW: Int): List<Run> {
            // Ham parçalar (hiç boşluk birleştirmeden).
            val segs = ArrayList<IntArray>()
            var start = -1
            // Koyu ekranda başlamış şeridin içindeki beyaz yazı da şerittir.
            fun on(x: Int) = if (dark) isDarkScreen(img, x, y) || (start >= 0 && img.minChannel(x, y) >= 110) else isWhite(img, x, y)
            for (x in 0..img.width) {
                val hit = x < img.width && on(x)
                if (hit) { if (start < 0) start = x; continue }
                if (start >= 0) { segs += intArrayOf(start, x - 1); start = -1 }
            }
            val out = ArrayList<Run>()
            var g0 = 0
            while (g0 < segs.size) {
                var g1 = g0
                while (g1 + 1 < segs.size && segs[g1 + 1][0] - segs[g1][1] - 1 <= GAP) g1++
                // Öbek g0..g1; her alt parça başı → her alt parça sonu.
                for (i in g0..g1) for (j in i..g1) {
                    val w = segs[j][1] - segs[i][0] + 1
                    if (w > maxW) break
                    if (w >= minW) out += Run(y, segs[i][0], segs[j][1])
                }
                g0 = g1 + 1
            }
            return out
        }

        private fun search(img: RgbImage, dark: Boolean, body: RgbImage = img): PhoneRect? {
            val W = img.width; val H = img.height
            val minW = (W * 0.12).roundToInt(); val maxW = (W * 0.30).roundToInt()
            // Satır → şerit başı → şerit sonları.
            val byRow = Array(H) { y -> runs(img, y, dark, minW, maxW).groupBy({ it.left }, { it.right }) }
            if (byRow.sumOf { it.size } < 8) return null
            // Sol kenar doğrusu: eğimler 0..±0.30, 0.02 adım; her satır bir oy.
            data class Cand(val slope: Double, val x0: Int, val votes: Int)
            val cands = ArrayList<Cand>()
            var s = -0.30
            while (s <= 0.3001) {
                val votes = HashMap<Int, Int>()
                for (y in 0 until H) byRow[y].keys.map { (it - s * y).roundToInt() }.toSet().forEach { votes[it] = (votes[it] ?: 0) + 1 }
                votes.filter { it.value >= 8 }.forEach { (k, v) -> cands += Cand(s, k, v) }
                s += 0.02
            }
            // Her aday için ekranın satırları; en çok 32 aday (en uzun kesintisiz ekranlar önce) sınanır.
            val scored = cands.map { c -> c to rowsFor(byRow, c.slope, c.x0) }.filter { it.second.size >= 8 }
                .sortedByDescending { it.second.size }
            for ((c, rows) in scored.take(32)) check(img, rows, c.slope, dark, body)?.let { return it }
            return null
        }

        /**
         * Sol doğruya uyan satırlar. Sağ kenar sol kenara koşuttur: en çok satırda görülen en seçilir; satırın şeridi en az
         * bu en kadar olmalıdır (parlama ya da açık zemin taşabilir). Satırın yeri sol doğru ve bu en ile verilir.
         */
        private fun rowsFor(byRow: Array<Map<Int, List<Int>>>, slope: Double, x0: Int): List<Run> {
            val widths = HashMap<Int, Int>()
            val found = ArrayList<Pair<Int, List<Int>>>()
            for (y in byRow.indices) {
                val l = x0 + slope * y
                val ws = HashSet<Int>()
                for (k in kotlin.math.ceil(l - 1.5).toInt()..kotlin.math.floor(l + 1.5).toInt()) byRow[y][k]?.forEach { ws += (it - l).roundToInt() }
                if (ws.isEmpty()) continue
                found += y to ws.toList()
                ws.forEach { widths[it] = (widths[it] ?: 0) + 1 }
            }
            val best = widths.keys.maxByOrNull { k -> (-1..1).sumOf { widths[k + it] ?: 0 } * 1000 + k } ?: return emptyList()
            val rows = found.filter { (_, ws) -> ws.any { it >= best - 2 } }.map { (y, _) -> val l = (x0 + slope * y).roundToInt(); Run(y, l, l + best) }
            return block(rows)
        }

        /**
         * Ekran kesintisiz bir dikdörtgendir: uyan satırlar boşluklarına göre öbeklenir, en uzun öbek
         * alınır (pencere pervazı, perde gibi aralıklı beyazlar telefon sayılmaz). Sohbetteki fotoğraf boşluğu bölmesin
         * diye boşluk karenin %20'sine kadar kabul edilir, ama öbeğin en az %60'ı dolu olmalıdır.
         */
        private fun block(rows: List<Run>): List<Run> {
            if (rows.isEmpty()) return rows
            val H = RgbImage.PHONE_H
            val maxGap = (H * 0.20).toInt()
            val groups = ArrayList<ArrayList<Run>>()
            for (r in rows) { val g = groups.lastOrNull(); if (g != null && r.y - g.last().y <= maxGap) g += r else groups += arrayListOf(r) }
            val g = groups.maxBy { it.size }
            val span = g.last().y - g.first().y + 1
            return if (g.size >= span * FILL) g else emptyList()
        }

        private fun check(img: RgbImage, rows: List<Run>, slope: Double, dark: Boolean, bodyImg: RgbImage): PhoneRect? {
            val r = checkWhy(img, rows, slope, dark, bodyImg)
            if (r is String) { debugLog?.invoke("slope=%.2f dark=%s rows=%d %s".format(slope, dark, rows.size, r)); return null }
            return r as PhoneRect
        }

        private fun checkWhy(img: RgbImage, rows: List<Run>, slope: Double, dark: Boolean, bodyImg: RgbImage): Any {
            if (rows.size < 8) return "az satır"
            val W = img.width.toDouble(); val H = img.height.toDouble()
            val top = rows.first().y; val bottom = rows.last().y
            val left = rows.minOf { it.left }.coerceAtLeast(0); val right = rows.maxOf { it.right }.coerceAtMost(img.width - 1)
            val height = (bottom - top + 1) / H
            if (height !in 0.38..0.86) return "boy %.2f (%d–%d)".format(height, top, bottom)
            // Oran ekranın kendi eniyle (eğik telefonda kutunun eni değil, satırın eni).
            val aspect = (bottom - top + 1).toDouble() / (rows.first().right - rows.first().left + 1)
            if (aspect !in 1.2..2.6) return "oran %.2f".format(aspect)
            val mid = (left + right + 1) / 2.0 / W
            if (mid !in 0.30..0.80) return "orta %.2f".format(mid)
            if (top / H < 0.04) return "üst"
            fun side(r: Run, dx: Int): Int? { val x = if (dx < 0) r.left + dx else r.right + dx; return if (x in 0 until img.width) x else null }
            if (!dark) {
                val darkSides = rows.count { r -> listOfNotNull(side(r, -2), side(r, 2)).let { xs -> xs.size == 2 && xs.all { img.minChannel(it, r.y) < SIDE_DARK } } }
                val notWhite = rows.count { r -> listOfNotNull(side(r, -2), side(r, 2)).all { !isWhite(img, it, r.y) } }
                // Koyu çerçeve: ekranın hemen dışında (1–3 nokta) koyu nokta (en koyu kanal < 90).
                val frame = rows.count { r -> (1..3).flatMap { listOfNotNull(side(r, -it), side(r, it)) }.any { img.minChannel(it, r.y) < SIDE_DARK } }
                val n = rows.size.toDouble()
                if (darkSides / n < 0.70 && !(notWhite / n >= 0.85 && frame / n >= 0.35)) return "yanlar koyu=%.2f beyazdeğil=%.2f çerçeve=%.2f x=%d–%d y=%d–%d".format(darkSides / n, notWhite / n, frame / n, left, right, top, bottom)
            } else {
                // Gövde: ekranın koyu kenarlığından sonra (1–6 nokta içinde) iki yanda açık gövde (≥ 85).
                fun bodyAt(r: Run, dir: Int) = (1..BODY_X).mapNotNull { side(r, dir * it) }.any { x -> (maxOf(0, r.y - BODY_Y)..minOf(img.height - 1, r.y + BODY_Y)).any { bodyImg.minChannel(x, it) >= BODY } }
                val body = rows.count { r -> bodyAt(r, -1) && bodyAt(r, 1) }
                // Beyaz yazı: 240 noktalık karede ince yazı satır atlayabildiği için komşu satırlara da bakılır.
                val text = rows.count { r -> (maxOf(0, r.y - 1)..minOf(img.height - 1, r.y + 1)).any { y -> (maxOf(0, r.left)..minOf(img.width - 1, r.right)).any { img.minChannel(it, y) >= 110 } } }
                val n = rows.size.toDouble()
                if (body / n < 0.70 || text / n < 0.15) return "koyu gövde=%.2f yazı=%.2f x=%d–%d y=%d–%d".format(body / n, text / n, left, right, top, bottom)
                if ((bottom + 1) / H > 0.96) return "koyu alt"
            }
            return PhoneRect(LiveBox(left / W, top / H, (right + 1) / W, (bottom + 1) / H), slope, dark)
        }

        /** Son yerde aynı tür ekran duruyor mu (beyazda %45, koyuda %50). */
        fun stillThere(img: RgbImage, p: PhoneRect): Boolean {
            val b = p.box
            val x0 = (b.left * img.width).toInt().coerceIn(0, img.width - 1); val x1 = (b.right * img.width).toInt().coerceIn(0, img.width - 1)
            val y0 = (b.top * img.height).toInt().coerceIn(0, img.height - 1); val y1 = (b.bottom * img.height).toInt().coerceIn(0, img.height - 1)
            var n = 0; var hit = 0
            for (y in y0..y1) for (x in x0..x1) { n++; if (if (p.dark) isDarkScreen(img, x, y) else isWhite(img, x, y)) hit++ }
            if (n == 0) return false
            return hit.toDouble() / n >= if (p.dark) 0.50 else 0.45
        }
    }
}
