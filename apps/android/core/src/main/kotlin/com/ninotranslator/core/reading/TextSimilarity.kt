// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading

/** İki yazının benzerliği (okuma-hatti.md, "Benzerlik"). */
object TextSimilarity {
    /** Küçük harf; harf ve rakam dışı her şey boşluk; boşluklar teke iner. */
    fun key(text: String): String {
        val out = StringBuilder(text.length)
        var space = false
        for (ch in text.lowercase()) {
            if (ch.isLetterOrDigit()) {
                if (space && out.isNotEmpty()) out.append(' ')
                out.append(ch)
                space = false
            } else {
                space = true
            }
        }
        return out.toString()
    }

    /** 1 - düzenleme uzaklığı / uzun olanın boyu. */
    fun ratio(a: String, b: String): Double = ratioOfKeys(key(a), key(b))

    fun ratioOfKeys(x: String, y: String): Double {
        val longest = maxOf(x.length, y.length)
        if (longest == 0) return 1.0
        return 1.0 - levenshtein(x, y).toDouble() / longest
    }

    /** Aynı altyazı mı? Biri ötekinin uzantısıysa aynı sayılmaz. */
    fun isSame(a: String, b: String, threshold: Double): Boolean {
        val x = key(a)
        val y = key(b)
        if (x != y && (x.startsWith(y) || y.startsWith(x))) return false
        return ratioOfKeys(x, y) >= threshold
    }

    fun levenshtein(a: CharSequence, b: CharSequence): Int {
        if (a.isEmpty()) return b.length
        if (b.isEmpty()) return a.length
        var prev = IntArray(b.length + 1) { it }
        var cur = IntArray(b.length + 1)
        for (i in 1..a.length) {
            cur[0] = i
            for (j in 1..b.length) {
                val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                cur[j] = minOf(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            val t = prev; prev = cur; cur = t
        }
        return prev[b.length]
    }
}
