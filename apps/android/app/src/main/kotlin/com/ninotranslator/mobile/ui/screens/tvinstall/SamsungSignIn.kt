// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.tvinstall

import android.annotation.SuppressLint
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.ui.components.GhostButton
import com.ninotranslator.mobile.ui.components.NinoTopBar
import com.ninotranslator.mobile.ui.screens.Screens
import com.ninotranslator.mobile.ui.theme.NinoColors

/**
 * Samsung girişi (kurulum giriş isteyince TV kurulum ekranının yerine geçer). Jeton telefonda dinleyen küçük sunucuya
 * gelir (kurulum katmanının işi); burası yalnız sayfayı gösterir. Geri / kapat girişi bırakır.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun SamsungSignIn(url: String, onClose: () -> Unit) {
    val context = LocalContext.current
    BackHandler(onBack = onClose)
    androidx.compose.runtime.DisposableEffect(Unit) {
        com.ninotranslator.mobile.ui.shell.AppSession.robotSuppressed.value = true
        onDispose { com.ninotranslator.mobile.ui.shell.AppSession.robotSuppressed.value = false }
    }
    Column(Modifier.fillMaxSize().background(NinoColors.Background).safeDrawingPadding()) {
        Box(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
            NinoTopBar(title = stringResource(R.string.tvinstall_signin_title), onClose = onClose, actions = {
                GhostButton(stringResource(R.string.tvinstall_signin_browser), { Screens.openUrl(context, url) })
            })
        }
        AndroidView(
            factory = { ctx ->
                runCatching {
                    WebView(ctx).apply {
                        layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                        setBackgroundColor(android.graphics.Color.parseColor("#EEF3FB"))
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                        settings.userAgentString = settings.userAgentString.replace("; wv", "")
                        CookieManager.getInstance().setAcceptCookie(true)
                        CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                        webViewClient = WebViewClient()
                        loadUrl(url)
                    }
                }.getOrElse { android.view.View(ctx) }
            },
            modifier = Modifier.fillMaxWidth().weight(1f),
        )
    }
}
