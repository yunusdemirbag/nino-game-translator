// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.link

import java.io.DataInputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.concurrent.thread

/** Testler için en basit TV: tek WebSocket bağlantısı, hello'ya welcome, ping'e pong; gelen mesajları biriktirir. */
class FakeDisplay(private val name: String = "Test TV", private val versions: List<Int> = listOf(1), private val answerPings: Boolean = true) : AutoCloseable {
    private val server = ServerSocket(0)
    val port: Int get() = server.localPort
    val received = CopyOnWriteArrayList<NinoMessage>()
    /** Gelen mesajların ham metni (uzantı alanlarını denetlemek için). */
    val raw = CopyOnWriteArrayList<String>()
    @Volatile var connections = 0
        private set
    private val sockets = CopyOnWriteArrayList<Socket>()

    init {
        thread(isDaemon = true) {
            while (!server.isClosed) {
                val s = runCatching { server.accept() }.getOrNull() ?: break
                sockets += s
                connections++
                thread(isDaemon = true) { runCatching { serve(s) } }
            }
        }
    }

    fun dropAll() { sockets.forEach { runCatching { it.close() } }; sockets.clear() }

    private fun serve(s: Socket) {
        val input = DataInputStream(s.getInputStream().buffered())
        val out = s.getOutputStream()
        var key: String? = null
        while (true) {
            val line = WebSocketClient.readLine(input)
            if (line.isEmpty()) break
            if (line.startsWith("Sec-WebSocket-Key:", true)) key = line.substringAfter(':').trim()
        }
        out.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
            "Sec-WebSocket-Accept: ${WebSocketClient.acceptKey(key!!)}\r\n\r\n").toByteArray())
        out.flush()
        while (true) {
            val text = readFrame(input) ?: return
            val m = NinoMessage.decode(text)
            raw += text
            received += m
            when (m) {
                is NinoMessage.Hello -> if (m.version in versions) send(out, NinoMessage.Welcome(m.version, name))
                    else send(out, NinoMessage.Error(NinoLink.ERROR_VERSION_UNSUPPORTED, versions = versions))
                is NinoMessage.Ping -> if (answerPings) send(out, NinoMessage.Pong(m.t))
                else -> Unit
            }
        }
    }

    private fun readFrame(input: DataInputStream): String? {
        val b0 = input.read()
        if (b0 < 0) return null
        val b1 = input.readUnsignedByte()
        var len = (b1 and 0x7F).toLong()
        if (len == 126L) len = input.readUnsignedShort().toLong() else if (len == 127L) len = input.readLong()
        val mask = ByteArray(4).also { input.readFully(it) }
        val p = ByteArray(len.toInt()).also { input.readFully(it) }
        for (i in p.indices) p[i] = (p[i].toInt() xor mask[i % 4].toInt()).toByte()
        if (b0 and 0x0F == 0x8) return null
        return String(p, Charsets.UTF_8)
    }

    private fun send(out: OutputStream, m: NinoMessage) {
        val p = m.encode().toByteArray()
        synchronized(out) {
            out.write(0x81)
            if (p.size < 126) out.write(p.size) else { out.write(126); out.write(p.size shr 8); out.write(p.size and 0xFF) }
            out.write(p); out.flush()
        }
    }

    override fun close() { dropAll(); server.close() }
}
