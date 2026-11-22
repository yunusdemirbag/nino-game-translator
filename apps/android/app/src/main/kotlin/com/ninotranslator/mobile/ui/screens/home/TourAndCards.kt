// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.home

import android.content.Context
import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.BuildConfig
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.tv.TvUpdateNotice
import com.ninotranslator.mobile.tv.install.TvUpdateCardPhase
import com.ninotranslator.mobile.remoteplay.NetworkAddresses
import com.ninotranslator.mobile.ui.components.StatusText
import com.ninotranslator.mobile.ui.screens.SmallNote
import com.ninotranslator.mobile.ui.screens.tvinstall.installErrorText
import com.ninotranslator.mobile.ui.screens.tvinstall.stepText
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.ui.platform.LocalContext
import com.ninotranslator.mobile.data.TvBrand
import com.ninotranslator.mobile.ui.components.GhostButton
import com.ninotranslator.mobile.ui.components.NinoIconButton
import com.ninotranslator.mobile.ui.components.NinoTile
import com.ninotranslator.mobile.ui.components.PrimaryButton
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoDimens
import com.ninotranslator.mobile.ui.theme.NinoType

/** Tur adımı: vurgulanacak öğenin kökteki yeri (bilinmiyorsa null), başlık, açıklama. */
data class TourStep(val target: Rect?, val title: String, val body: String)

/**
 * Tanıtım turu (ekranlar-1 §7.5): siyah %70 karartma, öğenin çevresinde 6 dp paylı, 16 dp köşeli delik ve 2 dp mavi
 * kenar; kart öğe aşağıdaysa (üst kenarı 900 pikselden aşağı) üstte, değilse altta.
 */
@Composable
fun TourOverlay(steps: List<TourStep>, onFinish: () -> Unit) {
    var index by remember { mutableIntStateOf(0) }
    val step = steps[index.coerceIn(0, steps.lastIndex)]
    val last = index >= steps.lastIndex
    Box(
        Modifier.fillMaxSize()
            .clickable(remember { MutableInteractionSource() }, indication = null) {}
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen },
    ) {
        Canvas(Modifier.fillMaxSize()) {
            drawRect(Color.Black.copy(alpha = 0.7f))
            step.target?.let { r ->
                val pad = 6.dp.toPx()
                val corner = CornerRadius(16.dp.toPx())
                val tl = Offset(r.left - pad, r.top - pad)
                val sz = Size(r.width + pad * 2, r.height + pad * 2)
                drawRoundRect(Color.Transparent, tl, sz, corner, blendMode = BlendMode.Clear)
                drawRoundRect(NinoColors.Accent, tl, sz, corner, style = Stroke(2.dp.toPx()))
            }
        }
        val cardOnTop = (step.target?.top ?: 0f) > 900f
        Column(
            Modifier.align(if (cardOnTop) Alignment.TopCenter else Alignment.BottomCenter)
                .safeDrawingPadding().padding(20.dp).widthIn(max = NinoDimens.MaxContentWidth).fillMaxWidth()
                .clip(NinoDimens.TileShape).background(NinoColors.Surface2).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.tour_counter, index + 1, steps.size), fontSize = 13.sp, color = NinoColors.InkSecondary)
                Spacer(Modifier.weight(1f))
                GhostButton(stringResource(R.string.skip), onFinish)
            }
            Text(step.title, style = NinoType.Headline)
            Text(step.body, style = NinoType.Body, color = NinoColors.InkSecondary)
            PrimaryButton(stringResource(if (last) R.string.tour_done else R.string.next), onClick = {
                if (last) onFinish() else index++
            })
        }
    }
}

/** Telefon uygulaması güncelleme kartı (§11.1). */
@Composable
fun AppUpdateCard(version: String, onDismiss: () -> Unit, onUpdate: () -> Unit) {
    NinoTile(selected = true) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.app_update_title, version), style = NinoType.Headline, modifier = Modifier.weight(1f))
            NinoIconButton(Icons.Filled.Close, stringResource(R.string.close), onDismiss, size = 32.dp, iconSize = 18.dp,
                tint = NinoColors.InkSecondary, background = Color.Transparent, border = null)
        }
        Text(stringResource(R.string.app_update_body), style = NinoType.Body, color = NinoColors.InkSecondary)
        PrimaryButton(stringResource(R.string.app_update_button), onUpdate)
    }
}

/**
 * TV uygulaması güncelleme kartı (§11.2). "Yeni Sürümü Kur" tek dokunuşla kurulumu başlatır; ilerleme ve sonuç kartta
 * görünür. Ek bilgi gerekince [onContinue] kurulum ekranını açar.
 */
@Composable
fun TvUpdateCard(notice: TvUpdateNotice, phase: TvUpdateCardPhase, onInstall: () -> Unit, onContinue: () -> Unit, onClose: () -> Unit) {
    val context = LocalContext.current
    val brand = when (notice.brand) { TvBrand.LG -> "LG"; TvBrand.SAMSUNG -> "Samsung"; TvBrand.ANDROID_TV -> "Android TV" }
    NinoTile(selected = true) {
        Text(stringResource(R.string.tvapp_update_title), style = NinoType.Headline)
        when (phase) {
            TvUpdateCardPhase.Offer -> {
                Text(if (notice.tvVersion != null) stringResource(R.string.tvapp_update_body, brand, notice.tvVersion, notice.phoneVersion)
                    else stringResource(R.string.tvapp_update_body_old, brand, notice.phoneVersion),
                    style = NinoType.Body, color = NinoColors.InkSecondary)
                PrimaryButton(stringResource(R.string.tvapp_update_install), onInstall)
            }
            is TvUpdateCardPhase.Running -> {
                StatusText(phase.step?.let { stepText(context, it) } ?: stringResource(R.string.tvinstall_step_connecting), good = false, live = true)
                SmallNote(stringResource(R.string.tvapp_update_keep_on))
            }
            is TvUpdateCardPhase.Done -> {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(Icons.Filled.CheckCircle, null, Modifier.size(24.dp), tint = NinoColors.Success)
                    Text(stringResource(if (phase.alreadyInstalled) R.string.tvinstall_up_to_date else R.string.tvinstall_done, phase.version),
                        Modifier.weight(1f), style = NinoType.Body)
                }
                GhostButton(stringResource(R.string.close), onClose)
            }
            is TvUpdateCardPhase.Failed -> {
                val ip = remember { NetworkAddresses.pickLocalAddress(NetworkAddresses.systemInterfaces()) ?: "?" }
                if (phase.needsScreen) SmallNote(stringResource(R.string.tvapp_update_needs_step))
                Text(installErrorText(context, phase.error, notice.brand, ip), style = NinoType.Body, color = NinoColors.InkSecondary)
                if (phase.needsScreen) {
                    PrimaryButton(stringResource(R.string.tvapp_update_continue), onContinue)
                } else {
                    PrimaryButton(stringResource(R.string.tvinstall_retry), onInstall)
                    GhostButton(stringResource(R.string.tvapp_update_continue), onContinue)
                }
            }
        }
    }
}

/** Uygulama güncellemesi kuralları (§11.1): yalnız mağaza dışı kopyada ve bilinen sürüm daha yeniyse. */
object AppUpdates {
    fun installedFromStore(context: Context): Boolean = runCatching {
        val installer = if (Build.VERSION.SDK_INT >= 30) {
            context.packageManager.getInstallSourceInfo(context.packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION") context.packageManager.getInstallerPackageName(context.packageName)
        }
        installer == "com.android.vending"
    }.getOrDefault(false)

    /** Gösterilecek sürüm ya da null. */
    fun offer(context: Context, latest: String?, dismissed: String?): String? {
        if (latest.isNullOrBlank() || latest == dismissed) return null
        if (installedFromStore(context)) return null
        return latest.takeIf { isNewer(it, BuildConfig.VERSION_NAME) }
    }

    /** "0.2.6" > "0.1.0-beta.37"; sayısal parçalar sırayla karşılaştırılır, ön sürüm eki aynı çekirdekte küçük sayılır. */
    fun isNewer(candidate: String, current: String): Boolean {
        fun core(v: String) = v.removePrefix("v").substringBefore('-').split('.').map { it.toIntOrNull() ?: 0 }
        val a = core(candidate); val b = core(current)
        for (i in 0 until maxOf(a.size, b.size)) {
            val x = a.getOrElse(i) { 0 }; val y = b.getOrElse(i) { 0 }
            if (x != y) return x > y
        }
        return !candidate.contains('-') && current.contains('-')
    }
}

