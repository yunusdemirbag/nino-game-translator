// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.samsung

import com.ninotranslator.mobile.tv.install.LocalIoException
import com.ninotranslator.core.json.Json
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException

/**
 * Samsung hesabı girişi (tv.md 3.3 adım 4): telefon 127.0.0.1:4794'te küçük bir HTTP dinleyicisi açar; Samsung jetonu
 * `POST /signin/callback`'e `code=<JSON>&state=…` olarak gönderir.
 */
object SamsungSignIn {
    const val PORT = 4794
    const val STATE = "accountcheckdogeneratedstatetext"
    const val URL = "https://account.samsung.com/accounts/be1dce529476c1a6d407c4c7578c31bd/signInGate?locale=&clientId=v285zxnl3h" +
        "&redirect_uri=http%3A%2F%2Flocalhost%3A4794%2Fsignin%2Fcallback&state=$STATE&tokenType=TOKEN"
    const val TIMEOUT_MS = 10 * 60_000L

    /** `%XX` dizilerini çözer; `+` boşluğa **çevrilmez**. */
    fun percentDecode(s: String): String {
        val out = ByteArrayOutputStream()
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c == '%' && i + 2 < s.length) {
                val h = s.substring(i + 1, i + 3).toIntOrNull(16)
                if (h != null) { out.write(h); i += 3; continue }
            }
            out.write(c.toString().toByteArray(Charsets.UTF_8))
            i++
        }
        return out.toString(Charsets.UTF_8.name())
    }

    /** Form gövdesi alanları (değerler [percentDecode] ile). */
    fun formFields(body: String): Map<String, String> = body.split('&').mapNotNull { part ->
        val i = part.indexOf('=')
        if (i <= 0) null else percentDecode(part.substring(0, i)) to percentDecode(part.substring(i + 1))
    }.toMap()

    sealed interface Callback {
        data class Ok(val account: SamsungCertificates.Account) : Callback
        /** Hesap bilgisi yok (400); [errors] Samsung'un hata alanları, jeton değil. */
        data class NoAccount(val errors: String?) : Callback
    }

    fun parseCallback(body: String): Callback {
        val f = formFields(body)
        if (f["state"] != STATE) return Callback.NoAccount("state tutmuyor")
        val json = f["code"]?.let { runCatching { Json.parse(it) as? Map<*, *> }.getOrNull() }
            ?: return Callback.NoAccount(f.filterKeys { "error" in it.lowercase() }.entries.joinToString { "${it.key}=${it.value}" }.ifEmpty { null })
        val token = json["access_token"]?.toString()?.takeIf { it.isNotBlank() }
        val user = json["userId"]?.toString()?.takeIf { it.isNotBlank() }
        if (token == null || user == null) {
            val errs = json.filterKeys { k -> k.toString().lowercase().let { "error" in it || "code" in it || "message" in it } && k != "access_token" }
            return Callback.NoAccount(errs.entries.joinToString { "${it.key}=${it.value}" }.ifEmpty { null })
        }
        return Callback.Ok(SamsungCertificates.Account(token, user, json["inputEmailID"]?.toString()?.takeIf { it.isNotBlank() }))
    }

    private const val DONE_PAGE = "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\">" +
        "<title>Nino</title></head><body style=\"font-family:sans-serif;text-align:center;padding:48px\">" +
        "<h2>Oturum açıldı / Sign-in complete</h2><p>Artık Nino'ya geri geçebilirsiniz. / Nino is ready, head back to it.</p></body></html>"

    /** Dinleyici: [await] jeton gelene, [cancelled] true olana ya da süre dolana kadar bekler. */
    class Listener(port: Int = PORT, private val log: (String) -> Unit = {}) : AutoCloseable {
        private val server = ServerSocket(port, 8, InetAddress.getByName("127.0.0.1")).apply { reuseAddress = true; soTimeout = 500 }
        val localPort: Int get() = server.localPort

        fun await(timeoutMs: Long, cancelled: () -> Boolean): SamsungCertificates.Account? {
            val end = System.currentTimeMillis() + timeoutMs
            while (System.currentTimeMillis() < end && !cancelled()) {
                val s = try { server.accept() } catch (_: SocketTimeoutException) { continue } catch (_: IOException) { return null }
                s.use { handle(it)?.let { a -> return a } }
            }
            return null
        }

        private fun handle(s: Socket): SamsungCertificates.Account? = runCatching {
            s.soTimeout = 10_000
            val (line, _, body) = readRequest(s.getInputStream())
            val parts = line.split(' ')
            val method = parts.getOrNull(0).orEmpty(); val path = parts.getOrNull(1).orEmpty().substringBefore('?')
            val out = s.getOutputStream()
            fun reply(code: Int, text: String, html: Boolean) {
                val b = text.toByteArray(Charsets.UTF_8)
                val status = mapOf(200 to "OK", 400 to "Bad Request", 404 to "Not Found")[code] ?: "OK"
                out.write(("HTTP/1.1 $code $status\r\nContent-Type: ${if (html) "text/html" else "text/plain"}; charset=utf-8\r\n" +
                    "Content-Length: ${b.size}\r\nConnection: close\r\n\r\n").toByteArray(Charsets.US_ASCII))
                out.write(b); out.flush()
            }
            if (path != "/signin/callback") { reply(404, "not found", false); return null }
            if (method != "POST") { reply(400, "POST bekleniyor", false); return null }
            when (val r = parseCallback(body)) {
                is Callback.Ok -> { reply(200, DONE_PAGE, true); log("Samsung girişi tamam"); r.account }
                is Callback.NoAccount -> { log("Samsung girişi hesap bilgisi vermedi: ${r.errors.orEmpty()}"); reply(400, "no account", false); null }
            }
        }.getOrElse { log("giriş isteği okunamadı: ${it.message}"); null }

        override fun close() { runCatching { server.close() } }
    }

    /** İlk satır, başlıklar (küçük harf) ve gövde (Content-Length kadar, en çok 1 MB). */
    fun readRequest(input: InputStream): Triple<String, Map<String, String>, String> {
        val head = ByteArrayOutputStream()
        var last4 = 0
        while (true) {
            val b = input.read()
            if (b < 0) break
            head.write(b)
            last4 = (last4 shl 8) or b
            if (last4 == 0x0D0A0D0A) break
            if (head.size() > 64 * 1024) throw LocalIoException("başlık çok uzun")
        }
        val lines = head.toString(Charsets.ISO_8859_1.name()).split("\r\n")
        val headers = lines.drop(1).filter { ':' in it }.associate { it.substringBefore(':').trim().lowercase() to it.substringAfter(':').trim() }
        val len = headers["content-length"]?.toIntOrNull()?.coerceIn(0, 1 shl 20) ?: 0
        val body = ByteArray(len)
        var off = 0
        while (off < len) { val r = input.read(body, off, len - off); if (r < 0) break; off += r }
        return Triple(lines.firstOrNull().orEmpty(), headers, String(body, 0, off, Charsets.UTF_8))
    }
}
