// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.support

import android.util.Log
import com.ninotranslator.core.http.HttpRequest
import com.ninotranslator.core.http.HttpTransport
import com.ninotranslator.core.http.UrlConnectionTransport
import com.ninotranslator.core.json.Json
import com.ninotranslator.core.pool.PoolConfig
import com.ninotranslator.core.pool.PoolEndpoint
import com.ninotranslator.mobile.BuildConfig
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.service.LiveStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Toplam indirme sayacı (ceviri.md 6.8): `/v1/config` cevabındaki `downloads`, `ninoDownloadTotal`'a yazılır.
 * Ana ekran açıkken açılışta ve en çok 600 sn'de bir sorulur (10 sn bağlanma/okuma). Çeviri sürerken havuz bu
 * cevabı zaten okur ([record]); o sırada ayrı istek yok. Alınamazsa son bilinen sayı kalır.
 */
object DownloadCounter {
    const val INTERVAL_MS = 600_000L
    private const val TIMEOUT_MS = 10_000

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    @Volatile private var lastAt = Long.MIN_VALUE / 2
    @Volatile var http: HttpTransport = UrlConnectionTransport

    /** Ana ekrandan çağrılır; son sorudan 600 sn geçmediyse bir şey yapmaz. */
    fun refresh(nowMs: Long = System.currentTimeMillis()) {
        val live = LiveStatus.state.value
        if (live.running && !live.demo) return
        val before: Long
        synchronized(this) {
            if (nowMs - lastAt < INTERVAL_MS) return
            before = lastAt
            lastAt = nowMs
        }
        scope.launch {
            val n = runCatching { fetch() }.onFailure { Log.i("Nino", "indirme sayısı alınamadı: ${it.message}") }.getOrNull()
            // Alınamadıysa sınır konmaz: ana ekrana dönülünce yeniden sorulur.
            if (n == null || n <= 0) synchronized(this@DownloadCounter) { if (lastAt == nowMs) lastAt = before } else record(n)
        }
    }

    /** Engelleyici: sunucudan sayıyı alır; alınamazsa null. */
    fun fetch(): Long? {
        val url = PoolEndpoint.resolve(Nino.filesDir) + "/v1/config"
        val r = http.send(HttpRequest(url, headers = mapOf("User-Agent" to PoolEndpoint.userAgent(BuildConfig.VERSION_NAME)),
            connectTimeoutMs = TIMEOUT_MS, readTimeoutMs = TIMEOUT_MS))
        if (!r.ok) return null
        return PoolConfig.parse(Json.parseObject(r.text)).downloads
    }

    /** Pozitif sayı kalıcı yazılır (ana ekran ayar değişikliğiyle yeniden çizilir). */
    fun record(downloads: Long?, nowMs: Long = System.currentTimeMillis()) {
        val n = downloads?.takeIf { it > 0 } ?: return
        synchronized(this) { lastAt = maxOf(lastAt, nowMs) }
        val v = n.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        val s = Nino.settingsOrNull() ?: return
        if (s.downloadTotal != v) s.downloadTotal = v
    }
}
