// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.setup

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.AppLanguage
import com.ninotranslator.mobile.ui.components.stageSurface
import com.ninotranslator.mobile.ui.theme.LocalAnimationsEnabled
import com.ninotranslator.mobile.ui.theme.letterSpacingFor
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Örnek altyazı satırı: İngilizce özgün ve çeviri. */
data class SampleLine(val english: String, val translation: String)

/**
 * Örnek sahnenin satırları (ekranlar-1 §6.1.1), çeviri diline göre. Örnek içerik olduğu için arayüz metni değildir.
 */
object SampleLines {
    private const val LANTERN = "Keep the lantern low until we cross the river."
    private const val STEPS = "Footsteps upstairs. Don't make a sound."
    private const val ANYONE = "Is anyone out there?"
    private const val FOG = "The fog rolls in every night at this hour."
    private const val DOCK = "Grab the map and meet me at the dock!"

    private fun three(anyone: String, steps: String, dock: String) =
        listOf(SampleLine(ANYONE, anyone), SampleLine(STEPS, steps), SampleLine(DOCK, dock))

    fun forLanguage(code: String): List<SampleLine> = when (code) {
        "tr" -> listOf(
            SampleLine(LANTERN, "Nehri geçene kadar feneri alçakta tut."),
            SampleLine(STEPS, "Üst katta ayak sesleri var. Sakın ses çıkarma."),
            SampleLine(ANYONE, "Dışarıda kimse var mı?"),
            SampleLine(FOG, "Sis her gece bu saatte çöker."),
            SampleLine(DOCK, "Haritayı al, iskelede buluşalım!"),
        )
        "ar" -> listOf(
            SampleLine(LANTERN, "أبقِ الفانوس منخفضًا حتى نعبر النهر."),
            SampleLine(STEPS, "خطوات في الطابق العلوي. لا تُصدر أي صوت."),
            SampleLine(ANYONE, "هل يوجد أحد في الخارج؟"),
            SampleLine(FOG, "يزحف الضباب كل ليلة في هذه الساعة."),
            SampleLine(DOCK, "خذ الخريطة وقابلني عند الرصيف!"),
        )
        "hi" -> three("क्या बाहर कोई है?", "ऊपर क़दमों की आहट है। कोई आवाज़ मत करना।", "नक्शा लो और मुझसे घाट पर मिलो!")
        "id" -> three("Apa ada orang di luar sana?", "Ada langkah kaki di lantai atas. Jangan bersuara.", "Ambil petanya dan temui aku di dermaga!")
        "th" -> three("มีใครอยู่ข้างนอกไหม?", "มีเสียงฝีเท้าอยู่ชั้นบน อย่าส่งเสียง", "เอาแผนที่มา แล้วไปเจอฉันที่ท่าเรือ!")
        "vi" -> three("Có ai ngoài đó không?", "Có tiếng bước chân trên lầu. Đừng gây tiếng động.", "Cầm bản đồ rồi gặp tôi ở bến tàu!")
        "ur" -> three("کیا باہر کوئی ہے؟", "اوپر قدموں کی آہٹ ہے۔ کوئی آواز مت کرنا۔", "نقشہ لو اور مجھ سے گھاٹ پر ملو!")
        "bn" -> three("বাইরে কেউ আছে?", "ওপরতলায় পায়ের শব্দ। কোনো শব্দ কোরো না।", "মানচিত্রটা নাও, ঘাটে আমার সাথে দেখা করো!")
        "ms" -> three("Ada sesiapa di luar sana?", "Ada bunyi tapak kaki di tingkat atas. Jangan bersuara.", "Ambil peta itu dan jumpa saya di jeti!")
        "tl" -> three("May tao ba riyan sa labas?", "May mga yabag sa itaas. Huwag kang mag-ingay.", "Kunin mo ang mapa at magkita tayo sa daungan!")
        "nl" -> three("Is daar buiten iemand?", "Voetstappen boven. Maak geen geluid.", "Pak de kaart en kom naar de steiger!")
        else -> forLanguage("tr")
    }
}

/**
 * Örnek altyazı sahnesi (§6.1.1): koyu sahne kartı, iki yumuşak ışık, sol üstte "ÖRNEK" rozeti, altta İngilizce satır
 * ve yerine yaylanarak gelen çeviri, sonsuz döngü.
 */
@Composable
fun SampleSubtitleScene(languageCode: String, modifier: Modifier = Modifier, height: Dp = 380.dp) {
    val lines = remember(languageCode) { SampleLines.forLanguage(languageCode) }
    val rtl = AppLanguage.isRtl(languageCode)
    val animations = LocalAnimationsEnabled.current
    var index by remember(languageCode) { mutableIntStateOf(0) }
    val english = remember { Animatable(0f) }
    val translated = remember { Animatable(0f) }
    val all = remember { Animatable(1f) }

    LaunchedEffect(languageCode, animations) {
        if (!animations) {
            english.snapTo(0f); translated.snapTo(1f); all.snapTo(1f)
            return@LaunchedEffect
        }
        while (true) {
            all.snapTo(1f); translated.snapTo(0f)
            english.animateTo(1f, tween(300))
            delay(900)
            translated.animateTo(1f, spring(dampingRatio = 0.8f, stiffness = 300f))
            delay(2_600)
            all.animateTo(0f, tween(250))
            delay(450)
            english.snapTo(0f)
            index = (index + 1) % lines.size
        }
    }

    val line = lines[index % lines.size]
    Box(modifier.fillMaxWidth().height(height).stageSurface()) {
        Canvas(Modifier.fillMaxSize()) {
            val w = size.width; val h = size.height
            drawRect(Brush.radialGradient(listOf(Color(0xFFFF9A4A).copy(alpha = 0.16f), Color.Transparent),
                center = Offset(w * 0.75f, h * 0.30f), radius = w * 0.35f))
            drawRect(Brush.radialGradient(listOf(Color(0xFF0070D1).copy(alpha = 0.22f), Color.Transparent),
                center = Offset(w * 0.20f, h * 0.45f), radius = w * 0.40f))
        }
        Text(
            stringResource(R.string.nino_sample),
            fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.White,
            letterSpacing = letterSpacingFor(languageCode, 1.5f),
            modifier = Modifier.align(Alignment.TopStart).padding(12.dp)
                .clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.4f))
                .border(1.dp, Color.White.copy(alpha = 0.2f), RoundedCornerShape(50))
                .padding(horizontal = 10.dp, vertical = 4.dp),
        )
        Box(Modifier.align(Alignment.BottomCenter).padding(start = 16.dp, end = 16.dp, bottom = 20.dp),
            contentAlignment = Alignment.Center) {
            Text(
                line.english,
                style = TextStyle(fontSize = 15.sp, color = Color(0xFFF4F1E8), textAlign = TextAlign.Center),
                modifier = Modifier.graphicsLayer {
                    alpha = (english.value * (1f - translated.value.coerceIn(0f, 1f)) * all.value).coerceIn(0f, 1f)
                },
            )
            val t = translated.value
            Text(
                line.translation,
                style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White,
                    textAlign = TextAlign.Center, textDirection = if (rtl) TextDirection.Rtl else TextDirection.Content),
                modifier = Modifier.graphicsLayer {
                    alpha = (t.coerceIn(0f, 1f) * all.value).coerceIn(0f, 1f)
                    val s = 0.96f + 0.04f * t
                    scaleX = s; scaleY = s
                }.clip(RoundedCornerShape(10.dp)).background(Color.Black.copy(alpha = 0.72f))
                    .padding(horizontal = 14.dp, vertical = 6.dp),
            )
        }
    }
}
