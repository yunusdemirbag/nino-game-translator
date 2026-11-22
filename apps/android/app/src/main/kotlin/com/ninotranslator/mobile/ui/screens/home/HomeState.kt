// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.home

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.ConsoleKind
import com.ninotranslator.mobile.data.HomeStyle
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.SubtitleTarget
import com.ninotranslator.mobile.data.VideoSource
import com.ninotranslator.mobile.service.LiveSnapshot
import com.ninotranslator.mobile.service.LiveStatus
import com.ninotranslator.mobile.ui.theme.NinoColors
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/** Ana ekran durumu (ekranlar-1 §7 "Kavramlar"). */
enum class HomeStatus { NOT_PAIRED, READY, CONNECTING, LIVE }

/** Ana ekranın okuduğu her şey, tek yerde. */
data class HomeModel(
    val live: LiveSnapshot,
    val status: HomeStatus,
    val paired: Boolean,
    val consoleKind: ConsoleKind,
    val videoSource: VideoSource,
    /** Kaynak adı: kartta "Capture Card", Xbox'ta Xbox'ın adı, PS5'te PS5'in adı. */
    val sourceName: String?,
    val target: SubtitleTarget,
    val style: HomeStyle,
    val language: String,
    val packsEnabled: Boolean,
    val downloadTotal: Int,
    val tourShown: Boolean,
) {
    val running get() = live.running
    val consoleLabel get() = if (consoleKind == ConsoleKind.XBOX) "Xbox" else "PS5"
    /** Çıkış telefonda ya da örnek oturum: döndürme ipucu ve yan çevirince tam ekran (Salon kuralı). */
    val phoneOutput get() = target == SubtitleTarget.PHONE || live.demo
}

/** Ayar, gizli değer ve canlı durumu izleyip [HomeModel] üretir. */
@Composable
fun rememberHomeModel(): HomeModel {
    val settings = Nino.settings
    val secrets = Nino.secrets
    val rev by settings.revision.collectAsState()
    val secretRev by secrets.revision.collectAsState()
    val live by remember { LiveStatus.uiState() }.collectAsState(remember { LiveStatus.uiNow() })
    val captureName = stringResource(R.string.capture_card)
    // Keystore çözme işi yalnız ayar ya da gizli değer değişince.
    val base = remember(rev, secretRev, captureName) {
        val source = settings.videoSource
        val kind = settings.effectiveConsoleKind
        val console = secrets.console
        val xbox = settings.xboxConsole
        val paired = when {
            source == VideoSource.CAPTURE_CARD -> true
            kind == ConsoleKind.XBOX -> xbox != null && secrets.xboxToken != null
            else -> console != null
        }
        val name = when {
            source == VideoSource.CAPTURE_CARD -> captureName
            kind == ConsoleKind.XBOX -> xbox?.name?.takeIf { it.isNotBlank() } ?: xbox?.let { "Xbox" }
            else -> console?.name
        }
        HomeModel(
            live = LiveSnapshot(), status = HomeStatus.NOT_PAIRED, paired = paired, consoleKind = kind, videoSource = source,
            sourceName = name, target = settings.target, style = settings.homeStyle, language = settings.targetLanguage,
            packsEnabled = settings.packsEnabled, downloadTotal = settings.downloadTotal, tourShown = settings.tourShown,
        )
    }
    return remember(base, live) {
        val status = when {
            live.running && live.streaming -> HomeStatus.LIVE
            live.running -> HomeStatus.CONNECTING
            base.paired -> HomeStatus.READY
            else -> HomeStatus.NOT_PAIRED
        }
        base.copy(live = live, status = status)
    }
}

/** Arayüzün okumadığı, sık değişen alanlar atılmış canlı durum (gereksiz yeniden çizimi önler). */
fun LiveSnapshot.forUi(): LiveSnapshot =
    copy(framesReceived = 0, recent = emptyList(), shownLines = 0, packLines = 0, lastFrame = null)

/** [LiveSnapshot.forUi] akışı. */
/** Arayüzün ilk karesi için şimdiki durum (bileşim içinde StateFlow.value okunmasın diye). */
fun LiveStatus.uiNow(): LiveSnapshot = state.value.forUi()

fun LiveStatus.uiState(): Flow<LiveSnapshot> = state.map { it.forUi() }.distinctUntilChanged()

/** Durum noktasının rengi (§7.1). */
fun HomeModel.dotColor(): Color = when (status) {
    HomeStatus.NOT_PAIRED -> NinoColors.InkSecondary
    HomeStatus.READY -> NinoColors.Accent
    HomeStatus.CONNECTING -> if (live.connectReason != null) NinoColors.Warning else NinoColors.Accent
    HomeStatus.LIVE -> NinoColors.LiveGreen
}
