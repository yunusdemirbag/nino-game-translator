// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.setup

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material.icons.filled.Tv
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.ui.components.AppIconImage
import com.ninotranslator.mobile.ui.components.GhostButton
import com.ninotranslator.mobile.ui.components.GlassOptionBox
import com.ninotranslator.mobile.ui.components.GlassRow
import com.ninotranslator.mobile.ui.components.LanguagePicker
import com.ninotranslator.mobile.ui.components.NinoScreen
import com.ninotranslator.mobile.ui.components.PrimaryButton
import com.ninotranslator.mobile.ui.components.ScreenHeader
import com.ninotranslator.mobile.ui.components.StageCard
import com.ninotranslator.mobile.ui.navigation.NinoNavigator
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoDimens
import kotlinx.coroutines.launch

/** Karşılama (ekranlar-1 §6.1): üç yatay sayfa, dil seçici, "Atla", sayfa noktaları. */
@Composable
fun WelcomeScreen(nav: NinoNavigator) {
    val settings = Nino.settings
    val language by remember { settings.watch { it.targetLanguage } }.collectAsState(settings.targetLanguage)
    // Hazır paketler yalnız Türkçe: paket sayfası yalnız çeviri dili Türkçeyken görünür (eskisinden farklı, bilinçli).
    val pages = if (language == "tr") listOf(0, 1, 2) else listOf(0, 2)
    val pager = rememberPagerState { pages.size }
    val scope = rememberCoroutineScope()
    val last = pager.currentPage == pages.size - 1

    fun finish() {
        settings.welcomeSeen = true
        nav.finishStep()
    }

    NinoScreen(
        scrollable = false,
        topBar = {
            // Arapça arayüzde de soldan sağa dizilir.
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                Row(Modifier.fillMaxWidth().height(NinoDimens.TopBarHeight), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(NinoDimens.TileGap)) {
                    AppIconImage()
                    Spacer(Modifier.weight(1f))
                    LanguagePicker(language, onSelect = { settings.targetLanguage = it })
                    if (!last) GhostButton(stringResource(R.string.skip), ::finish)
                }
            }
        },
        bottom = {
            PageDots(count = pages.size, current = pager.currentPage)
            PrimaryButton(stringResource(if (last) R.string.welcome_start else R.string.next), onClick = {
                if (last) finish() else scope.launch { pager.animateScrollToPage(pager.currentPage + 1) }
            })
        },
    ) {
        HorizontalPager(pager, Modifier.fillMaxWidth().weight(1f), pageSpacing = 20.dp) { index ->
            WelcomePage {
                when (pages.getOrElse(index) { 2 }) {
                    0 -> {
                        SampleSubtitleScene(language)
                        Spacer(Modifier.height(12.dp))
                        ScreenHeader(stringResource(R.string.welcome1_title), body = stringResource(R.string.welcome1_body))
                    }
                    1 -> {
                        StageCard {
                            val free = stringResource(R.string.packs_free)
                            GlassRow("Grand Theft Auto V", stringResource(R.string.welcome2_gta), badge = "GTA", tag = free)
                            GlassRow("Red Dead Redemption 2", stringResource(R.string.welcome2_rdr_lines), badge = "RDR", tag = free)
                            GlassRow("Mafia", stringResource(R.string.welcome2_maf_lines), badge = "MAF", tag = free)
                        }
                        Spacer(Modifier.height(12.dp))
                        ScreenHeader(stringResource(R.string.welcome2_title), body = stringResource(R.string.welcome2_body))
                    }
                    else -> {
                        StageCard {
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                GlassOptionBox(Icons.Filled.Tv, stringResource(R.string.welcome3_tv),
                                    stringResource(R.string.welcome3_tv_label), Modifier.weight(1f))
                                GlassOptionBox(Icons.Filled.Smartphone, stringResource(R.string.welcome3_phone),
                                    stringResource(R.string.welcome3_phone_label), Modifier.weight(1f))
                            }
                            GlassRow(stringResource(R.string.welcome3_wifi), stringResource(R.string.welcome3_wifi_body))
                        }
                        Spacer(Modifier.height(12.dp))
                        ScreenHeader(stringResource(R.string.welcome3_title), body = stringResource(R.string.welcome3_body))
                    }
                }
            }
        }
    }
}

/** Sayfa içeriği aşağıya yaslı; sığmazsa kaydırılır. */
@Composable
private fun WelcomePage(content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val min = maxHeight
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            Column(Modifier.fillMaxWidth().heightIn(min = min), verticalArrangement = Arrangement.Bottom, content = content)
        }
    }
}

/** Sayfa noktaları: etkin sayfa 24×8 dp mürekkep hap, diğerleri 8×8 dp %18 daire, aralar 8 dp. */
@Composable
fun PageDots(count: Int, current: Int, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (i in 0 until count) {
            val active = i == current
            val w by animateDpAsState(if (active) 24.dp else 8.dp, label = "dot")
            Box(Modifier.size(width = w, height = 8.dp).clip(RoundedCornerShape(50))
                .background(if (active) NinoColors.Ink else NinoColors.Ink.copy(alpha = 0.18f)))
        }
    }
}

