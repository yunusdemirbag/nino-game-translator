// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

/** Terimleri çeviriden önce yer tutucuyla değiştirir, sonra geri koyar (ceviri.md, "Terimlerin korunması"). */
class TermProtector(terms: List<Term>) {
    data class Protected(val text: String, val replacements: List<String>)

    val terms: List<Term> = run {
        val seen = HashSet<String>()
        terms.filter { it.source.isNotBlank() }
            .filter { seen.add(it.source.lowercase()) }
            .sortedByDescending { it.source.length }
    }

    fun protect(text: String): Protected {
        var result = text
        val replacements = ArrayList<String>()
        for (term in terms) {
            var from = 0
            while (true) {
                val at = result.indexOf(term.source, from, ignoreCase = true)
                if (at < 0) break
                val end = at + term.source.length
                if (isBoundary(result, at, end)) {
                    val ph = placeholder(replacements.size)
                    replacements += term.replacement
                    result = result.substring(0, at) + ph + result.substring(end)
                    from = at + ph.length
                } else {
                    from = end
                }
            }
        }
        return Protected(result, replacements)
    }

    /** Yer tutucuları geri koyar. Biri kaybolduysa null. */
    fun restore(translated: String, protected: Protected): String? {
        val out = StringBuilder()
        val found = HashSet<Int>()
        var i = 0
        while (i < translated.length) {
            val open = translated.indexOf('⟦', i)
            if (open < 0) { out.append(translated, i, translated.length); break }
            out.append(translated, i, open)
            val close = translated.indexOf('⟧', open)
            if (close < 0) { out.append(translated, open, translated.length); break }
            val n = translated.substring(open + 1, close).trim().toIntOrNull()
            if (n != null && n >= 0 && n < protected.replacements.size) {
                out.append(protected.replacements[n]); found += n
            } else {
                out.append(translated, open, close + 1)
            }
            i = close + 1
        }
        return if (found.size == protected.replacements.size) out.toString() else null
    }

    private fun isBoundary(s: String, start: Int, end: Int): Boolean {
        if (start > 0 && s[start - 1].isLetterOrDigit()) return false
        if (end < s.length && s[end].isLetterOrDigit()) return false
        return true
    }

    companion object {
        fun placeholder(i: Int) = "⟦$i⟧"
        val PLACEHOLDER = Regex("⟦\\d+⟧")
    }
}
