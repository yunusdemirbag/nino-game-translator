// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.ninotranslator.mobile.data.HealthIssue
import com.ninotranslator.mobile.data.HealthIssueKind
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.support.AutoReport
import com.ninotranslator.mobile.support.DeviceSummary
import com.ninotranslator.mobile.support.Findings
import com.ninotranslator.mobile.support.HealthEval
import com.ninotranslator.mobile.support.HealthInputs
import com.ninotranslator.mobile.support.HealthLevel
import com.ninotranslator.mobile.support.NetKind
import com.ninotranslator.mobile.support.NinoServer
import com.ninotranslator.mobile.telemetry.AppDiag
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Sorun kayıt kuralları (servis.md 6.1). Saf; [tick] düzenli çağrılır. PS5 kuralları yalnız PS5 Remote Play'de.
 * PS5 kopunca kayıt; 180 sn geri gelmezse "dakikalardır geri gelmiyor" + hemen otomatik bildirim; TV'ye altyazı
 * giderken bağlı TV sıfıra iner ve 20 sn geri gelmezse kayıt; ağ çevrimdışına geçince (ardışıklar bir kez) kayıt.
 */
class IssueRules(private val ps5Rules: Boolean) {
    sealed interface Out {
        data class Issue(val kind: HealthIssueKind, val reason: String? = null) : Out
        data object ReportNow : Out
        data object TvDropped : Out
    }

    private var dropAt: Long? = null
    private var tvZeroAt: Long? = null
    private var tvCount = 0
    private var offline = false
    var issues = 0; private set

    fun onDrop(reason: String?, nowMs: Long): List<Out> {
        if (!ps5Rules) return emptyList()
        dropAt = nowMs
        issues++
        return listOf(Out.Issue(HealthIssueKind.PS5_DROPPED, reason))
    }

    fun onStreaming() { dropAt = null }

    fun onTvCount(n: Int, toTv: Boolean, nowMs: Long) {
        if (n == 0 && tvCount > 0 && toTv) tvZeroAt = nowMs
        if (n > 0) tvZeroAt = null
        tvCount = n
    }

    fun onNetwork(kind: NetKind): List<Out> {
        val off = kind == NetKind.OFFLINE
        val out = if (off && !offline) { issues++; listOf(Out.Issue(HealthIssueKind.NETWORK_LOST)) } else emptyList()
        offline = off
        return out
    }

    fun tick(nowMs: Long): List<Out> {
        val out = ArrayList<Out>()
        val d = dropAt
        if (d != null && nowMs - d >= PS5_GONE_MS) {
            dropAt = null; issues++
            out += Out.Issue(HealthIssueKind.PS5_UNREACHABLE); out += Out.ReportNow
        }
        val t = tvZeroAt
        if (t != null && nowMs - t >= TV_GONE_MS) {
            tvZeroAt = null; issues++
            out += Out.Issue(HealthIssueKind.TV_DROPPED); out += Out.TvDropped
        }
        return out
    }

    companion object {
        const val PS5_GONE_MS = 180_000L
        const val TV_GONE_MS = 20_000L
    }
}

/**
 * Sağlık izleme (servis.md 5–6): uygulama açılınca kurulur, hizmetten bağımsızdır; oturum kapanınca da bildirim
 * gönderebilir. Klipte hiç çalışmaz. Durum [state]'te ve canlı durumda ([LiveSnapshot.health]).
 */
object HealthWatch {
    private const val TAG = "NinoHealth"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val meter = HealthMeter(System::currentTimeMillis)
    private val _state = MutableStateFlow(HealthSnapshot())
    val state: StateFlow<HealthSnapshot> = _state

    @Volatile private var installed = false
    @Volatile private var rules: IssueRules? = null
    @Volatile private var kind: SourceKind? = null
    @Volatile private var reportedThisSession = false
    @Volatile private var game: () -> String? = { null }
    @Volatile private var toTv: () -> Boolean = { true }
    private var ticker: Job? = null
    private val main = Handler(Looper.getMainLooper())

    fun install(context: Context) {
        if (installed) return
        installed = true
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return
        meter.network = networkOf(cm)
        AppDiag.network(meter.network)
        runCatching {
            cm.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) { main.postDelayed({ onNetwork(networkOf(cm)) }, 300) }
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) { onNetwork(networkOf(cm)) }
                // Wi-Fi'den mobile geçişte de kayıp gelir: 1,5 sn sonra yeniden bakılır.
                override fun onLost(network: Network) { main.postDelayed({ onNetwork(networkOf(cm)) }, 1_500) }
            })
        }.onFailure { Log.w(TAG, "ağ izlenemiyor", it) }
        // Önceki açılışta ağ hatasıyla gönderilemeyen bildirim.
        scope.launch { runCatching { Nino.autoReport.pending }.getOrNull()?.let { send(it) } }
    }

    /** Şimdiki ağ türü (uygulama açılınca izlenir; sağlık ekranı da bunu gösterir). */
    val network: NetKind get() = meter.network

    @Suppress("DEPRECATION")
    private fun networkOf(cm: ConnectivityManager): NetKind {
        val caps = runCatching { cm.getNetworkCapabilities(cm.activeNetwork) }.getOrNull() ?: return NetKind.OFFLINE
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> NetKind.WIRED
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> NetKind.WIFI
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> NetKind.CELLULAR
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) -> NetKind.OTHER
            else -> NetKind.OFFLINE
        }
    }

    private fun onNetwork(k: NetKind) {
        AppDiag.network(k)
        meter.network = k
        val r = rules ?: return publish()
        val out = r.onNetwork(k)
        if (out.isNotEmpty()) meter.onNetworkLost()
        handle(out)
    }

    // ---- hizmetten gelenler ----

    fun sessionStarted(k: SourceKind, gameName: () -> String?, subtitlesToTv: () -> Boolean) {
        AppDiag.sessionStarted(k, gameName)
        if (k == SourceKind.DEBUG_FRAMES) { kind = null; rules = null; return }
        kind = k; game = gameName; toTv = subtitlesToTv
        reportedThisSession = false
        rules = IssueRules(ps5Rules = k == SourceKind.REMOTE_PLAY)
        meter.start()
        publish()
        ticker?.cancel()
        ticker = scope.launch { while (isActive) { delay(1_000); rules?.let { handle(it.tick(System.currentTimeMillis())) }; publish() } }
    }

    fun onSourceState(s: SourceState) {
        AppDiag.sourceState(s)
        val r = rules ?: return
        when (s) {
            SourceState.Streaming -> { meter.onStreaming(); r.onStreaming() }
            SourceState.Connecting -> meter.onConnecting()
            is SourceState.Reconnecting, is SourceState.Failed -> {
                val key = (s as? SourceState.Reconnecting)?.reasonKey ?: (s as SourceState.Failed).reasonKey
                val reason = DropReasons.of(key)
                if (meter.onLost(reason)) handle(r.onDrop(reason, System.currentTimeMillis()))
            }
            else -> Unit
        }
        publish()
    }

    fun onFrames(total: Long) { AppDiag.frames(total); if (rules != null) meter.onFrames(total) }
    fun onLine(translateMs: Long?) { if (rules != null) meter.onLine(translateMs) }
    fun onTvCount(n: Int) { rules?.onTvCount(n, toTv(), System.currentTimeMillis()) }

    /** Oturum bitti: kayıt olduysa ya da görüntü/çeviri "sorun" düzeyindeyse otomatik bildirim. */
    fun sessionEnded() {
        AppDiag.sessionEnded()
        val r = rules ?: return
        ticker?.cancel(); ticker = null
        meter.stop()
        val s = meter.snapshot()
        _state.value = s
        LiveStatus.update { it.copy(health = s) }
        val i = input(s)
        if (r.issues > 0 || HealthEval.pictureLevel(i) == HealthLevel.PROBLEM || HealthEval.translationLevel(i) == HealthLevel.PROBLEM) autoReport(s)
        rules = null
    }

    private fun handle(out: List<IssueRules.Out>) {
        for (o in out) when (o) {
            is IssueRules.Out.Issue -> record(o.kind, o.reason)
            IssueRules.Out.ReportNow -> autoReport(meter.snapshot())
            IssueRules.Out.TvDropped -> meter.onTvDrop()
        }
    }

    private fun record(k: HealthIssueKind, reason: String?) {
        val s = meter.snapshot()
        runCatching {
            Nino.health.add(HealthIssue(
                dateMs = System.currentTimeMillis(), kind = k, network = s.network.wire, reason = reason,
                streamedMinutes = s.streamedMs / 60_000.0, framesPerSecond = s.framesPerSecond, game = game(),
            ))
        }.onFailure { Log.w(TAG, "sorun yazılamadı", it) }
    }

    private fun publish() {
        val s = meter.snapshot()
        _state.value = s
        if (rules != null) LiveStatus.update { if (it.health == s) it else it.copy(health = s) }
    }

    // ---- otomatik bildirim (servis.md 6.2) ----

    private fun input(s: HealthSnapshot) = HealthInputs.of(s, System.currentTimeMillis(), targetTv = toTv(),
        tvConnected = LiveStatus.state.value.connectedTvs)

    private fun autoReport(s: HealthSnapshot) {
        val settings = Nino.settingsOrNull() ?: return
        if (!settings.autoReport || reportedThisSession) return
        val counter = Nino.autoReport
        if (!counter.canSendToday()) return
        reportedThisSession = true
        // Gün sayacı gönderimden önce artar.
        counter.recordSent()
        val body = AutoReport.body(Findings.section(input(s), System.currentTimeMillis()), DeviceSummary.line())
        scope.launch { send(body) }
    }

    private fun send(body: String) {
        val status = runCatching { NinoServer.post("/v1/reports", body, 30_000).status }.getOrNull()
        Log.i(TAG, "otomatik bildirim: ${status ?: "ağ hatası"}")
        runCatching { Nino.autoReport.setPending(if (AutoReport.retryable(status)) body else null) }
    }
}
