// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading

/** Karenin oranı olarak dikdörtgen (0–1). Başlangıç noktası sol üst köşedir. */
data class NormalizedRect(val x: Double, val y: Double, val width: Double, val height: Double) {
    val midX: Double get() = x + width / 2
    val midY: Double get() = y + height / 2

    fun contains(px: Double, py: Double): Boolean = px >= x && px <= x + width && py >= y && py <= y + height

    companion object {
        /** Varsayılan altyazı bölgesi: altta ve ortada. */
        val DEFAULT_SUBTITLE = NormalizedRect(0.10, 0.62, 0.80, 0.36)
        val FULL = NormalizedRect(0.0, 0.0, 1.0, 1.0)
    }
}

/** OCR'nin okuduğu tek satır. */
data class RecognizedLine(val text: String, val confidence: Float, val box: NormalizedRect)
