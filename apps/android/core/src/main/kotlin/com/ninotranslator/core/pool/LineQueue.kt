// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.pool

import com.ninotranslator.core.http.HttpRequest
import com.ninotranslator.core.http.HttpTransport
import com.ninotranslator.core.json.Json
import com.ninotranslator.core.packs.GameIds
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.time.Instant
import java.util.UUID
import kotlin.random.Random

/**
 * Satır gönderme kuyruğu (ceviri.md 6.6): `pool/pending.jsonl` → `pool/outbox/` parçaları → `POST /v1/batches`;
 * reddedilenler `pool/parked/`. Durum `pool/state.json`. Eski `line-pool.json` bir kez içe alınır.
 * Engelleyici; çağıran IO iş parçacığında, zamanlayıcıyla (5 sn sonra, sonra 60 sn'de bir) [tick] çağırır.
 */
class LineQueue(
    private val filesDir: File,
    private val http: HttpTransport,
    private val appVersion: String,
    private val endpoint: String,
    private val now: () -> Long = System::currentTimeMillis,
    private val random: Random = Random.Default,
    /** Her çalışmada yeni oturum kimliği. */
    val session: String = UUID.randomUUID().toString(),
    /** Kurulum kimliği (uygulamanın tek kimliği); verilmezse [PoolInstall] seçer. */
    install: String? = null,
) {
    private val installId: String = install ?: PoolInstall.resolve(filesDir)

    private val dir = File(filesDir, "pool")
    private val pendingFile = File(dir, "pending.jsonl")
    private val stateFile = File(dir, "state.json")
    val outboxDir = File(dir, "outbox")
    val parkedDir = File(dir, "parked")

    data class State(
        val install: String,
        val frozenThrough: Long = 0,
        val failures: Int = 0,
        val nextAttempt: Long = 0,
        val serverRetryAt: Long = 0,
        val app: String? = null,
        val dropped: Int = 0,
    )

    @Volatile var state: State = State(installId); private set
    private var lastSeq = 0L
    private var pendingCount = 0
    private var oldestMs: Long? = null
    private var outboxSeq = 0

    init { synchronized(this) { open() } }

    private fun open() {
        dir.mkdirs()
        state = readState()
        repairTornTail(pendingFile)
        lastSeq = state.frozenThrough
        forEachPending { s, _, _, _, a -> lastSeq = maxOf(lastSeq, s); pendingCount++; oldestMs = minOf(oldestMs ?: Long.MAX_VALUE, (a * 1000).toLong()) }
        // Uygulama sürümü değişince kenara alınanlar yeniden denenir.
        if (state.app != appVersion) {
            parkedDir.listFiles().orEmpty().filter { it.name.endsWith(".json") }.forEach { f -> outboxDir.mkdirs(); f.renameTo(File(outboxDir, f.name)) }
            state = state.copy(app = appVersion)
            writeState()
        }
    }

    private fun readState(): State {
        if (!stateFile.isFile) return State(installId).also { state = it; writeState(it) }
        val m = runCatching { Json.parseObject(stateFile.readText()) }.getOrNull()
        if (m == null) {
            stateFile.renameTo(File(dir, "state.broken-${now() / 1000}.json"))
            return State(installId).also { writeState(it) }
        }
        fun l(k: String) = (m[k] as? Number)?.toLong()
        // Kimlik her zaman uygulamanın tek kimliği; dosyadaki farklıysa hemen düzeltilir.
        val s = State(
            install = installId,
            frozenThrough = l("frozenThrough") ?: 0, failures = l("failures")?.toInt() ?: 0,
            nextAttempt = l("nextAttempt") ?: 0, serverRetryAt = l("serverRetryAt") ?: 0,
            app = m["app"] as? String, dropped = l("dropped")?.toInt() ?: 0,
        )
        if (m["install"] != installId) writeState(s)
        return s
    }

    private fun writeState(s: State = state) {
        val json = Json.write(linkedMapOf(
            "install" to s.install, "frozenThrough" to s.frozenThrough, "failures" to s.failures, "nextAttempt" to s.nextAttempt,
            "serverRetryAt" to s.serverRetryAt, "app" to s.app, "dropped" to s.dropped,
        ))
        runCatching { atomicWrite(stateFile, json) }
    }

    private fun repairTornTail(f: File) {
        if (!f.isFile || f.length() == 0L) return
        RandomAccessFile(f, "rw").use { raf ->
            raf.seek(raf.length() - 1)
            if (raf.read() == '\n'.code) return
            var p = raf.length() - 1
            while (p > 0) { raf.seek(p - 1); if (raf.read() == '\n'.code) break; p-- }
            raf.setLength(p)
        }
    }

    private inline fun forEachPending(block: (Long, String, String?, String?, Double) -> Unit) {
        if (!pendingFile.isFile) return
        pendingFile.bufferedReader().useLines { lines ->
            for (line in lines) {
                if (line.isBlank()) continue
                val m = runCatching { Json.parseObject(line) }.getOrNull() ?: continue
                val s = (m["s"] as? Number)?.toLong() ?: continue
                val t = m["t"] as? String ?: continue
                block(s, t, m["g"] as? String, m["e"] as? String, (m["a"] as? Number)?.toDouble() ?: 0.0)
            }
        }
    }

    @get:Synchronized val pending: Int get() = pendingCount

    /** Görülen satırı süzgeçten geçirip kuyruğa ekler; oyun asıl kimlikle ([GameIds]) yazılır. Kabul edildiyse true. */
    @Synchronized fun offer(text: String, game: String?, at: Double = now() / 1000.0, sessionId: String? = session): Boolean {
        val clean = PoolLineFilter.clean(text)
        if (!PoolLineFilter.accepts(clean)) return false
        if (pendingFile.length() > MAX_PENDING_BYTES) { state = state.copy(dropped = state.dropped + 1); writeState(); return false }
        val rec = linkedMapOf("s" to lastSeq + 1, "t" to clean, "g" to GameIds.id(game), "e" to sessionId, "a" to at)
        try {
            dir.mkdirs()
            pendingFile.appendText(Json.write(rec) + "\n")
        } catch (e: IOException) { return false }
        lastSeq++
        pendingCount++
        oldestMs = minOf(oldestMs ?: Long.MAX_VALUE, (at * 1000).toLong())
        return true
    }

    /** Eski `files/line-pool.json` kuyruğunu bir kez aktarır; dosya `.imported` adına taşınır. */
    @Synchronized fun importLegacy(): Int {
        val f = File(filesDir, "line-pool.json")
        if (!f.isFile) return 0
        var n = 0
        runCatching {
            val root = Json.parseObject(f.readText())
            for (item in root["queue"] as? List<*> ?: emptyList<Any>()) {
                val m = item as? Map<*, *> ?: continue
                val t = m["text"] as? String ?: continue
                val a = (m["firstSeen"] as? String)?.let { runCatching { Instant.parse(it).epochSecond.toDouble() }.getOrNull() } ?: (now() / 1000.0)
                if (offer(t, null, a, null)) n++
            }
        }
        f.renameTo(File(filesDir, "line-pool.json.imported"))
        return n
    }

    /** Ortak havuz kapatılınca kuyruk, bekleyen ve kenara alınmış parçaların hepsi silinir. */
    @Synchronized fun clearAll() {
        pendingFile.delete()
        outboxDir.listFiles().orEmpty().forEach { it.delete() }
        parkedDir.listFiles().orEmpty().forEach { it.delete() }
        pendingCount = 0; oldestMs = null
        state = state.copy(frozenThrough = lastSeq, failures = 0, nextAttempt = 0, serverRetryAt = 0)
        writeState()
    }

    /** Ağ geri gelince bekleme sıfırlanır. */
    @Synchronized fun networkRestored() { state = state.copy(nextAttempt = 0, failures = 0); writeState() }

    /** Zamanlayıcı adımı: gerekiyorsa parçala, sonra gönder. */
    @Synchronized fun tick(): Int {
        val t = now()
        if (pendingCount >= BATCH_LINES || (oldestMs != null && t - oldestMs!! >= MAX_WAIT_MS)) freeze()
        return send()
    }

    /** Bekleyenleri (oyun, oturum, metin) üçlüsüne göre birleştirip 200 farklı satırlık parçalara böler. */
    @Synchronized fun freeze(): Int {
        data class K(val g: String?, val e: String?, val t: String)
        class Agg(var count: Int, var first: Double, var last: Double)
        val agg = LinkedHashMap<K, Agg>()
        var upTo = state.frozenThrough
        forEachPending { s, text, g, e, a ->
            if (s <= state.frozenThrough) return@forEachPending
            upTo = maxOf(upTo, s)
            // Eski sürümün yazdığı takma adlar ("grand-theft-auto-vi") de asıl kimlikte birleşir.
            val x = agg.getOrPut(K(GameIds.id(g), e, text)) { Agg(0, a, a) }
            x.count++; x.first = minOf(x.first, a); x.last = maxOf(x.last, a)
        }
        if (agg.isEmpty()) { pendingFile.delete(); pendingCount = 0; oldestMs = null; return 0 }
        outboxDir.mkdirs()
        var made = 0
        for (chunk in agg.entries.chunked(BATCH_LINES)) {
            val lines = chunk.map { (k, v) -> linkedMapOf("text" to k.t, "game" to k.g, "session" to k.e, "count" to v.count, "first" to v.first, "last" to v.last) }
            writeBatch(lines, upTo)
            made++
        }
        // En çok 1000 parça bekler: fazlası (en eskiler) atılır.
        val files = outboxFiles()
        if (files.size > MAX_OUTBOX) files.take(files.size - MAX_OUTBOX).forEach { it.delete() }
        pendingFile.delete()
        pendingCount = 0; oldestMs = null
        state = state.copy(frozenThrough = upTo)
        writeState()
        return made
    }

    private fun writeBatch(lines: List<Map<String, Any?>>, upTo: Long): File {
        val id = UUID(random.nextLong(), random.nextLong()).toString()
        val body = linkedMapOf("v" to 1, "batch" to id, "install" to state.install, "app" to appVersion, "platform" to "android", "lines" to lines, "upTo" to upTo)
        val name = now().toString().padStart(15, '0') + "-" + (outboxSeq++ % 10_000).toString().padStart(4, '0') + "-" + id + ".json"
        val f = File(outboxDir, name)
        atomicWrite(f, Json.write(body))
        return f
    }

    fun outboxFiles(): List<File> = outboxDir.listFiles().orEmpty().filter { it.isFile && it.name.endsWith(".json") }.sortedBy { it.name }

    /** Bekleyen parçaları gönderir; gönderilen parça sayısını döner. */
    @Synchronized fun send(): Int {
        val t = now()
        if (t < state.nextAttempt || t < state.serverRetryAt) return 0
        var sent = 0
        for (f in outboxFiles()) {
            val body = runCatching { Json.parseObject(f.readText()) }.getOrNull()
            if (body == null) { f.delete(); continue }
            val r = try {
                http.send(HttpRequest.json(endpoint + "/v1/batches", Json.write(body), mapOf("User-Agent" to PoolEndpoint.userAgent(appVersion)), 15_000, 30_000))
            } catch (e: IOException) { backoff(); return sent }
            when {
                r.ok -> {
                    val m = runCatching { Json.parseObject(r.text) }.getOrNull()
                    if (m?.get("ok") == true && m["batch"] == body["batch"]) { f.delete(); sent++; if (state.failures != 0) { state = state.copy(failures = 0); writeState() } }
                    else { backoff(); return sent } // kimlik tutmuyor: yanlış sunucu
                }
                r.status == 413 -> split(f, body)
                r.status == 429 || r.status == 503 -> {
                    val secs = r.header("Retry-After")?.trim()?.toLongOrNull() ?: 60
                    state = state.copy(serverRetryAt = now() + secs.coerceIn(1, 86_400) * 1000); writeState()
                    return sent
                }
                r.status == 400 || r.status == 422 -> { parkedDir.mkdirs(); f.renameTo(File(parkedDir, f.name)) }
                else -> { backoff(); return sent }
            }
        }
        return sent
    }

    /** 413: parça ikiye bölünür (tek satırsa kenara alınır). */
    private fun split(f: File, body: Map<String, Any?>) {
        val lines = (body["lines"] as? List<*>).orEmpty().mapNotNull { @Suppress("UNCHECKED_CAST") (it as? Map<String, Any?>) }
        if (lines.size <= 1) { parkedDir.mkdirs(); f.renameTo(File(parkedDir, f.name)); return }
        val upTo = (body["upTo"] as? Number)?.toLong() ?: state.frozenThrough
        val half = lines.size / 2
        writeBatch(lines.subList(0, half), upTo)
        writeBatch(lines.subList(half, lines.size), upTo)
        f.delete()
    }

    /** Artan bekleme: 30 sn × 2^(hata-1), en çok 1 saat, ±%20. */
    private fun backoff() {
        val n = state.failures + 1
        val base = minOf(3_600_000.0, 30_000.0 * Math.pow(2.0, (n - 1).toDouble()))
        val jitter = base * (random.nextDouble() * 0.4 - 0.2)
        state = state.copy(failures = n, nextAttempt = now() + (base + jitter).toLong())
        writeState()
    }

    private fun atomicWrite(f: File, text: String) {
        f.parentFile?.mkdirs()
        val tmp = File(f.parentFile, f.name + ".tmp")
        tmp.writeText(text)
        java.nio.file.Files.move(tmp.toPath(), f.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING, java.nio.file.StandardCopyOption.ATOMIC_MOVE)
    }

    companion object {
        const val BATCH_LINES = 200
        const val MAX_WAIT_MS = 120_000L
        const val MAX_OUTBOX = 1000
        const val MAX_PENDING_BYTES = 32L * 1024 * 1024
    }
}
