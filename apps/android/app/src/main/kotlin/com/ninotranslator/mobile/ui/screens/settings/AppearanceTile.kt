// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.service.TranslationControl
import com.ninotranslator.mobile.data.SubtitleFont
import com.ninotranslator.mobile.data.SubtitleTarget
import com.ninotranslator.mobile.data.TextColor
import com.ninotranslator.mobile.data.TvBackgroundShape
import com.ninotranslator.mobile.data.TvDisplayMode
import com.ninotranslator.mobile.data.TvPlacement
import com.ninotranslator.mobile.ui.components.NinoSlider
import com.ninotranslator.mobile.ui.components.NinoSwitch
import com.ninotranslator.mobile.ui.components.NinoTile
import com.ninotranslator.mobile.ui.components.SegmentedPicker
import com.ninotranslator.mobile.ui.components.TileLabel
import com.ninotranslator.mobile.ui.screens.SmallNote
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoDimens
import com.ninotranslator.mobile.ui.theme.NinoType
import com.ninotranslator.mobile.ui.theme.SubtitleFonts
import kotlin.math.roundToInt

/** Altyazı görünümü karosu (ekranlar-2 Ayarlar §7). Her değişiklik anında kaydedilir. */
@Composable
fun AppearanceTile() {
    val context = LocalContext.current
    val s = Nino.settings
    val rev by s.revision.collectAsState()
    val scale = remember(rev) { s.subtitleScale }
    val auto = remember(rev) { s.tvAutoSize }
    val color = remember(rev) { s.textColor }
    val font = remember(rev) { s.subtitleFont }
    val placement = remember(rev) { s.tvPlacement }
    val tvTarget = remember(rev) { s.target == SubtitleTarget.TV }
    fun test() { TranslationControl.sendTestSubtitle(context, context.getString(R.string.test_subtitle_text)) }

    NinoTile {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.settings_text_size), Modifier.weight(1f), style = NinoType.Headline)
            Text("%$scale", style = NinoType.Title)
        }
        LabeledSwitch(stringResource(R.string.settings_auto_size), auto) { s.tvAutoSize = it }
        if (auto) SmallNote(stringResource(R.string.settings_auto_size_note))
        NinoSlider(scale.toFloat(), { s.setSubtitleScaleByUser((it / 10f).roundToInt() * 10) }, valueRange = 40f..160f, steps = 11,
            onValueChangeFinished = ::test)

        Text(
            stringResource(R.string.settings_preview),
            style = NinoType.Title.copy(
                fontSize = (22 * scale / 100f).sp, lineHeight = (28 * scale / 100f).sp, fontWeight = FontWeight.SemiBold,
                fontFamily = SubtitleFonts.family(context.assets, font),
                color = if (color == TextColor.YELLOW) NinoColors.AccentText else NinoColors.Ink,
            ),
        )

        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(stringResource(R.string.settings_color), Modifier.weight(1f), style = NinoType.Headline)
            ColorSwatch(NinoColors.Ink, color == TextColor.WHITE) { s.textColor = TextColor.WHITE; test() }
            ColorSwatch(NinoColors.Accent, color == TextColor.YELLOW) { s.textColor = TextColor.YELLOW; test() }
        }

        TileLabel(stringResource(R.string.settings_font))
        val fonts = SubtitleFont.entries
        fonts.chunked(2).forEach { pair ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                pair.forEach { f -> FontBox(f, f == font, Modifier.weight(1f)) { s.subtitleFont = f; test() } }
            }
        }

        // Arka plan koyuluğu: "Örtsün"de TV'ye %60 altı gitmez, kaydırıcı %60'tan başlar.
        val cover = placement == TvPlacement.COVER
        val bg = remember(rev) { s.effectiveTvBackground }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.settings_background), Modifier.weight(1f), style = NinoType.Headline)
            Text("%$bg", style = NinoType.Headline, color = NinoColors.InkSecondary)
        }
        NinoSlider(bg.toFloat(), { s.tvBackground = (it / 5f).roundToInt() * 5 },
            valueRange = if (cover) 60f..100f else 0f..100f, steps = if (cover) 7 else 19)
        TileLabel(stringResource(R.string.settings_background_area))
        val shapes = listOf(TvBackgroundShape.FIT, TvBackgroundShape.BAND)
        val shape = remember(rev) { s.tvBackgroundShape }
        SegmentedPicker(listOf(stringResource(R.string.settings_background_fit), stringResource(R.string.settings_background_band)),
            shapes.indexOf(shape), { s.tvBackgroundShape = shapes[it] })
        SmallNote(stringResource(R.string.settings_background_note))

        if (tvTarget) {
            TileLabel(stringResource(R.string.settings_placement))
            val places = listOf(TvPlacement.COVER, TvPlacement.ABOVE, TvPlacement.BELOW, TvPlacement.FIXED)
            SegmentedPicker(
                listOf(stringResource(R.string.settings_placement_cover), stringResource(R.string.settings_placement_above),
                    stringResource(R.string.settings_placement_below), stringResource(R.string.settings_placement_fixed)),
                places.indexOf(placement), { s.tvPlacement = places[it] },
            )
            if (placement == TvPlacement.FIXED) {
                val saved = remember(rev) { s.tvBottomPercent }
                var height by remember(saved) { mutableFloatStateOf(saved.toFloat()) }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.settings_position_height), Modifier.weight(1f), style = NinoType.Headline)
                    Text("%${height.roundToInt()}", style = NinoType.Headline, color = NinoColors.InkSecondary)
                }
                NinoSlider(height, { height = it }, valueRange = 0f..85f, onValueChangeFinished = {
                    s.tvBottomPercent = height.roundToInt(); test()
                })
                SmallNote(stringResource(R.string.settings_placement_fixed_note))
            } else {
                SmallNote(stringResource(R.string.settings_placement_note))
            }
        }

        LabeledSwitch(stringResource(R.string.settings_stack_previous), remember(rev) { s.stackPrevious }) { s.stackPrevious = it }
        SmallNote(stringResource(R.string.settings_stack_previous_note))

        if (tvTarget) {
            TileLabel(stringResource(R.string.settings_display_mode))
            val modes = listOf(TvDisplayMode.IN_APP, TvDisplayMode.OVERLAY)
            SegmentedPicker(listOf(stringResource(R.string.settings_display_mode_in_app), stringResource(R.string.settings_display_mode_overlay)),
                modes.indexOf(remember(rev) { s.tvDisplayMode }), { s.tvDisplayMode = modes[it] })
            SmallNote(stringResource(R.string.settings_display_mode_note))
        }

        LabeledSwitch(stringResource(R.string.settings_tv_watermark), remember(rev) { s.tvWatermark }) { s.tvWatermark = it }
        SmallNote(stringResource(R.string.settings_tv_watermark_note))
        LabeledSwitch(stringResource(R.string.settings_screen_on), remember(rev) { s.keepScreenOn }) { s.keepScreenOn = it }
    }
}

@Composable
private fun LabeledSwitch(text: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(role = Role.Switch) { onChange(!checked) }, verticalAlignment = Alignment.CenterVertically) {
        Text(text, Modifier.weight(1f).padding(end = 8.dp), style = NinoType.Headline)
        NinoSwitch(checked, onChange)
    }
}

@Composable
private fun ColorSwatch(fill: Color, selected: Boolean, onClick: () -> Unit) {
    Box(
        Modifier.size(32.dp).clip(CircleShape).background(fill)
            .border(2.dp, if (selected) NinoColors.Accent else NinoColors.BorderStrong, CircleShape)
            .semantics { this.selected = selected }
            .clickable(role = Role.RadioButton, onClick = onClick),
    )
}

@Composable
private fun FontBox(font: SubtitleFont, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val context = LocalContext.current
    val name = stringResource(when (font) {
        SubtitleFont.CONDENSED -> R.string.settings_font_condensed
        SubtitleFont.MODERN -> R.string.settings_font_modern
        SubtitleFont.ROUNDED -> R.string.settings_font_rounded
        SubtitleFont.SYSTEM -> R.string.settings_font_system
    })
    Box(
        modifier.heightIn(min = 48.dp).clip(NinoDimens.ControlShape).background(NinoColors.Raised)
            .border(if (selected) 2.dp else 1.dp, if (selected) NinoColors.Accent else NinoColors.BorderStrong, NinoDimens.ControlShape)
            .semantics { this.selected = selected }
            .clickable(role = Role.RadioButton, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        Text(name, fontFamily = SubtitleFonts.family(context.assets, font), fontWeight = FontWeight.SemiBold, fontSize = 16.sp,
            color = NinoColors.Ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}
