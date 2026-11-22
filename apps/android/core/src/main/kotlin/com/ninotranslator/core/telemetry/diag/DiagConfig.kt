// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.telemetry.diag

/**
 * Sunucunun teşhis ayarı (`/v1/config` → `telemetry.diag`): `{ "off": ["ocr.silent"], "limits": { "tr.slow.p90Ms": 4000 } }`.
 * Eşik adı `kural.ad` biçimindedir ([Limit]); tarifteki düz ad (`trSlowP90Ms`) da kabul edilir. Bilinmeyen anahtar yok sayılır.
 */
data class DiagConfig(val off: Set<String> = emptySet(), val limits: Map<String, Double> = emptyMap()) {
    fun isOff(rule: String) = rule in off

    fun limit(l: Limit): Double = limits[l.key] ?: limits[l.alias] ?: l.default

    fun toWire(): Map<String, Any?> = linkedMapOf("off" to off.sorted(), "limits" to limits.toSortedMap())

    /** Varsayılan eşikler (tarif). */
    enum class Limit(val key: String, val alias: String, val default: Double) {
        PS5_NO_RETURN_SEC("ps5.no_return.sec", "ps5NoReturnSec", 180.0),
        TV_FLAP_WINDOW_MIN("tv.flapping.windowMin", "tvFlapWindowMin", 10.0),
        TV_FLAP_COUNT("tv.flapping.count", "tvFlapCount", 3.0),
        OCR_SILENT_MIN("ocr.silent.min", "ocrSilentMin", 15.0),
        OCR_STALL_SEC("ocr.stalled.sec", "ocrStallSec", 10.0),
        FRAMES_STALL_SEC("ocr.stalled.framesSec", "framesStallSec", 30.0),
        TR_SLOW_P90_MS("tr.slow.p90Ms", "trSlowP90Ms", 3000.0),
        TR_ERROR_RATE("tr.errors.rate", "trErrorRate", 0.30),
        HANG_SEC("app.hang.sec", "hangSec", 5.0),
        MEM_HIGH_MB("app.resources.memMB", "memHighMB", 800.0),
        CPU_HIGH_PCT("app.resources.cpu", "cpuHighPct", 90.0),
        PACK_ATTEMPTS("pack.download.attempts", "packAttempts", 3.0),
    }

    companion object {
        private val RULE = Regex("^[a-z0-9_.]{1,40}$")
        private val NAME = Regex("^[A-Za-z0-9_.]{1,64}$")

        fun parse(m: Map<*, *>?): DiagConfig {
            if (m == null) return DiagConfig()
            val off = (m["off"] as? List<*>)?.mapNotNull { (it as? String)?.takeIf(RULE::matches) }?.toSet().orEmpty()
            val limits = (m["limits"] as? Map<*, *>)?.entries?.mapNotNull { (k, v) ->
                val key = (k as? String)?.takeIf(NAME::matches) ?: return@mapNotNull null
                val d = (v as? Number)?.toDouble()?.takeIf { it.isFinite() && it >= 0 } ?: return@mapNotNull null
                key to d
            }?.toMap().orEmpty()
            return DiagConfig(off, limits)
        }
    }
}
