// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/** Çeviri sonucu; null dönen çeviri başarısızdır. */
data class LiveTranslation(val text: String, val fromPack: Boolean = false)

enum class LiveShowKind { NEW, RESTORED, UPDATED }

/** TV'ye/ekrana gidecek gösterim. */
data class LiveShow(
    val source: String,
    val translation: String,
    val durationMs: Long,
    val replacesPrevious: Boolean,
    val fromPack: Boolean,
    val kind: LiveShowKind,
)

/**
 * Bekletme ve çeviri sırası (okuma.md 6). Çeviriyi kendisi yapmaz; [translate] verilir. Tüm çağrılar
 * ve [scope] tek iş parçacığında olmalıdır.
 */
class LiveTranslationQueue(
    private val scope: CoroutineScope,
    private val clock: LiveClock,
    private val translate: suspend (String) -> LiveTranslation?,
    private val inPack: (String) -> Boolean = { false },
    private val onShow: (LiveShow) -> Unit,
    private val onFailed: (String) -> Unit = {},
) {
    private class Req(var text: String, val replaces: Boolean, val seq: Long) {
        var goneAt: Long? = null
        var suppressed = false
    }
    private class Held(var req: Req, val deadline: Long)
    private class Running(val req: Req, val job: Job)
    private class Last(val source: String, val seq: Long, val at: Long, val fromPack: Boolean) { var goneAt: Long? = null }

    private var seq = 0L
    private var hold: Held? = null
    private val waiting = ArrayDeque<Req>()
    private var running: Running? = null
    private var last: Last? = null
    private val cache = LinkedHashMap<String, LiveTranslation>()

    /** Bekleyen ve süren satırlar (test ve günlük için). */
    val heldText: String? get() = hold?.req?.text
    val waitingTexts: List<String> get() = waiting.map { it.text }
    val runningText: String? get() = running?.req?.text

    /** Sabitleyicinin "çevir" kararı. */
    fun submit(text: String, replacesPrevious: Boolean = false) {
        val now = clock.nowMs()
        tick()
        val l = last
        if (l != null && now - l.at <= RECENT_REREAD_MS && isReread(text, l.source) && !LiveText.addsMarker(text, l.source) &&
            LiveText.qualityScore(text) <= LiveText.qualityScore(l.source)) return
        hold?.let { h -> if (absorbIntoHold(h, text, ignoreBroken = true)) return; releaseHold(h) }
        val req = Req(text, replacesPrevious, ++seq)
        when {
            inPack(text) -> enqueue(req)
            LiveText.isBrokenReading(text) -> hold = Held(req, now + BROKEN_HOLD_MS)
            LiveText.maybePartial(text) -> hold = Held(req, now + PARTIAL_HOLD_MS)
            else -> enqueue(req)
        }
    }

    /** Sabitleyicinin "geri getir" kararı: son 8 çeviriden verilir. Yoksa false. */
    fun restore(text: String): Boolean {
        val key = cache.keys.lastOrNull { LiveStabilizer.isSameSubtitle(text, it) } ?: return false
        val t = cache[key]!!
        val s = ++seq
        cancelRunningIfOlder(s)
        last = Last(key, s, clock.nowMs(), t.fromPack)
        onShow(LiveShow(key, t.text, ON_SCREEN_MS, false, t.fromPack, LiveShowKind.RESTORED))
        return true
    }

    /** Her okumada çağrılır (boş okuma için boş yazı). */
    fun onReading(text: String) {
        val now = clock.nowMs()
        val empty = LiveText.key(text).length < 3
        for (r in active()) r.goneAt = if (!empty && stillThere(text, r.text)) null else (r.goneAt ?: now)
        last?.let { it.goneAt = if (!empty && stillThere(text, it.source)) null else (it.goneAt ?: now) }
        val h = hold
        if (h != null) {
            if (empty) releaseHold(h, dropBroken = true) else absorbIntoHold(h, text, ignoreBroken = false)
        }
        tick()
        val r = running
        if (r != null && r.req.goneAt != null && waiting.isNotEmpty()) cancelRunning()
    }

    /** Bekletme süresi dolanları sıraya alır. */
    fun tick() {
        val h = hold ?: return
        if (clock.nowMs() >= h.deadline) releaseHold(h)
    }

    /** Sunucudan sonradan daha iyi çeviri: satır ekrandaysa yerinde değişir (paket satırına dokunulmaz). */
    fun improve(source: String, better: String) {
        val l = last ?: return
        if (l.fromPack || l.goneAt != null || LiveText.key(l.source) != LiveText.key(source)) return
        put(l.source, LiveTranslation(better))
        onShow(LiveShow(l.source, better, ON_SCREEN_MS, true, false, LiveShowKind.UPDATED))
    }

    private fun active(): List<Req> = buildList {
        hold?.let { add(it.req) }
        addAll(waiting)
        running?.let { add(it.req) }
    }

    private fun stillThere(reading: String, text: String) =
        LiveStabilizer.isSameSubtitle(reading, text) || isReread(reading, text) || LiveStabilizer.isWorseReread(reading, text)

    /** Bekleyenin yeniden okuması mı? Öyleyse gerekirse yerine geçer. */
    private fun absorbIntoHold(h: Held, text: String, ignoreBroken: Boolean): Boolean {
        val old = h.req.text
        if (LiveText.addsMarker(text, old)) {
            // Olumsuzluk ya da sayı düzeltmesi bekleyenin yerini alır.
            if (LiveText.similarity(text, old) >= 0.6 || LiveText.commonWordRatio(text, old) >= 0.6) { h.req.text = text; return true }
            return false
        }
        if (isReread(text, old) || isReread(old, text)) {
            val merged = mergeKeepingCleanLines(old, text)
            if (LiveText.qualityScore(merged) > LiveText.qualityScore(old)) h.req.text = merged
            return true
        }
        return ignoreBroken && LiveText.isBrokenReading(text)
    }

    private fun releaseHold(h: Held, dropBroken: Boolean = false) {
        hold = null
        if (dropBroken && LiveText.isBrokenReading(h.req.text)) return
        enqueue(h.req)
    }

    private fun enqueue(req: Req) {
        waiting.removeAll { isReread(it.text, req.text) || isReread(req.text, it.text) }
        running?.let { r ->
            val a = LiveText.key(r.req.text); val b = LiveText.key(req.text)
            if (b.length > a.length && (b.startsWith(a) || LiveText.isWordExtension(req.text, r.req.text))) r.req.suppressed = true
        }
        waiting.addLast(req)
        while (waiting.size > MAX_WAITING) waiting.removeFirst()
        if (running?.req?.goneAt != null) cancelRunning()
        pump()
    }

    private fun pump() {
        if (running != null) return
        val req = waiting.removeFirstOrNull() ?: return
        val job = scope.launch(start = CoroutineStart.LAZY) {
            val result = try {
                translate(req.text)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                null
            }
            if (running?.req !== req) return@launch
            running = null
            finish(req, result)
            pump()
        }
        running = Running(req, job)
        job.start()
    }

    private fun finish(req: Req, result: LiveTranslation?) {
        if (result == null) { onFailed(req.text); return }
        put(req.text, result)
        if (req.suppressed) return
        if ((last?.seq ?: 0) > req.seq) return
        val now = clock.nowMs()
        val gone = req.goneAt
        if (gone != null && now - gone > LATE_LIMIT_MS) return
        if (!LiveStabilizer.shouldShow(req.text, result.text, result.fromPack)) return
        val duration = if (gone == null) ON_SCREEN_MS else lateDisplayMs(result.text)
        last = Last(req.text, req.seq, now, result.fromPack).also { it.goneAt = gone }
        onShow(LiveShow(req.text, result.text, duration, req.replaces, result.fromPack, LiveShowKind.NEW))
    }

    private fun cancelRunningIfOlder(s: Long) {
        val r = running ?: return
        if (r.req.seq < s) cancelRunning()
    }

    private fun cancelRunning() {
        val r = running ?: return
        running = null
        r.job.cancel()
        pump()
    }

    private fun put(source: String, t: LiveTranslation) {
        cache.remove(source)
        cache[source] = t
        while (cache.size > CACHE_SIZE) cache.remove(cache.keys.first())
    }

    companion object {
        const val BROKEN_HOLD_MS = 800L
        const val PARTIAL_HOLD_MS = 300L
        const val RECENT_REREAD_MS = 4000L
        const val MAX_WAITING = 2
        const val LATE_LIMIT_MS = 2500L
        const val ON_SCREEN_MS = 15000L
        const val CACHE_SIZE = 8

        /** Kalkmış satırın geç gelen çevirisi: en çok 8000, 2000 + harf × 60 ms. */
        fun lateDisplayMs(text: String): Long = minOf(8000L, 2000L + LiveText.letterCount(text) * 60L)

        /** Bölüm 6: iki okuma aynı satırın yeniden okuması mı? */
        fun isReread(a: String, old: String): Boolean {
            val aw = LiveText.key(a).split(' ').filter { it.isNotEmpty() }
            val ow = LiveText.key(old).split(' ').filter { it.isNotEmpty() }
            if (aw.isEmpty() || ow.isEmpty()) return false
            val broken = LiveText.isBrokenReading(a) || LiveText.isBrokenReading(old)
            if (broken) {
                val common = LiveText.commonCount(aw, ow)
                if (common >= 2 && common * 2 >= minOf(aw.size, ow.size)) return true
            }
            if (aw.size == ow.size && LiveText.similarity(a, old) >= 0.75) return true
            val ta = LiveText.tokens(a); val to = LiveText.tokens(old)
            val onlyA = ta.filter { t -> LiveText.key(t).let { k -> k.isNotEmpty() && k !in ow } }
            val onlyO = to.filter { t -> LiveText.key(t).let { k -> k.isNotEmpty() && k !in aw } }
            val diff = onlyA.size + onlyO.size
            if (diff > 0 && (onlyA + onlyO).all { LiveText.isBrokenWord(it) || LiveText.isGarbageWord(it) } &&
                maxOf(onlyA.size, onlyO.size) * 2 <= maxOf(aw.size, ow.size)) return true
            if (aw.size < ow.size && isSubsequence(aw, ow)) return true
            if (aw.size < ow.size && !LiveText.endsSentence(a) && containsRun(ow, aw)) return true
            return false
        }

        private fun isSubsequence(a: List<String>, b: List<String>): Boolean {
            var i = 0
            for (w in b) if (i < a.size && a[i] == w) i++
            return i == a.size
        }

        private fun containsRun(b: List<String>, a: List<String>): Boolean {
            for (s in 0..b.size - a.size) if (b.subList(s, s + a.size) == a) return true
            return false
        }

        /** Eskide olup yenide olmayan temiz satırlar korunur. */
        fun mergeKeepingCleanLines(old: String, new: String): String {
            val ol = old.split('\n').filter { it.isNotBlank() }
            val nl = new.split('\n').filter { it.isNotBlank() }.toMutableList()
            val used = BooleanArray(nl.size)
            val out = ArrayList<String>()
            for (o in ol) {
                val j = nl.indices.firstOrNull { !used[it] && (LiveText.similarity(nl[it], o) >= 0.6 || isReread(nl[it], o)) }
                if (j != null) { used[j] = true; out += nl[j] }
                else if (!LiveText.isBrokenReading(o)) out += o
            }
            nl.indices.filter { !used[it] }.forEach { out += nl[it] }
            return out.joinToString("\n")
        }
    }
}
