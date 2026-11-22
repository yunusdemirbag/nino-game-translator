// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.adb

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.Collections

/**
 * Sahte adbd/sdbd: bağlantıları kabul eder, imzayı kabul edip `CNXN` döner, hizmetleri [handler] ile yanıtlar,
 * `sync:` ile gelen dosyaları saklar. Kurucuların uçtan uca testleri için.
 */
class FakeTv(private val dialect: AdbDialect, private val handler: FakeTv.(service: String, input: ByteArray) -> String) : AutoCloseable {
    private val server = ServerSocket(0, 4, InetAddress.getLoopbackAddress())
    val port: Int get() = server.localPort
    val files: MutableMap<String, ByteArray> = Collections.synchronizedMap(LinkedHashMap())
    val commands: MutableList<String> = Collections.synchronizedList(ArrayList())
    @Volatile var failure: Throwable? = null

    private val thread = Thread {
        try {
            while (!server.isClosed) {
                val s = try { server.accept() } catch (_: IOException) { break }
                s.use { serve(it) }
            }
        } catch (e: Throwable) { failure = e }
    }.apply { isDaemon = true; start() }

    private fun serve(s: Socket) {
        s.soTimeout = 20_000
        val input = s.getInputStream(); val output = s.getOutputStream()
        fun read() = AdbMessage.read(input, 1 shl 24, dialect.verifyChecksum)
        fun send(m: AdbMessage) = AdbMessage.write(output, m)
        read() // CNXN
        send(AdbMessage(AdbMessage.AUTH, AdbMessage.AUTH_TOKEN, 0, ByteArray(20) { 4 }))
        check(read().arg0 == AdbMessage.AUTH_SIGNATURE)
        send(AdbMessage(AdbMessage.CNXN, dialect.version, dialect.maxData, "device::\u0000".toByteArray()))
        var id = 500
        while (true) {
            val open = try { read() } catch (_: IOException) { return }
            if (open.command != AdbMessage.OPEN) continue
            val service = String(open.data, Charsets.UTF_8).trimEnd('\u0000')
            val local = ++id; val remote = open.arg0
            commands += service
            send(AdbMessage(AdbMessage.OKAY, local, remote))
            val buf = ByteArrayOutputStream(); var used = 0
            fun need(n: Int): ByteArray {
                while (buf.size() - used < n) {
                    val w = read(); check(w.command == AdbMessage.WRTE) { "beklenmeyen ${w.name}" }
                    buf.write(w.data); send(AdbMessage(AdbMessage.OKAY, local, remote))
                }
                return buf.toByteArray().copyOfRange(used, used + n).also { used += n }
            }
            fun reply(b: ByteArray) {
                if (b.isNotEmpty()) { send(AdbMessage(AdbMessage.WRTE, local, remote, b)); check(read().command == AdbMessage.OKAY) }
            }
            if (service == "sync:") {
                var path = ""; val content = ByteArrayOutputStream()
                loop@ while (true) {
                    val h = need(8); val tag = String(h, 0, 4, Charsets.US_ASCII); val len = AdbMessage.getLe(h, 4)
                    when (tag) {
                        "SEND" -> { path = String(need(len)); content.reset() }
                        "DATA" -> content.write(need(len))
                        "DONE" -> { files[path] = content.toByteArray(); reply(AdbConnection.syncHeader("OKAY", 0)) }
                        "QUIT" -> break@loop
                    }
                }
            } else {
                val expect = Regex("-S (\\d+)").find(service)?.groupValues?.get(1)?.toInt() ?: 0
                val data = if (expect > 0) need(expect) else ByteArray(0)
                reply(handler(service, data).toByteArray())
            }
            send(AdbMessage(AdbMessage.CLSE, local, remote))
        }
    }

    override fun close() { runCatching { server.close() }; thread.join(2_000) }
}
