// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv

import com.ninotranslator.mobile.data.TvBrand
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Ağda bulunan TV. [brand] bilinmiyorsa null. [port] yalnız mDNS ile bulunan Android TV'de (Nino'nun dinlediği port);
 * [hasNino] true ise TV'de Nino açık ve altyazıya hazır (`_nino._tcp`).
 */
data class FoundTv(val name: String, val address: String, val brand: TvBrand?, val port: Int? = null, val hasNino: Boolean = false)

/** TV bulucu (mDNS `_nino._tcp` + SSDP). Arayüz yalnız bu arayüzü bilir. */
interface TvFinder {
    /** Bir kez arar; [timeoutMs] dolunca bulunanları döner. */
    suspend fun search(timeoutMs: Long = 3_000): List<FoundTv>
}

/** YER TUTUCU: asıl bulucu yazılana kadar hiç TV bulmaz. */
object NoTvFinder : TvFinder {
    override suspend fun search(timeoutMs: Long): List<FoundTv> = emptyList()
}

/** Kullanılan bulucu: asıl bulucu (mDNS + SSDP), uygulama bağlamı hazır olunca kendiliğinden kurulur. Testte değiştirilebilir. */
object TvFinders {
    @Volatile private var chosen: TvFinder? = null

    var current: TvFinder
        get() = chosen ?: runCatching { NetworkTvFinder(com.ninotranslator.mobile.data.Nino.appContext) }.getOrNull()?.also { chosen = it } ?: NoTvFinder
        set(value) { chosen = value }

    fun install(context: android.content.Context) {
        if (chosen == null) chosen = NetworkTvFinder(context)
    }
}

/**
 * TV'deki Nino telefondakinden eskiyse ana ekranda gösterilecek bilgi (ekranlar-1 §11.2). [tvVersion] null: eski 8787 TV
 * sürüm bildirmedi. [saved]: telefonun kayıtlı TV'si (`installedTv`); değilse bağlanan TV'den öğrenildi. [port]: kayıtlı
 * Android TV portu (0 = 5555).
 */
data class TvUpdateNotice(
    val brand: TvBrand,
    val tvVersion: String?,
    val phoneVersion: String,
    val host: String,
    val port: Int = 0,
    val saved: Boolean = true,
    val name: String? = null,
)

/** TV sürüm denetimi sonucu; `TvAppVersionCheck` doldurur (TV'deki Nino telefondakinden eskiyse dolu). */
object TvAppVersions {
    val notice = MutableStateFlow<TvUpdateNotice?>(null)
    val state: StateFlow<TvUpdateNotice?> get() = notice
}
