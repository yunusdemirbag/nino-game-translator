// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.shell

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.SubtitleTarget
import com.ninotranslator.mobile.data.VideoSource
import com.ninotranslator.mobile.service.LiveStatus
import com.ninotranslator.mobile.service.TranslationControl
import com.ninotranslator.mobile.ui.PhoneSubtitleActivity
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * Süreç boyunca bir kez olan şeyler. Etkinlik yeniden kurulsa (dil değişimi, döndürme) yeniden oynamazlar.
 */
object AppSession {
    /** Açılış animasyonu bu süreçte oynadı. */
    @Volatile var splashDone = false
    /** Salon'daki fiş gösterisi bu süreçte oynadı. */
    @Volatile var plugShowDone = false
    /** Bu süreçte ✕ ile gizlenen uygulama sürümü (kalıcı değil, veri-ve-ayarlar §1.4). */
    val dismissedAppUpdate = MutableStateFlow<String?>(null)
    /** Tam ekran giriş sayfası (Sony, Samsung) açıkken yüzen robot gizlenir. */
    val robotSuppressed = MutableStateFlow(false)
    /** Ana ekranda gösterilecek kamera izni uyarısı. */
    val cameraPermissionMissing = MutableStateFlow(false)
}

/** Çeviriyi başlatma ve durdurma işleri (ekranlar-1 §3.5). */
class TranslationStarter(private val context: Context, private val requestCamera: () -> Unit, private val requestNotify: () -> Unit) {

    /** Başlat: gerekirse kamera izni, bildirim izni; altyazı telefondaysa tam ekran pencere açılır. */
    fun start() {
        val settings = Nino.settings
        if (settings.videoSource == VideoSource.CAPTURE_CARD && !hasCamera(context)) {
            requestCamera()
            return
        }
        launch()
    }

    /** Kamera izni cevabı. */
    fun onCameraResult(granted: Boolean) {
        if (granted) {
            AppSession.cameraPermissionMissing.value = false
            launch()
        } else {
            AppSession.cameraPermissionMissing.value = true
        }
    }

    /** Örnek (demo) oturum: konsol gerekmez. */
    fun startDemo() {
        askNotifications()
        TranslationControl.startDemo(context)
        if (Nino.settings.target == SubtitleTarget.PHONE) PhoneSubtitleActivity.open(context)
    }

    fun stop() = TranslationControl.stop(context)

    fun toggle() = if (LiveStatus.state.value.running) stop() else start()

    private fun launch() {
        askNotifications()
        TranslationControl.start(context)
        if (Nino.settings.target == SubtitleTarget.PHONE) PhoneSubtitleActivity.open(context)
    }

    private fun askNotifications() {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestNotify()
        }
    }

    companion object {
        fun hasCamera(context: Context) =
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    }
}

/** Ekranda kullanılacak başlatıcı (izin isteyicileriyle). */
@Composable
fun rememberTranslationStarter(): TranslationStarter {
    val context = LocalContext.current
    var holder: TranslationStarter? = null
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { holder?.onCameraResult(it) }
    val notify = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    return remember(context) {
        TranslationStarter(context, { camera.launch(Manifest.permission.CAMERA) }, {
            if (Build.VERSION.SDK_INT >= 33) notify.launch(Manifest.permission.POST_NOTIFICATIONS)
        })
    }.also { holder = it }
}
