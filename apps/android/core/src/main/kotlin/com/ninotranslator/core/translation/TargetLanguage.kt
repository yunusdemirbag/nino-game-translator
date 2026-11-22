// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

/** Seçilebilen 11 hedef dil (ceviri.md 2). Kod ayarın ilk iki harfidir. */
enum class TargetLanguage(val code: String) {
    TR("tr"), AR("ar"), HI("hi"), ID("id"), TH("th"), VI("vi"), UR("ur"), BN("bn"), MS("ms"), TL("tl"), NL("nl");

    val isTurkish: Boolean get() = this == TR
    val isRightToLeft: Boolean get() = this == AR || this == UR

    /** Satır zaten bu dilin yazısında mı (PS5'in kendi menüsü). Yalnız kendine özgü yazısı olan dillerde. */
    fun isAlreadyInTarget(text: String): Boolean {
        val script: (Int) -> Boolean = when (this) {
            AR, UR -> { cp -> Character.UnicodeScript.of(cp) == Character.UnicodeScript.ARABIC }
            TH -> { cp -> Character.UnicodeScript.of(cp) == Character.UnicodeScript.THAI }
            HI -> { cp -> Character.UnicodeScript.of(cp) == Character.UnicodeScript.DEVANAGARI }
            BN -> { cp -> Character.UnicodeScript.of(cp) == Character.UnicodeScript.BENGALI }
            else -> return false
        }
        return text.codePoints().anyMatch { Character.isLetter(it) && script(it) }
    }

    /** Sağdan sola dillerde Arap harfli her paragrafın başına U+200F konur. */
    fun forDisplay(text: String): String {
        if (!isRightToLeft) return text
        return text.split('\n').joinToString("\n") { p ->
            if (p.codePoints().anyMatch { Character.UnicodeScript.of(it) == Character.UnicodeScript.ARABIC } && !p.startsWith('‏')) "‏$p" else p
        }
    }

    companion object {
        /** Kayıtlı ayardan: ilk iki harf küçültülür; Android'in eski kodları ("in", "fil") tanınır. */
        fun of(value: String?): TargetLanguage? {
            val v = value?.trim()?.lowercase() ?: return null
            if (v.startsWith("fil")) return TL
            val c = v.take(2).let { if (it == "in") "id" else it }
            return values().firstOrNull { it.code == c }
        }

        /** Anahtarlı çeviri hizmetinin (DeepL) desteklediği hedefler. */
        val DEEPL_TARGETS = setOf(TR, AR, ID, TH, VI, NL)
    }
}
