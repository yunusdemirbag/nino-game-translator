// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading

/** Yazıyı cümlelere böler (okuma-hatti.md, bölüm 6). */
class SentenceSplitter(abbreviations: Set<String> = DEFAULT_ABBREVIATIONS) {
    private val abbreviations = abbreviations.map { it.lowercase() }.toSet()

    fun split(text: String): List<String> {
        val out = ArrayList<String>()
        var start = 0
        var i = 0
        fun cut(end: Int) {
            val piece = text.substring(start, end).trim()
            if (piece.isNotEmpty()) out += piece
            start = end
        }
        loop@ while (i < text.length) {
            if (text[i] !in ENDERS) { i++; continue }
            val runStart = i
            while (i < text.length && text[i] in ENDERS) i++
            val run = text.substring(runStart, i)
            while (i < text.length && text[i] in CLOSERS) i++
            val end = i
            if (end >= text.length) break
            if (!text[end].isWhitespace()) continue
            var next = end
            while (next < text.length && text[next].isWhitespace()) next++
            if (next >= text.length) break
            if (text[next].isLowerCase()) continue
            if (run == "." && isAbbreviation(runStart, text)) continue
            cut(end)
        }
        cut(text.length)
        return out
    }

    private fun isAbbreviation(dot: Int, text: String): Boolean {
        var s = dot
        while (s > 0 && !text[s - 1].isWhitespace()) s--
        val word = text.substring(s, dot).dropWhile { !it.isLetter() }.lowercase()
        return word in abbreviations
    }

    companion object {
        val DEFAULT_ABBREVIATIONS = setOf("mr", "mrs", "ms", "dr", "st", "jr", "sr", "prof", "vs", "etc", "e.g", "i.e")
        private val ENDERS = setOf('.', '!', '?', '…')
        private val CLOSERS = setOf('"', '”', '\'', '’', ')', ']')
    }
}
