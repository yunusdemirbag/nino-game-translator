// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.link

import com.ninotranslator.core.json.Json
import java.io.DataInputStream
import java.io.IOException
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import java.util.TreeMap
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.concurrent.thread

/**
 * Eski TV uygulamaları için 8787 HTTP + SSE sunucusu (tv.md 1.2–1.5). Kalıcı uyumluluk.
 *
 * `OPTIONS` → 204; `GET /hello` → `{"app":"nino"}`; `GET /events[?model=…][&viewer=obs]` → SSE; gerisi 404.
 * Bağlanana önce son `style`, çeviri son 20 sn içinde başladıysa `started` (izleyicilere değil). Bağlanınca hemen
 * ve sonra 10 sn'de bir `: ping` + `event: ping` (TV ping gördükten sonra 25 sn sessizlikte yeniden bağlanır).
 * Yavaş ya da kopmuş TV öbürlerini bekletmez; yazılamayan dinleyici düşer.
 */
class LegacyEventServer(
    private val port: Int = DEFAULT_PORT,
    private val untilClearedMs: Int = UNTIL_CLEARED_MS,
    private val pingMs: Long = PING_MS,
    private val startedWindowMs: Long = STARTED_WINDOW_MS,
    private val replay: () -> Replay = { Replay(null, null) },
    /** false iken altyazı olayları yalnız izleyicilere (OBS) gider. */
    private val tvSubtitles: () -> Boolean = { true },
    private val onChange: () -> Unit = {},
    /** Bir TV (izleyici değil) düştü: anahtarı ve nedeni (ardından [onChange] çağrılmaz). */
    private val onDrop: (key: String, reason: DropReason) -> Unit = { _, _ -> onChange() },
    private val clock: () -> Long = System::currentTimeMillis,
) : AutoCloseable {
    /** Yeni bağlanana yollanacak son durum: style alanları ve çevirinin başladığı an. */
    data class Replay(val style: Map<String, Any?>?, val startedAt: Long?)

    companion object {
        const val DEFAULT_PORT = 8787
        const val UNTIL_CLEARED_MS = 15_000
        /** TV tarafı "ping görülmüşken 25 sn sessiz" kuralıyla düşer; 10 sn bir ping kaçsa bile yeter. */
        const val PING_MS = 10_000L
        const val STARTED_WINDOW_MS = 20_000L
        private const val MAX_MODEL = 60

        /** SSE çerçevesi. */
        fun frame(name: String, body: Map<String, Any?>): String = "event: $name\ndata: ${json(body)}\n\n"

        /** Anahtarlar her düzeyde sıralı, boşluksuz JSON (Mac/Windows ile aynı). */
        fun json(body: Map<String, Any?>): String = Json.write(LinkFormat.normalizeMap(body))

        const val PING_FRAME = ": ping\nevent: ping\ndata: {}\n\n"
        const val RETRY_FRAME = "retry: 2000\n\n"

        /** `?model=` temizliği: harf, rakam, boşluk ve `.-_()`; en çok 60 karakter; boşsa null. */
        fun cleanModel(raw: String?): String? {
            if (raw == null) return null
            val s = raw.filter { it.isLetterOrDigit() || it == ' ' || it in ".-_()" }.trim().take(MAX_MODEL).trim()
            return s.ifEmpty { null }
        }

        private val SUBTITLE_EVENTS = setOf("subtitle", "clear", "screen", "screen-clear", "region", "region-clear")
    }

    private inner class Client(val socket: Socket, val viewer: Boolean, val model: String?, val appVersion: String?) {
        val address: String = socket.inetAddress?.hostAddress ?: "?"
        val key = "legacy:$address:${socket.port}"
        val outbox = Outbox("nino-sse-out-$address", 512, { write(it) }, { drop(this, it) })
        private val out: OutputStream = socket.getOutputStream().buffered()
        private fun write(s: String) { out.write(s.toByteArray(Charsets.UTF_8)); out.flush() }
    }

    @Volatile private var server: ServerSocket? = null
    @Volatile private var running = false
    private val clients = CopyOnWriteArrayList<Client>()
    private var pinger: Thread? = null
    private val lock = Any()
    private var lastSubtitleId: Int? = null

    val localPort: Int get() = server?.localPort ?: -1

    /** Bağlı eski TV'ler (izleyiciler sayılmaz). */
    fun displays(): List<ConnectedDisplay> = clients.filter { !it.viewer }.map {
        ConnectedDisplay(it.key, it.model ?: it.address, it.address, DisplayKind.LEGACY, it.model, it.appVersion)
    }

    /** İzleyici (OBS) sayısı. */
    val viewerCount: Int get() = clients.count { it.viewer }

    fun start() {
        if (server != null) return
        val s = bindServer(port)
        server = s
        running = true
        thread(isDaemon = true, name = "nino-legacy-accept") {
            while (running) {
                val c = try { s.accept() } catch (_: IOException) { break }
                thread(isDaemon = true, name = "nino-legacy-conn") { serve(c) }
            }
        }
        pinger = thread(isDaemon = true, name = "nino-legacy-ping") {
            try {
                while (running) {
                    Thread.sleep(pingMs)
                    clients.forEach { it.outbox.post(PING_FRAME) }
                }
            } catch (_: InterruptedException) { }
        }
    }

    override fun close() {
        running = false
        runCatching { server?.close() }
        server = null
        pinger?.interrupt()
        clients.toList().forEach { drop(it, DropReason.STOPPED, notify = false) }
        onChange()
    }

    /** show → subtitle. `durationMs: 0` → eski varsayılan süre (15 sn). */
    fun show(p: ShowPayload) {
        val o = TreeMap<String, Any?>()
        o["text"] = p.text
        o["duration"] = if (p.durationMs > 0) p.durationMs else untilClearedMs
        o["at"] = clock()
        (p.extras["box"] as? Map<*, *>)?.let { o["box"] = it }
        if (p.extras["replace"] == true) o["replace"] = true
        if (p.extras["paragraphs"] == true) o["paragraphs"] = true
        (p.extras["light"] as? Number)?.let { o["light"] = it }
        (p.extras["cover"] as? String)?.let { o["cover"] = it }
        synchronized(lock) { lastSubtitleId = p.id }
        broadcast("subtitle", o)
    }

    /** Eski clear'ın kimliği yok: kimlik verilmişse yalnız son altyazı oysa yollanır. */
    fun clear(id: Int?) {
        synchronized(lock) {
            if (id != null && id != lastSubtitleId) return
            lastSubtitleId = null
        }
        broadcast("clear", emptyMap())
    }

    /** Uzantı mesajı → aynı adlı eski olay. screen'de `durationMs` → `duration`. */
    fun event(type: String, fields: Map<String, Any?>) {
        val body: Map<String, Any?> = when (type) {
            "screen" -> TreeMap<String, Any?>().also { o ->
                o["duration"] = (fields["durationMs"] as? Number)?.toInt() ?: 0
                o["items"] = fields["items"] ?: emptyList<Any?>()
                if (fields["overlay"] == true) o["overlay"] = true
            }
            "started", "stopped", "screen-clear", "region-clear" -> emptyMap()
            else -> fields
        }
        if (type == "stopped") synchronized(lock) { lastSubtitleId = null }
        broadcast(type, body)
    }

    /** "Altyazı telefonda"ya geçince eski TV'lerin ekranı temizlenir (izleyiciler değil). */
    fun clearTvs() {
        val f = frame("clear", emptyMap())
        synchronized(clients) { clients.forEach { if (!it.viewer) it.outbox.post(f) } }
    }

    private fun broadcast(name: String, body: Map<String, Any?>) {
        val f = frame(name, body)
        val subtitle = name in SUBTITLE_EVENTS
        val toTvs = !subtitle || tvSubtitles()
        synchronized(clients) { clients.forEach { if (it.viewer || toTvs) it.outbox.post(f) } }
    }

    /** İlk çağıran kazanır: neden yalnız bir kez bildirilir. */
    private fun drop(c: Client, reason: DropReason, notify: Boolean = true) {
        if (!clients.remove(c)) return
        c.outbox.close()
        runCatching { c.socket.close() }
        if (notify && !c.viewer) onDrop(c.key, reason)
    }

    private fun serve(socket: Socket) {
        try {
            socket.tcpNoDelay = true
            socket.keepAlive = true
            socket.soTimeout = 10_000
            val input = DataInputStream(socket.getInputStream().buffered())
            val out = socket.getOutputStream()
            val req = HttpRequest.read(input) ?: run { socket.close(); return }
            when {
                req.method == "OPTIONS" -> { HttpReply.noContent(out); socket.close() }
                req.method == "GET" && req.path == "/hello" -> { HttpReply.send(out, "200 OK", """{"app":"nino"}"""); socket.close() }
                req.method == "GET" && req.path == "/events" -> events(socket, input, req)
                else -> { HttpReply.send(out, "404 Not Found", null); socket.close() }
            }
        } catch (_: Exception) {
            runCatching { socket.close() }
        }
    }

    private fun events(socket: Socket, input: DataInputStream, req: HttpRequest) {
        val viewer = req.query["viewer"] == "obs"
        val client = Client(socket, viewer, cleanModel(req.query["model"]), cleanModel(req.query["app"]))
        // Başlık, son durum ve kayıt tek kilitte: araya yayın girmez, sıra tek yazıcıdadır.
        synchronized(clients) {
            client.outbox.post("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream; charset=utf-8\r\nCache-Control: no-cache\r\n" +
                "Connection: keep-alive\r\n${HttpReply.CORS}\r\n" + RETRY_FRAME)
            // İlk ping hemen: TV kalp atışını görsün, sessizlik kuralı baştan işlesin.
            client.outbox.post(PING_FRAME)
            val r = replay()
            r.style?.let { client.outbox.post(frame("style", it)) }
            val startedAt = r.startedAt
            if (!viewer && startedAt != null && clock() - startedAt <= startedWindowMs) client.outbox.post(frame("started", emptyMap()))
            // Aynı TV yeniden bağlandı: eski (yarı ölü) akışı okuma zaman aşımı olmadığından burada kapatılır.
            if (!viewer) clients.filter { !it.viewer && it.address == client.address }.forEach { drop(it, DropReason.REPLACED) }
            clients += client
        }
        if (!viewer) onChange()
        // TV bağlantıyı kapatınca okuma biter.
        socket.soTimeout = 0
        var reason = DropReason.CLOSED
        try {
            while (input.read() >= 0) Unit
        } catch (e: IOException) {
            reason = DropReason.of(e)
        } finally {
            drop(client, reason)
        }
    }
}
