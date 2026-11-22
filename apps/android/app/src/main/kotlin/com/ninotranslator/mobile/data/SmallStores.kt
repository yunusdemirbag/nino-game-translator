// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import android.content.SharedPreferences
import com.ninotranslator.core.pool.PoolInstall
import java.io.File

/**
 * Tek kurulum kimliği (§1.3): havuz, satır kuyruğu, sorun bildirimi, Nino'ya Sor ve ölçüm aynı UUID'yi kullanır.
 * Sıra: `files/pool/state.json`'daki `install`, `report/install`, `files/translation-pool/install`; ilk geçerli UUID
 * korunur, hiçbiri UUID değilse yenisi üretilir. Seçilen kimlik üç yere de yazılır ([PoolInstall]). Süreçte bir kez seçilir.
 */
class InstallIdentity(private val filesDir: File, report: SharedPreferences) {
    private val store = PrefStore(report)
    @Volatile private var cached: String? = null

    val id: String
        get() = cached ?: synchronized(this) {
            cached ?: PoolInstall.resolve(filesDir, store.string(KEY)).also { v ->
                if (store.string(KEY) != v) store.editNow(listOf(KEY)) { putString(KEY, v) }
                cached = v
            }
        }

    companion object {
        const val FILE = "report"
        const val KEY = "install"
    }
}

/** `app_update` (§1.4): GitHub'dan kurulan kopyanın sürüm denetimi. */
class AppUpdateStore(prefs: SharedPreferences) {
    private val store = PrefStore(prefs)

    val checkedAt: Long get() = store.long(K_CHECKED_AT, 0L)

    /** Başındaki `v` atılmış en son sürüm. */
    val latest: String? get() = store.string(K_LATEST)?.takeIf { it.isNotBlank() }

    /** 0 ya da gelecekteyse hemen; değilse 3 saat dolunca. */
    fun shouldCheck(nowMs: Long): Boolean {
        val at = checkedAt
        return at <= 0L || at > nowMs || nowMs - at >= CHECK_INTERVAL_MS
    }

    /** Yanıt geldi (403 dahil). [latest] null ise yalnız zaman güncellenir (taslak/ön sürüm yazılmaz). */
    fun recordCheck(nowMs: Long, latest: String?) {
        val v = latest?.trim()?.removePrefix("v")?.removePrefix("V")?.takeIf { it.isNotEmpty() }
        store.edit(K_CHECKED_AT, K_LATEST) {
            putLong(K_CHECKED_AT, nowMs)
            if (v != null) putString(K_LATEST, v)
        }
    }

    /** Eski kalıcı gizleme anahtarı; ✕'e basılınca silinir, hiç okunmaz. */
    fun removeLegacyDismissed() = store.remove(K_DISMISSED)

    companion object {
        const val FILE = "app_update"
        const val K_CHECKED_AT = "checked_at"
        const val K_LATEST = "latest"
        const val K_DISMISSED = "dismissed"
        const val CHECK_INTERVAL_MS = 3L * 60 * 60 * 1000
    }
}
