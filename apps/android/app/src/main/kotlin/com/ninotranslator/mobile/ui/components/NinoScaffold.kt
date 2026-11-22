// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import com.ninotranslator.mobile.ui.theme.NinoDimens
import com.ninotranslator.mobile.ui.theme.ninoScreenBackground

/**
 * Ekran iskeleti (ekranlar-1 §2.1): güvenli alan + 20 dp kenar → [topBar] → 12 dp → kaydırılan [content]
 * (öğeler arası 12 dp) → 12 dp → alta sabit [bottom] bölgesi (öğeler arası 12 dp, ortalı). Zemin: ekran zemini.
 * Klavye açılınca içerik yukarı daralır (imePadding). Tablette içerik en çok [NinoDimens.MaxContentWidth] ortalı.
 *
 * [scrollable] false ise içerik kaydırılmaz ve kalan yüksekliği doldurur (ör. Karşılama'daki yatay sayfalar).
 */
@Composable
fun NinoScreen(
    modifier: Modifier = Modifier,
    topBar: (@Composable () -> Unit)? = null,
    bottom: (@Composable ColumnScope.() -> Unit)? = null,
    scrollable: Boolean = true,
    scrollState: ScrollState = rememberScrollState(),
    maxWidth: Dp = NinoDimens.MaxContentWidth,
    contentSpacing: Dp = NinoDimens.TileGap,
    content: @Composable ColumnScope.() -> Unit,
) {
    Box(modifier.fillMaxSize().ninoScreenBackground()) {
      Box(Modifier.fillMaxSize().safeDrawingPadding().imePadding(), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier
                .widthIn(max = maxWidth + NinoDimens.ScreenPadding * 2)
                .fillMaxSize()
                .padding(NinoDimens.ScreenPadding),
        ) {
            if (topBar != null) {
                topBar()
                Spacer(Modifier.height(NinoDimens.TileGap))
            }
            val inner = Modifier.fillMaxWidth().weight(1f)
            Column(
                if (scrollable) inner.verticalScroll(scrollState) else inner,
                verticalArrangement = Arrangement.spacedBy(contentSpacing),
                content = content,
            )
            if (bottom != null) {
                Spacer(Modifier.height(NinoDimens.TileGap))
                Column(
                    Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(NinoDimens.TileGap),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    content = bottom,
                )
            }
        }
      }
    }
}
