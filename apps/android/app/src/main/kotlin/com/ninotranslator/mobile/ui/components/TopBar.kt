// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.ui.theme.NinoDimens
import com.ninotranslator.mobile.ui.theme.NinoType

/** Uygulama simgesi (`icon.png`), üst çubuğun solunda 36 dp. */
@Composable
fun AppIconImage(modifier: Modifier = Modifier, size: Dp = NinoDimens.AppIcon) {
    Image(painterResource(R.mipmap.icon), contentDescription = null, modifier = modifier.size(size))
}

/**
 * Üst çubuk (§2.2): 44 dp, öğeler arası 12 dp. Solda [onBack] verilmişse geri düğmesi (sağdan sola dillerde ayna ok),
 * yoksa uygulama simgesi. Ortada [title] (22 sp 600, tek satır) ya da boşluk. Sağda [actions], en sağda [onClose]
 * verilmişse kapat (X).
 */
@Composable
fun NinoTopBar(
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
    title: String? = null,
    onClose: (() -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
) {
    Row(
        modifier.fillMaxWidth().height(NinoDimens.TopBarHeight),
        horizontalArrangement = Arrangement.spacedBy(NinoDimens.TileGap),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) {
            NinoIconButton(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back), onBack)
        } else {
            AppIconImage()
        }
        Box(Modifier.weight(1f)) {
            if (title != null) Text(title, style = NinoType.Title, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        actions()
        if (onClose != null) NinoIconButton(Icons.Filled.Close, stringResource(R.string.close), onClose)
    }
}
