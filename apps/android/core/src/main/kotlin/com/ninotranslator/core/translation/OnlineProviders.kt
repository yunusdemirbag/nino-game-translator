// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import com.ninotranslator.core.http.HttpRequest
import com.ninotranslator.core.http.HttpResponse
import com.ninotranslator.core.http.HttpTimeoutException
import com.ninotranslator.core.http.HttpTransport
import com.ninotranslator.core.json.Json
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible
import java.io.IOException

/** Anahtar/çeviri hata durumları (ceviri.md 7). */
enum class KeyStatus { VALID, INVALID_KEY, QUOTA, MODEL_REJECTED, UNREACHABLE;
    /** Anahtar kaydedilebilir mi: geçerli, kotası dolmuş ya da modeli reddedilmiş anahtar kabul edilir. */
    val acceptable: Boolean get() = this == VALID || this == QUOTA || this == MODEL_REJECTED
}

/** Çevrimiçi çevirmen hatası. [rateLimitedMs] doluysa dakikalık sınır (uyarı gösterilmez). */
class OnlineError(val status: KeyStatus, val rateLimitedMs: Long? = null, message: String? = null) : Exception(message ?: status.name)

/** Bir istekteki önceki satır (bağlam). */
data class ContextLine(val source: String, val translation: String?)

/** Bir çevrimiçi istek. [terms] her cümlede bulunan sözlük terimleri (yalnız Türkçe). */
data class OnlineRequest(
    val sentences: List<String>,
    val target: TargetLanguage,
    val context: List<ContextLine> = emptyList(),
    val game: String? = null,
    val terms: List<List<Glossary.Hit>> = emptyList(),
)

/** Çevrimiçi çevirmen: tek istekte bütün cümleler. */
interface OnlineEngine {
    val service: OnlineService
    /** Önbellek motor adı (`deepl`, `gemini:<model>` …). */
    val cacheName: String
    fun supports(target: TargetLanguage): Boolean
    /** Engelleyici; [OnlineError] atar. Dönen liste cümle sayısı kadardır. */
    fun translate(request: OnlineRequest): List<String>
    fun testKey(): KeyStatus
}

suspend fun OnlineEngine.translateAsync(request: OnlineRequest): List<String> = runInterruptible(Dispatchers.IO) { translate(request) }

internal fun send(http: HttpTransport, r: HttpRequest): HttpResponse = try {
    http.send(r)
} catch (e: HttpTimeoutException) {
    throw OnlineError(KeyStatus.UNREACHABLE, message = "zaman aşımı")
} catch (e: IOException) {
    throw OnlineError(KeyStatus.UNREACHABLE, message = e.message)
}

// ============================ Çeviri hizmeti 1 (DeepL) ============================

class DeepLEngine(private val key: String, private val http: HttpTransport, private val timeoutMs: Int = 4_000) : OnlineEngine {
    override val service = OnlineService.DEEPL
    override val cacheName = "deepl"
    val baseUrl: String get() = if (key.trim().endsWith(":fx")) "https://api-free.deepl.com/v2/" else "https://api.deepl.com/v2/"
    override fun supports(target: TargetLanguage) = target in TargetLanguage.DEEPL_TARGETS

    private val headers get() = mapOf("Authorization" to "DeepL-Auth-Key ${key.trim()}")

    fun requestBody(r: OnlineRequest): String {
        val hasTerms = r.terms.any { it.isNotEmpty() }
        val texts = r.sentences.mapIndexed { i, s -> if (hasTerms) markTerms(s, r.terms.getOrNull(i).orEmpty()) else s }
        val body = linkedMapOf<String, Any?>(
            "text" to texts,
            "source_lang" to "EN",
            "target_lang" to r.target.code.uppercase(),
        )
        if (r.context.isNotEmpty()) body["context"] = r.context.takeLast(3).joinToString("\n") { it.source }
        if (r.target.isTurkish) body["formality"] = "prefer_less"
        body["preserve_formatting"] = true
        if (hasTerms) { body["tag_handling"] = "xml"; body["ignore_tags"] = listOf("x") }
        return Json.write(body)
    }

    override fun translate(request: OnlineRequest): List<String> {
        val r = send(http, HttpRequest.json(baseUrl + "translate", requestBody(request), headers, timeoutMs, timeoutMs))
        if (!r.ok) throw OnlineError(statusOf(r.status))
        val list = (runCatching { Json.parseObject(r.text) }.getOrNull()?.get("translations") as? List<*>)
            ?.map { ((it as? Map<*, *>)?.get("text") as? String) ?: throw OnlineError(KeyStatus.UNREACHABLE) }
            ?: throw OnlineError(KeyStatus.UNREACHABLE, message = "bozuk cevap")
        if (list.size != request.sentences.size) throw OnlineError(KeyStatus.UNREACHABLE, message = "sayı tutmuyor")
        val hasTerms = request.terms.any { it.isNotEmpty() }
        return if (hasTerms) list.map(::unmark) else list
    }

    override fun testKey(): KeyStatus = try {
        val r = send(http, HttpRequest(baseUrl + "usage", headers = headers, connectTimeoutMs = 6_000, readTimeoutMs = 6_000))
        if (!r.ok) statusOf(r.status) else {
            val m = runCatching { Json.parseObject(r.text) }.getOrNull()
            val used = (m?.get("character_count") as? Number)?.toLong(); val limit = (m?.get("character_limit") as? Number)?.toLong()
            if (used != null && limit != null && used >= limit) KeyStatus.QUOTA else KeyStatus.VALID
        }
    } catch (e: OnlineError) { e.status }

    companion object {
        fun statusOf(code: Int) = when (code) { 401, 403 -> KeyStatus.INVALID_KEY; 456 -> KeyStatus.QUOTA; else -> KeyStatus.UNREACHABLE }

        fun escapeXml(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        fun unescapeXml(s: String) = s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'").replace("&amp;", "&")

        /** Terim Türkçesiyle değiştirilip `<x>…</x>` içine alınır; metin XML için kaçışlanır. */
        fun markTerms(s: String, hits: List<Glossary.Hit>): String {
            val out = StringBuilder(); var last = 0
            for (h in hits.sortedBy { it.start }) {
                out.append(escapeXml(s.substring(last, h.start))).append("<x>").append(escapeXml(h.target)).append("</x>")
                last = h.end
            }
            out.append(escapeXml(s.substring(last)))
            return out.toString()
        }

        fun unmark(s: String) = unescapeXml(s.replace("<x>", "").replace("</x>", ""))
    }
}

// ============================ Yapay zekâ hizmetleri ============================

/** Dakikalık istek hakkı: kayan 60 sn pencere; uygulama genelinde model başına ortak. */
object RequestWindows {
    private class Window(var limit: Int) { val times = ArrayDeque<Long>() }
    private val windows = HashMap<String, Window>()

    /** Hak varsa sayar ve true döner. [force] hak bitse de gönderir (ama sayar). */
    @Synchronized fun take(model: String, perMinute: Int?, now: Long, force: Boolean = false): Boolean {
        val w = windows.getOrPut(model) { Window(perMinute ?: Int.MAX_VALUE) }
        if (perMinute != null && perMinute < w.limit && w.limit == Int.MAX_VALUE) w.limit = perMinute
        while (w.times.isNotEmpty() && now - w.times.first() >= 60_000) w.times.removeFirst()
        if (!force && w.times.size >= w.limit) return false
        w.times.addLast(now)
        return true
    }

    /** Sunucunun bildirdiği dakikalık sınır yalnız düşürür. */
    @Synchronized fun lower(model: String, perMinute: Int) {
        val w = windows.getOrPut(model) { Window(perMinute) }
        if (perMinute in 1 until w.limit) w.limit = perMinute
    }

    @Synchronized fun limit(model: String): Int? = windows[model]?.limit?.takeIf { it != Int.MAX_VALUE }

    @Synchronized fun reset() = windows.clear()
}

class AiEngine(
    override val service: OnlineService,
    val model: AiModels.Model,
    private val key: String,
    private val http: HttpTransport,
    private val now: () -> Long = System::currentTimeMillis,
    private val timeoutMs: Int = 5_000,
) : OnlineEngine {
    init { require(service != OnlineService.DEEPL) }

    override val cacheName: String = "${service.modelGroup}:${model.id}"
    override fun supports(target: TargetLanguage) = true

    data class Prompt(val system: String, val user: String, val maxTokens: Int)

    fun prompt(r: OnlineRequest, maxTokens: Int = 1024): Prompt {
        val user = StringBuilder()
        r.game?.takeIf { it.isNotBlank() }?.let { user.append("Game: ").append(it).append("\n\n") }
        val ctx = r.context.takeLast(3)
        if (ctx.isNotEmpty()) {
            user.append("Previous subtitle lines, for context only (do not translate them):\n")
            for (c in ctx) {
                user.append("English: ").append(c.source).append('\n')
                c.translation?.let { user.append("Translation: ").append(it).append('\n') }
            }
            user.append('\n')
        }
        user.append("Render the following ").append(r.sentences.size).append(" subtitle sentence(s) in ").append(languageName(r.target))
            .append(". Your whole answer must be a JSON array of exactly ").append(r.sentences.size)
            .append(" string(s), kept in the input order, with nothing else around it.\n")
        user.append(Json.write(r.sentences))
        return Prompt(systemInstruction(r.target), user.toString(), maxTokens)
    }

    fun endpoint(): String = when (service) {
        OnlineService.GEMINI -> "https://generativelanguage.googleapis.com/v1beta/models/${model.id}:generateContent"
        OnlineService.OPENAI -> "https://api.openai.com/v1/chat/completions"
        OnlineService.CLAUDE -> "https://api.anthropic.com/v1/messages"
        else -> error("yapay zekâ değil")
    }

    fun headers(): Map<String, String> = when (service) {
        OnlineService.GEMINI -> mapOf("x-goog-api-key" to key.trim())
        OnlineService.OPENAI -> mapOf("Authorization" to "Bearer ${key.trim()}")
        OnlineService.CLAUDE -> mapOf("x-api-key" to key.trim(), "anthropic-version" to "2023-06-01")
        else -> emptyMap()
    }

    fun body(p: Prompt): String = Json.write(when (service) {
        OnlineService.GEMINI -> linkedMapOf(
            "systemInstruction" to mapOf("parts" to listOf(mapOf("text" to p.system))),
            "contents" to listOf(linkedMapOf("role" to "user", "parts" to listOf(mapOf("text" to p.user)))),
            "generationConfig" to linkedMapOf<String, Any?>("maxOutputTokens" to p.maxTokens).also { g ->
                model.thinking?.let { g["thinkingConfig"] = mapOf("thinkingLevel" to it) }
            },
        )
        OnlineService.OPENAI -> linkedMapOf<String, Any?>(
            "model" to model.id,
            "messages" to listOf(mapOf("role" to "developer", "content" to p.system), mapOf("role" to "user", "content" to p.user)),
            "max_completion_tokens" to p.maxTokens,
        ).also { b -> model.effort?.let { b["reasoning_effort"] = it } }
        OnlineService.CLAUDE -> linkedMapOf<String, Any?>(
            "model" to model.id,
            "max_tokens" to p.maxTokens,
            "system" to p.system,
            "messages" to listOf(mapOf("role" to "user", "content" to p.user)),
        ).also { b ->
            model.effort?.let { b["output_config"] = mapOf("effort" to it) }
            model.thinking?.let { b["thinking"] = mapOf("type" to it) }
        }
        else -> error("yapay zekâ değil")
    })

    /** Cevap gövdesinden modelin metni; boşsa null. */
    fun extractText(json: String): String? {
        val root = runCatching { Json.parseObject(json) }.getOrNull() ?: return null
        val text = when (service) {
            OnlineService.GEMINI -> {
                val parts = (((root["candidates"] as? List<*>)?.firstOrNull() as? Map<*, *>)?.get("content") as? Map<*, *>)?.get("parts") as? List<*>
                parts?.mapNotNull { p -> (p as? Map<*, *>)?.takeIf { it["thought"] != true }?.get("text") as? String }?.joinToString("")
            }
            OnlineService.OPENAI -> (((root["choices"] as? List<*>)?.firstOrNull() as? Map<*, *>)?.get("message") as? Map<*, *>)?.get("content") as? String
            OnlineService.CLAUDE -> (root["content"] as? List<*>)?.mapNotNull { b -> (b as? Map<*, *>)?.takeIf { it["type"] == "text" }?.get("text") as? String }?.joinToString("")
            else -> null
        }
        return text?.takeIf { it.isNotBlank() }
    }

    /** Hata durumunu cevaptan çıkarır; dakikalık sınırsa [OnlineError.rateLimitedMs] dolu. */
    fun errorOf(r: HttpResponse): OnlineError {
        val body = r.text
        val low = body.lowercase()
        if (service == OnlineService.GEMINI && r.status == 429) perMinuteLimit(body)?.let { return it }
        val status = when {
            r.status == 401 || r.status == 403 -> KeyStatus.INVALID_KEY
            r.status == 402 || r.status == 429 -> KeyStatus.QUOTA
            r.status == 400 && ("api_key_invalid" in low || "api key not valid" in low) -> KeyStatus.INVALID_KEY
            r.status == 400 && ("credit balance" in low || "insufficient_quota" in low) -> KeyStatus.QUOTA
            r.status == 400 || r.status == 404 -> KeyStatus.MODEL_REJECTED
            else -> KeyStatus.UNREACHABLE
        }
        return OnlineError(status)
    }

    /** Hizmet A'nın 429 cevabı: kota ihlali kimliklerinde "PerMinute" var ve hiçbirinde "PerDay" yoksa dakikalık sınır. */
    private fun perMinuteLimit(body: String): OnlineError? {
        val details = ((runCatching { Json.parseObject(body) }.getOrNull()?.get("error") as? Map<*, *>)?.get("details") as? List<*>) ?: return null
        val violations = details.flatMap { d -> ((d as? Map<*, *>)?.get("violations") as? List<*>).orEmpty() }.mapNotNull { it as? Map<*, *> }
        val ids = violations.mapNotNull { it["quotaId"] as? String }
        if (ids.none { "PerMinute" in it } || ids.any { "PerDay" in it }) return null
        val delay = details.firstNotNullOfOrNull { d -> (d as? Map<*, *>)?.get("retryDelay") as? String }
            ?.removeSuffix("s")?.toDoubleOrNull()?.let { (it * 1000).toLong() }
        violations.firstOrNull { (it["quotaId"] as? String)?.let { id -> "PerMinute" in id && "Request" in id } == true }
            ?.let { v -> (v["quotaValue"] as? String)?.toIntOrNull() ?: (v["quotaValue"] as? Number)?.toInt() }
            ?.let { RequestWindows.lower(model.id, it) }
        return OnlineError(KeyStatus.QUOTA, rateLimitedMs = (delay ?: 1_000L).coerceIn(1_000L, 20_000L))
    }

    private fun call(p: Prompt, timeout: Int): String {
        val r = send(http, HttpRequest.json(endpoint(), body(p), headers(), timeout, timeout))
        if (!r.ok) throw errorOf(r)
        return extractText(r.text) ?: throw OnlineError(KeyStatus.UNREACHABLE, message = "boş cevap")
    }

    override fun translate(request: OnlineRequest): List<String> {
        if (!RequestWindows.take(model.id, model.requestsPerMinute, now())) throw OnlineError(KeyStatus.QUOTA, rateLimitedMs = 1_000L, message = "dakikalık hak bitti")
        val text = call(prompt(request), timeoutMs)
        return decode(text, request.sentences.size) ?: throw OnlineError(KeyStatus.UNREACHABLE, message = "cevap çözülemedi")
    }

    /** "Ekranı çevir": tek istekte en çok 40 parça, 8192 jeton, 30 sn; hak bitse de gönderilir ama sayılır. */
    fun translateScreen(pieces: List<String>, target: TargetLanguage, game: String?): List<String> {
        val out = ArrayList<String>()
        for (chunk in pieces.chunked(40)) {
            RequestWindows.take(model.id, model.requestsPerMinute, now(), force = true)
            val text = call(prompt(OnlineRequest(chunk, target, game = game), 8192), 30_000)
            out += decode(text, chunk.size) ?: throw OnlineError(KeyStatus.UNREACHABLE, message = "cevap çözülemedi")
        }
        return out
    }

    override fun testKey(): KeyStatus = try {
        call(prompt(OnlineRequest(listOf(TEST_LINE), TargetLanguage.TR)), 15_000)
        KeyStatus.VALID
    } catch (e: OnlineError) { if (e.rateLimitedMs != null) KeyStatus.QUOTA else e.status }

    companion object {
        const val TEST_LINE = "KRATOS: We go now. Stay close, boy."

        fun languageName(t: TargetLanguage) = when (t) {
            TargetLanguage.TR -> "Turkish"; TargetLanguage.AR -> "Arabic"; TargetLanguage.HI -> "Hindi"; TargetLanguage.ID -> "Indonesian"
            TargetLanguage.TH -> "Thai"; TargetLanguage.VI -> "Vietnamese"; TargetLanguage.UR -> "Urdu"; TargetLanguage.BN -> "Bengali"
            TargetLanguage.MS -> "Malay"; TargetLanguage.TL -> "Filipino"; TargetLanguage.NL -> "Dutch"
        }

        /** Dile göre üç türlü sistem yönergesi. */
        fun systemInstruction(t: TargetLanguage): String = when (t) {
            TargetLanguage.TR -> "Act as a subtitle translator: turn English game dialogue into everyday spoken Turkish. Speak to the player " +
                "with \"sen\", never \"siz\". Keep names, places and speaker labels (such as \"KRATOS:\") exactly as written. " +
                "Keep line breaks. Output only the translation."
            TargetLanguage.AR -> "Act as a subtitle translator: turn English game dialogue into Modern Standard Arabic, brief and natural. " +
                "Write names in Latin letters as written. Use Arabic punctuation and Western digits. Keep controller button symbols " +
                "unchanged. Keep speaker labels and line breaks. Output only the translation."
            else -> "Act as a subtitle translator: turn English game dialogue into everyday spoken ${languageName(t)}, kept brief. " +
                "Write names as written. Keep controller button symbols, speaker labels and line breaks unchanged. Output only the translation."
        }

        private val LEAKED = Regex("<\\|[^|>]{1,40}\\|>|<end_of_turn>|<start_of_turn>(?:model|user)?|</?s>")
        private val FENCE = Regex("^```[a-zA-Z]*\\s*|\\s*```$")
        private val TRAILING_COMMA = Regex(",\\s*]")

        /** Modelin cevabını cümle listesine çözer; sayı tutmazsa null. */
        fun decode(raw: String, count: Int): List<String>? {
            var s = raw.substringAfterLast("</think>")
            s = LEAKED.replace(s, "").trim()
            s = FENCE.replace(s, "").trim()
            s = TRAILING_COMMA.replace(s, "]")
            val open = s.indexOf('[')
            if (open >= 0) {
                val close = s.lastIndexOf(']')
                val firstInside = s.substring(open + 1).trimStart().firstOrNull()
                if (close > open && firstInside == '"') {
                    val arr = runCatching { Json.parse(s.substring(open, close + 1)) }.getOrNull() as? List<*>
                    if (arr != null) {
                        val strings = arr.map { it as? String ?: return null }
                        return if (strings.size == count) strings else null
                    }
                }
                if (close > open && firstInside != '"') {
                    val inner = s.substring(open + 1, close).trim()
                    for (parts in listOf(
                        inner.split('\n'),
                        inner.split(Regex("(?<=[.!?…]),")),
                        inner.split(','),
                    )) {
                        val p = parts.map { it.trim() }.filter { it.isNotEmpty() }
                        if (p.size == count) return p
                    }
                }
            }
            if (count == 1 && s.isNotBlank()) return listOf(s.trim().removeSurrounding("\""))
            return null
        }
    }
}

/** Hizmet ve anahtardan motor. */
object OnlineEngines {
    fun create(service: OnlineService, key: String, http: HttpTransport, models: AiModels?, modelSetting: String?, now: () -> Long = System::currentTimeMillis): OnlineEngine? = when (service) {
        OnlineService.DEEPL -> DeepLEngine(key, http)
        else -> models?.select(service, modelSetting)?.let { AiEngine(service, it, key, http, now) }
    }
}
