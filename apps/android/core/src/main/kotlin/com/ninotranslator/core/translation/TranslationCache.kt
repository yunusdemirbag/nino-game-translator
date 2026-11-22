// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import com.ninotranslator.core.json.Json
import com.ninotranslator.core.json.long
import com.ninotranslator.core.json.str
import java.io.File
import java.time.Instant

/** Diskte tutulan çeviri önbelleği; sınır aşılınca en eski kullanılan silinir. İş parçacığı güvenlidir. */
class TranslationCache(private val file: File? = null, capacity: Int = 50_000) {
    data class Entry(val key: String, val source: String, val text: String, val origin: String, val date: String, var lastUse: Long)

    val capacity = maxOf(1, capacity)
    private val entries = HashMap<String, Entry>()
    private var tick = 0L
    private var dirty = false

    init {
        val f = file
        if (f != null && f.isFile) runCatching {
            @Suppress("UNCHECKED_CAST")
            val list = Json.parse(f.readText()) as List<Map<String, Any?>>
            for (m in list) {
                val e = Entry(m.str("key") ?: continue, m.str("source") ?: "", m.str("text") ?: continue,
                    m.str("origin") ?: "", m.str("date") ?: "", m.long("lastUse") ?: 0)
                entries[e.key] = e
                tick = maxOf(tick, e.lastUse)
            }
        }
    }

    @get:Synchronized val count: Int get() = entries.size

    @Synchronized fun lookup(source: String): String? {
        val e = entries[TranslationKey.make(source)] ?: return null
        e.lastUse = ++tick
        dirty = true
        return e.text
    }

    @Synchronized fun store(source: String, text: String, origin: String, date: Instant = Instant.now()) {
        val key = TranslationKey.make(source)
        entries[key] = Entry(key, source, text, origin, date.toString(), ++tick)
        dirty = true
        if (entries.size > capacity) {
            entries.values.sortedBy { it.lastUse }.take(entries.size - capacity).forEach { entries.remove(it.key) }
        }
    }

    @Synchronized fun removeAll() { entries.clear(); dirty = true }

    /** Değişiklik varsa diske atomik yazar. */
    @Synchronized fun save() {
        val f = file ?: return
        if (!dirty) return
        f.parentFile?.mkdirs()
        val list = entries.values.sortedBy { it.lastUse }.map {
            linkedMapOf("date" to it.date, "key" to it.key, "lastUse" to it.lastUse, "origin" to it.origin, "source" to it.source, "text" to it.text)
        }
        val tmp = File(f.parentFile, f.name + ".tmp")
        tmp.writeText(Json.write(list))
        if (!tmp.renameTo(f)) { f.delete(); tmp.renameTo(f) }
        dirty = false
    }
}
