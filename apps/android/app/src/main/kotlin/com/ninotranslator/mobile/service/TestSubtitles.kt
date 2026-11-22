// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import android.content.Context
import android.util.Log
import com.ninotranslator.core.link.NinoLink
import com.ninotranslator.core.link.ShowPayload
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.Settings
import com.ninotranslator.mobile.data.SubtitleTarget
import com.ninotranslator.mobile.data.TvBrand
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/** Ayarlardaki görünümün TV'ye giden `style` iletisi (tv.md 1.5). */
fun tvStyleOf(settings: Settings): Map<String, Any?> = TvStyle.map(StyleInput(
    autoSize = settings.tvAutoSize, background = settings.effectiveTvBackground,
    backgroundShape = settings.tvBackgroundShape, bottomPercent = settings.tvBottomPercent,
    displayMode = settings.tvDisplayMode, font = settings.subtitleFont, fontSize = settings.tvFontPx,
    placement = settings.tvPlacement, stackPrevious = settings.stackPrevious, textColor = settings.textColor,
    watermark = settings.tvWatermark,
))

/**
 * Deneme altyazısı (servis.md 3.8): 8 sn'lik örnek altyazı. Çeviri sürüyorsa oturum gönderir (hedef TV ya da telefon).
 * Çeviri çalışmıyorsa ve hedef TV ise TV bağlantısı ([TvHub]) kısa süre açılır: bağlı bir TV beklenir (en çok
 * [WAIT_MS]), görünüm ve altyazı gönderilir, süre bitince bağlantı kapanır (bu arada çeviri başladıysa kapanmaz).
 * Art arda basılınca (kaydırıcı) tek pencere uzar; açma/kapama üst üste binmez.
 */
object TestSubtitles {
    private const val TAG = "Nino"
    const val ID = 900_000_001
    const val DURATION_MS = 8_000
    const val WAIT_MS = 6_000L

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Any()
    private var idleRunning = false
    @Volatile private var idleUntil = 0L
    @Volatile private var pendingText: String? = null
    @Volatile private var pendingDone: ((Boolean) -> Unit)? = null

    /** [onDone] ana iş parçacığında: altyazı bir yere gittiyse true. */
    fun send(context: Context, text: String, onDone: (Boolean) -> Unit) {
        SessionControl.handler?.let { h -> h.testSubtitle(text); post(onDone, true); return }
        // Örnek oturum (demo): altyazı telefondaki satıra yazılır.
        if (LiveStatus.state.value.let { it.running && it.demo }) { showOnPhone(text); post(onDone, true); return }
        if (Nino.settings.target != SubtitleTarget.TV) { post(onDone, false); return }
        val app = context.applicationContext
        synchronized(lock) {
            pendingText = text
            pendingDone = onDone
            if (idleRunning) return
            idleRunning = true
        }
        scope.launch { runIdle(app) }
    }

    private suspend fun runIdle(context: Context) {
        try { runIdleOnce(context) } finally {
            // Kapanırken gelen istek kaybolmasın.
            val again = synchronized(lock) { (pendingText != null).also { idleRunning = it } }
            if (again) scope.launch { runIdle(context) }
        }
    }

    private suspend fun runIdleOnce(context: Context) {
        val settings = Nino.settings
        val hub = TvHub.hub(context)
        val opened = TvHub.openIdle()
        try {
            if (!opened) {
                // Bu arada çeviri başladı: oturum göndersin.
                takePending()?.let { (t, done) -> SessionControl.handler?.testSubtitle(t); post(done, SessionControl.handler != null) }
                return
            }
            hub.tvSubtitlesEnabled = true
            hub.setStyle(tvStyleOf(settings))
            settings.installedTv?.takeIf { it.brand == TvBrand.ANDROID_TV }?.let { hub.connectTo(it.host, NinoLink.DEFAULT_PORT) }
            val connected = withTimeoutOrNull(WAIT_MS) { hub.displays.first { it.isNotEmpty() } } != null
            while (true) {
                val (text, done) = takePending() ?: break
                if (!connected) { post(done, false); break }
                runCatching { hub.show(ShowPayload(ID, text, durationMs = DURATION_MS)) }
                post(done, true)
                idleUntil = System.currentTimeMillis() + DURATION_MS
                // Yeni istek gelene ya da süre bitene kadar bekle.
                while (pendingText == null && System.currentTimeMillis() < idleUntil) delay(200)
            }
            if (connected) runCatching { hub.clear(ID) }
        } catch (t: Throwable) {
            Log.w(TAG, "deneme altyazısı gönderilemedi", t)
            takePending()?.let { (_, done) -> post(done, false) }
        } finally {
            if (opened) TvHub.closeIdle()
        }
    }

    private fun showOnPhone(text: String) {
        LiveStatus.update { it.copy(currentLine = text, currentLineId = it.currentLineId + 1) }
        scope.launch {
            delay(DURATION_MS.toLong())
            LiveStatus.update { if (it.currentLine == text) it.copy(currentLine = null, currentLineId = it.currentLineId + 1) else it }
        }
    }

    private fun takePending(): Pair<String, (Boolean) -> Unit>? = synchronized(lock) {
        val t = pendingText ?: return null
        val d = pendingDone ?: {}
        pendingText = null; pendingDone = null
        t to d
    }

    private fun post(done: (Boolean) -> Unit, ok: Boolean) {
        scope.launch { withContext(Dispatchers.Main) { done(ok) } }
    }
}
