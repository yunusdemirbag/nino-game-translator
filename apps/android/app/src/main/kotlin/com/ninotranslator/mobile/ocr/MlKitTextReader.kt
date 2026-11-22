// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ocr

import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.ninotranslator.core.reading.live.LiveBox
import com.ninotranslator.core.reading.live.LiveLine
import com.ninotranslator.core.reading.live.LumaPlane
import com.ninotranslator.mobile.service.TextReader
import kotlinx.coroutines.tasks.await

/**
 * ML Kit'in cihaz üstü Latin modeli, varsayılan ayarlarla (okuma.md 2). Girdi zaten bölgeye kırpılmış gri düzlemdir;
 * renk düzlemleri nötr 128 ile doldurulur (beyaz ve sarı altyazı aynı okunur). Ölçek değişmez. Güven değeri
 * kullanılmaz. Kutular kırpmaya göre 0–1; satırlar üst kenara göre sıralanır, boşlar atılır.
 * Süre sınırı (5 sn) çağıranda.
 */
class MlKitTextReader : TextReader, AutoCloseable {
    private val recognizer: TextRecognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    private var nv21: ByteArray = ByteArray(0)

    override suspend fun read(image: LumaPlane): List<LiveLine> {
        val w = image.width; val h = image.height
        if (w < 16 || h < 16 || w % 2 != 0 || h % 2 != 0) return emptyList()
        val size = w * h + w * h / 2
        val buf = if (nv21.size == size) nv21 else ByteArray(size).also { nv21 = it }
        for (y in 0 until h) System.arraycopy(image.data, y * image.rowStride, buf, y * w, w)
        java.util.Arrays.fill(buf, w * h, size, 128.toByte())
        // ML Kit arabelleği işlerken kopyalar; aynı arabellek bir sonraki okumada yeniden kullanılır (okumalar sıralı).
        val input = InputImage.fromByteArray(buf, w, h, 0, InputImage.IMAGE_FORMAT_NV21)
        val result = recognizer.process(input).await()
        val out = ArrayList<LiveLine>()
        for (block in result.textBlocks) for (line in block.lines) {
            val text = line.text.trim()
            if (text.isEmpty()) continue
            val b = line.boundingBox
            val box = b?.let { LiveBox(it.left.toDouble() / w, it.top.toDouble() / h, it.right.toDouble() / w, it.bottom.toDouble() / h) }
            out += LiveLine(text, box)
        }
        return out.sortedBy { it.box?.top ?: Double.MAX_VALUE }
    }

    override fun close() = recognizer.close()
}
