// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.profile

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Tv
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.SubtitleTarget
import com.ninotranslator.mobile.tv.FoundTv
import com.ninotranslator.mobile.tv.TvFinders
import com.ninotranslator.mobile.ui.components.NinoIconButton
import com.ninotranslator.mobile.ui.components.NinoRow
import com.ninotranslator.mobile.ui.components.NinoScreen
import com.ninotranslator.mobile.ui.components.NinoSwitch
import com.ninotranslator.mobile.ui.components.NinoTag
import com.ninotranslator.mobile.ui.components.NinoTile
import com.ninotranslator.mobile.ui.components.NinoTopBar
import com.ninotranslator.mobile.ui.components.RowList
import com.ninotranslator.mobile.ui.components.StatusTile
import com.ninotranslator.mobile.ui.components.TileLabel
import com.ninotranslator.mobile.ui.components.TwoColumns
import com.ninotranslator.mobile.ui.navigation.NinoNavigator
import com.ninotranslator.mobile.ui.navigation.Routes
import com.ninotranslator.mobile.ui.screens.Screens
import com.ninotranslator.mobile.ui.screens.SmallNote
import androidx.compose.material3.Text
import com.ninotranslator.mobile.ui.theme.NinoType

/**
 * Profil (ekranlar-2 "Profil"): cihazlar ve tercihler; hesap yoktur. Anahtarlar dokunulduğu an kaydeder.
 * "Kullanım verisi" satırı yok (kullanıcı kararı: ölçümün kapatma düğmesi yok).
 */
@Composable
fun ProfileScreen(nav: NinoNavigator) {
    val context = LocalContext.current
    val settings = Nino.settings
    val secrets = Nino.secrets
    val rev by settings.revision.collectAsState()
    val secretRev by secrets.revision.collectAsState()
    val ps5Name = remember(secretRev) { secrets.console?.name }
    val psnLinked = remember(secretRev) { secrets.accountId != null }
    val target = remember(rev) { settings.target }
    val tvName = remember(rev) { settings.tvName }

    var searching by remember { mutableStateOf(true) }
    var found by remember { mutableStateOf<List<FoundTv>>(emptyList()) }
    LaunchedEffect(Unit) {
        found = runCatching { TvFinders.current.search() }.getOrDefault(emptyList())
        searching = false
    }

    NinoScreen(topBar = {
        NinoTopBar(onBack = nav::back, title = stringResource(R.string.profile), actions = {
            NinoIconButton(Icons.Filled.Settings, stringResource(R.string.settings), { nav.open(Routes.SETTINGS) })
        })
    }) {
        TwoColumns(
            first = { m ->
                StatusTile("PS5", ps5Name ?: stringResource(R.string.profile_not_paired), m, icon = Icons.Filled.Tv,
                    onClick = nav::openPairing,
                    status = if (ps5Name != null) { { NinoTag(stringResource(R.string.main_paired)) } } else null)
            },
            second = { m ->
                StatusTile(stringResource(R.string.profile_psn),
                    stringResource(if (psnLinked) R.string.profile_psn_linked_short else R.string.profile_psn_missing), m,
                    icon = Icons.Filled.Person, onClick = { nav.open(Routes.PSN_SIGN_IN) })
            },
        )

        NinoTile(onClick = { nav.open(Routes.TARGET) }) {
            TileLabel(stringResource(R.string.profile_tvs))
            Text(
                if (target == SubtitleTarget.TV) tvName ?: stringResource(R.string.main_target_tv) else stringResource(R.string.main_target_phone),
                style = NinoType.Title,
            )
            SmallNote(when {
                searching -> stringResource(R.string.target_searching)
                found.isEmpty() -> stringResource(R.string.target_tvs_none)
                else -> found.joinToString(", ") { tv -> tv.brand?.let { "${tv.name} (${Screens.brandName(it)})" } ?: tv.name }
            })
        }

        RowList(rows = listOf {
            NinoRow(stringResource(R.string.tv_install_button), value = stringResource(R.string.tv_install_row_note),
                onClick = { nav.open(Routes.tvInstall()) })
        })

        val notifyDisconnect = remember(rev) { settings.notifyDisconnect }
        val notifyPacks = remember(rev) { settings.notifyPacks }
        RowList(rows = listOf(
            { SwitchRow(stringResource(R.string.notify_disconnect), null, notifyDisconnect) { settings.notifyDisconnect = it } },
            { SwitchRow(stringResource(R.string.notify_packs), null, notifyPacks) { settings.notifyPacks = it } },
        ))

        val pool = remember(rev) { settings.sharePool }
        val askGame = remember(rev) { settings.askGame }
        val speaker = remember(rev) { settings.showSpeakerNames }
        val fast = remember(rev) { settings.fastSubtitleDetection }
        RowList(rows = listOf(
            { SwitchRow(stringResource(R.string.settings_pool), stringResource(R.string.settings_pool_short), pool) { settings.sharePool = it } },
            { SwitchRow(stringResource(R.string.settings_ask_game), stringResource(R.string.settings_ask_game_short), askGame) { settings.askGame = it } },
            { SwitchRow(stringResource(R.string.settings_speaker_names), stringResource(R.string.settings_speaker_names_short), speaker) { settings.showSpeakerNames = it } },
            { SwitchRow(stringResource(R.string.settings_fast_reading), stringResource(R.string.settings_fast_reading_short), fast) { settings.fastSubtitleDetection = it } },
            { NinoRow(stringResource(R.string.profile_privacy), value = stringResource(R.string.profile_telemetry),
                onClick = { Screens.openUrl(context, context.getString(R.string.url_privacy)) }) },
            { NinoRow(stringResource(R.string.profile_help), onClick = { Screens.openUrl(context, context.getString(R.string.url_help)) }) },
            { NinoRow(stringResource(R.string.assistant_title), onClick = { nav.open(Routes.ASK_NINO) }) },
            { NinoRow(stringResource(R.string.report_title), onClick = { nav.open(Routes.REPORT) }) },
        ))

        SmallNote(stringResource(R.string.profile_no_account))
    }
}

/** Sağında anahtar olan satır; satırın tamamı da değiştirir. */
@Composable
fun SwitchRow(title: String, value: String?, checked: Boolean, onChange: (Boolean) -> Unit) {
    NinoRow(title, value = value, onClick = { onChange(!checked) }) { NinoSwitch(checked, onChange) }
}
