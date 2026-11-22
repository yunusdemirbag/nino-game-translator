// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui

import android.content.Context
import android.content.Intent
import android.graphics.Color as AndroidColor
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings as SystemSettings
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.AppLanguage
import com.ninotranslator.mobile.data.AppLocales
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.TextColor
import com.ninotranslator.mobile.service.LiveStatus
import com.ninotranslator.mobile.service.PlacedText
import com.ninotranslator.mobile.service.TranslationControl
import com.ninotranslator.mobile.ui.components.NinoIconButton
import com.ninotranslator.mobile.ui.components.NinoTag
import com.ninotranslator.mobile.ui.components.StatusDot
import com.ninotranslator.mobile.ui.components.TagStyle
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoTheme
import com.ninotranslator.mobile.ui.theme.SubtitleFonts
import com.ninotranslator.mobile.ui.screens.home.forUi
import com.ninotranslator.mobile.ui.screens.home.uiNow
import com.ninotranslator.mobile.ui.screens.home.uiState
import kotlin.math.roundToInt

/**
 * Telefonda tam ekran altyazı (ekranlar-1 §9): yatay, siyah, sistem çubukları gizli; ekran açık kalır, 10 sn sonra
 * parlaklık %35'e (sistem daha düşükse ona) kısılır.
 */
class PhoneSubtitleActivity : ComponentActivity() {
    private val handler = Handler(Looper.getMainLooper())

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(AppLocales.wrap(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(AndroidColor.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(AndroidColor.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(AndroidColor.BLACK))
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowCompat.getInsetsController(window, window.decorView).apply {
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
        }
        handler.postDelayed(::dimScreen, 10_000)
        setContent { NinoTheme { PhoneSubtitleContent(onClose = ::finish) } }
    }

    private fun dimScreen() {
        val system = runCatching {
            SystemSettings.System.getInt(contentResolver, SystemSettings.System.SCREEN_BRIGHTNESS) / 255f
        }.getOrDefault(1f)
        window.attributes = window.attributes.apply { screenBrightness = minOf(0.35f, system).coerceAtLeast(0.01f) }
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    companion object {
        fun open(context: Context) {
            context.startActivity(Intent(context, PhoneSubtitleActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}

/** Uzun satırı en dengeli biçimde 2–3 satıra böler; konuşan adı ("ARTHUR:") sonraki sözcükle kalır. */
internal object SubtitleSplit {
    const val LIMIT = 42

    fun split(text: String): Pair<String, Float> {
        if (text.length <= LIMIT || '\n' in text) return text to 1f
        val raw = text.split(' ').filter { it.isNotEmpty() }
        if (raw.size < 2) return text to 1f
        // Konuşan adını sonraki sözcüğe bağla.
        val words = mutableListOf<String>()
        var i = 0
        while (i < raw.size) {
            val w = raw[i]
            if (i == 0 && w.endsWith(':') && raw.size > 1) { words += "$w ${raw[1]}"; i += 2 } else { words += w; i++ }
        }
        val lines = if (text.length > LIMIT * 2) 3 else 2
        val best = balance(words, lines.coerceAtMost(words.size))
        val ratio = maxOf(0.75f, (LIMIT * 3f) / text.length).coerceAtMost(1f)
        return best.joinToString("\n") to ratio
    }

    private fun balance(words: List<String>, lines: Int): List<String> {
        if (lines <= 1) return listOf(words.joinToString(" "))
        var bestSplit: List<String> = listOf(words.joinToString(" "))
        var bestScore = Int.MAX_VALUE
        fun rec(start: Int, left: Int, acc: List<String>) {
            if (left == 1) {
                val all = acc + words.subList(start, words.size).joinToString(" ")
                val score = all.maxOf { it.length }
                if (score < bestScore) { bestScore = score; bestSplit = all }
                return
            }
            for (end in start + 1..words.size - left + 1) {
                if (end >= words.size) break
                rec(end, left - 1, acc + words.subList(start, end).joinToString(" "))
            }
        }
        rec(0, lines, emptyList())
        return bestSplit
    }
}

@Composable
private fun PhoneSubtitleContent(onClose: () -> Unit) {
    val context = LocalContext.current
    val live by remember { LiveStatus.uiState() }.collectAsState(remember { LiveStatus.uiNow() })
    val settings = Nino.settings
    val rev by settings.revision.collectAsState()
    val font = remember(rev) { SubtitleFonts.family(context.assets, settings.subtitleFont) }
    val scalePct = remember(rev) { settings.subtitleScale }
    val color = remember(rev) { if (settings.textColor == TextColor.YELLOW) NinoColors.SubtitleYellow else Color.White }
    val stack = remember(rev) { settings.stackPrevious }
    val rtl = AppLanguage.isRtl(remember(rev) { settings.targetLanguage })
    val connected = live.running && live.streaming

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(20.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                val status = when {
                    connected -> stringResource(R.string.subtitle_connected)
                    live.errorText != null -> live.errorText!!
                    live.running && live.phaseText != null -> live.phaseText!!
                    else -> stringResource(R.string.subtitle_waiting)
                }
                Row(Modifier.weight(1f, fill = false), verticalAlignment = Alignment.CenterVertically) {
                    StatusDot(if (connected) NinoColors.Success else Color.White.copy(alpha = 0.4f), live = connected)
                    Spacer(Modifier.width(4.dp))
                    Text(status, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.75f), maxLines = 1,
                        overflow = TextOverflow.Ellipsis)
                }
                live.packTitle?.let { NinoTag(stringResource(R.string.running_pack, it), style = TagStyle.PACK) }
                Spacer(Modifier.weight(1f))
                if (connected) {
                    if (live.screenTranslations.isEmpty()) {
                        NinoIconButton(Icons.Filled.Search, stringResource(if (live.screenTranslating) R.string.screen_working else R.string.screen_translate),
                            { TranslationControl.translateScreen(context) })
                    } else {
                        NinoIconButton(Icons.Filled.Delete, stringResource(R.string.screen_remove),
                            { TranslationControl.clearScreenTranslations(context) })
                    }
                }
                NinoIconButton(Icons.Filled.Close, stringResource(R.string.close), onClose)
            }
            Box(Modifier.weight(1f).fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) {
                val current = live.currentLine?.takeIf { it.isNotBlank() }
                val text = current ?: if (!live.running) "Nino" else null
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    val prev = live.previousLine
                    // Hizmet satırı zaten böldüyse onun ölçeği, değilse burada bölünür.
                    val (body, ratio) = remember(text, live.currentLineScale) {
                        when {
                            text == null -> "" to 1f
                            '\n' in text -> text to live.currentLineScale
                            else -> SubtitleSplit.split(text)
                        }
                    }
                    val baseSp = 36f * scalePct / 100f * ratio
                    if (stack && current != null && !prev.isNullOrBlank() && prev != current && current.length < 90) {
                        Text(prev, style = subtitleStyle(font, color.copy(alpha = 0.4f), baseSp * 0.8f, rtl), maxLines = 2,
                            overflow = TextOverflow.Ellipsis)
                    }
                    if (text != null) FittedSubtitle(body, subtitleStyle(font, color, baseSp, rtl))
                }
            }
            Text(stringResource(R.string.subtitle_screen_note), Modifier.align(Alignment.CenterHorizontally), fontSize = 13.sp,
                color = Color.White.copy(alpha = 0.45f))
        }
        PlacedOverlays(live.screenTranslations, live.extraTranslations)
    }
}

private fun subtitleStyle(font: androidx.compose.ui.text.font.FontFamily, color: Color, sizeSp: Float, rtl: Boolean) = TextStyle(
    fontFamily = font, fontWeight = FontWeight.SemiBold, fontSize = sizeSp.sp, lineHeight = (sizeSp * 44f / 36f).sp, color = color,
    textAlign = TextAlign.Center, textDirection = if (rtl) TextDirection.Rtl else TextDirection.Content,
)

/** Sığmazsa her denemede %10 küçülür, en çok yarı boya kadar. */
@Composable
private fun FittedSubtitle(text: String, style: TextStyle) {
    var shrink by remember(text, style.fontSize) { mutableFloatStateOf(1f) }
    Text(
        text,
        style = style.copy(fontSize = style.fontSize * shrink, lineHeight = style.lineHeight * shrink),
        onTextLayout = { r -> if (r.hasVisualOverflow && shrink > 0.5f) shrink = (shrink * 0.9f).coerceAtLeast(0.5f) },
    )
}

/** Ekran çevirisi ve ek alan çevirileri: oyundaki yerinde (görüntüye oranla). */
@Composable
private fun PlacedOverlays(screen: List<PlacedText>, extras: List<PlacedText>) {
    if (screen.isEmpty() && extras.isEmpty()) return
    val density = LocalDensity.current
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val w = constraints.maxWidth.toFloat()
        val h = constraints.maxHeight.toFloat()
        screen.forEach { p ->
            val l = (p.left ?: 0f) * w; val t = (p.top ?: 0f) * h
            val bw = ((p.right ?: 1f) - (p.left ?: 0f)) * w
            val bh = ((p.bottom ?: 1f) - (p.top ?: 0f)) * h
            val sizeSp = with(density) { (bh * 0.7f).toSp().value }.coerceIn(10f, 28f)
            Text(p.text, fontSize = sizeSp.sp, color = Color.White,
                modifier = Modifier.offset { IntOffset(l.roundToInt(), t.roundToInt()) }
                    .widthIn(min = 60.dp, max = with(density) { maxOf(bw, 60.dp.toPx()).toDp() })
                    .clip(RoundedCornerShape(4.dp)).background(Color.Black.copy(alpha = 0.85f)).padding(4.dp))
        }
        extras.forEach { p ->
            val hasPos = p.left != null && p.top != null
            val l = (p.left ?: 0.60f) * w; val t = (p.top ?: 0.05f) * h
            val areaW = if (hasPos) ((p.right ?: 1f) - (p.left ?: 0f)) * w else 0.35f * w
            val maxW = with(density) { maxOf(areaW, 120.dp.toPx()).toDp() }
            Text(p.text, fontSize = 13.sp, color = Color.White,
                modifier = Modifier.offset { IntOffset(l.roundToInt(), t.roundToInt()) }
                    .widthIn(min = 120.dp, max = maxW)
                    .clip(RoundedCornerShape(6.dp)).background(Color.Black.copy(alpha = 0.8f)).padding(6.dp))
        }
    }
}
