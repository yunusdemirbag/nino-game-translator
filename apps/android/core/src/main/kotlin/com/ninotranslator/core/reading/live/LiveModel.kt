// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import kotlin.math.abs

/** Zaman kaynağı (ms). Testlerde elle ilerletilir. */
fun interface LiveClock {
    fun nowMs(): Long
}

/** Elle ilerletilen saat. */
class ManualClock(var now: Long = 0L) : LiveClock {
    override fun nowMs(): Long = now
    fun advance(ms: Long) { now += ms }
}

/** Kenarlarıyla verilen dikdörtgen (0–1), sol üst başlangıçlı. */
data class LiveBox(val left: Double, val top: Double, val right: Double, val bottom: Double) {
    val width: Double get() = right - left
    val height: Double get() = bottom - top
    val midX: Double get() = (left + right) / 2
    val midY: Double get() = (top + bottom) / 2

    fun union(o: LiveBox) = LiveBox(minOf(left, o.left), minOf(top, o.top), maxOf(right, o.right), maxOf(bottom, o.bottom))
    fun containsPoint(x: Double, y: Double) = x >= left && x <= right && y >= top && y <= bottom
}

/** Altyazı bölgesi: karenin oranı olarak üst/alt/sol/sağ kenar. */
data class LiveRegion(val top: Double, val bottom: Double, val left: Double, val right: Double) {
    val width: Double get() = right - left
    val height: Double get() = bottom - top

    /** Bölgeye göre kutuyu karenin oranına çevirir. */
    fun toFrame(b: LiveBox) = LiveBox(left + b.left * width, top + b.top * height, left + b.right * width, top + b.bottom * height)

    /** Karenin oranındaki kutuyu bölgeye göre orana çevirir. */
    fun fromFrame(b: LiveBox) = LiveBox(
        (b.left - left) / width, (b.top - top) / height, (b.right - left) / width, (b.bottom - top) / height,
    )

    /** Karenin içinde kalır, en ve boy en az [MIN_SIZE]. */
    fun clamped(): LiveRegion {
        var w = width.coerceIn(MIN_SIZE, 1.0)
        var h = height.coerceIn(MIN_SIZE, 1.0)
        val l = left.coerceIn(0.0, 1.0 - w)
        val t = top.coerceIn(0.0, 1.0 - h)
        return LiveRegion(t, t + h, l, l + w)
    }

    /** Boyutu koruyarak taşır; karenin dışına çıkamaz. */
    fun moved(dx: Double, dy: Double): LiveRegion {
        val c = clamped()
        val l = (c.left + dx).coerceIn(0.0, 1.0 - c.width)
        val t = (c.top + dy).coerceIn(0.0, 1.0 - c.height)
        return LiveRegion(t, t + c.height, l, l + c.width)
    }

    /** Bir hazıra en çok 0.001 farkla eşit mi? */
    fun matches(o: LiveRegion, eps: Double = 0.001) =
        abs(top - o.top) <= eps && abs(bottom - o.bottom) <= eps && abs(left - o.left) <= eps && abs(right - o.right) <= eps

    companion object {
        const val MIN_SIZE = 0.05
        val BOTTOM = LiveRegion(0.62, 0.97, 0.14, 0.86)
        val TOP = LiveRegion(0.03, 0.38, 0.14, 0.86)
        val FULL = LiveRegion(0.0, 1.0, 0.0, 1.0)

        /** Ek alan hazırları. */
        val QUEST = LiveRegion(0.03, 0.30, 0.66, 0.98)
        val NOTIFICATION = LiveRegion(0.58, 0.88, 0.02, 0.30)
        val PHONE_MESSAGE = LiveRegion(0.50, 0.95, 0.72, 0.98)
        const val MAX_EXTRA_AREAS = 3
    }
}

enum class RegionPreset { BOTTOM, TOP, FULL, CUSTOM }

/** Kayıtlı bölgenin hangi hazır seçim olduğu. */
fun presetOf(r: LiveRegion): RegionPreset = when {
    r.matches(LiveRegion.BOTTOM) -> RegionPreset.BOTTOM
    r.matches(LiveRegion.TOP) -> RegionPreset.TOP
    r.matches(LiveRegion.FULL) -> RegionPreset.FULL
    else -> RegionPreset.CUSTOM
}

/** Okunan tek satır. Kutu okunan bölgeye göredir ve bilinmeyebilir. */
data class LiveLine(val text: String, val box: LiveBox? = null)

/** Süzgeçten çıkan okuma: satırlar alt satırla birleşir. */
data class LiveReading(val lines: List<LiveLine>) {
    val text: String get() = lines.joinToString("\n") { it.text }
    /** Satırların bölgeye göre birleşik kutusu (biri bilinmiyorsa yok). */
    val box: LiveBox? get() = if (lines.isEmpty() || lines.any { it.box == null }) null else lines.map { it.box!! }.reduce(LiveBox::union)
    val isEmpty: Boolean get() = lines.isEmpty()

    companion object {
        val EMPTY = LiveReading(emptyList())
        fun of(text: String): LiveReading = LiveReading(text.split('\n').filter { it.isNotBlank() }.map { LiveLine(it) })
    }
}
