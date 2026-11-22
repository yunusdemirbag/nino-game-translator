// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import java.nio.ByteBuffer
import kotlin.math.roundToInt

/** Küçük renkli görüntü: her piksel 0xRRGGBB. Oyun içi telefonu bulmak için (okuma.md 9). */
class RgbImage(val width: Int, val height: Int, val pixels: IntArray = IntArray(width * height)) {
    fun rgb(x: Int, y: Int): Int = pixels[y * width + x]
    fun r(x: Int, y: Int) = (rgb(x, y) shr 16) and 0xFF
    fun g(x: Int, y: Int) = (rgb(x, y) shr 8) and 0xFF
    fun b(x: Int, y: Int) = rgb(x, y) and 0xFF

    /** En koyu kanal. */
    fun minChannel(x: Int, y: Int): Int { val p = rgb(x, y); return minOf((p shr 16) and 0xFF, (p shr 8) and 0xFF, p and 0xFF) }

    /** Kanallar arası en büyük fark. */
    fun spread(x: Int, y: Int): Int {
        val p = rgb(x, y); val r = (p shr 16) and 0xFF; val g = (p shr 8) and 0xFF; val b = p and 0xFF
        return maxOf(r, g, b) - minOf(r, g, b)
    }

    fun luma(x: Int, y: Int): Int { val p = rgb(x, y); return (((p shr 16) and 0xFF) * 299 + ((p shr 8) and 0xFF) * 587 + (p and 0xFF) * 114) / 1000 }

    fun set(x: Int, y: Int, r: Int, g: Int, b: Int) { pixels[y * width + x] = (r.coerceIn(0, 255) shl 16) or (g.coerceIn(0, 255) shl 8) or b.coerceIn(0, 255) }

    /** Bütün kanallar [factor] ile çarpılır (karanlık karede aydınlatma). */
    fun scaled(factor: Double): RgbImage {
        val out = RgbImage(width, height)
        for (i in pixels.indices) {
            val p = pixels[i]
            val r = (((p shr 16) and 0xFF) * factor).roundToInt().coerceIn(0, 255)
            val g = (((p shr 8) and 0xFF) * factor).roundToInt().coerceIn(0, 255)
            val b = ((p and 0xFF) * factor).roundToInt().coerceIn(0, 255)
            out.pixels[i] = (r shl 16) or (g shl 8) or b
        }
        return out
    }

    /** Bir kutunun ortalama rengi (0–1 oranlarında); kutu boşsa null. */
    fun average(box: LiveBox): Int? {
        val x0 = (box.left * width).toInt().coerceIn(0, width - 1); val x1 = (box.right * width).toInt().coerceIn(0, width - 1)
        val y0 = (box.top * height).toInt().coerceIn(0, height - 1); val y1 = (box.bottom * height).toInt().coerceIn(0, height - 1)
        var r = 0L; var g = 0L; var b = 0L; var n = 0
        for (y in y0..y1) for (x in x0..x1) { val p = rgb(x, y); r += (p shr 16) and 0xFF; g += (p shr 8) and 0xFF; b += p and 0xFF; n++ }
        if (n == 0) return null
        return ((r / n).toInt() shl 16) or ((g / n).toInt() shl 8) or (b / n).toInt()
    }

    /**
     * Balonun rengi: kutudaki noktaların parlak yarısının ortalaması (koyu yazı atılır); kutu boşsa null.
     * Gelen beyaz balonda beyaz, giden mavi balonda mavi çıkar.
     */
    fun bubble(box: LiveBox): Int? {
        val x0 = (box.left * width).toInt().coerceIn(0, width - 1); val x1 = (box.right * width).toInt().coerceIn(0, width - 1)
        val y0 = (box.top * height).toInt().coerceIn(0, height - 1); val y1 = (box.bottom * height).toInt().coerceIn(0, height - 1)
        val px = ArrayList<Int>()
        for (y in y0..y1) for (x in x0..x1) px += rgb(x, y)
        if (px.isEmpty()) return null
        val bright = px.sortedBy { p -> (((p shr 16) and 0xFF) * 299 + ((p shr 8) and 0xFF) * 587 + (p and 0xFF) * 114) }.drop(px.size / 2)
        var r = 0L; var g = 0L; var b = 0L
        for (p in bright) { r += (p shr 16) and 0xFF; g += (p shr 8) and 0xFF; b += p and 0xFF }
        val n = bright.size
        return ((r / n).toInt() shl 16) or ((g / n).toInt() shl 8) or (b / n).toInt()
    }

    companion object {
        const val PHONE_W = 240
        const val PHONE_H = 135

        fun hex(rgb: Int) = "#%06x".format(rgb and 0xFFFFFF)

        /**
         * Rengin belirgin mavi olup olmadığı (giden mesaj balonu). Oyundaki giden balon açık lavanta mavisidir
         * (gerçek karelerde mavi kırmızıdan 12–37, yeşilden 13–27 fazla); gelen balon beyaz ya da sıcak gridir.
         */
        fun isBlue(rgb: Int): Boolean {
            val r = (rgb shr 16) and 0xFF; val g = (rgb shr 8) and 0xFF; val b = rgb and 0xFF
            return b >= 100 && b - r >= 10 && b - g >= 8
        }

        /**
         * YUV kareyi en yakın örnekle küçültür (BT.601, video aralığı). [u]/[v] yarım çözünürlükte, kaynağın
         * satır ve piksel adımlarıyla.
         */
        fun fromYuv(
            luma: ByteBuffer, lumaStride: Int, width: Int, height: Int,
            u: ByteBuffer, v: ByteBuffer, chromaRowStride: Int, chromaPixelStride: Int,
            outW: Int = PHONE_W, outH: Int = PHONE_H,
        ): RgbImage {
            val out = RgbImage(outW, outH)
            for (oy in 0 until outH) {
                val y = ((oy + 0.5) * height / outH).toInt().coerceIn(0, height - 1)
                for (ox in 0 until outW) {
                    val x = ((ox + 0.5) * width / outW).toInt().coerceIn(0, width - 1)
                    val yi = y * lumaStride + x
                    val ci = (y / 2) * chromaRowStride + (x / 2) * chromaPixelStride
                    val yy = if (yi < luma.limit()) luma.get(yi).toInt() and 0xFF else 0
                    val uu = (if (ci < u.limit()) u.get(ci).toInt() and 0xFF else 128) - 128
                    val vv = (if (ci < v.limit()) v.get(ci).toInt() and 0xFF else 128) - 128
                    val c = 1.164 * (yy - 16)
                    out.set(ox, oy, (c + 1.596 * vv).roundToInt(), (c - 0.392 * uu - 0.813 * vv).roundToInt(), (c + 2.017 * uu).roundToInt())
                }
            }
            return out
        }
    }
}
