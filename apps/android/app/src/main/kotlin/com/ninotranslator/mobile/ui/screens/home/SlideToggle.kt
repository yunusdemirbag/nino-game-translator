// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.home

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.ui.components.TargetLanguages
import com.ninotranslator.mobile.ui.theme.LocalAnimationsEnabled
import com.ninotranslator.mobile.ui.theme.NinoColors
import kotlinx.coroutines.launch
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/** Kaydırma çubuğunun dil rengi (üst → alt, §7.3.2). */
fun languageTrackColors(code: String): Pair<Color, Color> = when (code) {
    "ar", "ur", "bn" -> Color(0xFF0B8A4A) to Color(0xFF056236)
    "hi", "nl" -> Color(0xFFF08A1C) to Color(0xFFB85F00)
    "th", "ms", "tl" -> Color(0xFF2D4FB3) to Color(0xFF1A3380)
    else -> NinoColors.FlagRed to NinoColors.FlagRedDark
}

/**
 * Kaydırma çubuğu (§7.3.2): 68 dp hap, 56 dp tutamaç. Bırakınca: Bağlı Değil'de yarıdan öte → [onLocked]; kapalıyken
 * %85'ten öte → [onStart]; açıkken %15'ten beri → [onStop]. Tutamaca dokunmak da aynı işi yapar.
 */
@Composable
fun SlideToggle(
    model: HomeModel,
    onLocked: () -> Unit,
    onStart: () -> Unit,
    onStop: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val on = model.status == HomeStatus.CONNECTING || model.status == HomeStatus.LIVE
    val progress = remember { Animatable(if (on) 1f else 0f) }
    val scope = rememberCoroutineScope()
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val density = LocalDensity.current
    val animations = LocalAnimationsEnabled.current
    val status by rememberUpdatedState(model.status)

    LaunchedEffect(on) { progress.animateTo(if (on) 1f else 0f, spring(dampingRatio = 0.82f, stiffness = 320f)) }

    val label = stringResource(when (model.status) {
        HomeStatus.NOT_PAIRED -> R.string.slide_pair
        HomeStatus.READY -> R.string.slide_start
        else -> R.string.slide_stop
    })
    fun act() = when (status) {
        HomeStatus.NOT_PAIRED -> onLocked()
        HomeStatus.READY -> onStart()
        else -> onStop()
    }
    fun release() {
        val p = progress.value
        when {
            status == HomeStatus.NOT_PAIRED -> if (p > 0.5f) onLocked()
            status == HomeStatus.READY -> if (p > 0.85f) onStart()
            else -> if (p < 0.15f) onStop()
        }
        scope.launch {
            val back = if (status == HomeStatus.CONNECTING || status == HomeStatus.LIVE) 1f else 0f
            progress.animateTo(back, spring(dampingRatio = 0.8f, stiffness = 320f))
        }
    }

    val (top, bottom) = languageTrackColors(model.language)
    val shimmer = if (animations) {
        val t = rememberInfiniteTransition(label = "shimmer")
        val v by t.animateFloat(0f, 1f, infiniteRepeatable(tween(2200, easing = LinearEasing), RepeatMode.Restart), label = "s")
        v
    } else -1f
    val pill = RoundedCornerShape(50)

    BoxWithConstraints(
        modifier.fillMaxWidth().height(68.dp)
            .semantics { contentDescription = label; role = Role.Button; onClick { act(); true } },
    ) {
        val width = constraints.maxWidth.toFloat()
        val handlePx = with(density) { 56.dp.toPx() }
        val marginPx = with(density) { 6.dp.toPx() }
        val travel = (width - handlePx - marginPx * 2).coerceAtLeast(1f)
        val p = progress.value.coerceIn(0f, 1f)

        // İz
        Box(
            Modifier.fillMaxSize()
                .shadow((16 * p).dp, pill, ambientColor = top.copy(alpha = 0.6f), spotColor = top.copy(alpha = 0.6f))
                .clip(pill)
                .background(NinoColors.Ink)
                .drawBehind {
                    drawRect(Brush.verticalGradient(listOf(top, bottom)), alpha = p)
                    drawRect(Color.White.copy(alpha = 0.22f * p), size = Size(size.width, size.height / 2f))
                }
                .border(1.dp, Color.White.copy(alpha = 0.10f), pill),
        )
        // Yazı (tutamaçtan sonraki alanda, ışıltılı)
        val textAlpha = if (on) 1f else 1f - p
        val textStart = with(density) { (handlePx + marginPx * 2).toDp() }
        Box(
            Modifier.fillMaxSize().padding(start = if (rtl) 12.dp else textStart, end = if (rtl) textStart else 12.dp)
                .graphicsLayer { alpha = textAlpha },
            contentAlignment = Alignment.Center,
        ) {
            val base = Color.White.copy(alpha = 0.55f)
            val brush = if (shimmer < 0f) Brush.linearGradient(listOf(base, base)) else {
                val x = (if (rtl) 1f - shimmer else shimmer) * 2f - 0.5f
                Brush.horizontalGradient(
                    0f to base, (x - 0.15f).coerceIn(0f, 1f) to base, x.coerceIn(0f, 1f) to Color.White,
                    (x + 0.15f).coerceIn(0f, 1f) to base, 1f to base,
                )
            }
            Text(label, style = TextStyle(brush = brush, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center),
                maxLines = 1)
        }
        // Tutamaç
        val x = marginPx + travel * p
        val offsetX = if (rtl) width - handlePx - x else x
        Box(
            Modifier.offset { IntOffset(offsetX.roundToInt(), with(density) { 6.dp.roundToPx() }) }
                .size(56.dp)
                .shadow(10.dp, CircleShape)
                .clip(CircleShape)
                .background(Color.White)
                .pointerInput(rtl, travel) {
                    detectHorizontalDragGestures(
                        onDragEnd = { release() },
                        onDragCancel = { release() },
                    ) { change, dx ->
                        change.consume()
                        val delta = (if (rtl) -dx else dx) / travel
                        scope.launch { progress.snapTo((progress.value + delta).coerceIn(0f, 1f)) }
                    }
                }
                .clickable(role = Role.Button) { act() },
            contentAlignment = Alignment.Center,
        ) {
            if (model.status == HomeStatus.CONNECTING) {
                Spinner(Modifier.size(22.dp).graphicsLayer { alpha = 1f - p * 0.0f })
            } else {
                Icon(Icons.AutoMirrored.Filled.ArrowForward, null, Modifier.size(24.dp).graphicsLayer { alpha = 1f - p },
                    tint = NinoColors.Ink)
            }
            if (p > 0.01f && model.status != HomeStatus.CONNECTING) {
                FlagGlobe(model.language, Modifier.fillMaxSize().graphicsLayer { alpha = p })
            }
        }
    }
}

/** Dönen halka (Bağlanıyor). */
@Composable
private fun Spinner(modifier: Modifier) {
    val animations = LocalAnimationsEnabled.current
    val angle = if (animations) {
        val t = rememberInfiniteTransition(label = "spin")
        val a by t.animateFloat(0f, 360f, infiniteRepeatable(tween(900, easing = LinearEasing)), label = "a")
        a
    } else 0f
    Canvas(modifier) {
        drawArc(NinoColors.Accent, angle, 270f, false, style = Stroke(2.5.dp.toPx()))
    }
}

/** Camlı bayrak küresi: Türkçede ay yıldız, diğer dillerde bayrak emojisi; üstünde kenar ışığı ve parlama. */
@Composable
fun FlagGlobe(language: String, modifier: Modifier = Modifier) {
    Box(modifier.clip(CircleShape), contentAlignment = Alignment.Center) {
        if (language == "tr") {
            Box(Modifier.fillMaxSize().background(NinoColors.FlagRed), contentAlignment = Alignment.Center) {
                Canvas(Modifier.size(34.dp)) { drawCrescentStar(NinoColors.FlagRed) }
            }
        } else {
            BoxWithConstraints(Modifier.fillMaxSize().background(Color.White), contentAlignment = Alignment.Center) {
                val sizeSp = with(LocalDensity.current) { (maxWidth * 1.15f).toSp() }
                Text(TargetLanguages.of(language).flag, fontSize = sizeSp, maxLines = 1)
            }
        }
        Canvas(Modifier.fillMaxSize()) {
            drawCircle(Brush.linearGradient(listOf(Color.White.copy(alpha = 0.9f), Color.White.copy(alpha = 0.1f), Color.White.copy(alpha = 0.6f))),
                radius = size.minDimension / 2f - 1.dp.toPx(), style = Stroke(2.dp.toPx()))
            drawOval(Color.White.copy(alpha = 0.6f), topLeft = Offset(size.width * 0.2f, size.height * 0.1f),
                size = Size(size.width * 0.35f, size.height * 0.2f))
        }
    }
}

/** Ay yıldız (§7.3.2 "Ay yıldız çizimi"), kare alanın kenarı s. */
fun DrawScope.drawCrescentStar(background: Color) {
    val s = size.minDimension
    val r = 0.42f * s
    val c = Offset(0.42f * s, 0.5f * s)
    drawCircle(Color.White, r, c)
    drawCircle(background, r * 0.8f, Offset(c.x + 0.32f * r, c.y))
    val center = Offset(0.8f * s, 0.5f * s)
    val outer = 0.17f * s
    val inner = outer * 0.382f
    val path = Path()
    for (i in 0 until 10) {
        // İlk uç sola (aya) bakar.
        val angle = Math.PI + i * Math.PI / 5
        val rad = if (i % 2 == 0) outer else inner
        val px = center.x + (rad * cos(angle)).toFloat()
        val py = center.y + (rad * sin(angle)).toFloat()
        if (i == 0) path.moveTo(px, py) else path.lineTo(px, py)
    }
    path.close()
    drawPath(path, Color.White)
}
