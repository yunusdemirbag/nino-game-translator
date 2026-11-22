// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.link

import com.ninotranslator.core.json.Json
import java.math.BigDecimal
import java.math.RoundingMode
import java.util.TreeMap

/**
 * Uzantı mesajlarının ortak biçimi (protokol "Uzantılar", tv.md 1.4): anahtarlar her düzeyde sıralı, kutular 0–1'e
 * kırpılıp 4 basamağa yuvarlanır, `light`/`alpha` 2, `angle` 1 basamak; sondaki sıfırlar atılır, üslü yazım yok.
 */
object LinkFormat {
    /** `cover` taşıyan mesajın sınırı. */
    const val MAX_COVER_MESSAGE_BYTES = 512 * 1024
    /** `cover` taşımayan mesajların sınırı. */
    const val MAX_COMPACT_MESSAGE_BYTES = NinoLink.MAX_MESSAGE_BYTES
    const val MAX_SCREEN_ITEMS = 30

    private val BOX_SIDES = setOf("left", "top", "right", "bottom")

    /** Json yazıcısının olduğu gibi bastığı sayı (ör. "0.875", "1"). */
    class PlainNumber(private val text: String) : Number() {
        override fun toString() = text
        override fun toDouble() = text.toDouble()
        override fun toFloat() = text.toFloat()
        override fun toLong() = toDouble().toLong()
        override fun toInt() = toDouble().toInt()
        override fun toShort() = toInt().toShort()
        override fun toByte() = toInt().toByte()
        override fun equals(other: Any?) = other is PlainNumber && other.text == text
        override fun hashCode() = text.hashCode()
    }

    fun round(value: Double, digits: Int): PlainNumber {
        val d = BigDecimal.valueOf(value).setScale(digits, RoundingMode.HALF_UP).stripTrailingZeros()
        return PlainNumber(if (d.signum() == 0) "0" else d.toPlainString())
    }

    /** Bir haritayı biçime sokar; null değerler atılır. */
    fun normalizeMap(map: Map<String, Any?>): Map<String, Any?> {
        val out = TreeMap<String, Any?>()
        for ((k, v) in map) {
            val n = normalize(k, v) ?: continue
            out[k] = n
        }
        return out
    }

    private fun normalize(key: String?, value: Any?): Any? = when (value) {
        null -> null
        is Map<*, *> -> if (key == "box") box(value) else normalizeMap(value.entries.associate { it.key.toString() to it.value })
        is Iterable<*> -> value.mapNotNull { normalize(null, it) }
        is Array<*> -> value.mapNotNull { normalize(null, it) }
        is PlainNumber -> value
        is Double, is Float -> number(key, (value as Number).toDouble())
        else -> value
    }

    private fun number(key: String?, d: Double): Any? {
        if (d.isNaN() || d.isInfinite()) return null
        return when (key) {
            "light" -> round(d.coerceIn(0.0, 1.0), 2)
            "alpha" -> round(d.coerceIn(0.0, 1.0), 2)
            "line" -> round(d.coerceIn(0.0, 1.0), 4)
            "angle" -> if (kotlin.math.abs(d) > 0.3) round(d, 1) else null
            else -> round(d, 4)
        }
    }

    private fun box(m: Map<*, *>): Map<String, Any?> {
        val out = TreeMap<String, Any?>()
        for ((k, v) in m) {
            val key = k.toString()
            val n = v as? Number ?: continue
            val d = n.toDouble()
            if (d.isNaN() || d.isInfinite()) continue
            out[key] = if (key in BOX_SIDES) round(d.coerceIn(0.0, 1.0), 4) else round(d, 4)
        }
        return out
    }

    /** Uzantı mesajı: `{"app":"nino","type":<tür>, ...alanlar}`; alanlar önceden [normalizeMap]'ten geçmiş olmalı. */
    fun extension(type: String, fields: Map<String, Any?>): String {
        val o = TreeMap<String, Any?>(fields)
        o["app"] = "nino"; o["type"] = type
        return Json.write(o)
    }

    fun bytes(s: String) = s.toByteArray(Charsets.UTF_8).size

    /** `cover` ile 512 KB'ı aşan show'dan `cover` atılır. */
    fun fitShow(p: ShowPayload): ShowPayload {
        if ("cover" !in p.extras) return p
        if (bytes(NinoMessage.Show(p).encode()) <= MAX_COVER_MESSAGE_BYTES) return p
        return p.copy(extras = p.extras - "cover")
    }

    /** screen alanları: en çok 30 öğe; 16 KB'a sığmazsa sondan öğe atılır. */
    fun fitScreen(items: List<Map<String, Any?>>, durationMs: Int, overlay: Boolean): Map<String, Any?> {
        var list = items.take(MAX_SCREEN_ITEMS)
        fun fields(l: List<Map<String, Any?>>): Map<String, Any?> = TreeMap<String, Any?>().also {
            it["durationMs"] = durationMs
            it["items"] = l
            if (overlay) it["overlay"] = true
        }
        while (list.isNotEmpty() && bytes(extension("screen", fields(list))) > MAX_COMPACT_MESSAGE_BYTES) list = list.dropLast(1)
        return fields(list)
    }
}
