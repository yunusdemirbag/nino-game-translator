// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.remoteplay

import java.nio.ByteBuffer

/**
 * PS5'ten çözülmüş bir kare. [luma] görünür Y düzlemidir (satır aralığı [stride] = [width]); [chroma] yarım
 * çözünürlüklü renk, NV12 sırasıyla (U, V, U, V…; satır başına 2 × (en/2) bayt), yoksa null.
 *
 * Arabellekler **yalnız dinleyici çağrısı süresince geçerlidir**; sonraki kare aynı belleğe yazılır. Saklamak
 * gerekiyorsa [copyLuma] ile kopyalanmalı. Dinleyici kısa sürmeli (çözücünün çıkış iş parçacığında çağrılır).
 */
class RemotePlayFrame(
    val luma: ByteBuffer,
    val width: Int,
    val height: Int,
    val stride: Int,
    val chroma: ByteBuffer?,
    val colorFormat: Int,
    val timestampMs: Long,
) {
    fun copyLuma(): ByteArray {
        val out = ByteArray(width * height)
        luma.duplicate().apply { position(0) }.get(out, 0, minOf(out.size, luma.capacity()))
        return out
    }

    companion object {
        /** Yerelden gelen tek arabelleği (Y + renk) düzlemlere ayırır. */
        fun wrap(buffer: ByteBuffer, width: Int, height: Int, stride: Int, colorFormat: Int, hasChroma: Boolean,
                 timestampMs: Long): RemotePlayFrame? {
            val ySize = stride * height
            if (width <= 0 || height <= 0 || buffer.capacity() < ySize) return null
            val luma = buffer.duplicate().apply { position(0); limit(ySize) }.slice()
            val cSize = (width / 2) * 2 * (height / 2)
            val chroma = if (hasChroma && buffer.capacity() >= ySize + cSize)
                buffer.duplicate().apply { position(ySize); limit(ySize + cSize) }.slice() else null
            return RemotePlayFrame(luma, width, height, stride, chroma, colorFormat, timestampMs)
        }
    }
}

fun interface RemotePlayFrameListener {
    fun onFrame(frame: RemotePlayFrame)
}
