// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import com.ninotranslator.core.reading.live.FrameTrace
import com.ninotranslator.core.reading.live.LiveBox
import com.ninotranslator.core.reading.live.LiveClock
import com.ninotranslator.core.reading.live.LiveDecision
import com.ninotranslator.core.reading.live.LiveLine
import com.ninotranslator.core.reading.live.LiveNoiseFilter
import com.ninotranslator.core.reading.live.LiveReading
import com.ninotranslator.core.reading.live.LiveRegion
import com.ninotranslator.core.reading.live.LiveShow
import com.ninotranslator.core.reading.live.LiveShowKind
import com.ninotranslator.core.reading.live.LiveStabilizer
import com.ninotranslator.core.reading.live.LiveText
import com.ninotranslator.core.reading.live.LiveTranslation
import com.ninotranslator.core.reading.live.LiveTranslationQueue
import com.ninotranslator.core.reading.live.LumaPlane
import com.ninotranslator.core.reading.live.ReadThrottle
import com.ninotranslator.core.reading.live.SpeakerPrefix
import com.ninotranslator.core.reading.live.SubtitleBand
import com.ninotranslator.core.reading.live.TaskStripLine
import com.ninotranslator.core.reading.live.UnchangedRegionGate
import com.ninotranslator.core.translation.LineResult
import com.ninotranslator.core.translation.TargetLanguage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/** Yazı tanıma: gri kırpmadan satırlar (kutular kırpmaya göre, 0–1). Hata atabilir. */
fun interface TextReader {
    suspend fun read(image: LumaPlane): List<LiveLine>
}

/** Okuma döngüsünün o anki ayarları. Hizmet ayar değişince yenisini koyar. */
data class LoopConfig(
    /** Kullanıcının altyazı bölgesi. */
    val region: LiveRegion = LiveRegion.BOTTOM,
    /** Bu oyunda öğrenilmiş altyazı şeridi (yoksa null). */
    val band: SubtitleBand? = null,
    /** Öğrenilmiş kutuların boyları (görev şeridi çizgisi için). */
    val bandHeights: List<Double> = emptyList(),
    /** Havuz öncelikli oyun (GTA 6): görev şeridi çizgisi en çok 0.935. */
    val poolFirstGame: Boolean = false,
    val fastDetection: Boolean = false,
    val showSpeakerNames: Boolean = true,
    val target: TargetLanguage = TargetLanguage.TR,
    /** Harita ekranı açıkken (GTA 6) altyazı okunmaz. */
    val subtitlesSuppressed: Boolean = false,
    /** Okumadan önce siyaha boyanan kare kutuları (oyun içi telefon; okuma.md 9). */
    val blackout: List<LiveBox> = emptyList(),
    /** true dönen satır altyazı sayılmaz (GTA 6 kuralları); kutu kareye göre. */
    val dropLine: ((String, LiveBox?) -> Boolean)? = null,
) {
    /** Okunan bölge: öğrenilen şerit yalnız daraltır (okuma.md 3). */
    val readRegion: LiveRegion get() = (band?.narrow(region) ?: region).clamped()
    val taskLine: Double? get() = TaskStripLine.compute(band, bandHeights, poolFirstGame)
}

/** Gösterilecek satır (TV'ye ve telefona). [box] karenin oranında İngilizce altyazının yeri. */
data class ShownLine(
    val id: Int,
    val source: String,
    /** Gösterilecek çeviri (konuşan adı ayarı ve sağdan sola işaretleri uygulanmış). */
    val text: String,
    val durationMs: Long,
    val replacesPrevious: Boolean,
    val kind: LiveShowKind,
    val fromPack: Boolean,
    val origin: LineResult.Origin?,
    /** Paket satırında paket kimliği, motor satırında motor adı. */
    val engine: String?,
    val box: LiveBox?,
    /** Kareden gösterime geçen süre (ms); bilinmiyorsa null. */
    val latencyMs: Long?,
    /** Çeviri süresi (ms); paket ve geri getirilen satırda null. */
    val translateMs: Long?,
)

/**
 * Kareden gösterime okuma döngüsü (servis.md 3.1-3.3, okuma.md 1-6): saniyede en çok 5 okuma, değişmeyen bölge
 * kapısı, süzgeç → sabitleyici → bekletme sırası → çeviri → [Listener].
 *
 * [scope] tek iş parçacıklı olmalıdır (süzgeç, sabitleyici ve sıra tek iş parçacığında çalışır). [offerFrame]
 * herhangi bir iş parçacığından çağrılabilir; kareyi çağrının içinde kopyalar. [translate] ağır işi kendi
 * iş parçacığında yapmalıdır.
 */
class ReadingLoop(
    private val scope: CoroutineScope,
    private val clock: LiveClock,
    private val reader: TextReader,
    private val translate: suspend (String) -> LineResult?,
    private val listener: Listener,
    private val log: (String) -> Unit = {},
    private val ocrTimeoutMs: Long = OCR_TIMEOUT_MS,
    /** Satır pakette var mı: paketteki satır bekletilmeden çevrilir (okuma.md 6). */
    private val inPack: (String) -> Boolean = { false },
) {
    interface Listener {
        /** Okunan ham satırlar ve süzülmüş okuma (oyun ipuçları, kanca). */
        fun onReading(raw: List<LiveLine>, reading: LiveReading, region: LiveRegion) {}
        fun onShow(line: ShownLine)
        /** Ekrandaki satır kalktı; [id] son gösterilenin numarası. */
        fun onClear(id: Int)
        fun onTranslationFailed(source: String) {}
    }

    @Volatile var config: LoopConfig = LoopConfig()
        set(value) {
            val regionChanged = value.readRegion != field.readRegion || value.fastDetection != field.fastDetection
            field = value
            if (regionChanged) scope.launch { resetGate() }
        }

    private val throttle = ReadThrottle(MIN_READ_INTERVAL_MS)
    private val filter = LiveNoiseFilter(log)
    private val stabilizer = LiveStabilizer()
    private var gate = UnchangedRegionGate(false)
    private var gateFast = false
    private var lastLines: List<LiveLine> = emptyList()
    private var nextId = 0
    private var lastShownId: Int? = null
    @Volatile private var stopped = false

    private class Pending(val box: LiveBox?, val frameAt: Long)
    private class Done(val result: LineResult, val ms: Long)
    private val pending = Lru<String, Pending>(32)
    private val results = Lru<String, Done>(32)

    /** Okumalar (tanı/test). */
    @Volatile var readings = 0; private set
    @Volatile var ocrRuns = 0; private set

    private val queue = LiveTranslationQueue(
        scope = scope,
        clock = clock,
        translate = { text -> translateOne(text) },
        inPack = { runCatching { inPack(it) }.getOrDefault(false) },
        onShow = ::onQueueShow,
        onFailed = ::onQueueFailed,
    )

    /** Kare geldi. Okuma sırası değilse false (kare atlandı). */
    fun offerFrame(frame: VideoFrame): Boolean {
        if (stopped) return false
        val cfg = config
        val region = cfg.readRegion
        val rect = FrameTrace.crop(region, frame.width, frame.height) ?: return false
        if (frame.stride < frame.width || frame.luma.capacity() < frame.stride * (frame.height - 1) + frame.width) return false
        val now = clock.nowMs()
        synchronized(throttle) { if (!throttle.tryStart(now)) return false }
        val crop = try {
            copyCrop(frame, rect.left, rect.top, rect.width, rect.height).also { paint(it, region, cfg.blackout) }
        } catch (e: Exception) {
            synchronized(throttle) { throttle.finish() }
            return false
        }
        val at = frame.timestampMs
        scope.launch {
            try { process(crop, region, cfg, at) } finally { synchronized(throttle) { throttle.finish() } }
        }
        return true
    }

    /** Arka planda gelen daha iyi havuz çevirisi: satır hâlâ ekrandaysa yerinde değişir. */
    fun improve(result: LineResult) {
        scope.launch {
            if (stopped) return@launch
            results.put(LiveText.key(result.source), Done(result, 0))
            queue.improve(result.source, result.text)
        }
    }

    /** Düzenli çağrılır (bekletme süresi dolanlar sıraya girer). */
    fun tick() { scope.launch { if (!stopped) queue.tick() } }

    fun stop() { stopped = true }

    // ---- döngü içi ----

    private fun resetGate() {
        val fast = config.fastDetection
        gate = UnchangedRegionGate(fast)
        gateFast = fast
    }

    private suspend fun process(crop: LumaPlane, region: LiveRegion, cfg: LoopConfig, frameAt: Long) {
        if (stopped) return
        if (gateFast != cfg.fastDetection) resetGate()
        val coarse = FrameTrace.coarse(crop)
        val lines = if (gate.shouldReuse(coarse)) lastLines else {
            ocrRuns++
            val read = try {
                withTimeoutOrNull(ocrTimeoutMs) { reader.read(crop) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                log("yazı tanıma hata verdi: ${e.message}")
                null
            }
            // Okunamayan ya da süresi dolan kare atlanır; bir sonraki okumada yeniden denenir.
            if (read == null) { gate.reset(); return }
            read.also { lastLines = it }
        }
        if (stopped) return
        readings++
        val now = clock.nowMs()
        val grid = FrameTrace.grid(crop)
        val drop = cfg.dropLine
        val kept = if (drop == null) lines else lines.filterNot { l -> runCatching { drop(l.text, l.box?.let(region::toFrame)) }.getOrDefault(false) }
        // Süzgeç her okumada çalışır (eskiyen satır saati harita açıkken de ilerler); bastırılınca sonuç atılır.
        val filtered = filter.filter(kept, region, now, cfg.taskLine)
        val reading = if (cfg.subtitlesSuppressed) LiveReading.EMPTY else filtered
        listener.onReading(lines, reading, region)
        queue.onReading(reading.text)
        when (val d = stabilizer.onReading(reading, now, grid)) {
            is LiveDecision.Translate -> {
                pending.put(LiveText.key(d.text), Pending(reading.box?.let(region::toFrame), frameAt))
                queue.submit(d.text, d.replacesPrevious)
            }
            is LiveDecision.Restore -> {
                pending.put(LiveText.key(d.text), Pending(reading.box?.let(region::toFrame), frameAt))
                if (!queue.restore(d.text)) queue.submit(d.text, false)
            }
            LiveDecision.Clear -> lastShownId?.let { id -> lastShownId = null; listener.onClear(id) }
            LiveDecision.Nothing -> Unit
        }
    }

    private suspend fun translateOne(text: String): LiveTranslation? {
        val started = clock.nowMs()
        val r = try { translate(text) } catch (e: CancellationException) { throw e } catch (e: Exception) { null } ?: return null
        results.put(LiveText.key(text), Done(r, clock.nowMs() - started))
        return LiveTranslation(r.text, fromPack = r.origin == LineResult.Origin.PACK)
    }

    private fun onQueueShow(show: LiveShow) {
        if (stopped) return
        val cfg = config
        var text = show.translation
        if (!cfg.showSpeakerNames) text = SpeakerPrefix.stripNames(show.source, text)
        text = cfg.target.forDisplay(text)
        val key = LiveText.key(show.source)
        val done = results.get(key)
        val p = pending.get(key)
        val id = ++nextId
        lastShownId = id
        val fresh = show.kind == LiveShowKind.NEW
        listener.onShow(ShownLine(
            id = id,
            source = show.source,
            text = text,
            durationMs = show.durationMs,
            replacesPrevious = show.replacesPrevious,
            kind = show.kind,
            fromPack = show.fromPack,
            origin = done?.result?.origin,
            engine = done?.result?.engine,
            box = p?.box,
            latencyMs = if (fresh && p != null) (clock.nowMs() - p.frameAt).coerceAtLeast(0) else null,
            translateMs = if (fresh && !show.fromPack) done?.ms else null,
        ))
    }

    private fun onQueueFailed(text: String) {
        if (stopped) return
        stabilizer.onTranslationFailed(text, clock.nowMs())
        listener.onTranslationFailed(text)
    }

    /** Küçük LRU (yalnız döngü iş parçacığında). */
    private class Lru<K, V>(private val max: Int) {
        private val map = LinkedHashMap<K, V>()
        fun put(k: K, v: V) { map.remove(k); map[k] = v; while (map.size > max) map.remove(map.keys.first()) }
        fun get(k: K): V? = map[k]
    }

    companion object {
        const val MIN_READ_INTERVAL_MS = 200L
        const val OCR_TIMEOUT_MS = 5_000L

        /** Kare kutularının kırpmaya düşen kısmı siyaha boyanır. */
        fun paint(crop: LumaPlane, region: LiveRegion, boxes: List<LiveBox>) {
            for (b in boxes) {
                val x0 = (((b.left - region.left) / region.width) * crop.width).toInt().coerceIn(0, crop.width)
                val x1 = (((b.right - region.left) / region.width) * crop.width).toInt().coerceIn(0, crop.width)
                val y0 = (((b.top - region.top) / region.height) * crop.height).toInt().coerceIn(0, crop.height)
                val y1 = (((b.bottom - region.top) / region.height) * crop.height).toInt().coerceIn(0, crop.height)
                for (y in y0 until y1) java.util.Arrays.fill(crop.data, y * crop.rowStride + x0, y * crop.rowStride + x1, 0)
            }
        }

        /** Bölgeyi satır satır kopyalar (satır aralığına uyar). */
        fun copyCrop(frame: VideoFrame, left: Int, top: Int, width: Int, height: Int): LumaPlane {
            val out = ByteArray(width * height)
            val src = frame.luma.duplicate()
            for (y in 0 until height) {
                src.position((top + y) * frame.stride + left)
                src.get(out, y * width, width)
            }
            return LumaPlane(out, width, height)
        }
    }
}
