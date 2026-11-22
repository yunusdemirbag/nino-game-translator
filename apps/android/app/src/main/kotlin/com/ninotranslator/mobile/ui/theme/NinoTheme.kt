// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.theme

import android.provider.Settings as SystemSettings
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Ölçüler (ekranlar-1 §1.3). */
object NinoDimens {
    val ScreenPadding = 20.dp
    val TileGap = 12.dp
    val TilePadding = 16.dp
    val InnerGap = 8.dp
    val TinyGap = 4.dp

    val TileRadius = 22.dp
    val ControlRadius = 16.dp
    val BoxRadius = 8.dp
    val TagRadius = 6.dp
    val StageRadius = 28.dp

    val IconButton = 44.dp
    val RowMinHeight = 52.dp
    val TagHeight = 24.dp
    val StatusDot = 8.dp
    val ButtonHeight = 58.dp
    val GhostButtonHeight = 44.dp
    val TopBarHeight = 44.dp
    val AppIcon = 36.dp

    val TileShape = RoundedCornerShape(TileRadius)
    val ControlShape = RoundedCornerShape(ControlRadius)
    val BoxShape = RoundedCornerShape(BoxRadius)
    val TagShape = RoundedCornerShape(TagRadius)
    val StageShape = RoundedCornerShape(StageRadius)

    /** İçerik sütununun en fazla genişliği: sınırsız (eski uygulama tablette de tam genişlik kullanır). */
    val MaxContentWidth = Dp.Infinity
}

/** Sistemde "animasyonları kapat" açık mı (animasyon süresi ölçeği 0, §1.4). */
val LocalAnimationsEnabled = staticCompositionLocalOf { true }

/** Nino teması: yalnız açık renk takımı, sistem yazı tipi. */
@Composable
fun NinoTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val animations = remember {
        runCatching {
            SystemSettings.Global.getFloat(context.contentResolver, SystemSettings.Global.ANIMATOR_DURATION_SCALE, 1f)
        }.getOrDefault(1f) != 0f
    }
    val scheme = lightColorScheme(
        primary = NinoColors.Accent,
        onPrimary = NinoColors.Raised,
        secondary = NinoColors.AccentText,
        background = NinoColors.Background,
        onBackground = NinoColors.Ink,
        surface = NinoColors.Raised,
        onSurface = NinoColors.Ink,
        surfaceVariant = NinoColors.Surface2,
        onSurfaceVariant = NinoColors.InkSecondary,
        surfaceContainer = NinoColors.Surface2,
        surfaceContainerHigh = NinoColors.Surface2,
        surfaceContainerHighest = NinoColors.Surface2,
        outline = NinoColors.BorderStrong,
        outlineVariant = NinoColors.BorderStrong,
        error = NinoColors.Danger,
    )
    val typography = Typography(
        bodyLarge = NinoType.Body, bodyMedium = NinoType.Body, titleMedium = NinoType.Headline,
        titleLarge = NinoType.Title, labelLarge = NinoType.Headline, labelMedium = NinoType.Caption,
    )
    CompositionLocalProvider(LocalAnimationsEnabled provides animations) {
        MaterialTheme(colorScheme = scheme, typography = typography, content = content)
    }
}

/**
 * Ekran zemini (§1.1): sol üstten sağ alta açık degrade, sol üstte mavi, sağ altta lacivert yumuşak ışık.
 */
fun Modifier.ninoScreenBackground(): Modifier = this
    .background(Brush.linearGradient(listOf(NinoColors.ScreenTop, NinoColors.ScreenBottom)))
    .drawBehind {
        val w = size.width
        val h = size.height
        if (w <= 0f || h <= 0f) return@drawBehind
        drawRect(Brush.radialGradient(
            listOf(NinoColors.Accent.copy(alpha = 0.22f), NinoColors.Accent.copy(alpha = 0f)),
            center = Offset(w * 0.10f, h * 0.08f), radius = w * 0.9f,
        ))
        drawRect(Brush.radialGradient(
            listOf(NinoColors.PackDark.copy(alpha = 0.16f), NinoColors.PackDark.copy(alpha = 0f)),
            center = Offset(w * 0.95f, h * 0.95f), radius = w,
        ))
    }

/** Ekran zeminiyle dolu kutu. */
@Composable
fun NinoScreenBackground(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.ninoScreenBackground()) { content() }
}

/**
 * Basılıyken %97'ye küçülme (§1.4). Aynı [interaction] tıklanabilir öğeye de verilmeli.
 */
fun Modifier.pressScale(interaction: MutableInteractionSource, enabled: Boolean = true): Modifier = composed {
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed && enabled) 0.97f else 1f, tween(120), label = "press")
    graphicsLayer { scaleX = scale; scaleY = scale }
}
