// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import com.ninotranslator.core.json.Json
import com.ninotranslator.core.json.double
import com.ninotranslator.core.json.int
import com.ninotranslator.core.json.long
import com.ninotranslator.core.json.str
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

enum class HealthIssueKind(val wire: String) {
    PS5_DROPPED("ps5Dropped"), PS5_UNREACHABLE("ps5Unreachable"), NETWORK_LOST("networkLost"), TV_DROPPED("tvDropped");

    companion object {
        fun parse(s: String?) = entries.firstOrNull { it.wire == s }
    }
}

data class HealthIssue(
    val id: String = UUID.randomUUID().toString(),
    val dateMs: Long,
    val kind: HealthIssueKind,
    val network: String,
    val reason: String? = null,
    val streamedMinutes: Double? = null,
    val framesPerSecond: Double? = null,
    val game: String? = null,
)

/** `files/health/sorunlar.json`: son sorunlar, en çok 40, JSON dizisi. Tanınmayan `kind` atlanır. */
class HealthLog(private val file: File) {
    private val state: MutableStateFlow<List<HealthIssue>> by lazy { MutableStateFlow(parse(AtomicFiles.read(file))) }

    /** Dosyadaki sırayla (en eski başta). */
    val issues: StateFlow<List<HealthIssue>> get() = state.asStateFlow()

    /** En yenisi başta. */
    fun newestFirst(): List<HealthIssue> = state.value.sortedByDescending { it.dateMs }

    @Synchronized
    fun add(issue: HealthIssue) = save((state.value + issue).takeLast(MAX))

    @Synchronized
    fun clear() = save(emptyList())

    private fun save(list: List<HealthIssue>) {
        state.value = list
        AtomicFiles.write(file, encode(list))
    }

    companion object {
        const val PATH = "health/sorunlar.json"
        const val MAX = 40

        fun parse(text: String?): List<HealthIssue> {
            val arr = text?.let { runCatching { Json.parse(it) as? List<*> }.getOrNull() } ?: return emptyList()
            return arr.mapNotNull { item ->
                @Suppress("UNCHECKED_CAST")
                val m = item as? Map<String, Any?> ?: return@mapNotNull null
                val kind = HealthIssueKind.parse(m.str("kind")) ?: return@mapNotNull null
                HealthIssue(
                    id = m.str("id") ?: UUID.randomUUID().toString(),
                    dateMs = m.long("date") ?: 0L,
                    kind = kind,
                    network = m.str("network") ?: "",
                    reason = m.str("reason"),
                    streamedMinutes = m.double("streamedMinutes"),
                    framesPerSecond = m.double("framesPerSecond"),
                    game = m.str("game"),
                )
            }.takeLast(MAX)
        }

        fun encode(list: List<HealthIssue>): String = Json.write(list.map {
            linkedMapOf<String, Any?>("id" to it.id, "date" to it.dateMs, "kind" to it.kind.wire, "network" to it.network).apply {
                it.reason?.let { v -> put("reason", v) }
                it.streamedMinutes?.let { v -> put("streamedMinutes", v) }
                it.framesPerSecond?.let { v -> put("framesPerSecond", v) }
                it.game?.let { v -> put("game", v) }
            }
        })
    }
}

/** `files/health/otomatik-bildirim.json`: günlük otomatik bildirim sayacı (en çok 3) ve gönderilemeyen gövde. */
class AutoReportCounter(
    private val file: File,
    private val clock: () -> Long = System::currentTimeMillis,
    private val zone: () -> ZoneId = ZoneId::systemDefault,
) {
    data class State(val day: String, val sent: Int, val pending: String?)

    @Synchronized
    fun state(): State {
        val m = AtomicFiles.read(file)?.let { runCatching { Json.parseObject(it) }.getOrNull() }
        return State(m?.str("day") ?: "", m?.int("sent") ?: 0, m?.str("pending")?.takeIf { it.isNotEmpty() })
    }

    /** Bugün gönderilen (gün değiştiyse 0). */
    fun sentToday(): Int = state().let { if (it.day == today()) it.sent else 0 }

    fun canSendToday(): Boolean = sentToday() < MAX_PER_DAY

    @Synchronized
    fun recordSent() {
        val s = state()
        write(State(today(), sentToday() + 1, s.pending))
    }

    /** Gönderilemeyen bildirimin hazır JSON gövdesi; null siler. */
    @Synchronized
    fun setPending(body: String?) {
        val s = state()
        write(State(s.day.ifEmpty { today() }, s.sent, body))
    }

    val pending: String? get() = state().pending

    private fun write(s: State) = AtomicFiles.write(file, Json.write(linkedMapOf("day" to s.day, "sent" to s.sent, "pending" to (s.pending ?: ""))))

    private fun today(): String = DAY.withZone(zone()).format(Instant.ofEpochMilli(clock()))

    companion object {
        const val PATH = "health/otomatik-bildirim.json"
        const val MAX_PER_DAY = 3
        private val DAY: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd", Locale.ROOT)
    }
}
