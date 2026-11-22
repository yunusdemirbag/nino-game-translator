// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install.adb

import com.ninotranslator.mobile.tv.install.LocalIoException
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException

/** Bağlantı kurulamadığında neden. */
enum class AdbFailure { UNREACHABLE, NOT_APPROVED, NOT_PAIRED, NEEDS_APPROVAL }

class AdbException(val failure: AdbFailure, message: String, cause: Throwable? = null) : LocalIoException(message, cause)

/** Bir kanalın kapanışı ya da `sync:` hatası. */
class AdbChannelException(message: String) : LocalIoException(message)

/** El sıkışmanın ADB (Android TV) ve SDB (Samsung) farkları. */
data class AdbDialect(
    val version: Int,
    val maxData: Int,
    val banner: ByteArray,
    /** Gelen çerçevenin en büyük uzunluğu. */
    val readLimit: Int,
    val verifyChecksum: Boolean,
    /** true: jeton SHA1withRSA ile özetlenerek imzalanır (sdb); false: adb'nin ham imzası. */
    val sha1Sign: Boolean,
    val keyName: String,
    /** TV `maxdata` 0 bildirirse. */
    val fallbackMaxData: Int,
    val firstLocalId: Int,
) {
    companion object {
        val ADB = AdbDialect(
            version = 0x01000001, maxData = 256 * 1024, banner = "host::\u0000".toByteArray(Charsets.US_ASCII),
            readLimit = 1024 * 1024, verifyChecksum = false, sha1Sign = false, keyName = "nino@phone",
            fallbackMaxData = 4096, firstLocalId = 1,
        )
        val SDB = AdbDialect(
            version = 0x01000000, maxData = 4096, banner = "host::sdb-net-client".toByteArray(Charsets.US_ASCII),
            readLimit = 16 * 1024 * 1024, verifyChecksum = true, sha1Sign = true, keyName = "nino@android",
            fallbackMaxData = 4096, firstLocalId = 'b'.code,
        )
    }
}

/** Alttaki bağlantı (soket ya da testte boru). */
interface AdbTransport : AutoCloseable {
    val input: InputStream
    val output: OutputStream
    fun setReadTimeout(ms: Int)

    companion object {
        fun socket(host: String, port: Int, connectTimeoutMs: Int, readTimeoutMs: Int): AdbTransport {
            val s = Socket()
            try {
                s.tcpNoDelay = true
                s.connect(InetSocketAddress(host, port), connectTimeoutMs)
                s.soTimeout = readTimeoutMs
            } catch (e: IOException) {
                runCatching { s.close() }
                throw e
            }
            return object : AdbTransport {
                override val input: InputStream = s.getInputStream()
                override val output: OutputStream = s.getOutputStream()
                override fun setReadTimeout(ms: Int) { s.soTimeout = ms }
                override fun close() = s.close()
            }
        }
    }
}

/** `STLS` sonrası aynı bağlantı üstünde TLS kurar; şifreli akışları döner. */
fun interface AdbTlsUpgrade {
    fun upgrade(input: InputStream, output: OutputStream): Pair<InputStream, OutputStream>
}

/**
 * ADB/SDB istemcisi (AOSP protocol.txt): `CNXN` el sıkışması, `AUTH`, isteğe bağlı `STLS` (TLS 1.3), tek kanallı
 * `OPEN`/`WRTE`/`OKAY`/`CLSE`, `sync:` ile dosya gönderme.
 */
class AdbConnection(
    private val transport: AdbTransport,
    private val dialect: AdbDialect,
    private val key: AdbKey,
    private val log: (String) -> Unit = {},
) : AutoCloseable {
    private var input: InputStream = transport.input
    private var output: OutputStream = transport.output
    private var nextLocalId = dialect.firstLocalId
    var maxData: Int = dialect.maxData
        private set
    /** TV'nin `CNXN` verisi (ör. `device::ro.product.name=…`). */
    var banner: String = ""
        private set
    var tlsUsed = false
        private set

    /**
     * El sıkışma. [tls] yoksa `STLS` gelince ulaşılamadı sayılır. [approvalWaitMs] 0 ise TV onay isteyince
     * [AdbFailure.NEEDS_APPROVAL] (sessiz denetim); değilse açık anahtar gönderilir, [onApprove] çağrılır ve beklenir.
     */
    fun handshake(
        tls: AdbTlsUpgrade?,
        handshakeTimeoutMs: Int = 10_000,
        approvalWaitMs: Int = 90_000,
        sessionTimeoutMs: Int = 120_000,
        onApprove: () -> Unit = {},
    ) {
        transport.setReadTimeout(handshakeTimeoutMs)
        send(AdbMessage(AdbMessage.CNXN, dialect.version, dialect.maxData, dialect.banner))
        var tokens = 0
        var sentKey = false
        while (true) {
            val m = try {
                read()
            } catch (e: IOException) {
                throw when {
                    tlsUsed -> AdbException(AdbFailure.NOT_PAIRED, "TLS'ten sonra bağlantı kapandı: ${e.message}", e)
                    sentKey -> AdbException(AdbFailure.NOT_APPROVED, "onay beklenirken: ${e.message}", e)
                    else -> AdbException(AdbFailure.UNREACHABLE, "el sıkışmada: ${e.message}", e)
                }
            }
            when (m.command) {
                AdbMessage.STLS -> {
                    if (tls == null || tlsUsed) throw AdbException(AdbFailure.UNREACHABLE, "beklenmeyen STLS")
                    log("TV TLS istedi (kablosuz hata ayıklama)")
                    send(AdbMessage(AdbMessage.STLS, 0x01000000, 0))
                    val (i, o) = try {
                        tls.upgrade(input, output)
                    } catch (e: Exception) {
                        throw AdbException(AdbFailure.NOT_PAIRED, "TLS kurulamadı: ${e.message}", e)
                    }
                    input = i; output = o; tlsUsed = true
                }
                AdbMessage.AUTH -> {
                    if (m.arg0 != AdbMessage.AUTH_TOKEN) throw AdbException(AdbFailure.UNREACHABLE, "beklenmeyen AUTH ${m.arg0}")
                    tokens++
                    when {
                        tokens == 1 -> {
                            val sig = if (dialect.sha1Sign) key.signSha1WithRsa(m.data) else key.signAdbToken(m.data)
                            send(AdbMessage(AdbMessage.AUTH, AdbMessage.AUTH_SIGNATURE, 0, sig))
                        }
                        !sentKey -> {
                            if (approvalWaitMs <= 0) throw AdbException(AdbFailure.NEEDS_APPROVAL, "TV onay istiyor")
                            log("TV bu telefonu tanımıyor; açık anahtar gönderiliyor, onay bekleniyor")
                            val line = (key.publicKeyLine(dialect.keyName) + "\u0000").toByteArray(Charsets.US_ASCII)
                            send(AdbMessage(AdbMessage.AUTH, AdbMessage.AUTH_RSAPUBLICKEY, 0, line))
                            sentKey = true
                            transport.setReadTimeout(approvalWaitMs)
                            onApprove()
                        }
                        else -> throw AdbException(AdbFailure.NOT_APPROVED, "TV yine jeton gönderdi")
                    }
                }
                AdbMessage.CNXN -> {
                    maxData = minOf(dialect.maxData, if (m.arg1 > 0) m.arg1 else dialect.fallbackMaxData)
                    banner = String(m.data, Charsets.UTF_8).trimEnd('\u0000')
                    transport.setReadTimeout(sessionTimeoutMs)
                    log("bağlandı: ${banner.take(200)} (en büyük veri $maxData)")
                    return
                }
                else -> throw AdbException(AdbFailure.UNREACHABLE, "beklenmeyen paket ${m.name}")
            }
        }
    }

    // --- Kanallar ---

    private inner class Channel(val local: Int) {
        var remote = 0
        var closed = false
        val pending = ByteArrayOutputStream()
        var pendingOffset = 0
    }

    private var current: Channel? = null

    private fun send(m: AdbMessage) = AdbMessage.write(output, m)
    private fun read(): AdbMessage = AdbMessage.read(input, dialect.readLimit, dialect.verifyChecksum)

    /**
     * Bir paket okuyup işler. Başka kanala gelen veriye ve TV'nin kendiliğinden açtığı kanala `CLSE` dönülür.
     * Bu kanalın `OKAY`'i gelirse true.
     */
    private fun pump(ch: Channel): Boolean {
        val m = read()
        when (m.command) {
            AdbMessage.WRTE -> if (m.arg1 == ch.local && !ch.closed) {
                if (ch.remote == 0) ch.remote = m.arg0
                ch.pending.write(m.data)
                send(AdbMessage(AdbMessage.OKAY, ch.local, ch.remote))
            } else {
                send(AdbMessage(AdbMessage.CLSE, 0, m.arg0))
            }
            AdbMessage.OKAY -> if (m.arg1 == ch.local) {
                if (ch.remote == 0) ch.remote = m.arg0
                return true
            }
            AdbMessage.CLSE -> if (m.arg1 == ch.local || (m.arg1 == 0 && m.arg0 == ch.remote && ch.remote != 0)) ch.closed = true
            AdbMessage.OPEN -> send(AdbMessage(AdbMessage.CLSE, 0, m.arg0))
            else -> log("yok sayılan paket ${m.name}")
        }
        return false
    }

    private fun openChannel(service: String): Channel {
        check(current == null) { "bir anda tek kanal" }
        val ch = Channel(nextLocalId++)
        send(AdbMessage(AdbMessage.OPEN, ch.local, 0, (service + "\u0000").toByteArray(Charsets.UTF_8)))
        // TV kanal açılmadan veri yazabilir (sdb): veri saklanır, kanal açılmış sayılır.
        while (ch.remote == 0 && !ch.closed) pump(ch)
        if (ch.remote == 0) throw AdbChannelException("TV '$service' hizmetini açmadı")
        current = ch
        return ch
    }

    private fun writeChannel(ch: Channel, data: ByteArray, off: Int = 0, len: Int = data.size) {
        var p = off
        val end = off + len
        while (p < end) {
            if (ch.closed) throw AdbChannelException("kanal yazarken kapandı")
            val n = minOf(maxData, end - p)
            send(AdbMessage(AdbMessage.WRTE, ch.local, ch.remote, data.copyOfRange(p, p + n)))
            while (!pump(ch)) { if (ch.closed) throw AdbChannelException("kanal yazarken kapandı") }
            p += n
        }
    }

    private fun readExact(ch: Channel, n: Int): ByteArray {
        while (ch.pending.size() - ch.pendingOffset < n) {
            if (ch.closed) throw LocalIoException("kanal kapandı")
            pump(ch)
        }
        val all = ch.pending.toByteArray()
        val out = all.copyOfRange(ch.pendingOffset, ch.pendingOffset + n)
        ch.pendingOffset += n
        return out
    }

    private fun readToClose(ch: Channel): ByteArray {
        while (!ch.closed) pump(ch)
        val all = ch.pending.toByteArray()
        return all.copyOfRange(ch.pendingOffset, all.size)
    }

    private fun closeChannel(ch: Channel) {
        // TV kapatmış olsa da CLSE dönülür (adbd bilinmeyen kanalın CLSE'sini yok sayar).
        if (ch.remote != 0) runCatching { send(AdbMessage(AdbMessage.CLSE, ch.local, ch.remote)) }
        current = null
    }

    /** Hizmeti açar, [input]'u yazar ve TV kanalı kapatana kadar gelen çıktıyı döner. */
    fun service(name: String, input: ByteArray? = null): ByteArray {
        val ch = openChannel(name)
        try {
            if (input != null) writeChannel(ch, input)
            return readToClose(ch)
        } finally { closeChannel(ch) }
    }

    /** Hizmeti açar ve [stream]'i [length] bayt akıtır (kurulum), sonra çıktıyı okur. */
    fun serviceStreaming(name: String, stream: InputStream, onProgress: (Long) -> Unit = {}): ByteArray {
        val ch = openChannel(name)
        try {
            val buf = ByteArray(maxData)
            var total = 0L
            while (true) {
                val r = stream.read(buf)
                if (r < 0) break
                if (r == 0) continue
                writeChannel(ch, buf, 0, r)
                total += r
                onProgress(total)
            }
            return readToClose(ch)
        } finally { closeChannel(ch) }
    }

    fun shell(command: String): String = String(service("shell:$command"), Charsets.UTF_8)

    /**
     * `sync:` ile dosya gönderir: `SEND <yol>[,<kip>]`, 64 KB'lık `DATA`, `DONE` + zaman; TV `OKAY` ya da
     * `FAIL <ileti>` döner. [mode] null ise yoldan sonra kip yazılmaz (sdb).
     */
    fun push(path: String, mode: Int?, data: InputStream, mtimeSec: Int = (System.currentTimeMillis() / 1000).toInt()) {
        val ch = openChannel("sync:")
        try {
            val spec = (if (mode != null) "$path,$mode" else path).toByteArray(Charsets.UTF_8)
            writeChannel(ch, syncHeader("SEND", spec.size) + spec)
            val buf = ByteArray(SYNC_DATA_MAX)
            while (true) {
                var n = 0
                while (n < buf.size) { val r = data.read(buf, n, buf.size - n); if (r < 0) break; n += r }
                if (n == 0) break
                writeChannel(ch, syncHeader("DATA", n) + buf.copyOf(n))
                if (n < buf.size) break
            }
            writeChannel(ch, syncHeader("DONE", mtimeSec))
            val h = readExact(ch, 8)
            val id = String(h, 0, 4, Charsets.US_ASCII)
            val len = AdbMessage.getLe(h, 4)
            when (id) {
                "OKAY" -> {}
                "FAIL" -> throw AdbChannelException("FAIL " + String(readExact(ch, len.coerceIn(0, 64 * 1024)), Charsets.UTF_8))
                else -> throw AdbChannelException("beklenmeyen sync yanıtı $id")
            }
            runCatching { writeChannel(ch, syncHeader("QUIT", 0)) }
        } finally { closeChannel(ch) }
    }

    override fun close() { runCatching { transport.close() } }

    companion object {
        const val SYNC_DATA_MAX = 64 * 1024

        fun syncHeader(id: String, value: Int): ByteArray {
            val b = ByteArray(8)
            id.toByteArray(Charsets.US_ASCII).copyInto(b)
            AdbMessage.putLe(b, 4, value)
            return b
        }

        /** Okuma zaman aşımı mı. */
        fun isTimeout(e: Throwable): Boolean = generateSequence(e) { it.cause }.any { it is SocketTimeoutException }
    }
}
