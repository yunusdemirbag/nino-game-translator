// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import com.ninotranslator.core.json.Json
import java.io.File

/**
 * Telefon mesajlarının dil başına kalıcı hafızası (okuma.md 9): `<dizin>/<dil>.json`, anahtar → çeviri.
 * 5000 kaydı aşınca boşaltılır.
 */
class PhoneMessageMemory(private val dir: File, private val language: String, private val max: Int = MAX) {
    private var map: LinkedHashMap<String, String>? = null
    private val file get() = File(dir, "$language.json")

    @Synchronized fun get(text: String): String? = load()[LiveText.key(text)]

    @Synchronized fun put(text: String, translation: String) {
        val m = load()
        if (m.size >= max) m.clear()
        m[LiveText.key(text)] = translation
        runCatching {
            dir.mkdirs()
            val tmp = File(dir, "$language.json.tmp")
            tmp.writeText(Json.write(m))
            if (!tmp.renameTo(file)) { file.delete(); tmp.renameTo(file) }
        }
    }

    @Synchronized fun size() = load().size

    private fun load(): LinkedHashMap<String, String> = map ?: LinkedHashMap<String, String>().also { m ->
        runCatching { (Json.parse(file.readText()) as? Map<*, *>)?.forEach { (k, v) -> if (k is String && v is String) m[k] = v } }
        map = m
    }

    companion object {
        const val MAX = 5000
        const val DIR = "phone-messages"
    }
}

/** Telefon uygulamalarının sabit Türkçeleri (yalnız Türkçede; okuma.md 9 "Sabit sözlük"). */
object PhoneFixedTurkish {
    private val MAP = mapOf(
        "book ryde" to "Ryde çağır",
        "change destination" to "Hedefi değiştir",
        "your ryde is on the way" to "Ryde'ın yolda",
        "your ryde has arrived" to "Ryde'ın geldi",
        "cancel ryde" to "Ryde'ı iptal et",
        "steps today" to "Bugünkü adımlar",
        "calories" to "Kalori",
        "workout" to "Antrenman",
        "distance" to "Mesafe",
        "daily goal" to "Günlük hedef",
        "new message" to "Yeni mesaj",
        "balance" to "Bakiye",
        "send money" to "Para gönder",
        "request money" to "Para iste",
    )

    fun get(text: String): String? {
        val k = text.lowercase().replace(Regex("\\(.*?\\)"), "").replace(Regex("[^a-z ]"), " ").replace(Regex("\\s+"), " ").trim()
        return MAP[k]
    }
}
