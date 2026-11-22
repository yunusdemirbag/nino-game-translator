// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import com.ninotranslator.core.packs.LegacyPackLibrary
import com.ninotranslator.core.packs.PackKey
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.launch

/** Ortak havuz erişimi (çeviri sırasının gördüğü kadarı; gerçeği `core.pool.SharedPool`). */
interface PoolAccess {
    /** Telefona inmiş havuz çevirisi (havuz kapalıysa boş). */
    fun lookup(language: String, key: String): String?
    /** Havuz öncelikli oyun mu (sunucu kapalıysa/adres yoksa hayır). */
    fun isPoolFirst(game: String?, language: String): Boolean
    /** Havuz öncelikli oyunda bekleme süresi (100-10.000 ms). */
    val poolFirstDeadlineMs: Long
    /** Sunucuya anında sor; yoksa/hata null. [force] havuz kapalıyken de sorar (havuz öncelikli oyun). */
    suspend fun ask(line: String, language: String, game: String?, context: List<String>, force: Boolean): String?
    /** Pakette bulunmayan satırı gönderme kuyruğuna önerir. */
    fun offer(line: String, game: String?)
    /** Sunucunun anında çeviri bağlam sayısı. */
    val contextLines: Int
}

/** Bir satırın çeviri ayarları (çeviri sürerken anında değişebilir). */
data class TranslationSettings(
    val target: TargetLanguage = TargetLanguage.TR,
    val packsEnabled: Boolean = true,
    val sharePool: Boolean = true,
    val showSpeakerNames: Boolean = true,
    /** Elle seçilen oyun (ad ya da paket kimliği). */
    val manualGame: String? = null,
    /** Bilinen oyun kimliği (PS5'ten, paketten ya da sunucudan). */
    val game: String? = null,
    /** Deneme görüntüsünden okunan satır (havuza gönderilmez). */
    val fromClip: Boolean = false,
    /**
     * Altyazı dışı yazı (ek alan, ekranı çevir): ortak havuza önerilmez, altyazının bağlam listesine yazılmaz.
     */
    val sideText: Boolean = false,
)

data class LineResult(val source: String, val text: String, val origin: Origin, val engine: String? = null) {
    enum class Origin { SAME_LANGUAGE, PACK, POOL, ONLINE, ON_DEVICE }
}

/**
 * Bir altyazı satırının çeviri sırası (ceviri.md 1): hedef dilde mi → paket → havuz belleği → havuz öncelikli oyun →
 * seçili çevirmen (+ cihaz içi yedek) → paket/havuz yeniden bakış → arka planda havuz yükseltmesi.
 * Cihaz içi çevirmen de hata verirse null döner (satır gösterilmez; okuma hattı yeniden dener).
 */
class LineTranslator(
    @Volatile var packs: LegacyPackLibrary?,
    private val pool: PoolAccess?,
    private val onDevice: OnDeviceLineTranslator,
    /** Seçili anahtarlı çevirmen (yoksa null: yalnız cihaz içi). */
    @Volatile var online: OnlineLineTranslator?,
    private val recent: RecentLines,
    /** Yükseltme gibi arka plan işleri; SupervisorJob'lu olmalı. [translate] ana iş parçacığında çağrılmamalı. */
    private val scope: CoroutineScope,
    /** Sonradan gelen havuz çevirisi: satır hâlâ ekrandaysa yerine konmalı. */
    var onUpgrade: (LineResult) -> Unit = {},
) {
    /** Son çevirmen hatası (ana ekrandaki "çeviri hatası"). */
    @Volatile var lastFailure: Throwable? = null
        private set

    private fun packLookup(text: String, s: TranslationSettings): LegacyPackLibrary.Match? {
        if (!s.target.isTurkish || !s.packsEnabled) return null
        return packs?.find(text, s.manualGame, s.showSpeakerNames)
    }

    private fun poolLookup(text: String, s: TranslationSettings): String? {
        val key = PackKey.of(text) ?: return null
        return pool?.lookup(s.target.code, key)
    }

    suspend fun translate(line: String, s: TranslationSettings): LineResult? {
        val text = line.trim()
        if (text.isEmpty()) return null
        // 1. Zaten hedef dilde.
        if (s.target.isAlreadyInTarget(text)) return LineResult(text, text, LineResult.Origin.SAME_LANGUAGE)
        val poolFirst = pool?.isPoolFirst(s.game, s.target.code) == true
        // 2. Oyun paketi (havuz öncelikli oyunda değil).
        if (!poolFirst) packLookup(text, s)?.let { return shown(s, LineResult(text, it.text, LineResult.Origin.PACK, it.packId)) }
        if (s.target.isTurkish && s.sharePool && !s.fromClip && !s.sideText) pool?.offer(text, s.game)
        // 3. Havuz belleği.
        poolLookup(text, s)?.let { return shown(s, LineResult(text, it, LineResult.Origin.POOL)) }
        val context = recent.last(pool?.contextLines ?: 4, withinMs = 30_000, except = text).map { it.source }
        // 4. Havuz öncelikli oyun: sunucu sorulur, en çok deadline beklenir; gelmezse yalnız cihaz içi.
        if (poolFirst && pool != null) {
            // İstek arka plan kapsamında sürer: bekleme dolsa da geç gelen cevap belleğe yazılır.
            val job = scope.async { safeAsk { pool.ask(text, s.target.code, s.game, context, force = true) } }
            val answer = kotlinx.coroutines.withTimeoutOrNull(pool.poolFirstDeadlineMs) { job.await() }
            if (!answer.isNullOrBlank()) return shown(s, LineResult(text, answer, LineResult.Origin.POOL))
            val local = onDeviceOrNull(text, s) ?: return null
            upgradeLater(text, local) { job.await() }
            return shown(s, local)
        }
        // 5-6. Seçili çevirmen, hata olursa cihaz içi.
        var result: LineResult? = null
        val engine = online
        if (engine != null && engine.engine.supports(s.target)) {
            try {
                val ctx = recent.last(3, except = text).map { ContextLine(it.source, it.translation) }
                result = LineResult(text, engine.translate(text, s.target, ctx, s.game), LineResult.Origin.ONLINE, engine.engine.cacheName)
            } catch (e: CancellationException) { throw e } catch (e: Exception) { lastFailure = e }
        }
        if (result == null) result = onDeviceOrNull(text, s) ?: return null
        // 7. Çeviri sürerken havuzdan inen ya da paketten gelen varsa o gösterilir.
        packLookup(text, s)?.let { return shown(s, LineResult(text, it.text, LineResult.Origin.PACK, it.packId)) }
        poolLookup(text, s)?.let { return shown(s, LineResult(text, it, LineResult.Origin.POOL)) }
        // 8. Arka planda sunucuya sorulur (havuz açıksa).
        if (pool != null && s.sharePool && !s.fromClip && !s.sideText) upgradeLater(text, result) { safeAsk { pool.ask(text, s.target.code, s.game, context, force = false) } }
        return shown(s, result)
    }

    private suspend fun onDeviceOrNull(text: String, s: TranslationSettings): LineResult? = try {
        LineResult(text, onDevice.translate(text, s.target), LineResult.Origin.ON_DEVICE, OnDeviceLineTranslator.ENGINE_NAME).also { lastFailure = null }
    } catch (e: CancellationException) { throw e } catch (e: Exception) { lastFailure = e; null }

    private fun upgradeLater(text: String, current: LineResult, fetch: suspend () -> String?) {
        if (current.origin == LineResult.Origin.PACK) return
        scope.launch {
            val answer = runCatching { fetch() }.getOrNull()
            if (!answer.isNullOrBlank() && answer != current.text) {
                val up = LineResult(text, answer, LineResult.Origin.POOL)
                recent.record(text, answer)
                onUpgrade(up)
            }
        }
    }

    private suspend fun safeAsk(block: suspend () -> String?): String? = try { block() } catch (e: CancellationException) { throw e } catch (e: Exception) { null }

    private fun shown(s: TranslationSettings, r: LineResult): LineResult { if (!s.sideText) recent.record(r.source, r.text); return r }

}
