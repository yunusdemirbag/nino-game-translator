// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.pool

import com.ninotranslator.core.http.HttpRequest
import com.ninotranslator.core.http.HttpResponse
import com.ninotranslator.core.http.HttpTransport
import com.ninotranslator.core.json.Json
import com.ninotranslator.core.packs.GameIds
import com.ninotranslator.core.packs.PackKey
import com.ninotranslator.core.translation.PoolAccess
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runInterruptible
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File

/**
 * Ortak havuz istemcisi (ceviri.md 6): sunucu ayarı, toplu indirme, anında çeviri sorusu, çok satırlı soru,
 * havuz öncelikli oyun, varlık sinyali ve oyunu ekrandan tanıma isteği. Satır gönderme kuyruğu [LineQueue]'da.
 * Sunucuya giden her `game` alanı asıl kimliktir ([GameIds.id]: "Grand Theft Auto VI" → "gta-6").
 */
class SharedPool(
    private val filesDir: File,
    private val http: HttpTransport,
    private val appVersion: String,
    private val scope: CoroutineScope,
    private val now: () -> Long = System::currentTimeMillis,
    /** "Ortak havuz" ayarı. */
    @Volatile var shareEnabled: Boolean = true,
    endpoint: String? = null,
    /** Ayrıca satır kuyruğu (gönderme); yoksa [offer] bir şey yapmaz. */
    @Volatile var queue: LineQueue? = null,
    /** Kurulum kimliği (uygulamanın tek kimliği); verilmezse [PoolInstall] seçer. */
    install: String? = null,
) : PoolAccess {
    val endpoint: String = endpoint ?: PoolEndpoint.resolve(filesDir)
    val install: String by lazy { install ?: PoolInstall.resolve(filesDir) }
    private val poolDir = File(filesDir, "translation-pool")
    private val headers get() = mapOf("User-Agent" to PoolEndpoint.userAgent(appVersion))

    @Volatile var config: PoolConfig = PoolConfig()
        private set
    @Volatile private var configAt: Long = Long.MIN_VALUE / 2
    @Volatile var language: String = "tr"
        set(v) { if (field != v) { field = v; generation++ } }
    @Volatile private var generation = 0
    /** Sunucunun son tanıdığı oyun ve zamanı (600 sn geçerli). */
    @Volatile private var serverGame: Pair<String, Long>? = null

    private val memories = HashMap<String, PoolTranslations>()
    private fun memory(lang: String): PoolTranslations = synchronized(memories) { memories.getOrPut(lang) { PoolTranslations(poolDir, lang) } }

    // ---- ağ ----

    private fun get(path: String, readMs: Int = 30_000): HttpResponse =
        http.send(HttpRequest(endpoint + path, headers = headers, connectTimeoutMs = 15_000, readTimeoutMs = readMs))

    private fun post(path: String, body: Any?, readMs: Int = 20_000): HttpResponse =
        http.send(HttpRequest.json(endpoint + path, Json.write(body), headers, 15_000, readMs))

    private suspend fun <T> io(block: () -> T): T = runInterruptible(Dispatchers.IO) { block() }

    // ---- 6.1 sunucu ayarı ----

    /** En çok 600 sn'de bir sorar. Engelleyici değil. */
    suspend fun refreshConfig(force: Boolean = false): PoolConfig {
        if (!force && now() - configAt < CONFIG_TTL_MS) return config
        val r = runCatching { io { get("/v1/config") } }.getOrNull()
        if (r != null && r.ok) runCatching { Json.parseObject(r.text) }.getOrNull()?.let { config = PoolConfig.parse(it); configAt = now() }
        return config
    }

    // ---- 6.5 havuz öncelikli oyun ----

    override fun isPoolFirst(game: String?, language: String): Boolean {
        if (endpoint.isBlank() || !config.translateEnabled) return false
        if (config.isPoolFirst(game, language)) return true
        val sg = serverGame ?: return false
        return now() - sg.second <= SERVER_GAME_TTL_MS && config.isPoolFirst(sg.first, language)
    }

    override val poolFirstDeadlineMs: Long get() = config.clampedPoolFirstDeadlineMs
    override val contextLines: Int get() = config.contextLines

    // ---- bellek ----

    override fun lookup(language: String, key: String): String? = if (!shareEnabled) null else memory(language).get(key)

    /** Havuz kapatılınca: bellek ve kuyruk silinir. */
    fun disable() {
        shareEnabled = false
        generation++
        synchronized(memories) { memories.values.forEach { it.clear() }; memories.clear() }
        queue?.clearAll()
    }

    // ---- 6.2 toplu indirme ----

    private val syncLock = Mutex()

    /** Bir oyunun (null: bütün oyunlar) çevirilerini indirir. Aynı anda tek indirme; en erken max(30, syncSeconds) sn'de bir. */
    suspend fun sync(gameName: String?, force: Boolean = false): Int {
        val game = GameIds.id(gameName)
        if (!shareEnabled || !config.translateEnabled) return 0
        if (syncLock.isLocked) return 0
        return syncLock.withLock {
            val lang = language
            val gen = generation
            val mem = memory(lang)
            val cursorKey = game ?: ALL_GAMES
            var c = mem.cursor(cursorKey)
            val minGap = maxOf(30, config.syncSeconds) * 1000.0
            if (!force && now() - c.checked * 1000 < minGap) return@withLock 0
            val got = ArrayList<Pair<String, String>>()
            var since = c.since; var after = c.after; var newest = c.since
            var ok = true
            for (page in 0 until MAX_PAGES) {
                val q = PoolEndpoint.query("lang" to lang, "since" to since.toString(), "game" to game, "after" to after)
                val r = runCatching { io { get("/v1/translations?$q") } }.getOrNull()
                if (r == null || !r.ok) { ok = false; break }
                val root = runCatching { Json.parseObject(r.text) }.getOrNull() ?: run { ok = false; null } ?: break
                for (item in root["items"] as? List<*> ?: emptyList<Any>()) {
                    val a = item as? List<*> ?: continue
                    if (a.size < 3) continue
                    val k = a[0] as? String ?: continue; val t = a[1] as? String ?: continue
                    got += k to t
                    (a[2] as? Number)?.toLong()?.let { if (it > newest) newest = it }
                }
                val next = root["next"] as? Map<*, *>
                if (next == null) { since = newest; after = null; break }
                since = (next["since"] as? Number)?.toLong() ?: since
                after = next["after"] as? String
            }
            // İndirme sürerken dil değiştiyse ya da havuz kapandıysa gelenler kullanılmaz.
            if (gen != generation || !shareEnabled || lang != language) return@withLock 0
            for ((k, t) in got) mem.put(k, t)
            c = PoolTranslations.Cursor(since, after, if (ok) now() / 1000.0 else c.checked)
            mem.setCursor(cursorKey, c)
            mem.save()
            got.size
        }
    }

    // ---- 6.3 anında çeviri ----

    private val inFlight = HashMap<String, Deferred<String?>>()

    override suspend fun ask(line: String, language: String, game: String?, context: List<String>, force: Boolean): String? {
        if (!config.translateEnabled || endpoint.isBlank()) return null
        if (!shareEnabled && !force) return null
        val clean = PoolLineFilter.clean(line)
        if (!PoolLineFilter.accepts(clean)) return null
        val key = PackKey.of(clean) ?: return null
        memory(language).get(key)?.let { return it }
        val id = "$language/$key"
        val mine = CompletableDeferred<String?>()
        val existing = synchronized(inFlight) { inFlight[id] ?: run { inFlight[id] = mine; null } }
        if (existing != null) return existing.await()
        try {
            val answer = askMany0(listOf(clean), language, game, context).firstOrNull()
            if (answer != null && (shareEnabled || force)) memory(language).put(key, answer)
            mine.complete(answer)
            return answer
        } catch (e: Throwable) {
            mine.complete(null); throw e
        } finally {
            synchronized(inFlight) { inFlight.remove(id) }
        }
    }

    /** Tek istek: `POST /v1/translate`. */
    private suspend fun askMany0(lines: List<String>, language: String, game: String?, context: List<String>): List<String?> {
        val body = translateBody(lines, language, game, context.takeLast(config.contextLines.coerceAtLeast(0)))
        val r = runCatching { io { post("/v1/translate", body) } }.getOrNull() ?: return lines.map { null }
        if (!r.ok) return lines.map { null }
        val root = runCatching { Json.parseObject(r.text) }.getOrNull() ?: return lines.map { null }
        (root["game"] as? String)?.let(GameIds::id)?.let { serverGame = it to now() }
        val list = root["translations"] as? List<*> ?: return lines.map { null }
        return lines.indices.map { i -> ((list.getOrNull(i) as? Map<*, *>)?.get("text") as? String)?.takeIf { it.isNotBlank() } }
    }

    fun translateBody(lines: List<String>, language: String, game: String?, context: List<String>): Map<String, Any?> = linkedMapOf(
        "v" to 1, "install" to install, "app" to appVersion, "platform" to "android", "lang" to language,
        "game" to GameIds.id(game), "lines" to lines, "context" to context,
    )

    // ---- 6.4 çok satırlı soru ----

    /**
     * Oyun içi telefon/harita kartı: bilinenler istek atmadan döner; en çok maxLines'lık parçalar paralel gider,
     * toplam en çok [totalMs] beklenir. Gelmeyenler null (cihaz içine düşer); geç gelenler belleğe yazılır.
     */
    suspend fun askMany(lines: List<String>, language: String, game: String?, context: List<String>, force: Boolean, totalMs: Long = 10_000): List<String?> {
        if (!config.translateEnabled || (!shareEnabled && !force)) return lines.map { null }
        val mem = memory(language)
        val result = arrayOfNulls<String>(lines.size)
        val ask = ArrayList<Pair<Int, String>>()
        for ((i, l) in lines.withIndex()) {
            val c = PoolLineFilter.clean(l)
            val k = PackKey.of(c)
            val known = k?.let(mem::get)
            if (known != null) result[i] = known else if (k != null && PoolLineFilter.accepts(c)) ask += i to c
        }
        if (ask.isEmpty()) return result.toList()
        val jobs = ask.chunked(config.clampedMaxLines).map { chunk ->
            scope.async {
                val got = askMany0(chunk.map { it.second }, language, game, context)
                for ((j, p) in chunk.withIndex()) got[j]?.let { t -> PackKey.of(p.second)?.let { mem.put(it, t) }; result[p.first] = t }
            }
        }
        withTimeoutOrNull(totalMs) { jobs.awaitAll() }
        return result.toList()
    }

    // ---- 6.6 kuyruğa öneri ----

    override fun offer(line: String, game: String?) {
        if (!shareEnabled) return
        queue?.offer(line, game)
    }

    // ---- 6.8 varlık ----

    suspend fun ping(game: String?): Boolean {
        if (!shareEnabled) return false
        val q = PoolEndpoint.query("install" to install, "platform" to "android", "app" to appVersion, "game" to (GameIds.id(game) ?: ""), "lang" to language)
        return runCatching { io { get("/v1/ping?$q") }.ok }.getOrDefault(false)
    }

    /** Toplam indirme sayısı (`/v1/config`'teki `downloads`); bilinmiyorsa null. */
    val downloads: Long? get() = config.downloads

    // ---- 6.7 oyunu ekrandan tanıma ----

    /** [jpegBase64] gri, en çok 768 px, kalite 60 JPEG (app'te hazırlanır; en çok 450 KiB). Tanınan oyun ya da null (sonraki isteklerde asıl kimliğe çevrilir). */
    suspend fun identify(jpegBase64: String): String? {
        if (!shareEnabled) return null
        val body = identifyBody(jpegBase64)
        val r = runCatching { io { post("/v1/identify", body, readMs = 30_000) } }.getOrNull() ?: return null
        if (!r.ok) return null
        return (runCatching { Json.parseObject(r.text) }.getOrNull()?.get("game") as? String)?.takeIf { it.isNotBlank() }
    }

    fun identifyBody(jpegBase64: String): Map<String, Any?> =
        linkedMapOf("v" to 1, "install" to install, "app" to appVersion, "platform" to "android", "image" to jpegBase64)

    companion object {
        const val CONFIG_TTL_MS = 600_000L
        const val SERVER_GAME_TTL_MS = 600_000L
        const val MAX_PAGES = 50
        const val ALL_GAMES = "*"
        const val MAX_IMAGE_BYTES = 450 * 1024
    }
}

/** Oyun tanıma zamanlaması (6.7): 8 sn sonra, olmazsa 60 sn'de bir en çok 6 deneme; tanınınca 5 dk sonra bir, sonra 20 dk'da bir en çok 12 doğrulama. */
class IdentifySchedule(private val startMs: Long) {
    var attempts = 0; private set
    var checks = 0; private set
    var identifiedAt: Long? = null; private set
    private var last = startMs

    /** Sıradaki deneme zamanı; artık yoksa null. */
    fun nextAt(): Long? {
        val id = identifiedAt
        return if (id == null) {
            if (attempts >= 6) null else if (attempts == 0) startMs + 8_000 else last + 60_000
        } else {
            if (checks >= 12) null else if (checks == 0) id + 5 * 60_000 else last + 20 * 60_000
        }
    }

    fun record(at: Long, game: String?) {
        last = at
        if (identifiedAt == null) { attempts++; if (game != null) identifiedAt = at } else checks++
    }
}
