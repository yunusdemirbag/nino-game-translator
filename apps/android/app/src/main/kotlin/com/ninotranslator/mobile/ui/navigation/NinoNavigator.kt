// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.navigation

import android.net.Uri
import androidx.navigation.NavHostController
import com.ninotranslator.mobile.data.ConsoleKind
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.SetupFlow
import com.ninotranslator.mobile.data.SetupStep
import com.ninotranslator.mobile.data.VideoSource

/** Gezinme yolları. Kapsam dışı ekranlar da burada tanımlı (yer tutucu ekranlarla). */
object Routes {
    const val WELCOME = "welcome"
    const val CONSOLE_TYPE = "console_type"
    const val MICROSOFT_SIGN_IN = "microsoft_sign_in"
    const val XBOX_PICK = "xbox_pick"
    const val PSN_SIGN_IN = "psn_sign_in"
    const val PS5_PAIR = "ps5_pair"
    const val TARGET = "target"
    const val HOME = "home"
    const val VIDEO_SOURCE = "video_source"
    const val PACKS = "packs"
    const val PACK_IMPORT = "pack_import"
    const val PROFILE = "profile"
    const val SETTINGS = "settings"
    const val HISTORY = "history"
    const val HEALTH = "health"
    const val REPORT = "report"
    const val ASK_NINO = "ask_nino"

    /** TV'ye kurulum; isteğe bağlı `host` ile o TV seçili gelir. */
    const val TV_INSTALL = "tv_install?host={host}"
    const val TV_INSTALL_ARG_HOST = "host"
    fun tvInstall(host: String? = null) = if (host.isNullOrBlank()) "tv_install" else "tv_install?host=${Uri.encode(host)}"

    fun of(step: SetupStep): String = when (step) {
        SetupStep.WELCOME -> WELCOME
        SetupStep.CONSOLE_TYPE -> CONSOLE_TYPE
        SetupStep.MICROSOFT_SIGN_IN -> MICROSOFT_SIGN_IN
        SetupStep.XBOX_PICK -> XBOX_PICK
        SetupStep.PSN_SIGN_IN -> PSN_SIGN_IN
        SetupStep.PS5_PAIR -> PS5_PAIR
        SetupStep.TARGET -> TARGET
        SetupStep.HOME -> HOME
    }

    /** Yüzen robot düğmesinin göründüğü ekranlar (ekranlar-1 §5.1). */
    val WITH_ROBOT = setOf(HOME, WELCOME, CONSOLE_TYPE, PSN_SIGN_IN, PS5_PAIR, TARGET, MICROSOFT_SIGN_IN, XBOX_PICK,
        "tv_install", TV_INSTALL, VIDEO_SOURCE)
}

/**
 * Kurulum akışı ve "bitti" ile ilerleme kuralları (ekranlar-1 §3.2–3.4). Ekranlar doğrudan [NavHostController]
 * yerine bunu kullanır.
 */
class NinoNavigator(val nav: NavHostController) {
    private val settings get() = Nino.settings
    private val secrets get() = Nino.secrets

    /** Geride ekran var mı (geri düğmesi yalnız o zaman görünür; "Şimdilik Atla" yalnız yokken). */
    fun canGoBack(): Boolean = nav.previousBackStackEntry != null

    /** Açılıştaki ilk ekran (§3.1). */
    fun startRoute(): String = Routes.of(SetupFlow.next(settings, secrets))

    fun open(route: String) = nav.navigate(route) { launchSingleTop = true }

    fun back() {
        nav.popBackStack()
    }

    /** Bir kurulum adımı bitti: sıradaki eksik adım (§3.2). */
    fun finishStep() {
        val next = SetupFlow.next(settings, secrets)
        if (canGoBack()) {
            when (next) {
                SetupStep.HOME -> nav.popBackStack()
                else -> replaceCurrent(Routes.of(next))
            }
        } else {
            resetTo(Routes.of(next))
        }
    }

    /** "Şimdilik Atla" (§3.3): kurulum atlandı işaretlenir ve ilerlenir. */
    fun skipSetup() {
        settings.setupSkipped = true
        finishStep()
    }

    /** PSN girişi bitti: PS5 eşli değilse ve ana ekrandan gelindiyse PS5 eşleme yerine geçer. */
    fun psnSignInDone() {
        if (canGoBack() && secrets.console == null) replaceCurrent(Routes.PS5_PAIR) else finishStep()
    }

    /** Microsoft girişi bitti: Xbox seçilmemişse ve ana ekrandan gelindiyse Xbox seçimi yerine geçer. */
    fun microsoftSignInDone() {
        if (canGoBack() && settings.xboxConsole == null) replaceCurrent(Routes.XBOX_PICK) else finishStep()
    }

    /** TV'ye kurulum bitti ("Ana ekrana geç"). */
    fun tvInstallDone() {
        if (SetupFlow.next(settings, secrets) == SetupStep.HOME) resetTo(Routes.HOME) else nav.popBackStack()
    }

    /** Görüntü kaynağı kaydedildi: bir geri, sonra Xbox için eksik giriş/seçim. */
    fun videoSourceSaved() {
        nav.popBackStack()
        if (settings.videoSource == VideoSource.XBOX) {
            when {
                secrets.xboxToken == null -> open(Routes.MICROSOFT_SIGN_IN)
                settings.xboxConsole == null -> open(Routes.XBOX_PICK)
            }
        }
    }

    /** Eşleme akışı (§3.4). */
    fun openPairing() {
        val step = SetupFlow.pairingStep(settings.consoleKind, secrets.accountId != null, secrets.xboxToken != null)
        open(Routes.of(step))
    }

    /** Eşli değilken başlatma denetimine dokunmak (§7 "kilitli dokunuş"). */
    fun lockedTap() {
        if (settings.videoSource == VideoSource.CAPTURE_CARD) open(Routes.VIDEO_SOURCE) else openPairing()
    }

    /** Konsol kısa yolu: kart → Görüntü kaynağı; değilse eşleme akışı. */
    fun openConsoleShortcut() = lockedTap()

    private fun replaceCurrent(route: String) {
        val current = nav.currentDestination?.route
        nav.navigate(route) {
            if (current != null) popUpTo(current) { inclusive = true }
            launchSingleTop = true
        }
    }

    private fun resetTo(route: String) {
        nav.navigate(route) {
            popUpTo(nav.graph.id) { inclusive = true }
            launchSingleTop = true
        }
    }

    companion object {
        /** Ana ekranda konsol etiketi için. */
        fun consoleLabel(kind: ConsoleKind): String = if (kind == ConsoleKind.XBOX) "Xbox" else "PS5"
    }
}
