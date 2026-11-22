// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.update

import android.content.Context
import com.ninotranslator.core.http.HttpRequest
import com.ninotranslator.core.http.HttpTransport
import com.ninotranslator.core.http.UrlConnectionTransport
import com.ninotranslator.core.json.Json
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.ui.screens.home.AppUpdates
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Telefon uygulamasının güncelleme denetimi (servis.md §14). Play'den kurulmuş kopyada hiç denetlenmez. */
object AppUpdateChecker {
    const val API = "https://api.github.com/repos/yunusdemirbag/nino-game-translator/releases/latest"
    const val APK = "https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Telefon.apk"

    @Volatile var http: HttpTransport = UrlConnectionTransport

    enum class Outcome { CHECKED, OFFLINE, SKIPPED }

    /** [force] = "Şimdi denetle": 3 saat beklenmez. Hatalar sessizdir; sonuç yalnız Ayarlar satırı için. */
    suspend fun check(context: Context, force: Boolean): Outcome = withContext(Dispatchers.IO) {
        if (AppUpdates.installedFromStore(context)) return@withContext Outcome.SKIPPED
        val store = Nino.appUpdate
        val now = System.currentTimeMillis()
        if (!force && !store.shouldCheck(now)) return@withContext Outcome.SKIPPED
        try {
            val r = http.send(HttpRequest(API, headers = mapOf("User-Agent" to "Nino-Android", "Accept" to "application/vnd.github+json"),
                connectTimeoutMs = 8_000, readTimeoutMs = 8_000))
            // Yanıt geldiyse (403 dahil) 3 saat beklenir.
            store.recordCheck(now, if (r.ok) latestOf(r.text) else store.latest)
            Outcome.CHECKED
        } catch (e: Exception) {
            Outcome.OFFLINE
        }
    }

    /** Taslak ve ön sürüm yok sayılır; baştaki `v` atılır. */
    fun latestOf(json: String): String? {
        val m = runCatching { Json.parseObject(json) }.getOrNull() ?: return null
        if (m["draft"] == true || m["prerelease"] == true) return null
        return (m["tag_name"] as? String)?.trim()?.removePrefix("v")?.removePrefix("V")?.substringBefore('+')?.takeIf { it.isNotEmpty() }
    }
}
