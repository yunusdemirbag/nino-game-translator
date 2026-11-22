// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import com.ninotranslator.core.json.Json

/** Kullanıcının kendi anahtarıyla seçebildiği çevrimiçi hizmetler. Adlar ayardaki `engine` değeriyle aynı. */
enum class OnlineService(val settingName: String, val modelGroup: String?) {
    DEEPL("DEEPL", null), GEMINI("GEMINI", "gemini"), OPENAI("OPENAI", "openai"), CLAUDE("CLAUDE", "claude");

    companion object {
        /** `engine` ayarından; `FREE` ya da tanınmayan değer null (cihaz içi). */
        fun of(setting: String?): OnlineService? = values().firstOrNull { it.settingName == setting?.uppercase() }
    }
}

/** `ai-models.json` (ceviri.md 12). */
class AiModels(val byService: Map<String, List<Model>>) {
    data class Model(
        val id: String,
        val label: String,
        val effort: String? = null,
        val thinking: String? = null,
        val freeTier: Boolean = false,
        val requestsPerMinute: Int? = null,
    )

    fun models(service: OnlineService): List<Model> = service.modelGroup?.let { byService[it] }.orEmpty()

    /** Ayardaki model listede yoksa ilk model. */
    fun select(service: OnlineService, setting: String?): Model? = models(service).let { list -> list.firstOrNull { it.id == setting } ?: list.firstOrNull() }

    companion object {
        fun parse(text: String): AiModels {
            val root = Json.parseObject(text)
            val out = LinkedHashMap<String, List<Model>>()
            for ((k, v) in root) {
                val list = v as? List<*> ?: continue // _comment gibi alanlar atlanır
                out[k] = list.mapNotNull { item ->
                    val m = item as? Map<*, *> ?: return@mapNotNull null
                    val id = m["id"] as? String ?: return@mapNotNull null
                    Model(id, m["label"] as? String ?: id, m["effort"] as? String, m["thinking"] as? String,
                        m["freeTier"] as? Boolean ?: false, (m["requestsPerMinute"] as? Number)?.toInt())
                }
            }
            return AiModels(out)
        }
    }
}
