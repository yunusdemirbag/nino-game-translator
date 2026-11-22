// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import com.ninotranslator.core.reading.TextSimilarity

/** Sabitleyicinin bir okumaya yanıtı (okuma.md 5). */
sealed interface LiveDecision {
    data object Nothing : LiveDecision
    /** Yeni satır. [replacesPrevious]: TV'de öncekinin yerine koy (uzayan/düzelen yazı). */
    data class Translate(val text: String, val replacesPrevious: Boolean) : LiveDecision
    data object Clear : LiveDecision
    /** Az önce kalkan satır geri geldi; eski çeviri gösterilir. */
    data class Restore(val text: String) : LiveDecision
}

data class LiveStabilizerConfig(
    val stableReadings: Int = 2,
    val similarity: Double = 0.85,
    val clearAfterMs: Long = 800,
    val holdInPlaceMs: Long = 4000,
    val restoreWindowMs: Long = 1500,
    val restoreHistory: Int = 5,
    val failedRetryMs: Long = 1000,
    val garbageMinMs: Long = 700,
)

/**
 * Canlı sabitleyici. Zaman dışarıdan ms olarak verilir. Tek iş parçacığında kullanılır.
 */
class LiveStabilizer(private val cfg: LiveStabilizerConfig = LiveStabilizerConfig()) {
    private class Shown(val text: String, var box: LiveBox?, var trace: RegionTrace?)
    private class Candidate(var text: String, var count: Int, val firstSeen: Long)
    private class Gone(val text: String, val goneAt: Long)

    private var shown: Shown? = null
    private var candidate: Candidate? = null
    private var emptySince: Long? = null
    private var movedAt: Long? = null
    private val recent = ArrayDeque<Gone>()
    private var failedText: String? = null
    private var failedAt = 0L

    /** Ekranda sayılan (son gönderilen) satır. */
    val shownText: String? get() = shown?.text

    /**
     * @param trace bölgenin 64×12 izi; boş okumada "yazı yerinde mi" sorusu için.
     */
    fun onReading(reading: LiveReading, nowMs: Long, trace: RegionTrace? = null): LiveDecision {
        val text = reading.text
        if (LiveText.key(text).length < 3) return onEmpty(nowMs, trace)
        emptySince = null
        movedAt = null

        val s = shown
        if (s != null && (isSameSubtitle(text, s.text, cfg.similarity) || isWorseReread(text, s.text))) {
            candidate = null
            reading.box?.let { s.box = it }
            trace?.let { s.trace = it }
            return LiveDecision.Nothing
        }
        val f = failedText
        if (f != null && isSameSubtitle(text, f, cfg.similarity)) {
            candidate = null
            if (nowMs - failedAt < cfg.failedRetryMs) return LiveDecision.Nothing
            failedText = null
            return translate(text, reading, trace, nowMs)
        }

        val c = candidate
        if (c != null && sameCandidate(c.text, text)) { c.count++; c.text = text } else candidate = Candidate(text, 1, nowMs)
        val cc = candidate!!
        if (!isStable(cc, nowMs)) return LiveDecision.Nothing
        candidate = null

        val back = recent.lastOrNull { nowMs - it.goneAt <= cfg.restoreWindowMs && isSameSubtitle(text, it.text, cfg.similarity) }
        if (back != null) {
            recent.remove(back)
            retire(nowMs)
            shown = Shown(back.text, reading.box, trace)
            return LiveDecision.Restore(back.text)
        }
        return translate(text, reading, trace, nowMs)
    }

    /** Çevirisi başarısız oldu: satır unutulur, ekranda kalırsa en erken 1000 ms sonra yeniden çevrilir. */
    fun onTranslationFailed(text: String, nowMs: Long) {
        if (shown?.text == text) shown = null
        failedText = text
        failedAt = nowMs
    }

    fun reset() {
        shown = null; candidate = null; emptySince = null; movedAt = null; recent.clear(); failedText = null
    }

    private fun translate(text: String, reading: LiveReading, trace: RegionTrace?, now: Long): LiveDecision {
        val prev = shown
        val replaces = prev != null && isGrowthOrCorrection(prev.text, text)
        retire(now)
        shown = Shown(text, reading.box, trace)
        return LiveDecision.Translate(text, replaces)
    }

    private fun retire(now: Long) {
        val s = shown ?: return
        recent.addLast(Gone(s.text, now))
        while (recent.size > cfg.restoreHistory) recent.removeFirst()
        shown = null
    }

    private fun onEmpty(now: Long, trace: RegionTrace?): LiveDecision {
        candidate = null
        val s = shown
        if (s == null) { failedText = null; return LiveDecision.Nothing }
        val since = emptySince ?: now.also { emptySince = it }
        val ref = s.trace
        val clearAt = if (trace != null && ref != null) {
            if (movedAt == null && trace.changedFrom(ref, s.box)) movedAt = now
            val m = movedAt
            if (m == null) since + cfg.holdInPlaceMs else minOf(m + cfg.clearAfterMs, since + cfg.holdInPlaceMs)
        } else since + cfg.clearAfterMs
        if (now < clearAt) return LiveDecision.Nothing
        retire(now)
        emptySince = null; movedAt = null; failedText = null
        return LiveDecision.Clear
    }

    private fun sameCandidate(a: String, b: String): Boolean =
        !LiveText.addsMarker(a, b) && !LiveText.addsMarker(b, a) && LiveText.key(a).isNotEmpty() &&
            TextSimilarity.isSame(a, b, cfg.similarity)

    private fun isStable(c: Candidate, now: Long): Boolean = when {
        LiveText.isGarbageReading(c.text) -> c.count >= cfg.stableReadings && now - c.firstSeen >= cfg.garbageMinMs
        LiveText.endsSentence(c.text) -> true
        else -> c.count >= cfg.stableReadings
    }

    companion object {
        const val ALREADY_TRANSLATED = 0.90

        /** Okuma, gönderilen satırın yeniden okuması mı? (bölüm 5, "aynı altyazı") */
        fun isSameSubtitle(reading: String, sent: String, threshold: Double = 0.85): Boolean {
            val rk = LiveText.key(reading); val sk = LiveText.key(sent)
            if (rk.isEmpty() || sk.isEmpty()) return false
            // 1. Eklenen olumsuzluk ya da sayı.
            if (LiveText.addsMarker(reading, sent)) return false
            // 2. Başına ya da sonuna sözcük eklenmiş.
            if (LiveText.isWordExtension(reading, sent)) return false
            // 3. Karakter benzerliği.
            if (TextSimilarity.ratioOfKeys(rk, sk) >= threshold) return true
            // 4. Kesik okuma: yalnız tam satırlar eksikse aynı.
            val sl = sent.split('\n').filter { it.isNotBlank() }
            for (k in 1 until sl.size) {
                val head = sl.subList(0, k).joinToString("\n")
                val tail = sl.subList(sl.size - k, sl.size).joinToString("\n")
                if (LiveText.similarity(reading, head) >= threshold || LiveText.similarity(reading, tail) >= threshold) return true
            }
            if (rk != sk && (sk.startsWith(rk) || sk.endsWith(rk))) return false
            // 5. Sözcüklerin %85'i gönderilende.
            val rw = LiveText.compareWords(reading); val sw = LiveText.compareWords(sent)
            if (rw.size >= 4 && LiveText.commonCount(rw, sw) >= 0.85 * rw.size) return true
            // 6. Uzun iki okumada ortak sözcükler.
            if (rw.size >= 6 && sw.size >= 6) {
                val mx = maxOf(rw.size, sw.size); val mn = minOf(rw.size, sw.size)
                if (mn.toDouble() / mx >= 0.75 && LiveText.commonCount(rw, sw) >= 0.75 * mx) return true
            }
            return false
        }

        /** Gönderilenin bozuk ve daha iyi olmayan yeniden okuması mı? */
        fun isWorseReread(reading: String, sent: String): Boolean {
            val n = LiveText.wordCount(reading)
            if (n < 5 || n > LiveText.wordCount(sent)) return false
            if (LiveText.addsMarker(reading, sent) || LiveText.isWordExtension(reading, sent)) return false
            if (!LiveText.isGarbageReading(reading) && !LiveText.isBrokenReading(reading) &&
                LiveText.tokens(reading).none { LiveText.isGarbageWord(it) }) return false
            if (LiveText.wordSequenceSimilarity(reading, sent) < 0.65 && LiveText.similarity(reading, sent) < 0.75) return false
            return LiveText.qualityScore(reading) < LiveText.qualityScore(sent) + 4
        }

        /** Yeni satır öncekinin büyümesi ya da düzeltmesi mi? ("yerine koy") */
        fun isGrowthOrCorrection(prev: String, next: String): Boolean {
            val a = LiveText.key(prev); val b = LiveText.key(next)
            if (a.isEmpty() || b.isEmpty()) return false
            if (a.startsWith(b) || b.startsWith(a) || a.endsWith(b) || b.endsWith(a)) return true
            if (TextSimilarity.ratioOfKeys(a, b) >= 0.8) return true
            if (LiveText.wordCount(prev) >= 5 && LiveText.wordCount(next) >= 5 &&
                (LiveText.wordSequenceSimilarity(prev, next) >= 0.65 || LiveText.commonWordRatio(prev, next) >= 0.7)) return true
            return false
        }

        /**
         * Çeviri TV'ye gider mi? Kaynağa 0.90 ve üstü benzeyen çeviri gitmez. Paketten gelen her zaman
         * gider; yalnız kaynakta Türkçe harf varsa (PS5'in kendi ekranı) benzerlik kuralı uygulanır.
         */
        fun shouldShow(source: String, translation: String, fromPack: Boolean): Boolean {
            if (fromPack && !LiveText.hasTurkishLetters(source)) return true
            return LiveText.similarity(source, translation) < ALREADY_TRANSLATED
        }
    }
}
