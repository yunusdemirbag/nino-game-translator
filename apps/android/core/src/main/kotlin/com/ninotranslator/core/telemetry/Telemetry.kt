// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.telemetry

import com.ninotranslator.core.http.HttpRequest
import com.ninotranslator.core.http.HttpTransport
import com.ninotranslator.core.json.Json
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Nino ölçüm istemcisi (tarif: NinoCore docs/tarif/olcum.md). Olaylar diskte bir kuyrukta birikir
 * (`<dizin>/queue.json`, en çok 2000), toplu ve gzip'li olarak `POST /v1/events`'e gider.
 * Altyazı metni, IP, ad, yol ya da istisna mesajı hiçbir olaya girmez.
 *
 * Kullanıcı kararıyla kapatma düğmesi yoktur. Ölçümü yalnız sunucu durdurur (`telemetry.enabled = false`);
 * o zaman kuyruk silinir. [Options.enabled] yalnız testler içindir.
 *
 * [flush] engelleyicidir (ağ); IO iş parçacığında çağrılır. [record] hızlıdır, her iş parçacığından çağrılabilir.
 */
class Telemetry(
    val options: Options,
    private val http: HttpTransport,
    val marker: CrashMarker = CrashMarker(options.directory),
    private val clock: () -> Long = System::currentTimeMillis,
    private val newBatchId: () -> String = { UUID.randomUUID().toString() },
    private val isOnline: () -> Boolean = { true },
    private val zoneOffsetMs: (Long) -> Int = { TimeZone.getDefault().getOffset(it) },
) {
    data class Options(
        /** Havuzun kök adresi (`https://…workers.dev`), sonunda `/` olmadan. */
        val endpoint: String,
        val installId: String,
        val context: TelemetryContext,
        val directory: File,
        val enabled: Boolean = true,
        val userAgent: String? = null,
        /** Kuyrukta bu kadar olay birikince beklemeden gönderilir. */
        val flushThreshold: Int = 100,
        /** Diskteki kuyruğun en büyük boyu; dolunca en eski (çökme olmayan) olay atılır. */
        val maxQueued: Int = 2000,
        /** Bir parçada en çok olay (sunucu sınırı 300). */
        val maxBatch: Int = 300,
        val connectTimeoutMs: Int = 15_000,
        val readTimeoutMs: Int = 20_000,
    )

    sealed interface FlushResult {
        data object Disabled : FlushResult
        data object Empty : FlushResult
        data object Waiting : FlushResult
        data object Busy : FlushResult
        data class Sent(val count: Int) : FlushResult
        data object Duplicate : FlushResult
        data class Dropped(val count: Int) : FlushResult
        data object Split : FlushResult
        data class RetryLater(val seconds: Long) : FlushResult
    }

    data class Pending(val id: String, val events: List<TelemetryEvent>)

    private class State {
        val queue = ArrayList<TelemetryEvent>()
        var pending: Pending? = null
        var day = 0L
        var recordedToday = 0
        var droppedToday = 0
        var remote = TelemetryRemoteConfig()
        var nextAttempt = 0L
        var backoff = 0L
        var lastFlush = 0L
        var batchLimit = 0
    }

    private val lock = Any()
    private val flushing = AtomicBoolean(false)
    private val stateFile = File(options.directory, "queue.json")
    private val installId = options.installId.lowercase()
    private val validInstall = TelemetryContext.isInstallId(installId)
    @Volatile private var context = options.context.cleaned()
    private val state = State()
    @Volatile private var scope: CoroutineScope? = null
    private var loop: Job? = null

    init {
        if (options.enabled) load() else { runCatching { stateFile.delete() }; marker.clear() }
    }

    // ---- durum ----

    /** Açık, sunucu kapatmamış ve kurulum kimliği geçerli. */
    val isActive: Boolean get() = synchronized(lock) { activeLocked() }
    private fun activeLocked() = options.enabled && validInstall && state.remote.enabled

    val queued: List<TelemetryEvent> get() = synchronized(lock) { state.pending?.events.orEmpty() + state.queue }
    val queuedCount: Int get() = synchronized(lock) { state.queue.size + (state.pending?.events?.size ?: 0) }
    val remoteConfig: TelemetryRemoteConfig get() = synchronized(lock) { state.remote }
    val isSampled: Boolean get() = TelemetryRemoteConfig.isSampled(installId, remoteConfig.sample)
    val droppedToday: Int get() = synchronized(lock) { state.droppedToday }
    val currentContext: TelemetryContext get() = context

    /** Bağlı TV değişince (`ctx.tv`). */
    fun setTvBrand(brand: TelemetryEvent.TvBrand?) {
        context = context.copy(tv = brand?.wire ?: "")
    }

    /** Sunucunun `telemetry` ayarı. Kapatırsa kuyruk ve çalışma işareti silinir. */
    fun applyRemoteConfig(config: TelemetryRemoteConfig) = synchronized(lock) {
        state.remote = config
        if (!config.enabled) {
            state.queue.clear()
            state.pending = null
            marker.clear()
        }
        save()
    }

    /** `GET /v1/config` → `telemetry` bloğu. Kapalıyken de sorulur (sunucu yeniden açabilsin). Engelleyici. */
    fun refreshRemoteConfig(): Boolean {
        if (!options.enabled || !isOnline()) return false
        val r = runCatching {
            http.send(HttpRequest(options.endpoint + "/v1/config", headers = baseHeaders(), connectTimeoutMs = options.connectTimeoutMs,
                readTimeoutMs = options.readTimeoutMs))
        }.getOrNull() ?: return false
        if (!r.ok) return false
        val block = runCatching { Json.parseObject(r.text)["telemetry"] as? Map<*, *> }.getOrNull() ?: return false
        applyRemoteConfig(TelemetryRemoteConfig.parse(block))
        return true
    }

    // ---- yaşam döngüsü ----

    /** Önceki çalışma çöktüyse `crash` olayı ([CrashMarker.begin] ile alınan işaret ve işletim sisteminin kaydı). */
    fun reportPreviousRun(previous: CrashMarker.Record?, exit: PreviousExit) {
        CrashMarker.crashEvent(previous, exit)?.let(::record)
    }

    /** Uygulama açıldı. */
    fun recordLaunch(ms: Long? = null) = record(TelemetryEvent.launch(ms))

    /** Arka planda dakikada bir işareti tazeler ve zamanı gelince gönderir; 6 saatte bir uzak ayarı sorar. */
    fun start(scope: CoroutineScope, intervalMs: Long = 60_000) {
        this.scope = scope
        loop?.cancel()
        loop = scope.launch(Dispatchers.IO) {
            var configAt = Long.MIN_VALUE / 2
            while (true) {
                if (clock() - configAt >= CONFIG_EVERY_MS) { refreshRemoteConfig(); configAt = clock() }
                if (this@Telemetry.isActive) marker.touch(nowS())
                runCatching { flushIfDue() }
                delay(intervalMs)
            }
        }
    }

    fun stop() { loop?.cancel(); loop = null }

    /** Arka planda tek gönderim (uygulama arka plana geçerken). */
    fun flushSoon() { scope?.launch(Dispatchers.IO) { runCatching { flush() } } }

    // ---- kayıt ----

    /** Olayı kuyruğa ekler. Kapalıysa bir şey yapmaz. Günlük sınır dolduysa yalnız çökme ve teşhis eklenir. */
    fun record(event: TelemetryEvent) {
        var trigger = false
        synchronized(lock) {
            if (!activeLocked()) return
            val t = nowS()
            rollDay(t)
            var e = if (event.time == 0L) event.copy(time = t) else event
            if (e.kind == TelemetryEvent.Kind.SESSION && !TelemetryRemoteConfig.isSampled(installId, state.remote.sample)) {
                e = e.copy(fields = e.fields - "h")
            }
            if (e.kind == TelemetryEvent.Kind.ERROR && coalesce(e)) { save(); return }
            // Çökme ve otomatik teşhis günlük sınırdan muaf (teşhisin kendi sınırları var: DiagBudget).
            if (e.kind != TelemetryEvent.Kind.CRASH && e.kind != TelemetryEvent.Kind.DIAG && state.recordedToday >= state.remote.maxPerDay) {
                state.droppedToday++
                return
            }
            state.recordedToday++
            state.queue.add(e)
            while (state.queue.size > options.maxQueued) {
                val i = state.queue.indexOfFirst { it.kind != TelemetryEvent.Kind.CRASH }
                state.queue.removeAt(if (i >= 0) i else 0)
            }
            save()
            trigger = state.queue.size >= options.flushThreshold
        }
        if (trigger) flushSoon()
    }

    /** Yakalanan hata (kod geçersizse atılır). */
    fun recordError(code: String, http: Int? = null) {
        TelemetryEvent.error(code, http)?.let(::record)
    }

    /** Kuyruktaki aynı kodlu hataya ekler (`n`). Gönderilmekte olan parçaya dokunmaz. */
    private fun coalesce(e: TelemetryEvent): Boolean {
        val code = e.fields["code"]
        val httpCode = (e.fields["http"] as? Number)?.toLong()
        val i = state.queue.indexOfLast {
            it.kind == TelemetryEvent.Kind.ERROR && it.fields["code"] == code && (it.fields["http"] as? Number)?.toLong() == httpCode
        }
        if (i < 0) return false
        val old = state.queue[i]
        val n = ((old.fields["n"] as? Number)?.toLong() ?: 1) + ((e.fields["n"] as? Number)?.toLong() ?: 1)
        state.queue[i] = old.copy(fields = old.fields + ("n" to n.coerceAtMost(MAX_N)))
        return true
    }

    // ---- gönderim ----

    /** Zamanı geldiyse (aralık doldu, kuyruk kabardı ya da bekleyen parça var) gönderir. */
    fun flushIfDue(): FlushResult {
        val due = synchronized(lock) {
            if (!activeLocked()) return FlushResult.Disabled
            state.queue.size >= options.flushThreshold || state.pending != null || nowS() - state.lastFlush >= state.remote.flushSeconds
        }
        return if (due) flush() else FlushResult.Waiting
    }

    /** Bir parça gönderir. `force`: bekleme süresini (429/5xx sonrası) yok sayar. */
    fun flush(force: Boolean = false): FlushResult {
        if (!flushing.compareAndSet(false, true)) return FlushResult.Busy
        try {
            val pending: Pending
            val body: ByteArray
            synchronized(lock) {
                if (!activeLocked()) return FlushResult.Disabled
                val t = nowS()
                if (!force && t < state.nextAttempt) return FlushResult.Waiting
                if (state.pending == null) {
                    if (state.queue.isEmpty()) { state.lastFlush = t; return FlushResult.Empty }
                    val limit = if (state.batchLimit > 0) minOf(state.batchLimit, options.maxBatch) else options.maxBatch
                    val take = state.queue.take(limit)
                    state.queue.subList(0, take.size).clear()
                    state.pending = Pending(newBatchId().lowercase(), take)
                    save()
                }
                pending = state.pending!!
                body = encode(pending).toByteArray(Charsets.UTF_8)
            }
            if (!isOnline()) return FlushResult.Waiting
            val gz = TelemetryGzip.compress(body)
            val headers = baseHeaders() + mapOf("Content-Type" to "application/json", "Content-Encoding" to "gzip")
            val response = try {
                http.send(HttpRequest(options.endpoint + "/v1/events", "POST", headers, gz, options.connectTimeoutMs, options.readTimeoutMs))
            } catch (e: Exception) {
                return synchronized(lock) { retry(null, nowS()) }
            }
            synchronized(lock) {
                // Gönderim sürerken sunucu ölçümü kapattıysa parça zaten silinmiştir.
                if (!activeLocked() || state.pending?.id != pending.id) return FlushResult.Disabled
                val done = nowS()
                return when (response.status) {
                    in 200..299 -> {
                        state.pending = null
                        state.backoff = 0
                        state.nextAttempt = 0
                        if (state.queue.isEmpty()) state.batchLimit = 0
                        state.lastFlush = done
                        val reply = runCatching { Json.parseObject(response.text) }.getOrNull()
                        val config = reply?.get("config") as? Map<*, *>
                        if (config != null) applyRemoteConfig(TelemetryRemoteConfig.parse(config)) else save()
                        if (reply?.get("duplicate") == true) FlushResult.Duplicate else FlushResult.Sent(pending.events.size)
                    }
                    413 -> {
                        state.pending = null
                        if (pending.events.size > 1) {
                            state.queue.addAll(0, pending.events)
                            state.batchLimit = maxOf(1, pending.events.size / 2)
                            save()
                            FlushResult.Split
                        } else {
                            save()
                            FlushResult.Dropped(1)
                        }
                    }
                    // Yalnız "gövde bozuk" siler. 404 (sunucu henüz yayında değil), 429 ve 5xx: saklanır, beklenir.
                    400 -> { state.pending = null; save(); FlushResult.Dropped(pending.events.size) }
                    else -> retry(response.header("retry-after")?.trim()?.toLongOrNull(), done)
                }
            }
        } finally {
            flushing.set(false)
        }
    }

    /** Gövde (testler için de): `{v, batch, install, ctx, events}`. */
    fun encode(pending: Pending): String = Json.write(linkedMapOf(
        "v" to 1L, "batch" to pending.id, "install" to installId, "ctx" to context.toWire(),
        "events" to pending.events.map { it.toWire() },
    ))

    /** Saklanır (aynı kimlikle yeniden denenir); `retry-after` ya da 1 dk, 2 dk, 4 dk… en çok 1 saat. */
    private fun retry(after: Long?, t: Long): FlushResult {
        state.backoff = (state.backoff * 2).coerceIn(MIN_BACKOFF_S, MAX_BACKOFF_S)
        val wait = after?.coerceIn(1, MAX_RETRY_AFTER_S) ?: state.backoff
        state.nextAttempt = t + wait
        save()
        return FlushResult.RetryLater(wait)
    }

    private fun baseHeaders(): Map<String, String> = options.userAgent?.let { mapOf("User-Agent" to it) }.orEmpty()

    // ---- yardımcılar ----

    private fun nowS(): Long = clock() / 1000

    private fun rollDay(t: Long) {
        val day = Math.floorDiv(t * 1000 + zoneOffsetMs(t * 1000), 86_400_000L)
        if (day != state.day) {
            state.day = day
            state.recordedToday = 0
            state.droppedToday = 0
        }
    }

    private fun save() {
        if (!options.enabled) return
        runCatching {
            options.directory.mkdirs()
            val m = linkedMapOf<String, Any?>(
                "queue" to state.queue.map { it.toWire() },
                "pending" to state.pending?.let { linkedMapOf("id" to it.id, "events" to it.events.map { e -> e.toWire() }) },
                "day" to state.day, "recordedToday" to state.recordedToday.toLong(), "droppedToday" to state.droppedToday.toLong(),
                "remote" to state.remote.toWire(), "nextAttempt" to state.nextAttempt, "backoff" to state.backoff,
                "lastFlush" to state.lastFlush, "batchLimit" to state.batchLimit.toLong(),
            )
            val tmp = File(options.directory, "queue.json.tmp")
            tmp.writeText(Json.write(m))
            if (!tmp.renameTo(stateFile)) { stateFile.delete(); tmp.renameTo(stateFile) }
        }
        // Disk dolu ya da yazılamıyor: ölçüm uygulamayı asla bozmamalı.
    }

    private fun load() {
        val m = runCatching { Json.parseObject(stateFile.readText()) }.getOrNull() ?: return
        fun events(v: Any?) = (v as? List<*>)?.mapNotNull { (it as? Map<*, *>)?.let(TelemetryEvent::fromWire) }.orEmpty()
        fun long(k: String) = (m[k] as? Number)?.toLong() ?: 0L
        state.queue += events(m["queue"]).takeLast(options.maxQueued)
        (m["pending"] as? Map<*, *>)?.let { p ->
            val id = p["id"] as? String
            val ev = events(p["events"])
            if (id != null && ev.isNotEmpty()) state.pending = Pending(id, ev)
        }
        state.day = long("day")
        state.recordedToday = long("recordedToday").toInt()
        state.droppedToday = long("droppedToday").toInt()
        state.remote = TelemetryRemoteConfig.parse(m["remote"] as? Map<*, *>)
        state.nextAttempt = long("nextAttempt")
        state.backoff = long("backoff")
        state.lastFlush = long("lastFlush")
        state.batchLimit = long("batchLimit").toInt()
    }

    companion object {
        const val MIN_BACKOFF_S = 60L
        const val MAX_BACKOFF_S = 3600L
        const val MAX_RETRY_AFTER_S = 86_400L
        const val MAX_N = 10_000L
        private const val CONFIG_EVERY_MS = 6 * 3600_000L
    }
}
