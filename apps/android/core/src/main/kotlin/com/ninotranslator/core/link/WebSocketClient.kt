// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.link

import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.IOException
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URI
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

/** Yalnız metin mesajları için küçük bir WebSocket istemcisi (RFC 6455). Engelleyici; IO iş parçacığında kullanılır. */
class WebSocketClient private constructor(private val socket: Socket, private val input: DataInputStream, private val output: OutputStream) {
    private val writeLock = Any()
    @Volatile var isOpen = true
        private set

    class HandshakeException(message: String) : IOException(message)
    class TooLargeException : IOException("too large")

    fun sendText(text: String) = sendFrame(0x1, text.toByteArray(Charsets.UTF_8))

    /** Sıradaki metin mesajı; bağlantı kapanırsa null. Ping'lere kendisi cevap verir. */
    fun receiveText(maxBytes: Int = NinoLink.MAX_MESSAGE_BYTES): String? {
        val buffer = ByteArrayOutputStream()
        var messageOpcode = -1
        while (true) {
            val b0 = input.read()
            if (b0 < 0) { isOpen = false; return null }
            val b1 = input.readUnsignedByte()
            val fin = b0 and 0x80 != 0
            val opcode = b0 and 0x0F
            val masked = b1 and 0x80 != 0
            var len = (b1 and 0x7F).toLong()
            if (len == 126L) len = input.readUnsignedShort().toLong()
            else if (len == 127L) len = input.readLong()
            if (len < 0 || len > maxBytes) { close(1009); throw TooLargeException() }
            val mask = if (masked) ByteArray(4).also { input.readFully(it) } else null
            val payload = ByteArray(len.toInt()).also { input.readFully(it) }
            if (mask != null) for (i in payload.indices) payload[i] = (payload[i].toInt() xor mask[i % 4].toInt()).toByte()
            when (opcode) {
                0x8 -> { close(1000); return null }
                0x9 -> sendFrame(0xA, payload)
                0xA -> Unit
                0x1, 0x2, 0x0 -> {
                    if (opcode != 0) messageOpcode = opcode
                    if (buffer.size() + payload.size > maxBytes) { close(1009); throw TooLargeException() }
                    buffer.write(payload)
                    if (fin) {
                        if (messageOpcode == 0x1 || messageOpcode == 0x2) return buffer.toString(Charsets.UTF_8.name())
                        buffer.reset()
                    }
                }
            }
        }
    }

    fun close(code: Int = 1000) {
        if (!isOpen) return
        isOpen = false
        runCatching { sendFrameRaw(0x8, byteArrayOf((code shr 8).toByte(), code.toByte())) }
        runCatching { socket.close() }
    }

    private fun sendFrame(opcode: Int, payload: ByteArray) {
        if (!isOpen) throw IOException("closed")
        try { sendFrameRaw(opcode, payload) } catch (e: IOException) { isOpen = false; runCatching { socket.close() }; throw e }
    }

    private fun sendFrameRaw(opcode: Int, payload: ByteArray) {
        val mask = ByteArray(4).also { random.nextBytes(it) }
        val header = ByteArrayOutputStream()
        header.write(0x80 or opcode)
        when {
            payload.size < 126 -> header.write(0x80 or payload.size)
            payload.size <= 0xFFFF -> { header.write(0x80 or 126); header.write(payload.size shr 8); header.write(payload.size and 0xFF) }
            else -> { header.write(0x80 or 127); for (i in 7 downTo 0) header.write(((payload.size.toLong() shr (8 * i)) and 0xFF).toInt()) }
        }
        header.write(mask)
        val body = ByteArray(payload.size) { (payload[it].toInt() xor mask[it % 4].toInt()).toByte() }
        synchronized(writeLock) {
            output.write(header.toByteArray())
            output.write(body)
            output.flush()
        }
    }

    companion object {
        private val random = SecureRandom()
        private const val GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

        fun acceptKey(key: String): String =
            Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-1").digest((key + GUID).toByteArray()))

        /** ws://adres:kapı/yol adresine bağlanır ve el sıkışır. */
        fun connect(url: String, timeoutMs: Int): WebSocketClient {
            val uri = URI(url)
            val host = uri.host ?: throw HandshakeException("adres yok")
            val port = if (uri.port > 0) uri.port else 80
            val socket = Socket()
            try {
                socket.connect(InetSocketAddress(host.trim('[', ']').replace("%25", "%"), port), timeoutMs)
                socket.soTimeout = timeoutMs
                socket.tcpNoDelay = true
                val keyBytes = ByteArray(16).also { random.nextBytes(it) }
                val key = Base64.getEncoder().encodeToString(keyBytes)
                val hostHeader = if (uri.port > 0) "$host:$port" else host
                val request = "GET ${uri.rawPath.ifEmpty { "/" }} HTTP/1.1\r\nHost: $hostHeader\r\nUpgrade: websocket\r\n" +
                    "Connection: Upgrade\r\nSec-WebSocket-Key: $key\r\nSec-WebSocket-Version: 13\r\n\r\n"
                val out = socket.getOutputStream()
                out.write(request.toByteArray(Charsets.ISO_8859_1))
                out.flush()
                val input = DataInputStream(socket.getInputStream().buffered())
                val status = readLine(input)
                if (!status.startsWith("HTTP/1.1 101")) throw HandshakeException("cevap: $status")
                var accept: String? = null
                while (true) {
                    val line = readLine(input)
                    if (line.isEmpty()) break
                    val colon = line.indexOf(':')
                    if (colon > 0 && line.substring(0, colon).trim().equals("Sec-WebSocket-Accept", true)) accept = line.substring(colon + 1).trim()
                }
                if (accept != acceptKey(key)) throw HandshakeException("kabul anahtarı yanlış")
                socket.soTimeout = 0
                return WebSocketClient(socket, input, out)
            } catch (e: Exception) {
                runCatching { socket.close() }
                throw e
            }
        }

        internal fun readLine(input: DataInputStream): String {
            val b = StringBuilder()
            while (true) {
                val c = input.read()
                if (c < 0) throw IOException("bağlantı kapandı")
                if (c == '\n'.code) return b.toString().trimEnd('\r')
                b.append(c.toChar())
                if (b.length > 8192) throw IOException("satır çok uzun")
            }
        }
    }

    /** Okuma beklerken süre sınırı (ms); 0 sınırsız. */
    fun setReadTimeout(ms: Int) { socket.soTimeout = ms }
}
