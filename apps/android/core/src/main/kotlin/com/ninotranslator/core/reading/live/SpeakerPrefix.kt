// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

/** Konuşmacı öneki "AD: cümle" (okuma.md 8). */
object SpeakerPrefix {
    data class Parsed(val name: String, val body: String)

    const val MAX_NAME = 24
    private val TITLES = setOf(
        // Görev ve oyun ekranı başlıkları
        "mission", "quest", "task", "goal", "objective", "objectives", "chapter", "level", "location", "status",
        "reward", "rewards", "result", "results", "update", "new", "info", "time",
        // İpucu ve eğitim kutuları
        "tutorial", "tip", "hint", "note", "warning", "remember", "example", "question", "answer", "controls",
        "press", "hold", "tap",
        // Cümle başı sözcükler (konuşan adı değil)
        "yes", "no", "ok", "okay", "well", "so", "now", "then", "and", "but", "wait", "look", "listen",
    )

    fun parse(text: String): Parsed? {
        val idx = text.indexOfFirst { it == ':' || it == '：' }
        if (idx <= 0) return null
        val name = text.substring(0, idx).trimEnd()
        if (name.length != text.substring(0, idx).trimEnd().length || name.isEmpty()) return null
        // İki noktadan önce en çok bir boşluk olabilir.
        if (idx - name.length > 1) return null
        if (name.length > MAX_NAME || name.any { it.isDigit() } || name.contains('\n')) return null
        val words = name.split(' ').filter { it.isNotEmpty() }
        if (words.isEmpty() || words.size > 3) return null
        if (words.any { w -> !w.first().isUpperCase() || w.any { !it.isLetter() && it !in ".'’-" } }) return null
        if (words.size == 1 && words[0].lowercase().trimEnd('.') in TITLES) return null
        val body = text.substring(idx + 1).trim()
        if (body.isEmpty() || body.startsWith("/") || body.none { it.isLetter() }) return null
        return Parsed(name, body)
    }

    /** Gösterim: ad yeniden başa eklenir. */
    fun withName(name: String?, translation: String): String = if (name == null) translation else "$name: $translation"

    /**
     * "Konuşan adını göster" kapalıysa: kaynakta ad olan satır başlarındaki ad çeviriden atılır.
     * Türkçe başlık ("Hedef: ...") kaynakta ad olmadığı için kalır.
     */
    fun stripNames(source: String, translation: String): String {
        val names = source.split('\n').mapNotNull { parse(it.trim())?.name?.lowercase() }.toSet()
        if (names.isEmpty()) return translation
        return translation.split('\n').joinToString("\n") { line ->
            val p = parse(line.trim())
            if (p != null && p.name.lowercase() in names) p.body else line
        }
    }
}
