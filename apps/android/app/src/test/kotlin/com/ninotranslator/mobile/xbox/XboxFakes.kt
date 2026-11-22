// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.xbox

import com.ninotranslator.core.http.HttpRequest
import com.ninotranslator.core.http.HttpResponse
import com.ninotranslator.core.http.HttpTransport
import com.ninotranslator.core.json.Json
import java.io.IOException
import java.time.Instant

/** Sahte sunucu: adrese göre sıralı yanıtlar; gelen istekleri kaydeder. */
class FakeServer : HttpTransport {
    val requests = mutableListOf<HttpRequest>()
    private val routes = LinkedHashMap<String, ArrayDeque<() -> HttpResponse>>()

    fun on(urlPart: String, status: Int, body: String = "") = apply {
        routes.getOrPut(urlPart) { ArrayDeque() }.addLast { HttpResponse(status, body = body.toByteArray()) }
    }

    fun fail(urlPart: String) = apply { routes.getOrPut(urlPart) { ArrayDeque() }.addLast { throw IOException("ağ yok") } }

    override fun send(request: HttpRequest): HttpResponse {
        requests += request
        val key = routes.keys.filter { request.url.substringBefore('?').endsWith(it) }.maxByOrNull { it.length }
            ?: routes.keys.filter { request.url.contains(it) }.maxByOrNull { it.length }
            ?: throw AssertionError("beklenmeyen istek: ${request.method} ${request.url}")
        val q = routes.getValue(key)
        val next = if (q.size > 1) q.removeFirst() else q.first()
        return next()
    }

    fun count(urlPart: String) = requests.count { it.url.contains(urlPart) }
    fun last(urlPart: String) = requests.last { it.url.contains(urlPart) }
    fun bodyOf(r: HttpRequest) = r.body?.toString(Charsets.UTF_8).orEmpty()
}

/** Bellekte jeton deposu; Secrets ile aynı kurallar. */
class MemoryTokenStore(var saved: Map<String, Any?>? = null) : XboxTokenStore {
    override fun load(): Map<String, Any?>? = saved?.takeIf { !(it["refresh_token"] as? String).isNullOrBlank() }
    override fun save(response: Map<String, Any?>, nowMs: Long) {
        val m = LinkedHashMap(response)
        if ((m["refresh_token"] as? String).isNullOrBlank()) saved?.get("refresh_token")?.let { m["refresh_token"] = it }
        (m["expires_in"] as? Number)?.let { m["expires_on"] = Instant.ofEpochMilli(nowMs + it.toLong() * 1000).toString() }
        saved = m
    }
    override fun clear() { saved = null }
}

object XboxSamples {
    fun xbl(token: String, notAfter: String, uhs: String = "UHS1") =
        Json.write(mapOf("Token" to token, "NotAfter" to notAfter, "DisplayClaims" to mapOf("xui" to listOf(mapOf("uhs" to uhs)))))

    fun iso(ms: Long) = Instant.ofEpochMilli(ms).toString()
}
