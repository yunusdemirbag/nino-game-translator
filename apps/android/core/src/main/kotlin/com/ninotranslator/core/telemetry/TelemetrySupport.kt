// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.telemetry

import com.ninotranslator.core.telemetry.diag.DiagConfig
import java.io.ByteArrayOutputStream
import java.util.UUID
import java.util.zip.GZIPOutputStream

/**
 * Her parçada giden ortak alanlar (`ctx`). [cleaned] sunucunun kurallarıyla süzer: uymayan alan boş gider
 * (ör. kullanıcının verdiği cihaz adı hiç gönderilmez).
 */
data class TelemetryContext(
    val platform: String,
    val app: String,
    val os: String,
    /** Cihaz modeli (`SM-S918B`), kullanıcının verdiği ad değil. */
    val device: String,
    /** Bağlı TV'nin markası (`androidtv`, `samsung`, `lg`); yoksa boş. */
    val tv: String = "",
    val channel: String = "release",
) {
    fun cleaned() = TelemetryContext(
        platform = platform.takeIf { it in PLATFORMS } ?: "",
        app = app.takeIf { VERSION.matches(it) } ?: "",
        os = os.takeIf { OS.matches(it) } ?: "",
        device = device.trim().takeIf { DEVICE.matches(it) } ?: "",
        tv = tv.takeIf { it in TV_BRANDS } ?: "",
        channel = channel.takeIf { it in CHANNELS } ?: "release",
    )

    fun toWire(): Map<String, Any?> = linkedMapOf(
        "platform" to platform, "app" to app, "os" to os, "device" to device, "tv" to tv, "channel" to channel,
    )

    companion object {
        val PLATFORMS = setOf("mac", "windows", "linux", "android", "ios", "androidtv", "webos", "tizen")
        private val TV_BRANDS = setOf("androidtv", "samsung", "lg")
        private val CHANNELS = setOf("release", "beta", "dev")
        private val VERSION = Regex("^[0-9A-Za-z.+-]{1,24}$")
        private val OS = Regex("^[A-Za-z][A-Za-z0-9 ._()-]{0,39}$")
        private val DEVICE = Regex("^[A-Za-z0-9][A-Za-z0-9 ,._()+-]{0,59}$")

        /** Kurulum kimliği sunucunun beklediği biçimde mi (UUID). Değilse ölçüm gönderilmez (400 = silme). */
        fun isInstallId(v: String): Boolean =
            v.length == 36 && runCatching { UUID.fromString(v) }.isSuccess && Regex("^[0-9a-fA-F-]{36}$").matches(v)
    }
}

/** Sunucunun uzaktan ölçüm ayarı (`/v1/config` → `telemetry`, ve her `/v1/events` cevabındaki `config`). */
data class TelemetryRemoteConfig(
    val enabled: Boolean = true,
    val sample: Double = 1.0,
    val maxPerDay: Int = 1000,
    val flushSeconds: Long = 600,
    /** Otomatik teşhis: kapatılan kurallar ve eşikler (`telemetry.diag`); yoksa tarifteki varsayılanlar. */
    val diag: DiagConfig = DiagConfig(),
) {
    fun toWire(): Map<String, Any?> = linkedMapOf(
        "enabled" to enabled, "sample" to sample, "maxPerDay" to maxPerDay.toLong(), "flushSeconds" to flushSeconds, "diag" to diag.toWire(),
    )

    companion object {
        /** Eksik ya da bozuk alanlarda varsayılan. */
        fun parse(m: Map<*, *>?): TelemetryRemoteConfig {
            val d = TelemetryRemoteConfig()
            if (m == null) return d
            return TelemetryRemoteConfig(
                enabled = m["enabled"] as? Boolean ?: d.enabled,
                sample = (m["sample"] as? Number)?.toDouble()?.takeIf { !it.isNaN() }?.coerceIn(0.0, 1.0) ?: d.sample,
                maxPerDay = (m["maxPerDay"] as? Number)?.toLong()?.coerceIn(0, 1_000_000)?.toInt() ?: d.maxPerDay,
                flushSeconds = (m["flushSeconds"] as? Number)?.toLong()?.coerceIn(60, 86_400) ?: d.flushSeconds,
                diag = DiagConfig.parse(m["diag"] as? Map<*, *>),
            )
        }

        /** 32 bit FNV-1a (işaretsiz). */
        fun fnv1a32(s: String): Long {
            var h = 0x811c9dc5L
            for (b in s.toByteArray(Charsets.UTF_8)) {
                h = h xor (b.toLong() and 0xff)
                h = (h * 0x01000193L) and 0xffffffffL
            }
            return h
        }

        /** Kurulum süre örnekleminde mi: `fnv1a32(kimlik küçük harf) % 10000 < sample × 10000`. Kurulum başına sabit. */
        fun isSampled(install: String, sample: Double): Boolean {
            if (sample >= 1) return true
            if (sample <= 0) return false
            return (fnv1a32(install.lowercase()) % 10_000).toDouble() < sample * 10_000
        }
    }
}

object TelemetryGzip {
    fun compress(data: ByteArray): ByteArray {
        val out = ByteArrayOutputStream(data.size / 3 + 64)
        GZIPOutputStream(out).use { it.write(data) }
        return out.toByteArray()
    }
}
