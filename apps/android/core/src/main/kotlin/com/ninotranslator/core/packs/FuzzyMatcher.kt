// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.packs

import com.ninotranslator.core.translation.LineText

/** Tek paket içinde bulanık arama (ceviri.md 9.4): önce tek OCR düzeltmesi, sonra imza. */
object FuzzyMatcher {
    private val PAIRS = listOf(
        "rn" to "m", "m" to "rn", "cl" to "d", "d" to "cl", "vv" to "w", "ri" to "n", "n" to "ri", "li" to "h",
        "l" to "i", "i" to "l", "1" to "l", "1" to "i", "0" to "o", "5" to "s", "j" to "i", "c" to "e", "e" to "c",
        "a" to "o", "o" to "a", "h" to "b", "b" to "h", "f" to "t", "t" to "f", "u" to "v", "v" to "u", "y" to "v", "q" to "g",
    )

    /** Adım 1: tek düzeltmeyle olabilecek hâllerin tam anahtarı. Bütün bulunanlar aynı Türkçeye çıkmalı. */
    fun singleCorrection(text: String, pack: LegacyPack): String? {
        val canon = PackKey.canonical(text)
        val n = canon.codePointCount(0, canon.length)
        if (n < 6 || n > 48) return null
        val variants = LinkedHashSet<String>()
        for ((from, to) in PAIRS) {
            var at = canon.indexOf(from)
            while (at >= 0) {
                variants += canon.substring(0, at) + to + canon.substring(at + from.length)
                at = canon.indexOf(from, at + 1)
            }
        }
        for (i in canon.indices) {
            if (canon[i] == ' ') {
                variants += canon.substring(0, i) + canon.substring(i + 1) // iki sözcük birleşir
            } else {
                variants += (canon.substring(0, i) + canon.substring(i + 1)).replace("  ", " ").trim() // bir harf düşer
                if (i > 0 && canon[i - 1] != ' ') variants += canon.substring(0, i) + " " + canon.substring(i) // sözcük bölünür
            }
        }
        variants.remove(canon)
        var found: String? = null
        for (v in variants) {
            if (v.isEmpty()) continue
            val t = pack.anyLine(PackKey.longOfCanonical(v)) ?: continue
            if (found == null) found = t else if (found != t) return null
        }
        return found
    }

    data class Hit(val key: Long, val text: String, val score: Double)

    /** Adım 2: imza ile arama. */
    fun signature(text: String, pack: LegacyPack): Hit? {
        val index = pack.fuzzy ?: return null
        val folded = FuzzySignature.fold(text)
        val len = FuzzySignature.lengthOf(folded)
        if (len < FuzzySignature.MIN_LENGTH) return null
        val damaged = FuzzySignature.isDamaged(text)
        val threshold = FuzzySignature.threshold(len, damaged)
        val qBits = FuzzySignature.bitsFor(len)
        val query = FuzzySignature.bloom(folded, qBits)
        val cand = LongArray(4)
        val qFold = HashMap<Int, LongArray>()
        fun q(bits: Int) = qFold.getOrPut(bits) { FuzzySignature.foldTo(query, bits) }

        var best: Hit? = null
        val near = ArrayList<Hit>()
        for (i in 0 until index.size) {
            val cl = index.lengths[i]
            if (Math.abs(cl - len) * 4 > len) continue
            val bits = minOf(qBits, index.bits(i))
            index.bloomInto(i, bits, cand)
            val score = FuzzySignature.similarity(q(bits), cand.copyOf(bits / 64))
            if (score < threshold - FuzzySignature.MARGIN) continue
            val tr = pack.anyLine(index.keys[i]) ?: continue
            val hit = Hit(index.keys[i], tr, score)
            near += hit
            if (best == null || score > best.score || (score == best.score && java.lang.Long.compareUnsigned(hit.key, best.key) > 0)) best = hit
        }
        if (best != null && best.score >= threshold) {
            return if (near.any { it.text != best.text && best.score - it.score < FuzzySignature.MARGIN }) null else best
        }
        if (len < 22) return null
        return oneWay(text, folded, len, query, qBits, index, pack)
    }

    /** Tek yönlü kapsama: yarım okuma (satır kısa) ya da fazlalıklı okuma (satır uzun). */
    private fun oneWay(text: String, folded: String, len: Int, query: LongArray, qBits: Int, index: FuzzyIndex, pack: LegacyPack): Hit? {
        val cand = LongArray(4)
        var best: Hit? = null
        val all = ArrayList<Hit>()
        for (i in 0 until index.size) {
            val cl = index.lengths[i]
            if (cl < 22 || cl == len || cl * 20 < len * 11 || cl * 2 > len * 5) continue
            val bits = minOf(qBits, index.bits(i))
            index.bloomInto(i, bits, cand)
            val c = cand.copyOf(bits / 64)
            val qq = FuzzySignature.foldTo(query, bits)
            val pq = FuzzySignature.popcount(qq); val pc = FuzzySignature.popcount(c)
            val inter = FuzzySignature.intersection(qq, c)
            val queryShort = len < cl
            val shortBits = if (queryShort) pq else pc
            if (shortBits == 0 || inter * 10 < shortBits * 9) continue
            val inner = if (queryShort) FuzzySignature.coverage(inter, pq, pc, bits) else FuzzySignature.coverage(inter, pc, pq, bits)
            val outer = if (queryShort) FuzzySignature.coverage(inter, pc, pq, bits) else FuzzySignature.coverage(inter, pq, pc, bits)
            if (inner < 90) continue
            if (queryShort) { if (outer < 25) continue } else {
                if (outer < 55) continue
                if (!clausesCovered(text, index.bloom(i), index.bits(i))) continue
            }
            val tr = pack.anyLine(index.keys[i]) ?: continue
            val hit = Hit(index.keys[i], tr, inner - 10)
            all += hit
            if (best == null || hit.score > best.score || (hit.score == best.score && java.lang.Long.compareUnsigned(hit.key, best.key) > 0)) best = hit
        }
        best ?: return null
        return if (all.any { it.text != best.text && best.score - it.score < FuzzySignature.MARGIN }) null else best
    }

    private val CLAUSE = Regex("[.,;:!?•…]+")
    private val UPPER_WORD = Regex("^\\p{Lu}[\\p{Lu}'’\\-]*$")

    /** Yan cümle denetimi: en az 6 harfli her yan cümlenin üçlülerinin en az %30'u adayda olmalı. */
    internal fun clausesCovered(text: String, bloom: LongArray, bits: Int): Boolean {
        val clauses = CLAUSE.split(text).map { it.trim() }.filter { it.isNotEmpty() }
        if (clauses.size < 2) return true
        for ((n, clause) in clauses.withIndex()) {
            if (LineText.isCornerText(clause)) continue
            if (covered(clause, bloom, bits)) continue
            val words = clause.split(Regex("\\s+")).toMutableList()
            var trimmed = false
            if (n == 0) { var k = 0; while (k < 3 && words.size > 1 && UPPER_WORD.matches(words[0])) { words.removeAt(0); k++; trimmed = true } }
            if (n == clauses.size - 1) { var k = 0; while (k < 3 && words.size > 1 && UPPER_WORD.matches(words.last())) { words.removeAt(words.size - 1); k++; trimmed = true } }
            if (trimmed && covered(words.joinToString(" "), bloom, bits)) continue
            return false
        }
        return true
    }

    private fun covered(clause: String, bloom: LongArray, bits: Int): Boolean {
        val f = FuzzySignature.fold(clause)
        if (FuzzySignature.lengthOf(f) < 6) return true
        val tris = FuzzySignature.trigrams(f)
        if (tris.isEmpty()) return true
        val hits = tris.count { t -> val b = FuzzySignature.bitOf(t, bits); (bloom[b ushr 6] ushr (b and 63)) and 1L == 1L }
        return hits * 10 >= tris.size * 3
    }
}
