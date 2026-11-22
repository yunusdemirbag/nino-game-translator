// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Çeviri sırası: önbellek → oyun paketi → çevirmen zinciri (ceviri.md). */
class Translator(
    private val cache: TranslationCache = TranslationCache(),
    private val chain: ProviderChain,
    @Volatile var pack: PhraseLookup? = null,
    @Volatile var userTerms: List<Term> = emptyList(),
    val sourceLanguage: String = "en",
    val targetLanguage: String = "tr",
    private val postProcessor: TurkishPostProcessor? = TurkishPostProcessor(),
    saveEvery: Int = 20,
) {
    val saveEvery = maxOf(1, saveEvery)
    private val lock = Mutex()
    private var unsaved = 0

    suspend fun translate(sentence: String): Translation {
        val source = sentence.trim()
        if (source.isEmpty()) return Translation(sentence, sentence, TranslationOrigin.None)
        cache.lookup(source)?.let { return Translation(source, it, TranslationOrigin.Cache) }
        val pack = pack
        pack?.lookup(source)?.let { return Translation(source, it, TranslationOrigin.Pack) }
        val protector = TermProtector(userTerms + (pack?.terms ?: emptyList()))
        val protected = protector.protect(source)
        val leftover = TermProtector.PLACEHOLDER.replace(protected.text, "")
        if (protected.replacements.isNotEmpty() && leftover.none { it.isLetter() }) {
            protector.restore(protected.text, protected)?.let { return Translation(source, it, TranslationOrigin.Pack) }
        }
        val result = chain.translate(protected.text, sourceLanguage, targetLanguage) { protector.restore(it, protected) != null }
        val restored = result?.let { protector.restore(it.text, protected) }
            ?: return Translation(source, source, TranslationOrigin.None)
        val text = postProcessor?.process(restored, source) ?: restored
        cache.store(source, text, result.provider)
        val flushNow = lock.withLock { ++unsaved >= saveEvery }
        if (flushNow) flush()
        return Translation(source, text, TranslationOrigin.Provider(result.provider))
    }

    suspend fun translate(sentences: List<String>): List<Translation> = sentences.map { translate(it) }

    suspend fun flush() {
        runCatching { cache.save() }
        lock.withLock { unsaved = 0 }
    }
}
