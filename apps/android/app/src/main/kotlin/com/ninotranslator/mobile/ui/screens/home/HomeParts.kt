// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.home

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.OpenInFull
import androidx.compose.material.icons.filled.ScreenRotation
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.ConsoleKind
import com.ninotranslator.mobile.data.SubtitleTarget
import com.ninotranslator.mobile.ui.components.IconTextButton
import com.ninotranslator.mobile.ui.components.languageDisplayName
import com.ninotranslator.mobile.ui.theme.LocalAnimationsEnabled
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoType

/** Ortak başlık (§7.1): durum satırı ve büyük başlık. */
@Composable
fun HomeHeader(model: HomeModel, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(top = 8.dp)) {
        val statusText = when (model.status) {
            HomeStatus.NOT_PAIRED -> stringResource(R.string.home_not_paired)
            HomeStatus.READY -> stringResource(R.string.home_ready)
            HomeStatus.CONNECTING -> stringResource(R.string.home_connecting)
            HomeStatus.LIVE -> if (model.target == SubtitleTarget.TV) stringResource(R.string.home_status_tv)
            else stringResource(R.string.home_live)
        }
        val name = if (model.live.demo) stringResource(R.string.demo_name) else model.sourceName
        val line = if (model.status == HomeStatus.NOT_PAIRED || name.isNullOrBlank()) statusText else "$name  ·  $statusText"
        val pulse = (model.status == HomeStatus.CONNECTING || model.status == HomeStatus.LIVE) && LocalAnimationsEnabled.current
        val dotAlpha = if (pulse) {
            val t = rememberInfiniteTransition(label = "dot")
            val a by t.animateFloat(1f, 0.3f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "a")
            a
        } else 1f
        val dot = model.dotColor()
        Row(verticalAlignment = Alignment.CenterVertically) {
            Canvas(Modifier.size(8.dp).graphicsLayer { alpha = dotAlpha }) { drawCircle(dot) }
            Spacer(Modifier.width(8.dp))
            Text(line, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = NinoColors.InkSecondary, maxLines = 1,
                overflow = TextOverflow.Ellipsis)
        }
        Spacer(Modifier.height(6.dp))
        val title = when (model.status) {
            HomeStatus.NOT_PAIRED -> stringResource(if (model.consoleKind == ConsoleKind.XBOX) R.string.xbox_home_title_pair else R.string.home_title_pair)
            HomeStatus.LIVE -> stringResource(R.string.home_title_live)
            else -> stringResource(R.string.home_title_ready, languageDisplayName(model.language))
        }
        AnimatedContent(title, transitionSpec = { fadeIn(tween(300)) togetherWith fadeOut(tween(200)) }, label = "title") { t ->
            Text(t, style = NinoType.HomeTitle)
        }
    }
}

/** Kısa yol kutusu (§7.4.1). */
@Composable
private fun Shortcut(icon: ImageVector, name: String, value: String, onClick: () -> Unit, modifier: Modifier) {
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier.clip(shape).background(Color.White.copy(alpha = 0.72f)).border(1.dp, Color.White, shape)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 14.dp),
    ) {
        Icon(icon, null, Modifier.size(22.dp), tint = NinoColors.Accent)
        Spacer(Modifier.height(10.dp))
        Text(name, fontSize = 12.sp, color = NinoColors.InkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(value, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = NinoColors.Ink, maxLines = 1,
            overflow = TextOverflow.Ellipsis)
    }
}

/**
 * Üç kısa yol (§7.4.1): konsol, çıkış, paketler. [onOutputPlaced] ve [onPacksPlaced] tur için konumu bildirir.
 */
@Composable
fun Shortcuts(
    model: HomeModel,
    outputValue: String,
    onConsole: () -> Unit,
    onOutput: () -> Unit,
    onPacks: () -> Unit,
    onOutputPlaced: (LayoutCoordinates) -> Unit = {},
    onPacksPlaced: (LayoutCoordinates) -> Unit = {},
) {
    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Shortcut(Icons.Filled.SportsEsports, model.consoleLabel, model.sourceName ?: stringResource(R.string.profile_not_paired),
            onConsole, Modifier.weight(1f).fillMaxHeight())
        Shortcut(if (model.target == SubtitleTarget.TV) Icons.Filled.Tv else Icons.Filled.Smartphone,
            stringResource(R.string.nino_output), outputValue, onOutput,
            Modifier.weight(1f).fillMaxHeight().onGloballyPositioned(onOutputPlaced))
        Shortcut(Icons.Filled.Inventory2, stringResource(R.string.nino_packs),
            if (model.packsEnabled) stringResource(R.string.packs_free) else "—", onPacks,
            Modifier.weight(1f).fillMaxHeight().onGloballyPositioned(onPacksPlaced))
    }
}

/** "PS5'siz Deneyin" düğmesi (§7.4.2). */
@Composable
fun DemoTryButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        IconTextButton(Icons.Filled.AutoAwesome, stringResource(R.string.demo_try), onClick)
    }
}

/** Döndürme ipucu (§7.4.3). */
@Composable
fun RotateHint(modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Filled.ScreenRotation, null, Modifier.size(18.dp), tint = NinoColors.InkSecondary)
        Spacer(Modifier.width(8.dp))
        Text(stringResource(R.string.home_rotate_hint), fontSize = 14.sp, color = NinoColors.InkSecondary)
    }
}

/** Salon'daki "Tam Ekran" hapı (§7.2 madde 5). */
@Composable
fun FullScreenPill(onClick: () -> Unit, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(50)
    Row(
        modifier.heightIn(min = 36.dp).clip(shape).background(Color.White.copy(alpha = 0.72f)).border(1.dp, Color.White, shape)
            .clickable(role = Role.Button, onClick = onClick).padding(horizontal = 12.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.OpenInFull, null, Modifier.size(16.dp), tint = NinoColors.Accent)
        Spacer(Modifier.width(6.dp))
        Text(stringResource(R.string.home_full_screen), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = NinoColors.Accent)
    }
}
