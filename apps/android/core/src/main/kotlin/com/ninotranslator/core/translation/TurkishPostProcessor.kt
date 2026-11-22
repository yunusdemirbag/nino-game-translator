// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import java.util.Locale

/** Çevirmenden gelen metni toparlar (ceviri.md, "Türkçe son düzeltme"). */
class TurkishPostProcessor(private val locale: Locale = Locale.forLanguageTag("tr-TR")) {
    fun process(translated: String, source: String): String {
        var s = translated.replace("…", "...").trim().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        for (p in listOf(" ,", " .", " !", " ?", " ;", " :")) while (s.contains(p)) s = s.replace(p, p.substring(1))
        s = spaceAfter(s, setOf(',', ';'))
        s = fixDots(s)
        val first = source.firstOrNull { it.isLetter() }
        val idx = s.indexOfFirst { it.isLetter() }
        if (first != null && first.isUpperCase() && idx >= 0 && s[idx].isLowerCase()) {
            s = s.substring(0, idx) + s[idx].toString().uppercase(locale) + s.substring(idx + 1)
        }
        val src = source.trim()
        val last = s.lastOrNull()
        if (last != null && last !in ENDERS && last !in "\"'”’)]") {
            if (src.endsWith("...") || src.endsWith("…")) s += "..."
            else src.lastOrNull()?.takeIf { it in ENDERS }?.let { s += it }
        }
        return s
    }

    private fun spaceAfter(s: String, marks: Set<Char>): String {
        val out = StringBuilder()
        for (i in s.indices) {
            out.append(s[i])
            if (s[i] in marks && i + 1 < s.length && s[i + 1].isLetter()) out.append(' ')
        }
        return out.toString()
    }

    private fun fixDots(s: String): String {
        val out = StringBuilder()
        var run = 0
        fun flush() {
            if (run == 1 || run == 2) out.append('.') else if (run >= 3) out.append("...")
            run = 0
        }
        for (c in s) if (c == '.') run++ else { flush(); out.append(c) }
        flush()
        return out.toString()
    }

    companion object { private val ENDERS = setOf('.', '!', '?') }
}
