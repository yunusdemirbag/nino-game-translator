// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import com.ninotranslator.core.json.Json
import com.ninotranslator.core.json.bool
import com.ninotranslator.core.json.double
import com.ninotranslator.core.json.obj
import com.ninotranslator.core.json.str
import java.util.UUID
import kotlin.math.abs

// Ayar değerleri. Diske büyük harfli enum adıyla yazılır (subtitleFont hariç: küçük harf).

/** Görüntü kaynağı; konsol türünün tek doğru kaynağı. */
enum class VideoSource { REMOTE_PLAY, CAPTURE_CARD, XBOX }

/** Altyazının gösterildiği yer. */
enum class SubtitleTarget { TV, PHONE }

enum class HomeStyle { LIVING_ROOM, TOGGLE }

/** Çeviri motoru. `secrets` içindeki anahtar adı `key.<ad>`. */
enum class Engine { FREE, DEEPL, GEMINI, OPENAI, CLAUDE }

enum class TextColor { WHITE, YELLOW }

enum class SubtitleFont(val wire: String) {
    CONDENSED("condensed"), MODERN("modern"), ROUNDED("rounded"), SYSTEM("system");

    companion object {
        /** Büyük/küçük harf fark etmez; tanınmayan → condensed. */
        fun parse(value: String?): SubtitleFont =
            entries.firstOrNull { it.wire.equals(value?.trim(), ignoreCase = true) } ?: CONDENSED
    }
}

enum class TvBackgroundShape { FIT, BAND }
enum class TvDisplayMode { IN_APP, OVERLAY }
enum class TvPlacement { COVER, ABOVE, BELOW, FIXED }
enum class AreaPreset { BOTTOM, TOP, FULL, CUSTOM }
enum class TvBrand { LG, SAMSUNG, ANDROID_TV }

/** Xbox yayın kalitesi (`xboxQuality`). 720p: Xbox daha düşük çözünürlük ve bit hızıyla gönderir, zayıf Wi-Fi'da daha az kopar. */
enum class XboxQuality { P1080, P720 }

/** Türetilen konsol türü (§5.1). Ayarda tutulmaz. */
enum class ConsoleKind { PLAYSTATION, XBOX }

internal inline fun <reified E : Enum<E>> parseEnum(value: String?): E? {
    if (value.isNullOrBlank()) return null
    val v = value.trim()
    return enumValues<E>().firstOrNull { it.name == v } ?: enumValues<E>().firstOrNull { it.name.equals(v, ignoreCase = true) }
}

/** Görüntüye oranla (0–1) dikdörtgen bölge. */
data class Region(val top: Double, val bottom: Double, val left: Double, val right: Double) {
    fun sameAs(o: Region, eps: Double = 0.001) =
        abs(top - o.top) <= eps && abs(bottom - o.bottom) <= eps && abs(left - o.left) <= eps && abs(right - o.right) <= eps

    fun toMap(): Map<String, Any?> = linkedMapOf("top" to top, "bottom" to bottom, "left" to left, "right" to right)
    fun toJson(): String = Json.write(toMap())

    companion object {
        val BOTTOM = Region(0.62, 0.97, 0.14, 0.86)
        val TOP = Region(0.03, 0.38, 0.14, 0.86)
        val FULL = Region(0.0, 1.0, 0.0, 1.0)
        val DEFAULT = BOTTOM

        // Ek alan hazırları.
        val QUEST = Region(0.03, 0.30, 0.66, 0.98)
        val NOTIFICATION = Region(0.58, 0.88, 0.02, 0.30)
        val PHONE = Region(0.50, 0.95, 0.72, 0.98)

        fun of(preset: AreaPreset): Region? = when (preset) {
            AreaPreset.BOTTOM -> BOTTOM
            AreaPreset.TOP -> TOP
            AreaPreset.FULL -> FULL
            AreaPreset.CUSTOM -> null
        }

        /** Hazır seçimlerden biriyle (±0,001) aynıysa o, değilse CUSTOM. */
        fun presetOf(r: Region): AreaPreset = when {
            r.sameAs(BOTTOM) -> AreaPreset.BOTTOM
            r.sameAs(TOP) -> AreaPreset.TOP
            r.sameAs(FULL) -> AreaPreset.FULL
            else -> AreaPreset.CUSTOM
        }

        /** Dört alan da sayı olmalı; değilse null. */
        fun fromMap(m: Map<String, Any?>?): Region? {
            m ?: return null
            return Region(m.double("top") ?: return null, m.double("bottom") ?: return null,
                m.double("left") ?: return null, m.double("right") ?: return null)
        }

        fun parse(json: String?): Region? =
            json?.let { runCatching { fromMap(Json.parseObject(it)) }.getOrNull() }
    }
}

/** Altyazının yanında okunan ek alan (görev, bildirim, telefon). */
data class ExtraArea(val id: String, val name: String, val region: Region, val enabled: Boolean = true) {
    fun toMap(): Map<String, Any?> = linkedMapOf("id" to id, "name" to name, "region" to region.toMap(), "enabled" to enabled)

    companion object {
        const val MAX = 3

        fun parseList(json: String?): List<ExtraArea> = parse(json).first

        /** İkinci değer: kimliği boş olup yenisi üretilen öğe var mı (kalıcı olsun diye geri yazılmalı). */
        fun parse(json: String?): Pair<List<ExtraArea>, Boolean> {
            if (json.isNullOrBlank()) return emptyList<ExtraArea>() to false
            val list = runCatching { Json.parse(json) as? List<*> }.getOrNull() ?: return emptyList<ExtraArea>() to false
            var repaired = false
            val out = list.asSequence().mapNotNull { item ->
                @Suppress("UNCHECKED_CAST")
                val m = item as? Map<String, Any?> ?: return@mapNotNull null
                ExtraArea(
                    id = m.str("id")?.takeIf { it.isNotBlank() } ?: UUID.randomUUID().toString().also { repaired = true },
                    name = m.str("name") ?: "",
                    region = Region.fromMap(m.obj("region")) ?: Region.QUEST,
                    enabled = m.bool("enabled") ?: true,
                )
            }.take(MAX).toList()
            return out to repaired
        }

        fun toJson(list: List<ExtraArea>): String = Json.write(list.take(MAX).map { it.toMap() })
    }
}

/** Seçilen Xbox (`xboxConsole`). */
data class XboxConsole(
    val id: String,
    val name: String? = null,
    val model: String? = null,
    val streamingEnabled: Boolean = false,
    val powerState: String? = null,
) {
    fun toJson(): String = Json.write(linkedMapOf<String, Any?>("id" to id).apply {
        if (name != null) put("name", name)
        if (model != null) put("model", model)
        put("streamingEnabled", streamingEnabled)
        if (powerState != null) put("powerState", powerState)
    })

    companion object {
        fun parse(json: String?): XboxConsole? {
            val m = json?.let { runCatching { Json.parseObject(it) }.getOrNull() } ?: return null
            val id = m.str("id")?.takeIf { it.isNotBlank() } ?: return null
            return XboxConsole(id, m.str("name"), m.str("model"), m.bool("streamingEnabled") ?: false, m.str("powerState"))
        }
    }
}

/** Bu telefonun TV uygulamasını kurduğu TV (`tvApp.*` dörtlüsü). */
data class InstalledTv(val brand: TvBrand, val host: String, val port: Int = 0, val version: String? = null)
