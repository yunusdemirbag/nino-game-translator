// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoDimens
import com.ninotranslator.mobile.ui.theme.NinoType
import com.ninotranslator.mobile.ui.theme.pressScale

private val Pill = RoundedCornerShape(50)

/**
 * Simge düğmesi (§2.3): 44 dp beyaz daire, 1 dp güçlü kenar, ortada 20 dp mürekkep simge. Basma ışığı daire içinde.
 * [contentDescription] erişilebilirlik adıdır (ör. `R.string.back`).
 */
@Composable
fun NinoIconButton(
    icon: ImageVector,
    contentDescription: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: androidx.compose.ui.unit.Dp = NinoDimens.IconButton,
    iconSize: androidx.compose.ui.unit.Dp = 20.dp,
    tint: Color = NinoColors.Ink,
    background: Color = NinoColors.Raised,
    border: Color? = NinoColors.BorderStrong,
) {
    Box(
        modifier
            .size(size)
            .clip(CircleShape)
            .background(background)
            .let { if (border != null) it.border(1.dp, border, CircleShape) else it }
            .clickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription, Modifier.size(iconSize), tint = tint)
    }
}

/**
 * Birincil düğme (§2.4): tam genişlik, 58 dp hap, koyu degrade, beyaz yazı, koyu gölge, basılıyken %97.
 * Pasifken açık zemin, ikincil yazı, gölgesiz.
 */
@Composable
fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    val interaction = remember { MutableInteractionSource() }
    val base = modifier
        .fillMaxWidth()
        .height(NinoDimens.ButtonHeight)
        .pressScale(interaction, enabled)
    val styled = if (enabled) {
        base.shadow(18.dp, Pill, ambientColor = NinoColors.Ink.copy(alpha = 0.5f), spotColor = NinoColors.Ink.copy(alpha = 0.6f))
            .clip(Pill)
            .background(Brush.verticalGradient(listOf(NinoColors.PrimaryTop, NinoColors.Ink)))
            .border(1.dp, Color.White.copy(alpha = 0.14f), Pill)
    } else {
        base.clip(Pill).background(NinoColors.Surface2).border(1.dp, NinoColors.BorderStrong, Pill)
    }
    Box(
        styled.clickable(interaction, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 20.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = NinoType.Headline, color = if (enabled) Color.White else NinoColors.InkSecondary,
            maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
    }
}

/** İkincil düğme (§2.4): tam genişlik, 58 dp hap, beyaz zemin, güçlü kenar, mürekkep yazı, gölgesiz. */
@Composable
fun SecondaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    Box(
        modifier
            .fillMaxWidth()
            .height(NinoDimens.ButtonHeight)
            .clip(Pill)
            .background(NinoColors.Raised)
            .border(1.dp, NinoColors.BorderStrong, Pill)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 20.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = NinoType.Headline, color = if (enabled) NinoColors.Ink else NinoColors.InkSecondary,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Metin (hayalet) düğme (§2.4): 44 dp yükseklik, yalnız yazı 17 sp 600, varsayılan vurgu yazısı rengi. */
@Composable
fun GhostButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    color: Color = NinoColors.AccentText,
    enabled: Boolean = true,
) {
    Box(
        modifier
            .heightIn(min = NinoDimens.GhostButtonHeight)
            .clip(Pill)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = NinoType.Headline, color = if (enabled) color else NinoColors.InkSecondary,
            textAlign = TextAlign.Center)
    }
}

/** Tehlikeli düğme (§2.4): 52 dp, 16 dp köşe, açık kırmızı zemin, kırmızı yazı. */
@Composable
fun DangerButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    Box(
        modifier
            .fillMaxWidth()
            .height(52.dp)
            .clip(NinoDimens.ControlShape)
            .background(NinoColors.DangerBackground)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = NinoType.Headline, color = NinoColors.Danger)
    }
}

/** Kare simge + yazı, hap biçimli küçük metin düğmesi ("PS5'siz Deneyin" gibi). */
@Composable
fun IconTextButton(
    icon: ImageVector,
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    color: Color = NinoColors.AccentText,
) {
    androidx.compose.foundation.layout.Row(
        modifier
            .heightIn(min = 48.dp)
            .clip(Pill)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, Modifier.size(20.dp), tint = color)
        androidx.compose.foundation.layout.Spacer(Modifier.size(8.dp))
        Text(text, style = NinoType.Headline, color = color)
    }
}

