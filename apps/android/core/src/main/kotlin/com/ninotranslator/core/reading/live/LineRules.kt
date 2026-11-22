// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

/** Kumanda ipucu tanıma (okuma.md 4, adım 5). */
object ControllerHints {
    private val BUTTON_WORDS = setOf("r1", "r2", "r3", "l1", "l2", "l3", "options", "touchpad")
    private val BUTTON_SYMBOLS = setOf('✕', '×', '⨯', '✖', '○', '◯', '⭘', '●', '□', '▢', '☐', '■', '△', '▲', '⃝')
    private val VERBS = setOf("press", "hold", "tap", "push", "use", "mash", "release")
    private val ADVERBS = setOf("slowly", "quickly", "gently", "carefully", "rapidly", "repeatedly", "continuously", "briefly")

    private fun bare(t: String) = t.trim { it in ".,!?;:\"'()[]" }

    fun isSymbol(t: String): Boolean { val b = bare(t); return b.isNotEmpty() && b.all { it in BUTTON_SYMBOLS || it.isWhitespace() } }
    fun isButton(t: String): Boolean = isSymbol(t) || bare(t).lowercase() in BUTTON_WORDS
    private fun isXO(t: String) = bare(t) in setOf("X", "O", "x", "o")

    fun isHint(text: String): Boolean {
        val p = LiveText.tokens(text)
        if (p.isEmpty()) return false
        val ends = LiveText.endsSentence(text)
        if (isButton(p.first()) && p.size <= 5) return true
        if (isButton(p.last()) && p.size <= 4 && !ends) return true
        if (isXO(p.first()) && p.size in 2..4 && p[1].first().isUpperCase() && !ends) return true
        if (bare(p.first()).lowercase() in VERBS && p.size in 2..10 && (isButton(p[1]) || isXO(p[1]))) return true
        // "A e DRINKS": baştaki tek karakterli kırıntılar, ardından BÜYÜK HARFLİ sözcükler.
        val crumbs = p.takeWhile { it.length == 1 }.size
        if (crumbs in 1..3) {
            val rest = p.drop(crumbs)
            if (rest.size in 1..3 && rest.all { w -> w.any(Char::isLetter) && w.all { it.isUpperCase() || !it.isLetter() } && w.none { it in ".,!?;:…" } }) return true
        }
        if (bare(p.first()).lowercase() in ADVERBS && p.size in 3..16 && !ends &&
            p.drop(3).any { bare(it).lowercase() == "to" }) return true
        if (p.size <= 16 && !ends && p.any { isSymbol(it) } && p.any { bare(it).lowercase() == "to" }) return true
        return false
    }
}

/** Yol tarifi tanıma (adım 6). */
object Directions {
    private const val DIST = "(?:\\d+(?:[.,]\\d+)?|[Oo])\\s*(?:ft|mi|yd|km|m)\\.?"
    private val PATTERN = Regex(
        "^(?:turn\\s+(?:left|right)|keep\\s+(?:left|right)|make\\s+a\\s+u-?\\s?turn)[.!]?(?:\\s+$DIST)*$",
        RegexOption.IGNORE_CASE,
    )

    fun isDirection(text: String): Boolean = PATTERN.matches(text.trim())
}

/** Sözcük çöpü temizliği (adım 7). */
object WordCleanup {
    private val SYMBOLS = "\$@#%^*_=|\\~<>{}¢£¥§©®°±µ¶¤".toSet()
    private val PUNCT_ONLY = Regex("^[?!.,;:]+$")
    private val ELLIPSIS = Regex("^(\\.\\.\\.|…)$")
    private val ALLOWED = listOf(
        Regex("^[A-Za-z]{1,3}\\d{1,2}$"),                     // PS5, R2, L1
        Regex("^\\d+(st|nd|rd|th)$", RegexOption.IGNORE_CASE), // 2nd
        Regex("^\\d+([.,]\\d+)?(m|km|cm|mm|kg|g|lb|lbs|ft|mi|yd|s|ms|h|min|mph|k|x|%)$", RegexOption.IGNORE_CASE),
        Regex("^x\\d+$", RegexOption.IGNORE_CASE),             // x3
        Regex("^\\d{1,2}:\\d{2}(am|pm)?$", RegexOption.IGNORE_CASE),
        Regex("^\\$\\d+([.,]\\d+)*$"),                          // $500
        Regex("^\\d+%$"),
    )
    private val L_CONTRACTION = Regex("^[l|]'(m|ll|ve|d)$")

    private fun core(t: String) = t.trim { it in ".,!?;:\"'”’“‘()" }
    private fun trailingPunct(t: String) = t.takeLastWhile { it in ".,!?;:" }

    /** Parça çöp mü? (simge ya da harf-rakam iç içe; olağan karışımlar korunur) */
    fun isJunk(token: String): Boolean {
        val c = core(token)
        if (c.isEmpty()) return false
        if (ALLOWED.any { it.matches(c) }) return false
        if (c.any { it in SYMBOLS }) return true
        val hasL = c.any { it.isLetter() }; val hasD = c.any { it.isDigit() }
        return hasL && hasD
    }

    fun clean(text: String): String {
        val input = LiveText.tokens(text)
        val out = ArrayList<String>()
        fun ended() = out.isNotEmpty() && LiveText.endsSentence(out.last())
        for ((i, raw) in input.withIndex()) {
            var t = raw
            if (t == "l" || t == "|") t = "I"
            L_CONTRACTION.matchEntire(t)?.let { t = "I'" + it.groupValues[1] }
            if (ELLIPSIS.matches(t)) { if (out.isNotEmpty()) out[out.size - 1] = out.last() + t else out += t; continue }
            if (PUNCT_ONLY.matches(t)) {
                if (out.isNotEmpty() && !ended()) out[out.size - 1] = out.last() + t
                continue
            }
            if (isJunk(t)) {
                val c = core(t)
                val lead = c.takeWhile { it.isLetter() }
                if (lead.length >= 3) { out += lead + trailingPunct(t); continue }
                val p = trailingPunct(t)
                if (p.isNotEmpty() && out.isNotEmpty() && !ended()) out[out.size - 1] = out.last() + p
                continue
            }
            if (t == "I" || t == "I.") {
                val next = input.getOrNull(i + 1)
                val keep = next != null && next.first().isLowerCase()
                if (!keep) continue
            }
            out += t
        }
        // Başa yapışmış gösterge sayısı ("9? We'll lose…").
        if (out.size >= 3 && out[0].trim { it in "?!.,;:" }.all(Char::isDigit) && out[0].any(Char::isDigit) && out[1].first().isUpperCase()) {
            out.removeAt(0)
        }
        return out.joinToString(" ")
    }
}

/** Öğrenilmiş altyazı şeridi (okuma.md 3). */
data class SubtitleBand(val top: Double, val bottom: Double) {
    /** Okunan bölge: üstü şeridin üstü − 0.05'e iner (yalnız daraltır). */
    fun narrow(region: LiveRegion): LiveRegion {
        val t = maxOf(region.top, top - 0.05)
        return if (region.bottom - t < 0.06) region else region.copy(top = t)
    }

    companion object {
        const val MAX_SAMPLES = 60
        const val MIN_SAMPLES = 8

        /** Örneklerden şerit (alt kenarı 0.80'den yukarıda olan sayılmaz). */
        fun learn(samples: List<LiveBox>): SubtitleBand? {
            val ok = samples.filter { it.bottom >= 0.80 }.takeLast(MAX_SAMPLES)
            if (ok.size < MIN_SAMPLES) return null
            return SubtitleBand(percentile(ok.map { it.top }, 0.10), percentile(ok.map { it.bottom }, 0.90))
        }

        /** Örnek eklenir mi? */
        fun accepts(b: LiveBox) = b.bottom >= 0.80

        private fun percentile(v: List<Double>, p: Double): Double {
            val s = v.sorted()
            return s[((s.size - 1) * p).toInt().coerceIn(0, s.size - 1)]
        }
    }
}

/** Görev şeridi çizgisi; null = sınır yok. */
object TaskStripLine {
    const val DEFAULT = 0.895

    fun compute(band: SubtitleBand?, boxHeights: List<Double> = emptyList(), isGta6: Boolean = false): Double? {
        var line = if (band == null) DEFAULT else {
            val med = if (boxHeights.isEmpty()) 0.0 else boxHeights.sorted()[boxHeights.size / 2]
            maxOf(band.bottom + maxOf(0.012, med), band.top + 0.03, DEFAULT)
        }
        if (isGta6) line = minOf(line, 0.935)
        return if (line >= 0.97) null else line
    }
}
