// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.packs

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Oyun paketi özeti (Oyun paketleri ekranı). [id] `disabledPacks` ayarındaki kimliktir. [ids]: aynı oyunun bütün
 * paketleri (havuz paketi başta); aç/kapa hepsine uygulanır.
 */
data class PackInfo(val id: String, val title: String, val lineCount: Int, val ids: List<String> = listOf(id))

/** Paket listesi durumu. [imported] içe aktarılan (topluluk) paketler; [packs] diğerleri. */
data class PackListState(val loading: Boolean, val packs: List<PackInfo>, val imported: List<PackInfo> = emptyList())

/** Havuzdan inen ve içe aktarılan paketlerin listesi. Arayüz yalnız bu arayüzü bilir. */
interface PackCatalog {
    val state: StateFlow<PackListState>

    /** Listeyi yükler; [force] true ise sunucudan yeniden indirir ("Paketleri güncelle"). */
    fun refresh(force: Boolean)
}

/** YER TUTUCU: asıl paket katmanı bağlanana kadar boş liste verir (uydurma paket göstermez). */
object EmptyPackCatalog : PackCatalog {
    private val flow = MutableStateFlow(PackListState(loading = false, packs = emptyList()))
    override val state: StateFlow<PackListState> get() = flow
    override fun refresh(force: Boolean) {}
}

/** Kullanılan katalog: uygulama bağlamı hazırsa asıl depo ([StorePackCatalog]); testte değiştirilebilir. */
object Packs {
    @Volatile private var chosen: PackCatalog? = null

    var catalog: PackCatalog
        get() = chosen ?: runCatching { StorePackCatalog(com.ninotranslator.mobile.data.Nino.appContext) }.getOrNull()
            ?.also { chosen = it } ?: EmptyPackCatalog
        set(value) { chosen = value }
}
