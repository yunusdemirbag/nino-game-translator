// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui

import android.content.Context
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import com.ninotranslator.mobile.data.AppLocales
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.Settings
import com.ninotranslator.mobile.service.LiveStatus
import com.ninotranslator.mobile.ui.shell.NinoApp
import com.ninotranslator.mobile.ui.theme.NinoTheme
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/**
 * Ana pencere: kenardan kenara, dikey, tek örnek (manifestte `singleTask`). Arayüz dili çeviri dilini izler
 * (Android 12 ve altında bağlam sarılır, dil değişince pencere yeniden kurulur).
 */
class MainActivity : ComponentActivity() {
    private var languageListener: AutoCloseable? = null

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(AppLocales.wrap(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            languageListener = Nino.settings.addListener { key ->
                if (key == Settings.K.TARGET_LANGUAGE) runOnUiThread { recreate() }
            }
        }
        // §3.6: çeviri sürerken ve "ekranı açık tut" açıkken ekran kararmaz.
        lifecycleScope.launch {
            combine(LiveStatus.state, Nino.settings.watch { it.keepScreenOn }) { s, keep -> s.running && keep }
                .collect { on ->
                    if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
        }
        setContent { NinoTheme { NinoApp() } }
    }

    override fun onDestroy() {
        languageListener?.close()
        languageListener = null
        super.onDestroy()
    }
}
