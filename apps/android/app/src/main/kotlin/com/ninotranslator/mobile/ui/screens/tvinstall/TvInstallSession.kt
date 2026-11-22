// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.tvinstall

import com.ninotranslator.mobile.tv.install.techDetail
import com.ninotranslator.mobile.data.InstalledTv
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.tv.TvUpdateNotice
import com.ninotranslator.mobile.tv.install.TvInstallError
import com.ninotranslator.mobile.tv.install.TvInstallException
import com.ninotranslator.mobile.tv.install.TvInstallRequest
import com.ninotranslator.mobile.tv.install.TvInstallResult
import com.ninotranslator.mobile.tv.install.TvInstallStep
import com.ninotranslator.mobile.tv.install.TvInstallers
import com.ninotranslator.mobile.tv.install.TvUpdatePlan
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Süren TV kurulumu; ekrandan bağımsız (ekran kapansa da kurulum biter). */
object TvInstallSession {
    data class State(
        val running: Boolean = false,
        val step: TvInstallStep? = null,
        val result: TvInstallResult? = null,
        val error: TvInstallException? = null,
        val request: TvInstallRequest? = null,
        /** Ana ekrandaki güncelleme kartından başlatıldıysa o kartın verisi (kart sonucu gösterene dek kalır). */
        val card: TvUpdateNotice? = null,
    )

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    fun start(request: TvInstallRequest, card: TvUpdateNotice? = null) {
        if (_state.value.running) return
        _state.value = State(running = true, request = request, card = card)
        scope.launch {
            try {
                val r = TvInstallers.current.install(request) { step -> _state.update { it.copy(step = step) } }
                Nino.settings.recordTvInstall(InstalledTv(request.brand, r.host, r.port, r.version))
                _state.update { it.copy(running = false, result = r, step = null) }
            } catch (e: TvInstallException) {
                Nino.tvInstallLog.append("hata: ${e.error} ${e.message.orEmpty()}")
                _state.update { it.copy(running = false, error = e, step = null) }
            } catch (e: Exception) {
                Nino.tvInstallLog.append("hata: ${e.javaClass.simpleName} ${e.message.orEmpty()}")
                _state.update { it.copy(running = false, error = TvInstallException(TvInstallError.FAILED, techDetail(e), note = e.message), step = null) }
            }
        }
    }

    /** Kurulum bu TV için mi (adresin ip kısmı). */
    fun isFor(host: String?): Boolean = host != null && _state.value.request?.let { TvUpdatePlan.hostOf(it.address) } == TvUpdatePlan.hostOf(host)

    /** Biten kurulumun sonucunu siler (marka değişimi, ekrandan çıkış). Süren kurulum etkilenmez. */
    fun clearFinished() { _state.update { if (it.running) it else State() } }
}
