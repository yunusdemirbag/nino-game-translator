// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import com.ninotranslator.core.json.Json
import com.ninotranslator.core.packs.GameIds
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Öğrenilen altyazı şeridi örneği (0–1 oranları). */
data class SubtitleBand(val top: Double, val bottom: Double)

/**
 * `files/subtitle-layout.json`: oyun anahtarı → `[[üst, alt], …]`, oyun başına en çok 60 örnek, en yenisi sonda.
 * Oyun anahtarı paketin asıl oyun kimliği ([GameIds.ofPack]: "pool-gta-6" → "gta-6"); bilinmiyorsa [GENERIC], havuz
 * öncelikli oyunda [GTA6]. Eski anahtarlar okunurken asıl kimlikte birleşir.
 */
class SubtitleLayoutStore(private val file: File) {
    private var cache: MutableMap<String, List<SubtitleBand>>? = null

    @Synchronized
    fun all(): Map<String, List<SubtitleBand>> = load().toMap()

    @Synchronized
    fun samples(game: String): List<SubtitleBand> = load()[key(game)].orEmpty()

    @Synchronized
    fun record(game: String, band: SubtitleBand) {
        val m = load()
        val k = key(game)
        m[k] = (m[k].orEmpty() + band).takeLast(MAX_PER_GAME)
        AtomicFiles.write(file, encode(m))
    }

    @Synchronized
    fun clear(game: String? = null) {
        val m = load()
        if (game == null) m.clear() else m.remove(key(game))
        AtomicFiles.write(file, encode(m))
    }

    private fun load(): MutableMap<String, List<SubtitleBand>> =
        cache ?: LinkedHashMap(parse(AtomicFiles.read(file))).also { cache = it }

    companion object {
        const val FILE = "subtitle-layout.json"
        const val MAX_PER_GAME = 60
        const val GENERIC = "genel"
        const val GTA6 = "gta-6"

        /** Anahtarın asıl hâli ("pool-gta-6", "grand-theft-auto-vi" → "gta-6"). */
        fun key(game: String): String = GameIds.ofPack(game).ifEmpty { game }

        fun parse(text: String?): Map<String, List<SubtitleBand>> {
            val root = text?.let { runCatching { Json.parseObject(it) }.getOrNull() } ?: return emptyMap()
            val out = LinkedHashMap<String, List<SubtitleBand>>()
            for ((game, v) in root) {
                val bands = (v as? List<*>)?.mapNotNull { pair ->
                    val p = pair as? List<*> ?: return@mapNotNull null
                    val top = (p.getOrNull(0) as? Number)?.toDouble() ?: return@mapNotNull null
                    val bottom = (p.getOrNull(1) as? Number)?.toDouble() ?: return@mapNotNull null
                    SubtitleBand(top, bottom)
                } ?: continue
                // Aynı oyunun eski anahtarları tek anahtarda: önce okunanlar başta, en çok 60.
                val k = key(game.toString())
                out[k] = (out[k].orEmpty() + bands).takeLast(MAX_PER_GAME)
            }
            return out
        }

        fun encode(m: Map<String, List<SubtitleBand>>): String =
            Json.write(m.mapValues { (_, list) -> list.map { listOf(it.top, it.bottom) } })
    }
}

/** `files/tvinstall.log`: düz metin, her satır `yyyy-MM-dd HH:mm:ss <ileti>`; 512 KB'ı geçince silinip baştan başlar. */
class TvInstallLog(
    private val file: File,
    private val clock: () -> Long = System::currentTimeMillis,
    private val zone: () -> ZoneId = ZoneId::systemDefault,
) {
    @Synchronized
    fun append(message: String) {
        try {
            file.parentFile?.mkdirs()
            if (file.length() > MAX_BYTES) file.delete()
            val stamp = STAMP.withZone(zone()).format(Instant.ofEpochMilli(clock()))
            file.appendText("$stamp ${message.replace('\n', ' ')}\n", Charsets.UTF_8)
        } catch (_: Exception) {
            // Günlük yazılamazsa kurulum sürer.
        }
    }

    fun read(): String = AtomicFiles.read(file).orEmpty()

    @Synchronized
    fun clear() { file.delete() }

    companion object {
        const val FILE = "tvinstall.log"
        const val MAX_BYTES = 512L * 1024
        private val STAMP: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss", Locale.ROOT)
    }
}
