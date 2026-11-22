// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.pool

import com.ninotranslator.core.packs.GameIds

/** `GET /v1/config` cevabı (ceviri.md 6.1). Eksik alanlarda varsayılanlar. */
data class PoolConfig(
    val translateEnabled: Boolean = true,
    val syncSeconds: Long = 180,
    val contextLines: Int = 4,
    val maxLines: Int = 12,
    val deadlineMs: Long = 900,
    val poolFirstGames: List<String> = DEFAULT_POOL_FIRST,
    val poolFirstDeadlineMs: Long = 1_500,
    val poolFirstLangs: List<String> = listOf("tr"),
    val downloads: Long? = null,
) {
    val clampedMaxLines: Int get() = maxLines.coerceIn(1, 12)
    val clampedPoolFirstDeadlineMs: Long get() = poolFirstDeadlineMs.coerceIn(100, 10_000)

    /**
     * Oyun kimliği listedeki parçalardan birini içeriyor ve dil listede mi. Liste eski adları da taşıyabilir
     * ("grand-theft-auto-vi"); iki taraf asıl kimliğe ([GameIds]) çevrilip de karşılaştırılır.
     */
    fun isPoolFirst(game: String?, language: String): Boolean {
        if (!translateEnabled || game.isNullOrBlank()) return false
        // NinoCore `isPoolFirstGame`: iki yan da asıl kimliğe çevrilir; kimliğin içinde geçmesi de sayılır.
        val c = GameIds.id(game) ?: return false
        if (poolFirstGames.none { e -> GameIds.id(e)?.let { k -> c.contains(k) || c.contains(e.lowercase()) } == true }) return false
        return "*" in poolFirstLangs || language in poolFirstLangs
    }

    companion object {
        val DEFAULT_POOL_FIRST = listOf("grand-theft-auto-vi", "gta-vi", "gta-6", "gta6")

        fun parse(root: Map<*, *>): PoolConfig {
            val d = PoolConfig()
            val t = root["translate"] as? Map<*, *>
            val p = root["poolFirst"] as? Map<*, *>
            fun num(m: Map<*, *>?, k: String) = (m?.get(k) as? Number)
            return PoolConfig(
                translateEnabled = t?.get("enabled") as? Boolean ?: d.translateEnabled,
                syncSeconds = num(t, "syncSeconds")?.toLong() ?: d.syncSeconds,
                contextLines = num(t, "contextLines")?.toInt() ?: d.contextLines,
                maxLines = num(t, "maxLines")?.toInt() ?: d.maxLines,
                deadlineMs = num(t, "deadlineMs")?.toLong() ?: d.deadlineMs,
                poolFirstGames = (p?.get("games") as? List<*>)?.filterIsInstance<String>() ?: d.poolFirstGames,
                poolFirstDeadlineMs = num(p, "deadlineMs")?.toLong() ?: d.poolFirstDeadlineMs,
                poolFirstLangs = (p?.get("langs") as? List<*>)?.filterIsInstance<String>() ?: d.poolFirstLangs,
                downloads = num(root, "downloads")?.toLong()?.takeIf { it > 0 },
            )
        }
    }
}
