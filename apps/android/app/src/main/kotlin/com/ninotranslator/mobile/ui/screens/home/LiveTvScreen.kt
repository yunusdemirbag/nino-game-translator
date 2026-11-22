// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.home

import android.graphics.Typeface
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextGeometricTransform
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.AppLanguage
import com.ninotranslator.mobile.ui.theme.LocalAnimationsEnabled
import com.ninotranslator.mobile.ui.theme.letterSpacingFor
import kotlinx.coroutines.delay
import java.text.NumberFormat
import kotlin.math.pow

/**
 * Canlı TV ekranı (§7.4.4): zemin (öncelikli havuz oyununda gün batımı), sol üstte CANLI, sağ üstte isteğe bağlı
 * toplam indirme, altta bağlantı durumu ya da çeviri satırı. Hep soldan sağa.
 */
@Composable
fun LiveTvScreen(
    model: HomeModel,
    modifier: Modifier = Modifier,
    counter: Int? = null,
    countUp: Boolean = false,
) {
    val live = model.live
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        Box(modifier.fillMaxSize().background(liveBackground(live.poolFirstGame))) {
            if (live.poolFirstGame) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.28f)))
            Box(Modifier.fillMaxSize().padding(18.dp)) {
                Row(
                    Modifier.align(Alignment.TopStart).clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.4f))
                        .padding(horizontal = 10.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Canvas(Modifier.size(8.dp)) { drawCircle(Color(0xFFE30A17)) }
                    Spacer(Modifier.width(6.dp))
                    Text(stringResource(R.string.nino_live), fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.White,
                        letterSpacing = letterSpacingFor(model.language, 1.2f))
                }
                if (counter != null && counter > 0) {
                    DownloadCounter(counter, countUp, model.language, Modifier.align(Alignment.TopEnd))
                }
                Box(Modifier.align(Alignment.BottomCenter).padding(bottom = 8.dp)) {
                    val shown = live.currentLine ?: live.lastLine
                    when {
                        !live.streaming -> Text(live.phaseText ?: stringResource(R.string.nino_connecting_ps5), fontSize = 15.sp,
                            fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.7f), textAlign = TextAlign.Center)
                        shown.isNullOrBlank() -> Text(stringResource(R.string.nino_waiting_next), fontSize = 15.sp,
                            fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.55f), textAlign = TextAlign.Center)
                        else -> Text(
                            shown,
                            fontSize = when { shown.length <= 60 -> 24.sp; shown.length <= 90 -> 20.sp; else -> 17.sp },
                            fontWeight = FontWeight.SemiBold, color = Color.White, textAlign = TextAlign.Center, maxLines = 3,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(Color.Black.copy(alpha = 0.72f))
                                .padding(horizontal = 16.dp, vertical = 8.dp),
                        )
                    }
                }
            }
        }
    }
}

private fun liveBackground(poolFirst: Boolean): Brush = if (poolFirst) {
    Brush.verticalGradient(0f to Color(0xFF1A1457), 0.40f to Color(0xFF75299E), 0.74f to Color(0xFFED4A99), 1f to Color(0xFFFF8C7A))
} else {
    Brush.linearGradient(listOf(Color(0xFF171F3D), Color(0xFF26172E)))
}

private val CondensedBlack = FontFamily(Typeface.create("sans-serif-condensed", Typeface.BOLD))

/**
 * Toplam indirme göstergesi (§7.4.5): sağa yaslı iki satır, dar kalın yazı, sağa eğik, siyah çerçeveli. [countUp]
 * iken 1, 2, 3 diye başlayıp hızlanarak toplama çıkar, sonda arka kenarından büyüyüp yerine döner.
 */
@Composable
fun DownloadCounter(total: Int, countUp: Boolean, language: String, modifier: Modifier = Modifier) {
    val animations = LocalAnimationsEnabled.current
    val target by rememberUpdatedState(total)
    var shown by remember { mutableIntStateOf(if (countUp && animations && total > 3) 0 else total) }
    val pop = remember { Animatable(1f) }
    val glow = remember { Animatable(0f) }
    val arabic = language == "ar"
    val rtl = AppLanguage.isRtl(language)

    LaunchedEffect(countUp, animations) {
        if (!countUp || !animations || target <= 3) { shown = target; return@LaunchedEffect }
        for (i in 1..3) { shown = i; delay(280) }
        val start = System.nanoTime()
        while (true) {
            val p = ((System.nanoTime() - start) / 1_000_000f / 1_550f).coerceAtMost(1f)
            shown = 3 + ((target - 3) * p.toDouble().pow(2.6)).toInt()
            if (p >= 1f) break
            delay(16)
        }
        shown = target
        glow.snapTo(0.95f)
        pop.animateTo(1.32f, spring(dampingRatio = 0.45f, stiffness = Spring.StiffnessHigh))
        delay(260)
        glow.snapTo(0f)
        pop.animateTo(1f, spring(dampingRatio = 0.6f, stiffness = Spring.StiffnessLow))
    }
    LaunchedEffect(total) { if (!countUp || !animations) shown = total }

    val label = stringResource(R.string.nino_total_downloads)
    val number = remember(shown) { NumberFormat.getIntegerInstance().format(shown) }
    val skew = if (arabic) null else TextGeometricTransform(skewX = -0.12f)
    Column(
        modifier.clearAndSetSemantics { contentDescription = "$label ${NumberFormat.getIntegerInstance().format(total)}" },
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(1.dp),
    ) {
        OutlinedText(label, 11.sp, Color.White, 1f, skew, letterSpacingFor(language, 0.8f))
        Box(Modifier.graphicsLayer {
            scaleX = pop.value; scaleY = pop.value
            transformOrigin = TransformOrigin(if (rtl) 0f else 1f, 0.5f)
        }) {
            OutlinedText(number, 27.sp, Color(0xFF7BE87B), 1.5f, skew, 0.sp,
                glow = if (glow.value > 0f) Color(0xFF7BE87B).copy(alpha = glow.value) else null)
        }
    }
}

/** Çerçeveli yazı: derinlik gölgesi + siyah çerçeve + dolgu. */
@Composable
private fun OutlinedText(
    text: String,
    size: TextUnit,
    fill: Color,
    strokeDp: Float,
    skew: TextGeometricTransform?,
    spacing: TextUnit,
    glow: Color? = null,
) {
    val d = LocalDensity.current.density
    val base = TextStyle(fontFamily = CondensedBlack, fontWeight = FontWeight.Black, fontSize = size, letterSpacing = spacing,
        textGeometricTransform = skew)
    Box {
        Text(text, style = base.copy(color = Color.Black.copy(alpha = 0.9f)), modifier = Modifier.offset(y = (strokeDp + 1f).dp))
        Text(text, style = base.copy(color = Color.Black, drawStyle = Stroke(width = strokeDp * 2f * d)))
        Text(text, style = base.copy(color = fill, shadow = glow?.let { Shadow(it, blurRadius = 14f * d) }))
    }
}
