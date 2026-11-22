// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoDimens
import com.ninotranslator.mobile.ui.theme.NinoType
import com.ninotranslator.mobile.ui.theme.pressScale

/**
 * Karo (§2.5): 22 dp köşe, beyaz %85 zemin, 1 dp beyaz %75 kenar, yumuşak lacivert gölge, iç boşluk 16 dp, öğeler
 * arası 8 dp. [selected] = etkin (1,5 dp mavi kenar). [onClick] verilirse basılabilir ve basılıyken %97.
 * [dimmed] = sönük (%40 opak).
 */
@Composable
fun NinoTile(
    modifier: Modifier = Modifier,
    selected: Boolean = false,
    dimmed: Boolean = false,
    onClick: (() -> Unit)? = null,
    contentPadding: androidx.compose.foundation.layout.PaddingValues =
        androidx.compose.foundation.layout.PaddingValues(NinoDimens.TilePadding),
    spacing: androidx.compose.ui.unit.Dp = NinoDimens.InnerGap,
    content: @Composable ColumnScope.() -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val shape = NinoDimens.TileShape
    var m = modifier.fillMaxWidth()
    if (onClick != null) m = m.pressScale(interaction)
    m = m.alpha(if (dimmed) 0.4f else 1f)
        .shadow(14.dp, shape, ambientColor = NinoColors.PackDark.copy(alpha = 0.10f), spotColor = NinoColors.PackDark.copy(alpha = 0.10f))
        .clip(shape)
        .background(NinoColors.Surface)
        .border(if (selected) 1.5.dp else 1.dp, if (selected) NinoColors.Accent else NinoColors.Border, shape)
    if (onClick != null) m = m.clickable(interaction, indication = null, role = Role.Button, onClick = onClick)
    Column(m.padding(contentPadding), verticalArrangement = Arrangement.spacedBy(spacing), content = content)
}

/** Karo etiketi: 13 sp 500 ikincil. */
@Composable
fun TileLabel(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier, style = NinoType.Caption, color = NinoColors.InkSecondary)
}

/** Karo simgesi: 28 dp açık mavi daire içinde 16 dp simge (varsayılan vurgu yazısı rengi). */
@Composable
fun TileIcon(icon: ImageVector, modifier: Modifier = Modifier, tint: Color = NinoColors.AccentText) {
    Box(modifier.size(28.dp).clip(CircleShape).background(NinoColors.AccentSoft), contentAlignment = Alignment.Center) {
        Icon(icon, null, Modifier.size(16.dp), tint = tint)
    }
}

/**
 * Not/uyarı karosu (§2.5). [warning] true: solda uyarı simgesi, yazı uyarı renginde. false: bilgi notu, ikincil renk,
 * simgesiz.
 */
@Composable
fun NoteTile(text: String, modifier: Modifier = Modifier, warning: Boolean = true) {
    NinoTile(modifier) {
        Row(horizontalArrangement = Arrangement.spacedBy(NinoDimens.InnerGap), verticalAlignment = Alignment.CenterVertically) {
            if (warning) TileIcon(Icons.Filled.Warning, tint = NinoColors.Warning)
            Text(text, Modifier.weight(1f), style = NinoType.Body,
                color = if (warning) NinoColors.Warning else NinoColors.InkSecondary)
        }
    }
}

/** Satır listesi (§2.5): tek karo, satırlar arası 1 dp ayraç; iç boşluk yatay 16, dikey 4 dp. */
@Composable
fun RowList(modifier: Modifier = Modifier, rows: List<@Composable () -> Unit>) {
    NinoTile(modifier, contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp, vertical = 4.dp),
        spacing = 0.dp) {
        rows.forEachIndexed { i, row ->
            if (i > 0) HorizontalDivider(thickness = 1.dp, color = NinoColors.Border)
            row()
        }
    }
}

/**
 * Satır (§2.5): en az 52 dp; solda [title] (17 sp 600) ve altında [value] (13 sp ikincil); sağda isteğe bağlı
 * [trailing]. [onClick] verilirse tüm satır basılır.
 */
@Composable
fun NinoRow(
    title: String,
    modifier: Modifier = Modifier,
    value: String? = null,
    onClick: (() -> Unit)? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
) {
    var m = modifier.fillMaxWidth().heightIn(min = NinoDimens.RowMinHeight)
    if (onClick != null) m = m.clickable(role = Role.Button, onClick = onClick)
    Row(m.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(NinoDimens.InnerGap)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = NinoType.Headline)
            if (value != null) Text(value, style = NinoType.Caption.copy(fontWeight = null), color = NinoColors.InkSecondary)
        }
        trailing?.invoke(this)
    }
}

/**
 * Durum karosu (§2.15): üst satırda isteğe bağlı karo simgesi + [name] (13 sp ikincil) + sağda [status]; altında
 * [value] (22 sp 600, en çok 2 satır); altında isteğe bağlı [note]. [selected] mavi kenar, [dimmed] %40.
 */
@Composable
fun StatusTile(
    name: String,
    value: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    note: String? = null,
    selected: Boolean = false,
    dimmed: Boolean = false,
    onClick: (() -> Unit)? = null,
    status: (@Composable () -> Unit)? = null,
) {
    NinoTile(modifier, selected = selected, dimmed = dimmed, onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(NinoDimens.InnerGap)) {
            if (icon != null) TileIcon(icon)
            Text(name, Modifier.weight(1f), style = NinoType.Caption.copy(fontWeight = null), color = NinoColors.InkSecondary,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            status?.invoke()
        }
        Text(value, style = NinoType.Title, maxLines = 2, overflow = TextOverflow.Ellipsis)
        if (note != null) Text(note, style = NinoType.Caption.copy(fontWeight = null), color = NinoColors.InkSecondary)
    }
}

/** Seçili işareti (§2.15): 20 dp mavi daire içinde 14 dp beyaz onay; erişilebilirlik adı "Seçili". */
@Composable
fun SelectedMark(modifier: Modifier = Modifier) {
    val label = stringResource(R.string.selected)
    Box(modifier.size(20.dp).clip(CircleShape).background(NinoColors.Accent).semantics { contentDescription = label },
        contentAlignment = Alignment.Center) {
        Icon(Icons.Filled.Check, null, Modifier.size(14.dp), tint = Color.White)
    }
}

/** Ortası yazılı ayraç (§2.15): iki yanda ince güçlü kenar çizgisi, ortada 13 sp ikincil yazı, aralar 12 dp. */
@Composable
fun LabeledDivider(text: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        HorizontalDivider(Modifier.weight(1f), thickness = 1.dp, color = NinoColors.BorderStrong)
        Text(text, fontSize = 13.sp, color = NinoColors.InkSecondary)
        HorizontalDivider(Modifier.weight(1f), thickness = 1.dp, color = NinoColors.BorderStrong)
    }
}

/**
 * İki sütun (§2.15): iki eşit genişlikte öğe yan yana, 12 dp ara, aynı yükseklikte. [second] null ise ilk öğe yarım
 * genişlikte kalır. Öğeler `Modifier.fillMaxHeight()` almalı (verilen modifier ile).
 */
@Composable
fun TwoColumns(
    modifier: Modifier = Modifier,
    first: @Composable (Modifier) -> Unit,
    second: (@Composable (Modifier) -> Unit)?,
) {
    Row(modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(NinoDimens.TileGap)) {
        first(Modifier.weight(1f).fillMaxHeight())
        if (second != null) second(Modifier.weight(1f).fillMaxHeight()) else Spacer(Modifier.weight(1f))
    }
}

/** Küçük yatay boşluk yardımcısı. */
@Composable
fun HSpace(width: androidx.compose.ui.unit.Dp) = Spacer(Modifier.width(width))

/** Küçük dikey boşluk yardımcısı. */
@Composable
fun VSpace(height: androidx.compose.ui.unit.Dp) = Spacer(Modifier.height(height))
