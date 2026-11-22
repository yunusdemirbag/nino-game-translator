// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

/** Önbellek ve paket eşleştirmesinin anahtarı (ceviri.md, "Anahtar"). */
object TranslationKey {
    fun make(text: String): String {
        val b = StringBuilder(text.length)
        for (ch in text) when (ch) {
            '“', '”', '„' -> b.append('"')
            '‘', '’', '‚' -> b.append('\'')
            '…' -> b.append("...")
            else -> b.append(ch)
        }
        return b.toString().lowercase().trim().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
    }
}

/** Çevirinin nereden geldiği. */
sealed interface TranslationOrigin {
    data object Cache : TranslationOrigin
    data object Pack : TranslationOrigin
    data class Provider(val name: String) : TranslationOrigin
    data object None : TranslationOrigin
}

data class Translation(val source: String, val text: String, val origin: TranslationOrigin) {
    val failed: Boolean get() = origin == TranslationOrigin.None
}

/** Oyun terimi. target yoksa olduğu gibi korunur. */
data class Term(val source: String, val target: String? = null) {
    val replacement: String get() = target ?: source
}

/** Bir çevirmen sağlayıcısı. Adı geneldir (marka adı kullanılmaz). */
interface TranslationProvider {
    val name: String
    suspend fun translate(text: String, source: String, target: String): String
}

class TranslationProviderException(val kind: Kind, val status: Int = 0) : Exception(kind.name) {
    enum class Kind { TIMEOUT, EMPTY, BAD_RESPONSE, HTTP }
}

/** Hazır çeviri arayan her şey (oyun paketleri). */
interface PhraseLookup {
    fun lookup(sentence: String): String?
    val terms: List<Term>
}
