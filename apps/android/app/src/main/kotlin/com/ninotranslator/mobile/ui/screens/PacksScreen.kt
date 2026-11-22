// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.packs.PackInfo
import com.ninotranslator.mobile.packs.Packs
import com.ninotranslator.mobile.service.LiveStatus
import com.ninotranslator.mobile.ui.components.NinoRow
import com.ninotranslator.mobile.ui.components.NinoSwitch
import com.ninotranslator.mobile.ui.components.NinoScreen
import com.ninotranslator.mobile.ui.components.NinoTag
import com.ninotranslator.mobile.ui.components.NinoTile
import com.ninotranslator.mobile.ui.components.NinoTopBar
import com.ninotranslator.mobile.ui.components.NoteTile
import com.ninotranslator.mobile.ui.components.PackTile
import com.ninotranslator.mobile.ui.components.RowList
import com.ninotranslator.mobile.ui.components.SecondaryButton
import com.ninotranslator.mobile.ui.components.TagStyle
import com.ninotranslator.mobile.ui.components.TileIcon
import com.ninotranslator.mobile.ui.components.TwoColumns
import com.ninotranslator.mobile.ui.navigation.NinoNavigator
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoDimens
import com.ninotranslator.mobile.ui.theme.NinoType
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlin.math.roundToInt

/** Paket karosundaki kısaltma ve kısa ad (ekranlar-1 §8). */
object PackNames {
    fun abbreviationAndShort(title: String): Pair<String, String> {
        val t = title.lowercase()
        return when {
            t == "gta v" || t.contains("grand theft auto v") -> "GTA" to "GTA V"
            t.contains("red dead redemption 2") -> "RDR" to "Red Dead 2"
            t.contains("mafia: the old country") -> "MAF" to "Mafia: TOC"
            t.contains("assassin's creed shadows") || t.contains("assassin’s creed shadows") -> "ACS" to "AC Shadows"
            t.contains("death stranding 2") -> "DS2" to "Death Str. 2"
            t.contains("modern warfare") && t.contains("2019") -> "MW" to "CoD MW 2019"
            else -> title.filter { it.isLetterOrDigit() }.take(3).uppercase() to title
        }
    }
}

/** Satır sayısı yazısı: 1000 ve üstü en yakın bine yuvarlanır. */
@Composable
fun lineCountText(count: Int): String =
    if (count >= 1000) stringResource(R.string.lines_thousands, (count / 1000.0).roundToInt())
    else stringResource(R.string.lines_count, count)

/** Oyun paketleri (ekranlar-1 §8) ve içe aktarılan paketler bölümü (ekranlar-2). */
@Composable
fun PacksScreen(nav: NinoNavigator) {
    val settings = Nino.settings
    val catalog = Packs.catalog
    val state by catalog.state.collectAsState()
    val rev by settings.revision.collectAsState()
    val playingId by remember { LiveStatus.state.map { it.packId }.distinctUntilChanged() }.collectAsState(null)
    val enabled = remember(rev) { settings.packsEnabled }
    val disabled = remember(rev) { settings.disabledPacks }
    LaunchedEffect(Unit) { catalog.refresh(force = false) }

    NinoScreen(
        topBar = {
            NinoTopBar(onBack = nav::back, title = stringResource(R.string.packs_title), actions = {
                val count = state.packs.size
                NinoTag(if (count == 0) stringResource(R.string.packs_free) else stringResource(R.string.packs_free_count, count),
                    style = TagStyle.PACK)
            })
        },
        bottom = { SecondaryButton(stringResource(R.string.packs_refresh), { catalog.refresh(force = true) }) },
    ) {
        Text(stringResource(R.string.packs_auto), style = NinoType.Body, color = NinoColors.InkSecondary)
        RowList(rows = listOf {
            NinoRow(stringResource(R.string.settings_packs), value = stringResource(R.string.packs_switch_note),
                onClick = { settings.packsEnabled = !enabled }) {
                NinoSwitch(enabled, { settings.packsEnabled = it })
            }
        })
        when {
            state.loading -> Text(stringResource(R.string.packs_loading), style = NinoType.Body, color = NinoColors.InkSecondary)
            state.packs.isEmpty() -> NoteTile(stringResource(R.string.packs_none_yet), warning = false)
            else -> state.packs.chunked(2).forEach { pair ->
                val other = pair.getOrNull(1)
                val second: (@Composable (Modifier) -> Unit)? =
                    if (other == null) null else { m -> PackCard(other, enabled, disabled, playingId, m) }
                TwoColumns(first = { m -> PackCard(pair[0], enabled, disabled, playingId, m) }, second = second)
            }
        }
        PackImportSection(state.imported)
        NinoTile {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(NinoDimens.InnerGap)) {
                TileIcon(Icons.Filled.Refresh)
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.packs_next), style = NinoType.Headline)
                    Text(stringResource(R.string.packs_next_note), fontSize = 13.sp, color = NinoColors.InkSecondary)
                }
            }
        }
    }
}

@Composable
private fun PackCard(pack: PackInfo, allEnabled: Boolean, disabled: Set<String>, playingId: String?, modifier: Modifier) {
    val settings = Nino.settings
    val (abbr, short) = PackNames.abbreviationAndShort(pack.title)
    // Aynı oyunun bütün paketleri ([PackInfo.ids]) birlikte açılıp kapanır.
    val off = pack.ids.all { it in disabled }
    val now = playingId != null && playingId in pack.ids
    PackTile(
        abbr, short, lineCountText(pack.lineCount), modifier,
        selected = now,
        dimmed = !allEnabled || off,
        onClick = { settings.disabledPacks = if (off) disabled - pack.ids.toSet() else disabled + pack.ids },
        status = when {
            now -> { { Text(stringResource(R.string.packs_now), fontSize = 13.sp, fontWeight = FontWeight.Medium, color = NinoColors.Success) } }
            off && allEnabled -> { { NinoTag(stringResource(R.string.packs_off)) } }
            else -> null
        },
    )
}
