// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

/** Canlı hattın cümle bölücüsü ve konuşma parçaları (okuma.md 7). */
object LiveSentences {
    val ABBREVIATIONS = setOf(
        // unvanlar, rütbeler, yer ve kısaltma sözcükleri
        "dr", "prof", "mr", "mrs", "ms", "jr", "sr", "capt", "col", "gen", "lt", "sgt", "mt", "st", "e.g", "i.e", "etc", "vs",
    )
    private val ENDERS = setOf('.', '!', '?', '…')
    private val CLOSERS = setOf('"', '\'', '”', '’', ')', ']')
    private val DASH = Regex("^[-–—]\\s*")
    private val LABEL = Regex("^((?:[A-Z0-9][A-Z0-9'’.-]*)(?:\\s+[A-Z0-9][A-Z0-9'’.-]*){0,2}|(?:[A-Z][\\p{L}'’.-]*)(?:\\s+[A-Z][\\p{L}'’.-]*){0,2})\\s?[:：]\\s*")

    /** Yazıyı cümlelere böler. */
    fun split(text: String): List<String> {
        val out = ArrayList<String>()
        var start = 0
        var i = 0
        fun cut(end: Int) { text.substring(start, end).trim().takeIf { it.isNotEmpty() }?.let { out += it }; start = end }
        while (i < text.length) {
            if (text[i] !in ENDERS) { i++; continue }
            val runStart = i
            while (i < text.length && text[i] in ENDERS) i++
            var closers = 0
            while (i < text.length && text[i] in CLOSERS && closers < 10) { i++; closers++ }
            val end = i
            if (end >= text.length || !text[end].isWhitespace()) continue
            var next = end
            while (next < text.length && text[next].isWhitespace()) next++
            if (next >= text.length || text[next].isLowerCase()) continue
            if (text[runStart] == '.' && end - runStart == 1 && isAbbreviation(text, runStart)) continue
            cut(end)
        }
        cut(text.length)
        return out
    }

    private fun isAbbreviation(text: String, dot: Int): Boolean {
        var s = dot
        while (s > 0 && (text[s - 1].isLetter() || text[s - 1] == '.')) s--
        val word = text.substring(s, dot)
        if (word.length == 1 && word[0].isUpperCase()) return true // "J. R. R."
        return word.lowercase() in ABBREVIATIONS
    }

    /** Konuşma parçası: [prefix] (tire ya da etiket) çevrilmez. */
    data class Segment(val prefix: String, val body: String) {
        val translatable: Boolean get() = body.any { it.isLetter() }
    }

    /** Satır başındaki konuşmacı etiketi (en çok 3 sözcük; tümü büyük harf ya da her sözcük büyük harfle). */
    fun label(line: String): String? {
        val m = LABEL.find(line) ?: return null
        if (line.length == m.range.last + 1) return null
        return m.value
    }

    /**
     * Satırlar konuşmalara ayrılır: etiketle ya da tireyle başlayan satır yeni konuşmadır; diğerleri
     * öncekine boşlukla eklenir.
     */
    fun segments(text: String): List<Segment> {
        val out = ArrayList<Segment>()
        for (raw in text.split('\n')) {
            val line = raw.trim()
            if (line.isEmpty()) continue
            val dash = DASH.find(line)?.takeIf { line.length > it.value.length }
            val lab = if (dash == null) label(line) else null
            when {
                dash != null -> out += Segment(dash.value, line.substring(dash.value.length))
                lab != null -> out += Segment(lab, line.substring(lab.length))
                out.isEmpty() -> out += Segment("", line)
                else -> { val p = out.removeAt(out.size - 1); out += p.copy(body = p.body + " " + line) }
            }
        }
        return out
    }

    /** Konuşmalar arası satır sonu ayracıyla yeniden birleştirir. */
    fun join(segments: List<Segment>, bodies: List<String> = segments.map { it.body }): String =
        segments.indices.joinToString("\n") { segments[it].prefix + bodies[it] }

    /** Etiketlerden öğrenilen adlar. */
    fun namesFrom(text: String): Set<String> = segments(text).mapNotNull { s ->
        s.prefix.trim().trimEnd(':', '：').trim().takeIf { it.isNotEmpty() && it.first().isLetter() }
    }.flatMap { it.split(' ') }.map { it.lowercase() }.toSet()

    /** Tümü büyük harfli, en az iki sözcüklü cümle cümle düzenine çevrilir. */
    fun sentenceCase(sentence: String, names: Set<String> = emptySet()): String {
        val letters = sentence.filter { it.isLetter() }
        val toks = LiveText.tokens(sentence)
        if (letters.isEmpty() || letters.any { it.isLowerCase() } || toks.size < 2) return sentence
        var start = true
        return toks.joinToString(" ") { tok ->
            val core = tok.filter { it.isLetter() || it == '\'' || it == '’' }.lowercase()
            val upper = start || core == "i" || core.startsWith("i'") || core.startsWith("i’") ||
                core.trimEnd('\'', '’', 's') in names || core in names
            val w = tok.lowercase()
            if (tok.any { it.isLetter() }) start = LiveText.endsSentence(tok)
            if (!upper) w else {
                val i = w.indexOfFirst { it.isLetter() }
                if (i < 0) w else w.substring(0, i) + w[i].uppercaseChar() + w.substring(i + 1)
            }
        }
    }

    /** Köşe yazısı gibi satır: en çok 4 sözcük; "•" içerir ya da her sözcüğü büyük harfle başlar. */
    fun isCornerLike(line: String): Boolean {
        val t = LiveText.tokens(line)
        if (t.isEmpty() || t.size > 4) return false
        return line.contains('•') || t.all { w -> w.firstOrNull { it.isLetter() }?.isUpperCase() ?: true }
    }

    /**
     * Paket araması: tamamı, etiketsiz/tiresiz hâli, her satır ayrı, her cümle ayrı. Hiçbiri tutmazsa
     * aynı sıra [fuzzy] ile bir kez daha denenir.
     */
    fun lookupPack(text: String, exact: (String) -> String?, fuzzy: ((String) -> String?)? = null): String? =
        lookupWith(text, exact) ?: fuzzy?.let { lookupWith(text, it) }

    private fun lookupWith(text: String, find: (String) -> String?): String? {
        find(text)?.let { return it }
        val segs = segments(text)
        if (segs.any { it.prefix.isNotEmpty() }) {
            val bodies = segs.map { if (it.translatable) find(it.body) else it.body }
            if (bodies.all { it != null }) return join(segs, bodies.map { it!! })
            find(segs.joinToString(" ") { it.body })?.let { return it }
        }
        val lines = text.split('\n').map { it.trim() }.filter { it.isNotEmpty() }
        if (lines.size > 1) {
            val found = lines.map { l -> find(l) ?: if (isCornerLike(l)) l else null }
            if (found.all { it != null } && lines.indices.any { found[it] != lines[it] }) return found.joinToString("\n")
        }
        val sentences = split(text.replace('\n', ' '))
        if (sentences.size > 1) {
            val found = sentences.map { find(it) }
            if (found.all { it != null }) return found.joinToString(" ")
        }
        return null
    }
}
