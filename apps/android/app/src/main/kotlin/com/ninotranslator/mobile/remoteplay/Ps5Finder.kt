// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.remoteplay

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext

/** Ağda bulunan PS5. Çalışan uygulama ana ekranda ya da dinlenmede boştur (null). */
data class FoundPs5(
    val address: String,
    val name: String,
    val awake: Boolean,
    val runningTitleId: String?,
    val runningAppName: String?,
)

/**
 * PS5 bulucu. Arama yayınla değil, hedef adreslere tek tek yapılır (verilen adres ya da telefonun /24 ağı);
 * yerel kod süre dolana kadar 500 ms'de bir yeniden sorar.
 */
class Ps5Finder(
    private val interfaces: () -> List<NetInterface> = NetworkAddresses::systemInterfaces,
) {
    /** Bloklar. [address] verilmişse yalnız ona sorulur. Kütüphane yoksa ya da hedef yoksa boş. */
    fun findBlocking(address: String?, timeoutMs: Int): List<FoundPs5> {
        if (!RemotePlayNative.isReady) return emptyList()
        val targets = NetworkAddresses.searchTargets(address, interfaces())
        if (targets.isEmpty()) return emptyList()
        return parse(RemotePlayNative.nativeDiscover(targets.toTypedArray(), timeoutMs))
    }

    suspend fun find(address: String?, timeoutMs: Int): List<FoundPs5> =
        withContext(Dispatchers.IO) { findBlocking(address, timeoutMs) }

    /**
     * Eşleme ekranının sürekli araması: tüm ağ 2,5 sn aranır; hiç yoksa 1,5 sn, bulunduysa 6 sn sonra yinelenir.
     * Toplayan iptal edince durur.
     */
    fun pairingScan(): Flow<List<FoundPs5>> = flow {
        while (true) {
            val found = findBlocking(null, PAIRING_SEARCH_MS)
            emit(found)
            delay(if (found.isEmpty()) RETRY_EMPTY_MS else RETRY_FOUND_MS)
        }
    }.flowOn(Dispatchers.IO)

    companion object {
        const val PAIRING_SEARCH_MS = 2_500
        const val RETRY_EMPTY_MS = 1_500L
        const val RETRY_FOUND_MS = 6_000L
        const val SAVED_ADDRESS_SEARCH_MS = 2_000
        const val RELOCATE_SEARCH_MS = 3_000

        /** Yerelden gelen düz dizi: her PS5 için 5 alan. */
        fun parse(flat: Array<String>): List<FoundPs5> = (0 until flat.size / 5).map { i ->
            val b = i * 5
            FoundPs5(
                address = flat[b],
                name = flat[b + 1].ifBlank { "PS5" },
                awake = flat[b + 2] == "1",
                runningTitleId = flat[b + 3].ifBlank { null },
                runningAppName = flat[b + 4].ifBlank { null },
            )
        }
    }
}
