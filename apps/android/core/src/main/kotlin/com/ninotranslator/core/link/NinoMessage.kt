// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.link

import com.ninotranslator.core.json.Json

/** Nino Bağlantı Protokolü sabitleri (NinoCore docs/tarif/protokol.md). */
object NinoLink {
    const val VERSION = 1
    val SUPPORTED_VERSIONS = listOf(1)
    const val DEFAULT_PORT = 47800
    const val SERVICE_TYPE = "_nino._tcp"
    const val MAX_MESSAGE_BYTES = 16 * 1024
    const val HANDSHAKE_TIMEOUT_MS = 5_000L
    const val PING_INTERVAL_MS = 5_000L
    const val PONG_TIMEOUT_MS = 15_000L
    const val DISPLAY_IDLE_TIMEOUT_MS = 20_000L

    const val PATH_INFO = "/nino/info"
    const val PATH_WS = "/nino/ws"
    const val PATH_SHOW = "/nino/show"
    const val PATH_CLEAR = "/nino/clear"

    const val ERROR_VERSION_UNSUPPORTED = "version_unsupported"
    const val ERROR_BAD_HANDSHAKE = "bad_handshake"
    const val ERROR_BAD_MESSAGE = "bad_message"
    const val ERROR_TOO_LARGE = "too_large"
    const val ERROR_REPLACED = "replaced"

    fun bestCommonVersion(theirs: List<Int>, ours: List<Int> = SUPPORTED_VERSIONS): Int? = theirs.intersect(ours.toSet()).maxOrNull()

    /** Adres + kapı + yol. IPv6 köşeli paranteze alınır; kapsam %25 olarak kodlanır, IPv4'te atılır. */
    fun url(scheme: String, host: String, port: Int, path: String): String {
        var h = host.trim().trim('[', ']')
        require(h.isNotEmpty()) { "boş adres" }
        if (!h.contains(':')) {
            h = h.substringBefore('%')
        } else {
            h = "[" + h.replace("%25", "%").replace("%", "%25") + "]"
        }
        return "$scheme://$h:$port$path"
    }

    /** Yerel ağ adresi mi? */
    fun isLocalAddress(host: String): Boolean {
        var h = host.lowercase().substringBefore('%').trim('[', ']')
        if (h.startsWith("::ffff:")) h = h.removePrefix("::ffff:")
        val parts = h.split('.')
        if (parts.size == 4) {
            val n = parts.map { it.toIntOrNull()?.takeIf { v -> v in 0..255 } ?: return false }
            return when {
                n[0] == 10 || n[0] == 127 -> true
                n[0] == 192 && n[1] == 168 -> true
                n[0] == 169 && n[1] == 254 -> true
                n[0] == 172 && n[1] in 16..31 -> true
                else -> false
            }
        }
        if (h.contains(':')) {
            if (h == "::1") return true
            if (h.startsWith("fe8") || h.startsWith("fe9") || h.startsWith("fea") || h.startsWith("feb")) return true
            if (h.startsWith("fc") || h.startsWith("fd")) return true
        }
        return false
    }
}

enum class SubtitlePosition(val wire: String) {
    BOTTOM("bottom"), TOP("top");
    companion object { fun of(s: String?) = entries.firstOrNull { it.wire == s } ?: BOTTOM }
}

/**
 * show mesajının içeriği. [extras], protokolün isteğe bağlı ek alanlarıdır (ör. "style");
 * TV tanımadığı alanları yok sayar, bu yüzden sürüm artmaz.
 */
data class ShowPayload(
    val id: Int,
    val text: String,
    val source: String? = null,
    val position: SubtitlePosition = SubtitlePosition.BOTTOM,
    val durationMs: Int = 0,
    val extras: Map<String, Any?> = emptyMap(),
)

sealed interface NinoMessage {
    val type: String

    data class Hello(val version: Int, val device: String?, val client: String?) : NinoMessage { override val type = "hello" }
    data class Welcome(val version: Int, val name: String?, val model: String? = null, val appVersion: String? = null) : NinoMessage { override val type = "welcome" }
    data class Info(
        val version: Int, val versions: List<Int>, val name: String, val id: String,
        val model: String? = null, val appVersion: String? = null, val role: String? = null,
    ) : NinoMessage { override val type = "info" }
    data class Show(val payload: ShowPayload) : NinoMessage { override val type = "show" }
    data class Clear(val id: Int?) : NinoMessage { override val type = "clear" }
    data class Ping(val t: Long) : NinoMessage { override val type = "ping" }
    data class Pong(val t: Long) : NinoMessage { override val type = "pong" }
    data class Error(val code: String, val message: String? = null, val versions: List<Int>? = null) : NinoMessage { override val type = "error" }
    data object Ok : NinoMessage { override val type = "ok" }
    data class Unknown(override val type: String) : NinoMessage

    class DecodeException(message: String) : Exception(message)

    fun toMap(): Map<String, Any?> {
        val o = sortedMapOf<String, Any?>("app" to "nino", "type" to type)
        when (this) {
            is Hello -> { o["version"] = version; device?.let { o["device"] = it }; client?.let { o["client"] = it } }
            is Welcome -> { o["version"] = version; name?.let { o["name"] = it }; model?.let { o["model"] = it }; appVersion?.let { o["appVersion"] = it } }
            is Info -> {
                o["version"] = version; o["versions"] = versions; o["name"] = name; o["id"] = id
                model?.let { o["model"] = it }; appVersion?.let { o["appVersion"] = it }; role?.let { o["role"] = it }
            }
            is Show -> {
                for ((k, v) in payload.extras) if (k !in RESERVED) o[k] = v
                o["id"] = payload.id; o["text"] = payload.text
                payload.source?.let { o["source"] = it }
                o["position"] = payload.position.wire; o["durationMs"] = payload.durationMs
            }
            is Clear -> id?.let { o["id"] = it }
            is Ping -> o["t"] = t
            is Pong -> o["t"] = t
            is Error -> { o["code"] = code; message?.let { o["message"] = it }; versions?.let { o["versions"] = it } }
            Ok, is Unknown -> Unit
        }
        return o
    }

    fun encode(): String = Json.write(toMap())

    companion object {
        private val RESERVED = setOf("app", "type", "id", "text", "source", "position", "durationMs")

        fun decode(text: String): NinoMessage {
            val o = runCatching { Json.parse(text) }.getOrNull() as? Map<*, *> ?: throw DecodeException("notJSON")
            if (o["app"] != "nino") throw DecodeException("notNino")
            val type = o["type"] as? String ?: throw DecodeException("missing type")
            fun int(k: String): Long? = (o[k] as? Number)?.let { if (it is Double && it != Math.rint(it)) null else it.toLong() }
            fun need(k: String): Long = int(k) ?: throw DecodeException("missing $k")
            fun ints(k: String): List<Int>? = (o[k] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() }
            return when (type) {
                "hello" -> Hello(need("version").toInt(), o["device"] as? String, o["client"] as? String)
                "welcome" -> Welcome(need("version").toInt(), o["name"] as? String, o["model"] as? String, o["appVersion"] as? String)
                "info" -> Info(need("version").toInt(), ints("versions") ?: emptyList(), o["name"] as? String ?: "", o["id"] as? String ?: "",
                    o["model"] as? String, o["appVersion"] as? String, o["role"] as? String)
                "show" -> {
                    val extras = o.entries.filter { it.key !in RESERVED }.associate { it.key.toString() to it.value }
                    Show(ShowPayload(need("id").toInt(), o["text"] as? String ?: throw DecodeException("missing text"),
                        o["source"] as? String, SubtitlePosition.of(o["position"] as? String),
                        maxOf(0, int("durationMs")?.toInt() ?: 0), extras))
                }
                "clear" -> Clear(int("id")?.toInt())
                "ping" -> Ping(need("t"))
                "pong" -> Pong(need("t"))
                "error" -> Error(o["code"] as? String ?: throw DecodeException("missing code"), o["message"] as? String, ints("versions"))
                "ok" -> Ok
                else -> Unknown(type)
            }
        }
    }
}
