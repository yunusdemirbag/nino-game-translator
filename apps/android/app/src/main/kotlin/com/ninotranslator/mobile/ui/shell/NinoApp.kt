// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.shell

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.ninotranslator.mobile.support.HealthFeed
import com.ninotranslator.mobile.update.AppUpdateChecker
import kotlinx.coroutines.launch
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.service.LiveStatus
import com.ninotranslator.mobile.ui.components.languageDisplayName
import com.ninotranslator.mobile.ui.navigation.NinoNavigator
import com.ninotranslator.mobile.ui.navigation.Routes
import com.ninotranslator.mobile.ui.screens.PacksScreen
import com.ninotranslator.mobile.ui.screens.home.HomeScreen
import com.ninotranslator.mobile.ui.screens.assistant.AskNinoScreen
import com.ninotranslator.mobile.ui.screens.setup.ConsoleTypeScreen
import com.ninotranslator.mobile.ui.screens.health.HealthScreen
import com.ninotranslator.mobile.ui.screens.history.HistoryScreen
import com.ninotranslator.mobile.ui.screens.xbox.MicrosoftSignInScreen
import com.ninotranslator.mobile.ui.screens.profile.ProfileScreen
import com.ninotranslator.mobile.ui.screens.psn.PsnSignInScreen
import com.ninotranslator.mobile.ui.screens.report.ReportScreen
import com.ninotranslator.mobile.ui.screens.settings.SettingsScreen
import com.ninotranslator.mobile.ui.screens.tvinstall.TvInstallScreen
import com.ninotranslator.mobile.ui.screens.xbox.XboxPickScreen
import com.ninotranslator.mobile.ui.screens.setup.Ps5PairScreen
import com.ninotranslator.mobile.ui.screens.setup.TargetScreen
import com.ninotranslator.mobile.ui.screens.setup.VideoSourceScreen
import com.ninotranslator.mobile.ui.screens.setup.WelcomeScreen
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/** Uygulamanın kökü: gezinme, üstte açılış animasyonu, yüzen robot ve "çeviri başladı" balonu. */
@Composable
fun NinoApp() {
    val controller = rememberNavController()
    val nav = remember(controller) { NinoNavigator(controller) }
    val start = rememberSaveable { nav.startRoute() }
    var splash by remember { mutableStateOf(!AppSession.splashDone) }
    val entry by controller.currentBackStackEntryAsState()
    val route = entry?.destination?.route
    val startedAt by remember { LiveStatus.state.map { it.startedAtMs }.distinctUntilChanged() }.collectAsState(null)
    val language by remember { Nino.settings.watch { it.targetLanguage } }.collectAsState(Nino.settings.targetLanguage)

    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // Sağlık ölçümü süreç boyunca bir kez kurulur; uygulama her öne gelişte güncelleme denetlenir (en çok 3 saatte bir).
    LaunchedEffect(Unit) { HealthFeed.ensureStarted(context) }
    LifecycleEventEffect(Lifecycle.Event.ON_START) { scope.launch { AppUpdateChecker.check(context, force = false) } }

    Box(Modifier.fillMaxSize()) {
        NavHost(controller, startDestination = start) {
            composable(Routes.WELCOME) { WelcomeScreen(nav) }
            composable(Routes.CONSOLE_TYPE) { ConsoleTypeScreen(nav) }
            composable(Routes.MICROSOFT_SIGN_IN) { MicrosoftSignInScreen(nav) }
            composable(Routes.XBOX_PICK) { XboxPickScreen(nav) }
            composable(Routes.PSN_SIGN_IN) { PsnSignInScreen(nav) }
            composable(Routes.PS5_PAIR) { Ps5PairScreen(nav) }
            composable(Routes.TARGET) { TargetScreen(nav) }
            composable(Routes.HOME) { HomeScreen(nav, splashRunning = splash) }
            composable(Routes.VIDEO_SOURCE) { VideoSourceScreen(nav) }
            composable(Routes.PACKS) { PacksScreen(nav) }
            // Paket içe aktarma Oyun paketleri ekranının bir bölümü.
            composable(Routes.PACK_IMPORT) { PacksScreen(nav) }
            composable(Routes.PROFILE) { ProfileScreen(nav) }
            composable(Routes.SETTINGS) { SettingsScreen(nav) }
            composable(Routes.HISTORY) { HistoryScreen(nav) }
            composable(Routes.HEALTH) { HealthScreen(nav) }
            composable(Routes.REPORT) { ReportScreen(nav) }
            composable(Routes.ASK_NINO) { AskNinoScreen(nav) }
            composable(
                Routes.TV_INSTALL,
                arguments = listOf(navArgument(Routes.TV_INSTALL_ARG_HOST) { type = NavType.StringType; nullable = true; defaultValue = null }),
            ) { e -> TvInstallScreen(nav, e.arguments?.getString(Routes.TV_INSTALL_ARG_HOST)) }
        }

        val suppressed by AppSession.robotSuppressed.collectAsState()
        val robotVisible = !splash && route in Routes.WITH_ROBOT && !suppressed
        val robotBottom = if (route == Routes.HOME) 96.dp else 92.dp
        if (robotVisible) {
            FloatingRobot(onClick = { if (route != Routes.ASK_NINO) nav.open(Routes.ASK_NINO) }, bottomOffset = robotBottom)
        }
        if (!splash) TranslationStartedBubble(startedAt, robotVisible, robotBottom)

        AnimatedVisibility(splash, enter = fadeIn(), exit = fadeOut()) {
            SplashAnimation(languageDisplayName(language), onFinished = {
                AppSession.splashDone = true
                splash = false
            })
        }
    }
}
