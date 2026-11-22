// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.packs

import android.content.Context
import android.util.Log
import com.ninotranslator.core.packs.GameIds
import com.ninotranslator.core.packs.PackImporter
import com.ninotranslator.core.packs.PackStore
import com.ninotranslator.mobile.service.TranslationControl
import com.ninotranslator.mobile.telemetry.AppDiag
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Asıl paket kataloğu: havuzdan inen + içe aktarılan paketler, [PackStore] ile ([PoolPacks]). Kapalı paketler de
 * listelenir (yeniden açılabilsinler diye). Kütüphane yalnız ad ve satır sayısı için yüklenir, sonra bırakılır.
 * Hiç paket yoksa liste boştur; çeviri paketsiz sürer.
 */
class StorePackCatalog(context: Context) : PackCatalog {
    private val app = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _state = MutableStateFlow(PackListState(loading = true, packs = emptyList()))
    override val state: StateFlow<PackListState> = _state.asStateFlow()
    private var job: Job? = null

    private fun store(): PackStore = PoolPacks.store(app)

    val importedDir: File get() = File(app.filesDir, "packs-imported")

    override fun refresh(force: Boolean) {
        if (job?.isActive == true) return
        _state.update { it.copy(loading = it.packs.isEmpty() && it.imported.isEmpty()) }
        job = scope.launch {
            try {
                val s = store()
                // Önce telefondaki liste (ağ beklenmez), sonra gerekiyorsa havuzla eşitlenip yeniden.
                if (!force) publish(s)
                // "Paketleri güncelle" ya da son bakış 24 saatten eskiyse havuzla eşitlenir.
                if (force || s.isDue(PackStore.Reason.DAILY)) {
                    val r = runCatching { s.refresh() }.getOrNull().also(AppDiag::packs)
                    if (force || r?.changed == true || s.serverPacks.isNotEmpty()) publish(s)
                }
            } catch (e: Throwable) {
                Log.w("Nino", "paket listesi okunamadı", e)
                _state.update { it.copy(loading = false) }
            }
        }
    }

    private fun publish(s: PackStore) {
        val lib = s.loadLibrary(emptySet())
        // Havuz paketinin gölgelediği eski paket de listeye girer; aynı oyunun kartında birleşir (aç/kapa ikisine).
        val all = (lib.packs + lib.shadowed).map { PackInfo(it.id, it.title, it.entryCount) }
        // Sunucuda olup henüz inmemiş paketler de görünür.
        val missing = s.serverPacks.filter { sp -> all.none { it.id == sp.id } }
            .map { PackInfo(it.id, it.title, it.entries.toInt()) }
        val (imported, others) = (all + missing).partition { it.id.startsWith(COMMUNITY) }
        _state.value = PackListState(loading = false, packs = distinctGames(others), imported = imported)
    }

    /** İçe aktarılan paketi siler ve listeyi yeniler. */
    fun deleteImported(id: String): Boolean {
        val ok = File(importedDir, "$id.json").delete()
        TranslationControl.reloadPacks(app)
        job?.cancel(); refresh(false)
        return ok
    }

    /** İçe aktarılan paketi kaydeder (aynı kimlik varsa [replace] gerekir) ve listeyi yeniler. */
    fun saveImported(title: String, preview: PackImporter.Preview, replace: Boolean): String {
        val id = PackImporter.save(importedDir, title, preview, replace)
        TranslationControl.reloadPacks(app)
        job?.cancel(); refresh(false)
        return id
    }

    companion object {
        const val COMMUNITY = "community-"

        /** Aynı asıl kimliğe ([GameIds]) düşen paketler tek oyun: havuz paketi gösterilir, ötekiler [PackInfo.ids]'te. */
        fun distinctGames(list: List<PackInfo>): List<PackInfo> =
            GameIds.groupPacks(list, { it.id }, { it.title }).map { g -> g.first().copy(ids = g.flatMap { it.ids }.distinct()) }
    }
}
