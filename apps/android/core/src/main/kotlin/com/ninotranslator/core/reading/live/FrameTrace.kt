// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import kotlin.math.abs
import kotlin.math.roundToInt

/** Parlaklık (gri) düzlemi. */
class LumaPlane(val data: ByteArray, val width: Int, val height: Int, val rowStride: Int = width) {
    fun at(x: Int, y: Int): Int = data[y * rowStride + x].toInt() and 0xFF
}

/** Piksel cinsinden kırpma. */
data class PixelRect(val left: Int, val top: Int, val width: Int, val height: Int)

/** Kare izi hesapları (okuma.md 1–2). */
object FrameTrace {
    const val MIN_CROP = 16
    const val GRID_W = 64
    const val GRID_H = 12
    const val CHANGE_STEP = 16

    /** Bölgenin kırpması: sol/üst ve en/boy çift sayıya yuvarlanır; 16 pikselden küçükse null. */
    fun crop(region: LiveRegion, frameW: Int, frameH: Int): PixelRect? {
        fun even(v: Double) = (v.roundToInt() / 2) * 2
        val l = even(region.left * frameW).coerceIn(0, frameW)
        val t = even(region.top * frameH).coerceIn(0, frameH)
        val w = even(region.width * frameW).coerceAtMost(((frameW - l) / 2) * 2)
        val h = even(region.height * frameH).coerceAtMost(((frameH - t) / 2) * 2)
        if (w < MIN_CROP || h < MIN_CROP) return null
        return PixelRect(l, t, w, h)
    }

    /** Kaba iz: her 8. satırın her 8. pikseli, parlaklığın üst 4 biti. */
    fun coarse(p: LumaPlane, r: PixelRect = PixelRect(0, 0, p.width, p.height)): CoarseTrace {
        val out = ArrayList<Byte>()
        var y = r.top
        while (y < r.top + r.height) {
            var x = r.left
            while (x < r.left + r.width) { out += (p.at(x, y) ushr 4).toByte(); x += 8 }
            y += 8
        }
        return CoarseTrace(out.toByteArray())
    }

    /** 64×12 gri iz: her hücrenin ortasındaki piksel. */
    fun grid(p: LumaPlane, r: PixelRect = PixelRect(0, 0, p.width, p.height)): RegionTrace {
        val v = IntArray(GRID_W * GRID_H)
        for (gy in 0 until GRID_H) for (gx in 0 until GRID_W) {
            val x = r.left + ((gx + 0.5) * r.width / GRID_W).toInt().coerceIn(0, r.width - 1)
            val y = r.top + ((gy + 0.5) * r.height / GRID_H).toInt().coerceIn(0, r.height - 1)
            v[gy * GRID_W + gx] = p.at(x, y)
        }
        return RegionTrace(v)
    }
}

class CoarseTrace(val bytes: ByteArray) {
    override fun equals(other: Any?) = other is CoarseTrace && bytes.contentEquals(other.bytes)
    override fun hashCode() = bytes.contentHashCode()
}

/** Bölgenin 64×12 izi. */
class RegionTrace(val samples: IntArray) {
    /**
     * Bir örnek 16'dan fazla değiştiyse "değişti". [box] verilirse (bölgeye göre) yalnız onun
     * örttüğü örneklere bakılır.
     */
    fun changedFrom(o: RegionTrace, box: LiveBox? = null): Boolean {
        for (gy in 0 until FrameTrace.GRID_H) for (gx in 0 until FrameTrace.GRID_W) {
            if (box != null && !box.containsPoint((gx + 0.5) / FrameTrace.GRID_W, (gy + 0.5) / FrameTrace.GRID_H)) continue
            val i = gy * FrameTrace.GRID_W + gx
            if (abs(samples[i] - o.samples[i]) > FrameTrace.CHANGE_STEP) return true
        }
        return false
    }

    /** 16'dan fazla değişen örneklerin payı (0–1). */
    fun changedShare(o: RegionTrace): Double {
        val n = minOf(samples.size, o.samples.size)
        if (n == 0) return 0.0
        var c = 0
        for (i in 0 until n) if (abs(samples[i] - o.samples[i]) > FrameTrace.CHANGE_STEP) c++
        return c.toDouble() / n
    }
}

/**
 * Değişmeyen bölge: iz öncekiyle aynıysa yazı tanıma çalışmaz, son okuma yeniden verilir. En çok
 * 20 kare (hızlı altyazı algılamada 2) tekrarlanır, sonra yeniden okunur.
 */
class UnchangedRegionGate(fastDetection: Boolean = false) {
    private val limit = if (fastDetection) 2 else 20
    private var last: CoarseTrace? = null
    private var reused = 0

    /** true: OCR atlanır, son okuma kullanılır. */
    fun shouldReuse(trace: CoarseTrace): Boolean {
        if (trace == last && reused < limit) { reused++; return true }
        last = trace
        reused = 0
        return false
    }

    fun reset() { last = null; reused = 0 }
}

/** Okuma sıklığı: saniyede en çok 5 kare; okuma sürerken gelen kare atlanır. */
class ReadThrottle(private val minIntervalMs: Long = 200) {
    private var lastStart = Long.MIN_VALUE / 2
    private var busy = false

    fun tryStart(nowMs: Long): Boolean {
        if (busy || nowMs - lastStart < minIntervalMs) return false
        busy = true; lastStart = nowMs
        return true
    }

    fun finish() { busy = false }
}
