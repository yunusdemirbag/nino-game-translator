// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import android.app.LocaleManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.LocaleList
import java.util.Locale

/**
 * Arayüz dili (§5.3). Android 13+: sistemin uygulama başına dil ayarı (AppCompat yok). 12 ve altı: her etkinlik
 * bağlamı [wrap] ile sarılır (`attachBaseContext` içinde).
 */
object AppLocales {
    /** Android 13+: etiket farklıysa uygulama dilini ayarlar (açık ekranlar sistemce yeniden çizilir). */
    fun apply(context: Context, tag: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        runCatching {
            val lm = context.getSystemService(LocaleManager::class.java) ?: return
            val current = lm.applicationLocales
            if (current.size() == 1 && current[0].toLanguageTag() == tag) return
            lm.applicationLocales = LocaleList.forLanguageTags(tag)
        }
    }

    /** Android 12 ve altı: bağlamı çeviri dilinin yereliyle sarar. 13+ ise olduğu gibi döner. */
    fun wrap(base: Context): Context {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return base
        val tag = Nino.settingsOrNull()?.uiLanguageTag
            ?: AppLanguage.uiTag(base.getSharedPreferences(Settings.FILE, Context.MODE_PRIVATE).getString(Settings.K.TARGET_LANGUAGE, null)
                ?: AppLanguage.fromDevice(Locale.getDefault().language))
        val locale = Locale.forLanguageTag(tag)
        Locale.setDefault(locale)
        val config = Configuration(base.resources.configuration)
        config.setLocale(locale)
        config.setLayoutDirection(locale)
        return base.createConfigurationContext(config)
    }
}
