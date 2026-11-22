// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.link

import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.IOException
import java.io.OutputStream
import java.net.Socket
import java.net.URLDecoder

/** Sunucuların okuduğu HTTP isteği (yalnız ilk satır ve başlıklar). Başlık adları küçük harfle tutulur. */
class HttpRequest(val method: String, val target: String, val headers: Map<String, String>) {
    val path: String get() = target.substringBefore('?')

    /** Sorgu parametreleri, URL çözülmüş. */
    val query: Map<String, String> by lazy {
        val q = target.substringAfter('?', "")
        if (q.isEmpty()) emptyMap() else q.split('&').filter { it.isNotEmpty() }.associate {
            val k = it.substringBefore('=')
            val v = it.substringAfter('=', "")
            decode(k) to decode(v)
        }
    }

    fun header(name: String): String? = headers[name.lowercase()]

    companion object {
        const val MAX_HEADER_BYTES = 64 * 1024

        private fun decode(s: String) = runCatching { URLDecoder.decode(s, "UTF-8") }.getOrDefault(s)

        /** İsteği boş satıra kadar okur. Bağlantı erken kapanırsa null; başlıklar 64 KB'ı geçerse hata. */
        fun read(input: DataInputStream, maxBytes: Int = MAX_HEADER_BYTES): HttpRequest? {
            var total = 0
            fun line(): String? {
                val b = ByteArrayOutputStream()
                while (true) {
                    val c = input.read()
                    if (c < 0) return null
                    if (++total > maxBytes) throw IOException("başlıklar çok büyük")
                    if (c == '\n'.code) return b.toString(Charsets.ISO_8859_1.name()).trimEnd('\r')
                    b.write(c)
                }
            }
            val first = line() ?: return null
            val parts = first.split(' ')
            if (parts.size < 2) throw IOException("bozuk istek")
            val headers = HashMap<String, String>()
            while (true) {
                val l = line() ?: return null
                if (l.isEmpty()) break
                val colon = l.indexOf(':')
                if (colon > 0) headers[l.substring(0, colon).trim().lowercase()] = l.substring(colon + 1).trim()
            }
            return HttpRequest(parts[0].uppercase(), parts[1], headers)
        }
    }
}

internal object HttpReply {
    const val CORS = "Access-Control-Allow-Origin: *\r\n"
    private const val CORS_PREFLIGHT = "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: *\r\n" +
        "Access-Control-Max-Age: 600\r\n"

    fun send(out: OutputStream, status: String, body: String? = null, contentType: String = "application/json; charset=utf-8") {
        val bytes = body?.toByteArray(Charsets.UTF_8) ?: ByteArray(0)
        val head = StringBuilder("HTTP/1.1 $status\r\n").append(CORS)
        if (body != null) head.append("Content-Type: $contentType\r\n")
        head.append("Content-Length: ${bytes.size}\r\nConnection: close\r\n\r\n")
        out.write(head.toString().toByteArray(Charsets.ISO_8859_1))
        out.write(bytes)
        out.flush()
    }

    fun noContent(out: OutputStream) {
        out.write("HTTP/1.1 204 No Content\r\n$CORS${CORS_PREFLIGHT}Content-Length: 0\r\nConnection: close\r\n\r\n".toByteArray(Charsets.ISO_8859_1))
        out.flush()
    }
}

/**
 * WebSocket'in sunucu ucu (RFC 6455), yalnız metin. İstemciden gelen çerçeveler maskeli olmalı; giden çerçeveler
 * maskesiz. Ping'e kendisi pong döner. Engelleyici; kendi iş parçacığında kullanılır.
 */
class WebSocketServerConnection private constructor(
    val socket: Socket,
    private val input: DataInputStream,
    private val output: OutputStream,
) {
    private val writeLock = Any()
    @Volatile var isOpen = true
        private set

    class TooLargeException : IOException("too large")

    fun sendText(text: String) = sendFrame(0x1, text.toByteArray(Charsets.UTF_8))

    /** Sıradaki metin mesajı; bağlantı kapanırsa null. [maxBytes]'ı aşan mesaj [TooLargeException] atar. */
    fun receiveText(maxBytes: Int = NinoLink.MAX_MESSAGE_BYTES): String? {
        val buffer = ByteArrayOutputStream()
        var opcodeOfMessage = -1
        while (true) {
            val b0 = input.read()
            if (b0 < 0) { isOpen = false; return null }
            val b1 = input.readUnsignedByte()
            val fin = b0 and 0x80 != 0
            val opcode = b0 and 0x0F
            if (b1 and 0x80 == 0) { close(1002); throw IOException("maskesiz istemci çerçevesi") }
            var len = (b1 and 0x7F).toLong()
            if (len == 126L) len = input.readUnsignedShort().toLong() else if (len == 127L) len = input.readLong()
            val control = opcode >= 0x8
            if (len < 0 || len > maxBytes || (control && len > 125)) throw TooLargeException()
            val mask = ByteArray(4).also { input.readFully(it) }
            val payload = ByteArray(len.toInt()).also { input.readFully(it) }
            for (i in payload.indices) payload[i] = (payload[i].toInt() xor mask[i and 3].toInt()).toByte()
            when (opcode) {
                0x8 -> { close(1000); return null }
                0x9 -> sendFrame(0xA, payload)
                0xA -> Unit
                0x2 -> { close(1003); throw IOException("ikili çerçeve") }
                0x1, 0x0 -> {
                    if (opcode == 0x1) { opcodeOfMessage = 0x1; buffer.reset() }
                    if (buffer.size() + payload.size > maxBytes) throw TooLargeException()
                    buffer.write(payload)
                    if (fin && opcodeOfMessage == 0x1) return buffer.toString(Charsets.UTF_8.name())
                }
                else -> { close(1002); throw IOException("bilinmeyen çerçeve $opcode") }
            }
        }
    }

    fun setReadTimeout(ms: Int) { socket.soTimeout = ms }

    fun close(code: Int = 1000) {
        if (!isOpen) { runCatching { socket.close() }; return }
        isOpen = false
        runCatching { writeFrame(0x8, byteArrayOf((code shr 8).toByte(), code.toByte())) }
        runCatching { socket.close() }
    }

    private fun sendFrame(opcode: Int, payload: ByteArray) {
        if (!isOpen) throw IOException("closed")
        try { writeFrame(opcode, payload) } catch (e: IOException) { isOpen = false; runCatching { socket.close() }; throw e }
    }

    private fun writeFrame(opcode: Int, payload: ByteArray) {
        val header = ByteArrayOutputStream(10)
        header.write(0x80 or opcode)
        when {
            payload.size < 126 -> header.write(payload.size)
            payload.size <= 0xFFFF -> { header.write(126); header.write(payload.size shr 8); header.write(payload.size and 0xFF) }
            else -> { header.write(127); for (i in 7 downTo 0) header.write(((payload.size.toLong() shr (8 * i)) and 0xFF).toInt()) }
        }
        synchronized(writeLock) {
            output.write(header.toByteArray())
            output.write(payload)
            output.flush()
        }
    }

    companion object {
        /** İstek bir WebSocket yükseltmesi mi? */
        fun isUpgrade(req: HttpRequest): Boolean =
            req.method == "GET" && req.header("upgrade")?.contains("websocket", ignoreCase = true) == true

        /** Yükseltmeyi kabul eder (101). Eksik/yanlış başlıkta 400 yollar ve null döner. */
        fun accept(socket: Socket, input: DataInputStream, output: OutputStream, req: HttpRequest): WebSocketServerConnection? {
            val key = req.header("sec-websocket-key")
            val version = req.header("sec-websocket-version")
            val connection = req.header("connection")
            if (!isUpgrade(req) || key.isNullOrBlank() || version != "13" || connection?.contains("upgrade", ignoreCase = true) != true) {
                output.write(("HTTP/1.1 400 Bad Request\r\n${HttpReply.CORS}Sec-WebSocket-Version: 13\r\nContent-Length: 0\r\n" +
                    "Connection: close\r\n\r\n").toByteArray(Charsets.ISO_8859_1))
                output.flush()
                return null
            }
            output.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
                "Sec-WebSocket-Accept: ${WebSocketClient.acceptKey(key)}\r\n\r\n").toByteArray(Charsets.ISO_8859_1))
            output.flush()
            return WebSocketServerConnection(socket, input, output)
        }
    }
}
