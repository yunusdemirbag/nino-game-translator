// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import com.ninotranslator.core.json.Json
import com.ninotranslator.core.json.list
import com.ninotranslator.core.json.str
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

enum class HistoryOrigin(val wire: String) {
    PACK("pack"), ENGINE("engine");

    companion object {
        /** `pack` dışındaki her değer `engine`. */
        fun parse(s: String?) = if (s == PACK.wire) PACK else ENGINE
    }
}

/** Geçmiş öğesi. [dateMs] saniye hassasiyetinde Unix ms. */
data class HistoryEntry(val id: Int, val dateMs: Long, val source: String, val translation: String, val origin: HistoryOrigin)

/**
 * `files/history.json` (§3.1): `{"version":1,"entries":[…]}`, en yenisi başta, en çok 200 öğe, metinler en çok 500
 * karakter. Mac/iPhone/Windows ile aynı biçim. Bozuk dosya = boş geçmiş. Yazma çağıran iş parçacığında yapılır.
 */
class HistoryStore(private val file: File, private val clock: () -> Long = System::currentTimeMillis) {
    private val state: MutableStateFlow<List<HistoryEntry>> by lazy { MutableStateFlow(parse(AtomicFiles.read(file))) }

    val entries: StateFlow<List<HistoryEntry>> get() = state.asStateFlow()

    @Synchronized
    fun add(source: String, translation: String, origin: HistoryOrigin): HistoryEntry {
        val old = state.value
        val entry = HistoryEntry(
            id = (old.maxOfOrNull { it.id } ?: 0) + 1,
            dateMs = clock() / 1000 * 1000,
            source = source.take(MAX_TEXT),
            translation = translation.take(MAX_TEXT),
            origin = origin,
        )
        save((listOf(entry) + old).take(MAX_ENTRIES))
        return entry
    }

    @Synchronized
    fun remove(id: Int) = save(state.value.filterNot { it.id == id })

    @Synchronized
    fun clear() = save(emptyList())

    private fun save(list: List<HistoryEntry>) {
        state.value = list
        AtomicFiles.write(file, encode(list))
    }

    companion object {
        const val FILE = "history.json"
        const val MAX_ENTRIES = 200
        const val MAX_TEXT = 500

        private val DATE: DateTimeFormatter = DateTimeFormatter.ISO_INSTANT

        fun formatDate(ms: Long): String = DATE.format(Instant.ofEpochMilli(ms).truncatedTo(ChronoUnit.SECONDS))

        fun parse(text: String?): List<HistoryEntry> {
            if (text.isNullOrBlank()) return emptyList()
            val root = runCatching { Json.parseObject(text) }.getOrNull() ?: return emptyList()
            val items = root.list("entries") ?: return emptyList()
            return items.asSequence().mapNotNull { item ->
                @Suppress("UNCHECKED_CAST")
                val m = item as? Map<String, Any?> ?: return@mapNotNull null
                val id = (m["id"] as? Number)?.toInt() ?: return@mapNotNull null
                val source = m.str("source") ?: return@mapNotNull null
                val translation = m.str("translation") ?: return@mapNotNull null
                val date = m.str("date")?.let { runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() } ?: 0L
                HistoryEntry(id, date, source.take(MAX_TEXT), translation.take(MAX_TEXT), HistoryOrigin.parse(m.str("origin")))
            }.take(MAX_ENTRIES).toList()
        }

        fun encode(list: List<HistoryEntry>): String = Json.write(linkedMapOf(
            "version" to 1,
            "entries" to list.take(MAX_ENTRIES).map {
                linkedMapOf("id" to it.id, "date" to formatDate(it.dateMs), "source" to it.source,
                    "translation" to it.translation, "origin" to it.origin.wire)
            },
        ))
    }
}
