// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading

/** Gürültüyü atar, kalan satırları birleştirir (okuma-hatti.md, bölüm 4). */
class NoiseFilter(
    val minConfidence: Float = 0.40f,
    val minLetters: Int = 2,
    ignoredPhrases: Set<String> = DEFAULT_IGNORED,
) {
    val ignoredPhrases: Set<String> = ignoredPhrases.map(::collapse).toSet()

    fun isNoise(line: RecognizedLine): Boolean {
        if (line.confidence < minConfidence) return true
        val visible = line.text.filterNot { it.isWhitespace() }
        val letters = visible.count { it.isLetter() }
        if (letters < minLetters) return true
        if (letters * 2 < visible.length) return true
        return collapse(line.text) in ignoredPhrases
    }

    fun clean(lines: List<RecognizedLine>, region: NormalizedRect): List<RecognizedLine> =
        lines.filter { region.contains(it.box.midX, it.box.midY) && !isNoise(it) }
            .sortedWith(compareBy({ it.box.y }, { it.box.x }))

    /** Hiç satır kalmazsa null (boş kare). */
    fun text(lines: List<RecognizedLine>, region: NormalizedRect): String? {
        val joined = squeeze(clean(lines, region).joinToString(" ") { it.text })
        return joined.ifEmpty { null }
    }

    companion object {
        val DEFAULT_IGNORED = setOf(
            "options", "menu", "skip", "pause", "back", "select", "confirm",
            "continue", "loading", "settings", "map", "inventory",
        )

        fun squeeze(text: String): String = text.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        fun collapse(text: String): String = squeeze(text).lowercase()
    }
}
