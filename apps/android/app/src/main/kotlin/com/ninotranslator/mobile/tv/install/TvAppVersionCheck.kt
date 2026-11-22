// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install

import android.content.Context
import com.ninotranslator.mobile.data.InstalledTv
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.service.TvHub
import com.ninotranslator.mobile.tv.TvAppVersions
import com.ninotranslator.mobile.tv.TvUpdateNotice
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Sessiz sürüm denetimi (tv.md 3.4): uygulama açılınca ve TV bağlantı durumu her değiştiğinde kayıtlı TV'deki sürüme
 * ve bağlı her Nino TV'nin bildirdiği sürüme bakılır; aynı anda tek denetim. TV'deki sürüm telefondakinden eskiyse ana
 * ekran kartı ve Ayarlar satırı için [TvAppVersions.notice] dolar (karar [TvUpdatePlan.decide]). Kurulum ancak
 * kullanıcı karttaki düğmeye basınca başlar.
 */
object TvAppVersionCheck {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val running = Mutex()
    private val installed = AtomicBoolean(false)
    @Volatile private var app: Context? = null

    /** Kart verisi: TV'deki sürüm telefondakinden kesin eskiyse dolu. */
    fun notice(tv: InstalledTv, tvVersion: String?, phoneVersion: String?): TvUpdateNotice? {
        if (tvVersion == null || phoneVersion == null) return null
        return if (TvVersions.compare(phoneVersion, tvVersion) > 0) TvUpdateNotice(tv.brand, tvVersion, phoneVersion, tv.host, tv.port) else null
    }

    fun install(context: Context) {
        if (!installed.compareAndSet(false, true)) return
        val app = context.applicationContext
        this.app = app
        checkNow()
        scope.launch {
            runCatching {
                // Bağlanan/kopan TV ve TV'nin bildirdiği sürüm değişince yeniden denetlenir.
                TvHub.hub(app).displays.map { l -> l.map { it.address to it.appVersion } }.distinctUntilChanged().collect { checkNow() }
            }
        }
    }

    /** Bir denetim başlatır (sürüyorsa yenisi başlamaz). */
    fun checkNow() {
        scope.launch {
            if (!running.tryLock()) return@launch
            try { runCatching { check() } } finally { running.unlock() }
        }
    }

    private fun check() {
        val settings = Nino.settingsOrNull() ?: return
        val installer = TvInstallers.current as? NetworkTvInstaller ?: return
        val tv = settings.installedTv
        val version = tv?.let { installer.quietVersion(it) }
        if (tv != null && version != null && version != tv.version) settings.installedTv = tv.copy(version = version)
        val displays = app?.let { a -> runCatching { TvHub.hub(a).displays.value }.getOrNull() }.orEmpty()
        val d = TvUpdatePlan.decide(tv, version, displays, installer::phoneVersion)
        if (!d.keep) TvAppVersions.notice.value = d.notice // keep: kayıtlı TV'ye ulaşılamadı, durum değişmez
    }
}
