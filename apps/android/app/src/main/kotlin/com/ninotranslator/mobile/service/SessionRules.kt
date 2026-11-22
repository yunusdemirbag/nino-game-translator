// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import com.ninotranslator.core.reading.live.GameNames
import com.ninotranslator.core.reading.live.GameResolver
import com.ninotranslator.core.reading.live.LineWrapper
import com.ninotranslator.core.reading.live.LiveStabilizer
import com.ninotranslator.core.reading.live.PackGameGuesser
import com.ninotranslator.core.translation.LineResult
import com.ninotranslator.mobile.data.SubtitleFont
import com.ninotranslator.mobile.data.TextColor
import com.ninotranslator.mobile.data.TvBackgroundShape
import com.ninotranslator.mobile.data.TvDisplayMode
import com.ninotranslator.mobile.data.TvPlacement

/**
 * Telefon ekranındaki satır (servis.md 3.4): yeni satır öncekini üste (soluk) iter; aynı cümlenin uzamış ya da
 * düzelmiş okuması öncekinin yerine geçer. Süre dolunca satır kalkar.
 */
class PhoneLines {
    data class State(val current: String? = null, val previous: String? = null, val scale: Double = 1.0, val untilMs: Long = 0)

    var state = State(); private set
    private var currentSource: String? = null

    fun show(source: String, text: String, replaces: Boolean, durationMs: Long?, nowMs: Long): State {
        val wrapped = LineWrapper.wrap(text)
        val same = replaces || currentSource?.let { LiveStabilizer.isGrowthOrCorrection(it, source) } == true
        val previous = if (same) state.previous else state.current ?: state.previous
        state = State(wrapped.text, previous, wrapped.scale, nowMs + LineWrapper.phoneDisplayMs(text, durationMs))
        currentSource = source
        return state
    }

    /** "Temizlendi": iki satır da silinir. */
    fun clear(): State { state = State(); currentSource = null; return state }

    /** Süre dolduysa satır kalkar; değiştiyse yeni durum. */
    fun expire(nowMs: Long): State? {
        if (state.current == null || nowMs < state.untilMs) return null
        state = State(previous = null)
        currentSource = null
        return state
    }
}

/** TV'deki görünüm (tv.md 1.5 `style`). */
data class StyleInput(
    val autoSize: Boolean = true,
    val background: Int = 100,
    val backgroundShape: TvBackgroundShape = TvBackgroundShape.FIT,
    val bottomPercent: Int = 7,
    val displayMode: TvDisplayMode = TvDisplayMode.IN_APP,
    val font: SubtitleFont = SubtitleFont.entries.first(),
    val fontSize: Int = 46,
    val placement: TvPlacement = TvPlacement.COVER,
    val stackPrevious: Boolean = true,
    val textColor: TextColor = TextColor.WHITE,
    val watermark: Boolean = true,
)

object TvStyle {
    fun map(s: StyleInput): Map<String, Any?> = linkedMapOf(
        "autoSize" to s.autoSize,
        "background" to s.background.coerceIn(0, 100),
        "backgroundShape" to if (s.backgroundShape == TvBackgroundShape.BAND) "band" else "fit",
        "bold" to false,
        "bottomPercent" to s.bottomPercent,
        "displayMode" to if (s.displayMode == TvDisplayMode.OVERLAY) "overlay" else "inApp",
        "font" to s.font.wire,
        "fontSize" to s.fontSize,
        "placement" to s.placement.name.lowercase(),
        "stackPrevious" to s.stackPrevious,
        "textColor" to s.textColor.name.lowercase(),
        "watermark" to s.watermark,
    )
}

/** Cihaz içi model indirme denemeleri (ceviri.md 3): 6 deneme, aralar 10, 20, 30, 40, 50 sn; 2. hatadan sonra uyarı. */
object ModelRetry {
    const val ATTEMPTS = 6
    const val ATTEMPT_TIMEOUT_MS = 300_000L

    /** [failed] başarısız deneme sayısı (1..); sonraki denemeye kadar bekleme ya da null (vazgeç). */
    fun delayAfter(failed: Int): Long? = if (failed >= ATTEMPTS) null else failed * 10_000L

    fun showWarning(failed: Int): Boolean = failed >= 2
}

/**
 * Oynanan oyun (okuma.md 13): PS5 > kullanıcı > paket > ekran. Paketten: son 20 satırdan 5'i yalnız bir pakette
 * bulunduysa. [changed] oyun değişince true döner (havuz eşitleme, altyazı yeri yeniden hesap).
 */
class GameTracker(enabled: Boolean) {
    private val resolver = GameResolver()
    private val guesser = PackGameGuesser()
    var enabled = enabled; private set

    val current: String? get() = if (enabled) resolver.current else null
    val packGame: String? get() = resolver.packGame
    /** Kullanıcının elle seçtiği oyun. */
    val userGame: String? get() = resolver.userGame
    val ps5Game: String? get() = resolver.ps5Game
    /** Oyun bilinmiyor ya da yalnız paketten tahmin edildi (oyun içi telefon kapısı). */
    val unknownOrGuessed: Boolean get() = resolver.ps5Game == null && resolver.userGame == null && resolver.screenGame == null

    /** PS5'in bildirdiği oyun; görüntü kesilince null. */
    fun onPs5(name: String?): Boolean = change { resolver.onPs5Reported(name) }

    fun onUserChoice(game: String?): Boolean = change { resolver.userGame = game?.takeIf { it.isNotBlank() } }

    /** Gösterilen satır: paketten ve yalnız bir pakette bulunduysa o paket sayılır. */
    fun onShown(origin: LineResult.Origin?, packId: String?, uniquePack: Boolean): Boolean = change {
        val packs = if (origin == LineResult.Origin.PACK && packId != null && uniquePack) setOf(packId) else emptySet()
        resolver.packGame = guesser.record(packs) ?: resolver.packGame
    }

    fun onScreen(game: String?): Boolean = change { resolver.screenGame = game }

    private fun change(block: () -> Unit): Boolean {
        if (!enabled) return false
        val before = resolver.current
        block()
        val after = resolver.current
        return before == null && after != null || before != null && (after == null || !GameNames.sameGame(before, after))
    }
}
