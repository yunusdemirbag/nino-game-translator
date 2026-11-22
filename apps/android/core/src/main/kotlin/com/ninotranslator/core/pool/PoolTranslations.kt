// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.pool

import com.ninotranslator.core.json.Json
import com.ninotranslator.core.packs.GameIds
import java.io.File

/**
 * Havuzdan telefona inmiş çeviriler, dil başına (ceviri.md 6.2):
 * `translation-pool/translations-<dil>.json` = `{"language", "texts": {anahtar: çeviri}, "cursors": {oyun: {since, after, checked}}}`.
 */
class PoolTranslations(private val dir: File, val language: String) {
    data class Cursor(val since: Long = 0, val after: String? = null, val checked: Double = 0.0)

    private val texts = LinkedHashMap<String, String>()
    private val cursors = HashMap<String, Cursor>()
    private val file: File get() = File(dir, "translations-$language.json")

    init { load() }

    @get:Synchronized val size: Int get() = texts.size
    @Synchronized fun get(key: String): String? = texts[key]
    @Synchronized fun put(key: String, text: String) { texts.remove(key); texts[key] = text }
    @Synchronized fun cursor(game: String): Cursor = cursors[game] ?: Cursor()
    @Synchronized fun setCursor(game: String, c: Cursor) { cursors[game] = c }
    @Synchronized fun clear() { texts.clear(); cursors.clear(); file.delete() }

    private fun load() {
        val root = runCatching { Json.parseObject(file.readText()) }.getOrNull() ?: return
        (root["texts"] as? Map<*, *>)?.forEach { (k, v) -> if (k is String && v is String) texts[k] = v }
        (root["cursors"] as? Map<*, *>)?.forEach { (k, v) ->
            val m = v as? Map<*, *> ?: return@forEach
            if (k !is String) return@forEach
            val c = Cursor((m["since"] as? Number)?.toLong() ?: 0, m["after"] as? String, (m["checked"] as? Number)?.toDouble() ?: 0.0)
            // Eski anahtar ("Grand Theft Auto VI") asıl kimlikle; çakışırsa daha ilerideki imleç kalır.
            val g = if (k == SharedPool.ALL_GAMES) k else GameIds.id(k) ?: k
            if ((cursors[g]?.since ?: Long.MIN_VALUE) < c.since) cursors[g] = c
        }
    }

    /** Dil başına en çok [MAX] çeviri yazılır (en yeniler). Geçici dosyadan yerine konur. */
    @Synchronized fun save() {
        val keep = if (texts.size > MAX) texts.entries.toList().takeLast(MAX).associate { it.key to it.value } else texts
        val json = Json.write(linkedMapOf(
            "language" to language,
            "texts" to keep,
            "cursors" to cursors.mapValues { (_, c) -> linkedMapOf("since" to c.since, "after" to c.after, "checked" to c.checked) },
        ))
        runCatching {
            dir.mkdirs()
            val tmp = File(dir, file.name + ".tmp")
            tmp.writeText(json)
            java.nio.file.Files.move(tmp.toPath(), file.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING, java.nio.file.StandardCopyOption.ATOMIC_MOVE)
        }
    }

    companion object { const val MAX = 400_000 }
}
