// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.psn

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.Nino
import com.ninotranslator.mobile.remoteplay.PsnLogin
import com.ninotranslator.mobile.ui.components.GhostButton
import com.ninotranslator.mobile.ui.components.GlassIconRow
import com.ninotranslator.mobile.ui.components.InfoDialog
import com.ninotranslator.mobile.ui.components.NinoScreen
import com.ninotranslator.mobile.ui.components.NinoTextField
import com.ninotranslator.mobile.ui.components.NinoTopBar
import com.ninotranslator.mobile.ui.components.NoteTile
import com.ninotranslator.mobile.ui.components.PrimaryButton
import com.ninotranslator.mobile.ui.components.ScreenHeader
import com.ninotranslator.mobile.ui.components.StageCard
import com.ninotranslator.mobile.ui.navigation.NinoNavigator
import com.ninotranslator.mobile.ui.screens.Screens
import com.ninotranslator.mobile.ui.screens.SmallNote
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val INTRO = 0
private const val WEB = 1
private const val BROWSER = 2

/**
 * PSN girişi (ekranlar-2 "PSN girişi"): tanıtım, uygulama içi giriş, tarayıcıda giriş. Hal, uygulama arka planda
 * kapatılıp açılsa da korunur. Sonuç: 8 baytlık hesap kimliği `Nino.secrets.setAccountId` ile saklanır.
 */
@Composable
fun PsnSignInScreen(nav: NinoNavigator) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var mode by rememberSaveable { mutableStateOf(INTRO) }
    var failure by rememberSaveable { mutableStateOf<String?>(null) }
    var googleNote by rememberSaveable { mutableStateOf(false) }
    var field by rememberSaveable { mutableStateOf("") }
    var lastTried by rememberSaveable { mutableStateOf<String?>(null) }
    var completing by remember { mutableStateOf(false) }
    var why by remember { mutableStateOf(false) }
    val tooMany = stringResource(R.string.psn_too_many)

    fun complete(url: String) {
        if (completing) return
        completing = true
        lastTried = url
        scope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { PsnLogin.accountIdFromRedirect(url) }
            }
            completing = false
            // Kod tek kullanımlık: panoda hâlâ aynı adres duruyorsa temizlenir.
            if (PsnLogin.extractRedirect(Screens.clipboardText(context)) == url) Screens.clearClipboard(context)
            val saved = result.getOrNull()?.let { id -> withContext(Dispatchers.IO) { Nino.secrets.setAccountId(id) } }
            if (saved == true) {
                failure = null
                nav.psnSignInDone()
                return@launch
            }
            result.onSuccess {
                // Güvenli depoya yazılamadı.
                failure = context.getString(R.string.psn_error_keystore)
                mode = INTRO
            }.onFailure { e ->
                val le = e as? PsnLogin.LoginException
                failure = when {
                    le?.rateLimited == true -> tooMany
                    le?.problem == PsnLogin.Problem.TIMEOUT -> context.getString(R.string.psn_error_timeout)
                    le?.problem == PsnLogin.Problem.NETWORK -> context.getString(R.string.psn_error_network)
                    le?.problem == PsnLogin.Problem.BAD_RESPONSE -> context.getString(R.string.psn_error_response)
                    // Sunucunun hata kodu ve açıklaması olduğu gibi (teknik ayrıntı).
                    else -> e.message ?: e.javaClass.simpleName
                }
                mode = INTRO
            }
        }
    }

    fun toBrowser(google: Boolean) {
        googleNote = google
        mode = BROWSER
        Screens.openUrl(context, PsnLogin.authorizeUrl)
    }

    BackHandler(enabled = mode != INTRO) { mode = INTRO }

    when (mode) {
        WEB -> PsnWebLogin(
            completing = completing,
            onClose = { mode = INTRO },
            onBrowser = { toBrowser(false) },
            onRedirect = { complete(it) },
            onGoogle = { toBrowser(true) },
        )
        BROWSER -> BrowserLogin(field, { field = it }, googleNote, completing,
            onBack = { mode = INTRO },
            onReopen = { Screens.openUrl(context, PsnLogin.authorizeUrl) },
            onNext = { PsnLogin.extractRedirect(field)?.let { complete(it) } },
            onClipboard = { text ->
                val url = PsnLogin.extractRedirect(text)
                if (url != null && url != lastTried) { field = url; complete(url) }
            })
        else -> {
            // Tanıtım görünür görünmez eski tarayıcı verisi silinmeye başlar.
            LaunchedEffect(Unit) { PsnWebCleanup.start() }
            val canBack = nav.canGoBack()
            NinoScreen(
                topBar = {
                    NinoTopBar(onBack = if (canBack) nav::back else null, actions = {
                        if (!canBack) GhostButton(stringResource(R.string.skip_for_now), nav::skipSetup)
                    })
                },
                bottom = {
                    GhostButton(stringResource(R.string.psn_why), { why = true })
                    PrimaryButton(stringResource(R.string.psn_open), { failure = null; mode = WEB })
                },
            ) {
                ScreenHeader(stringResource(R.string.psn_title), step = stringResource(R.string.setup_step, 1),
                    body = stringResource(R.string.psn_body))
                StageCard(height = 270.dp) {
                    GlassIconRow(Icons.Filled.Person, stringResource(R.string.psn_free), stringResource(R.string.psn_free_note))
                    GlassIconRow(Icons.Filled.PlayArrow, stringResource(R.string.psn_you_play), stringResource(R.string.psn_you_play_note))
                    GlassIconRow(Icons.Filled.Lock, stringResource(R.string.psn_password_safe), stringResource(R.string.psn_password_safe_note))
                }
                NoteTile(stringResource(R.string.psn_main_account))
                failure?.let {
                    NoteTile(stringResource(R.string.psn_failed, it))
                    GhostButton(stringResource(R.string.psn_browser), { toBrowser(false) })
                }
            }
            if (why) InfoDialog(stringResource(R.string.psn_why), stringResource(R.string.psn_why_body)) { why = false }
        }
    }
}

/** Tarayıcıda giriş hali: adres alanı, panodan otomatik alma. */
@Composable
private fun BrowserLogin(
    field: String,
    onField: (String) -> Unit,
    googleNote: Boolean,
    completing: Boolean,
    onBack: () -> Unit,
    onReopen: () -> Unit,
    onNext: () -> Unit,
    onClipboard: (String?) -> Unit,
) {
    val context = LocalContext.current
    val window = LocalWindowInfo.current
    // Pencere her odak kazandığında (tarayıcıdan dönünce) pano okunur.
    LaunchedEffect(window) {
        snapshotFlow { window.isWindowFocused }.collect { focused -> if (focused) onClipboard(Screens.clipboardText(context)) }
    }
    val valid = PsnLogin.extractRedirect(field) != null
    NinoScreen(
        topBar = { NinoTopBar(onBack = onBack) },
        bottom = {
            GhostButton(stringResource(R.string.psn_browser_reopen), onReopen)
            PrimaryButton(stringResource(R.string.next), onNext, enabled = valid && !completing)
        },
    ) {
        ScreenHeader(stringResource(R.string.psn_browser_title), body = stringResource(R.string.psn_browser_body))
        if (googleNote) SmallNote(stringResource(R.string.psn_browser_google))
        NinoTextField(field, onField, stringResource(R.string.psn_browser_field), singleLine = false,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri))
        if (field.isNotBlank() && !valid) NoteTile(stringResource(R.string.psn_browser_wrong))
    }
}
