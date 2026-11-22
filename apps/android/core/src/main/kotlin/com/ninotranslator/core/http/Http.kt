// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.http

import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL

/** Tek bir HTTP isteği. Gövde bayt olarak verilir. */
data class HttpRequest(
    val url: String,
    val method: String = "GET",
    val headers: Map<String, String> = emptyMap(),
    val body: ByteArray? = null,
    val connectTimeoutMs: Int = 15_000,
    val readTimeoutMs: Int = 30_000,
) {
    companion object {
        fun json(url: String, body: String, headers: Map<String, String> = emptyMap(), connectTimeoutMs: Int = 15_000, readTimeoutMs: Int = 30_000) =
            HttpRequest(url, "POST", mapOf("Content-Type" to "application/json") + headers, body.toByteArray(Charsets.UTF_8), connectTimeoutMs, readTimeoutMs)
    }
}

/** Cevap. Başlık adları küçük harfle tutulur. */
class HttpResponse(val status: Int, val headers: Map<String, String> = emptyMap(), val body: ByteArray = ByteArray(0)) {
    val text: String get() = body.toString(Charsets.UTF_8)
    val ok: Boolean get() = status in 200..299
    fun header(name: String): String? = headers[name.lowercase()]
}

/** Zaman aşımı ayrıca ayırt edilsin diye. */
class HttpTimeoutException(cause: Throwable? = null) : IOException("zaman aşımı", cause)

/** Ağ katmanı. Testlerde sahtesi verilir. Engelleyicidir; çağıran IO iş parçacığında çağırır. */
fun interface HttpTransport {
    @Throws(IOException::class)
    fun send(request: HttpRequest): HttpResponse
}

/** HttpURLConnection ile gerçek ağ. */
object UrlConnectionTransport : HttpTransport {
    override fun send(request: HttpRequest): HttpResponse {
        val c = URL(request.url).openConnection() as HttpURLConnection
        try {
            c.connectTimeout = request.connectTimeoutMs
            c.readTimeout = request.readTimeoutMs
            c.requestMethod = request.method
            c.instanceFollowRedirects = true
            for ((k, v) in request.headers) c.setRequestProperty(k, v)
            request.body?.let { b ->
                c.doOutput = true
                c.setFixedLengthStreamingMode(b.size)
                c.outputStream.use { it.write(b) }
            }
            val status = c.responseCode
            val stream = if (status >= 400) c.errorStream else c.inputStream
            val bytes = stream?.use { it.readBytes() } ?: ByteArray(0)
            val headers = HashMap<String, String>()
            for ((k, v) in c.headerFields) if (k != null && v != null && v.isNotEmpty()) headers[k.lowercase()] = v.first()
            return HttpResponse(status, headers, bytes)
        } catch (e: SocketTimeoutException) {
            throw HttpTimeoutException(e)
        } finally {
            c.disconnect()
        }
    }
}
