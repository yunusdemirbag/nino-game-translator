// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.history

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.HistoryEntry
import com.ninotranslator.mobile.data.HistoryOrigin
import com.ninotranslator.mobile.data.HistoryStore
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.ui.components.DangerButton
import com.ninotranslator.mobile.ui.components.NinoScreen
import com.ninotranslator.mobile.ui.components.NinoTile
import com.ninotranslator.mobile.ui.components.NinoTopBar
import com.ninotranslator.mobile.ui.components.SecondaryButton
import com.ninotranslator.mobile.ui.screens.ConfirmDialog
import com.ninotranslator.mobile.ui.screens.Screens
import com.ninotranslator.mobile.ui.screens.SmallNote
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoType
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val TIME = DateTimeFormatter.ofPattern("HH:mm:ss").withZone(ZoneId.systemDefault())

/** Düz metin kopyası (servis.md §11): "[SS:DD:ss] çeviri" ve altında kaynak, satırlar arası boş satır. */
fun historyPlainText(list: List<HistoryEntry>): String =
    list.joinToString("\n\n") { "[${TIME.format(Instant.ofEpochMilli(it.dateMs))}] ${it.translation}\n${it.source}" }

/** Geçmiş (ekranlar-2 "Geçmiş"): bu ve önceki oturumlarda çevrilen satırlar, en yenisi üstte. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun HistoryScreen(nav: com.ninotranslator.mobile.ui.navigation.NinoNavigator) {
    val context = LocalContext.current
    val entries by Nino.history.entries.collectAsState()
    var copiedFor by remember { mutableStateOf<List<HistoryEntry>?>(null) }
    var confirm by remember { mutableStateOf(false) }
    val list = remember(entries) { entries.sortedByDescending { it.dateMs } }

    NinoScreen(
        topBar = { NinoTopBar(onBack = nav::back, title = stringResource(R.string.history)) },
        scrollable = false,
        bottom = if (list.isEmpty()) null else {
            {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    SecondaryButton(stringResource(if (copiedFor === entries) R.string.history_copied else R.string.history_copy_all), {
                        Screens.copy(context, historyPlainText(list)); copiedFor = entries
                    }, Modifier.weight(1f))
                    DangerButton(stringResource(R.string.history_clear), { confirm = true }, Modifier.weight(1f).padding(top = 3.dp))
                }
            }
        },
    ) {
        SmallNote(stringResource(R.string.history_note, HistoryStore.MAX_ENTRIES))
        if (list.isEmpty()) {
            Text(stringResource(R.string.history_empty), style = NinoType.Body, color = NinoColors.InkSecondary)
        } else {
            NinoTile(Modifier.weight(1f), contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp, vertical = 4.dp)) {
                LazyColumn(Modifier.fillMaxWidth()) {
                    items(list, key = { it.id }) { e ->
                        Column(
                            Modifier.fillMaxWidth()
                                .combinedClickable(onClick = {}, onLongClick = { Screens.copy(context, "${e.translation}\n${e.source}") })
                                .padding(vertical = 10.dp),
                            verticalArrangement = Arrangement.spacedBy(2.dp),
                        ) {
                            val pack = e.origin == HistoryOrigin.PACK
                            Text("${TIME.format(Instant.ofEpochMilli(e.dateMs))} · " +
                                stringResource(if (pack) R.string.history_pack else R.string.history_engine),
                                fontFamily = FontFamily.Monospace, fontSize = 12.sp,
                                color = if (pack) NinoColors.PackDark else NinoColors.InkSecondary)
                            Text(e.translation, style = NinoType.Body)
                            SmallNote(e.source)
                        }
                    }
                }
            }
        }
    }
    if (confirm) {
        ConfirmDialog(stringResource(R.string.history_clear_title), stringResource(R.string.history_clear_body),
            stringResource(R.string.history_clear), { Nino.history.clear(); confirm = false }, { confirm = false })
    }
}
