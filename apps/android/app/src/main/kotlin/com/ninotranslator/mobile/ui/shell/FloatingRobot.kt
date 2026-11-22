// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.shell

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.ui.theme.LocalAnimationsEnabled
import com.ninotranslator.mobile.ui.theme.NinoColors
import kotlinx.coroutines.delay

/**
 * Yüzen robot düğmesi (ekranlar-1 §5.1): sağ altta (sağdan sola arayüzde sol altta), 60 dp beyaz cam daire, içinde
 * 46 dp robot. 1,6 sn'de 3 dp yüzer, 4,5 sn'de bir 150 ms göz kırpar. [bottomOffset] gezinme çubuğunun üstünden.
 */
@Composable
fun BoxScope.FloatingRobot(onClick: () -> Unit, bottomOffset: Dp) {
    val animations = LocalAnimationsEnabled.current
    val label = stringResource(R.string.assistant_title)
    val lift = if (animations) {
        val t = rememberInfiniteTransition(label = "bot")
        val v by t.animateFloat(0f, 1f, infiniteRepeatable(tween(800, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "lift")
        v
    } else 0f
    var blink by remember { mutableStateOf(false) }
    if (animations) {
        LaunchedEffect(Unit) {
            while (true) {
                delay(4_500)
                blink = true
                delay(150)
                blink = false
            }
        }
    }
    Box(
        Modifier.align(Alignment.BottomEnd).navigationBarsPadding()
            .padding(end = 20.dp, bottom = bottomOffset)
            .size(60.dp)
            .shadow(14.dp, CircleShape, ambientColor = NinoColors.PackDark.copy(alpha = 0.25f), spotColor = NinoColors.PackDark.copy(alpha = 0.3f))
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.94f))
            .border(1.dp, NinoColors.BorderStrong, CircleShape)
            .semantics { contentDescription = label }
            .clickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painterResource(if (blink) R.drawable.nino_bot_blink else R.drawable.nino_bot), null,
            Modifier.size(46.dp).offset(y = (-3).dp * lift),
        )
    }
}

/** "Çeviri başladı" balonunun süresi (§5.2). */
const val STARTED_NOTICE_MS = 7_000L

/**
 * "Çeviri başladı" balonu (§5.2). [startedAtMs]'den 7 sn geçene kadar görünür. Robot görünüyorsa onun solunda,
 * değilse ekranın üst ortasında. Ekran okuyucuya kibarca duyurulur.
 */
@Composable
fun BoxScope.TranslationStartedBubble(startedAtMs: Long?, robotVisible: Boolean, robotBottomOffset: Dp) {
    var visible by remember { mutableStateOf(false) }
    LaunchedEffect(startedAtMs) {
        val at = startedAtMs ?: run { visible = false; return@LaunchedEffect }
        val left = STARTED_NOTICE_MS - (System.currentTimeMillis() - at)
        if (left <= 0) { visible = false; return@LaunchedEffect }
        visible = true
        delay(left)
        visible = false
    }
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val place = if (robotVisible) {
        Modifier.align(Alignment.BottomEnd).navigationBarsPadding()
            .padding(start = 20.dp, end = 90.dp, bottom = robotBottomOffset)
            .heightIn(min = 60.dp)
    } else {
        Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 12.dp, start = 20.dp, end = 20.dp)
    }
    Box(place, contentAlignment = Alignment.Center) {
        AnimatedVisibility(
            visible,
            enter = slideInHorizontally { w -> if (rtl) -w / 3 else w / 3 } + fadeIn(),
            exit = fadeOut(tween(600)),
        ) {
            Text(
                stringResource(R.string.translation_started_notice),
                fontSize = 14.sp, lineHeight = 18.sp, fontWeight = FontWeight.Bold, color = Color.White,
                modifier = Modifier.widthIn(max = 250.dp)
                    .clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.55f))
                    .padding(horizontal = 14.dp, vertical = 8.dp)
                    .semantics { liveRegion = LiveRegionMode.Polite },
            )
        }
    }
}

