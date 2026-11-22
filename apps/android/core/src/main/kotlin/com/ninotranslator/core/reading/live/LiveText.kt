// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import com.ninotranslator.core.reading.TextSimilarity
import kotlin.math.max
import kotlin.math.min

/** Canlı hattın ortak yazı yardımcıları (okuma.md 5–6). */
object LiveText {
    private val SENTENCE_END = setOf('.', '!', '?', '…')
    private val CLOSING = setOf('"', '\'', '”', '’', ')', ']', '»')
    private val VOWELS = "aeiouyAEIOUY".toSet()
    private val INTERJECTIONS = setOf("hmm", "hm", "shh", "sh", "brr", "psst", "pst", "zzz", "mm", "mmm", "hmph", "tsk", "grr", "pfft")
    private val SYMBOLS = "\$@#%^*_=|\\~<>{}¢£¥§©®°±µ¶¤".toSet()
    private val TYPOGRAPHIC = "’‘“”—–…".toSet()
    private val NEGATIONS = setOf(
        "not", "no", "never", "cannot", "dont", "cant", "wont", "isnt", "arent", "wasnt", "werent", "doesnt",
        "didnt", "hasnt", "havent", "hadnt", "shouldnt", "wouldnt", "couldnt", "mustnt", "neednt", "aint", "nothing",
        "nobody", "none", "nowhere", "neither", "nor",
    )
    private val DIGIT_AS_LETTER = mapOf('0' to 'o', '1' to 'i', '3' to 'e', '4' to 'a', '5' to 's', '7' to 't', '8' to 'b')
    private val ALLOWED_SINGLE = setOf("a", "A", "I", "o", "O")

    /** Sadeleştirilmiş hâl (tarif anahtarı). */
    fun key(text: String): String = TextSimilarity.key(text)

    /** Karakter benzerliği; boş yazı hiçbir yazıya benzemez. */
    fun similarity(a: String, b: String): Double {
        val x = key(a); val y = key(b)
        if (x.isEmpty() || y.isEmpty()) return 0.0
        return TextSimilarity.ratioOfKeys(x, y)
    }

    /** Cümle sonu işaretiyle bitiyor mu (kapanan tırnak/parantez yok sayılır). */
    fun endsSentence(text: String): Boolean {
        var i = text.trimEnd().length - 1
        while (i >= 0 && text[i] in CLOSING) i--
        return i >= 0 && text[i] in SENTENCE_END
    }

    fun letterCount(text: String): Int = text.count { it.isLetter() }

    /** Boşlukla ayrılmış parçalar. */
    fun tokens(text: String): List<String> = text.split(Regex("\\s+")).filter { it.isNotEmpty() }

    /** Karşılaştırma sözcükleri: küçük harf, tek harfli ve sayılar hariç. */
    fun compareWords(text: String): List<String> = key(text).split(' ').filter { it.length > 1 && !it.all(Char::isDigit) }

    /** Bölüm 5'teki bozuk sözcük: karışık büyük/küçük harf, simge, parantez, 3+ ünlüsüz. */
    fun isGarbageWord(token: String): Boolean {
        val w = token.trim { it in ".,!?;:\"'”’“‘…-" }
        if (w.isEmpty()) return false
        if (w.any { it in SYMBOLS || it in "[](){}" }) return true
        val letters = w.filter { it.isLetter() }
        if (letters.isEmpty()) return false
        if (letters.length >= 3 && letters.none { it in VOWELS } && letters.lowercase() !in INTERJECTIONS) return true
        // Karışık harf: ilk harften sonra büyük harf ve küçük harf birlikte (ör. "hEllo", "wAtEr").
        val rest = letters.drop(1)
        if (rest.any { it.isUpperCase() } && rest.any { it.isLowerCase() }) return true
        if (letters.first().isLowerCase() && rest.any { it.isUpperCase() }) return true
        return false
    }

    /** Çöp gibi okuma: harflerin altıda birinden fazlası bozuk sözcüklerde. */
    fun isGarbageReading(text: String): Boolean {
        val toks = tokens(text)
        val total = toks.sumOf { letterCount(it) }
        if (total == 0) return false
        val bad = toks.filter { isGarbageWord(it) }.sumOf { letterCount(it) }
        return bad * 6 > total
    }

    /** Puan: temiz sözcüğün her harfi +1, bozuk sözcüğün her harfi −2. */
    fun qualityScore(text: String): Int = tokens(text).sumOf {
        val n = letterCount(it)
        if (isGarbageWord(it) || isBrokenWord(it)) -2 * n else n
    }

    /** Bölüm 6'daki bozuk sözcük (karakter kuralları). */
    fun isBrokenWord(token: String): Boolean {
        if (token.any { it.code > 127 && it !in TYPOGRAPHIC }) return true
        val w = token.trim { !it.isLetterOrDigit() }
        if (w.isEmpty()) return false
        if (w.length > 14) return true
        for (i in 1 until w.length - 1) {
            val c = w[i]
            if (!c.isLetterOrDigit() && c != '\'' && c != '’' && c != '-') return true
        }
        for (i in 1 until w.length) {
            val a = w[i - 1]; val b = w[i]
            if ((a.isLetter() && b.isDigit()) || (a.isDigit() && b.isLetter())) return true
        }
        if (w.length == 1 && w[0].isLetter() && w !in ALLOWED_SINGLE) return true
        return false
    }

    /** Bölüm 6'daki bozuk okuma. */
    fun isBrokenReading(text: String): Boolean = tokens(text).any { isBrokenWord(it) }

    /** Yarım olabilecek okuma: bir satırı küçük harfle başlıyor ya da cümle sonu yok. */
    fun maybePartial(text: String): Boolean {
        if (!endsSentence(text)) return true
        return text.split('\n').any { line -> line.trim().firstOrNull { it.isLetter() }?.isLowerCase() == true }
    }

    /** Olumsuzluk ve sayı işaretleri (rakamlar harfe çevrilerek de bakılır). */
    fun markers(text: String): Set<String> {
        val out = HashSet<String>()
        val raw = tokens(text.lowercase().replace('’', '\'')).map { tok -> tok.trim { !it.isLetterOrDigit() && it != '\'' }.replace("'", "") }
        for ((i, clean) in raw.withIndex()) {
            if (clean.isEmpty()) continue
            // Tek "1" ve "0" çoğu zaman "I" ve "O" harfidir.
            if (clean == "1" || clean == "0") continue
            if (clean.all(Char::isDigit)) { out += "#$clean"; continue }
            val asLetters = clean.map { DIGIT_AS_LETTER[it] ?: it }.joinToString("")
            if (asLetters in NEGATIONS) out += "!$asLetters"
            // Kesmesi okunmamış "won t", "can t".
            if (asLetters == "t" && i > 0 && (raw[i - 1] + "t") in NEGATIONS) out += "!" + raw[i - 1] + "t"
        }
        return out
    }

    /** Okuma, gönderilende olmayan bir olumsuzluk ya da sayı ekliyor mu? */
    fun addsMarker(reading: String, sent: String): Boolean = (markers(reading) - markers(sent)).isNotEmpty()

    /** Sözcük düzeyinde: [longer], [shorter]'ın başına ya da sonuna sözcük eklenmiş hâli mi? */
    fun isWordExtension(longer: String, shorter: String): Boolean {
        val l = key(longer).split(' ').filter { it.isNotEmpty() }
        val s = key(shorter).split(' ').filter { it.isNotEmpty() }
        if (s.isEmpty() || l.size <= s.size) return false
        return l.subList(0, s.size) == s || l.subList(l.size - s.size, l.size) == s
    }

    /** Sözcük dizisi benzerliği (sözcükler üzerinde Levenshtein oranı). */
    fun wordSequenceSimilarity(a: String, b: String): Double {
        val x = key(a).split(' ').filter { it.isNotEmpty() }
        val y = key(b).split(' ').filter { it.isNotEmpty() }
        val n = max(x.size, y.size)
        if (n == 0) return 0.0
        return 1.0 - levenshtein(x, y).toDouble() / n
    }

    /** Ortak sözcük oranı: ortak / uzun olanın sözcük sayısı. */
    fun commonWordRatio(a: String, b: String): Double {
        val x = compareWords(a); val y = compareWords(b)
        val n = max(x.size, y.size)
        if (n == 0) return 0.0
        return commonCount(x, y).toDouble() / n
    }

    /** Çoklu küme kesişimi. */
    fun commonCount(x: List<String>, y: List<String>): Int {
        val bag = HashMap<String, Int>()
        for (w in y) bag[w] = (bag[w] ?: 0) + 1
        var c = 0
        for (w in x) { val k = bag[w] ?: 0; if (k > 0) { c++; bag[w] = k - 1 } }
        return c
    }

    fun wordCount(text: String): Int = key(text).split(' ').count { it.isNotEmpty() }

    private fun <T> levenshtein(a: List<T>, b: List<T>): Int {
        if (a.isEmpty()) return b.size
        if (b.isEmpty()) return a.size
        var prev = IntArray(b.size + 1) { it }
        var cur = IntArray(b.size + 1)
        for (i in 1..a.size) {
            cur[0] = i
            for (j in 1..b.size) cur[j] = min(min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + if (a[i - 1] == b[j - 1]) 0 else 1)
            val t = prev; prev = cur; cur = t
        }
        return prev[b.size]
    }

    /** Türkçe harf (PS5'in kendi ekranı işareti). */
    fun hasTurkishLetters(text: String): Boolean = text.any { it in "ğışçöüĞİŞÇÖÜ" }
}
