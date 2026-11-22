// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.psn

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.net.http.SslError
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.remoteplay.PsnLogin
import com.ninotranslator.mobile.ui.components.GhostButton
import com.ninotranslator.mobile.ui.components.NinoTopBar
import com.ninotranslator.mobile.ui.components.PrimaryButton
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoType
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull

/** Sony sayfasının açılamama nedeni. */
enum class PsnPageProblem { OFFLINE, TIMEOUT, SSL, HTTP, BLANK, CRASHED, OTHER }

/** Hata ve teknik ayrıntı (ilk hata kalır). */
data class PsnPageError(val problem: PsnPageProblem, val detail: String)

/**
 * Uygulama içi tarayıcının eski verisini (çerezler, localStorage, IndexedDB, service worker) siler. Tanıtım görünür
 * görünmez başlar; tarayıcı açılırken en çok 5 sn beklenir. Tarayıcı kurulu değilse ya da güncelleniyorsa [failed].
 */
object PsnWebCleanup {
    @Volatile private var pending: CompletableDeferred<Boolean>? = null

    /** Silmeyi başlatır (sürüyorsa yenisini başlatmaz). */
    fun start(): CompletableDeferred<Boolean> {
        pending?.takeIf { !it.isCompleted }?.let { return it }
        val d = CompletableDeferred<Boolean>()
        pending = d
        try {
            WebStorage.getInstance().deleteAllData()
            CookieManager.getInstance().removeAllCookies { d.complete(true) }
        } catch (e: Throwable) {
            d.complete(false)
        }
        return d
    }

    /** Biter ya da 5 sn dolar; tarayıcı yoksa false. */
    suspend fun awaitReady(): Boolean = withTimeoutOrNull(5_000) { start().await() } ?: true
}

/**
 * Uygulama içi giriş hali (ekranlar-2 "PSN girişi" §2). Yönlendirme yakalanınca [onRedirect], Google sayfasına
 * gidilince [onGoogle] çağrılır. [completing] true iken (kod jetona çevriliyor) yine "bağlanılıyor" örtüsü görünür.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun PsnWebLogin(
    completing: Boolean,
    onClose: () -> Unit,
    onBrowser: () -> Unit,
    onRedirect: (String) -> Unit,
    onGoogle: () -> Unit,
) {
    var attempt by remember { mutableIntStateOf(0) }
    var progress by remember(attempt) { mutableIntStateOf(0) }
    var ready by remember(attempt) { mutableStateOf(false) }
    var visible by remember(attempt) { mutableStateOf(false) }
    var finishedOnce by remember(attempt) { mutableStateOf(false) }
    var captured by remember(attempt) { mutableStateOf(false) }
    var error by remember(attempt) { mutableStateOf<PsnPageError?>(null) }
    var webView by remember(attempt) { mutableStateOf<WebView?>(null) }
    val redirect by rememberUpdatedState(onRedirect)
    val google by rememberUpdatedState(onGoogle)

    fun fail(p: PsnPageProblem, detail: String) { if (error == null && !captured) error = PsnPageError(p, detail) }

    // Çerez silme bitince (en çok 5 sn) sayfa açılır.
    LaunchedEffect(attempt, webView) {
        val wv = webView ?: return@LaunchedEffect
        val ok = PsnWebCleanup.awaitReady()
        if (!ok) { fail(PsnPageProblem.CRASHED, "WebView"); return@LaunchedEffect }
        wv.loadUrl(PsnLogin.authorizeUrl)
    }
    // Zaman aşımı: tarayıcının olaylarına bağlı değil.
    LaunchedEffect(attempt) {
        delay(20_000)
        if (!ready && !captured) fail(if (finishedOnce) PsnPageProblem.BLANK else PsnPageProblem.TIMEOUT, "20 s")
    }
    // Hazır mı denetimi: görünür ya da bittiyse her 1 sn'de dokunulabilir öğe sayısı.
    LaunchedEffect(attempt, visible, finishedOnce) {
        if (!visible && !finishedOnce) return@LaunchedEffect
        while (!ready && error == null && !captured) {
            webView?.evaluateJavascript(READY_JS) { v -> if ((v?.trim('"')?.toIntOrNull() ?: 0) > 0) ready = true }
            delay(1_000)
        }
    }
    DisposableEffect(attempt) { onDispose { webView?.let { runCatching { it.stopLoading(); it.destroy() } } } }
    DisposableEffect(Unit) {
        com.ninotranslator.mobile.ui.shell.AppSession.robotSuppressed.value = true
        onDispose { com.ninotranslator.mobile.ui.shell.AppSession.robotSuppressed.value = false }
    }

    Column(Modifier.fillMaxSize().background(NinoColors.Background).safeDrawingPadding()) {
        Box(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
            NinoTopBar(title = stringResource(R.string.psn_open), onClose = onClose)
        }
        if (progress < 100 && error == null) {
            LinearProgressIndicator(progress = { progress / 100f }, Modifier.fillMaxWidth().height(2.dp),
                color = NinoColors.Accent, trackColor = NinoColors.BorderStrong)
        }
        Box(Modifier.weight(1f).fillMaxWidth()) {
            key(attempt) { AndroidView(
                factory = { ctx ->
                    try {
                        WebView(ctx).apply {
                            layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                            setBackgroundColor(android.graphics.Color.parseColor("#121314"))
                            settings.javaScriptEnabled = true
                            settings.domStorageEnabled = true
                            CookieManager.getInstance().setAcceptCookie(true)
                            CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                            webChromeClient = object : WebChromeClient() {
                                override fun onProgressChanged(view: WebView, newProgress: Int) { progress = newProgress }
                            }
                            webViewClient = object : WebViewClient() {
                                private fun intercept(view: WebView, url: String?): Boolean {
                                    if (captured) return true
                                    if (PsnLogin.isRedirect(url)) {
                                        captured = true
                                        view.stopLoading()
                                        redirect(url!!)
                                        return true
                                    }
                                    if (PsnLogin.isGoogle(url)) {
                                        view.stopLoading()
                                        google()
                                        return true
                                    }
                                    return false
                                }

                                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                                    request.isForMainFrame && intercept(view, request.url?.toString())

                                override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) { intercept(view, url) }
                                override fun onPageCommitVisible(view: WebView, url: String?) { visible = true }
                                override fun onPageFinished(view: WebView, url: String?) { if (!captured) finishedOnce = true }

                                override fun onReceivedError(view: WebView, request: WebResourceRequest, err: WebResourceError) {
                                    if (!request.isForMainFrame) return
                                    val p = when (err.errorCode) {
                                        ERROR_HOST_LOOKUP, ERROR_CONNECT, ERROR_PROXY_AUTHENTICATION -> PsnPageProblem.OFFLINE
                                        ERROR_TIMEOUT -> PsnPageProblem.TIMEOUT
                                        else -> PsnPageProblem.OTHER
                                    }
                                    fail(p, "${err.errorCode} ${err.description}")
                                }

                                override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                                    if (request.isForMainFrame) fail(PsnPageProblem.HTTP, "HTTP ${response.statusCode}")
                                }

                                @SuppressLint("WebViewClientOnReceivedSslError")
                                override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, e: SslError) {
                                    handler.cancel()
                                    fail(PsnPageProblem.SSL, "SSL ${e.primaryError}")
                                }

                                override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                                    fail(PsnPageProblem.CRASHED, if (detail.didCrash()) "renderer crash" else "renderer killed")
                                    webView = null
                                    return true
                                }
                            }
                            webView = this
                        }
                    } catch (e: Throwable) {
                        fail(PsnPageProblem.CRASHED, e.javaClass.simpleName)
                        android.view.View(ctx)
                    }
                },
                modifier = Modifier.fillMaxSize(),
            ) }
            val err = error
            if (err != null) {
                PageError(err, onRetry = { attempt++ ; PsnWebCleanup.start() }, onBrowser = onBrowser)
            } else if (!ready || completing || captured) {
                Column(Modifier.fillMaxSize().background(NinoColors.Background).padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
                    horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator(color = NinoColors.Accent)
                    Text(stringResource(R.string.psn_loading), style = NinoType.Headline)
                    Text(stringResource(R.string.psn_loading_hint), style = NinoType.Body, color = NinoColors.InkSecondary, textAlign = TextAlign.Center)
                }
            }
        }
        if (error == null) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                GhostButton(stringResource(R.string.psn_browser), onBrowser)
                Spacer(Modifier.weight(1f))
                GhostButton(stringResource(R.string.close), onClose, color = NinoColors.InkSecondary)
            }
        }
    }
}

@Composable
private fun PageError(err: PsnPageError, onRetry: () -> Unit, onBrowser: () -> Unit) {
    val body = stringResource(when (err.problem) {
        PsnPageProblem.OFFLINE -> R.string.psn_problem_offline
        PsnPageProblem.TIMEOUT -> R.string.psn_problem_timeout
        PsnPageProblem.SSL -> R.string.psn_problem_ssl
        PsnPageProblem.HTTP -> R.string.psn_problem_http
        PsnPageProblem.BLANK -> R.string.psn_problem_blank
        PsnPageProblem.CRASHED -> R.string.psn_problem_crashed
        PsnPageProblem.OTHER -> R.string.psn_problem_other
    })
    Column(Modifier.fillMaxSize().background(NinoColors.Background).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally) {
        Text(stringResource(R.string.psn_page_failed), style = NinoType.Title, textAlign = TextAlign.Center)
        Text("$body (${err.detail})", style = NinoType.Body, textAlign = TextAlign.Center)
        Text(stringResource(R.string.psn_page_failed_hint), style = NinoType.Body, color = NinoColors.InkSecondary, textAlign = TextAlign.Center)
        PrimaryButton(stringResource(R.string.psn_retry), onRetry)
        GhostButton(stringResource(R.string.psn_browser), onBrowser)
    }
}

/** Sayfadaki gizli olmayan giriş kutuları ve düğmeler. */
private const val READY_JS = "(function(){var n=0;document.querySelectorAll('input,button,[role=button]').forEach(function(e){" +
    "if(e.type==='hidden')return;var r=e.getBoundingClientRect();var s=getComputedStyle(e);" +
    "if(r.width>0&&r.height>0&&s.visibility!=='hidden'&&s.display!=='none')n++;});return n;})()"

