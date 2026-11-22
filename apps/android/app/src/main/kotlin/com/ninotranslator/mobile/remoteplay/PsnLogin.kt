// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.remoteplay

import com.ninotranslator.core.http.HttpRequest
import com.ninotranslator.core.http.HttpTimeoutException
import com.ninotranslator.core.http.HttpTransport
import com.ninotranslator.core.http.UrlConnectionTransport
import com.ninotranslator.core.json.Json
import java.net.URLDecoder
import java.net.URLEncoder
import java.util.Base64

/**
 * Sony girişi (ekranlar-2 "PSN girişi", remote-play.md §4): yetkilendirme adresi, yönlendirme adresinin ayıklanması,
 * kodun jetona ve jetonun 8 baytlık hesap kimliğine çevrilmesi. Jeton saklanmaz. Saf Java; birim testi var.
 */
object PsnLogin {
    const val AUTHORIZE_URL = "https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/authorize"
    const val TOKEN_URL = "https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/token"
    const val REDIRECT = "https://remoteplay.dl.playstation.net/remoteplay/redirect"
    const val CLIENT_ID = "ba495a24-818c-472b-b12d-ff231c1b5745"
    /** Remote Play istemcisinin herkese açık sırrı (masaüstü Nino ile aynı). */
    private const val CLIENT_SECRET = "mvaiZkRsAsI1IBkY"
    const val SCOPE = "psn:clientapp referenceDataService:countryConfig.read pushNotification:webSocket.desktop.connect sessionManager:remotePlaySession.system.update"

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8").replace("+", "%20")

    val authorizeUrl: String by lazy {
        val params = listOf(
            "service_entity" to "urn:service-entity:psn",
            "response_type" to "code",
            "client_id" to CLIENT_ID,
            "redirect_uri" to REDIRECT,
            "scope" to SCOPE,
            "request_locale" to "en_US",
            "ui" to "pr",
            "service_logo" to "ps",
            "layout_type" to "popup",
            "smcid" to "remoteplay",
            "prompt" to "always",
            "PlatformPrivacyWs1" to "minimal",
        )
        AUTHORIZE_URL + "?" + params.joinToString("&") { (k, v) -> "$k=${enc(v)}" }
    }

    fun isRedirect(url: String?): Boolean = url != null && url.startsWith(REDIRECT)

    fun isGoogle(url: String?): Boolean {
        val host = url?.substringAfter("://", "")?.substringBefore('/')?.substringBefore(':')?.lowercase() ?: return false
        return host == "accounts.google.com"
    }

    /** Metnin içinden yönlendirme adresi: boşluk, `"`, `<`, `>` görülene kadar. Geçerli değilse null. */
    fun extractRedirect(text: String?): String? {
        if (text == null) return null
        val i = text.indexOf(REDIRECT)
        if (i < 0) return null
        var end = i
        while (end < text.length && !text[end].isWhitespace() && text[end] != '"' && text[end] != '<' && text[end] != '>') end++
        val url = text.substring(i, end)
        val q = query(url)
        return url.takeIf { !q["code"].isNullOrEmpty() || q.containsKey("error") }
    }

    /** Adresin sorgu parametreleri (çözülmüş). */
    fun query(url: String): Map<String, String> {
        val q = url.substringAfter('?', "").substringBefore('#')
        if (q.isEmpty()) return emptyMap()
        return q.split('&').filter { it.isNotEmpty() }.associate { part ->
            val k = part.substringBefore('=')
            val v = part.substringAfter('=', "")
            dec(k) to dec(v)
        }
    }

    private fun dec(s: String) = runCatching { URLDecoder.decode(s, "UTF-8") }.getOrDefault(s)

    /** Yönlendirmedeki kod ya da Sony'nin hata metni. */
    sealed interface Redirect {
        data class Code(val code: String) : Redirect
        data class Error(val message: String, val rateLimited: Boolean) : Redirect
    }

    fun parseRedirect(url: String): Redirect {
        val q = query(url)
        q["code"]?.takeIf { it.isNotEmpty() }?.let { return Redirect.Code(it) }
        val msg = listOfNotNull(q["error"], q["error_description"]?.replace('+', ' '), q["error_code"])
            .filter { it.isNotBlank() }.joinToString(" · ").ifEmpty { "unknown" }
        val l = msg.lowercase()
        return Redirect.Error(msg, "too many" in l || "too_many" in l || "rate limit" in l)
    }

    /** Hatanın türü: arayüz [TIMEOUT], [NETWORK] ve [BAD_RESPONSE]'u kendi metniyle, [SERVER]'ı sunucunun ayrıntısıyla gösterir. */
    enum class Problem { SERVER, TIMEOUT, NETWORK, BAD_RESPONSE }

    /** Giriş hatası; [message] teknik ayrıntı (sunucunun hata kodu ya da günlük için). */
    class LoginException(message: String, val rateLimited: Boolean = false, val problem: Problem = Problem.SERVER) : Exception(message)

    /** Engelleyici (IO iş parçacığında): yönlendirme adresi → 8 baytlık hesap kimliği. */
    fun accountIdFromRedirect(url: String, http: HttpTransport = UrlConnectionTransport): ByteArray =
        when (val r = parseRedirect(url)) {
            is Redirect.Error -> throw LoginException(r.message, r.rateLimited)
            is Redirect.Code -> exchange(r.code, http)
        }

    fun exchange(code: String, http: HttpTransport): ByteArray {
        val basic = "Basic " + Base64.getEncoder().encodeToString("$CLIENT_ID:$CLIENT_SECRET".toByteArray(Charsets.UTF_8))
        val form = "grant_type=authorization_code&code=${enc(code)}&scope=${enc(SCOPE)}&redirect_uri=${enc(REDIRECT)}"
        val headers = mapOf("Authorization" to basic, "Content-Type" to "application/x-www-form-urlencoded")
        val token = try {
            val r = http.send(HttpRequest(TOKEN_URL, "POST", headers, form.toByteArray(Charsets.UTF_8), 30_000, 30_000))
            if (!r.ok) throw LoginException("HTTP ${r.status}" + errorOf(r.text), r.status == 429)
            (runCatching { Json.parseObject(r.text) }.getOrNull()?.get("access_token") as? String)
                ?: throw LoginException("access_token", problem = Problem.BAD_RESPONSE)
        } catch (e: HttpTimeoutException) { throw LoginException("timeout", problem = Problem.TIMEOUT) }
        catch (e: java.io.IOException) { throw LoginException(e.message ?: e.javaClass.simpleName, problem = Problem.NETWORK) }
        val info = try {
            val r = http.send(HttpRequest("$TOKEN_URL/${enc(token)}", "GET", mapOf("Authorization" to basic), null, 30_000, 30_000))
            if (!r.ok) throw LoginException("HTTP ${r.status}" + errorOf(r.text), r.status == 429)
            runCatching { Json.parseObject(r.text) }.getOrNull() ?: throw LoginException("user info", problem = Problem.BAD_RESPONSE)
        } catch (e: HttpTimeoutException) { throw LoginException("timeout", problem = Problem.TIMEOUT) }
        catch (e: java.io.IOException) { throw LoginException(e.message ?: e.javaClass.simpleName, problem = Problem.NETWORK) }
        val userId = when (val v = info["user_id"]) { is String -> v; is Number -> v.toLong().toString(); else -> null }
            ?: throw LoginException("user_id", problem = Problem.BAD_RESPONSE)
        return PsnAccountId.fromUserId(userId) ?: throw LoginException("user_id", problem = Problem.BAD_RESPONSE)
    }

    private fun errorOf(text: String): String {
        val m = runCatching { Json.parseObject(text) }.getOrNull() ?: return ""
        return listOfNotNull(m["error"] as? String, m["error_description"] as? String).joinToString(" · ").let { if (it.isEmpty()) "" else " · $it" }
    }
}
