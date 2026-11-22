// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

/** Çeviri dili ve arayüz dili kuralları (§5.3). Saf; Android'e bağlı değil. */
object AppLanguage {
    /** Çeviri dilleri (iki harfli). Filipince `tl` olarak tutulur. */
    val TARGET_LANGUAGES = listOf("tr", "ar", "hi", "id", "th", "vi", "ur", "bn", "ms", "tl", "nl")

    /** Uygulamanın arayüz dilleri (`locales_config`). */
    val UI_TAGS = listOf("tr", "en", "ar", "hi", "id", "th", "vi", "ur", "bn", "ms", "fil", "nl")

    /** Telefon dilinden çeviri dili: `in` → `id`, `fil…` → `tl`; listede yoksa `tr`. */
    fun fromDevice(language: String?): String {
        val code = canonical(language)
        return if (code in TARGET_LANGUAGES) code else "tr"
    }

    /** Kaydedilecek biçim: ilk iki harf, küçük. */
    fun normalizeForSave(code: String): String = canonical(code).ifEmpty { "tr" }

    /** Çeviri dilinden arayüz etiketi: `tl` → `fil`; listedekiler aynı; diğerleri `en`. */
    fun uiTag(targetLanguage: String?): String {
        val code = canonical(targetLanguage)
        return when {
            code == "tl" -> "fil"
            code in TARGET_LANGUAGES -> code
            else -> "en"
        }
    }

    fun isRtl(tag: String?): Boolean = canonical(tag) == "ar" || canonical(tag) == "ur"

    private fun canonical(code: String?): String {
        val c = code?.trim()?.lowercase().orEmpty().substringBefore('-').substringBefore('_')
        return when {
            c.startsWith("fil") -> "tl"
            c == "in" -> "id"
            else -> c.take(2)
        }
    }
}
