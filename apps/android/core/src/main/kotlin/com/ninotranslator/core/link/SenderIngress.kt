// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.link

import java.io.DataInputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/** Sunucu portunu açar; dolu ise birkaç kez yeniden dener. */
internal fun bindServer(port: Int, attempts: Int = 3, waitMs: Long = 300): ServerSocket {
    var last: IOException? = null
    repeat(attempts) { i ->
        val s = ServerSocket()
        try {
            s.reuseAddress = true
            s.bind(InetSocketAddress(port))
            return s
        } catch (e: IOException) {
            runCatching { s.close() }
            last = e
            if (i < attempts - 1) Thread.sleep(waitMs)
        }
    }
    throw last ?: IOException("port açılamadı: $port")
}

/**
 * Tek bağlantının gönderim sırası: yazma kendi iş parçacığında, sırayla. Yazma hatası [DropReason.WRITE_ERROR];
 * sıra dolarsa (TV okumuyor, bağlantı asılı) [DropReason.TIMEOUT].
 */
internal class Outbox(name: String, capacity: Int, private val write: (String) -> Unit, private val failed: (DropReason) -> Unit) {
    private val queue = LinkedBlockingQueue<String>(capacity)
    @Volatile private var open = true
    private val worker = thread(isDaemon = true, name = name) {
        try {
            while (open) {
                val m = queue.poll(500, TimeUnit.MILLISECONDS) ?: continue
                write(m)
            }
        } catch (_: InterruptedException) {
        } catch (_: Exception) {
            if (open) failed(DropReason.WRITE_ERROR)
        }
    }

    fun post(m: String) {
        if (!open) return
        if (!queue.offer(m)) failed(DropReason.TIMEOUT)
    }

    fun close() { open = false; queue.clear(); worker.interrupt() }
}

/**
 * Gönderici girişi (47800): LG/Samsung web TV'leri telefona bağlanır. `GET /nino/info` (`role:"sender"`, CORS),
 * `OPTIONS` 204, `GET /nino/ws` WebSocket. Bağlantı açılınca ilk `hello`'yu telefon yollar, TV `welcome` döner;
 * sonra son durum (style, started, altyazı) gider. 5 sn'de bir ping; 15 sn TV'den ses yoksa kapatılır.
 * Birden çok TV aynı anda bağlanabilir.
 */
class SenderIngress(
    private val port: Int,
    private val info: () -> String,
    private val hello: (version: Int) -> String,
    private val replay: () -> List<String>,
    private val onChange: () -> Unit,
    /** Hazır bir TV düştü: anahtarı ve nedeni (ardından [onChange] çağrılmaz). */
    private val onDrop: (key: String, reason: DropReason) -> Unit = { _, _ -> onChange() },
    private val pingIntervalMs: Long = NinoLink.PING_INTERVAL_MS,
    private val silenceTimeoutMs: Long = NinoLink.PONG_TIMEOUT_MS,
    private val handshakeTimeoutMs: Long = NinoLink.HANDSHAKE_TIMEOUT_MS,
    private val versions: List<Int> = NinoLink.SUPPORTED_VERSIONS,
    /** Yalnız özel ağ adreslerinden gelen bağlantılar kabul edilir. */
    private val localOnly: Boolean = true,
) : AutoCloseable {
    private inner class Peer(val socket: Socket, val ws: WebSocketServerConnection) {
        val address: String = socket.inetAddress?.hostAddress ?: "?"
        @Volatile var welcome: NinoMessage.Welcome? = null
        @Volatile var ready = false
        val outbox = Outbox("nino-ws-out-$address", 512, { ws.sendText(it) }, { drop(this, it) })
        val key = "web:$address:${socket.port}"
    }

    @Volatile private var server: ServerSocket? = null
    private val peers = CopyOnWriteArrayList<Peer>()
    @Volatile private var running = false
    private var pinger: Thread? = null

    val localPort: Int get() = server?.localPort ?: -1

    fun start() {
        if (server != null) return
        val s = bindServer(port)
        server = s
        running = true
        thread(isDaemon = true, name = "nino-ingress-accept") {
            while (running) {
                val c = try { s.accept() } catch (_: IOException) { break }
                thread(isDaemon = true, name = "nino-ingress-conn") { serve(c) }
            }
        }
        pinger = thread(isDaemon = true, name = "nino-ingress-ping") {
            try {
                while (running) {
                    Thread.sleep(pingIntervalMs)
                    val ping = NinoMessage.Ping(System.currentTimeMillis()).encode()
                    peers.forEach { if (it.ready) it.outbox.post(ping) }
                }
            } catch (_: InterruptedException) { }
        }
    }

    /** Hazır bütün TV'lere yollar; beklemez. */
    fun broadcast(json: String) {
        synchronized(peers) { peers.forEach { if (it.ready) it.outbox.post(json) } }
    }

    fun displays(): List<ConnectedDisplay> = peers.filter { it.ready }.map { p ->
        val w = p.welcome
        ConnectedDisplay(p.key, w?.name?.takeIf { it.isNotBlank() } ?: p.address, p.address, DisplayKind.WEB_TV, w?.model, w?.appVersion)
    }

    override fun close() {
        running = false
        runCatching { server?.close() }
        server = null
        pinger?.interrupt()
        peers.toList().forEach { drop(it, DropReason.STOPPED, notify = false) }
        onChange()
    }

    /** İlk çağıran kazanır: neden yalnız bir kez bildirilir. */
    private fun drop(p: Peer, reason: DropReason, notify: Boolean = true) {
        val wasReady = p.ready
        p.ready = false
        if (!peers.remove(p)) return
        p.outbox.close()
        if (notify && wasReady) onDrop(p.key, reason)
        // Yazma kilidini beklemeden: takılmış bir TV'ye yazan iş parçacığı soket kapanınca çözülür.
        runCatching { p.socket.close() }
    }

    private fun serve(socket: Socket) {
        try {
            val remote = socket.inetAddress?.hostAddress ?: ""
            if (localOnly && !NinoLink.isLocalAddress(remote)) { socket.close(); return }
            socket.tcpNoDelay = true
            socket.keepAlive = true
            socket.soTimeout = 10_000
            val input = DataInputStream(socket.getInputStream().buffered())
            val out = socket.getOutputStream().buffered()
            val req = HttpRequest.read(input) ?: run { socket.close(); return }
            when {
                req.method == "OPTIONS" -> { HttpReply.noContent(out); socket.close() }
                req.method == "GET" && req.path == NinoLink.PATH_INFO -> { HttpReply.send(out, "200 OK", info()); socket.close() }
                req.path == NinoLink.PATH_WS -> {
                    val ws = WebSocketServerConnection.accept(socket, input, out, req) ?: run { socket.close(); return }
                    session(socket, ws)
                }
                else -> { HttpReply.send(out, "404 Not Found", """{"app":"nino","type":"error","code":"bad_message"}"""); socket.close() }
            }
        } catch (_: Exception) {
            runCatching { socket.close() }
        }
    }

    private fun session(socket: Socket, ws: WebSocketServerConnection) {
        val peer = Peer(socket, ws)
        peers += peer
        var reason = DropReason.CLOSED
        try {
            // El sıkışma: hello telefondan; 5 sn içinde welcome gelmezse kapatılır.
            ws.setReadTimeout(handshakeTimeoutMs.toInt())
            var version = versions.max()
            val tried = HashSet<Int>()
            while (true) {
                tried += version
                ws.sendText(hello(version))
                val reply = ws.receiveText() ?: return
                when (val m = runCatching { NinoMessage.decode(reply) }.getOrNull()) {
                    is NinoMessage.Welcome -> { peer.welcome = m; break }
                    is NinoMessage.Error -> {
                        val next = if (m.code == NinoLink.ERROR_VERSION_UNSUPPORTED) NinoLink.bestCommonVersion(m.versions ?: emptyList(), versions) else null
                        if (next == null || next in tried) return
                        version = next
                    }
                    else -> return
                }
            }
            // Son durum ve "hazır" tek kilitte: araya yayın girmez.
            synchronized(peers) {
                peer.ready = true
                replay().forEach { peer.outbox.post(it) }
            }
            onChange()
            ws.setReadTimeout(silenceTimeoutMs.toInt())
            while (true) {
                val text = try { ws.receiveText() } catch (_: SocketTimeoutException) { reason = DropReason.TIMEOUT; return }
                    catch (_: WebSocketServerConnection.TooLargeException) {
                        reason = DropReason.OTHER
                        runCatching { ws.sendText(NinoMessage.Error(NinoLink.ERROR_TOO_LARGE).encode()) }
                        return
                    } ?: return
                // pong ve öbür mesajlar yalnız "TV canlı" demektir; okuma süresi her mesajda yenilenir.
                if (text.isEmpty()) continue
            }
        } catch (e: Exception) {
            reason = DropReason.of(e)
        } finally {
            drop(peer, reason)
        }
    }
}
