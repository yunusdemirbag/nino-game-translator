// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.setup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Gamepad
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.ConsoleKind
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.ui.components.NinoScreen
import com.ninotranslator.mobile.ui.components.NinoTopBar
import com.ninotranslator.mobile.ui.components.PrimaryButton
import com.ninotranslator.mobile.ui.components.ScreenHeader
import com.ninotranslator.mobile.ui.components.SelectableGlassBox
import com.ninotranslator.mobile.ui.components.StageCard
import com.ninotranslator.mobile.ui.navigation.NinoNavigator
import com.ninotranslator.mobile.ui.screens.SmallNote
import com.ninotranslator.mobile.ui.theme.NinoColors

/** Konsol seçimi (ekranlar-2 "Konsol seçimi"): PS5 ya da Xbox; varsayılan PlayStation. */
@Composable
fun ConsoleTypeScreen(nav: NinoNavigator) {
    val initial = Nino.settings.consoleKind ?: ConsoleKind.PLAYSTATION
    var kind by rememberSaveable { mutableStateOfKind(initial) }
    NinoScreen(
        topBar = if (nav.canGoBack()) { { NinoTopBar(onBack = nav::back) } } else null,
        bottom = {
            PrimaryButton(stringResource(R.string.next_continue), {
                Nino.settings.selectConsoleKind(kind)
                nav.finishStep()
            })
        },
    ) {
        ScreenHeader(stringResource(R.string.console_title), body = stringResource(R.string.console_body))
        StageCard(height = 250.dp) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SelectableGlassBox(Icons.Filled.SportsEsports, "PS5", stringResource(R.string.console_ps5_detail),
                    kind == ConsoleKind.PLAYSTATION, { kind = ConsoleKind.PLAYSTATION }, Modifier.weight(1f))
                SelectableGlassBox(Icons.Filled.Gamepad, "Xbox", stringResource(R.string.console_xbox_detail),
                    kind == ConsoleKind.XBOX, { kind = ConsoleKind.XBOX }, Modifier.weight(1f))
            }
        }
        Text(stringResource(if (kind == ConsoleKind.XBOX) R.string.console_xbox_body else R.string.console_ps5_body),
            fontSize = 15.sp, lineHeight = 21.sp, color = NinoColors.InkSecondary)
        if (kind == ConsoleKind.XBOX) SmallNote(stringResource(R.string.xbox_beta_note))
    }
}

private fun mutableStateOfKind(k: ConsoleKind) = androidx.compose.runtime.mutableStateOf(k)
