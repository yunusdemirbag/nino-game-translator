// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.ui.theme.LocalAnimationsEnabled
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoDimens
import com.ninotranslator.mobile.ui.theme.NinoType

/**
 * Kurulum ekranı başlığı (§2.6), aralar 6 dp: isteğe bağlı [step] satırı (ör. "Kurulum · Adım 2/3"), 32 sp kalın
 * [title], isteğe bağlı [body] (16/23 ikincil).
 */
@Composable
fun ScreenHeader(title: String, modifier: Modifier = Modifier, step: String? = null, body: String? = null) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (step != null) Text(step, style = NinoType.StepLine)
        Text(title, style = NinoType.ScreenTitle)
        if (body != null) Text(body, style = NinoType.ScreenBody)
    }
}

/** Etiket türü (§2.7). */
enum class TagStyle { NEUTRAL, PACK }

/** Etiket (hap, §2.7): 24 dp, 6 dp köşe, 8 dp yatay iç boşluk, 13 sp 500 tek satır. */
@Composable
fun NinoTag(text: String, modifier: Modifier = Modifier, style: TagStyle = TagStyle.NEUTRAL) {
    val (bg, fg) = when (style) {
        TagStyle.NEUTRAL -> NinoColors.Surface2 to NinoColors.InkSecondary
        TagStyle.PACK -> NinoColors.PackSoft to NinoColors.PackDark
    }
    Box(modifier.height(NinoDimens.TagHeight).clip(NinoDimens.TagShape).background(bg).padding(horizontal = 8.dp),
        contentAlignment = Alignment.Center) {
        Text(text, style = NinoType.Caption, color = fg, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * Durum noktası (§2.8): 16 dp alan içinde 8 dp dolu daire. [live] iken çevresinde 2 sn'de bir büyüyüp sönen 2 dp
 * halka (animasyon kapalıysa halka yok).
 */
@Composable
fun StatusDot(color: Color, modifier: Modifier = Modifier, live: Boolean = false) {
    val animate = live && LocalAnimationsEnabled.current
    val progress = if (animate) {
        val t = rememberInfiniteTransition(label = "liveRing")
        val p by t.animateFloat(0f, 1f, infiniteRepeatable(tween(2000, easing = LinearEasing), RepeatMode.Restart), label = "p")
        p
    } else 0f
    Canvas(modifier.size(16.dp)) {
        val dot = NinoDimens.StatusDot.toPx() / 2f
        if (animate) {
            val maxR = size.minDimension / 2f - 1.dp.toPx()
            val r = maxR * (0.5f + 0.5f * progress)
            drawCircle(color.copy(alpha = 0.7f * (1f - progress)), radius = r, style = Stroke(2.dp.toPx()))
        }
        drawCircle(color, radius = dot)
    }
}

/**
 * Durum yazısı (§2.8): nokta + 4 dp + 13 sp yazı, tek satır, zeminsiz. [good] iken nokta başarı yeşili, değilse ikincil.
 */
@Composable
fun StatusText(
    text: String,
    good: Boolean,
    modifier: Modifier = Modifier,
    live: Boolean = false,
    textColor: Color = NinoColors.Ink,
    dotColor: Color = if (good) NinoColors.Success else NinoColors.InkSecondary,
) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        StatusDot(dotColor, live = live)
        Text(text, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = textColor, maxLines = 1,
            overflow = TextOverflow.Ellipsis)
    }
}
