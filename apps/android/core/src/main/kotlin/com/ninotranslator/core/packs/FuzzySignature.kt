// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.packs

import java.text.Normalizer

/**
 * Bulanık eşleme imzası (ceviri.md 9.4): OCR'ın karıştırdığı harfler birleşmiş, boşluksuz harf dizisinin
 * üçlülerinden Bloom kümesi. Bit = FNV-1a 64 (üçlünün UTF-8 baytları) mod bit sayısı; baytlar küçük uçlu.
 * Deneme verisi: test/resources/packs/fuzzy-vectors.json.
 */
object FuzzySignature {
    const val MIN_LENGTH = 16
    const val MAX_LENGTH = 255
    const val MARGIN = 5.0
    private val TAG = Regex("<[^<>]{0,40}>")

    /** Katlanmış harf dizisi. */
    fun fold(text: String): String {
        var s = TAG.replace(text, " ")
        s = Normalizer.normalize(s, Normalizer.Form.NFKC).lowercase()
        s = Normalizer.normalize(s, Normalizer.Form.NFD)
        val out = StringBuilder(s.length)
        var i = 0
        while (i < s.length) {
            val cp = s.codePointAt(i)
            i += Character.charCount(cp)
            when (cp) {
                'l'.code, '1'.code, 'ı'.code, 'j'.code -> out.append('i')
                '0'.code -> out.append('o')
                '5'.code -> out.append('s')
                'æ'.code -> out.append('a')
                'ø'.code, 'œ'.code -> out.append('o')
                'ß'.code -> out.append('s')
                else -> if (Character.isLetter(cp)) out.appendCodePoint(cp)
            }
        }
        return out.toString()
    }

    fun lengthOf(folded: String): Int = minOf(MAX_LENGTH, folded.codePointCount(0, folded.length))

    /** Uzunluğa göre bit sayısı: 64'ten başlar, uzunluk × 3 bitleri aştıkça iki katı, en çok 256. */
    fun bitsFor(length: Int): Int {
        var b = 64
        while (length * 3 > b && b < 256) b *= 2
        return b
    }

    fun fnv1a64(bytes: ByteArray): Long {
        var h = -0x340d631b7bdddcdbL // 0xcbf29ce484222325
        for (x in bytes) { h = h xor (x.toLong() and 0xff); h *= 0x100000001b3L }
        return h
    }

    /** Farklı üçlüler (kod noktası). */
    fun trigrams(folded: String): Set<String> {
        val cps = folded.codePoints().toArray()
        val set = LinkedHashSet<String>()
        for (i in 0..cps.size - 3) set += String(cps, i, 3)
        return set
    }

    fun bitOf(trigram: String, bits: Int): Int = java.lang.Long.remainderUnsigned(fnv1a64(trigram.toByteArray(Charsets.UTF_8)), bits.toLong()).toInt()

    /** Bloom kümesi; [bits] 64/128/256. */
    fun bloom(folded: String, bits: Int = bitsFor(lengthOf(folded))): LongArray {
        val words = LongArray(bits / 64)
        for (t in trigrams(folded)) { val b = bitOf(t, bits); words[b ushr 6] = words[b ushr 6] or (1L shl (b and 63)) }
        return words
    }

    /** Küçük uçlu bayt dizisinden Bloom. */
    fun fromBytes(bytes: ByteArray, offset: Int, bits: Int): LongArray {
        val words = LongArray(bits / 64)
        for (i in 0 until bits / 8) words[i ushr 3] = words[i ushr 3] or ((bytes[offset + i].toLong() and 0xff) shl ((i and 7) * 8))
        return words
    }

    fun toBytes(words: LongArray): ByteArray = ByteArray(words.size * 8) { i -> (words[i ushr 3] ushr ((i and 7) * 8)).toByte() }

    /** Daha az bite katlar (bit = h mod bit; bitler ikinin kuvveti olduğundan OR ile katlanır). */
    fun foldTo(words: LongArray, bits: Int): LongArray {
        val n = bits / 64
        if (words.size == n) return words
        val out = LongArray(n)
        for (i in words.indices) out[i % n] = out[i % n] or words[i]
        return out
    }

    fun popcount(w: LongArray): Int = w.sumOf { java.lang.Long.bitCount(it) }
    fun intersection(a: LongArray, b: LongArray): Int { var n = 0; for (i in a.indices) n += java.lang.Long.bitCount(a[i] and b[i]); return n }

    /** Rastlantıdan arındırılmış kapsama: x'in bitlerinin y'de olma oranı, rastlantı payı düşülmüş (0-100). */
    fun coverage(inter: Int, x: Int, y: Int, bits: Int): Double {
        val expected = x.toDouble() * y / bits
        val d = x - expected
        if (d <= 0) return 0.0
        return 100.0 * (inter - expected) / d
    }

    /** İki yönlü benzerlik: kapsamaların küçüğü. Bloomlar küçük olanın boyuna katlanır. */
    fun similarity(a: LongArray, b: LongArray): Double {
        val bits = minOf(a.size, b.size) * 64
        val x = foldTo(a, bits); val y = foldTo(b, bits)
        val i = intersection(x, y); val px = popcount(x); val py = popcount(y)
        return minOf(coverage(i, px, py, bits), coverage(i, py, px, bits))
    }

    fun similarity(textA: String, textB: String): Double = similarity(bloom(fold(textA)), bloom(fold(textB)))

    /** OCR izi (ceviri.md 9.4). */
    fun isDamaged(text: String): Boolean {
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            i += Character.charCount(cp)
            if (cp > 0x7f && !Character.isWhitespace(cp) && cp !in TYPOGRAPHIC) return true
        }
        for (raw in text.split(WS)) {
            if (raw.isEmpty()) continue
            val w = raw.trim { !it.isLetterOrDigit() }
            if (w.isEmpty()) continue
            if (w.codePointCount(0, w.length) > 14) return true
            val letters = w.count { it.isLetter() }
            if (w.length == 1 && letters == 1 && w[0] !in "aAIoO") return true
            for (k in w.indices) {
                val c = w[k]
                if (!c.isLetterOrDigit() && c !in INNER_OK) return true
                if (k > 0) {
                    val p = w[k - 1]
                    if ((p.isLetter() && c.isDigit()) || (p.isDigit() && c.isLetter())) return true
                }
            }
        }
        return false
    }

    private val WS = Regex("\\s+")
    private const val INNER_OK = "'-’‘‐‑"
    private val TYPOGRAPHIC = setOf(0x2018, 0x2019, 0x201A, 0x201B, 0x201C, 0x201D, 0x201E, 0x201F, 0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015, 0x2026, 0x00A0)

    /** Kabul eşiği (satır harf sayısına ve OCR izine göre). */
    fun threshold(length: Int, damaged: Boolean): Double = if (!damaged) {
        if (length < 24) 90.0 else 80.0
    } else {
        when { length < 24 -> 70.0; length < 40 -> 60.0; else -> 55.0 }
    }
}
