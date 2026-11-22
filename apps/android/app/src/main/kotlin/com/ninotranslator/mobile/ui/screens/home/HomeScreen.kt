// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.home

import com.ninotranslator.mobile.support.DownloadCounter
import kotlinx.coroutines.delay
import androidx.compose.runtime.LaunchedEffect
import android.view.OrientationEventListener
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.HomeStyle
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.SubtitleTarget
import com.ninotranslator.mobile.tv.TvAppVersions
import com.ninotranslator.mobile.tv.install.TvInstallers
import com.ninotranslator.mobile.tv.install.TvUpdateAction
import com.ninotranslator.mobile.tv.install.TvUpdatePlan
import com.ninotranslator.mobile.ui.screens.tvinstall.TvInstallSession
import com.ninotranslator.mobile.ui.PhoneSubtitleActivity
import com.ninotranslator.mobile.ui.components.NinoIconButton
import com.ninotranslator.mobile.ui.components.NinoScreen
import com.ninotranslator.mobile.ui.components.NinoTopBar
import com.ninotranslator.mobile.ui.components.NoteTile
import com.ninotranslator.mobile.ui.components.stageSurface
import com.ninotranslator.mobile.ui.navigation.NinoNavigator
import com.ninotranslator.mobile.ui.navigation.Routes
import com.ninotranslator.mobile.ui.screens.setup.openUrl
import com.ninotranslator.mobile.ui.shell.AppSession
import com.ninotranslator.mobile.ui.shell.rememberTranslationStarter

private enum class TourKey { START, OUTPUT, PACKS, PROFILE }

/** Ana ekran (ekranlar-1 §7): ortak kabuk, Salon ya da kaydırmalı görünüm, güncelleme kartları, tur. */
@Composable
fun HomeScreen(nav: NinoNavigator, splashRunning: Boolean) {
    val context = LocalContext.current
    val model = rememberHomeModel()
    val starter = rememberTranslationStarter()
    val tvNotice by TvAppVersions.state.collectAsState()
    val tvSession by TvInstallSession.state.collectAsState()
    val samsungSignIn by TvInstallers.current.samsungSignInUrl.collectAsState()
    // Karttan başlayan Samsung kurulumu giriş isterse giriş sayfası kurulum ekranında açılır.
    LaunchedEffect(samsungSignIn) {
        val card = tvSession.card
        if (samsungSignIn != null && tvSession.running && card != null) nav.open(Routes.tvInstall(card.host))
    }
    val dismissed by AppSession.dismissedAppUpdate.collectAsState()
    val cameraMissing by AppSession.cameraPermissionMissing.collectAsState()
    // Bilinen son sürüm `app_update` dosyasından okunur (denetimi güncelleme denetleyicisi yapar).
    val appOffer = remember(dismissed) { AppUpdates.offer(context, Nino.appUpdate.latest, dismissed) }
    val bounds = remember { mutableStateMapOf<TourKey, Rect>() }

    fun toggle() = when {
        model.running -> starter.stop()
        model.paired -> starter.start()
        else -> nav.lockedTap()
    }
    val openFull = { PhoneSubtitleActivity.open(context) }

    RotateToFullScreen(enabled = model.running && model.phoneOutput, onOpen = openFull)
    // Toplam indirme sayısı: açılışta ve ana ekran açıkken en çok 10 dakikada bir.
    LaunchedEffect(Unit) {
        while (true) { DownloadCounter.refresh(); delay(DownloadCounter.INTERVAL_MS) }
    }

    Box(Modifier.fillMaxSize()) {
        NinoScreen(
            topBar = {
                NinoTopBar(actions = {
                    NinoIconButton(Icons.Filled.History, stringResource(R.string.history), { nav.open(Routes.HISTORY) })
                    NinoIconButton(Icons.Filled.Settings, stringResource(R.string.settings), { nav.open(Routes.SETTINGS) })
                    NinoIconButton(Icons.Filled.Person, stringResource(R.string.profile), { nav.open(Routes.PROFILE) },
                        Modifier.onGloballyPositioned { bounds[TourKey.PROFILE] = it.boundsInRoot() })
                })
            },
        ) {
            if (!model.running) {
                (tvNotice ?: tvSession.card)?.let { n ->
                    val phase = TvUpdatePlan.phase(n.host, tvSession.request?.address, tvSession.running, tvSession.step,
                        tvSession.result, tvSession.error)
                    TvUpdateCard(n, phase,
                        onInstall = {
                            when (val a = TvUpdatePlan.action(n, TvInstallers.current.hasLgKey(n.host))) {
                                is TvUpdateAction.Direct -> TvInstallSession.start(a.request, card = n)
                                is TvUpdateAction.OpenScreen -> nav.open(Routes.tvInstall(a.host))
                            }
                        },
                        onContinue = { nav.open(Routes.tvInstall(n.host)) },
                        onClose = { TvInstallSession.clearFinished() })
                }
                appOffer?.let { v ->
                    AppUpdateCard(v, onDismiss = {
                        AppSession.dismissedAppUpdate.value = v
                        Nino.appUpdate.removeLegacyDismissed()
                    }, onUpdate = { openUrl(context, context.getString(R.string.url_app_apk)) })
                }
            }
            val outputPlaced = { c: androidx.compose.ui.layout.LayoutCoordinates -> bounds[TourKey.OUTPUT] = c.boundsInRoot() }
            val packsPlaced = { c: androidx.compose.ui.layout.LayoutCoordinates -> bounds[TourKey.PACKS] = c.boundsInRoot() }
            val startPlaced = Modifier.onGloballyPositioned { bounds[TourKey.START] = it.boundsInRoot() }
            if (model.style == HomeStyle.LIVING_ROOM) {
                LivingRoomHome(model, nav, ::toggle, openFull, { starter.startDemo() }, !splashRunning, startPlaced, outputPlaced, packsPlaced)
            } else {
                ToggleHome(model, nav, starter::start, starter::stop, openFull, { starter.startDemo() }, startPlaced, outputPlaced, packsPlaced)
            }
            val error = model.live.errorText ?: if (cameraMissing) stringResource(R.string.capture_no_permission) else null
            error?.let { NoteTile(it) }
            // Sağ alttaki robot son öğenin üstüne binmesin.
            Spacer(Modifier.height(76.dp))
        }

        if (!model.tourShown && !splashRunning) {
            val steps = listOf(
                // 1. adım ekranda görünen başlatma denetimine göre: Salon'da fiş/priz, kaydırmalı düzende çubuk.
                TourStep(bounds[TourKey.START], stringResource(R.string.tour1_title),
                    stringResource(if (model.style == HomeStyle.LIVING_ROOM) R.string.tour1_body_plug else R.string.tour1_body)),
                TourStep(bounds[TourKey.OUTPUT], stringResource(R.string.tour2_title), stringResource(R.string.tour2_body)),
                TourStep(bounds[TourKey.PACKS], stringResource(R.string.tour3_title), stringResource(R.string.tour3_body)),
                TourStep(bounds[TourKey.PROFILE], stringResource(R.string.tour4_title), stringResource(R.string.tour4_body)),
            )
            TourOverlay(steps, onFinish = { Nino.settings.tourShown = true })
        }
    }
}

/** Salon görünümü (§7.2). */
@Composable
private fun LivingRoomHome(
    model: HomeModel,
    nav: NinoNavigator,
    onToggle: () -> Unit,
    onFullScreen: () -> Unit,
    onDemo: () -> Unit,
    showReady: Boolean,
    startPlaced: Modifier,
    outputPlaced: (androidx.compose.ui.layout.LayoutCoordinates) -> Unit,
    packsPlaced: (androidx.compose.ui.layout.LayoutCoordinates) -> Unit,
) {
    Column(Modifier.fillMaxWidth()) {
        HomeHeader(model)
        Spacer(Modifier.height(14.dp))
        LivingRoomScene(model, onToggle, showReady, startPlaced)
        Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth().heightIn(min = 36.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            val hint = when {
                model.running -> stringResource(R.string.nino_unplug_to_stop)
                model.paired -> stringResource(R.string.nino_plug_to_start,
                    com.ninotranslator.mobile.ui.components.languageDisplayName(model.language))
                else -> stringResource(R.string.nino_pair_first)
            }
            Text(hint, Modifier.weight(1f), style = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium,
                color = com.ninotranslator.mobile.ui.theme.NinoColors.InkSecondary))
            AnimatedVisibility(model.running, enter = fadeIn(), exit = fadeOut()) { FullScreenPill(onFullScreen) }
        }
        if (!model.paired && !model.running) {
            Spacer(Modifier.height(14.dp))
            DemoTryButton(onDemo)
        }
        if (model.running && model.phoneOutput) {
            Spacer(Modifier.height(14.dp))
            RotateHint()
        }
        Spacer(Modifier.height(if (!model.paired && !model.running) 18.dp else 22.dp))
        val output = when {
            model.target == SubtitleTarget.PHONE -> stringResource(R.string.nino_phone)
            model.live.connectedTvs > 0 -> stringResource(R.string.nino_tv_connected)
            else -> stringResource(R.string.nino_tv)
        }
        Shortcuts(model, output, nav::openConsoleShortcut, { nav.open(Routes.TARGET) }, { nav.open(Routes.PACKS) },
            outputPlaced, packsPlaced)
    }
}

/** Kaydırmalı ana ekran ("Cam düğme", §7.3). */
@Composable
private fun ToggleHome(
    model: HomeModel,
    nav: NinoNavigator,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onFullScreen: () -> Unit,
    onDemo: () -> Unit,
    startPlaced: Modifier,
    outputPlaced: (androidx.compose.ui.layout.LayoutCoordinates) -> Unit,
    packsPlaced: (androidx.compose.ui.layout.LayoutCoordinates) -> Unit,
) {
    Column(Modifier.fillMaxWidth()) {
        HomeHeader(model)
        Spacer(Modifier.height(20.dp))
        StageCardLive(model, onFullScreen)
        Spacer(Modifier.height(22.dp))
        SlideToggle(model, onLocked = nav::lockedTap, onStart = onStart, onStop = onStop, modifier = startPlaced)
        if (model.status == HomeStatus.NOT_PAIRED) {
            Spacer(Modifier.height(12.dp))
            DemoTryButton(onDemo)
        }
        AnimatedVisibility(model.status == HomeStatus.LIVE && model.target != SubtitleTarget.TV, enter = fadeIn(), exit = fadeOut()) {
            Column { Spacer(Modifier.height(14.dp)); RotateHint() }
        }
        Spacer(Modifier.height(28.dp))
        val output = stringResource(if (model.target == SubtitleTarget.TV) R.string.nino_tv else R.string.nino_phone)
        Shortcuts(model, output, nav::openConsoleShortcut, { nav.open(Routes.TARGET) }, { nav.open(Routes.PACKS) },
            outputPlaced, packsPlaced)
    }
}

/** Kaydırmalı ekranın sahne kartı (§7.3.1). */
@Composable
private fun StageCardLive(model: HomeModel, onFullScreen: () -> Unit) {
    val live = model.status == HomeStatus.LIVE
    val tapToFull = live && model.target != SubtitleTarget.TV
    Box(
        Modifier.fillMaxWidth().heightIn(min = 196.dp).stageSurface()
            .let { if (tapToFull) it.clickable(role = Role.Button, onClick = onFullScreen) else it },
    ) {
        AnimatedContent(live, transitionSpec = { fadeIn(tween(400)) togetherWith fadeOut(tween(250)) }, label = "stage") { isLive ->
            if (isLive) {
                Box(Modifier.fillMaxWidth().height(196.dp)) { LiveTvScreen(model) }
            } else {
                val reason = model.live.connectReason?.takeIf { model.status == HomeStatus.CONNECTING && it != model.live.errorText }
                Box(Modifier.fillMaxWidth().heightIn(min = 196.dp), contentAlignment = Alignment.Center) {
                    if (reason != null) {
                        Text(reason, Modifier.padding(horizontal = 22.dp, vertical = 18.dp), textAlign = TextAlign.Center,
                            style = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.85f)))
                    } else {
                        Text(stringResource(if (model.status == HomeStatus.CONNECTING) R.string.home_connecting else R.string.home_stage_idle),
                            Modifier.padding(horizontal = 22.dp, vertical = 24.dp), textAlign = TextAlign.Center,
                            style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.42f)))
                    }
                }
            }
        }
        AnimatedVisibility(tapToFull, Modifier.align(Alignment.TopEnd).padding(12.dp),
            enter = fadeIn(tween(300)), exit = fadeOut(tween(200))) {
            val pill = RoundedCornerShape(50)
            Row(
                Modifier.shadow(12.dp, pill).clip(pill)
                    .background(Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.26f), Color.White.copy(alpha = 0.10f))))
                    .border(1.dp, Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.55f), Color.White.copy(alpha = 0.12f))), pill)
                    .clickable(role = Role.Button, onClick = onFullScreen)
                    .padding(start = 12.dp, end = 14.dp, top = 8.dp, bottom = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Fullscreen, null, Modifier.size(20.dp), tint = Color.White)
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.home_full_screen), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
            }
        }
    }
}

/**
 * Yan çevirince tam ekran (§7.4.3): telefon bir kez dik tutulunca kurulur; yan duruma geçip 0,7 sn kalırsa ve
 * uygulama öndeyse [onOpen]; açılınca kurulum düşer.
 */
@Composable
private fun RotateToFullScreen(enabled: Boolean, onOpen: () -> Unit) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val open by rememberUpdatedState(onOpen)
    DisposableEffect(enabled) {
        if (!enabled) return@DisposableEffect onDispose { }
        var armed = false
        var sidewaysSince = 0L
        val listener = object : OrientationEventListener(context) {
            override fun onOrientationChanged(deg: Int) {
                if (deg == ORIENTATION_UNKNOWN) return
                // Tam ekran (ya da başka pencere) öndeyken kurulmaz: dönünce telefon önce yeniden dik gelmeli.
                if (!lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) { armed = false; sidewaysSince = 0L; return }
                val upright = deg <= 25 || deg >= 335
                val sideways = deg in 65..115 || deg in 245..295
                val now = System.currentTimeMillis()
                when {
                    upright -> { armed = true; sidewaysSince = 0L }
                    sideways && armed -> {
                        if (sidewaysSince == 0L) sidewaysSince = now
                        else if (now - sidewaysSince >= 700 && lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
                            armed = false
                            sidewaysSince = 0L
                            open()
                        }
                    }
                    else -> sidewaysSince = 0L
                }
            }
        }
        if (listener.canDetectOrientation()) listener.enable()
        onDispose { listener.disable() }
    }
}
