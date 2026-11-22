// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.AreaPreset
import com.ninotranslator.mobile.data.ExtraArea
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.Region
import com.ninotranslator.mobile.service.LiveStatus
import com.ninotranslator.mobile.service.TranslationControl
import com.ninotranslator.mobile.ui.theme.NinoColors
import java.util.UUID
import kotlin.math.roundToInt

/** Bölge önizlemesinde en küçük alan boyu (oran). Tarif sayı vermiyor. */
const val MIN_AREA_SIZE = 0.08

/**
 * Bölge önizlemesi (ekranlar-1 §12.3): 16:9 siyah kutu; çeviri sürüyorsa son oyun karesi, yoksa bilgi yazısı.
 * Üstünde mavi bölge çerçevesi; sağ alt köşenin 32 dp yakınından başlayan sürükleme boyutlandırır, diğeri taşır.
 * Her değişiklik [onChange] ile bildirilir.
 */
@Composable
fun RegionPreview(region: Region, onChange: (Region) -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val live by LiveStatus.state.collectAsState()
    val current by rememberUpdatedState(region)
    val change by rememberUpdatedState(onChange)
    DisposableEffect(Unit) {
        TranslationControl.setPreviewActive(context, true)
        onDispose { TranslationControl.setPreviewActive(context, false) }
    }
    val shape = RoundedCornerShape(16.dp)
    Box(modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(shape).background(Color.Black)) {
        val frame = live.lastFrame
        if (live.running && frame != null) {
            Image(frame.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds)
        } else {
            Text(stringResource(R.string.area_preview_empty), Modifier.align(Alignment.Center).padding(16.dp), fontSize = 13.sp,
                color = NinoColors.InkSecondary, textAlign = TextAlign.Center)
        }
        Canvas(
            Modifier.fillMaxSize().pointerInput(Unit) {
                var resizing = false
                detectDragGestures(
                    onDragStart = { start ->
                        val r = current
                        val corner = Offset((r.right * size.width).toFloat(), (r.bottom * size.height).toFloat())
                        resizing = (start - corner).getDistance() <= 32.dp.toPx()
                    },
                ) { c, d ->
                    c.consume()
                    val r = current
                    val dx = d.x / size.width
                    val dy = d.y / size.height
                    val next = if (resizing) {
                        r.copy(right = (r.right + dx).coerceIn(r.left + MIN_AREA_SIZE, 1.0),
                            bottom = (r.bottom + dy).coerceIn(r.top + MIN_AREA_SIZE, 1.0))
                    } else {
                        val w = r.right - r.left; val h = r.bottom - r.top
                        val l = (r.left + dx).coerceIn(0.0, 1.0 - w); val t = (r.top + dy).coerceIn(0.0, 1.0 - h)
                        Region(t, t + h, l, l + w)
                    }
                    change(next)
                }
            },
        ) {
            val l = (region.left * size.width).toFloat(); val t = (region.top * size.height).toFloat()
            val w = ((region.right - region.left) * size.width).toFloat(); val h = ((region.bottom - region.top) * size.height).toFloat()
            drawRect(NinoColors.Accent.copy(alpha = 0.15f), Offset(l, t), Size(w, h))
            drawRect(NinoColors.Accent, Offset(l, t), Size(w, h), style = Stroke(2.dp.toPx()))
            drawCircle(NinoColors.Accent, 7.dp.toPx(), Offset(l + w, t + h))
        }
    }
}

@Composable
private fun AreaSlider(label: String, value: Int, range: ClosedFloatingPointRange<Float>, onChange: (Int) -> Unit) {
    Column {
        Row {
            Text(label, Modifier.weight(1f), fontSize = 15.sp, color = NinoColors.Ink)
            Text(stringResource(R.string.area_percent, value), fontSize = 15.sp, color = NinoColors.InkSecondary)
        }
        NinoSlider(value.toFloat(), { onChange(it.roundToInt()) }, valueRange = range)
    }
}

/** Altyazı alanı karosu (§12.1). Değişiklikler anında kaydedilir. */
@Composable
fun SubtitleAreaTile(modifier: Modifier = Modifier) {
    val settings = Nino.settings
    val rev by settings.revision.collectAsState()
    val region = remember(rev) { settings.region }
    val preset = remember(rev) { settings.areaPreset }
    val presets = listOf(AreaPreset.BOTTOM, AreaPreset.TOP, AreaPreset.FULL, AreaPreset.CUSTOM)
    NinoTile(modifier) {
        TileLabel(stringResource(R.string.area_title))
        SegmentedPicker(
            listOf(stringResource(R.string.area_bottom), stringResource(R.string.area_top), stringResource(R.string.area_full),
                stringResource(R.string.area_custom)),
            presets.indexOf(preset), { settings.selectAreaPreset(presets[it]) },
        )
        RegionPreview(region, { settings.setCustomRegion(it) })
        if (preset == AreaPreset.CUSTOM) {
            val heightPct = ((region.bottom - region.top) * 100).roundToInt()
            val topPct = (region.top * 100).roundToInt()
            val minPct = (MIN_AREA_SIZE * 100).roundToInt()
            AreaSlider(stringResource(R.string.area_position), topPct, 0f..(100 - heightPct).toFloat().coerceAtLeast(0.01f)) { v ->
                val t = v / 100.0
                settings.setCustomRegion(region.copy(top = t, bottom = (t + heightPct / 100.0).coerceAtMost(1.0)))
            }
            AreaSlider(stringResource(R.string.area_height), heightPct, minPct.toFloat()..100f) { v ->
                val h = v / 100.0
                val t = region.top.coerceAtMost(1.0 - h)
                settings.setCustomRegion(region.copy(top = t, bottom = t + h))
            }
        }
        Text(stringResource(R.string.area_drag_note), fontSize = 13.sp, color = NinoColors.InkSecondary)
    }
}

/** Ek alan türleri ve hazır bölgeleri (§12.2). */
private enum class ExtraKind(val region: Region) { QUEST(Region.QUEST), NOTIFICATION(Region.NOTIFICATION), PHONE(Region.PHONE) }

/** Ek alanlar karosu (§12.2): en çok üç alan; her değişiklik anında kaydedilir. */
@Composable
fun ExtraAreasTile(modifier: Modifier = Modifier) {
    val settings = Nino.settings
    val rev by settings.revision.collectAsState()
    val areas = remember(rev) { settings.extraAreas }
    fun save(list: List<ExtraArea>) { settings.extraAreas = list }
    fun update(a: ExtraArea) = save(areas.map { if (it.id == a.id) a else it })
    val kindNames = listOf(stringResource(R.string.extra_quest), stringResource(R.string.extra_notification), stringResource(R.string.extra_phone))

    NinoTile(modifier) {
        TileLabel(stringResource(R.string.extra_title))
        Text(stringResource(R.string.extra_note), fontSize = 13.sp, color = NinoColors.InkSecondary)
        areas.forEach { area ->
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(NinoColors.Surface2).padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    NinoTextField(area.name, { update(area.copy(name = it)) }, stringResource(R.string.extra_name), Modifier.weight(1f))
                    NinoSwitch(area.enabled, { update(area.copy(enabled = it)) })
                    NinoIconButton(Icons.Filled.Delete, stringResource(R.string.extra_remove), { save(areas.filterNot { it.id == area.id }) })
                }
                val kinds = ExtraKind.entries
                SegmentedPicker(kindNames, kinds.indexOfFirst { area.region.sameAs(it.region) },
                    { update(area.copy(region = kinds[it].region)) })
                RegionPreview(area.region, { update(area.copy(region = it)) }, Modifier.alpha(if (area.enabled) 1f else 0.5f))
            }
        }
        if (areas.size < ExtraArea.MAX) {
            var open by remember { mutableStateOf(false) }
            Box {
                SecondaryButton(stringResource(R.string.extra_add), { open = true })
                DropdownMenu(open, { open = false }, containerColor = NinoColors.Raised) {
                    val titles = listOf(R.string.extra_quest_title, R.string.extra_notification_title, R.string.extra_phone_title)
                    ExtraKind.entries.forEachIndexed { i, kind ->
                        DropdownMenuItem(text = { Text(stringResource(titles[i]), fontSize = 15.sp) }, onClick = {
                            open = false
                            save(areas + ExtraArea(UUID.randomUUID().toString(), kindNames[i], kind.region))
                        })
                    }
                }
            }
        }
    }
}
