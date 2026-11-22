// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import com.ninotranslator.core.json.Json
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * Ayarla tarif edilen genel HTTP çevirmeni (ceviri.md, "Genel HTTP sağlayıcısı").
 * Şablonlarda {text} {source} {target} {key}; gövdede JSON, adreste URL kaçışı.
 */
class HttpTranslationProvider(val configuration: Configuration, private val apiKey: String? = null, private val timeoutMs: Int = 5_000) : TranslationProvider {
    data class Configuration(
        val name: String,
        val urlTemplate: String,
        val method: String = "POST",
        val headers: Map<String, String> = mapOf("Content-Type" to "application/json"),
        val bodyTemplate: String? = null,
        val responsePath: List<String>,
    )

    override val name: String get() = configuration.name

    override suspend fun translate(text: String, source: String, target: String): String = runInterruptible(Dispatchers.IO) {
        val values = mapOf("text" to text, "source" to source, "target" to target, "key" to (apiKey ?: ""))
        val url = fill(configuration.urlTemplate, values) { URLEncoder.encode(it, "UTF-8").replace("+", "%20") }
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = timeoutMs; c.readTimeout = timeoutMs
        c.requestMethod = configuration.method
        for ((k, v) in configuration.headers) c.setRequestProperty(k, fill(v, values) { it })
        try {
            configuration.bodyTemplate?.let { body ->
                c.doOutput = true
                c.outputStream.use { it.write(fill(body, values, ::jsonEscape).toByteArray()) }
            }
            val status = c.responseCode
            if (status !in 200..299) throw TranslationProviderException(TranslationProviderException.Kind.HTTP, status)
            val data = c.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
            val value = extract(data, configuration.responsePath) ?: throw TranslationProviderException(TranslationProviderException.Kind.BAD_RESPONSE)
            if (value.isEmpty()) throw TranslationProviderException(TranslationProviderException.Kind.EMPTY)
            value
        } finally { c.disconnect() }
    }

    companion object {
        fun fill(template: String, values: Map<String, String>, escape: (String) -> String): String {
            var s = template
            for ((k, v) in values) s = s.replace("{$k}", escape(v))
            return s
        }

        fun jsonEscape(s: String): String = Json.quote(s).let { it.substring(1, it.length - 1) }

        fun extract(data: String, path: List<String>): String? {
            var node: Any? = runCatching { Json.parse(data) }.getOrNull() ?: return null
            for (step in path) {
                val i = step.toIntOrNull()
                node = when {
                    i != null && node is List<*> -> if (i in node.indices) node[i] else return null
                    node is Map<*, *> && node.containsKey(step) -> node[step]
                    else -> return null
                }
            }
            return when (node) {
                is String -> node
                is List<*> -> if (node.all { it is String }) node.joinToString("") else null
                else -> null
            }
        }
    }
}
