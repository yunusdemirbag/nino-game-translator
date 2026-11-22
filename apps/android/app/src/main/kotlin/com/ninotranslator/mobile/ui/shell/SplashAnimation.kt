// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.shell

import android.os.Build
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.ui.theme.LocalAnimationsEnabled
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.ninoScreenBackground
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Açılış animasyonu (ekranlar-1 §4): ışık, dönen halka, logo, bayrak parıltısı, "Nino" ve dil satırı. Yaklaşık 3,3 sn;
 * animasyon kapalıysa hemen tam görünür ve 900 ms sonra biter. [onFinished] bitince bir kez çağrılır.
 * [background] false ise zemin çizilmez (Salon TV'sinin içinde kullanılırken).
 */
@Composable
fun SplashAnimation(
    languageName: String,
    onFinished: () -> Unit,
    modifier: Modifier = Modifier,
    background: Boolean = true,
) {
    val animations = LocalAnimationsEnabled.current
    val finish by rememberUpdatedState(onFinished)
    val logo = remember { Animatable(if (animations) 0f else 1f) }
    val text = remember { Animatable(if (animations) 0f else 1f) }
    val flag = remember { Animatable(0f) }
    val exit = remember { Animatable(0f) }

    LaunchedEffect(Unit) {
        if (!animations) {
            delay(900)
            finish()
            return@LaunchedEffect
        }
        coroutineScope {
            launch { logo.animateTo(1f, spring(dampingRatio = 0.62f, stiffness = 120f)) }
            delay(650)
            launch { text.animateTo(1f, tween(600, easing = FastOutSlowInEasing)) }
            repeat(2) {
                flag.animateTo(1f, tween(500))
                flag.animateTo(0.15f, tween(500))
            }
        }
        delay(250)
        exit.animateTo(1f, tween(420))
        finish()
    }

    val ring = if (animations) {
        val t = rememberInfiniteTransition(label = "ring")
        val a by t.animateFloat(0f, 360f, infiniteRepeatable(tween(2400, easing = LinearEasing), RepeatMode.Restart), label = "a")
        a
    } else 0f

    Box(
        modifier.fillMaxSize().let { if (background) it.ninoScreenBackground() else it },
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.graphicsLayer {
                alpha = 1f - exit.value
                val s = 1f + 0.06f * exit.value
                scaleX = s; scaleY = s
            },
        ) {
            val p = logo.value
            Box(
                Modifier.size(300.dp).graphicsLayer {
                    val s = 0.72f + 0.28f * p
                    scaleX = s; scaleY = s
                    alpha = p.coerceIn(0f, 1f)
                },
                contentAlignment = Alignment.Center,
            ) {
                Canvas(Modifier.size(300.dp)) {
                    drawCircle(Brush.radialGradient(listOf(NinoColors.Accent.copy(alpha = 0.35f), Color.Transparent)))
                }
                Canvas(Modifier.size(270.dp).rotate(ring)) {
                    val stroke = 3.dp.toPx()
                    drawCircle(
                        Brush.sweepGradient(listOf(Color.Transparent, NinoColors.Accent, NinoColors.AccentLight,
                            Color.Transparent, Color.Transparent)),
                        radius = size.minDimension / 2f - stroke / 2f, style = Stroke(stroke),
                    )
                }
                val blurDp = if (p >= 0.95f) 0f else 14f * (1f - p).coerceIn(0f, 1f)
                Image(
                    painterResource(R.drawable.nino_logo), null,
                    Modifier.size(230.dp).let { if (blurDp > 0.1f && Build.VERSION.SDK_INT >= 31) it.blur(blurDp.dp) else it },
                )
                Canvas(Modifier.offset(y = (-62).dp).size(120.dp, 70.dp).graphicsLayer { alpha = flag.value * 0.85f }) {
                    drawOval(Brush.radialGradient(listOf(Color(0xFFF21F29).copy(alpha = 0.75f), Color.Transparent),
                        center = Offset(size.width / 2f, size.height / 2f), radius = size.width / 2f))
                }
            }
            Spacer(Modifier.height(28.dp))
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.graphicsLayer {
                    alpha = text.value
                    translationY = (1f - text.value) * 12.dp.toPx()
                },
            ) {
                Text("Nino", fontSize = 34.sp, fontWeight = FontWeight.Bold, color = NinoColors.Ink)
                Spacer(Modifier.height(6.dp))
                Text(stringResource(R.string.nino_games_now_in, languageName), fontSize = 15.sp, color = NinoColors.InkSecondary)
            }
        }
    }
}
