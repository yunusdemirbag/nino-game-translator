// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.support

import android.content.Context
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.SubtitleTarget
import com.ninotranslator.mobile.service.HealthSnapshot
import com.ninotranslator.mobile.service.HealthWatch
import com.ninotranslator.mobile.service.LiveSnapshot
import com.ninotranslator.mobile.service.LiveStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Sağlık ölçümünün arayüz tarafı (servis.md §5). Ölçümü hizmet yapar ([HealthWatch], [LiveSnapshot.health]);
 * burası saniyede bir [HealthInputs] ile [HealthInput]'a çevirir (eşikler ve sebepler [HealthEval]'de). Hizmet henüz
 * ölçmediyse yalnız ağ türü bilinir ve ekran "Çeviriyi başlatınca ölçülür" der. Süreç boyunca bir kez kurulur.
 */
object HealthFeed {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val _input = MutableStateFlow(HealthInput())
    val input: StateFlow<HealthInput> = _input.asStateFlow()

    @Volatile private var started = false

    fun ensureStarted(context: Context) {
        if (started) return
        synchronized(this) {
            if (started) return
            started = true
        }
        scope.launch {
            while (true) {
                runCatching { _input.value = inputOf(LiveStatus.state.value, System.currentTimeMillis()) }
                delay(1_000)
            }
        }
    }

    private fun inputOf(s: LiveSnapshot, now: Long): HealthInput {
        val targetTv = Nino.settings.target == SubtitleTarget.TV
        val h = s.health ?: HealthSnapshot(network = HealthWatch.network)
        val input = HealthInputs.of(h, now, running = s.running, streaming = s.streaming, targetTv = targetTv,
            tvConnected = s.connectedTvs, packLines = s.packLines)
        return if (s.health == null) input.copy(measured = false) else input
    }
}
