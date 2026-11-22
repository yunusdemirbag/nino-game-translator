// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.xbox

import com.ninotranslator.core.http.HttpRequest
import com.ninotranslator.core.http.HttpResponse
import com.ninotranslator.core.http.HttpTimeoutException
import com.ninotranslator.core.http.HttpTransport
import com.ninotranslator.core.json.Json
import com.ninotranslator.core.json.str
import java.io.IOException
import java.util.TimeZone

/**
 * Yayın oturumunun sorun türü (servis.md 10.5–10.6). [START_FAILED]: Xbox oturumu başlatamadı
 * (`StartStreamingSession failed`); kullanıcıya çözüm adımları gösterilir.
 */
enum class XboxProblem { SIGN_IN, NO_PROFILE, UNREACHABLE, BUSY, TIMEOUT, NETWORK, SERVICE, WEBRTC, START_FAILED }

/**
 * Yayın kalitesinin istekteki karşılığı. Tarifte yok; açık kaynak Xbox oynatıcısı greenlight'ın
 * (github.com/unknownskl/greenlight, xHome/xCloud istemcisi) kullandığı alanlar: `play` gövdesindeki `settings.osName`
 * Xbox'un gönderdiği çözünürlüğü seçer ("windows" 1080p, "android" 720p); `X-MS-Device-Info` ekran boyu ve
 * `dimensionschanged` iletisi aynı boyla gider. Bit hızı için oturumda alan yok: standart SDP `b=AS:<kbps>` (RFC 4566)
 * teklifin görüntü bölümüne yazılır, Xbox bu sınırın üstünde göndermez. [maxBitrateKbps] null: sınır yok.
 */
data class XboxStreamProfile(val width: Int, val height: Int, val osName: String, val maxBitrateKbps: Int?) {
    companion object {
        val P1080 = XboxStreamProfile(1920, 1080, "windows", null)
        val P720 = XboxStreamProfile(1280, 720, "android", 4_000)

        fun of(quality: com.ninotranslator.mobile.data.XboxQuality) = when (quality) {
            com.ninotranslator.mobile.data.XboxQuality.P1080 -> P1080
            com.ninotranslator.mobile.data.XboxQuality.P720 -> P720
        }
    }
}

/** Yayın hatası. [rejected]: konsol yayını reddetti, yeniden denenmez. */
class XboxStreamException(val problem: XboxProblem, val rejected: Boolean = false, detail: String? = null) :
    Exception(detail ?: problem.name)

/** Yerel ya da uzak ICE adayı (SDP satırı, `a=candidate:…`). */
data class XboxIceCandidate(val candidate: String, val sdpMid: String?, val sdpMLineIndex: Int)

/** `GET …/state` yanıtı. */
data class XboxSessionState(val state: String, val errorDetails: Map<String, Any?>?)

/**
 * Ev yayını uçları (10.4). Engelleyicidir. Her istek `<baseUri><yol>`, yayın jetonu ve sabit Windows cihaz bilgisiyle
 * gider. Hata yanıtları [XboxStreamException]'a çevrilir.
 */
class XboxStreamApi(
    private val http: HttpTransport,
    val profile: XboxStreamProfile = XboxStreamProfile.P1080,
    private val host: () -> XboxStreamHost,
) {
    private val deviceInfo = deviceInfo(profile.width, profile.height)

    fun play(serverId: String, timezoneOffsetMin: Int = TimeZone.getDefault().getOffset(System.currentTimeMillis()) / 60_000): String {
        val r = call("POST", "/v5/sessions/home/play", playBody(serverId, timezoneOffsetMin, profile.osName))
        val path = runCatching { Json.parseObject(r.text).str("sessionPath") }.getOrNull()
        return path?.let(::sessionIdOf) ?: throw XboxStreamException(XboxProblem.SERVICE, detail = "sessionPath yok")
    }

    fun state(id: String): XboxSessionState {
        val m = runCatching { Json.parseObject(call("GET", "/v5/sessions/home/$id/state").text) }.getOrNull().orEmpty()
        @Suppress("UNCHECKED_CAST")
        return XboxSessionState(m.str("state").orEmpty(), m["errorDetails"] as? Map<String, Any?>)
    }

    fun connect(id: String, transferToken: String) {
        call("POST", "/v5/sessions/home/$id/connect", Json.write(mapOf("userToken" to transferToken)))
    }

    /** POST'un gövdesi (bazen değiş-tokuş yanıtını hemen taşır). */
    fun postOffer(id: String, sdp: String): String = call("POST", "/v5/sessions/home/$id/sdp", offerBody(sdp)).text
    fun postIce(id: String, candidates: List<XboxIceCandidate>): String = call("POST", "/v5/sessions/home/$id/ice", iceBody(candidates)).text

    /** Değiş-tokuş yanıtı (`exchangeResponse` metni); henüz yoksa null. [kind]: `sdp` ya da `ice`. */
    fun exchange(id: String, kind: String): String? {
        val r = call("GET", "/v5/sessions/home/$id/$kind")
        if (r.status == 204) return null
        return exchangeOf(r.text)
    }

    fun keepalive(id: String) { call("POST", "/v5/sessions/home/$id/keepalive", "") }

    fun delete(id: String) { call("DELETE", "/v5/sessions/home/$id") }

    private fun call(method: String, path: String, body: String? = null): HttpResponse {
        val h = host()
        val headers = mapOf(
            "Authorization" to "Bearer ${h.token}", "X-Gssv-Client" to "XboxComBrowser", "X-MS-Device-Info" to deviceInfo,
            "Content-Type" to "application/json", "Accept" to "application/json",
        )
        val r = try {
            http.send(HttpRequest(h.baseUri + path, method, headers, body?.toByteArray(Charsets.UTF_8)))
        } catch (e: HttpTimeoutException) {
            throw XboxStreamException(XboxProblem.TIMEOUT, detail = e.message)
        } catch (e: IOException) {
            throw XboxStreamException(XboxProblem.NETWORK, detail = e.message)
        }
        if (!r.ok) throw XboxStreamException(classify(r.status, r.text), detail = "HTTP ${r.status} $method $path")
        return r
    }

    companion object {
        const val WIDTH = 1920
        const val HEIGHT = 1080

        /** Sabit Windows/Surface cihaz bilgisi (Xbox uygulaması gibi); ekran boyu kaliteye göre. */
        val DEVICE_INFO: String = deviceInfo(WIDTH, HEIGHT)

        fun deviceInfo(width: Int, height: Int): String = Json.write(linkedMapOf(
            "appInfo" to linkedMapOf("env" to linkedMapOf(
                "clientAppId" to "Microsoft.GamingApp", "clientAppType" to "native", "clientAppVersion" to "2203.1001.4.0",
                "clientSdkVersion" to "8.5.2", "httpEnvironment" to "prod", "sdkInstallId" to "",
            )),
            "dev" to linkedMapOf(
                "hw" to linkedMapOf("make" to "Microsoft", "model" to "Surface Pro", "sdktype" to "native"),
                "os" to linkedMapOf("name" to "Windows 11", "ver" to "22631.2715", "platform" to "desktop"),
                "displayInfo" to linkedMapOf(
                    "dimensions" to linkedMapOf("widthInPixels" to width, "heightInPixels" to height),
                    "pixelDensity" to linkedMapOf("dpiX" to 1, "dpiY" to 1),
                ),
            ),
        ))

        /** 401/403 → giriş; InUse/Busy → meşgul; 404 ya da NotFound/Offline → ulaşılamıyor; diğer → hizmet. */
        fun classify(status: Int, body: String): XboxProblem = when {
            status == 401 || status == 403 -> XboxProblem.SIGN_IN
            body.contains("InUse") || body.contains("Busy") -> XboxProblem.BUSY
            status == 404 || body.contains("NotFound") || body.contains("Offline") -> XboxProblem.UNREACHABLE
            else -> XboxProblem.SERVICE
        }

        /** `sessionPath`'in son parçası. */
        fun sessionIdOf(path: String): String? = path.trim().trimEnd('/').substringAfterLast('/').takeIf { it.isNotBlank() }

        fun playBody(serverId: String, timezoneOffsetMin: Int, osName: String = "windows"): String = Json.write(linkedMapOf(
            "clientSessionId" to "", "titleId" to "", "systemUpdateGroup" to "", "serverId" to serverId,
            "fallbackRegionNames" to emptyList<String>(),
            "settings" to linkedMapOf(
                "nanoVersion" to "V3;WebrtcTransport.dll", "enableOptionalDataCollection" to false, "enableTextToSpeech" to false,
                "highContrast" to 0, "locale" to "en-US", "useIceConnection" to false,
                "timezoneOffsetMinutes" to timezoneOffsetMin, "sdkType" to "web", "osName" to osName,
            ),
        ))

        private fun versions(min: Int, max: Int) = linkedMapOf("minVersion" to min, "maxVersion" to max)

        fun offerBody(sdp: String): String = Json.write(linkedMapOf(
            "messageType" to "offer",
            "sdp" to sdp,
            "configuration" to linkedMapOf(
                "chatConfiguration" to linkedMapOf(
                    "bytesPerSample" to 2, "expectedClipDurationMs" to 20,
                    "format" to linkedMapOf("codec" to "opus", "container" to "webm"),
                    "numChannels" to 1, "sampleFrequencyHz" to 24000,
                ),
                "chat" to versions(1, 1), "control" to versions(1, 3), "input" to versions(1, 8), "message" to versions(1, 1),
            ),
        ))

        fun iceBody(candidates: List<XboxIceCandidate>): String = Json.write(linkedMapOf(
            "messageType" to "iceCandidate",
            "candidate" to candidates.map { linkedMapOf("candidate" to it.candidate, "sdpMid" to (it.sdpMid ?: "0"), "sdpMLineIndex" to it.sdpMLineIndex) },
        ))

        /** Gövdedeki `exchangeResponse` metni; boşsa null. */
        fun exchangeOf(body: String): String? =
            runCatching { Json.parseObject(body).str("exchangeResponse") }.getOrNull()?.takeIf { it.isNotBlank() }

        /** SDP yanıtı: `exchangeResponse` içindeki `sdp`. */
        fun answerSdp(exchange: String): String? =
            runCatching { Json.parseObject(exchange).str("sdp") }.getOrNull()?.takeIf { it.isNotBlank() }

        /** ICE yanıtı: aday listesi (doğrudan dizi ya da `candidates` alanı). */
        fun remoteCandidates(exchange: String): List<XboxIceCandidate> {
            val v = runCatching { Json.parse(exchange) }.getOrNull()
            @Suppress("UNCHECKED_CAST")
            val list = (v as? List<Any?>) ?: ((v as? Map<String, Any?>)?.get("candidates") as? List<Any?>) ?: return emptyList()
            return list.mapNotNull { item ->
                @Suppress("UNCHECKED_CAST")
                val m = item as? Map<String, Any?> ?: return@mapNotNull null
                val c = m.str("candidate")?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                XboxIceCandidate(c, m.str("sdpMid"), XboxAuthWire.number(m["sdpMLineIndex"])?.toInt() ?: 0)
            }
        }
    }
}
