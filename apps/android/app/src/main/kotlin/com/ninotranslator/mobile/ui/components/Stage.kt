// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoDimens

private val White = Color.White

/** Koyu sahne kartının ortak zemini: gölge, degrade, degrade kenar (§2.14). Sahne kartı ve canlı sahne kullanır. */
fun Modifier.stageSurface(radius: Dp = NinoDimens.StageRadius): Modifier {
    val shape = RoundedCornerShape(radius)
    return this
        .shadow(28.dp, shape, ambientColor = NinoColors.Ink.copy(alpha = 0.5f), spotColor = NinoColors.Ink.copy(alpha = 0.5f))
        .clip(shape)
        .background(Brush.verticalGradient(listOf(NinoColors.StageTop, NinoColors.StageBottom)))
        .border(BorderStroke(1.dp, Brush.verticalGradient(listOf(White.copy(alpha = 0.22f), White.copy(alpha = 0.03f)))), shape)
}

/**
 * Koyu sahne kartı (§2.14): tam genişlik, [height] (varsayılan 380 dp), 28 dp köşe, koyu degrade. İç boşluk 16,
 * içerik dikeyde ortalı, aralar 10 dp. [overlay] kartın üstüne serbest çizim için (ör. ışık, rozet).
 */
@Composable
fun StageCard(
    modifier: Modifier = Modifier,
    height: Dp = 380.dp,
    overlay: @Composable BoxScope.() -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    Box(modifier.fillMaxWidth().height(height).stageSurface()) {
        overlay()
        Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically),
            content = content)
    }
}

private val GlassRowShape = RoundedCornerShape(18.dp)

/**
 * Cam satır (§2.14): beyaz %8 zemin, 18 dp köşe, 1 dp beyaz %12 kenar. Solda isteğe bağlı [badge] (40 dp kısaltma
 * rozeti), ortada [title] (15 sp 600 tek satır) ve [subtitle] (12 sp beyaz %60 tek satır), sağda isteğe bağlı
 * yeşil [tag].
 */
@Composable
fun GlassRow(
    title: String,
    subtitle: String,
    modifier: Modifier = Modifier,
    badge: String? = null,
    tag: String? = null,
) {
    GlassRowFrame(modifier) {
        if (badge != null) {
            Box(Modifier.size(40.dp).clip(RoundedCornerShape(12.dp)).background(White.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center) {
                Text(badge, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = White, maxLines = 1)
            }
        }
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = White, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle, fontSize = 12.sp, color = White.copy(alpha = 0.6f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (tag != null) {
            Box(Modifier.clip(RoundedCornerShape(50)).background(NinoColors.LiveGreen.copy(alpha = 0.25f))
                .padding(horizontal = 10.dp, vertical = 4.dp)) {
                Text(tag, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = White, maxLines = 1)
            }
        }
    }
}

/**
 * Simgeli cam satır (§2.14): rozet yerine 40 dp beyaz %12 daire içinde 20 dp beyaz simge; açıklama çok satırlı,
 * etiket yok (PSN ekranındaki güvence satırları).
 */
@Composable
fun GlassIconRow(icon: ImageVector, title: String, subtitle: String, modifier: Modifier = Modifier) {
    GlassRowFrame(modifier) {
        Box(Modifier.size(40.dp).clip(CircleShape).background(White.copy(alpha = 0.12f)), contentAlignment = Alignment.Center) {
            Icon(icon, null, Modifier.size(20.dp), tint = White)
        }
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = White, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle, fontSize = 12.sp, color = White.copy(alpha = 0.6f))
        }
    }
}

@Composable
private fun GlassRowFrame(modifier: Modifier, content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    Row(
        modifier.fillMaxWidth().clip(GlassRowShape).background(White.copy(alpha = 0.08f))
            .border(1.dp, White.copy(alpha = 0.12f), GlassRowShape)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

private val GlassBoxShape = RoundedCornerShape(20.dp)

/**
 * Cam seçenek kutusu (§2.14): beyaz %8 zemin, 20 dp köşe, iç boşluk 16, aralar 8. Üstte 40 dp daire içinde 22 dp
 * beyaz [icon], altında [name] (20 sp kalın), altında [detail] (12 sp beyaz %60).
 */
@Composable
fun GlassOptionBox(icon: ImageVector, name: String, detail: String, modifier: Modifier = Modifier) {
    Column(
        modifier.clip(GlassBoxShape).background(White.copy(alpha = 0.08f)).border(1.dp, White.copy(alpha = 0.12f), GlassBoxShape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        GlassBoxContent(icon, name, detail, maxDetailLines = Int.MAX_VALUE)
    }
}

/**
 * Seçilebilir cam kutu (§2.14): 190 dp sabit yükseklik; seçiliyken beyaz %16 zemin ve 2 dp beyaz %85 kenar, sağ üstte
 * 24 dp beyaz daire içinde onay; değilken beyaz %6 ve 1 dp beyaz %12. Açıklama en çok 3 satır. Dokununca [onSelect].
 */
@Composable
fun SelectableGlassBox(
    icon: ImageVector,
    name: String,
    detail: String,
    selected: Boolean,
    onSelect: () -> Unit,
    modifier: Modifier = Modifier,
    height: Dp = 190.dp,
) {
    Box(
        modifier.height(height).clip(GlassBoxShape)
            .background(White.copy(alpha = if (selected) 0.16f else 0.06f))
            .border(if (selected) 2.dp else 1.dp, White.copy(alpha = if (selected) 0.85f else 0.12f), GlassBoxShape)
            .semantics { this.selected = selected }
            .clickable(role = Role.RadioButton, onClick = onSelect),
    ) {
        Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            GlassBoxContent(icon, name, detail, maxDetailLines = 3)
        }
        if (selected) {
            Box(Modifier.align(Alignment.TopEnd).padding(12.dp).size(24.dp).clip(CircleShape).background(White),
                contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Check, null, Modifier.size(16.dp), tint = NinoColors.Ink)
            }
        }
    }
}

@Composable
private fun GlassBoxContent(icon: ImageVector, name: String, detail: String, maxDetailLines: Int) {
    Box(Modifier.size(40.dp).clip(CircleShape).background(White.copy(alpha = 0.12f)), contentAlignment = Alignment.Center) {
        Icon(icon, null, Modifier.size(22.dp), tint = White)
    }
    Text(name, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = White, maxLines = 1, overflow = TextOverflow.Ellipsis)
    Text(detail, fontSize = 12.sp, lineHeight = 16.sp, color = White.copy(alpha = 0.6f), maxLines = maxDetailLines,
        overflow = TextOverflow.Ellipsis)
}
