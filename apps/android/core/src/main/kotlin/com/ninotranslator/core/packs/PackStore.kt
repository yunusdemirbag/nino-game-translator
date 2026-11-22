// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.packs

import com.ninotranslator.core.http.HttpRequest
import com.ninotranslator.core.http.HttpTransport
import com.ninotranslator.core.json.Json
import com.ninotranslator.core.json.list
import com.ninotranslator.core.json.long
import com.ninotranslator.core.json.str
import java.io.File
import java.io.InputStream
import java.security.MessageDigest

/** Dosyadan ya da akıştan okunan bir paket kaynağı. [name] dosya adı, ör. `pool-oyun.json.gz`. */
class PackSource(val name: String, val open: () -> InputStream) {
    val id: String get() = packIdOf(name)

    companion object {
        fun directory(dir: File): List<PackSource> = dir.listFiles().orEmpty()
            .filter { it.isFile && (it.name.endsWith(".json.gz") || it.name.endsWith(".json")) && !it.name.startsWith(".") }
            .sortedBy { it.name }
            .map { f -> PackSource(f.name) { f.inputStream() } }
    }
}

/** Dosya adından paket kimliği (`.json`/`.gz` atılır); kapatılan paket listesi bu kimliği kullanır. */
fun packIdOf(fileName: String): String = fileName.removeSuffix(".gz").removeSuffix(".json")

/**
 * Paket deposu (ceviri.md 9.2, 10): `packs-remote/` (havuzdan inenler) + `packs-imported/`, kapalı paketler,
 * `packs.state`, SHA-256 doğrulama ve havuzdan indirme/güncelleme. Uygulamayla paket gelmez; [embedded] yalnız
 * dışarıdan verilen ek kaynaklar içindir (testler). Hiç paket yoksa kütüphane boştur, çeviri paketsiz sürer.
 *
 * Havuz: `GET <adres>/v1/packs?lang=<dil>` liste, `GET <adres>/v1/packs/<id>?lang=<dil>` gzip'li paket
 * (ETag = `"<sha256>"`, `If-None-Match` → 304).
 */
class PackStore(
    filesDir: File,
    private val embedded: List<PackSource>,
    private val http: HttpTransport,
    /** Havuz adresi (`PoolEndpoint`); boşsa indirme kapalı. */
    private val baseUrl: String?,
    private val now: () -> Long = System::currentTimeMillis,
    /** Paket dili; paketler şimdilik yalnız Türkçe. `packs.state` tek dillidir. */
    private val lang: String = "tr",
    /** Havuzun beklediği tanıtım başlığı (`PoolEndpoint.userAgent`). */
    private val userAgent: String? = null,
) {
    val remoteDir = File(filesDir, "packs-remote")
    val importedDir = File(filesDir, "packs-imported")
    private val stateFile = File(remoteDir, "packs.state")

    data class RemotePack(val id: String, val title: String, val version: Long, val sha256: String)
    data class State(val checked: Long, val packs: List<RemotePack>)
    data class ServerPack(val id: String, val title: String, val version: Long, val sha256: String, val size: Long, val entries: Long)
    data class LoadFailure(val name: String, val reason: String)

    /** Son bakışta sunucunun listesi (paket ekranı inmemişleri de gösterir). */
    @Volatile var serverPacks: List<ServerPack> = emptyList()
        private set
    @Volatile var lastFailures: List<LoadFailure> = emptyList()
        private set

    val downloadEnabled: Boolean get() = !baseUrl.isNullOrBlank()

    // ---- durum dosyası ----

    fun readState(): State {
        val m = runCatching { Json.parseObject(stateFile.readText()) }.getOrNull() ?: return State(0, emptyList())
        val list = m.list("packs").orEmpty().mapNotNull { item ->
            @Suppress("UNCHECKED_CAST") val p = item as? Map<String, Any?> ?: return@mapNotNull null
            val id = p.str("id") ?: return@mapNotNull null
            RemotePack(id, p.str("title") ?: id, p.long("version") ?: 0, (p.str("sha256") ?: "").lowercase())
        }
        return State(m.long("checked") ?: 0, list)
    }

    private fun writeState(state: State) {
        remoteDir.mkdirs()
        val json = Json.write(linkedMapOf(
            "checked" to state.checked,
            "packs" to state.packs.map { linkedMapOf("id" to it.id, "title" to it.title, "version" to it.version, "sha256" to it.sha256) },
        ))
        atomicWrite(stateFile, json.toByteArray(Charsets.UTF_8))
    }

    // ---- yükleme ----

    /** Kapalı olmayan bütün paketleri yükler. Bozuk ya da bellek yetmeyen paket atlanır. */
    fun loadLibrary(disabled: Set<String> = emptySet()): LegacyPackLibrary {
        val out = ArrayList<LegacyPack>()
        val failures = ArrayList<LoadFailure>()
        fun attempt(name: String, open: () -> InputStream) {
            if (packIdOf(name) in disabled) return
            try { open().use { out += LegacyPack.load(it, packIdOf(name)) } }
            catch (e: OutOfMemoryError) { failures += LoadFailure(name, "bellek yetmedi") }
            catch (e: Exception) { failures += LoadFailure(name, e.message ?: e.javaClass.simpleName) }
        }
        for (s in embedded.sortedBy { it.name }) attempt(s.name, s.open)
        for (p in readState().packs) {
            val f = remoteFile(p.id) ?: continue
            if (!f.isFile) continue
            if (sha256(f) != p.sha256) { failures += LoadFailure(f.name, "SHA-256 tutmuyor"); continue }
            attempt(f.name) { f.inputStream() }
        }
        importedDir.listFiles().orEmpty().filter { it.isFile && it.name.endsWith(".json") && !it.name.startsWith(".") }
            .sortedBy { it.name }.forEach { f -> attempt(f.name) { f.inputStream() } }
        lastFailures = failures
        return LegacyPackLibrary(out)
    }

    private fun remoteFile(id: String): File? = if (isSafeId(id)) File(remoteDir, "$id.json.gz") else null

    // ---- indirme ----

    enum class Reason { APP_START, DAILY, NEW_GAME }

    /** Bakma zamanı geldi mi: açılışta hemen; 24 saatte bir; yeni oyunda son bakış 10 dk'dan eskiyse. */
    fun isDue(reason: Reason): Boolean {
        if (!downloadEnabled) return false
        val age = now() - readState().checked
        return when (reason) {
            Reason.APP_START -> true
            Reason.DAILY -> age >= DAY_MS
            Reason.NEW_GAME -> age >= 10 * 60_000L
        }
    }

    data class RefreshResult(val ok: Boolean, val changed: Boolean, val downloaded: List<String>, val removed: List<String>, val failed: List<String>)

    /** Sunucudaki listeyle eşitler. Engelleyici. Değişiklik varsa çalışan çeviri paketleri yeniden okumalı. */
    fun refresh(): RefreshResult {
        val base = baseUrl?.trimEnd('/') ?: return RefreshResult(false, false, emptyList(), emptyList(), emptyList())
        val list = try { fetchList(base) } catch (e: Exception) { null }
            ?: return RefreshResult(false, false, emptyList(), emptyList(), emptyList())
        serverPacks = list
        val old = readState()
        val oldById = old.packs.associateBy { it.id }
        val next = ArrayList<RemotePack>()
        val downloaded = ArrayList<String>(); val failed = ArrayList<String>(); val removed = ArrayList<String>()
        remoteDir.mkdirs()
        for (sp in list) {
            val file = remoteFile(sp.id) ?: continue
            val prev = oldById[sp.id]
            val localSha = if (prev != null && file.isFile) sha256(file) else null
            // İçerik aynıysa (sha tutuyor) indirilmez; havuzda sürüm yalnız içerik değişince değişir.
            if (prev != null && localSha != null && prev.sha256 == sp.sha256 && localSha == sp.sha256) {
                next += prev.copy(title = sp.title, version = sp.version); continue
            }
            val got = download(base, sp, file, localSha?.takeIf { it == prev?.sha256 })
            if (got == Download.NOT_MODIFIED) {
                // Sunucu "değişmedi" dedi: elimizdeki doğrulanmış dosya kalır.
                next += RemotePack(sp.id, sp.title, sp.version, localSha!!)
            } else if (got == Download.OK) {
                next += RemotePack(sp.id, sp.title, sp.version, sp.sha256); downloaded += sp.id
            } else {
                failed += sp.id
                // Eski sürüm kalır; sonraki bakışta yeniden denensin diye sürüm −1.
                if (prev != null && file.isFile) next += prev.copy(version = -1)
            }
        }
        val serverIds = list.map { it.id }.toSet()
        for (p in old.packs) {
            if (p.id in serverIds) continue
            // Havuz yalnız `pool-*` paketlerini listeler; eski paket sunucusundan inmiş paketler silinmez, okunmaya
            // devam eder (onları kaldırmak ayrı bir karar).
            if (!p.id.startsWith(POOL_PREFIX)) { next += p; continue }
            remoteFile(p.id)?.delete(); removed += p.id
        }
        writeState(State(if (failed.isEmpty()) now() else old.checked, next))
        return RefreshResult(true, downloaded.isNotEmpty() || removed.isNotEmpty(), downloaded, removed, failed)
    }

    private fun fetchList(base: String): List<ServerPack>? {
        val r = http.send(HttpRequest("$base/v1/packs?lang=${enc(lang)}", headers = headers(), connectTimeoutMs = 15_000, readTimeoutMs = 60_000))
        if (!r.ok) return null
        val root = runCatching { Json.parseObject(r.text) }.getOrNull() ?: return null
        val raw = root["packs"] as? List<*> ?: return null // eksik/null liste hata (boş sayılırsa inmiş paketler silinirdi)
        val out = ArrayList<ServerPack>()
        for (item in raw) {
            @Suppress("UNCHECKED_CAST") val p = item as? Map<String, Any?> ?: return null
            val id = p.str("id")?.takeIf(::isSafeId) ?: return null
            // Başka dilin paketi bu listeye girmez (havuz zaten süzer; yine de).
            if (p.str("lang")?.let { !it.equals(lang, ignoreCase = true) } == true) continue
            out += ServerPack(id, p.str("title") ?: id, p.long("version") ?: 0, (p.str("sha256") ?: return null).lowercase(), p.long("size") ?: 0, p.long("entries") ?: 0)
        }
        return out
    }

    private enum class Download { OK, NOT_MODIFIED, FAILED }

    /** [localSha] elimizdeki doğrulanmış dosyanın sha'sı; varsa `If-None-Match` ile sorulur. */
    private fun download(base: String, sp: ServerPack, target: File, localSha: String?): Download {
        val tmp = File(remoteDir, "${sp.id}.download")
        return try {
            val h = headers().toMutableMap()
            if (localSha != null) h["If-None-Match"] = "\"$localSha\""
            val r = http.send(HttpRequest("$base/v1/packs/${enc(sp.id)}?lang=${enc(lang)}", headers = h, connectTimeoutMs = 15_000, readTimeoutMs = 60_000))
            if (r.status == 304) return if (localSha != null) Download.NOT_MODIFIED else Download.FAILED
            if (!r.ok || r.body.isEmpty()) return Download.FAILED
            val sha = sha256(r.body)
            if (sha != sp.sha256) return Download.FAILED
            r.header("x-pack-sha256")?.let { if (!it.equals(sha, ignoreCase = true)) return Download.FAILED }
            tmp.writeBytes(r.body)
            moveReplacing(tmp, target)
            Download.OK
        } catch (e: Exception) {
            Download.FAILED
        } finally { tmp.delete() }
    }

    private fun headers(): Map<String, String> = userAgent?.let { mapOf("User-Agent" to it) } ?: emptyMap()

    private fun enc(s: String) = java.net.URLEncoder.encode(s, "UTF-8")

    /** "İndirilen paketleri sil". */
    fun deleteDownloaded() {
        remoteDir.listFiles().orEmpty().forEach { it.delete() }
    }

    companion object {
        const val DAY_MS = 24 * 60 * 60_000L
        /** Havuzun ürettiği paket kimliklerinin öneki. */
        const val POOL_PREFIX = "pool-"

        fun isSafeId(id: String) = id.isNotEmpty() && id.length <= 120 && !id.startsWith(".") && id.all { it.isLetterOrDigit() && it.code < 128 || it == '-' || it == '_' || it == '.' }

        fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(java.util.Locale.ROOT, it) }

        fun sha256(file: File): String? = runCatching {
            val md = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { s -> val b = ByteArray(65_536); while (true) { val n = s.read(b); if (n < 0) break; md.update(b, 0, n) } }
            md.digest().joinToString("") { "%02x".format(java.util.Locale.ROOT, it) }
        }.getOrNull()

        internal fun atomicWrite(file: File, bytes: ByteArray) {
            file.parentFile?.mkdirs()
            val tmp = File(file.parentFile, file.name + ".tmp")
            tmp.writeBytes(bytes)
            moveReplacing(tmp, file)
        }

        internal fun moveReplacing(from: File, to: File) {
            java.nio.file.Files.move(from.toPath(), to.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING, java.nio.file.StandardCopyOption.ATOMIC_MOVE)
        }
    }
}
