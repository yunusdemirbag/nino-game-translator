// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.xbox

import com.ninotranslator.core.http.HttpRequest
import com.ninotranslator.core.http.HttpResponse
import com.ninotranslator.core.http.HttpTransport
import com.ninotranslator.core.json.Json
import com.ninotranslator.core.json.list
import com.ninotranslator.core.json.obj
import com.ninotranslator.core.json.str
import java.io.IOException
import java.net.URLEncoder
import java.time.Instant

/** Kalıcı Microsoft kullanıcı jetonu (servis.md 10.1 madde 4). Uygulamada `Nino.secrets`, testte bellek. */
interface XboxTokenStore {
    /** Saklanan jeton yanıtı (+ `expires_on`); yoksa ya da yenileme jetonu boşsa null. */
    fun load(): Map<String, Any?>?
    /** Yanıtı olduğu gibi saklar, `expires_on` = şimdi + `expires_in`; yanıtta yenileme jetonu yoksa öncekini korur. */
    fun save(response: Map<String, Any?>, nowMs: Long)
    fun clear()
}

/** Süreli jeton; [uhs] yalnız Xbox Live jetonlarında. */
data class TimedToken(val value: String, val expiresAtMs: Long, val uhs: String? = null)

/** Ev yayını sunucusu: bölgenin adresi ve yayın jetonu (10.2 madde 4). */
data class XboxStreamHost(val baseUri: String, val token: String, val expiresAtMs: Long)

/** Cihaz kodu isteğinin yanıtı (10.1). */
data class DeviceCodeGrant(
    val deviceCode: String,
    val userCode: String,
    val verificationUri: String,
    val expiresInSec: Long,
    val intervalSec: Long,
)

/** Cihaz kodu sorgusunun sonucu (10.1 madde 3). */
sealed interface DevicePoll {
    data object Pending : DevicePoll
    data object SlowDown : DevicePoll
    data object Expired : DevicePoll
    data object Declined : DevicePoll
    /** 5xx: beklemeye devam. */
    data object ServerBusy : DevicePoll
    data class Done(val response: Map<String, Any?>) : DevicePoll
    data class Failed(val detail: String) : DevicePoll
}

/** Microsoft ve Xbox Live adresleri, istek gövdeleri ve yanıt okuyucuları. Saf; ağ yok. */
object XboxAuthWire {
    const val CLIENT_ID = "1f907974-e22b-4810-a9de-d9647380c97e"
    const val SCOPE = "xboxlive.signin openid profile offline_access"
    const val DEVICE_CODE_URL = "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode"
    const val TOKEN_URL = "https://login.microsoftonline.com/consumers/oauth2/v2.0/token"
    const val USER_AUTH_URL = "https://user.auth.xboxlive.com/user/authenticate"
    const val XSTS_URL = "https://xsts.auth.xboxlive.com/xsts/authorize"
    const val STREAM_LOGIN_URL = "https://xhome.gssv-play-prod.xboxlive.com/v2/login/user"
    const val TRANSFER_URL = "https://login.live.com/oauth20_token.srf"
    const val TRANSFER_SCOPE = "service::http://Passport.NET/purpose::PURPOSE_XBOX_CLOUD_CONSOLE_TRANSFER_TOKEN"
    const val DEVICE_GRANT = "urn:ietf:params:oauth:grant-type:device_code"
    const val RP_XBOXLIVE = "http://xboxlive.com"
    const val RP_GSSV = "http://gssv.xboxlive.com/"
    const val DEFAULT_VERIFY_URI = "https://www.microsoft.com/link"
    const val BROWSER_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0"

    /** Bu XErr'ler "Xbox profili yok / çocuk hesabı / ülke" demektir; diğerleri yeniden giriş. */
    val NO_PROFILE_XERR = setOf(2148916233L, 2148916235L, 2148916236L, 2148916237L, 2148916238L)

    fun form(vararg pairs: Pair<String, String>): String =
        pairs.joinToString("&") { (k, v) -> URLEncoder.encode(k, "UTF-8") + "=" + URLEncoder.encode(v, "UTF-8") }

    fun deviceCodeBody() = form("client_id" to CLIENT_ID, "scope" to SCOPE)
    fun devicePollBody(deviceCode: String) = form("grant_type" to DEVICE_GRANT, "client_id" to CLIENT_ID, "device_code" to deviceCode)
    fun refreshBody(refreshToken: String) =
        form("client_id" to CLIENT_ID, "grant_type" to "refresh_token", "refresh_token" to refreshToken, "scope" to SCOPE)
    fun transferBody(refreshToken: String) =
        form("client_id" to CLIENT_ID, "scope" to TRANSFER_SCOPE, "grant_type" to "refresh_token", "refresh_token" to refreshToken)

    fun userTokenBody(accessToken: String): String = Json.write(linkedMapOf(
        "Properties" to linkedMapOf("AuthMethod" to "RPS", "RpsTicket" to "d=$accessToken", "SiteName" to "user.auth.xboxlive.com"),
        "RelyingParty" to "http://auth.xboxlive.com",
        "TokenType" to "JWT",
    ))

    fun xstsBody(userToken: String, relyingParty: String): String = Json.write(linkedMapOf(
        "Properties" to linkedMapOf("SandboxId" to "RETAIL", "UserTokens" to listOf(userToken)),
        "RelyingParty" to relyingParty,
        "TokenType" to "JWT",
    ))

    fun streamLoginBody(gssvToken: String): String = Json.write(linkedMapOf("token" to gssvToken, "offeringId" to "xhome"))

    fun parseDeviceCode(body: String): DeviceCodeGrant? {
        val m = runCatching { Json.parseObject(body) }.getOrNull() ?: return null
        val device = m.str("device_code")?.takeIf { it.isNotBlank() } ?: return null
        val user = m.str("user_code")?.takeIf { it.isNotBlank() } ?: return null
        return DeviceCodeGrant(
            device, user,
            (m.str("verification_uri") ?: m.str("verification_url"))?.takeIf { it.isNotBlank() } ?: DEFAULT_VERIFY_URI,
            number(m["expires_in"])?.takeIf { it > 0 } ?: 900,
            maxOf(1L, number(m["interval"]) ?: 5),
        )
    }

    fun parsePoll(status: Int, body: String): DevicePoll {
        val m = runCatching { Json.parseObject(body) }.getOrNull()
        if (status in 200..299) return if (m?.str("access_token").isNullOrBlank()) DevicePoll.Failed("no access_token") else DevicePoll.Done(m!!)
        if (status >= 500) return DevicePoll.ServerBusy
        return when (val err = m?.str("error")) {
            "authorization_pending" -> DevicePoll.Pending
            "slow_down" -> DevicePoll.SlowDown
            "expired_token", "code_expired" -> DevicePoll.Expired
            "authorization_declined", "access_denied" -> DevicePoll.Declined
            else -> DevicePoll.Failed(err ?: "HTTP $status")
        }
    }

    /** Xbox Live jetonu: `Token`, `NotAfter`, `DisplayClaims.xui[0].uhs`. */
    fun parseXblToken(body: String): TimedToken? {
        val m = runCatching { Json.parseObject(body) }.getOrNull() ?: return null
        val token = m.str("Token")?.takeIf { it.isNotBlank() } ?: return null
        val until = m.str("NotAfter")?.let(::parseInstant) ?: return null
        @Suppress("UNCHECKED_CAST")
        val uhs = (m.obj("DisplayClaims")?.list("xui")?.firstOrNull() as? Map<String, Any?>)?.str("uhs")
        return TimedToken(token, until, uhs)
    }

    /** XSTS 401 gövdesindeki `XErr`. */
    fun xErr(body: String): Long? = runCatching { number(Json.parseObject(body)["XErr"]) }.getOrNull()

    /** Varsayılan bölge (`isDefault`, yoksa ilki), `gsToken`, `durationInSeconds` (yoksa 30 dk). */
    fun parseStreamHost(body: String, nowMs: Long): XboxStreamHost? {
        val m = runCatching { Json.parseObject(body) }.getOrNull() ?: return null
        val token = m.str("gsToken")?.takeIf { it.isNotBlank() } ?: return null
        @Suppress("UNCHECKED_CAST")
        val regions = m.obj("offeringSettings")?.list("regions")?.mapNotNull { it as? Map<String, Any?> }.orEmpty()
        val region = regions.firstOrNull { it["isDefault"] == true } ?: regions.firstOrNull() ?: return null
        val base = region.str("baseUri")?.trimEnd('/')?.takeIf { it.isNotBlank() } ?: return null
        val seconds = number(m["durationInSeconds"])?.takeIf { it > 0 } ?: 1800
        return XboxStreamHost(base, token, nowMs + seconds * 1000)
    }

    /** ISO 8601 an; saniyenin yedi haneli kesrini de kabul eder (`…T10:16:00.1234567Z`). */
    fun parseInstant(text: String): Long? = runCatching { Instant.parse(text.trim()).toEpochMilli() }.getOrNull()

    fun number(v: Any?): Long? = when (v) {
        is Number -> v.toLong()
        is String -> v.trim().toLongOrNull()
        else -> null
    }
}

/**
 * Jeton zinciri (servis.md 10.2): Microsoft erişim jetonu → Xbox Live kullanıcı jetonu → XSTS (iki RP) → ev yayını
 * girişi; ayrıca konsola aktarım jetonu. Hepsi bellekte, süresine [MARGIN_MS]'den az kalınca yenilenir. Engelleyicidir.
 */
class XboxTokenChain(
    private val http: HttpTransport,
    private val store: XboxTokenStore,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private var access: TimedToken? = null
    private var user: TimedToken? = null
    private val xsts = HashMap<String, TimedToken>()
    private var host: XboxStreamHost? = null
    private var transfer: TimedToken? = null

    private fun fresh(expiresAtMs: Long?) = expiresAtMs != null && expiresAtMs - now() > MARGIN_MS

    /** Bellekteki jetonları unutur (giriş ya da çıkıştan sonra). */
    @Synchronized fun reset() {
        access = null; user = null; xsts.clear(); host = null; transfer = null
    }

    @Synchronized fun accessToken(): String {
        access?.takeIf { fresh(it.expiresAtMs) }?.let { return it.value }
        val saved = store.load() ?: throw XboxException(XboxErrorKind.SIGN_IN)
        val savedToken = saved.str("access_token")
        val savedUntil = saved.str("expires_on")?.let(XboxAuthWire::parseInstant)
        if (!savedToken.isNullOrBlank() && fresh(savedUntil)) {
            return TimedToken(savedToken, savedUntil!!).also { access = it }.value
        }
        val refresh = saved.str("refresh_token")?.takeIf { it.isNotBlank() } ?: throw XboxException(XboxErrorKind.SIGN_IN)
        val r = send(HttpRequest(XboxAuthWire.TOKEN_URL, "POST", FORM, XboxAuthWire.refreshBody(refresh).toByteArray()))
        if (r.status == 400 || r.status == 401) throw XboxException(XboxErrorKind.SIGN_IN)
        if (!r.ok) throw unexpected(r)
        val m = runCatching { Json.parseObject(r.text) }.getOrNull() ?: throw unexpected(r)
        val token = m.str("access_token")?.takeIf { it.isNotBlank() } ?: throw unexpected(r)
        val t = now()
        store.save(m, t)
        val seconds = XboxAuthWire.number(m["expires_in"]) ?: 3600
        return TimedToken(token, t + seconds * 1000).also { access = it }.value
    }

    @Synchronized fun userToken(): TimedToken {
        user?.takeIf { fresh(it.expiresAtMs) }?.let { return it }
        val r = send(HttpRequest.json(XboxAuthWire.USER_AUTH_URL, XboxAuthWire.userTokenBody(accessToken()), mapOf(
            "x-xbl-contract-version" to "1", "Accept" to "application/json",
            "Origin" to "https://www.xbox.com", "Referer" to "https://www.xbox.com/",
        )))
        if (r.status == 400 || r.status == 401 || r.status == 403) throw XboxException(XboxErrorKind.SIGN_IN)
        if (!r.ok) throw unexpected(r)
        return (XboxAuthWire.parseXblToken(r.text) ?: throw unexpected(r)).also { user = it }
    }

    @Synchronized fun xsts(relyingParty: String): TimedToken {
        xsts[relyingParty]?.takeIf { fresh(it.expiresAtMs) }?.let { return it }
        val r = send(HttpRequest.json(XboxAuthWire.XSTS_URL, XboxAuthWire.xstsBody(userToken().value, relyingParty), mapOf(
            "x-xbl-contract-version" to "1", "Accept" to "application/json",
            "User-Agent" to XboxAuthWire.BROWSER_UA, "ms-cv" to "0",
        )))
        if (r.status == 401 || r.status == 403) {
            val err = XboxAuthWire.xErr(r.text)
            throw XboxException(if (err != null && err in XboxAuthWire.NO_PROFILE_XERR) XboxErrorKind.NO_ACCOUNT else XboxErrorKind.SIGN_IN, err?.toString())
        }
        if (!r.ok) throw unexpected(r)
        return (XboxAuthWire.parseXblToken(r.text) ?: throw unexpected(r)).also { xsts[relyingParty] = it }
    }

    @Synchronized fun streamHost(): XboxStreamHost {
        host?.takeIf { fresh(it.expiresAtMs) }?.let { return it }
        val r = send(HttpRequest.json(XboxAuthWire.STREAM_LOGIN_URL, XboxAuthWire.streamLoginBody(xsts(XboxAuthWire.RP_GSSV).value),
            mapOf("x-gssv-client" to "XboxComBrowser", "Accept" to "application/json")))
        if (r.status == 401 || r.status == 403) throw XboxException(XboxErrorKind.SIGN_IN)
        if (!r.ok) throw unexpected(r)
        return (XboxAuthWire.parseStreamHost(r.text, now()) ?: throw unexpected(r)).also { host = it }
    }

    @Synchronized fun transferToken(): String {
        transfer?.takeIf { fresh(it.expiresAtMs) }?.let { return it.value }
        val refresh = store.load()?.str("refresh_token")?.takeIf { it.isNotBlank() } ?: throw XboxException(XboxErrorKind.SIGN_IN)
        val r = send(HttpRequest(XboxAuthWire.TRANSFER_URL, "POST", FORM, XboxAuthWire.transferBody(refresh).toByteArray()))
        if (r.status == 400 || r.status == 401) throw XboxException(XboxErrorKind.SIGN_IN)
        if (!r.ok) throw unexpected(r)
        val m = runCatching { Json.parseObject(r.text) }.getOrNull() ?: throw unexpected(r)
        val token = m.str("access_token")?.takeIf { it.isNotBlank() } ?: throw unexpected(r)
        val seconds = XboxAuthWire.number(m["expires_in"]) ?: 3600
        return TimedToken(token, now() + seconds * 1000).also { transfer = it }.value
    }

    /** Hesaptaki Xbox'lar (10.3). */
    fun consoles(): List<com.ninotranslator.mobile.data.XboxConsole> {
        val t = xsts(XboxAuthWire.RP_XBOXLIVE)
        val r = send(HttpRequest(XboxConsoleList.URL, "GET", mapOf(
            "Authorization" to "XBL3.0 x=${t.uhs.orEmpty()};${t.value}", "x-xbl-contract-version" to "4",
            "skillplatform" to "RemoteManagement", "Accept" to "application/json",
        )))
        if (r.status == 401 || r.status == 403) {
            synchronized(this) { xsts.remove(XboxAuthWire.RP_XBOXLIVE) }
            throw XboxException(XboxErrorKind.SIGN_IN)
        }
        if (!r.ok) throw unexpected(r)
        return XboxConsoleList.parse(r.text)
    }

    // ---- Microsoft cihaz kodu (10.1) ----

    fun requestDeviceCode(): DeviceCodeGrant {
        val r = send(HttpRequest(XboxAuthWire.DEVICE_CODE_URL, "POST", FORM, XboxAuthWire.deviceCodeBody().toByteArray()))
        if (!r.ok) throw unexpected(r)
        return XboxAuthWire.parseDeviceCode(r.text) ?: throw unexpected(r)
    }

    /** Tek sorgu. Ağ hatası [IOException] olarak çağırana çıkar (giriş bitmez, çağıran yeniden dener). */
    fun pollDeviceCode(deviceCode: String): DevicePoll {
        val r = http.send(HttpRequest(XboxAuthWire.TOKEN_URL, "POST", FORM, XboxAuthWire.devicePollBody(deviceCode).toByteArray()))
        return XboxAuthWire.parsePoll(r.status, r.text)
    }

    /** Onaylanan girişin yanıtını saklar ve eski bellek jetonlarını bırakır. */
    fun signedIn(response: Map<String, Any?>) {
        store.save(response, now())
        reset()
    }

    private fun send(request: HttpRequest): HttpResponse = try {
        http.send(request)
    } catch (e: IOException) {
        throw XboxException(XboxErrorKind.OFFLINE, e.message)
    }

    private fun unexpected(r: HttpResponse) = XboxException(XboxErrorKind.UNEXPECTED, "HTTP ${r.status}")

    companion object {
        const val MARGIN_MS = 60_000L
        private val FORM = mapOf("Content-Type" to "application/x-www-form-urlencoded", "Accept" to "application/json")
    }
}

/** Konsol listesi (10.3). */
object XboxConsoleList {
    const val URL = "https://xccs.xboxlive.com/lists/devices?queryCurrentDevice=false&includeStorageDevices=true"

    /** Yalnız `consoleStreamingEnabled` ve `remoteManagementEnabled` açıksa hazır (seçilebilir). */
    fun parse(body: String): List<com.ninotranslator.mobile.data.XboxConsole> {
        val m = runCatching { Json.parseObject(body) }.getOrNull() ?: return emptyList()
        @Suppress("UNCHECKED_CAST")
        val items = (m.list("result") ?: m.list("results")).orEmpty().mapNotNull { it as? Map<String, Any?> }
        return items.mapNotNull { d ->
            val id = d.str("id")?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            com.ninotranslator.mobile.data.XboxConsole(
                id = id,
                name = d.str("name")?.takeIf { it.isNotBlank() },
                model = d.str("consoleType")?.let(::modelName),
                streamingEnabled = d["consoleStreamingEnabled"] == true && d["remoteManagementEnabled"] == true,
                powerState = d.str("powerState"),
            )
        }
    }

    fun modelName(type: String): String = when (type) {
        "XboxSeriesX" -> "Series X"
        "XboxSeriesS" -> "Series S"
        "XboxOne" -> "One"
        "XboxOneS" -> "One S"
        "XboxOneX" -> "One X"
        else -> type
    }
}
