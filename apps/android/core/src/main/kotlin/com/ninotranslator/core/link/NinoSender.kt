// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.link

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runInterruptible
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/** Yeniden bağlanma bekleme süreleri: 1, 2, 4, 8, 8… sn. */
class ReconnectBackoff(private val initialMs: Long = 1_000, private val maximumMs: Long = 8_000) {
    private var attempt = 0
    fun next(): Long = minOf(maximumMs, initialMs shl minOf(attempt++, 20))
    fun reset() { attempt = 0 }
}

/**
 * Gönderici: TV'ye WebSocket ile bağlanır, el sıkışır, altyazı yollar.
 * Canlı tutma açıksa 5 sn'de bir ping atar; 15 sn cevap yoksa yeniden bağlanır ve son altyazıyı yeniden yollar.
 */
class NinoSender(
    val host: String,
    val port: Int = NinoLink.DEFAULT_PORT,
    val device: String? = null,
    val client: String? = null,
    val versions: List<Int> = NinoLink.SUPPORTED_VERSIONS,
) {
    sealed interface State {
        data object Disconnected : State
        data class Connected(val version: Int, val displayName: String?) : State
    }

    sealed class SenderException(message: String) : IOException(message) {
        class VersionUnsupported(val theirs: List<Int>) : SenderException("version_unsupported $theirs")
        class Rejected(val code: String) : SenderException("rejected $code")
        class UnexpectedReply : SenderException("unexpected reply")
        class NotConnected : SenderException("not connected")
        class Timeout : SenderException("timeout")
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _state = MutableStateFlow<State>(State.Disconnected)
    val state: StateFlow<State> = _state

    @Volatile var lastError: NinoMessage.Error? = null
        private set
    @Volatile var lastShown: ShowPayload? = null
        private set
    /** Son el sıkışmadaki welcome (TV adı, modeli, uygulama sürümü). */
    @Volatile var lastWelcome: NinoMessage.Welcome? = null
        private set

    /**
     * Canlı tutma yeniden bağlanınca çağrılır. Verilmişse son altyazıyı yeniden yollamak onun işidir
     * (ör. DisplayHub style → started → altyazı sırasını kendisi yollar).
     */
    @Volatile var onReconnected: (suspend (NinoSender) -> Unit)? = null

    /** Bağlantı koptu (neden ile); kopma anında, durum [State.Disconnected] olduktan sonra çağrılır. */
    @Volatile var onDropped: ((DropReason) -> Unit)? = null

    /** Canlı tutmanın yeniden bağlanma denemesi başarısız oldu. */
    @Volatile var onReconnectFailed: ((Throwable) -> Unit)? = null

    /** Son kopmanın nedeni. */
    @Volatile var lastDropReason: DropReason? = null
        private set

    @Volatile private var socket: WebSocketClient? = null
    private var readerJob: Job? = null
    private var keepAliveJob: Job? = null
    private val pendingPings = ConcurrentHashMap<Long, CompletableDeferred<Unit>>()
    private val pingCounter = AtomicLong()

    val url: String get() = NinoLink.url("ws", host, port, NinoLink.PATH_WS)

    /** Bağlanır, el sıkışır; TV'nin adını döner. */
    suspend fun connect(timeoutMs: Long = NinoLink.HANDSHAKE_TIMEOUT_MS): String? = withContext(Dispatchers.IO) {
        dropSocket(DropReason.REPLACED)
        var version = versions.max()
        val tried = HashSet<Int>()
        while (true) {
            tried += version
            val ws = runInterruptible { WebSocketClient.connect(url, timeoutMs.toInt()) }
            try {
                ws.sendText(NinoMessage.Hello(version, device, client).encode())
                ws.setReadTimeout(timeoutMs.toInt())
                val reply = try {
                    runInterruptible { ws.receiveText() }
                } catch (e: java.net.SocketTimeoutException) { throw SenderException.Timeout() }
                    ?: throw SenderException.UnexpectedReply()
                ws.setReadTimeout(0)
                when (val m = runCatching { NinoMessage.decode(reply) }.getOrElse { throw SenderException.UnexpectedReply() }) {
                    is NinoMessage.Welcome -> {
                        socket = ws
                        lastError = null
                        lastWelcome = m
                        _state.value = State.Connected(m.version, m.name)
                        startReading(ws)
                        return@withContext m.name
                    }
                    is NinoMessage.Error -> {
                        ws.close()
                        if (m.code != NinoLink.ERROR_VERSION_UNSUPPORTED) throw SenderException.Rejected(m.code)
                        val theirs = m.versions ?: emptyList()
                        val next = NinoLink.bestCommonVersion(theirs, versions)
                        if (next == null || next in tried) throw SenderException.VersionUnsupported(theirs)
                        version = next
                    }
                    else -> { ws.close(); throw SenderException.UnexpectedReply() }
                }
            } catch (e: Exception) {
                ws.close(1001)
                throw e
            }
        }
        @Suppress("UNREACHABLE_CODE") null
    }

    suspend fun show(payload: ShowPayload) {
        send(NinoMessage.Show(payload))
        lastShown = if (payload.durationMs == 0) payload else null
    }

    suspend fun clear(id: Int? = null) {
        send(NinoMessage.Clear(id))
        if (id == null || id == lastShown?.id) lastShown = null
    }

    /** Ping yollar, pong bekler; gidiş-dönüş süresi (ms). */
    suspend fun ping(timeoutMs: Long = NinoLink.PONG_TIMEOUT_MS): Long {
        val t = System.currentTimeMillis() * 1000 + pingCounter.incrementAndGet() % 1000
        val started = System.nanoTime()
        val waiter = CompletableDeferred<Unit>()
        pendingPings[t] = waiter
        try {
            send(NinoMessage.Ping(t))
            try { withTimeout(timeoutMs) { waiter.await() } } catch (e: kotlinx.coroutines.TimeoutCancellationException) { throw SenderException.Timeout() }
        } finally {
            pendingPings.remove(t)
        }
        return (System.nanoTime() - started) / 1_000_000
    }

    fun startKeepAlive(intervalMs: Long = NinoLink.PING_INTERVAL_MS, pongTimeoutMs: Long = NinoLink.PONG_TIMEOUT_MS, backoff: ReconnectBackoff = ReconnectBackoff()) {
        keepAliveJob?.cancel()
        keepAliveJob = scope.launch {
            while (isActive) {
                delay(intervalMs)
                try {
                    if (socket == null) throw SenderException.NotConnected()
                    ping(pongTimeoutMs)
                    backoff.reset()
                } catch (e: kotlinx.coroutines.CancellationException) {
                    throw e
                } catch (e: Exception) {
                    // Pong gelmedi: bağlantı ölü sayılır, bekleme boyunca bağlı görünmesin.
                    if (e is SenderException.Timeout) socket?.let { lost(it, DropReason.TIMEOUT) }
                    delay(backoff.next())
                    reconnect()
                }
            }
        }
    }

    fun disconnect() {
        keepAliveJob?.cancel()
        keepAliveJob = null
        dropSocket(DropReason.STOPPED)
    }

    /** Göndericiyi tamamen kapatır. */
    fun close() { disconnect(); scope.cancel() }

    private suspend fun reconnect() {
        try {
            connect()
            val hook = onReconnected
            if (hook != null) hook(this) else lastShown?.let { send(NinoMessage.Show(it)) }
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            // Sonraki turda yeniden denenir.
            onReconnectFailed?.invoke(e)
        }
    }

    /** Hazır JSON metnini yollar (uzantı mesajları: style, screen, region…). */
    suspend fun sendRaw(text: String) = sendText(text)

    private suspend fun send(m: NinoMessage) = sendText(m.encode())

    private suspend fun sendText(text: String) = withContext(Dispatchers.IO) {
        val ws = socket ?: throw SenderException.NotConnected()
        try {
            ws.sendText(text)
        } catch (e: IOException) {
            lost(ws, DropReason.WRITE_ERROR)
            throw e
        }
    }

    private fun startReading(ws: WebSocketClient) {
        readerJob?.cancel()
        readerJob = scope.launch {
            while (isActive) {
                val text = try { ws.receiveText() } catch (e: Exception) { lost(ws, DropReason.of(e)); return@launch }
                if (text == null) { lost(ws, DropReason.CLOSED); return@launch }
                val m = runCatching { NinoMessage.decode(text) }.getOrNull() ?: continue
                if (ws !== socket) continue
                when (m) {
                    is NinoMessage.Pong -> pendingPings[m.t]?.complete(Unit)
                    is NinoMessage.Error -> lastError = m
                    else -> Unit
                }
            }
        }
    }

    private fun lost(ws: WebSocketClient, reason: DropReason) {
        if (ws !== socket) return
        dropSocket(reason)
    }

    /** Soketi bırakır. Açık bir bağlantı vardıysa neden kaydedilir ve [onDropped] çağrılır. */
    private fun dropSocket(reason: DropReason) {
        val had = synchronized(this) { socket.also { socket = null } }
        had?.close()
        if (had != null) lastDropReason = reason
        _state.value = State.Disconnected
        pendingPings.values.forEach { it.completeExceptionally(SenderException.NotConnected()) }
        pendingPings.clear()
        if (had != null) onDropped?.invoke(reason)
    }
}

/** WebSocket kullanamayanlar için tek seferlik HTTP çağrıları. */
object NinoHttpClient {
    class StatusException(val status: Int) : IOException("http $status")

    fun info(host: String, port: Int = NinoLink.DEFAULT_PORT, timeoutMs: Int = 3_000): NinoMessage.Info {
        val c = URL(NinoLink.url("http", host, port, NinoLink.PATH_INFO)).openConnection() as HttpURLConnection
        c.connectTimeout = timeoutMs; c.readTimeout = timeoutMs
        try {
            if (c.responseCode !in 200..299) throw StatusException(c.responseCode)
            val body = c.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
            return NinoMessage.decode(body) as? NinoMessage.Info ?: throw IOException("bad reply")
        } finally { c.disconnect() }
    }

    fun show(p: ShowPayload, host: String, port: Int = NinoLink.DEFAULT_PORT) = post(NinoMessage.Show(p), NinoLink.PATH_SHOW, host, port)
    fun clear(id: Int?, host: String, port: Int = NinoLink.DEFAULT_PORT) = post(NinoMessage.Clear(id), NinoLink.PATH_CLEAR, host, port)

    private fun post(m: NinoMessage, path: String, host: String, port: Int, timeoutMs: Int = 3_000) {
        val c = URL(NinoLink.url("http", host, port, path)).openConnection() as HttpURLConnection
        c.connectTimeout = timeoutMs; c.readTimeout = timeoutMs
        c.requestMethod = "POST"; c.doOutput = true
        c.setRequestProperty("Content-Type", "application/json")
        try {
            c.outputStream.use { it.write(m.encode().toByteArray()) }
            if (c.responseCode !in 200..299) throw StatusException(c.responseCode)
            val body = c.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
            if (runCatching { NinoMessage.decode(body) }.getOrNull() != NinoMessage.Ok) throw IOException("bad reply")
        } finally { c.disconnect() }
    }
}
