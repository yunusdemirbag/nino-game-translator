// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.xbox

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.data.XboxConsole
import com.ninotranslator.mobile.ui.components.GhostButton
import com.ninotranslator.mobile.ui.components.NinoScreen
import com.ninotranslator.mobile.ui.components.NinoTag
import com.ninotranslator.mobile.ui.components.NinoTile
import com.ninotranslator.mobile.ui.components.NinoTopBar
import com.ninotranslator.mobile.ui.components.NoteTile
import com.ninotranslator.mobile.ui.components.PrimaryButton
import com.ninotranslator.mobile.ui.components.ScreenHeader
import com.ninotranslator.mobile.ui.components.StatusText
import com.ninotranslator.mobile.ui.components.TileLabel
import com.ninotranslator.mobile.ui.navigation.NinoNavigator
import com.ninotranslator.mobile.ui.screens.Screens
import com.ninotranslator.mobile.ui.screens.SmallNote
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoType
import com.ninotranslator.mobile.xbox.XboxAccounts
import com.ninotranslator.mobile.xbox.XboxErrorKind
import com.ninotranslator.mobile.xbox.XboxException
import com.ninotranslator.mobile.xbox.XboxSignIn

/** Xbox hata metni (ekranlar-2 "Microsoft girişi"). */
fun xboxErrorText(context: Context, e: XboxException): String = when (e.kind) {
    XboxErrorKind.SIGN_IN -> context.getString(R.string.xbox_error_sign_in)
    XboxErrorKind.EXPIRED -> context.getString(R.string.xbox_login_expired)
    XboxErrorKind.NO_ACCOUNT -> context.getString(R.string.xbox_error_no_account)
    XboxErrorKind.OFFLINE -> context.getString(R.string.xbox_error_offline)
    XboxErrorKind.UNEXPECTED -> context.getString(R.string.xbox_error_unexpected, e.detail ?: "?")
    XboxErrorKind.NOT_READY -> context.getString(R.string.not_ready_yet)
}

/** Microsoft girişi (cihaz kodu, Adım 1/3). Bekleme ekrandan bağımsızdır ([XboxSignIn]). */
@Composable
fun MicrosoftSignInScreen(nav: NinoNavigator) {
    val context = LocalContext.current
    val state by XboxSignIn.state.collectAsState()
    val secretRev by Nino.secrets.revision.collectAsState()
    val signedIn = remember(secretRev) { Nino.secrets.xboxToken != null }
    var noBrowser by remember { mutableStateOf<String?>(null) }
    val copied = stringResource(R.string.xbox_login_copied)

    LaunchedEffect(state.done) {
        if (state.done) {
            XboxSignIn.consumeDone()
            nav.microsoftSignInDone()
        }
    }

    fun openPage(uri: String, code: String) {
        Screens.copy(context, code)
        Screens.toast(context, copied)
        noBrowser = if (Screens.openUrl(context, uri)) null else uri
    }

    val canBack = nav.canGoBack()
    NinoScreen(
        topBar = {
            NinoTopBar(onBack = if (canBack) { { XboxSignIn.cancel(); nav.back() } } else null, actions = {
                if (!canBack) GhostButton(stringResource(R.string.skip_for_now), { XboxSignIn.cancel(); nav.skipSetup() })
            })
        },
        bottom = {
            state.code?.let { c -> GhostButton(stringResource(R.string.xbox_login_open), { openPage(c.verificationUri, c.userCode) }) }
            PrimaryButton(stringResource(R.string.xbox_login_button), {
                noBrowser = null
                val main = Handler(Looper.getMainLooper())
                XboxSignIn.start { code -> main.post { openPage(code.verificationUri, code.userCode) } }
            }, enabled = !state.working && !state.waiting)
        },
    ) {
        ScreenHeader(stringResource(R.string.xbox_login_title), step = stringResource(R.string.setup_step, 1),
            body = stringResource(R.string.xbox_login_body))
        NinoTag(stringResource(R.string.beta))
        val code = state.code
        if (signedIn && code == null) StatusText(stringResource(R.string.xbox_login_done), good = true)
        if (code == null && !state.waiting) Text(stringResource(R.string.xbox_login_how), style = NinoType.Body, color = NinoColors.InkSecondary)
        if (code != null) {
            NinoTile {
                TileLabel(stringResource(R.string.xbox_login_code))
                Text(code.userCode, Modifier.clickable { Screens.copy(context, code.userCode); Screens.toast(context, copied) },
                    fontSize = 32.sp, fontWeight = FontWeight.Bold, color = NinoColors.Accent, letterSpacing = 2.sp)
                Text(code.verificationUri.removePrefix("https://"), Modifier.clickable { openPage(code.verificationUri, code.userCode) },
                    style = NinoType.Body, color = NinoColors.Accent, textDecoration = TextDecoration.Underline)
                SmallNote(stringResource(R.string.xbox_login_steps))
                if (state.waiting) SmallNote(stringResource(R.string.xbox_login_waiting))
            }
        }
        noBrowser?.let { NoteTile(stringResource(R.string.xbox_login_failed, stringResource(R.string.xbox_login_no_browser, it))) }
        state.error?.let { NoteTile(stringResource(R.string.xbox_login_failed, xboxErrorText(context, it))) }
    }
}

/** Xbox seçimi (Adım 2/3). */
@Composable
fun XboxPickScreen(nav: NinoNavigator) {
    val context = LocalContext.current
    val settings = Nino.settings
    var reload by remember { mutableIntStateOf(0) }
    var loading by remember { mutableStateOf(true) }
    var list by remember { mutableStateOf<List<XboxConsole>>(emptyList()) }
    var error by remember { mutableStateOf<XboxException?>(null) }
    var selectedId by rememberSaveable { mutableStateOf(settings.xboxConsole?.id) }

    LaunchedEffect(reload) {
        loading = true; error = null
        try {
            list = XboxAccounts.current.listConsoles()
            if (list.none { it.id == selectedId && it.streamingEnabled }) selectedId = list.firstOrNull { it.streamingEnabled }?.id
        } catch (e: XboxException) {
            error = e; list = emptyList()
        } catch (e: Exception) {
            error = XboxException(XboxErrorKind.UNEXPECTED, e.message); list = emptyList()
        }
        loading = false
    }
    val needSignIn = error?.kind == XboxErrorKind.SIGN_IN
    val chosen = list.firstOrNull { it.id == selectedId && it.streamingEnabled }
    val canBack = nav.canGoBack()
    NinoScreen(
        topBar = {
            NinoTopBar(onBack = if (canBack) nav::back else null, actions = {
                if (!canBack) GhostButton(stringResource(R.string.skip_for_now), nav::skipSetup)
            })
        },
        bottom = {
            GhostButton(stringResource(R.string.xbox_consoles_refresh), { reload++ })
            if (needSignIn) {
                PrimaryButton(stringResource(R.string.xbox_login_button), { nav.open(com.ninotranslator.mobile.ui.navigation.Routes.MICROSOFT_SIGN_IN) })
            } else {
                PrimaryButton(stringResource(R.string.xbox_console_choose), {
                    chosen?.let { settings.xboxConsole = it; nav.finishStep() }
                }, enabled = chosen != null)
            }
        },
    ) {
        ScreenHeader(stringResource(R.string.xbox_consoles_title), step = stringResource(R.string.setup_step, 2),
            body = stringResource(R.string.xbox_consoles_body))
        when {
            loading -> NinoTile { Text(stringResource(R.string.xbox_consoles_searching), style = NinoType.Body) }
            list.isEmpty() && error == null -> SmallNote(stringResource(R.string.xbox_consoles_empty))
        }
        list.forEach { x ->
            NinoTile(selected = x.id == selectedId && x.streamingEnabled, onClick = if (x.streamingEnabled) { { selectedId = x.id } } else null) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(if (x.streamingEnabled) Icons.Filled.CheckCircle else Icons.Filled.Warning, null, Modifier.size(24.dp),
                        tint = if (x.streamingEnabled) NinoColors.Success else NinoColors.Warning)
                    Column(Modifier.weight(1f)) {
                        Text(x.name?.takeIf { it.isNotBlank() } ?: x.model ?: "Xbox", style = NinoType.Headline)
                        SmallNote(stringResource(if (x.streamingEnabled) R.string.xbox_console_ready else R.string.xbox_console_off))
                    }
                }
            }
        }
        error?.let { NoteTile(xboxErrorText(context, it)) }
    }
}
