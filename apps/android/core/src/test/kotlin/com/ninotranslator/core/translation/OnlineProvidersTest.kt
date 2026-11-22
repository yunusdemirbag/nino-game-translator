// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import com.ninotranslator.core.json.Json
import com.ninotranslator.core.packs.TestFiles
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File

@Suppress("UNCHECKED_CAST")
class OnlineProvidersTest {
    /** Uygulamayla gelen model listesi (Nino'nun kendi dosyası). */
    private val models = AiModels.parse(File(TestFiles.assets, "ai-models.json").readText())
    @Before fun reset() = RequestWindows.reset()

    @Test fun aiModelsFile() {
        for (s in listOf(OnlineService.GEMINI, OnlineService.OPENAI, OnlineService.CLAUDE)) {
            val list = models.models(s)
            assertTrue("$s modeli yok", list.isNotEmpty())
            assertEquals("$s kimlikleri tekrar etmemeli", list.size, list.map { it.id }.toSet().size)
            assertTrue(list.all { it.id.isNotBlank() && it.label.isNotBlank() })
        }
        val g = models.models(OnlineService.GEMINI)
        // Ücretsiz katmandaki modellerin dakikalık sınırı olmalı (aşılırsa satır cihaz içine düşer).
        assertTrue(g.all { !it.freeTier || (it.requestsPerMinute ?: 0) > 0 })
        assertEquals(g[0], models.select(OnlineService.GEMINI, "yok-boyle-model"))
        assertEquals(g[1], models.select(OnlineService.GEMINI, g[1].id))
        assertTrue(models.models(OnlineService.DEEPL).isEmpty())
        // `_about` gibi dizi olmayan alanlar atlanır.
        assertEquals(setOf("gemini", "openai", "claude"), models.byService.keys)
        val inline = AiModels.parse("""{"_about":"x","gemini":[{"id":"m1","label":"l","thinking":"LOW","freeTier":true,"requestsPerMinute":5},{"label":"kimliksiz"}]}""")
        assertEquals(listOf(AiModels.Model("m1", "l", null, "LOW", true, 5)), inline.models(OnlineService.GEMINI))
    }

    @Test fun deepLRequestAndTerms() {
        val http = FakeHttp { FakeHttp.json(200, """{"translations":[{"text":"<x>işaret fişeği</x> ateşle!"},{"text":"Koş &amp; saklan"}]}""") }
        val e = DeepLEngine("abc:fx", http)
        val g = Glossary.parse("""{"terms":{"flare gun":"işaret fişeği"}}""")
        val s = listOf("Fire a flare gun!", "Run & hide")
        val out = e.translate(OnlineRequest(s, TargetLanguage.TR, listOf(ContextLine("A", null), ContextLine("B", null)), null, s.map(g::find)))
        assertEquals(listOf("işaret fişeği ateşle!", "Koş & saklan"), out)
        val r = http.requests.single()
        assertEquals("https://api-free.deepl.com/v2/translate", r.url)
        assertEquals("DeepL-Auth-Key abc:fx", r.headers["Authorization"])
        val body = Json.parseObject(r.bodyText)
        assertEquals(listOf("Fire a <x>işaret fişeği</x>!", "Run &amp; hide"), body["text"])
        assertEquals("TR", body["target_lang"]); assertEquals("prefer_less", body["formality"]); assertEquals("xml", body["tag_handling"])
        assertEquals(listOf("x"), body["ignore_tags"]); assertEquals("A\nB", body["context"]); assertEquals(true, body["preserve_formatting"])
        assertEquals("https://api.deepl.com/v2/", DeepLEngine("abc", http).baseUrl)
        assertFalse(e.supports(TargetLanguage.HI)); assertTrue(e.supports(TargetLanguage.NL))
        val ar = Json.parseObject(e.requestBody(OnlineRequest(listOf("Hi"), TargetLanguage.AR)))
        assertNull(ar["formality"]); assertNull(ar["tag_handling"])
    }

    @Test fun deepLErrorsAndKeyTest() {
        for ((code, status) in listOf(401 to KeyStatus.INVALID_KEY, 403 to KeyStatus.INVALID_KEY, 456 to KeyStatus.QUOTA, 500 to KeyStatus.UNREACHABLE)) {
            val e = DeepLEngine("k", FakeHttp { FakeHttp.json(code, "{}") })
            assertEquals(status, runCatching { e.translate(OnlineRequest(listOf("x"), TargetLanguage.TR)) }.exceptionOrNull().let { (it as OnlineError).status })
        }
        assertEquals(KeyStatus.QUOTA, DeepLEngine("k", FakeHttp { FakeHttp.json(200, """{"character_count":10,"character_limit":10}""") }).testKey())
        assertEquals(KeyStatus.VALID, DeepLEngine("k", FakeHttp { FakeHttp.json(200, """{"character_count":1,"character_limit":10}""") }).testKey())
        val wrongCount = DeepLEngine("k", FakeHttp { FakeHttp.json(200, """{"translations":[]}""") })
        assertTrue(runCatching { wrongCount.translate(OnlineRequest(listOf("x"), TargetLanguage.TR)) }.isFailure)
    }

    @Test fun aiBodies() {
        val gm = AiModels.Model("gemini-model", "l", thinking = "LOW", freeTier = true, requestsPerMinute = 10)
        val gemini = AiEngine(OnlineService.GEMINI, gm, "key", FakeHttp { error("ağ yok") })
        val p = gemini.prompt(OnlineRequest(listOf("Go!"), TargetLanguage.TR, listOf(ContextLine("Hi", "Selam")), "God of War"))
        assertTrue(p.user.startsWith("Game: God of War"))
        assertTrue(p.user.contains("English: Hi\nTranslation: Selam"))
        assertTrue(p.user.trimEnd().endsWith("[\"Go!\"]"))
        assertTrue(p.system.contains("sen"))
        val gb = Json.parseObject(gemini.body(p))
        assertEquals("LOW", ((gb["generationConfig"] as Map<String, Any?>)["thinkingConfig"] as Map<String, Any?>)["thinkingLevel"])
        assertEquals(1024L, (gb["generationConfig"] as Map<String, Any?>)["maxOutputTokens"])
        assertEquals("https://generativelanguage.googleapis.com/v1beta/models/${gm.id}:generateContent", gemini.endpoint())
        assertEquals("key", gemini.headers()["x-goog-api-key"])
        assertEquals("gemini:${gm.id}", gemini.cacheName)

        val om = AiModels.Model("openai-model", "l", effort = "none")
        val ob = Json.parseObject(AiEngine(OnlineService.OPENAI, om, "k", FakeHttp { error("") }).body(p))
        assertEquals(listOf("developer", "user"), (ob["messages"] as List<Map<String, Any?>>).map { it["role"] })
        assertEquals("none", ob["reasoning_effort"]); assertEquals(1024L, ob["max_completion_tokens"])

        val cm = AiModels.Model("claude-model", "l", effort = "low", thinking = "disabled")
        val claude = AiEngine(OnlineService.CLAUDE, cm, "k", FakeHttp { error("") })
        val cb = Json.parseObject(claude.body(p))
        assertEquals(mapOf("effort" to "low"), cb["output_config"]); assertEquals(mapOf("type" to "disabled"), cb["thinking"])
        assertEquals("2023-06-01", claude.headers()["anthropic-version"])
        assertEquals("Merhaba", claude.extractText("""{"content":[{"type":"thinking","text":"x"},{"type":"text","text":"Merhaba"}]}"""))
        assertEquals("ab", gemini.extractText("""{"candidates":[{"content":{"parts":[{"text":"düşünce","thought":true},{"text":"a"},{"text":"b"}]}}]}"""))
        assertNull(gemini.extractText("""{"candidates":[]}"""))
    }

    @Test fun decodeVariants() {
        assertEquals(listOf("Bir", "İki"), AiEngine.decode("<think>hmm</think>```json\n[\"Bir\", \"İki\",]\n```", 2))
        assertEquals(listOf("Bir.", "İki."), AiEngine.decode("[Bir., İki.]", 2))
        assertEquals(listOf("Bir", "İki"), AiEngine.decode("[Bir\nİki]", 2))
        assertEquals(listOf("Merhaba"), AiEngine.decode("Merhaba<|im_end|>", 1))
        assertNull(AiEngine.decode("[\"Bir\"]", 2))
    }

    @Test fun aiErrorsAndPerMinuteLimit() {
        val m = AiModels.Model("gemini-limit", "l", freeTier = true, requestsPerMinute = 15)
        fun status(code: Int, body: String) = AiEngine(OnlineService.GEMINI, m, "k", FakeHttp { error("") }).errorOf(FakeHttp.json(code, body))
        assertEquals(KeyStatus.INVALID_KEY, status(400, """{"error":{"message":"API key not valid"}}""").status)
        assertEquals(KeyStatus.QUOTA, status(400, "insufficient_quota").status)
        assertEquals(KeyStatus.MODEL_REJECTED, status(404, "{}").status)
        assertEquals(KeyStatus.UNREACHABLE, status(500, "{}").status)
        val daily = status(429, """{"error":{"details":[{"violations":[{"quotaId":"GenerateRequestsPerDayPerProject"}]}]}}""")
        assertNull(daily.rateLimitedMs); assertEquals(KeyStatus.QUOTA, daily.status)
        val perMinute = status(429, """{"error":{"details":[
            {"@type":"type.googleapis.com/google.rpc.QuotaFailure","violations":[{"quotaId":"GenerateRequestsPerMinutePerProjectPerModel","quotaValue":"5"}]},
            {"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"37s"}]}}""")
        assertEquals(20_000L, perMinute.rateLimitedMs)
        assertEquals(5, RequestWindows.limit(m.id))
    }

    @Test fun requestWindow() {
        for (i in 0 until 3) assertTrue(RequestWindows.take("m", 3, 1_000L + i))
        assertFalse(RequestWindows.take("m", 3, 2_000))
        assertTrue(RequestWindows.take("m", 3, 2_000, force = true))
        assertTrue(RequestWindows.take("m", 3, 70_000))
    }
}

class EchoRetryTest {
    @Test fun echoedSentenceUsesOnDeviceAndIsNotCached() = kotlinx.coroutines.runBlocking {
        RequestWindows.reset()
        val model = AiModels.Model("m", "m")
        val http = FakeHttp { FakeHttp.json(200, """{"content":[{"type":"text","text":"[\"Hello there, friend.\"]"}]}""") }
        val cache = LineCache.memory()
        val t = OnlineLineTranslator(AiEngine(OnlineService.CLAUDE, model, "k", http), { cache }, { Glossary.EMPTY }, { 0L }) { _, _ -> "Merhaba dostum." }
        assertEquals("Merhaba dostum.", t.translate("Hello there, friend.", TargetLanguage.TR, emptyList(), null))
        assertEquals(0, cache.size)
    }
}
