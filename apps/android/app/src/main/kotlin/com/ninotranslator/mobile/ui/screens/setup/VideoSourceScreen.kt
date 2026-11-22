// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.setup

import android.Manifest
import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Gamepad
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.Usb
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.VideoSource
import com.ninotranslator.mobile.ui.components.GlassRow
import com.ninotranslator.mobile.ui.components.NinoScreen
import com.ninotranslator.mobile.ui.components.NinoTopBar
import com.ninotranslator.mobile.ui.components.NoteTile
import com.ninotranslator.mobile.ui.components.PrimaryButton
import com.ninotranslator.mobile.ui.components.ScreenHeader
import com.ninotranslator.mobile.ui.components.SelectableGlassBox
import com.ninotranslator.mobile.ui.components.StageCard
import com.ninotranslator.mobile.ui.navigation.NinoNavigator
import com.ninotranslator.mobile.ui.shell.AppSession
import com.ninotranslator.mobile.ui.shell.TranslationStarter
import com.ninotranslator.mobile.ui.theme.NinoColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/** Takılı yakalama kartı (harici kamera). [resolution] "1920×1080" gibi ya da null. */
data class CaptureCardInfo(val resolution: String?)

/** Harici kamera olarak görünen yakalama kartını arar (izin gerekmez; yalnız özellikler okunur). */
object CaptureCards {
    fun find(context: Context): CaptureCardInfo? = runCatching {
        val cm = context.getSystemService(CameraManager::class.java) ?: return null
        for (id in cm.cameraIdList) {
            val ch = cm.getCameraCharacteristics(id)
            if (ch.get(CameraCharacteristics.LENS_FACING) != CameraCharacteristics.LENS_FACING_EXTERNAL) continue
            val map = ch.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val size = map?.getOutputSizes(ImageFormat.YUV_420_888)?.maxByOrNull { it.width.toLong() * it.height }
            return CaptureCardInfo(size?.let { "${it.width}×${it.height}" })
        }
        null
    }.getOrNull()
}

/** Görüntü kaynağı (ekranlar-1 §6.4): PS5, Xbox ya da yakalama kartı. */
@Composable
fun VideoSourceScreen(nav: NinoNavigator) {
    val settings = Nino.settings
    val context = LocalContext.current
    var source by rememberSaveable { mutableStateOf(settings.videoSource) }
    var card by remember { mutableStateOf<CaptureCardInfo?>(null) }
    var searched by remember { mutableStateOf(false) }

    // Takılı kart ekran açıkken 1,5 sn'de bir yeniden aranır.
    LaunchedEffect(Unit) {
        while (true) {
            card = withContext(Dispatchers.IO) { CaptureCards.find(context) }
            searched = true
            delay(1_500)
        }
    }

    fun save() {
        settings.videoSource = source
        if (source != VideoSource.CAPTURE_CARD || TranslationStarter.hasCamera(context)) {
            AppSession.cameraPermissionMissing.value = false
        }
        nav.videoSourceSaved()
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { save() }

    val isCard = source == VideoSource.CAPTURE_CARD
    NinoScreen(
        topBar = { NinoTopBar(onBack = if (nav.canGoBack()) nav::back else null) },
        bottom = {
            PrimaryButton(stringResource(R.string.save), onClick = {
                if (isCard && !TranslationStarter.hasCamera(context)) permission.launch(Manifest.permission.CAMERA) else save()
            })
        },
    ) {
        ScreenHeader(stringResource(R.string.settings_video_source), body = stringResource(R.string.source_body))
        StageCard(height = if (isCard) 316.dp else 250.dp) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SelectableGlassBox(Icons.Filled.SportsEsports, "PS5", stringResource(R.string.source_ps5_detail),
                    source == VideoSource.REMOTE_PLAY, { source = VideoSource.REMOTE_PLAY }, Modifier.weight(1f))
                SelectableGlassBox(Icons.Filled.Gamepad, "Xbox", stringResource(R.string.source_xbox_detail),
                    source == VideoSource.XBOX, { source = VideoSource.XBOX }, Modifier.weight(1f))
                SelectableGlassBox(Icons.Filled.Usb, stringResource(R.string.capture_card), stringResource(R.string.source_card_detail),
                    isCard, { source = VideoSource.CAPTURE_CARD }, Modifier.weight(1f))
            }
            if (isCard) {
                val c = card
                if (c != null) {
                    GlassRow(stringResource(R.string.capture_found_title), stringResource(R.string.capture_found_detail, c.resolution ?: "—"),
                        badge = "USB", tag = stringResource(R.string.capture_ready))
                } else {
                    GlassRow(stringResource(R.string.capture_missing_title), stringResource(R.string.capture_missing_detail), badge = "USB")
                }
            }
        }
        Text(
            stringResource(when (source) {
                VideoSource.REMOTE_PLAY -> R.string.source_ps5_body
                VideoSource.XBOX -> R.string.source_xbox_body
                VideoSource.CAPTURE_CARD -> R.string.source_card_body
            }),
            style = TextStyle(fontSize = 15.sp, lineHeight = 21.sp, color = NinoColors.InkSecondary),
        )
        if (isCard) {
            if (searched && card == null) NoteTile(stringResource(R.string.capture_not_found))
            Text(stringResource(R.string.source_hdcp), style = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, color = NinoColors.InkSecondary))
        }
    }
}
