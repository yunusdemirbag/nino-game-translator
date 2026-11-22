// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.setup

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.SubtitleTarget
import com.ninotranslator.mobile.tv.FoundTv
import com.ninotranslator.mobile.tv.TvFinders
import com.ninotranslator.mobile.ui.components.GhostButton
import com.ninotranslator.mobile.ui.components.NinoScreen
import com.ninotranslator.mobile.ui.components.NinoTopBar
import com.ninotranslator.mobile.ui.components.PrimaryButton
import com.ninotranslator.mobile.ui.components.ScreenHeader
import com.ninotranslator.mobile.ui.components.SecondaryButton
import com.ninotranslator.mobile.ui.components.SelectableGlassBox
import com.ninotranslator.mobile.ui.components.StageCard
import com.ninotranslator.mobile.ui.navigation.NinoNavigator
import com.ninotranslator.mobile.ui.navigation.Routes
import com.ninotranslator.mobile.ui.theme.NinoColors

/** Altyazılar nerede görünsün? (ekranlar-1 §6.3). */
@Composable
fun TargetScreen(nav: NinoNavigator) {
    val settings = Nino.settings
    val context = LocalContext.current
    val canBack = nav.canGoBack()
    var target by rememberSaveable { mutableStateOf(settings.target) }
    var tvs by remember { mutableStateOf<List<FoundTv>?>(null) }

    // TV araması ekran açılınca bir kez.
    LaunchedEffect(Unit) { tvs = runCatching { TvFinders.current.search() }.getOrDefault(emptyList()) }

    NinoScreen(
        topBar = { NinoTopBar(onBack = if (canBack) nav::back else null) },
        bottom = {
            PrimaryButton(stringResource(R.string.next_continue), onClick = {
                settings.completeTargetSelection(target, tvs?.firstOrNull()?.name)
                nav.finishStep()
            })
        },
    ) {
        ScreenHeader(stringResource(R.string.target_title), step = if (canBack) null else stringResource(R.string.setup_step, 3),
            body = stringResource(R.string.target_body))
        StageCard(height = 250.dp) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                val list = tvs
                val tvDetail = when {
                    list == null -> stringResource(R.string.target_searching)
                    list.isEmpty() -> stringResource(R.string.target_tv_over_game)
                    else -> list.joinToString(", ") { it.name }
                }
                SelectableGlassBox(Icons.Filled.Tv, stringResource(R.string.target_tv_short), tvDetail,
                    selected = target == SubtitleTarget.TV, onSelect = { target = SubtitleTarget.TV }, modifier = Modifier.weight(1f))
                SelectableGlassBox(Icons.Filled.Smartphone, stringResource(R.string.target_phone), stringResource(R.string.target_phone_note),
                    selected = target == SubtitleTarget.PHONE, onSelect = { target = SubtitleTarget.PHONE }, modifier = Modifier.weight(1f))
            }
        }
        Text(
            stringResource(if (target == SubtitleTarget.TV) R.string.target_tv_body else R.string.target_phone_body),
            style = TextStyle(fontSize = 15.sp, lineHeight = 21.sp, color = NinoColors.InkSecondary),
        )
        if (target == SubtitleTarget.TV) {
            SecondaryButton(stringResource(R.string.tv_install_button), { nav.open(Routes.tvInstall()) })
        }
        GhostButton(stringResource(R.string.target_unlisted), { openUrl(context, context.getString(R.string.url_tvs)) })
    }
}

/** Tarayıcıda adres açar; tarayıcı yoksa sessizce geçer. */
fun openUrl(context: Context, url: String) {
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
