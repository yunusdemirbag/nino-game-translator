// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

/**
 * Cihaz içi çeviride terim koruma (ceviri.md 5.2): terim uydurma bir özel adla değiştirilir, çeviriden sonra ad bulunup
 * yerine Türkçe terim konur ve çevirmenin koyduğu ek terime göre yeniden kurulur. Bir satırda en çok 8 terim.
 */
object TermShield {
    val NAMES = listOf("Zarmon", "Velkor", "Dorvan", "Kelmar", "Tolvar", "Brandur", "Halvor", "Feldor")

    data class Shielded(val text: String, val slots: List<Slot>, val curlyApostrophe: Boolean, val preexisting: Set<String> = emptySet())
    data class Slot(val name: String, val target: String, val proper: Boolean)

    /** [also] bağlam gibi aynı isteğe giden öbür metin (orada geçen ad da kullanılmaz). */
    fun shield(text: String, hits: List<Glossary.Hit>, also: String = ""): Shielded {
        val free = NAMES.filter { n -> !text.contains(n, true) && !also.contains(n, true) }.toMutableList()
        val out = StringBuilder()
        val slots = ArrayList<Slot>()
        var last = 0
        for (h in hits.sortedBy { it.start }) {
            if (free.isEmpty()) break
            val name = free.removeAt(0)
            out.append(text, last, h.start).append(name)
            val proper = h.kept || h.target.firstOrNull()?.isUpperCase() == true
            slots += Slot(name, h.target, proper)
            last = h.end
        }
        out.append(text, last, text.length)
        return Shielded(out.toString(), slots, text.contains('’'), NAMES.filter { text.contains(it, true) || also.contains(it, true) }.toSet())
    }

    private fun pattern(name: String) = Regex("(?<![\\p{L}])" + name + "(?:[ ]?(['’])[ ]?(\\p{L}+)|(\\p{L}+))?(?![\\p{L}])", RegexOption.IGNORE_CASE)

    /** Adları geri koyar. Ad kaybolduysa ya da beklenmeyen ad çıktıysa null (sonuç güvenilmez). */
    fun restore(translated: String, s: Shielded): String? {
        var result = translated
        for (slot in s.slots) {
            val p = pattern(slot.name)
            val matches = p.findAll(result).toList()
            if (matches.isEmpty()) return null
            result = p.replace(result) { m ->
                val suffix = m.groupValues[2].ifEmpty { m.groupValues[3] }
                val apostrophe = if (s.curlyApostrophe) '’' else '\''
                var t = TurkishText.attachSuffix(slot.target, suffix, slot.proper, apostrophe)
                if (atSentenceStart(result, m.range.first)) t = TurkishText.capitalize(t)
                t
            }
        }
        val used = s.slots.map { it.name }.toSet()
        if (NAMES.any { it !in used && it !in s.preexisting && Regex("(?<![\\p{L}])$it", RegexOption.IGNORE_CASE).containsMatchIn(result) }) return null
        return result
    }

    private fun atSentenceStart(s: String, at: Int): Boolean {
        var i = at - 1
        while (i >= 0 && (s[i].isWhitespace() || s[i] in "\"'“‘«(-–—")) i--
        return i < 0 || s[i] in ".!?…:"
    }
}
