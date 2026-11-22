// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.theme

import android.content.res.AssetManager
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.data.SubtitleFont

/** Yazı ölçeği (ekranlar-1 §1.2). Uygulama yazısı sistemin yazı tipidir. */
object NinoType {
    private fun style(size: Int, line: Int, weight: FontWeight = FontWeight.Normal) =
        TextStyle(fontSize = size.sp, lineHeight = line.sp, fontWeight = weight, color = NinoColors.Ink)

    /** 28/34, 600. */
    val LargeTitle = style(28, 34, FontWeight.SemiBold)
    /** 22/28, 600. */
    val Title = style(22, 28, FontWeight.SemiBold)
    /** 17/22, 600: alt başlık ve düğme yazısı. */
    val Headline = style(17, 22, FontWeight.SemiBold)
    /** 17/22 normal: önceki altyazı satırı. */
    val PreviousLine = style(17, 22)
    /** 15/20 normal. */
    val Body = style(15, 20)
    /** 13/16, 500. */
    val Caption = style(13, 16, FontWeight.Medium)
    /** Telefondaki altyazı (dikey) 28/36, 600. */
    val PhoneSubtitle = style(28, 36, FontWeight.SemiBold)
    /** Telefondaki altyazı (yatay tam ekran) 36/44, 600. */
    val PhoneSubtitleFull = style(36, 44, FontWeight.SemiBold)

    /** Kurulum ekranı başlığı 32/38, 700, −0,5 sp (§2.6). */
    val ScreenTitle = TextStyle(fontSize = 32.sp, lineHeight = 38.sp, fontWeight = FontWeight.Bold,
        letterSpacing = (-0.5).sp, color = NinoColors.Ink)
    /** Kurulum ekranı açıklaması 16/23. */
    val ScreenBody = TextStyle(fontSize = 16.sp, lineHeight = 23.sp, color = NinoColors.InkSecondary)
    /** Adım satırı 13 sp 600, 0,2 sp. */
    val StepLine = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.2.sp,
        color = NinoColors.AccentText)
    /** Ana ekran başlığı 34/40 kalın, −0,6 sp (§7.1). */
    val HomeTitle = TextStyle(fontSize = 34.sp, lineHeight = 40.sp, fontWeight = FontWeight.Bold,
        letterSpacing = (-0.6).sp, color = NinoColors.Ink)
}

/** Altyazı yazı tipleri (§1.2): assets `fonts/` altında, Gradle kopyalar. Bulunmayan harfler sistem yedeğinden. */
object SubtitleFonts {
    @Volatile private var cache: Map<SubtitleFont, FontFamily>? = null

    fun family(assets: AssetManager, font: SubtitleFont): FontFamily {
        val map = cache ?: build(assets).also { cache = it }
        return map[font] ?: FontFamily.Default
    }

    @OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)
    private fun build(assets: AssetManager): Map<SubtitleFont, FontFamily> {
        fun fam(vararg fonts: () -> Font): FontFamily =
            runCatching { FontFamily(fonts.map { it() }) }.getOrDefault(FontFamily.Default)
        return mapOf(
            SubtitleFont.CONDENSED to fam(
                { Font("fonts/BarlowCondensed-SemiBold.ttf", assets, FontWeight.SemiBold) },
                { Font("fonts/BarlowCondensed-Bold.ttf", assets, FontWeight.Bold) },
            ),
            SubtitleFont.MODERN to fam(
                { Font("fonts/Barlow-SemiBold.ttf", assets, FontWeight.SemiBold) },
                { Font("fonts/Barlow-Bold.ttf", assets, FontWeight.Bold) },
            ),
            SubtitleFont.ROUNDED to fam(
                {
                    Font("fonts/Nunito-Variable.ttf", assets, FontWeight(650),
                        variationSettings = FontVariation.Settings(FontVariation.weight(650)))
                },
            ),
            SubtitleFont.SYSTEM to FontFamily.Default,
        )
    }
}

/** Arapça yazıda harf aralığı 0 olur (birçok yerde). */
fun letterSpacingFor(languageTag: String?, spacingSp: Float) =
    if (languageTag?.startsWith("ar") == true) 0.em else spacingSp.sp
