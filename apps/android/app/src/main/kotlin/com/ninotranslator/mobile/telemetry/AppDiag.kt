// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.telemetry

import android.app.Application
import android.content.ComponentCallbacks2
import android.content.res.Configuration
import android.os.Build
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import com.ninotranslator.core.link.DisplayEvent
import com.ninotranslator.core.link.DisplayHub
import com.ninotranslator.core.link.DisplayKind
import com.ninotranslator.core.link.ConnectedDisplay
import com.ninotranslator.core.packs.PackStore
import com.ninotranslator.core.reading.live.LiveShowKind
import com.ninotranslator.core.reading.live.LumaPlane
import com.ninotranslator.core.telemetry.TelemetryEvent.TvBrand
import com.ninotranslator.core.telemetry.diag.DiagBudget
import com.ninotranslator.core.telemetry.diag.DiagConfig
import com.ninotranslator.core.telemetry.diag.DiagWatch
import com.ninotranslator.core.translation.KeyStatus
import com.ninotranslator.core.translation.LineResult
import com.ninotranslator.core.translation.OnlineError
import com.ninotranslator.mobile.BuildConfig
import com.ninotranslator.mobile.service.ShownLine
import com.ninotranslator.mobile.service.SourceKind
import com.ninotranslator.mobile.service.SourceState
import com.ninotranslator.mobile.service.TextReader
import com.ninotranslator.mobile.support.NetKind
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.onSubscription
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File
import java.util.concurrent.atomic.AtomicLong
import kotlin.coroutines.cancellation.CancellationException

/**
 * Otomatik teşhisin uygulama bağlantısı (tarif: otomatik-teshis.md). Bekçi çekirdekte ([DiagWatch]); burada yalnız
 * hizmetin ve sistemin olayları yapılandırılmış adıma çevrilir. Teşhis ölçümün parçasıdır: ayrı kapatma düğmesi
 * yoktur, sunucu `telemetry.diag` ile kural kapatır. Metin, ad, adres hiçbir adıma girmez.
 */
object AppDiag {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    @Volatile private var watch: DiagWatch? = null
    @Volatile private var kind: SourceKind? = null
    @Volatile private var game: () -> String? = { null }
    @Volatile private var tv: Pair<DisplayKind, Pair<String?, String?>>? = null
    private var ticker: Job? = null
    private var tvJob: Job? = null
    private var streaming = false
    private var net: NetKind? = null
    private var lastFrames: Pair<Long, Long>? = null

    /** `AppTelemetry.install`: bekçi, ana iş parçacığı izleyicisi, bellek uyarısı ve kaynak örneklemesi. */
    fun install(app: Application, directory: File) {
        if (watch != null) return
        val w = DiagWatch(
            clock = System::currentTimeMillis,
            sink = AppTelemetry::record,
            config = { AppTelemetry.client?.remoteConfig?.diag ?: DiagConfig() },
            budget = DiagBudget(File(directory, "diag.json")),
            memHighMb = 800.0,
            context = ::context,
        )
        watch = w
        app.registerComponentCallbacks(object : ComponentCallbacks2 {
            override fun onTrimMemory(level: Int) {
                @Suppress("DEPRECATION")
                if (level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL) w.step("mem.high", memMb())
            }
            override fun onConfigurationChanged(newConfig: Configuration) = Unit
            @Deprecated("Deprecated in Java")
            override fun onLowMemory() = w.step("mem.high", memMb())
        })
        watchMainThread(w)
        val power = app.getSystemService(PowerManager::class.java)
        scope.launch {
            var cpuAt = Process.getElapsedCpuTime() to SystemClock.elapsedRealtime()
            while (isActive) {
                delay(10_000)
                val now = Process.getElapsedCpuTime() to SystemClock.elapsedRealtime()
                val wall = (now.second - cpuAt.second).coerceAtLeast(1)
                val cpu = (now.first - cpuAt.first) * 100 / wall / Runtime.getRuntime().availableProcessors().coerceAtLeast(1)
                cpuAt = now
                runCatching { w.resources(memMb(), cpu, thermal(power)) }
            }
        }
    }

    // ---- hizmetten (tek satırlık çağrılar) ----

    fun sessionStarted(k: SourceKind, gameName: () -> String?) {
        val w = watch ?: return
        if (k == SourceKind.DEBUG_FRAMES) return
        kind = k; game = gameName; streaming = false; lastFrames = null
        w.step("session.start")
        ticker?.cancel()
        ticker = scope.launch { while (isActive) { delay(1_000); w.tick() } }
    }

    fun sessionEnded() {
        val w = watch ?: return
        if (kind == null) return
        kind = null
        ticker?.cancel(); ticker = null
        tvJob?.cancel(); tvJob = null
        w.step("session.stop")
    }

    /** PS5/Xbox kaynak durumu: yayındayken kopma `ps5.drop` (sebep kodu), yeniden deneme `ps5.retry`. */
    fun sourceState(s: SourceState) {
        val w = watch ?: return
        val k = kind ?: return
        if (k != SourceKind.REMOTE_PLAY && k != SourceKind.XBOX) return
        when (s) {
            SourceState.Streaming -> { streaming = true; w.step("ps5.connect") }
            is SourceState.Reconnecting -> if (streaming) { streaming = false; w.step("ps5.drop", reason = ps5Reason(s.reasonKey)) } else w.step("ps5.retry")
            is SourceState.Failed -> if (streaming) { streaming = false; w.step("ps5.drop", reason = ps5Reason(s.reasonKey)) }
            else -> Unit
        }
    }

    /** Kare sayacı (2 sn'de bir): saniyedeki kare. */
    fun frames(total: Long) {
        val w = watch ?: return
        if (kind == null) return
        val now = SystemClock.elapsedRealtime()
        val prev = lastFrames
        lastFrames = total to now
        if (prev == null || now <= prev.second) return
        w.step("ps5.frame", ((total - prev.first).coerceAtLeast(0) * 1000) / (now - prev.second))
    }

    fun network(k: NetKind) {
        val w = watch ?: return
        val before = net
        net = k
        w.set("net", when (k) {
            NetKind.WIFI -> "wifi"; NetKind.WIRED -> "ethernet"; NetKind.CELLULAR -> "cellular"; NetKind.OFFLINE -> "none"; NetKind.OTHER -> "other"
        })
        when {
            before == k -> Unit
            k == NetKind.OFFLINE -> w.step("net.down")
            before == NetKind.OFFLINE -> w.step("net.up")
            before != null -> w.step("net.change")
        }
    }

    /** Ekranda yeni çeviri satırı (gecikme ve kaynağı). Havuz ya da çevirmenden geldiyse başarılı istek sayılır. */
    fun shown(line: ShownLine) {
        val w = watch ?: return
        if (kind == null || line.kind != LiveShowKind.NEW) return
        val origin = when (line.origin) {
            LineResult.Origin.PACK -> "pack"
            LineResult.Origin.POOL -> "pool"
            LineResult.Origin.ONLINE -> "provider"
            LineResult.Origin.ON_DEVICE -> "device"
            else -> null
        }
        if (line.origin == LineResult.Origin.ONLINE) w.set("provider", SessionTelemetry.providerName(line.engine))
        // Çevirmen istekleri [providerRequest]'ten sayılır; burada yalnız havuz.
        w.line(line.latencyMs, origin, request = line.origin == LineResult.Origin.POOL)
    }

    /** Anahtarlı çevirmenin her isteği: başarı ya da hata türü (429 → quota, anahtar → auth, ulaşılamadı → offline/timeout). */
    fun providerRequest(e: OnlineError?) {
        val w = watch ?: return
        if (kind == null) return
        if (e == null) { w.step("tr.ok"); return }
        when (e.status) {
            KeyStatus.QUOTA -> w.step("tr.error", 429, "quota")
            KeyStatus.INVALID_KEY, KeyStatus.MODEL_REJECTED -> w.step("tr.error", 401, "auth")
            KeyStatus.UNREACHABLE -> if (e.rateLimitedMs != null) w.step("tr.error", 429, "quota") else w.step("tr.error", null, if (net == NetKind.OFFLINE) "offline" else "timeout")
            else -> w.step("tr.error")
        }
    }

    /** Satırın bütün çevirmenleri başarısız oldu. */
    fun translationFailed() { if (kind != null) watch?.step("tr.error") }

    /** Yazı tanımayı sarar: süre, takılma (10 sn) ve "yazı okundu mu". */
    fun timed(reader: TextReader): TextReader = TextReader { image: LumaPlane ->
        val w = watch
        if (w == null || kind == null) return@TextReader reader.read(image)
        val start = SystemClock.elapsedRealtime()
        w.ocrStarted()
        try {
            reader.read(image).also { w.ocrDone(SystemClock.elapsedRealtime() - start, it.isNotEmpty()) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            w.ocrDone(SystemClock.elapsedRealtime() - start, false); throw e
        }
    }

    /** TV bağlanma/kopmaları (oturum sürerken). */
    fun watchTv(hub: DisplayHub) {
        val w = watch ?: return
        tvJob?.cancel()
        fun connected(d: ConnectedDisplay) {
            tv = d.kind to (d.model to d.appVersion)
            w.set("proto", if (d.kind == DisplayKind.LEGACY) "legacy" else "nino")
            w.step("tv.connect")
        }
        tvJob = hub.events
            // Oturumdan önce bağlanmış TV'ler (bağlanma olayı kaçmış olabilir).
            .onSubscription { hub.displays.value.forEach(::connected) }
            .onEach { e ->
                when (e) {
                    is DisplayEvent.Connected -> connected(e.display)
                    // Kopma nedeni ölçümdekiyle aynı eşleme; uygulamanın durdurması (null) sayılmaz.
                    is DisplayEvent.Dropped -> TvTracker.dropCode(e.reason)?.let { w.step("tv.drop", reason = it) }
                    else -> Unit
                }
            }
            .launchIn(scope)
    }

    /** Paket eşitlemesi: inemeyen paketler `pack.fail`, inenler sayaçtan çıkar. */
    fun packs(r: PackStore.RefreshResult?) {
        val w = watch ?: return
        if (r == null || !r.ok) return
        r.downloaded.forEach(w::packOk)
        r.failed.forEach { w.packFailed(it, null, null) }
    }

    fun background() { watch?.step("app.background") }
    fun foreground() { watch?.step("app.foreground") }

    // ---- yardımcılar ----

    private fun context(): DiagWatch.Context {
        val t = tv
        val brand = when (t?.first) {
            DisplayKind.ANDROID_TV -> TvBrand.ANDROID_TV
            null -> null
            else -> AppTelemetry.context().tv.let { b -> TvBrand.entries.firstOrNull { it.wire == b } }
        }
        return DiagWatch.Context(brand, t?.second?.first, t?.second?.second,
            runCatching { game() }.getOrNull()?.let(SessionTelemetry::gameId), mapOf("core" to BuildConfig.VERSION_NAME))
    }

    /** Hizmetin neden anahtarı → kopma sebebi kodu. */
    private fun ps5Reason(key: String): String? = when (key) {
        "phase_network" -> "network_lost"
        "phase_asleep" -> "ps5_standby"
        "phase_in_use" -> "kicked"
        "phase_no_picture" -> "stalled"
        "phase_refused", "phase_rejected", "phase_rejected_code" -> "ps5_closed"
        else -> null
    }

    private fun memMb(): Long {
        val rt = Runtime.getRuntime()
        return (rt.totalMemory() - rt.freeMemory() + Debug.getNativeHeapAllocatedSize()) / (1024 * 1024)
    }

    private fun thermal(power: PowerManager?): String? {
        if (power == null || Build.VERSION.SDK_INT < 29) return null
        return when (power.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE, PowerManager.THERMAL_STATUS_LIGHT -> "nominal"
            PowerManager.THERMAL_STATUS_MODERATE -> "fair"
            PowerManager.THERMAL_STATUS_SEVERE -> "serious"
            else -> "critical"
        }
    }

    /** Ana iş parçacığı izleyicisi: saniyede bir ana iş parçacığına iş bırakır; `hangSec` (5) dönmezse askı (blok başına bir kez). */
    private fun watchMainThread(w: DiagWatch) {
        val main = Handler(Looper.getMainLooper())
        val answered = AtomicLong(SystemClock.uptimeMillis())
        val ping = Runnable { answered.set(SystemClock.uptimeMillis()) }
        Thread({
            var reported = false
            while (true) {
                main.post(ping)
                val before = SystemClock.uptimeMillis()
                try { Thread.sleep(1_000) } catch (e: InterruptedException) { return@Thread }
                // Süreç bütünüyle dondurulduysa (önbellek dondurucu, hata ayıklayıcı) izleyici de uyumuştur: askı değil.
                if (SystemClock.uptimeMillis() - before > 3_000) { answered.set(SystemClock.uptimeMillis()); continue }
                val blocked = (SystemClock.uptimeMillis() - answered.get()) / 1000
                val limit = AppTelemetry.client?.remoteConfig?.diag?.limit(DiagConfig.Limit.HANG_SEC) ?: 5.0
                if (blocked >= limit && !reported) { reported = true; runCatching { w.mainBlocked(blocked) } }
                if (blocked < 2) reported = false
            }
        }, "nino-diag-hang").apply { isDaemon = true; priority = Thread.MIN_PRIORITY }.start()
    }
}
