// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.telemetry.diag

import com.ninotranslator.core.json.Json
import java.io.File
import java.util.TimeZone

/**
 * Teşhis bildirimlerinin günlük sınırı (tarif): kurulum başına günde en çok [perDay] (5), aynı kural günde en çok
 * [perRule] (2). Gün yerel saate göre döner. [file] verilirse sayaçlar diskte durur (uygulama yeniden açılınca da geçerli).
 */
class DiagBudget(
    private val file: File? = null,
    private val perDay: Int = 5,
    private val perRule: Int = 2,
    private val zoneOffsetMs: (Long) -> Int = { TimeZone.getDefault().getOffset(it) },
) {
    private val lock = Any()
    private var day = Long.MIN_VALUE
    private var total = 0
    private val rules = HashMap<String, Int>()

    init { load() }

    /** Sınır izin veriyorsa sayar ve true döner. */
    fun take(rule: String, nowMs: Long): Boolean = synchronized(lock) {
        roll(nowMs)
        if (total >= perDay || (rules[rule] ?: 0) >= perRule) return false
        total++
        rules[rule] = (rules[rule] ?: 0) + 1
        save()
        true
    }

    private fun roll(nowMs: Long) {
        val d = Math.floorDiv(nowMs + zoneOffsetMs(nowMs), 86_400_000L)
        if (d != day) { day = d; total = 0; rules.clear() }
    }

    private fun save() {
        val f = file ?: return
        runCatching {
            f.parentFile?.mkdirs()
            f.writeText(Json.write(linkedMapOf("day" to day, "total" to total.toLong(), "rules" to rules.mapValues { it.value.toLong() })))
        }
    }

    private fun load() {
        val f = file ?: return
        val m = runCatching { Json.parseObject(f.readText()) }.getOrNull() ?: return
        day = (m["day"] as? Number)?.toLong() ?: return
        total = (m["total"] as? Number)?.toInt() ?: 0
        (m["rules"] as? Map<*, *>)?.forEach { (k, v) -> if (k is String && v is Number) rules[k] = v.toInt() }
    }
}
