// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile

import android.app.Application
import com.ninotranslator.mobile.data.AppLocales
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.Settings
import com.ninotranslator.mobile.service.HealthWatch
import com.ninotranslator.mobile.tv.install.TvAppVersionCheck
import com.ninotranslator.mobile.telemetry.AppTelemetry

/** Uygulama açılışı: veri katmanı, önceki kapanış durumu, arayüz dili. */
class NinoApplication : Application() {
    private var languageListener: AutoCloseable? = null

    override fun onCreate() {
        super.onCreate()
        Nino.init(this)
        // Ölçüm: çökme yakalayıcı ve çalışma işareti en başta (kapatma düğmesi yok; tarif olcum.md).
        AppTelemetry.install(this)
        val settings = Nino.settings
        // §5.8: `translating` okunur ve hemen false yapılır.
        Nino.previousRunDiedWhileTranslating = settings.consumeTranslatingFlag()
        // §5.3: arayüz dili çeviri dilini izler.
        AppLocales.apply(this, settings.uiLanguageTag)
        // §6: sağlık izleme uygulama açılınca kurulur (hizmetten bağımsız; bekleyen otomatik bildirimi de gönderir).
        HealthWatch.install(this)
        // tv.md 3.4: kayıtlı TV'deki Nino sürümüne sessizce bakılır (açılışta ve TV bağlantısı değişince).
        TvAppVersionCheck.install(this)
        languageListener = settings.addListener { key ->
            if (key == Settings.K.TARGET_LANGUAGE) AppLocales.apply(this, settings.uiLanguageTag)
        }
    }
}
