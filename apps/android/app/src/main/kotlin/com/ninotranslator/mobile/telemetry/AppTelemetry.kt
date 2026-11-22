// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.telemetry

import android.app.Activity
import android.app.ActivityManager
import android.app.Application
import android.app.ApplicationExitInfo
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.os.SystemClock
import android.util.Log
import com.ninotranslator.core.http.UrlConnectionTransport
import com.ninotranslator.core.pool.PoolEndpoint
import com.ninotranslator.core.telemetry.CrashMarker
import com.ninotranslator.core.telemetry.PreviousExit
import com.ninotranslator.core.telemetry.Telemetry
import com.ninotranslator.core.telemetry.TelemetryCode
import com.ninotranslator.core.telemetry.TelemetryContext
import com.ninotranslator.core.telemetry.TelemetryEvent
import com.ninotranslator.mobile.BuildConfig
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.TvBrand as SettingsTvBrand
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.File

/**
 * Uygulamanın ölçüm bağlantısı (tarif: olcum.md): açılış, çökme işareti, ön plan/arka plan, `ctx`.
 * Kapatma düğmesi yoktur; yalnız sunucu durdurabilir. Kişisel veri, metin, IP ve istisna mesajı gönderilmez.
 *
 * Çalışıyor sayılma: ekranda bir etkinlik açık ya da çeviri oturumu sürüyor (çeviri arka planda da sürer).
 * İkisi de yokken işaret "arka planda" olur; o sırada işletim sisteminin kapatması çökme sayılmaz.
 */
object AppTelemetry {
    private const val TAG = "NinoTelemetry"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Any()

    @Volatile var client: Telemetry? = null
        private set
    private var marker: CrashMarker? = null
    private val early = ArrayList<(Telemetry) -> Unit>()
    @Volatile private var installed = false
    private var startedActivities = 0
    @Volatile private var sessionRunning = false
    @Volatile private var launchRecorded = false

    /** `NinoApplication.onCreate`: çökme yakalayıcı ve işaret hemen (eşzamanlı); kuyruk ve ağ IO'da. */
    fun install(app: Application) {
        if (installed) return
        installed = true
        val dir = File(app.filesDir, "telemetry")
        val m = CrashMarker(dir)
        marker = m
        installCrashHandler(m)
        val previous = runCatching { m.begin(BuildConfig.VERSION_NAME, nowS(), Process.myPid()) }.getOrNull()
        app.registerActivityLifecycleCallbacks(Lifecycle)
        AppDiag.install(app, dir)

        scope.launch {
            val t = runCatching { create(app, m) }.onFailure { Log.w(TAG, "ölçüm kurulamadı", it) }.getOrNull() ?: return@launch
            val exit = runCatching { previousExit(app, previous) }.getOrDefault(PreviousExit.Unknown)
            t.reportPreviousRun(previous, exit)
            val pending = synchronized(lock) { client = t; early.toList().also { early.clear() } }
            pending.forEach { runCatching { it(t) } }
            t.start(scope)
        }
    }

    private fun create(app: Application, m: CrashMarker): Telemetry? {
        // Kurulum kimliği havuzdakiyle aynı (pool/state.json). UUID değilse ölçüm gönderilmez (sunucu 400 verir).
        val install = Nino.installId.lowercase()
        if (!TelemetryContext.isInstallId(install)) { Log.w(TAG, "kurulum kimliği UUID değil; ölçüm kapalı"); return null }
        val options = Telemetry.Options(
            endpoint = PoolEndpoint.resolve(app.filesDir),
            installId = install,
            context = context(),
            directory = File(app.filesDir, "telemetry"),
            userAgent = PoolEndpoint.userAgent(BuildConfig.VERSION_NAME),
        )
        return Telemetry(options, UrlConnectionTransport, m, isOnline = { online(app) })
    }

    /** `ctx`: platform, sürüm, işletim sistemi, cihaz modeli (kullanıcının verdiği ad asla), kanal. */
    fun context(): TelemetryContext = TelemetryContext(
        platform = "android",
        app = BuildConfig.VERSION_NAME,
        os = "Android ${Build.VERSION.RELEASE}",
        device = Build.MODEL.orEmpty(),
        tv = when (Nino.settingsOrNull()?.installedTv?.brand) {
            SettingsTvBrand.ANDROID_TV -> "androidtv"
            SettingsTvBrand.LG -> "lg"
            SettingsTvBrand.SAMSUNG -> "samsung"
            null -> ""
        },
        channel = channel(BuildConfig.DEBUG, BuildConfig.VERSION_NAME),
    ).cleaned()

    /** Geliştirici yapısı `dev` (sunucu alır, saymaz); sürümde `beta` geçiyorsa `beta`. */
    fun channel(debug: Boolean, version: String): String = when {
        debug -> "dev"
        version.contains("beta", ignoreCase = true) -> "beta"
        else -> "release"
    }

    // ---- kayıt (istemci hazır değilse sıraya alınır) ----

    private fun whenReady(block: (Telemetry) -> Unit) {
        val t = synchronized(lock) { client ?: run { if (early.size < 50) early += block; null } } ?: return
        runCatching { block(t) }
    }

    fun record(e: TelemetryEvent) = whenReady { it.record(e) }
    fun recordError(code: String, http: Int? = null) = whenReady { it.recordError(code, http) }
    fun setTvBrand(brand: TelemetryEvent.TvBrand?) = whenReady { it.setTvBrand(brand) }
    fun flushSoon() { client?.flushSoon() }

    fun setSessionRunning(running: Boolean) {
        sessionRunning = running
        updateRunning()
    }

    private fun updateRunning() {
        val running = synchronized(lock) { startedActivities > 0 } || sessionRunning
        runCatching { marker?.setBackground(!running, nowS()) }
        if (!running) flushSoon()
    }

    private object Lifecycle : Application.ActivityLifecycleCallbacks {
        override fun onActivityStarted(activity: Activity) {
            val first = synchronized(lock) { startedActivities++ == 0 }
            if (first) { updateRunning(); AppDiag.foreground() }
        }

        override fun onActivityStopped(activity: Activity) {
            val last = synchronized(lock) { startedActivities = (startedActivities - 1).coerceAtLeast(0); startedActivities == 0 }
            if (last) { updateRunning(); AppDiag.background() }
        }

        override fun onActivityResumed(activity: Activity) {
            if (launchRecorded) return
            launchRecorded = true
            // Soğuk açılış: süreç başından ilk ekranın öne gelmesine (uzunsa ölçülmemiş sayılır).
            val ms = SystemClock.uptimeMillis() - Process.getStartUptimeMillis()
            record(TelemetryEvent.launch(ms.takeIf { it in 0..30_000 }))
        }

        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
        override fun onActivityPaused(activity: Activity) = Unit
        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
        override fun onActivityDestroyed(activity: Activity) = Unit
    }

    // ---- çökme ----

    /** Yakalanmamış istisnada yalnız sınıf adı ve uygulama içi sembol işarete yazılır; önceki yakalayıcıya geçilir. */
    private fun installCrashHandler(m: CrashMarker) {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            runCatching { m.noteCrash(TelemetryCode.ofThrowable(error), TelemetryCode.whereOf(error)) }
            if (previous != null) previous.uncaughtException(thread, error) else { Process.killProcess(Process.myPid()); System.exit(10) }
        }
    }

    /** Android 11+: önceki sürecin çıkış sebebi (aynı pid). Yerel çökme, ANR, önde bellek yetmezliği çökmedir. */
    private fun previousExit(context: Context, previous: CrashMarker.Record?): PreviousExit {
        if (previous == null || Build.VERSION.SDK_INT < 30) return PreviousExit.Unknown
        val am = context.getSystemService(ActivityManager::class.java) ?: return PreviousExit.Unknown
        val pid = previous.pid ?: return PreviousExit.Unknown
        val info = am.getHistoricalProcessExitReasons(context.packageName, pid, 1).firstOrNull()
            ?.takeIf { it.timestamp >= previous.started * 1000 - 60_000 } ?: return PreviousExit.Unknown
        return exitOf(info.reason, info.status, previous.background)
    }

    /** Çıkış sebebi → karar (saf; test edilir). `status` yerel çökmede sinyal numarasıdır. */
    fun exitOf(reason: Int, status: Int, background: Boolean): PreviousExit = when (reason) {
        ApplicationExitInfo.REASON_CRASH -> PreviousExit.Crash(TelemetryCode.UNCLEAN_EXIT)
        ApplicationExitInfo.REASON_CRASH_NATIVE -> PreviousExit.Crash(signalName(status))
        ApplicationExitInfo.REASON_ANR -> PreviousExit.Crash("anr")
        ApplicationExitInfo.REASON_LOW_MEMORY -> if (background) PreviousExit.Clean else PreviousExit.Crash("oom")
        else -> PreviousExit.Clean
    }

    fun signalName(status: Int): String = when (status) {
        4 -> "SIGILL"
        5 -> "SIGTRAP"
        6 -> "SIGABRT"
        7 -> "SIGBUS"
        8 -> "SIGFPE"
        11 -> "SIGSEGV"
        else -> "native_crash"
    }

    // ---- yardımcılar ----

    private fun online(context: Context): Boolean = runCatching {
        val cm = context.getSystemService(ConnectivityManager::class.java)
        cm.getNetworkCapabilities(cm.activeNetwork)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
    }.getOrDefault(true)

    private fun nowS() = System.currentTimeMillis() / 1000
}
