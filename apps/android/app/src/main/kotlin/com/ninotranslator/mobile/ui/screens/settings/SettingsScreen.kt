// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.settings

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.ninotranslator.mobile.BuildConfig
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.ConsoleKind
import com.ninotranslator.mobile.data.HomeStyle
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.service.TranslationControl
import com.ninotranslator.mobile.data.SubtitleTarget
import com.ninotranslator.mobile.data.VideoSource
import com.ninotranslator.mobile.data.XboxQuality
import com.ninotranslator.mobile.ui.components.SegmentedPicker
import com.ninotranslator.mobile.service.LiveStatus
import com.ninotranslator.mobile.tv.TvAppVersions
import com.ninotranslator.mobile.ui.components.ExtraAreasTile
import com.ninotranslator.mobile.ui.components.GhostButton
import com.ninotranslator.mobile.ui.components.LanguagePicker
import com.ninotranslator.mobile.ui.components.LanguagePickerStyle
import com.ninotranslator.mobile.ui.components.NinoRow
import com.ninotranslator.mobile.ui.components.NinoScreen
import com.ninotranslator.mobile.ui.components.NinoTag
import com.ninotranslator.mobile.ui.components.NinoTextField
import com.ninotranslator.mobile.ui.components.NinoTile
import com.ninotranslator.mobile.ui.components.NinoTopBar
import com.ninotranslator.mobile.ui.components.NoteTile
import com.ninotranslator.mobile.ui.components.RowList
import com.ninotranslator.mobile.ui.components.SecondaryButton
import com.ninotranslator.mobile.ui.components.SubtitleAreaTile
import com.ninotranslator.mobile.ui.components.TileLabel
import com.ninotranslator.mobile.ui.navigation.NinoNavigator
import com.ninotranslator.mobile.ui.navigation.Routes
import com.ninotranslator.mobile.ui.screens.Screens
import com.ninotranslator.mobile.ui.screens.SmallNote
import com.ninotranslator.mobile.ui.screens.home.AppUpdates
import com.ninotranslator.mobile.ui.screens.profile.SwitchRow
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoType
import com.ninotranslator.mobile.update.AppUpdateChecker
import com.ninotranslator.mobile.xbox.XboxAccounts
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/** Ayarlar (ekranlar-2 "Ayarlar"): tek kayan sütun, her değişiklik anında kaydedilir. */
@Composable
fun SettingsScreen(nav: NinoNavigator) {
    val context = LocalContext.current
    val s = Nino.settings
    val secrets = Nino.secrets
    val rev by s.revision.collectAsState()
    val secretRev by secrets.revision.collectAsState()
    val poolFirst by remember { LiveStatus.state.map { it.poolFirstGame }.distinctUntilChanged() }.collectAsState(false)
    // Oyun henüz bilinmiyorsa Türkçede GTA 6 ortak çevirisi öntanımlı sayılır (okuma.md §9); eskisi de böyle gösterirdi.
    val gameKnown by remember { LiveStatus.state.map { it.game != null }.distinctUntilChanged() }.collectAsState(false)
    val running by remember { LiveStatus.state.map { it.running }.distinctUntilChanged() }.collectAsState(false)
    val source = remember(rev) { s.videoSource }
    val language = remember(rev) { s.targetLanguage }
    val gta6 = language == "tr" && (poolFirst || !gameKnown)
    var testNeedsStart by remember { mutableStateOf(false) }

    NinoScreen(topBar = { NinoTopBar(onBack = nav::back, title = stringResource(R.string.settings)) }) {
        // 1. Görüntü kaynağı
        RowList(rows = listOf {
            NinoRow(stringResource(R.string.settings_video_source), value = stringResource(when (source) {
                VideoSource.REMOTE_PLAY -> R.string.source_remote_play
                VideoSource.XBOX -> R.string.source_xbox
                VideoSource.CAPTURE_CARD -> R.string.capture_card
            }), onClick = { nav.open(Routes.VIDEO_SOURCE) })
        })

        // 2. Arayüz
        InterfaceTile()

        // 3. Çeviri dili
        NinoTile {
            TileLabel(stringResource(R.string.nino_translation_language))
            LanguagePicker(language, { s.targetLanguage = it }, Modifier.fillMaxWidth(), style = LanguagePickerStyle.ROW)
            SmallNote(stringResource(R.string.nino_translation_language_note))
        }

        // 4. Sistem sağlığı
        RowList(rows = listOf {
            NinoRow(stringResource(R.string.nino_system_health), value = stringResource(R.string.nino_system_health_detail),
                onClick = { nav.open(Routes.HEALTH) })
        })

        // 5. GTA 6
        if (gta6) {
            NinoTile {
                TileLabel("GTA 6")
                NinoTag(stringResource(R.string.nino_gta6_active))
                SmallNote(stringResource(R.string.nino_gta6_note))
            }
        }

        // 6. Çeviri motoru
        EngineTile(stringResource(if (gta6) R.string.settings_engine_other_games else R.string.settings_engine))

        // 7–9. Görünüm, altyazı alanı, ek alanlar
        AppearanceTile()
        SubtitleAreaTile()
        ExtraAreasTile()

        // 10. PS5 giriş şifresi
        PasscodeTile(secretRev)

        // 11. Satır listesi
        val packsOn = remember(rev) { s.packsEnabled }
        val target = remember(rev) { s.target }
        val tvName = remember(rev) { s.tvName }
        val xbox = source == VideoSource.XBOX || s.effectiveConsoleKind == ConsoleKind.XBOX
        val consoleName = remember(rev, secretRev) { if (xbox) s.xboxConsole?.name?.takeIf { it.isNotBlank() } ?: s.xboxConsole?.model else secrets.console?.name }
        val fromStore = remember { AppUpdates.installedFromStore(context) }
        val rows = ArrayList<@Composable () -> Unit>()
        rows += {
            NinoRow(stringResource(R.string.settings_packs), onClick = { nav.open(Routes.PACKS) }) {
                NinoTag(stringResource(if (packsOn) R.string.main_packs_on else R.string.main_packs_off))
            }
        }
        rows += {
            NinoRow(stringResource(R.string.settings_target),
                value = if (target == SubtitleTarget.TV) tvName ?: stringResource(R.string.main_target_tv) else stringResource(R.string.main_target_phone),
                onClick = { nav.open(Routes.TARGET) })
        }
        rows += {
            NinoRow(if (xbox) "Xbox" else stringResource(R.string.settings_ps5), value = consoleName ?: stringResource(R.string.profile_not_paired),
                onClick = nav::openPairing)
        }
        if (xbox) rows += {
            SwitchRow(stringResource(R.string.settings_xbox_audio), stringResource(R.string.settings_xbox_audio_short),
                remember(rev) { s.xboxAudioOnDevice }) { s.xboxAudioOnDevice = it }
        }
        if (xbox) rows += {
            // Yayın kalitesi: 720p'de Xbox daha düşük çözünürlük ve bit hızıyla gönderir (sonraki bağlantıda geçerli).
            var quality by remember(rev) { mutableStateOf(s.xboxQuality) }
            Column(Modifier.padding(bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                NinoRow(stringResource(R.string.settings_xbox_quality), value = stringResource(R.string.settings_xbox_quality_note))
                SegmentedPicker(listOf("1080p", "720p"), quality.ordinal, { i ->
                    quality = XboxQuality.values()[i]
                    s.xboxQuality = quality
                })
            }
        }
        rows += { NinoRow(stringResource(R.string.assistant_title), value = stringResource(R.string.assistant_row_note), onClick = { nav.open(Routes.ASK_NINO) }) }
        rows += { NinoRow(stringResource(R.string.report_title), value = stringResource(R.string.report_row_note), onClick = { nav.open(Routes.REPORT) }) }
        if (!fromStore) rows += { UpdateRow() }
        rows += {
            NinoRow(stringResource(R.string.settings_about), value = BuildConfig.VERSION_NAME,
                onClick = { Screens.openUrl(context, context.getString(R.string.url_source)) })
        }
        RowList(rows = rows)

        // 12. Microsoft çıkışı
        val signedIn = remember(secretRev) { secrets.xboxToken != null }
        if (source == VideoSource.XBOX && signedIn) {
            RowList(rows = listOf { NinoRow(stringResource(R.string.xbox_sign_out), onClick = { XboxAccounts.current.signOut() }) })
        }

        // 13. TV uygulaması
        val notice by TvAppVersions.state.collectAsState()
        val installed = remember(rev) { s.installedTv }
        NinoTile {
            TileLabel(stringResource(R.string.settings_tv_app))
            NinoRow(stringResource(R.string.tvinstall_entry), value = when {
                notice != null -> stringResource(R.string.tvapp_update_short, notice!!.phoneVersion)
                installed != null -> listOfNotNull(Screens.brandName(installed.brand), installed.version).joinToString(" · ")
                else -> null
            }, onClick = { nav.open(Routes.tvInstall(notice?.host)) })
        }

        // 14. Deneme
        SecondaryButton(stringResource(R.string.settings_test_subtitle), {
            TranslationControl.sendTestSubtitle(context, context.getString(R.string.test_subtitle_text)) { ok -> testNeedsStart = !ok }
        })
        if (testNeedsStart && !running) NoteTile(stringResource(R.string.settings_test_needs_start), warning = false)

        // 15. Telif satırı (NOTICE'tan)
        val copyright = remember { noticeLine(context) }
        if (copyright != null) {
            Spacer(Modifier.height(8.dp))
            SmallNote(copyright)
        }
    }
}

/** NOTICE dosyasından telif satırı ("Copyright (C) …"; metin tek yerde durur). */
private fun noticeLine(context: android.content.Context): String? = runCatching {
    val text = context.assets.open("NOTICE").bufferedReader().use { it.readText() }
    text.lineSequence().map { it.trim() }.firstOrNull { it.startsWith("Copyright") }
}.getOrNull()

/** Arayüz karosu: iki seçenek kutusu (salon / cam düğme önizlemesi) ve ipucu. */
@Composable
private fun InterfaceTile() {
    val s = Nino.settings
    val rev by s.revision.collectAsState()
    val style = remember(rev) { s.homeStyle }
    NinoTile {
        TileLabel(stringResource(R.string.nino_interface))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StyleOption(stringResource(R.string.nino_home_living_room), style == HomeStyle.LIVING_ROOM, Modifier.weight(1f),
                { s.homeStyle = HomeStyle.LIVING_ROOM }) {
                Image(painterResource(R.drawable.living_room), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            }
            StyleOption(stringResource(R.string.nino_home_toggle), style == HomeStyle.TOGGLE, Modifier.weight(1f),
                { s.homeStyle = HomeStyle.TOGGLE }) {
                GlassTogglePreview()
            }
        }
        SmallNote(stringResource(if (style == HomeStyle.LIVING_ROOM) R.string.nino_home_living_room_hint else R.string.nino_home_toggle_hint))
    }
}

@Composable
private fun StyleOption(name: String, selected: Boolean, modifier: Modifier, onClick: () -> Unit, preview: @Composable () -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    Column(
        modifier.clip(shape).border(if (selected) 2.dp else 1.dp, if (selected) NinoColors.Accent else NinoColors.BorderStrong, shape)
            .semantics { this.selected = selected }
            .clickable(role = Role.RadioButton, onClick = onClick).padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(Modifier.fillMaxWidth().height(64.dp).clip(RoundedCornerShape(10.dp)).background(NinoColors.Surface2),
            contentAlignment = Alignment.Center) { preview() }
        Text(name, style = NinoType.Headline, color = if (selected) NinoColors.Accent else NinoColors.Ink)
    }
}

/** Cam düğmenin küçük, etkileşimsiz çizimi: koyu zeminde cam küre (en çok 130 dp). */
@Composable
private fun GlassTogglePreview() {
    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(NinoColors.StageTop, NinoColors.StageBottom))),
        contentAlignment = Alignment.Center) {
        Box(Modifier.widthIn(max = 130.dp).fillMaxWidth(0.7f).height(36.dp).clip(RoundedCornerShape(50))
            .background(Color.White.copy(alpha = 0.12f)).border(1.dp, Color.White.copy(alpha = 0.25f), RoundedCornerShape(50)),
            contentAlignment = Alignment.CenterStart) {
            Box(Modifier.padding(4.dp).size(28.dp).clip(CircleShape)
                .background(Brush.radialGradient(listOf(Color.White, NinoColors.AccentLight))))
        }
    }
}

/** PS5 giriş şifresi: yalnız rakam, en çok 4; yazdıkça kaydedilir, boşaltınca silinir. */
@Composable
private fun PasscodeTile(secretRev: Long) {
    val secrets = Nino.secrets
    val saved = remember(secretRev) { secrets.loginPasscode != null }
    var text by remember { mutableStateOf("") }
    NinoTile {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.settings_passcode), Modifier.weight(1f), style = NinoType.Headline)
            if (saved) NinoTag(stringResource(R.string.settings_key_saved))
        }
        NinoTextField(text, { v ->
            val d = v.filter { it in '0'..'9' }.take(4)
            text = d
            when {
                d.isEmpty() -> secrets.setLoginPasscode(null)
                d.length == 4 -> secrets.setLoginPasscode(d)
            }
        }, stringResource(R.string.settings_passcode_field), secret = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword))
        SmallNote(stringResource(R.string.settings_passcode_note))
    }
}

/** Güncelleme satırı (yalnız Play dışı kurulumda). */
@Composable
private fun UpdateRow() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var checking by remember { mutableStateOf(false) }
    var offline by remember { mutableStateOf(false) }
    var latest by remember { mutableStateOf(Nino.appUpdate.latest) }
    LaunchedEffect(Unit) {
        checking = true
        AppUpdateChecker.check(context, force = false)
        latest = Nino.appUpdate.latest
        checking = false
    }
    val newer = latest?.takeIf { AppUpdates.isNewer(it, BuildConfig.VERSION_NAME) }
    NinoRow(
        stringResource(R.string.update_row_title),
        value = when {
            checking -> stringResource(R.string.update_row_checking)
            newer != null -> stringResource(R.string.update_row_newer, newer)
            offline -> stringResource(R.string.xbox_error_offline)
            else -> stringResource(R.string.update_row_current)
        },
    ) {
        when {
            checking -> {}
            newer != null -> GhostButton(stringResource(R.string.update_row_download), { Screens.openUrl(context, AppUpdateChecker.APK) })
            else -> GhostButton(stringResource(R.string.update_row_check), {
                scope.launch {
                    checking = true
                    offline = AppUpdateChecker.check(context, force = true) == AppUpdateChecker.Outcome.OFFLINE
                    latest = Nino.appUpdate.latest
                    checking = false
                }
            })
        }
    }
}
