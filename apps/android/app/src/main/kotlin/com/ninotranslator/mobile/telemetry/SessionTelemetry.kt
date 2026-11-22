// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.telemetry

import android.os.SystemClock
import com.ninotranslator.core.link.ConnectFailure
import com.ninotranslator.core.link.ConnectedDisplay
import com.ninotranslator.core.link.DisplayEvent
import com.ninotranslator.core.link.DisplayHub
import com.ninotranslator.core.link.DisplayKind
import com.ninotranslator.core.link.DropReason
import com.ninotranslator.core.reading.live.LiveShowKind
import com.ninotranslator.core.reading.live.LumaPlane
import com.ninotranslator.core.telemetry.SessionTimings
import com.ninotranslator.core.telemetry.SessionTimings.Metric
import com.ninotranslator.core.telemetry.TelemetryCode
import com.ninotranslator.core.telemetry.TelemetryEvent
import com.ninotranslator.core.telemetry.TelemetryEvent.Ps5Route
import com.ninotranslator.core.telemetry.TelemetryEvent.TvBrand
import com.ninotranslator.core.telemetry.TelemetryEvent.TvProtocol
import com.ninotranslator.core.translation.LineResult
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.TvBrand as SettingsTvBrand
import com.ninotranslator.mobile.service.ServiceTexts
import com.ninotranslator.mobile.service.ShownLine
import com.ninotranslator.mobile.service.SourceKind
import com.ninotranslator.mobile.service.SourceState
import com.ninotranslator.mobile.service.TextReader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.onSubscription

/**
 * PS5 bağlantı izleyicisi (saf): kaynak durumlarından `ps5_connect` / `ps5_drop` olayları.
 * Hazırlanma/bağlanma bir deneme başlatır; yayın başlayınca `ok`; yayın yokken kopma `ps5_connect <kod>`,
 * yayındayken kopma `ps5_drop`. Kullanıcının durdurması kopma değildir (izleyici çağrılmaz).
 */
class Ps5Tracker(private val via: Ps5Route = Ps5Route.LAN, private val maxFailures: Int = 10) {
    private var attemptAt: Long? = null
    private var streamingAt: Long? = null
    private var failures = 0
    var firstStreamMs: Long? = null; private set
    private var firstAttemptAt: Long? = null

    fun onState(s: SourceState, nowMs: Long): List<TelemetryEvent> = when (s) {
        SourceState.Preparing, SourceState.Connecting -> {
            if (attemptAt == null && streamingAt == null) attemptAt = nowMs
            if (firstAttemptAt == null) firstAttemptAt = nowMs
            emptyList()
        }
        SourceState.Streaming -> {
            val start = attemptAt
            attemptAt = null
            if (streamingAt == null) streamingAt = nowMs
            if (start == null) emptyList() else listOf(TelemetryEvent.ps5Connect("ok", nowMs - start, via))
        }
        is SourceState.Reconnecting -> lost(s.reasonKey, nowMs)
        is SourceState.Failed -> lost(s.reasonKey, nowMs)
        SourceState.Idle -> emptyList()
    }

    /** İlk deneme başından şimdiye (ilk kare için). */
    fun sinceFirstAttempt(nowMs: Long): Long? = firstAttemptAt?.let { nowMs - it }

    private fun lost(key: String, nowMs: Long): List<TelemetryEvent> {
        val streamed = streamingAt
        val start = attemptAt
        streamingAt = null
        attemptAt = null
        return when {
            streamed != null -> listOf(TelemetryEvent.ps5Drop(dropCode(key), (nowMs - streamed) / 1000))
            start != null && failures < maxFailures -> { failures++; listOf(TelemetryEvent.ps5Connect(connectCode(key), nowMs - start, via)) }
            else -> emptyList()
        }
    }

    companion object {
        /** Hizmetin neden anahtarı → bağlantı hata kodu (kapalı eşleme; bilinmeyen `ps5.other`). */
        fun connectCode(key: String): String = when {
            key.startsWith("phase_not_found") -> TelemetryCode.PS5_DISCOVER_NONE
            key == "phase_network" -> TelemetryCode.PS5_SESSION_TIMEOUT
            key == "phase_in_use" -> TelemetryCode.PS5_SESSION_BUSY
            key == "phase_asleep" -> TelemetryCode.PS5_SESSION_STANDBY
            key == "phase_no_picture" -> TelemetryCode.PS5_STREAM_NO_PICTURE
            key == "phase_refused" || key.startsWith("phase_rejected") -> TelemetryCode.PS5_AUTH_REJECTED
            key == "phase_registration_invalid" -> TelemetryCode.PS5_REGISTER_FAILED
            key == "phase_remote_play_disabled" -> TelemetryCode.PS5_REMOTE_DISABLED
            key.startsWith("phase_passcode") -> TelemetryCode.PS5_AUTH_PASSCODE
            else -> TelemetryCode.PS5_OTHER
        }

        /** Yayındayken kopma sebebi. */
        fun dropCode(key: String): String = when (key) {
            "phase_network" -> TelemetryCode.Drop.NETWORK_LOST
            "phase_asleep" -> TelemetryCode.Drop.STANDBY
            "phase_in_use" -> TelemetryCode.Drop.KICKED
            "phase_no_picture" -> TelemetryCode.Drop.STALLED
            "phase_refused", "phase_rejected", "phase_rejected_code" -> TelemetryCode.Drop.PS5_CLOSED
            else -> TelemetryCode.Drop.OTHER
        }

        /** Oturumun başlamadan bitmesine yol açan hizmet anahtarı → hata kodu; sayılmayacaksa null. */
        fun failureCode(key: String): String? = when (key) {
            ServiceTexts.ERROR_NATIVE -> TelemetryCode.NATIVE_MISSING
            "capture_no_permission" -> TelemetryCode.CAPTURE_DENIED
            // Eşlenmemiş PS5, Xbox kaynağı yok: kullanıcı kurulumu, hata değil.
            else -> null
        }
    }
}

/**
 * TV bağlantı izleyicisi (saf): DisplayHub olaylarından `tv_connect` / `tv_drop`. Anahtar başına tekrarsızdır.
 * Uygulamanın durdurması ([DropReason.STOPPED]) kopma sayılmaz. Bağlanamama dönemi başına bir kez, toplam en çok
 * [maxFailures] `tv_connect` hatası.
 */
class TvTracker(private val maxFailures: Int = 10, private val brandOfWebTv: () -> TvBrand?) {
    private val since = HashMap<String, Long>()
    private val kinds = HashMap<String, DisplayKind>()
    private var waitingSince: Long? = null
    private var failures = 0

    fun start(nowMs: Long) { waitingSince = nowMs }

    /** Abone olunca o an bağlı olanlar (bağlanma olayları kaçmış olabilir). */
    fun seed(list: List<ConnectedDisplay>, nowMs: Long): List<TelemetryEvent> = list.flatMap { onEvent(DisplayEvent.Connected(it), nowMs) }

    fun onEvent(e: DisplayEvent, nowMs: Long): List<TelemetryEvent> = when (e) {
        is DisplayEvent.Connected -> {
            val d = e.display
            if (d.key in since) emptyList() else {
                since[d.key] = nowMs
                kinds[d.key] = d.kind
                // Süre: oturum başından (ya da son kopmadan) bağlanana kadar.
                val ms = waitingSince?.let { nowMs - it }
                listOf(TelemetryEvent.tvConnect("ok", ms, brand(d.kind), if (d.kind == DisplayKind.LEGACY) TvProtocol.LEGACY else TvProtocol.NINO))
            }
        }
        is DisplayEvent.Dropped -> {
            val at = since.remove(e.display.key)
            val kind = kinds.remove(e.display.key)
            if (since.isEmpty()) waitingSince = nowMs
            val code = dropCode(e.reason)
            if (at == null || code == null) emptyList()
            else listOf(TelemetryEvent.tvDrop(code, (kind ?: e.display.kind).let(::brand), (nowMs - at) / 1000))
        }
        is DisplayEvent.ConnectFailed -> {
            if (failures >= maxFailures) emptyList()
            else { failures++; listOf(TelemetryEvent.tvConnect(connectCode(e.reason), null, TvBrand.ANDROID_TV, TvProtocol.NINO)) }
        }
    }

    fun brand(kind: DisplayKind): TvBrand? = if (kind == DisplayKind.ANDROID_TV) TvBrand.ANDROID_TV else brandOfWebTv()

    val connected: Boolean get() = since.isNotEmpty()
    fun firstBrand(): TvBrand? = kinds.values.firstOrNull()?.let(::brand)

    companion object {
        /** Kopma nedeni → `tv_drop.code` (tarif). Uygulamanın durdurması null: gönderilmez. */
        fun dropCode(r: DropReason): String? = when (r) {
            DropReason.TIMEOUT -> TelemetryCode.Drop.TIMEOUT
            DropReason.CLOSED -> TelemetryCode.Drop.CLOSED
            DropReason.WRITE_ERROR -> TelemetryCode.Drop.WRITE_ERROR
            DropReason.NETWORK_LOST -> TelemetryCode.Drop.NETWORK_LOST
            // Tarifte "yerine başkası geldi" kodu yok.
            DropReason.REPLACED, DropReason.OTHER -> TelemetryCode.Drop.OTHER
            DropReason.STOPPED -> null
        }

        /** Bağlanamama nedeni → `tv_connect.r`. */
        fun connectCode(r: ConnectFailure): String = when (r) {
            ConnectFailure.TIMEOUT, ConnectFailure.NETWORK -> TelemetryCode.TV_CONNECT_TIMEOUT
            ConnectFailure.REFUSED -> TelemetryCode.TV_CONNECT_REFUSED
            ConnectFailure.PROTOCOL -> TelemetryCode.TV_PROTOCOL_MISMATCH
            ConnectFailure.OTHER -> TelemetryCode.TV_OTHER
        }
    }
}

/**
 * Çeviri oturumunun ölçümü: PS5/TV bağlantıları, okuma ve çeviri süreleri, oturum sonu. Hizmet yalnız tek satırlık
 * çağrılar yapar. Klip (deneme kareleri) ölçülmez. Altyazı metni, konsol adı ve hata ayrıntısı hiç kullanılmaz.
 */
object SessionTelemetry {
    private val lock = Any()
    @Volatile private var active: Active? = null

    private class Active(
        val kind: SourceKind,
        val startedMs: Long,
        val game: () -> String?,
        val ps5: Ps5Tracker?,
        val tv: TvTracker,
        val timings: SessionTimings = SessionTimings(),
    ) {
        var lines = 0L
        @Volatile var frameSeen = false
        var firstSubtitle = false
        var tvJob: Job? = null
    }

    private fun now() = SystemClock.elapsedRealtime()
    private fun record(e: TelemetryEvent) = AppTelemetry.record(e)

    /** `begin()`: oturum başladı. */
    fun started(kind: SourceKind, hub: DisplayHub?, game: () -> String?) {
        if (kind == SourceKind.DEBUG_FRAMES) return
        val ps5 = if (kind == SourceKind.REMOTE_PLAY || kind == SourceKind.XBOX) Ps5Tracker(if (kind == SourceKind.XBOX) Ps5Route.XBOX else Ps5Route.LAN) else null
        val tv = TvTracker { installedWebBrand() }
        val a = Active(kind, now(), game, ps5, tv)
        synchronized(lock) { active?.tvJob?.cancel(); active = a }
        AppTelemetry.setSessionRunning(true)
        tv.start(a.startedMs)
        if (hub != null) {
            // Olaylardan: kısa bir kopup yeniden bağlanma da nedeniyle sayılır. Abone olunca bağlı olanlar eklenir.
            fun apply(f: (TvTracker) -> List<TelemetryEvent>) {
                val events = synchronized(lock) { if (active === a) f(a.tv) else emptyList() }
                events.forEach(::record)
                AppTelemetry.setTvBrand(if (a.tv.connected) a.tv.firstBrand() else null)
            }
            a.tvJob = hub.events
                .onSubscription { apply { it.seed(hub.displays.value, now()) } }
                .onEach { e -> apply { it.onEvent(e, now()) } }
                .launchIn(CoroutineScope(SupervisorJob() + Dispatchers.Default))
        }
    }

    fun onSourceState(s: SourceState) {
        val a = active ?: return
        val events = synchronized(lock) { a.ps5?.onState(s, now()).orEmpty() }
        events.forEach(::record)
        if (s is SourceState.Failed && a.kind == SourceKind.CAPTURE_CARD) Ps5Tracker.failureCode(s.reasonKey)?.let { AppTelemetry.recordError(it) }
    }

    /** Kare geldi (sıcak yol: yalnız bir kez iş yapar). */
    fun onFrame() {
        val a = active ?: return
        if (a.frameSeen) return
        a.frameSeen = true
        val ms = a.ps5?.sinceFirstAttempt(now()) ?: (now() - a.startedMs)
        a.timings.record(Metric.FIRST_FRAME, ms)
    }

    /** Ekranda bir satır gösterildi: kaynağa göre süre, gecikme ve satır sayısı. */
    fun onShow(line: ShownLine) {
        val a = active ?: return
        if (line.kind != LiveShowKind.NEW) return
        synchronized(lock) {
            a.lines++
            if (!a.firstSubtitle) { a.firstSubtitle = true; a.timings.record(Metric.FIRST_SUBTITLE, now() - a.startedMs) }
        }
        line.latencyMs?.let { a.timings.record(Metric.TOTAL, it) }
        val ms = line.translateMs ?: return
        when (line.origin) {
            LineResult.Origin.PACK -> a.timings.record(Metric.PACK, ms)
            LineResult.Origin.POOL -> a.timings.record(Metric.POOL, ms)
            LineResult.Origin.ONLINE -> a.timings.recordProvider(providerName(line.engine), ms)
            LineResult.Origin.ON_DEVICE -> a.timings.recordProvider("mlkit", ms)
            else -> Unit
        }
    }

    fun onTranslationFailed() { if (active != null) AppTelemetry.recordError(TelemetryCode.LINE_FAILED) }

    /** Yakalanan hata (kod listesinden). */
    fun error(code: String) { if (active != null) AppTelemetry.recordError(code) }

    /** Altyazı sunucusunun kapısı başka uygulamada. */
    fun portBusy(any: Boolean) { if (any) error(TelemetryCode.PORT_BUSY) }

    /** Cihaz içi dil modeli indirilemedi. */
    fun modelMissing(warn: Boolean) { if (warn) error(TelemetryCode.ON_DEVICE_MISSING) }

    /** Oturum başlamadan bitti (`fail(key)`). */
    fun failed(key: String) {
        Ps5Tracker.failureCode(key)?.let { AppTelemetry.recordError(it) }
    }

    /** Kurulum beklenmeyen bir hatayla düştü. */
    fun setupFailed() = AppTelemetry.recordError(TelemetryCode.SESSION_SETUP)

    /** `stop()`: oturum sonu (`session`). Kullanıcı durdurması kopma sayılmaz; TV izleme önce bırakılır. */
    fun ended() {
        val a = synchronized(lock) { active.also { active = null } }
        AppTelemetry.setSessionRunning(false)
        a ?: return
        a.tvJob?.cancel()
        val dur = (now() - a.startedMs) / 1000
        val src = when (a.kind) {
            SourceKind.CAPTURE_CARD -> TelemetryEvent.SessionSource.CAPTURE
            SourceKind.XBOX -> TelemetryEvent.SessionSource.XBOX
            else -> TelemetryEvent.SessionSource.REMOTE_PLAY
        }
        record(TelemetryEvent.session(dur, runCatching { a.game() }.getOrNull()?.let(::gameId), src, a.lines, a.timings))
        AppTelemetry.flushSoon()
    }

    /** Yazı tanımayı süre ölçerek sarar (kare başına `ocr`). */
    fun timed(reader: TextReader): TextReader = TextReader { image: LumaPlane ->
        val start = now()
        // Hata ve iptal olduğu gibi geçer; yalnız başarılı okuma süre olarak eklenir.
        reader.read(image).also { active?.timings?.record(Metric.OCR, now() - start) }
    }

    /** Çevirmen adı: motorun önbellek adından (`deepl`, `gemini:…`, `openai:…`) yalnız sağlayıcı. */
    fun providerName(engine: String?): String {
        val e = engine?.lowercase().orEmpty()
        return listOf("deepl", "gemini", "openai", "claude", "groq").firstOrNull { e.startsWith(it) || e.contains(it) } ?: "online"
    }

    /** Oyun adı ya da kimliğinden asıl kimlik (`Grand Theft Auto VI` → `gta-6`, `Yeni Oyun` → `yeni-oyun`); kimliğe çevrilemeyende null, alan gönderilmez. */
    fun gameId(g: String): String? = com.ninotranslator.core.telemetry.TelemetryEvent.gameField(g)

    private fun installedWebBrand(): TvBrand? = when (Nino.settingsOrNull()?.installedTv?.brand) {
        SettingsTvBrand.LG -> TvBrand.LG
        SettingsTvBrand.SAMSUNG -> TvBrand.SAMSUNG
        else -> null
    }
}
