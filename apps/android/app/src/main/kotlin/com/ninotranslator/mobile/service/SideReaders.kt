// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import android.util.Log
import com.ninotranslator.core.link.ShowPayload
import com.ninotranslator.core.reading.live.AreaLines
import com.ninotranslator.core.reading.live.ExtraAreaTracker
import com.ninotranslator.core.reading.live.FrameTrace
import com.ninotranslator.core.reading.live.LiveBox
import com.ninotranslator.core.reading.live.LiveClock
import com.ninotranslator.core.reading.live.LiveLine
import com.ninotranslator.core.reading.live.LiveRegion
import com.ninotranslator.core.reading.live.LumaPlane
import com.ninotranslator.core.reading.live.ScreenPlan
import com.ninotranslator.core.reading.live.ScreenRefresh
import com.ninotranslator.core.translation.LineResult
import com.ninotranslator.mobile.data.ExtraArea
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/** Yan okuyucuların ortak yazı tanıması: tek okuyucu, sıralı kullanım (altyazıyı bekletmez). */
class SharedReader(private val reader: TextReader, private val timeoutMs: Long = 5_000) {
    private val lock = Mutex()

    /** Okunan satırlar; hata ya da süre dolarsa null. */
    suspend fun read(p: LumaPlane): List<LiveLine>? = lock.withLock {
        try { withTimeoutOrNull(timeoutMs) { reader.read(p) } } catch (e: CancellationException) { throw e } catch (e: Exception) { null }
    }
}

/** Karenin bir bölgesini kopyalar (kutu kareye göre); çok küçükse null. Çağrının içinde kullanılmalı. */
fun VideoFrame.copyRegion(r: LiveRegion): LumaPlane? {
    val rect = FrameTrace.crop(r.clamped(), width, height) ?: return null
    if (stride < width || luma.capacity() < stride * (height - 1) + width) return null
    return runCatching { ReadingLoop.copyCrop(this, rect.left, rect.top, rect.width, rect.height) }.getOrNull()
}

/**
 * TV'deki `screen` kanalının tek sahibi: elle "Ekranı çevir" sonuçları ile oyun içi telefon/harita katmanı aynı
 * kanalı kullanır. Elle sonuç ekrandayken katman gönderilmez; sonuç kalkınca katman geri gelir. Katman 120 sn
 * sürelidir; değişmese de 60 sn'de bir yenilenir.
 */
class ScreenChannel(
    private val scope: CoroutineScope,
    private val clock: LiveClock = LiveClock { System.nanoTime() / 1_000_000 },
    private val tv: () -> TvOutput,
) {
    @Volatile var manualActive = false; private set
    private val refresh = ScreenRefresh()
    private var refresher: Job? = null

    @Synchronized fun setOverlay(items: List<Map<String, Any?>>) {
        run(refresh.set(items, clock.nowMs()))
    }

    @Synchronized fun manual(items: List<Map<String, Any?>>, durationMs: Long) {
        manualActive = true
        refresh.pause()
        scope.launch { runCatching { tv().screen(items, durationMs.toInt(), overlay = false) } }
    }

    @Synchronized fun manualClear() {
        if (!manualActive) return
        manualActive = false
        scope.launch { runCatching { tv().screenClear() } }
        run(refresh.resume(clock.nowMs()))
    }

    /** Değişmeyen katman 60 sn'de bir yeniden gider; [TICK_MS]'de bir bakılır. */
    @Synchronized fun tick() { run(refresh.tick(clock.nowMs())) }

    private fun run(a: ScreenRefresh.Action) {
        when (a) {
            ScreenRefresh.Action.None -> Unit
            ScreenRefresh.Action.Clear -> { scope.launch { runCatching { tv().screenClear() } }; refresher?.cancel(); refresher = null }
            is ScreenRefresh.Action.Send -> {
                scope.launch { runCatching { tv().screen(a.items, a.durationMs, overlay = true) } }
                if (refresher == null) refresher = scope.launch { while (true) { delay(TICK_MS); tick() } }
            }
        }
    }

    fun close() { refresher?.cancel() }

    companion object {
        const val OVERLAY_MS = ScreenRefresh.DURATION_MS
        const val TICK_MS = 1_000L
    }
}

/**
 * Ek alanlar (okuma.md 11): en çok 3, altyazıdan ayrı ve 1 sn'de bir okunur; aynı paketlerle ve motorla çevrilir ama
 * ortak havuza önerilmez. Sonuç TV'de `region` kutusu ve canlı durumda [LiveSnapshot.extraTranslations].
 */
class ExtraAreaReader(
    private val scope: CoroutineScope,
    private val clock: LiveClock,
    private val reader: SharedReader,
    private val areas: () -> List<ExtraArea>,
    private val translate: suspend (String) -> LineResult?,
    private val tv: () -> TvOutput,
) {
    private val busy = AtomicBoolean(false)
    @Volatile private var lastAt = Long.MIN_VALUE / 2
    private val trackers = HashMap<String, ExtraAreaTracker>()
    private val shown = LinkedHashMap<String, PlacedText>()
    @Volatile private var stopped = false

    fun offer(frame: VideoFrame) {
        if (stopped) return
        val now = clock.nowMs()
        if (now - lastAt < AreaLines.EXTRA_READ_INTERVAL_MS) return
        val list = areas().filter { it.enabled }.take(ExtraArea.MAX)
        if (list.isEmpty()) { if (shown.isNotEmpty()) scope.launch { clearAll() }; return }
        if (!busy.compareAndSet(false, true)) return
        lastAt = now
        val crops = list.mapNotNull { a ->
            val r = LiveRegion(a.region.top, a.region.bottom, a.region.left, a.region.right)
            frame.copyRegion(r)?.let { Triple(a.id, r.clamped(), it) }
        }
        scope.launch {
            try { crops.forEach { (id, r, p) -> step(id, r, p) }; dropRemoved(list.map { it.id }.toSet()) } finally { busy.set(false) }
        }
    }

    private suspend fun step(id: String, region: LiveRegion, crop: LumaPlane) {
        val t = synchronized(trackers) { trackers.getOrPut(id) { ExtraAreaTracker() } }
        val decision = if (t.shouldRead(FrameTrace.coarse(crop))) t.onRead(reader.read(crop), region) else t.unchangedRound()
        when (decision) {
            ExtraAreaTracker.Decision.Nothing -> Unit
            ExtraAreaTracker.Decision.Clear -> hide(id)
            is ExtraAreaTracker.Decision.Translate -> {
                val out = decision.parts.map { part -> translate(part)?.text }
                if (out.any { it == null }) { t.forget(); return }
                val tr = out.joinToString("\n")
                val src = decision.parts.joinToString("\n")
                if (!AreaLines.worthShowing(src, tr)) { hide(id); return }
                val b = decision.box
                synchronized(shown) { shown[id] = PlacedText(tr, b?.left?.toFloat(), b?.top?.toFloat(), b?.right?.toFloat(), b?.bottom?.toFloat()) }
                publish()
                runCatching { tv().region(id, tr, b?.let(ScreenPlan::box) ?: ScreenPlan.box(region.let { LiveBox(it.left, it.top, it.right, it.bottom) }), decision.lineHeight) }
            }
        }
    }

    private suspend fun hide(id: String) {
        val had = synchronized(shown) { shown.remove(id) != null }
        if (had) { publish(); runCatching { tv().region(id, "", null, null) } }
    }

    private suspend fun dropRemoved(ids: Set<String>) {
        val gone = synchronized(shown) { shown.keys.filter { it !in ids } }
        gone.forEach { hide(it) }
        synchronized(trackers) { trackers.keys.retainAll(ids) }
    }

    private suspend fun clearAll() {
        val had = synchronized(shown) { val n = shown.isNotEmpty(); shown.clear(); n }
        synchronized(trackers) { trackers.clear() }
        if (had) { publish(); runCatching { tv().regionClearAll() } }
    }

    private fun publish() {
        val list = synchronized(shown) { shown.values.toList() }
        LiveStatus.update { it.copy(extraTranslations = list) }
    }

    fun stop() { stopped = true }
}

/**
 * "Ekranı çevir" (okuma.md 12, servis.md 3.7): sıradaki karenin tamamı ayrı okuyucuyla bir kez okunur, gruplar
 * çevrilir, sonuçlar telefonda ve TV'de yazının yerinde görünür ve kendi süresi kadar kalır. Çevrilirken ya da sonuçlar
 * ekrandayken yeniden basmak her şeyi kaldırır; eski işin geç gelen sonuçları yok sayılır.
 */
class ScreenTranslator(
    private val scope: CoroutineScope,
    private val reader: SharedReader,
    private val channel: ScreenChannel,
    private val texts: ServiceStrings,
    private val tv: () -> TvOutput,
    private val streaming: () -> Boolean,
    private val resendStyle: () -> Unit,
    /** Yapay zekâ çevirmeni (havuz öncelikli oyunda değil) varsa bütün parçalar tek istekte; yoksa null. */
    private val batch: suspend (List<String>) -> List<String>?,
    private val translate: suspend (String) -> LineResult?,
) {
    enum class Phase { IDLE, WAITING, TRANSLATING, SHOWING }

    private val generation = AtomicInteger()
    @Volatile var phase = Phase.IDLE; private set
    private var timer: Job? = null
    private var noticeId = NOTICE_ID_BASE

    /** Sonuçlar ekranda ya da çevriliyor: telefon ve harita okunmaz. */
    val active: Boolean get() = phase != Phase.IDLE

    fun toggle() {
        if (phase != Phase.IDLE) { clear(); return }
        if (!streaming()) { notice(ServiceTexts.SCREEN_NO_PICTURE, null, 4_000); return }
        generation.incrementAndGet()
        phase = Phase.WAITING
        LiveStatus.update { it.copy(screenTranslating = true, screenShowing = false, screenTranslations = emptyList(), screenNotice = null) }
        resendStyle()
        notice(ServiceTexts.SCREEN_TRANSLATING, null, 2_500)
    }

    fun clear() {
        generation.incrementAndGet()
        timer?.cancel(); timer = null
        val was = phase
        phase = Phase.IDLE
        LiveStatus.update { it.copy(screenTranslating = false, screenShowing = false, screenTranslations = emptyList()) }
        if (was == Phase.SHOWING || was == Phase.TRANSLATING) channel.manualClear()
    }

    fun offer(frame: VideoFrame) {
        if (phase != Phase.WAITING) return
        val gen = generation.get()
        val full = frame.copyRegion(LiveRegion.FULL) ?: return
        phase = Phase.TRANSLATING
        scope.launch { run(gen, full) }
    }

    private suspend fun run(gen: Int, full: LumaPlane) {
        try {
            val lines = reader.read(full)
            if (gen != generation.get()) return
            if (lines == null) { finishEmpty(gen); return }
            val groups = ScreenPlan.groups(lines)
            if (groups.isEmpty()) { finishEmpty(gen); return }
            val duration = ScreenPlan.durationMs(groups)
            val placed = ArrayList<Pair<ScreenPlan.Group, String>>()
            fun push() {
                if (gen != generation.get()) return
                val items = placed.map { (g, t) -> ScreenPlan.item(g, t) }
                LiveStatus.update { it.copy(screenTranslations = placed.map { (g, t) -> PlacedText(t, g.box.left.toFloat(), g.box.top.toFloat(), g.box.right.toFloat(), g.box.bottom.toFloat()) }) }
                if (items.isNotEmpty()) channel.manual(items, duration)
            }
            val all = runCatching { batch(groups.map { it.text }) }.getOrNull()
            if (all != null && all.size == groups.size) {
                groups.zip(all).filter { (g, t) -> t.isNotBlank() && AreaLines.worthShowing(g.text, t) }.forEach { placed += it }
                push()
            } else for (g in groups) {
                if (gen != generation.get()) return
                val t = translate(g.text)?.text ?: continue
                if (!AreaLines.worthShowing(g.text, t)) continue
                placed += g to t
                push()
            }
            if (gen != generation.get()) return
            if (placed.isEmpty()) { finishEmpty(gen); return }
            phase = Phase.SHOWING
            LiveStatus.update { it.copy(screenTranslating = false, screenShowing = true) }
            timer = scope.launch { delay(duration); if (gen == generation.get()) clear() }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w("Nino", "ekran çevrilemedi", e)
            if (gen != generation.get()) return
            phase = Phase.IDLE
            LiveStatus.update { it.copy(screenTranslating = false, screenShowing = false) }
            notice(ServiceTexts.SCREEN_FAILED, e.message ?: e.javaClass.simpleName, 6_000)
        }
    }

    private fun finishEmpty(gen: Int) {
        if (gen != generation.get()) return
        phase = Phase.IDLE
        LiveStatus.update { it.copy(screenTranslating = false, screenShowing = false) }
        notice(ServiceTexts.SCREEN_NO_TEXT, null, 2_500)
    }

    /** TV'de kısa not (altyazı numaralarından ayrı aralıkta) ve telefonda [LiveSnapshot.screenNotice]. */
    private fun notice(key: String, arg: String?, ms: Int) {
        val text = texts.get(TextRef(key, arg))
        val id = synchronized(this) { ++noticeId }
        LiveStatus.update { it.copy(screenNotice = text) }
        scope.launch {
            runCatching { tv().show(ShowPayload(id = id, text = text, durationMs = ms)) }
            delay(ms.toLong())
            LiveStatus.update { if (it.screenNotice == text) it.copy(screenNotice = null) else it }
        }
    }

    companion object {
        /** Okuma döngüsünün numaralarıyla çakışmasın. */
        const val NOTICE_ID_BASE = 1_000_000_000
    }
}
