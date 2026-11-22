// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import kotlinx.coroutines.withTimeout

/** Cihaz içi çevirmen (app'te ML Kit). İngilizceden hedef dile; hata atar. */
interface OnDeviceTranslator {
    suspend fun translate(text: String, target: TargetLanguage): String
}

/** Son gösterilen satırlar (bağlam için). Saat dışarıdan. */
class RecentLines(private val now: () -> Long, private val keep: Int = 8) {
    data class Shown(val source: String, val translation: String, val atMs: Long)
    private val list = ArrayDeque<Shown>()

    @Synchronized fun record(source: String, translation: String) {
        list.removeAll { it.source == source }
        list.addLast(Shown(source, translation, now()))
        while (list.size > keep) list.removeFirst()
    }

    /** [withinMs] içindeki en çok [n] satır, [except] hariç; eskiden yeniye. */
    @Synchronized fun last(n: Int, withinMs: Long? = null, except: String? = null): List<Shown> {
        val t = now()
        return list.filter { (withinMs == null || t - it.atMs <= withinMs) && it.source != except }.takeLast(n)
    }

    @Synchronized fun clear() = list.clear()
}

/**
 * Cihaz içi çeviri hattı (ceviri.md 3.1 Türkçe, 3.2 öbür diller). Önbellek motor adı `mlkit-p3`.
 * Çevirmen de hata verirse [translate] hata atar (satır gösterilmez, yeniden denenir).
 */
class OnDeviceLineTranslator(
    private val translator: OnDeviceTranslator,
    private val cacheFor: (TargetLanguage) -> LineCache,
    private val glossary: () -> Glossary,
    private val recent: RecentLines,
    private val now: () -> Long,
    private val timeoutMs: Long = 10_000,
) {
    private val contextOf = object : LinkedHashMap<String, String?>(32, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, String?>?) = size > 32
    }

    suspend fun translate(line: String, target: TargetLanguage): String =
        if (target.isTurkish) turkish(line) else other(line, target)

    /** Tek cümle, ham (bağlamsız, korumasız) — yapay zekânın geri verdiği cümleyi denemek için. */
    suspend fun raw(text: String, target: TargetLanguage): String = withTimeout(timeoutMs) { translator.translate(text, target) }

    // ---- öbür diller ----

    private suspend fun other(line: String, target: TargetLanguage): String {
        val cache = cacheFor(target)
        cache.get(line)?.let { return it }
        val out = ArrayList<String>()
        for (s in LineText.sentences(line.replace('\n', ' '))) {
            val src = TurkishText.sentenceCase(s)
            val t = cache.get(src) ?: raw(src, target).trim().also { cache.put(src, it) }
            out += t
        }
        val joined = out.joinToString(" ")
        cache.put(line, joined)
        return joined
    }

    // ---- Türkçe ----

    private data class Utterance(val prefix: String, val body: String)

    /** Etiketli ya da tireli satır yeni konuşma; öbür satır sonları sarma. */
    private fun utterances(line: String): List<Utterance> {
        val out = ArrayList<Utterance>()
        for (raw in line.split('\n').map { it.trim() }.filter { it.isNotEmpty() }) {
            val p = LineText.prefix(raw)
            if (p != null || out.isEmpty()) out += Utterance(p?.prefix ?: "", p?.body ?: raw)
            else out[out.size - 1] = out.last().copy(body = out.last().body + " " + raw)
        }
        return out
    }

    private suspend fun turkish(line: String): String {
        val g = glossary()
        val utts = utterances(line)
        val names = HashSet(g.properWords)
        for (u in utts) LineText.speakerLabel(u.prefix.trimStart('-', '–', '—', ' ') + "x")?.prefix?.trimEnd(':', ' ')?.split(' ')?.let { names += it }
        // Bağlam: aynı satır yeniden okunursa aynı bağlam.
        val previous: String? = synchronized(contextOf) {
            if (contextOf.containsKey(line)) contextOf[line] else {
                val p = recent.last(1, withinMs = 20_000, except = line).lastOrNull()?.source?.let { LineText.sentences(it).lastOrNull() }
                contextOf[line] = p
                p
            }
        }
        val translated = ArrayList<MutableList<String>>()
        var prevSentence = previous
        for (u in utts) {
            val list = ArrayList<String>()
            val whole = g.line(u.body)
            if (whole != null) { list += whole; prevSentence = u.body; translated += list; continue }
            for (s in LineText.sentences(u.body)) {
                val cased = TurkishText.sentenceCase(s, names)
                list += sentence(cased, prevSentence, g)
                prevSentence = cased
            }
            translated += list
        }
        val flat = TurkishText.unifyAddress(translated.flatten())
        var k = 0
        return utts.mapIndexed { i, u -> u.prefix + translated[i].indices.joinToString(" ") { flat[k++] } }.joinToString("\n")
    }

    private suspend fun sentence(sentence: String, context: String?, g: Glossary): String {
        g.line(sentence)?.let { return it }
        val cache = cacheFor(TargetLanguage.TR)
        val prepared = TurkishText.applyIdioms(g.applyPhrases(sentence))
        val hits = g.find(prepared)
        val useContext = context != null && LineText.wordCount(sentence) in 1..3
        val key = buildString {
            if (hits.isNotEmpty()) append(g.fingerprint).append(LineCache.SEPARATOR)
            if (useContext) append(context).append(LineCache.SEPARATOR)
            append(sentence)
        }
        cache.get(key)?.let { return it }
        val ctx = if (useContext) TurkishText.applyIdioms(g.applyPhrases(context!!)) else null
        val result = attempt(prepared, hits, ctx, shield = true)
            ?: (if (ctx != null) attempt(prepared, hits, null, shield = true) else null)
            ?: attempt(prepared, hits, null, shield = false)
            ?: raw(prepared, TargetLanguage.TR)
        val final = TurkishText.postProcess(result.trim(), sentence)
        cache.put(key, final)
        return final
    }

    /** Bir deneme; sonuç güvenilmezse null. */
    private suspend fun attempt(text: String, hits: List<Glossary.Hit>, context: String?, shield: Boolean): String? {
        val sh = if (shield && hits.isNotEmpty()) TermShield.shield(text, hits, context ?: "") else null
        val body = sh?.text ?: text
        val request = if (context != null) "$context$CONTEXT_SEPARATOR$body" else body
        val raw = raw(request, TargetLanguage.TR)
        val part = if (context != null) afterSeparator(raw, body) ?: return null else raw
        return if (sh != null) TermShield.restore(part, sh) else part
    }

    companion object {
        const val ENGINE_NAME = "mlkit-p3"
        const val CONTEXT_SEPARATOR = " *** "

        /** Bağlamlı çeviriden ayracın sonrası; kurallara uymazsa null. */
        fun afterSeparator(translated: String, source: String): String? {
            val first = translated.indexOf("***")
            if (first < 0 || translated.indexOf("***", first + 3) >= 0) return null
            if (first > 0 && translated[first - 1] == '*') return null
            if (first + 3 < translated.length && translated[first + 3] == '*') return null
            val before = translated.substring(0, first); val after = translated.substring(first + 3).trim()
            if (before.none { it.isLetter() } || after.none { it.isLetter() }) return null
            if (after.length > source.length * 3 + 20) return null
            return after
        }
    }
}
