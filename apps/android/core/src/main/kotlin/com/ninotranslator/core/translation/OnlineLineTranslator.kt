// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import com.ninotranslator.core.reading.TextSimilarity

/**
 * Anahtarlı çevrimiçi çevirmenin satır kuralları (ceviri.md 7.1): satır cümlelere bölünür, etiketler çevrilmez,
 * önbellekteki cümleler gönderilmez, eksikler büyük harf düzeninden geçip tek istekte gider; satırın tamamı da yazılır.
 * Dinlenme: hata → 60 sn; dakikalık sınır → 1-20 sn (uyarısız).
 */
class OnlineLineTranslator(
    val engine: OnlineEngine,
    private val cacheFor: (TargetLanguage) -> LineCache,
    private val glossary: () -> Glossary,
    private val now: () -> Long,
    /** Yapay zekâ cümleyi çevirmeden geri verirse bir kez denenecek cihaz içi çeviri. */
    private val onDeviceRetry: (suspend (String, TargetLanguage) -> String)? = null,
) {
    @Volatile var restingUntil: Long = 0
        private set
    /** Ana ekrandaki anahtar uyarısı (son hata); başarılı istekte kalkar. */
    @Volatile var warning: KeyStatus? = null
        private set

    /** Her gerçek istek sonucunda (önbellek değil): hata yoksa null. Otomatik teşhis için; metin taşımaz. */
    @Volatile var onRequest: ((OnlineError?) -> Unit)? = null

    fun isResting(): Boolean = now() < restingUntil

    private fun cacheKey(sentence: String, game: String?, hits: List<Glossary.Hit>, g: Glossary): String = when {
        engine is AiEngine && !game.isNullOrBlank() -> game + LineCache.SEPARATOR + sentence
        engine is DeepLEngine && hits.isNotEmpty() -> g.fingerprint + LineCache.SEPARATOR + sentence
        else -> sentence
    }

    /** Satırı çevirir; hata, dinlenme ya da hak bitiminde [OnlineError] atar (çağıran cihaz içine düşer). */
    suspend fun translate(line: String, target: TargetLanguage, context: List<ContextLine>, game: String?): String {
        if (isResting()) throw OnlineError(KeyStatus.UNREACHABLE, rateLimitedMs = 0, message = "dinleniyor")
        val cache = cacheFor(target)
        val g = if (target.isTurkish) glossary() else Glossary.EMPTY
        val lineKey = if (engine is AiEngine && !game.isNullOrBlank()) game + LineCache.SEPARATOR + line else line
        cache.get(lineKey)?.let { return it }

        data class Part(val prefix: String, val sentences: List<String>)
        val parts = line.split('\n').map { it.trim() }.filter { it.isNotEmpty() }.map { raw ->
            val p = LineText.prefix(raw)
            Part(p?.prefix ?: "", LineText.sentences(p?.body ?: raw).map { TurkishText.sentenceCase(it) })
        }
        val all = parts.flatMap { it.sentences }
        val hits = all.map { if (target.isTurkish) g.find(it) else emptyList() }
        val results = arrayOfNulls<String>(all.size)
        val missing = ArrayList<Int>()
        var allStored = true
        for (i in all.indices) {
            val c = cache.get(cacheKey(all[i], game, hits[i], g))
            if (c != null) results[i] = c else missing += i
        }
        if (missing.isNotEmpty()) {
            val request = OnlineRequest(missing.map { all[it] }, target, context, game, missing.map { hits[it] })
            val got = try {
                engine.translateAsync(request).also { warning = null; onRequest?.invoke(null) }
            } catch (e: OnlineError) {
                onRequest?.invoke(e)
                if (e.rateLimitedMs != null) restingUntil = now() + e.rateLimitedMs.coerceIn(1_000L, 20_000L)
                else { restingUntil = now() + 60_000; warning = e.status }
                throw e
            }
            for ((j, i) in missing.withIndex()) {
                var t = got[j].trim()
                if (target.isTurkish) t = TurkishText.postProcess(t, all[i])
                var store = true
                val retry = onDeviceRetry
                if (engine is AiEngine && retry != null && TextSimilarity.ratio(t, all[i]) >= 0.90) {
                    val alt = runCatching { retry(all[i], target).trim() }.getOrNull()
                    if (alt != null && alt.isNotEmpty() && TextSimilarity.ratio(alt, all[i]) < 0.90) { t = alt; store = false }
                }
                results[i] = t
                if (!store) allStored = false
                if (store) cache.put(cacheKey(all[i], game, hits[i], g), t)
            }
        }
        var k = 0
        val text = parts.joinToString("\n") { p -> p.prefix + p.sentences.joinToString(" ") { results[k++]!! } }
        if (allStored) cache.put(lineKey, text)
        return text
    }
}
