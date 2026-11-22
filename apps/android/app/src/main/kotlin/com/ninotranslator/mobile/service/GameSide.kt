// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import android.graphics.Bitmap
import android.util.Base64
import android.util.Log
import com.ninotranslator.core.link.DisplayHub
import com.ninotranslator.core.link.NinoLink
import com.ninotranslator.core.pool.IdentifySchedule
import com.ninotranslator.core.pool.SharedPool
import com.ninotranslator.core.reading.live.ScreenIdentifyGate
import com.ninotranslator.mobile.data.TvBrand
import com.ninotranslator.mobile.tv.FoundTv
import com.ninotranslator.mobile.tv.TvFinder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Oyunu ekrandan tanıma (okuma.md 13, ceviri.md 6.7): karenin en çok 768 piksel genişliğe küçültülmüş gri kopyası
 * JPEG (kalite 60) olarak havuz sunucusuna gider. Zamanlama [IdentifySchedule]; kapı [ScreenIdentifyGate].
 * Sunucu bir şey söyleyemezse eski oyun kalır.
 */
class ScreenGameIdentifier(
    private val scope: CoroutineScope,
    private val pool: SharedPool,
    private val wallClock: () -> Long,
    private val allowed: () -> Boolean,
    private val onGame: (String) -> Unit,
) {
    private val schedule = IdentifySchedule(wallClock())
    private val busy = AtomicBoolean(false)

    fun offer(frame: VideoFrame) {
        val next = schedule.nextAt() ?: return
        val now = wallClock()
        if (now < next || !allowed() || !busy.compareAndSet(false, true)) return
        val (w, h) = ScreenIdentifyGate.scaledSize(frame.width, frame.height)
        val gray = IntArray(w * h)
        try {
            val src = frame.luma
            for (y in 0 until h) {
                val sy = (y.toLong() * frame.height / h).toInt()
                for (x in 0 until w) {
                    val sx = (x.toLong() * frame.width / w).toInt()
                    val i = sy * frame.stride + sx
                    val v = if (i < src.limit()) src.get(i).toInt() and 0xFF else 0
                    gray[y * w + x] = (0xFF shl 24) or (v shl 16) or (v shl 8) or v
                }
            }
        } catch (e: Exception) { busy.set(false); return }
        scope.launch {
            try {
                val b64 = jpeg(gray, w, h) ?: return@launch
                val game = runCatching { pool.identify(b64) }.getOrNull()
                schedule.record(now, game)
                Log.i("Nino", "ekrandan oyun: ${game ?: "tanınmadı"}")
                if (game != null) onGame(game)
            } finally { busy.set(false) }
        }
    }

    private fun jpeg(px: IntArray, w: Int, h: Int): String? {
        val bmp = Bitmap.createBitmap(px, w, h, Bitmap.Config.ARGB_8888)
        val out = ByteArrayOutputStream()
        try { bmp.compress(Bitmap.CompressFormat.JPEG, 60, out) } finally { bmp.recycle() }
        val bytes = out.toByteArray()
        if (bytes.size > SharedPool.MAX_IMAGE_BYTES) return null
        return Base64.encodeToString(bytes, Base64.NO_WRAP)
    }
}

/**
 * Ağdaki Android TV'leri bulup bağlanma (tv.md 2): eski uygulamada TV telefonu bulurdu; şimdi telefon mDNS ile Nino'su
 * açık TV'leri bulur ve bağlanır. Hiç TV bağlı değilken 30 sn'de, bağlıyken 2 dk'da bir aranır.
 */
class TvAutoConnect(
    private val scope: CoroutineScope,
    private val finder: () -> TvFinder,
    private val hub: () -> DisplayHub,
    private val connected: () -> Int,
) {
    private val linked = HashSet<String>()

    fun start() = scope.launch {
        while (isActive) {
            val found = runCatching { finder().search(3_000) }.getOrDefault(emptyList())
            for (tv in pick(found, synchronized(linked) { linked.toSet() })) {
                Log.i("NinoTv", "Android TV bulundu, bağlanılıyor")
                hub().connectTo(tv.address, tv.port ?: NinoLink.DEFAULT_PORT)
                synchronized(linked) { linked += tv.address }
            }
            delay(if (connected() > 0) 120_000 else 30_000)
        }
    }

    companion object {
        /** Bağlanılacaklar: Nino'su açık (mDNS) Android TV'ler, daha önce bağlanılmamış. */
        fun pick(found: List<FoundTv>, already: Set<String>): List<FoundTv> =
            found.filter { it.hasNino && (it.brand == null || it.brand == TvBrand.ANDROID_TV) && it.address !in already }
    }
}
