// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.report

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.support.AppLog
import com.ninotranslator.mobile.support.DeviceSummary
import com.ninotranslator.mobile.support.Findings
import com.ninotranslator.mobile.support.HealthFeed
import com.ninotranslator.mobile.support.ImageShrink
import com.ninotranslator.mobile.support.ReportSender
import com.ninotranslator.mobile.ui.components.NinoScreen
import com.ninotranslator.mobile.ui.components.NinoTextField
import com.ninotranslator.mobile.ui.components.NinoTile
import com.ninotranslator.mobile.ui.components.NinoTopBar
import com.ninotranslator.mobile.ui.components.NoteTile
import com.ninotranslator.mobile.ui.components.PrimaryButton
import com.ninotranslator.mobile.ui.components.RowList
import com.ninotranslator.mobile.ui.components.TileLabel
import com.ninotranslator.mobile.ui.navigation.NinoNavigator
import com.ninotranslator.mobile.ui.screens.Screens
import com.ninotranslator.mobile.ui.screens.SmallNote
import com.ninotranslator.mobile.ui.screens.health.incidentName
import com.ninotranslator.mobile.ui.screens.profile.SwitchRow
import com.ninotranslator.mobile.ui.theme.NinoType
import androidx.compose.material3.Text
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val HM = DateTimeFormatter.ofPattern("HH:mm").withZone(ZoneId.systemDefault())

/** Sorun Bildir (ekranlar-2 "Sorun Bildir"). */
@Composable
fun ReportScreen(nav: NinoNavigator) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { HealthFeed.ensureStarted(context) }
    val issuesAll by Nino.health.issues.collectAsState()
    val now = remember { System.currentTimeMillis() }
    val recent = remember(issuesAll) { Findings.recent(now) }
    var text by rememberSaveable { mutableStateOf("") }
    var contact by rememberSaveable { mutableStateOf("") }
    var includeLog by rememberSaveable { mutableStateOf(true) }
    val photos = remember { mutableStateListOf<ByteArray>() }
    var loadingPhotos by remember { mutableStateOf(0) }
    var photoFailed by remember { mutableStateOf(false) }
    var sending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<ReportSender.Result?>(null) }
    val settingsRev by Nino.settings.revision.collectAsState()
    val auto = remember(settingsRev) { Nino.settings.autoReport }
    val thanks = stringResource(R.string.report_thanks)

    val picker = rememberPhotoPicker({ 3 - photos.size }) { uris ->
        loadingPhotos += uris.size
        uris.forEach { uri ->
            scope.launch {
                val b = withContext(Dispatchers.IO) { ImageShrink.jpeg(context, uri, ImageShrink.REPORT_BYTES) }
                if (b != null && photos.size < 3) photos += b else if (b == null) photoFailed = true
                loadingPhotos--
            }
        }
    }

    fun send(userText: String) {
        if (sending) return
        sending = true; error = null
        scope.launch {
            val result = withContext(Dispatchers.IO) {
                val findings = Findings.section(HealthFeed.input.value, System.currentTimeMillis())
                val body = ReportSender.buildBody(ReportSender.composeText(userText, findings), contact,
                    if (includeLog) AppLog.collect() else null, DeviceSummary.line(), photos.toList())
                ReportSender.send(body)
            }
            sending = false
            if (result == ReportSender.Result.SENT) {
                Screens.toast(context, thanks, long = true)
                nav.back()
            } else error = result
        }
    }

    NinoScreen(
        topBar = { NinoTopBar(onBack = nav::back, title = stringResource(R.string.report_title)) },
        bottom = {
            PrimaryButton(stringResource(if (sending) R.string.report_sending else R.string.report_send), { send(text) },
                enabled = !sending && loadingPhotos == 0)
        },
    ) {
        NinoTile {
            TileLabel(stringResource(R.string.report_findings))
            if (recent.isEmpty()) {
                SmallNote(stringResource(R.string.report_findings_none))
            } else {
                Text(stringResource(R.string.report_findings_summary, recent.size), style = NinoType.Body)
                recent.take(6).forEach { SmallNote("• ${HM.format(Instant.ofEpochMilli(it.dateMs))}  ${incidentName(context, it.kind)}") }
            }
            PrimaryButton(stringResource(R.string.report_send_problems), { send("") }, enabled = !sending && loadingPhotos == 0)
        }
        SmallNote(stringResource(R.string.report_more_optional))
        NinoTextField(text, { text = it.take(ReportSender.MAX_TEXT) }, stringResource(R.string.report_description), singleLine = false, minLines = 5)
        NinoTile {
            TileLabel(stringResource(R.string.report_photos))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                photos.forEachIndexed { i, p ->
                    PhotoThumb(p, 84.dp, 14.dp, stringResource(R.string.report_remove_photo)) { photos.removeAt(i) }
                }
                if (photos.size + loadingPhotos < 3) AddPhotoBox(84.dp, stringResource(R.string.report_add_photo)) { photoFailed = false; picker.pick(3 - photos.size) }
            }
            if (photoFailed) SmallNote(stringResource(R.string.report_photo_failed), color = com.ninotranslator.mobile.ui.theme.NinoColors.Warning)
        }
        NinoTextField(contact, { contact = it.take(ReportSender.MAX_CONTACT) }, stringResource(R.string.report_contact))
        RowList(rows = listOf {
            SwitchRow(stringResource(R.string.report_include_log), stringResource(R.string.report_include_log_note), includeLog) { includeLog = it }
        })
        RowList(rows = listOf {
            SwitchRow(stringResource(R.string.report_auto), stringResource(R.string.report_auto_note), auto) { Nino.settings.autoReport = it }
        })
        error?.let {
            NoteTile(stringResource(when (it) {
                ReportSender.Result.RATE_LIMITED -> R.string.report_rate_limited
                ReportSender.Result.TOO_LARGE -> R.string.report_too_large
                ReportSender.Result.INVALID -> R.string.report_invalid
                else -> R.string.report_failed
            }))
        }
        SmallNote(stringResource(R.string.report_privacy))
    }
}
