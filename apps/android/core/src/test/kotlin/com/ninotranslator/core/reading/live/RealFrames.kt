// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import java.io.File
import javax.imageio.ImageIO

/** Gerçek GTA 6 kareleri (JPG) → RgbImage / LumaPlane. Yol `nino.fixtures` test özelliğinden. */
object RealFrames {
    private val dir: File get() = File(System.getProperty("nino.fixtures") ?: error("nino.fixtures yok"))
    val names: List<String> get() = dir.listFiles { f -> f.name.startsWith("gta6-") && f.name.endsWith(".jpg") }!!.map { it.name }.sorted()

    private val cache = HashMap<String, java.awt.image.BufferedImage>()
    private fun load(name: String) = cache.getOrPut(name) { ImageIO.read(File(dir, name)) ?: error("okunamadı: $name") }

    /** Uygulamadaki gibi en yakın örnekle 240×135'e küçültülmüş renkli kare. */
    fun rgb(name: String, w: Int = RgbImage.PHONE_W, h: Int = RgbImage.PHONE_H): RgbImage {
        val src = load(name)
        val out = RgbImage(w, h)
        for (oy in 0 until h) {
            val y = ((oy + 0.5) * src.height / h).toInt().coerceIn(0, src.height - 1)
            for (ox in 0 until w) {
                val x = ((ox + 0.5) * src.width / w).toInt().coerceIn(0, src.width - 1)
                out.pixels[oy * w + ox] = src.getRGB(x, y) and 0xFFFFFF
            }
        }
        return out
    }

    /**
     * Cihazdaki yol: kare video aralığında YUV 4:2:0'a çevrilir (deneme kaynağı ve Remote Play gibi), sonra
     * [RgbImage.fromYuv] ile 240×135'e küçültülür.
     */
    fun rgbViaYuv(name: String): RgbImage {
        val src = load(name)
        val w = src.width / 2 * 2; val h = src.height / 2 * 2
        val px = src.getRGB(0, 0, w, h, null, 0, w)
        val y = ByteArray(w * h)
        for (i in 0 until w * h) { val c = px[i]; y[i] = (16 + (((c shr 16) and 255) * 257 + ((c shr 8) and 255) * 504 + (c and 255) * 98) / 1000).coerceIn(0, 255).toByte() }
        val cw = w / 2; val ch = h / 2
        val u = ByteArray(cw * ch); val v = ByteArray(cw * ch)
        for (cy in 0 until ch) for (cx in 0 until cw) {
            var r = 0; var g = 0; var b = 0
            for (dy in 0..1) for (dx in 0..1) { val c = px[(cy * 2 + dy) * w + cx * 2 + dx]; r += (c shr 16) and 255; g += (c shr 8) and 255; b += c and 255 }
            r /= 4; g /= 4; b /= 4
            u[cy * cw + cx] = (128 + (-148 * r - 291 * g + 439 * b) / 1000).coerceIn(0, 255).toByte()
            v[cy * cw + cx] = (128 + (439 * r - 368 * g - 71 * b) / 1000).coerceIn(0, 255).toByte()
        }
        return RgbImage.fromYuv(java.nio.ByteBuffer.wrap(y), w, w, h, java.nio.ByteBuffer.wrap(u), java.nio.ByteBuffer.wrap(v), cw, 1)
    }

    /** Tam boy renkli kare. */
    fun full(name: String): RgbImage { val s = load(name); return rgb(name, s.width, s.height) }

    /** Tam boy gri düzlem (BT.601 parlaklık). */
    fun luma(name: String): LumaPlane {
        val img = full(name)
        val data = ByteArray(img.width * img.height) { i -> val p = img.pixels[i]; ((((p shr 16) and 0xFF) * 299 + ((p shr 8) and 0xFF) * 587 + (p and 0xFF) * 114) / 1000).toByte() }
        return LumaPlane(data, img.width, img.height)
    }
}
