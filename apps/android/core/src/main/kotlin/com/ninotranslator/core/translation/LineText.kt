// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

/** Altyazı satırının parçaları: konuşmacı etiketi, diyalog tiresi, cümleler, köşe yazısı (ceviri.md 3.1 ve 9.3). */
object LineText {
    /** Satır başı öneki ve gövde. */
    data class Prefixed(val prefix: String, val body: String)

    /** Ad sayılmayan tek sözcüklü başlıklar ("Note:", "Objective:"…); çevrilirler. */
    val HEADINGS = setOf(
        "note", "objective", "objectives", "tip", "hint", "warning", "info", "reward", "rewards", "location", "quest",
        "mission", "goal", "task", "new", "updated", "tutorial", "controls", "hold", "press", "status", "bonus",
        "optional", "required", "unlocked", "completed", "failed", "time", "distance", "level", "chapter", "episode",
    )

    private val LABEL = Regex("^([\\p{Lu}][\\p{L}\\p{N}'’.\\-]*(?: [\\p{Lu}\\p{N}][\\p{L}\\p{N}'’.\\-]*){0,2}):[ \\t]+(?=\\S)")
    private val DASH = Regex("^[-–—‐][ \\t]*(?=\\S)")

    /** Konuşmacı etiketi ("ATREUS: ", "Kratos: "; en çok üç sözcük). Başlıklar etiket değildir. */
    fun speakerLabel(text: String): Prefixed? {
        val m = LABEL.find(text) ?: return null
        val name = m.groupValues[1]
        if (!name.contains(' ') && name.lowercase() in HEADINGS) return null
        return Prefixed(m.value, text.substring(m.value.length))
    }

    /** Diyalog tiresi. */
    fun dash(text: String): Prefixed? = DASH.find(text)?.let { Prefixed(it.value, text.substring(it.value.length)) }

    /** Etiket ya da tire (önce etiket). Tireden sonra etiket de gelebilir ("- KRATOS: ..."). */
    fun prefix(text: String): Prefixed? {
        speakerLabel(text)?.let { return it }
        val d = dash(text) ?: return null
        val inner = speakerLabel(d.body)
        return if (inner != null) Prefixed(d.prefix + inner.prefix, inner.body) else d
    }

    /**
     * OCR'ın bozduğu etiket: ilk 32 karakterde `:` ya da `•`, önündeki sözcük harf
     * içerir ve küçük harf içermez; ya da iki noktasız en çok üç büyük harfli sözcük + büyük harfle başlayan küçük
     * harfli sözcük.
     */
    fun looseLabel(text: String): Prefixed? {
        val limit = minOf(32, text.length)
        for (i in 0 until limit) {
            val c = text[i]
            if (c != ':' && c != '•') continue
            var s = i
            while (s > 0 && !text[s - 1].isWhitespace()) s--
            val word = text.substring(s, i)
            if (word.none { it.isLetter() } || word.any { it.isLowerCase() }) {
                if (word.any { it.isLowerCase() }) return null
                continue
            }
            var e = i + 1
            while (e < text.length && text[e].isWhitespace()) e++
            if (e >= text.length) return null
            return Prefixed(text.substring(0, e), text.substring(e))
        }
        val words = Regex("\\S+").findAll(text).toList()
        var n = 0
        while (n < words.size && n < 3) {
            val w = words[n].value
            if (w.any { it.isLetter() } && w.none { it.isLowerCase() } && w.all { it.isLetter() || it == '\'' || it == '’' || it == '-' || it == '.' }) n++ else break
        }
        if (n == 0 || n >= words.size) return null
        if (words.take(n).sumOf { m -> m.value.count { it.isLetter() } } < 2) return null
        val next = words[n].value
        if (!next[0].isUpperCase() || next.none { it.isLowerCase() }) return null
        val start = words[n].range.first
        return Prefixed(text.substring(0, start), text.substring(start))
    }

    private val ABBREVIATIONS = setOf("mr", "mrs", "ms", "dr", "st", "jr", "sr", "prof", "vs", "etc", "lt", "sgt", "capt", "col", "gen", "mt", "no")
    private const val CLOSERS = "\"'”’)]»"

    /** Cümlelere böler (`. ! ? …`, ardından kapanış işareti ve boşluk; ardından küçük harf ya da kısaltma bitirmez). */
    fun sentences(text: String): List<String> {
        val out = ArrayList<String>()
        var start = 0
        var i = 0
        val s = text
        while (i < s.length) {
            val c = s[i]
            if (c == '.' || c == '!' || c == '?' || c == '…') {
                var j = i
                while (j + 1 < s.length && (s[j + 1] == '.' || s[j + 1] == '!' || s[j + 1] == '?' || s[j + 1] == '…')) j++
                var k = j
                while (k + 1 < s.length && s[k + 1] in CLOSERS) k++
                if (k + 1 < s.length && s[k + 1].isWhitespace()) {
                    var n = k + 1
                    while (n < s.length && s[n].isWhitespace()) n++
                    val nextLower = n < s.length && s[n].isLowerCase()
                    if (!nextLower && !(c == '.' && j == i && isAbbreviation(s, i))) {
                        s.substring(start, k + 1).trim().takeIf { it.isNotEmpty() }?.let(out::add)
                        start = n
                        i = n
                        continue
                    }
                }
                i = k + 1
                continue
            }
            i++
        }
        s.substring(start).trim().takeIf { it.isNotEmpty() }?.let(out::add)
        return out
    }

    private fun isAbbreviation(s: String, dot: Int): Boolean {
        var b = dot
        while (b > 0 && s[b - 1].isLetter()) b--
        val w = s.substring(b, dot)
        if (w.length == 1 && w[0].isUpperCase()) return true
        return w.lowercase() in ABBREVIATIONS
    }

    /** Köşe yazısı: en çok 4 sözcük; `•` içerir ya da her sözcük büyük harfle başlar ve yalnız harf/rakamdır. */
    fun isCornerText(text: String): Boolean {
        val words = text.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (words.isEmpty() || words.size > 4) return false
        if (text.contains('•')) return true
        return words.all { w -> w[0].isUpperCase() && w.all { it.isLetterOrDigit() } }
    }

    /** Harf içeren sözcük sayısı. */
    fun wordCount(text: String): Int = text.split(Regex("\\s+")).count { w -> w.any { it.isLetter() } }

    /** Türkçe harf izi (PS5'in kendi Türkçe ekranı). */
    fun hasTurkishLetters(text: String): Boolean = text.any { it in "ğĞşŞıİ" } || text.count { it in "üÜöÖçÇ" } >= 2
}
