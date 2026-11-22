// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.link

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.UUID

private val REPLAY = Any()

/** Bağlı TV'nin türü. */
enum class DisplayKind {
    /** Android TV: TV dinler, telefon bağlanır (47800). */
    ANDROID_TV,
    /** LG/Samsung web TV: TV telefonun 47800'üne bağlanır. */
    WEB_TV,
    /** Eski TV uygulaması: 8787 /events (SSE). */
    LEGACY,
}

/** Şu an altyazı alan bir TV. [key] listede ayırt etmek içindir. */
data class ConnectedDisplay(
    val key: String,
    val name: String,
    val address: String,
    val kind: DisplayKind,
    val model: String? = null,
    val appVersion: String? = null,
)

/**
 * Bütün TV çıkışları tek yerden: Android TV'lere istemci ([connectTo]), web TV'ler için 47800 sunucusu
 * ([SenderIngress]) ve eski TV uygulamaları için 8787 ([LegacyEventServer]). Hepsi aynı anda açık olabilir.
 * Bir TV koparsa ya da yavaşsa ötekiler etkilenmez. Gönderimler beklemez; her TV'nin kendi sırası vardır.
 */
class DisplayHub(val config: Config) {
    data class Config(
        /** Telefonun görünen adı (hello.device, info.name). */
        val deviceName: String,
        /** İstemci sürümü, ör. "nino-android/1.0.0" (hello.client). */
        val clientVersion: String,
        /** Telefonun kalıcı kimliği (info.id). */
        val deviceId: String = UUID.randomUUID().toString(),
        /** Uygulama sürümü (info.appVersion). */
        val appVersion: String? = null,
        val ingressEnabled: Boolean = true,
        val ingressPort: Int = NinoLink.DEFAULT_PORT,
        val legacyEnabled: Boolean = true,
        val legacyPort: Int = LegacyEventServer.DEFAULT_PORT,
        /** `durationMs: 0` eski TV'de bu süreye çevrilir. */
        val legacyUntilClearedMs: Int = LegacyEventServer.UNTIL_CLEARED_MS,
        val pingIntervalMs: Long = NinoLink.PING_INTERVAL_MS,
        val pongTimeoutMs: Long = NinoLink.PONG_TIMEOUT_MS,
        val handshakeTimeoutMs: Long = NinoLink.HANDSHAKE_TIMEOUT_MS,
        val legacyPingMs: Long = LegacyEventServer.PING_MS,
        val legacyStartedWindowMs: Long = LegacyEventServer.STARTED_WINDOW_MS,
    )

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Any()

    private val _displays = MutableStateFlow<List<ConnectedDisplay>>(emptyList())
    val displays: StateFlow<List<ConnectedDisplay>> = _displays

    private val _events = MutableSharedFlow<DisplayEvent>(extraBufferCapacity = 64, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    /**
     * Bağlanma, kopma (nedeniyle) ve Android TV'ye bağlanamama olayları, oluş sırasıyla. Kısa bir yeniden bağlanma
     * da kaçmaz ([displays] durum akışı ara durumu atlayabilir). Geçmişi tutmaz: o anki liste için [displays].
     */
    val events: SharedFlow<DisplayEvent> = _events

    private val _portProblems = MutableStateFlow<Set<Int>>(emptySet())
    /** Açılamayan portlar (başka uygulama tutuyor). Arayüz `error_port` gösterir; çeviri yine sürer. */
    val portProblems: StateFlow<Set<Int>> = _portProblems

    /**
     * false iken altyazı olayları (show, clear, screen, region) TV'lere gitmez; style/started/stopped gider.
     * Eski sunucudaki OBS izleyicileri yine alır ("altyazı telefonda" hedefi).
     */
    @Volatile var tvSubtitlesEnabled: Boolean = true
        set(value) {
            if (field == value) return
            field = value
            // Kapatınca TV'ler temizlenir; açınca son style ve altyazı yeniden gider.
            if (!value) {
                val c = NinoMessage.Clear(null).encode()
                forEachNewOutput { it(c) }
                legacy?.clearTvs()
            } else {
                for (m in replayMessages(withStarted = false)) forEachNewOutput { it(m) }
            }
        }

    // Yeni bağlanana yeniden yollanacak son durum.
    private var lastStyle: String? = null
    private var lastStyleFields: Map<String, Any?>? = null
    private var started = false
    private var startedAt = 0L
    private var shown: String? = null
    private var shownId: Int? = null

    @Volatile private var ingress: SenderIngress? = null
    @Volatile private var legacy: LegacyEventServer? = null
    private val links = LinkedHashMap<String, TvLink>()

    /** Gerçek dinlenen portlar (test için; port 0 verilirse işletim sistemi seçer). */
    val ingressLocalPort: Int get() = ingress?.localPort ?: -1
    val legacyLocalPort: Int get() = legacy?.localPort ?: -1

    /** 47800 ve 8787 sunucularını açar. Açılamayan port [portProblems]'e yazılır. */
    fun start() {
        synchronized(lock) {
            val problems = HashSet<Int>()
            if (config.ingressEnabled && ingress == null) {
                val s = SenderIngress(
                    port = config.ingressPort,
                    info = { infoJson() },
                    hello = { v -> NinoMessage.Hello(v, config.deviceName, config.clientVersion).encode() },
                    replay = { replayMessages() },
                    onChange = { publish() },
                    onDrop = { key, reason -> publish(mapOf(key to reason)) },
                    pingIntervalMs = config.pingIntervalMs,
                    silenceTimeoutMs = config.pongTimeoutMs,
                    handshakeTimeoutMs = config.handshakeTimeoutMs,
                )
                try { s.start(); ingress = s } catch (e: java.io.IOException) { problems += config.ingressPort }
            }
            if (config.legacyEnabled && legacy == null) {
                val s = LegacyEventServer(
                    port = config.legacyPort,
                    untilClearedMs = config.legacyUntilClearedMs,
                    pingMs = config.legacyPingMs,
                    startedWindowMs = config.legacyStartedWindowMs,
                    replay = { legacyReplay() },
                    tvSubtitles = { tvSubtitlesEnabled },
                    onChange = { publish() },
                    onDrop = { key, reason -> publish(mapOf(key to reason)) },
                )
                try { s.start(); legacy = s } catch (e: java.io.IOException) { problems += config.legacyPort }
            }
            _portProblems.value = problems
        }
        publish()
    }

    /** Her şeyi kapatır: sunucular, Android TV bağlantıları. Yeniden [start] edilebilir. */
    fun close() {
        val (i, l, ls) = synchronized(lock) {
            val r = Triple(ingress, legacy, links.values.toList())
            ingress = null; legacy = null; links.clear()
            r
        }
        // Listeden önce çıkar: bu kopmalar uygulamanın durdurmasıdır.
        publish(fallback = DropReason.STOPPED)
        i?.close(); l?.close()
        ls.forEach { it.close() }
        scope.coroutineContext.cancelChildren()
        _portProblems.value = emptySet()
        publish()
    }

    /** Android TV'ye bağlanır ve bağlantıyı canlı tutar (kopunca 1, 2, 4, 8 sn arayla yeniden). */
    fun connectTo(host: String, port: Int = NinoLink.DEFAULT_PORT) {
        val key = host.trim()
        if (key.isEmpty()) return
        val old = synchronized(lock) {
            val existing = links[key]
            if (existing != null && existing.port == port) return
            links.remove(key)
        }
        if (old != null) { publish(mapOf(old.displayKey to DropReason.REPLACED)); old.close() }
        val link = TvLink(key, port)
        synchronized(lock) { links[key] = link }
        link.start()
    }

    fun disconnectFrom(host: String) {
        val link = synchronized(lock) { links.remove(host.trim()) } ?: return
        publish(mapOf(link.displayKey to DropReason.STOPPED))
        link.close()
    }

    suspend fun show(payload: ShowPayload) {
        val p = LinkFormat.fitShow(payload.copy(extras = LinkFormat.normalizeMap(payload.extras)))
        val json = NinoMessage.Show(p).encode()
        synchronized(lock) {
            if (p.durationMs == 0) { shown = json; shownId = p.id } else { shown = null; shownId = null }
        }
        dispatch(json, subtitle = true)
        legacy?.show(p)
    }

    suspend fun clear(id: Int?) {
        synchronized(lock) { if (id == null || id == shownId) { shown = null; shownId = null } }
        dispatch(NinoMessage.Clear(id).encode(), subtitle = true)
        legacy?.clear(id)
    }

    /** Görünüm; bağlanan her TV'ye bağlanınca ve her değişince gider. */
    fun setStyle(style: Map<String, Any?>) {
        val fields = LinkFormat.normalizeMap(style)
        val json = LinkFormat.extension("style", fields)
        synchronized(lock) { lastStyle = json; lastStyleFields = fields }
        dispatch(json, subtitle = false)
        legacy?.event("style", fields)
    }

    suspend fun started() {
        synchronized(lock) { started = true; startedAt = System.currentTimeMillis() }
        dispatch(LinkFormat.extension("started", emptyMap()), subtitle = false)
        legacy?.event("started", emptyMap())
    }

    suspend fun stopped() {
        synchronized(lock) { started = false; startedAt = 0; shown = null; shownId = null }
        dispatch(LinkFormat.extension("stopped", emptyMap()), subtitle = false)
        legacy?.event("stopped", emptyMap())
    }

    /** "Ekranı çevir" ve yan çeviriler. En çok 30 öğe; 16 KB'a sığmayan sondaki öğeler atılır. */
    suspend fun screen(items: List<Map<String, Any?>>, durationMs: Int, overlay: Boolean) {
        val fields = LinkFormat.fitScreen(items.map { LinkFormat.normalizeMap(it) }, maxOf(0, durationMs), overlay)
        dispatch(LinkFormat.extension("screen", fields), subtitle = true)
        legacy?.event("screen", fields)
    }

    suspend fun screenClear() {
        dispatch(LinkFormat.extension("screen-clear", emptyMap()), subtitle = true)
        legacy?.event("screen-clear", emptyMap())
    }

    /** Ek alan. [line] true ise kutu tek satırdır: satır yüksekliği kutunun yüksekliği sayılır. */
    suspend fun region(id: String, text: String, box: Map<String, Double>, line: Boolean) {
        val h = if (line) box["bottom"]?.let { b -> box["top"]?.let { t -> b - t } }?.takeIf { it > 0 } else null
        region(id, text, box, h)
    }

    /** Ek alan; [lineHeight] satır yüksekliği (ekran yüksekliğine oran, 0–1). [text] boşsa kutu kalkar. */
    suspend fun region(id: String, text: String, box: Map<String, Double>?, lineHeight: Double?) {
        val raw = LinkedHashMap<String, Any?>()
        raw["id"] = id; raw["text"] = text
        if (!box.isNullOrEmpty()) raw["box"] = box
        if (lineHeight != null) raw["line"] = lineHeight
        val fields = LinkFormat.normalizeMap(raw)
        dispatch(LinkFormat.extension("region", fields), subtitle = true)
        legacy?.event("region", fields)
    }

    suspend fun regionClear(id: String) {
        // Protokolde region-clear bütün kutuları kaldırır; tek kutu boş metinle kalkar.
        if (id.isNotEmpty()) return region(id, "", null, null)
        regionClearAll()
    }

    /** Bütün ek alan kutularını kaldırır (çeviri durdu). */
    suspend fun regionClearAll() {
        dispatch(LinkFormat.extension("region-clear", emptyMap()), subtitle = true)
        legacy?.event("region-clear", emptyMap())
    }

    // --- iç işler ---

    private fun dispatch(json: String, subtitle: Boolean) {
        if (subtitle && !tvSubtitlesEnabled) return
        forEachNewOutput { it(json) }
    }

    /** Yeni protokol çıkışları: Android TV bağlantıları ve web TV'ler. */
    private inline fun forEachNewOutput(send: ((String) -> Unit) -> Unit) {
        val targets = synchronized(lock) { links.values.toList() }
        targets.forEach { l -> send { l.post(it) } }
        ingress?.let { i -> send { i.broadcast(it) } }
    }

    /** Yeni bağlanana sıra: style → (son 20 sn içinde başladıysa) started → ekranda kalması gereken altyazı. */
    private fun replayMessages(withStarted: Boolean = true): List<String> = synchronized(lock) {
        buildList {
            lastStyle?.let { add(it) }
            if (withStarted && started && System.currentTimeMillis() - startedAt <= config.legacyStartedWindowMs) add(LinkFormat.extension("started", emptyMap()))
            if (tvSubtitlesEnabled) shown?.let { add(it) }
        }
    }

    private fun legacyReplay(): LegacyEventServer.Replay = synchronized(lock) {
        LegacyEventServer.Replay(lastStyleFields, if (started) startedAt else null)
    }

    private fun infoJson(): String {
        val o = sortedMapOf<String, Any?>(
            "app" to "nino", "type" to "info", "version" to NinoLink.VERSION, "versions" to NinoLink.SUPPORTED_VERSIONS,
            "name" to config.deviceName, "id" to config.deviceId, "role" to "sender",
        )
        config.appVersion?.let { o["appVersion"] = it }
        return com.ninotranslator.core.json.Json.write(o)
    }

    private val publishLock = Any()
    /** Bağlı TV'lerin bağlandığı an (kopmada süre için). */
    private val connectedAt = HashMap<String, Long>()

    /**
     * Listeyi yeniden kurar; öncekiyle farkı [events]'e yazar. Giden TV'nin nedeni [reasons]'ta yoksa [fallback].
     * Her bağlanma ve kopma anında eşzamanlı çağrılır; sıra [publishLock] ile korunur.
     */
    private fun publish(reasons: Map<String, DropReason> = emptyMap(), fallback: DropReason = DropReason.OTHER) = synchronized(publishLock) {
        val list = ArrayList<ConnectedDisplay>()
        val (ls, i, l) = synchronized(lock) { Triple(links.values.toList(), ingress, legacy) }
        ls.mapNotNullTo(list) { it.display() }
        i?.displays()?.let { list += it }
        l?.displays()?.let { list += it }
        val before = _displays.value
        _displays.value = list
        val now = System.currentTimeMillis()
        val keys = list.mapTo(HashSet()) { it.key }
        for (d in before) if (d.key !in keys) {
            val at = connectedAt.remove(d.key) ?: now
            _events.tryEmit(DisplayEvent.Dropped(d, reasons[d.key] ?: fallback, now - at))
        }
        val old = before.mapTo(HashSet()) { it.key }
        for (d in list) if (d.key !in old) {
            connectedAt[d.key] = now
            _events.tryEmit(DisplayEvent.Connected(d))
        }
    }

    /** Bir Android TV'ye giden bağlantı: kendi gönderim sırası, ilk bağlantı ve canlı tutma. */
    private inner class TvLink(val host: String, val port: Int) {
        val sender = NinoSender(host, port, device = config.deviceName, client = config.clientVersion)
        val displayKey = "tv:$host:$port"
        /** Bu bağlantı döneminde bağlanamama bildirildi (yeniden denemeler tekrar bildirilmez). */
        @Volatile private var failureReported = false
        // Tek yazıcı: altyazılar ve yeniden bağlanınca son durum aynı sıradan gider.
        private val queue = Channel<Any>(256, BufferOverflow.DROP_OLDEST)
        private var job: Job? = null
        /** İlk bağlantının son durumu sıraya kondu; ondan önceki gönderimler bırakılır. */
        @Volatile private var ready = false

        fun start() {
            // Yeniden bağlanınca son durum (style → started → altyazı) baştan yollanır; o an okunur.
            sender.onReconnected = { queue.trySend(REPLAY); connected() }
            sender.onDropped = { reason -> publish(mapOf(displayKey to reason)) }
            sender.onReconnectFailed = { connectFailed(it) }
            job = scope.launch {
                val backoff = ReconnectBackoff()
                while (isActive) {
                    try { sender.connect(config.handshakeTimeoutMs); break } catch (e: CancellationException) { throw e } catch (e: Exception) {
                        connectFailed(e)
                        delay(backoff.next())
                    }
                }
                queue.trySend(REPLAY)
                ready = true
                connected()
                sender.startKeepAlive(config.pingIntervalMs, config.pongTimeoutMs)
                for (m in queue) {
                    try {
                        if (m === REPLAY) for (r in replayMessages()) sender.sendRaw(r) else sender.sendRaw(m as String)
                    } catch (e: CancellationException) { throw e } catch (_: Exception) { /* yeniden bağlanınca son durum gider */ }
                }
            }
        }

        private fun connected() {
            failureReported = false
            publish()
        }

        private fun connectFailed(e: Throwable) {
            if (failureReported) return
            failureReported = true
            _events.tryEmit(DisplayEvent.ConnectFailed(host, ConnectFailure.of(e)))
        }

        /** Bağlı değilken bırakılır: yeniden bağlanınca son durum yine gider. */
        fun post(json: String) {
            if (ready && sender.state.value is NinoSender.State.Connected) queue.trySend(json)
        }

        fun display(): ConnectedDisplay? {
            if (!ready) return null
            val s = sender.state.value as? NinoSender.State.Connected ?: return null
            val w = sender.lastWelcome
            return ConnectedDisplay(displayKey, s.displayName ?: host, host, DisplayKind.ANDROID_TV, w?.model, w?.appVersion)
        }

        fun close() {
            job?.cancel()
            queue.close()
            sender.close()
        }
    }
}
