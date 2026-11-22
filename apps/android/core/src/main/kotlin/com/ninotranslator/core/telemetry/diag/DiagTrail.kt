// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.telemetry.diag

import com.ninotranslator.core.telemetry.TelemetryCode
import com.ninotranslator.core.telemetry.TelemetryEvent.DiagStep

/**
 * Bekçinin iz tamponu: son [windowMs] (10 dk) içindeki en çok [capacity] (200) yapılandırılmış adım.
 * Her adım yalnız zaman, kod ve sayı?; metin, ad, adres yoktur (kod kurala uymuyorsa adım atılır).
 * Art arda aynı kod ve sayı tek adımda tutulur (zamanı en sonuncunun): sık gelen okuma adımları tamponu doldurmasın.
 */
class DiagTrail(private val capacity: Int = 200, private val windowMs: Long = 600_000) {
    data class Entry(val atMs: Long, val code: String, val value: Long?)

    private val ring = ArrayDeque<Entry>()

    val size: Int get() = ring.size
    val entries: List<Entry> get() = ring.toList()

    fun add(atMs: Long, code: String, value: Long? = null) {
        val c = TelemetryCode.clean(code) ?: return
        prune(atMs)
        val last = ring.lastOrNull()
        if (last != null && last.code == c && last.value == value && COLLAPSIBLE(c)) {
            ring.removeLast()
        }
        ring.addLast(Entry(atMs, c, value))
        while (ring.size > capacity) ring.removeFirst()
    }

    /** Bildirimde giden iz: [nowMs]'den önceki son [max] adım, `[−saniye, kod, sayı?]`. */
    fun snapshot(nowMs: Long, max: Int = 40): List<DiagStep> {
        prune(nowMs)
        return ring.filter { it.atMs <= nowMs }.takeLast(max).map {
            DiagStep(-Math.floorDiv(nowMs - it.atMs + 500, 1000L), it.code, it.value)
        }
    }

    fun clear() = ring.clear()

    private fun prune(nowMs: Long) {
        while (ring.isNotEmpty() && nowMs - ring.first().atMs > windowMs) ring.removeFirst()
    }

    private companion object {
        /** Tekrarı tek adımda tutulan kodlar (sayılar durumda ayrıca tutulur). */
        val COLLAPSIBLE: (String) -> Boolean = { it in setOf("ocr.empty", "ocr.text", "tr.ok", "tr.error", "ps5.frame", "ocr.slow", "tr.slow") }
    }
}
