// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.home

import android.graphics.BlurMaskFilter
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.ConsoleKind
import com.ninotranslator.mobile.ui.components.languageDisplayName
import com.ninotranslator.mobile.ui.shell.AppSession
import com.ninotranslator.mobile.ui.shell.SplashAnimation
import com.ninotranslator.mobile.ui.theme.LocalAnimationsEnabled
import com.ninotranslator.mobile.ui.theme.letterSpacingFor
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt

/** Salon görselinin ölçüleri (görsel pikseli, ekranlar-1 §7.2.1). */
private class RoomGeometry(
    val image: Int,
    val screen: Rect,
    val frame: Rect,
    val stand: Rect,
    val socket: Offset,
    val cableStart: Offset,
    val rest: Offset,
    /** Görselde var olan kablo parçası (PS5); üstünden geçilir. Boşsa konsolun arkasında küçük fiş başı çizilir. */
    val cablePrefix: List<Offset>,
    val exitDir: Offset,
) {
    companion object {
        const val WIDTH = 1672f
        const val HEIGHT = 941f
        private fun r(l: Float, t: Float, w: Float, h: Float) = Rect(l, t, l + w, t + h)

        val PS5 = RoomGeometry(
            R.drawable.living_room, r(149f, 40f, 1151f, 595f), r(139f, 27f, 1171f, 621f), r(49f, 713f, 1502f, 160f),
            Offset(1564f, 378f), Offset(1550f, 734f), Offset(1600f, 885f),
            listOf(Offset(1490f, 706f), Offset(1522f, 706f), Offset(1535f, 709f), Offset(1545f, 716f), Offset(1552f, 727f)),
            Offset(0.5f, 0.87f),
        )
        val XBOX = RoomGeometry(
            R.drawable.living_room_xbox, r(136f, 40f, 1185f, 596f), r(121f, 26f, 1214f, 630f), r(43f, 733f, 1580f, 167f),
            Offset(1561f, 381f), Offset(1572f, 722f), Offset(1646f, 912f), emptyList(), Offset(1f, 0.1f),
        )
    }
}

private fun Offset.norm(): Offset { val l = hypot(x, y); return if (l == 0f) this else Offset(x / l, y / l) }

/**
 * Salon sahnesi (§7.2.1): duvarda TV, sehpa, konsol, priz; fiş prize takılınca çeviri başlar, çekilince durur.
 * [onToggle] fişe/prize dokunma ve sürükleme sonucu (açıksa durdur; kapalıysa eşliyse başlat, değilse kilitli dokunuş).
 * [showReady] false iken (açılış animasyonu sürüyor) açılış gösterisi bekler.
 */
@Composable
fun LivingRoomScene(
    model: HomeModel,
    onToggle: () -> Unit,
    showReady: Boolean,
    modifier: Modifier = Modifier,
) {
    val geo = if (model.consoleKind == ConsoleKind.XBOX) RoomGeometry.XBOX else RoomGeometry.PS5
    val density = LocalDensity.current
    val animations = LocalAnimationsEnabled.current
    val running = model.running
    val toggle by rememberUpdatedState(onToggle)
    val runningNow by rememberUpdatedState(running)
    val label = if (running) stringResource(R.string.nino_unplug_to_stop)
    else stringResource(R.string.nino_plug_to_start, languageDisplayName(model.language))

    // Arapça arayüzde de aynalanmaz.
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        BoxWithConstraints(modifier.fillMaxWidth()) {
            val widthPx = constraints.maxWidth.toFloat()
            val scale = widthPx / (RoomGeometry.WIDTH + 40f)
            val dpPerImagePx = scale / density.density
            val magnify = (0.3f / dpPerImagePx).coerceIn(1f, 1.6f)
            val heightPx = max(RoomGeometry.HEIGHT, geo.rest.y + 46f * magnify) * scale + with(density) { 6.dp.toPx() }
            val heightDp = with(density) { heightPx.toDp() }

            val plug = remember(geo) { Animatable(if (running && AppSession.plugShowDone) geo.socket else geo.rest, Offset.VectorConverter) }
            var dragging by remember { mutableStateOf(false) }
            var showing by remember { mutableStateOf(!AppSession.plugShowDone) }
            var softUntil by remember { mutableStateOf(0L) }
            val scope = rememberCoroutineScope()

            // Açılış gösterisi: ana ekran ilk göründüğünde bir kez.
            LaunchedEffect(showReady, geo) {
                if (!showReady || AppSession.plugShowDone) return@LaunchedEffect
                AppSession.plugShowDone = true
                if (!animations) { plug.snapTo(if (runningNow) geo.socket else geo.rest); showing = false; return@LaunchedEffect }
                plug.snapTo(geo.rest)
                delay(900)
                softUntil = System.currentTimeMillis() + 1_200
                if (runningNow) plug.animateTo(geo.socket, spring(dampingRatio = 0.7f, stiffness = 130f))
                delay((softUntil - System.currentTimeMillis()).coerceAtLeast(0))
                showing = false
            }
            // Durum değişince fiş yerine yaylanır.
            LaunchedEffect(running, geo, showing) {
                if (dragging || showing) return@LaunchedEffect
                val target = if (running) geo.socket else geo.rest
                if (!animations) plug.snapTo(target)
                else plug.animateTo(target, spring(dampingRatio = 0.78f, stiffness = 158f))
            }

            val plugged = !dragging && (plug.value - geo.socket).getDistance() < 3f
            val ledAlpha by animateFloatAsState(if (running && plugged) 1f else 0f, tween(800), label = "led")
            val socketAlpha by animateFloatAsState(if (plugged) 0f else 1f, tween(500), label = "socket")
            val poolMix by animateFloatAsState(if (model.live.poolFirstGame) 1f else 0f, tween(1200), label = "pool")
            val pulse = if (animations) {
                val t = rememberInfiniteTransition(label = "pulse")
                val v by t.animateFloat(0f, 1f, infiniteRepeatable(tween(950, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "p")
                v
            } else 1f

            val touchPx = with(density) { 32.dp.toPx() }
            val slop = LocalViewConfiguration.current.touchSlop

            Box(
                Modifier.fillMaxWidth().height(heightDp)
                    .semantics { contentDescription = label; role = Role.Button; onClick { toggle(); true } }
                    .pointerInput(geo, scale) {
                        awaitEachGesture {
                            val down = awaitFirstDown(requireUnconsumed = false)
                            val plugScreen = plug.value * scale
                            val restAt = (if (runningNow) geo.socket else geo.rest) * scale
                            val nearPlug = (down.position - plugScreen).getDistance() <= touchPx ||
                                (down.position - restAt).getDistance() <= touchPx
                            val nearSocket = (down.position - geo.socket * scale).getDistance() <= touchPx
                            if (!nearPlug && !nearSocket) return@awaitEachGesture
                            down.consume()
                            var moved = 0f
                            var drag = false
                            val start = plug.value
                            var total = Offset.Zero
                            while (true) {
                                val event = awaitPointerEvent()
                                val change = event.changes.firstOrNull { it.id == down.id } ?: break
                                if (!change.pressed) break
                                val delta = change.positionChange()
                                moved += delta.getDistance()
                                total += delta
                                if (!drag && moved > slop && nearPlug) { drag = true; dragging = true }
                                if (drag) {
                                    change.consume()
                                    val next = start + total / scale
                                    scope.launch { plug.snapTo(next) }
                                }
                            }
                            if (drag) {
                                val wantPlugged = (plug.value - geo.socket).getDistance() < 160f
                                if (wantPlugged != runningNow) toggle()
                                dragging = false
                                scope.launch {
                                    delay(50)
                                    val target = if (runningNow) geo.socket else geo.rest
                                    plug.animateTo(target, spring(dampingRatio = 0.75f, stiffness = 158f))
                                }
                            } else {
                                toggle()
                            }
                        }
                    },
            ) {
                // 1–2: LED ve priz ışığı (görselin arkasında).
                Canvas(Modifier.fillMaxSize()) {
                    if (ledAlpha > 0.01f) drawLeds(geo, scale, ledAlpha, poolMix)
                    if (socketAlpha > 0.01f) drawSocketGlow(geo, scale, socketAlpha, pulse)
                }
                // 3: salon görseli.
                Image(
                    painterResource(geo.image), null,
                    Modifier.size(with(density) { (RoomGeometry.WIDTH * scale).toDp() }, with(density) { (RoomGeometry.HEIGHT * scale).toDp() }),
                )
                // 4: TV ekranının içi.
                val sw = with(density) { (geo.screen.width * scale).toDp() }
                val sh = with(density) { (geo.screen.height * scale).toDp() }
                Box(
                    Modifier.offset { IntOffset((geo.screen.left * scale).roundToInt(), (geo.screen.top * scale).roundToInt()) }
                        .size(sw, sh).clipToBounds().background(Color.Black),
                ) {
                    TvContent(model, plugged = running && plugged, hideCounter = showing, screenWidthDp = sw.value,
                        aspect = geo.screen.height / geo.screen.width)
                }
                // 5–6: kablo ve fiş.
                Canvas(Modifier.fillMaxSize()) { drawCableAndPlug(geo, scale, magnify, plug.value, plugged, dragging) }
            }
        }
    }
}

/** TV'nin içi: bekleme ekranı, açılış animasyonu ya da canlı ekran (420 dp genişlikte sanal TV, küçültülür). */
@Composable
private fun TvContent(model: HomeModel, plugged: Boolean, hideCounter: Boolean, screenWidthDp: Float, aspect: Float) {
    var bootDone by remember { mutableStateOf(false) }
    LaunchedEffect(plugged) { if (!plugged) bootDone = false }
    val virtualW = 420f
    val factor = screenWidthDp / virtualW
    Box(
        Modifier.wrapContentSize(Alignment.TopStart, unbounded = true)
            .requiredSize(virtualW.dp, (virtualW * aspect).dp)
            .graphicsLayer { scaleX = factor; scaleY = factor; transformOrigin = TransformOrigin(0f, 0f) },
    ) {
        when {
            !plugged -> IdleTv(model, counter = if (hideCounter) null else model.downloadTotal)
            !bootDone && !model.live.streaming -> {
                val bootW = 820f
                val k = virtualW / bootW
                Box(
                    Modifier.wrapContentSize(Alignment.TopStart, unbounded = true).requiredSize(bootW.dp, 424.dp)
                        .graphicsLayer { scaleX = k; scaleY = k; transformOrigin = TransformOrigin(0f, 0f) },
                ) {
                    SplashAnimation(languageDisplayName(model.language), onFinished = { bootDone = true })
                }
            }
            else -> LiveTvScreen(model, counter = if (hideCounter) null else model.downloadTotal, countUp = true)
        }
    }
}

/** Bekleme ekranı (§7.2.2). */
@Composable
private fun IdleTv(model: HomeModel, counter: Int?) {
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        Text(
            stringResource(R.string.nino_plug_drag_hint),
            style = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 16.sp, lineHeight = 23.sp, fontWeight = FontWeight.SemiBold,
                letterSpacing = letterSpacingFor(model.language, 2.5f), color = Color.White.copy(alpha = 0.45f), textAlign = TextAlign.Center),
            modifier = Modifier.align(Alignment.Center).padding(horizontal = 56.dp),
        )
        if (counter != null && counter > 0) {
            DownloadCounter(counter, countUp = false, language = model.language, modifier = Modifier.align(Alignment.TopEnd).padding(18.dp))
        }
    }
}

private val LedWide = Color(0xFF1F5CFF)
private val LedThin = Color(0xFF738CFF)
private val PoolWide = listOf(Color(0xFFFF3D9E), Color(0xFFBD80F5), Color(0xFF4DC7FF))
private val PoolThin = listOf(Color(0xFFFF85C7), Color(0xFFD6B3FF), Color(0xFF94E0FF))

private fun mix(a: Color, b: Color, t: Float) = Color(
    a.red + (b.red - a.red) * t, a.green + (b.green - a.green) * t, a.blue + (b.blue - a.blue) * t, 1f,
)

private fun ledBrush(base: Color, pool: List<Color>, mixT: Float, left: Float, right: Float): Brush =
    Brush.horizontalGradient(pool.map { mix(base, it, mixT) }, startX = left, endX = right)

/** TV arkası duvar ışığı ve sehpa şeridi. */
private fun DrawScope.drawLeds(g: RoomGeometry, s: Float, alpha: Float, poolMix: Float) {
    val f = g.frame
    val wide = ledBrush(LedWide, PoolWide, poolMix, f.left * s, f.right * s)
    val thin = ledBrush(LedThin, PoolThin, poolMix, f.left * s, f.right * s)
    for (i in 0 until 7) {
        val e = 10f + 12f * i
        val a = 0.11f - (0.11f - 0.06f) * i / 6f
        drawRoundRect(wide, Offset((f.left - e) * s, (f.top - e) * s), Size((f.width + 2 * e) * s, (f.height + 2 * e) * s),
            CornerRadius((30f + e) * s), alpha = a * alpha)
    }
    drawRoundRect(thin, Offset((f.left - 5f) * s, (f.top - 5f) * s), Size((f.width + 10f) * s, (f.height + 10f) * s),
        CornerRadius(12f * s), alpha = 0.55f * alpha)

    val st = g.stand
    val sw = ledBrush(LedWide, PoolWide, poolMix, st.left * s, st.right * s)
    val stn = ledBrush(LedThin, PoolThin, poolMix, st.left * s, st.right * s)
    for (i in 0 until 6) {
        val h = 10f + 8f * i
        val a = 0.14f - (0.14f - 0.08f) * i / 5f
        drawRoundRect(sw, Offset(st.left * s, (st.bottom - h / 2f) * s), Size(st.width * s, h * s), CornerRadius(h / 2f * s), alpha = a * alpha)
    }
    drawRoundRect(stn, Offset(st.left * s, (st.bottom - 3f) * s), Size(st.width * s, 6f * s), CornerRadius(3f * s), alpha = alpha)
}

/** Prizin çevresinde yumuşak kenarlı iki kare, nabız gibi. */
private fun DrawScope.drawSocketGlow(g: RoomGeometry, s: Float, alpha: Float, pulse: Float) {
    fun square(color: Color, side: Float, corner: Float, soft: Float, a: Float) {
        drawIntoCanvas { canvas ->
            val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                this.color = color.copy(alpha = a.coerceIn(0f, 1f)).toArgb()
                if (soft > 0f) maskFilter = BlurMaskFilter(soft * s, BlurMaskFilter.Blur.NORMAL)
            }
            val half = side / 2f
            canvas.nativeCanvas.drawRoundRect((g.socket.x - half) * s, (g.socket.y - half) * s, (g.socket.x + half) * s,
                (g.socket.y + half) * s, corner * s, corner * s, paint)
        }
    }
    square(Color(0xFF4DA8FF), 86f + 26f, 16f, 18f, (0.30f + 0.65f * pulse) * alpha)
    square(Color(0xFF9ED6FF), 86f + 8f, 12f, 5f, (0.45f + 0.55f * pulse) * alpha)
}

/** Kablo (başından fişe tek eğri) ve fiş. */
private fun DrawScope.drawCableAndPlug(g: RoomGeometry, s: Float, m: Float, plug: Offset, plugged: Boolean, dragging: Boolean) {
    val cable = Color(0xFF0F0F0F)
    val stroke = Stroke(8f * s, cap = StrokeCap.Round, join = StrokeJoin.Round)
    val path = Path()
    if (g.cablePrefix.isNotEmpty()) {
        path.moveTo(g.cablePrefix.first().x * s, g.cablePrefix.first().y * s)
        g.cablePrefix.drop(1).forEach { path.lineTo(it.x * s, it.y * s) }
    } else {
        path.moveTo(g.cableStart.x * s, g.cableStart.y * s)
    }
    val start = if (g.cablePrefix.isNotEmpty()) g.cablePrefix.last() else g.cableStart
    val exit = g.exitDir.norm()

    // Fişin yönü: dinlenirken uçlar aşağı; prize yaklaştıkça prize döner (120 px kala tam).
    val toSocket = g.socket - plug
    val dist = toSocket.getDistance()
    val restDist = (g.socket - g.rest).getDistance().coerceAtLeast(121f)
    val turn = (1f - (dist - 120f) / (restDist - 120f)).coerceIn(0f, 1f)
    val full = if (dist < 0.5f) 0f else atan2(-toSocket.x, toSocket.y)
    val angle = full * turn
    val axis = Offset(-kotlin.math.sin(angle), kotlin.math.cos(angle))

    if (plugged) {
        val end = g.socket + Offset(0f, 30f)
        path.cubicTo((start.x + exit.x * 120f) * s, (start.y + exit.y * 120f) * s,
            end.x * s, (end.y + 140f) * s, end.x * s, end.y * s)
        path.lineTo(g.socket.x * s, g.socket.y * s)
    } else {
        val end = plug - axis * (40f * m)
        val slack = (330f - (end - start).getDistance()).coerceAtLeast(0f) * 0.45f
        val c1 = start + exit * 90f + Offset(0f, slack)
        val c2 = end - axis * 90f + Offset(0f, slack)
        path.cubicTo(c1.x * s, c1.y * s, c2.x * s, c2.y * s, end.x * s, end.y * s)
    }
    drawPath(path, cable, style = stroke)
    if (g.cablePrefix.isEmpty()) {
        // Xbox: konsolun arkasındaki girişte küçük fiş başı.
        drawRoundRect(Color(0xFF141414), Offset((g.cableStart.x - 7f) * s, (g.cableStart.y - 6f) * s), Size(14f * s, 12f * s),
            CornerRadius(3f * s))
    }

    if (plugged) {
        val c = g.socket * s
        val r = 29f * m * s
        drawCircle(Color.Black.copy(alpha = 0.35f), r, c + Offset(0f, 4f * m * s))
        drawCircle(Brush.linearGradient(listOf(Color(0xFF3D3D3D), Color(0xFF0A0A0A)), start = c - Offset(r, r), end = c + Offset(r, r)), r, c)
        drawCircle(Color.White.copy(alpha = 0.18f), r, c, style = Stroke(1.5f * m * s))
        return
    }
    val k = m * s * (if (dragging) 1.08f else 1f)
    translate(plug.x * s, plug.y * s) {
        rotate(angle * 180f / PI.toFloat(), pivot = Offset.Zero) {
            // Kablo boğazı, gövde, iki metal uç (uçlar +y yönünde).
            drawRoundRect(cable, Offset(-8f * k, -39f * k), Size(16f * k, 14f * k), CornerRadius(6f * k))
            drawRoundRect(Brush.horizontalGradient(listOf(Color(0xFF383838), Color(0xFF0A0A0A)), -18f * k, 18f * k),
                Offset(-18f * k, -25f * k), Size(36f * k, 50f * k), CornerRadius(9f * k))
            for (dx in listOf(-10f, 10f)) {
                drawRoundRect(Brush.verticalGradient(listOf(Color(0xFFEBEBEB), Color(0xFF999999)), 25f * k, 49f * k),
                    Offset((dx - 3f) * k, 25f * k), Size(6f * k, 24f * k), CornerRadius(3f * k))
            }
        }
    }
}

