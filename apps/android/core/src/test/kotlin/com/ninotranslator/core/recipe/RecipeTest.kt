// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.recipe

import com.ninotranslator.core.engine.EngineEvent
import com.ninotranslator.core.engine.NinoEngine
import com.ninotranslator.core.engine.SubtitleOutput
import com.ninotranslator.core.json.Json
import com.ninotranslator.core.link.ShowPayload
import com.ninotranslator.core.packs.TranslationPack
import com.ninotranslator.core.reading.NoiseFilter
import com.ninotranslator.core.reading.NormalizedRect
import com.ninotranslator.core.reading.ReadingPipeline
import com.ninotranslator.core.reading.RecognizedLine
import com.ninotranslator.core.reading.SentenceSplitter
import com.ninotranslator.core.reading.Stabilizer
import com.ninotranslator.core.reading.StabilizerEvent
import com.ninotranslator.core.reading.SubtitleEvent
import com.ninotranslator.core.reading.TextSimilarity
import com.ninotranslator.core.translation.HttpTranslationProvider
import com.ninotranslator.core.translation.ProviderChain
import com.ninotranslator.core.translation.Term
import com.ninotranslator.core.translation.TermProtector
import com.ninotranslator.core.translation.TranslationCache
import com.ninotranslator.core.translation.TranslationOrigin
import com.ninotranslator.core.translation.TranslationProvider
import com.ninotranslator.core.translation.Translator
import com.ninotranslator.core.translation.TurkishPostProcessor
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** NinoCore tariflerindeki (okuma-hatti, ceviri, paket, motor) örnekler. */
class RecipeTest {
    private fun line(t: String, y: Double = 0.8, c: Float = 0.9f) = RecognizedLine(t, c, NormalizedRect(0.3, y, 0.4, 0.05))

    @Test fun noise() {
        val f = NoiseFilter()
        for (t in listOf("A", "3", ">>", "—", "[X] 12/40", "Options", "  MENU ")) assertTrue(t, f.isNoise(line(t)))
        for (t in listOf("No.", "Go!", "Hm?")) assertFalse(t, f.isNoise(line(t)))
        assertTrue(f.isNoise(line("Hello there", c = 0.3f)))
        assertEquals("First line. Second line.", f.text(listOf(line("Second line.", 0.85), line("First   line.", 0.75), line("Outside", 0.1)), NormalizedRect.DEFAULT_SUBTITLE))
    }

    @Test fun splitter() {
        val s = SentenceSplitter()
        assertEquals(listOf("Wait... what?"), s.split("Wait... what?"))
        assertEquals(listOf("Wait...", "What?"), s.split("Wait... What?"))
        assertEquals(listOf("It is 3.5 meters."), s.split("It is 3.5 meters."))
        assertEquals(listOf("Mr. Smith is here.", "Go."), s.split("Mr. Smith is here. Go."))
        assertEquals(listOf("- Run!", "- Where?"), s.split("- Run! - Where?"))
        assertEquals(listOf("\"Stop.\"", "Now."), s.split("\"Stop.\" Now."))
    }

    @Test fun similarity() {
        assertTrue(TextSimilarity.isSame("Hello there", "Hel1o there", 0.85))
        assertFalse(TextSimilarity.isSame("Hello there, my friend.", "Hello there, my friend. Go.", 0.85))
    }

    @Test fun stabilizerRules() {
        val st = Stabilizer()
        assertEquals(emptyList<StabilizerEvent>(), st.observe("Hello there"))
        st.observe(null) // tek boş kare adayı bozmaz
        assertEquals(emptyList<StabilizerEvent>(), st.observe("Hel1o there"))
        assertEquals(listOf(StabilizerEvent.Stabilized("Hello there", 4)), st.observe("Hello there"))
        assertEquals(emptyList<StabilizerEvent>(), st.observe(null))
        assertEquals(listOf(StabilizerEvent.Disappeared("Hello there")), st.observe(null))
    }

    @Test fun pipelineContinuationAndRepeat() {
        val p = ReadingPipeline()
        fun frame(t: String?) = p.process(if (t == null) emptyList() else listOf(line(t)))
        repeat(2) { frame("Hello there.") }
        val first = frame("Hello there.").single() as SubtitleEvent.Started
        assertEquals(1, first.subtitle.id)
        frame("Hello there. How are you?")
        assertTrue(frame("Hello there. How are you?").single() is SubtitleEvent.Ended)
        val events = frame("Hello there. How are you?")
        val started = events.filterIsInstance<SubtitleEvent.Started>().single().subtitle
        assertTrue(started.isContinuation)
        assertEquals(listOf("How are you?"), started.newSentences)
        repeat(2) { frame(null) }
        repeat(3) { frame("Hello there.") }
        // geri dönen yazı yeniden başlar ve tekrar sayılır
        frame(null); frame(null)
        val again = (1..3).flatMap { frame("Hello there.") }.filterIsInstance<SubtitleEvent.Started>().single().subtitle
        assertTrue(again.isRepeat)
    }

    @Test fun postProcessor() {
        val pp = TurkishPostProcessor()
        assertEquals("Tamam, gidelim.", pp.process("tamam ,gidelim", "Okay, let's go."))
        assertEquals("İyi...", pp.process("iyi....", "Fine..."))
        assertEquals("Neden?", pp.process("neden", "Why?"))
        assertEquals("Bekle.", pp.process("bekle..", "Wait."))
    }

    @Test fun termProtector() {
        val tp = TermProtector(listOf(Term("Osk"), Term("Vale Harbor", "Vale Limanı")))
        val p = tp.protect("Osk went to vale harbor. Oskar stays.")
        assertEquals("⟦1⟧ went to ⟦0⟧. Oskar stays.", p.text)
        assertEquals("Osk Vale Limanı'na gitti.", tp.restore("⟦1⟧ ⟦0⟧'na gitti.", p))
        assertNull(tp.restore("⟦1⟧ gitti.", p))
    }

    private class Fake(override val name: String, val answer: (String) -> String) : TranslationProvider {
        var calls = 0
        override suspend fun translate(text: String, source: String, target: String): String { calls++; return answer(text) }
    }

    @Test fun chainFallsBackAndRests() = runBlocking {
        var now = 0L
        val broken = Fake("p1") { error("down") }
        val same = Fake("p2") { it }
        val good = Fake("p3") { "çeviri" }
        val chain = ProviderChain(listOf(broken, same, good), now = { now })
        repeat(3) { assertEquals("p3", chain.translate("text", "en", "tr")!!.provider) }
        assertEquals(listOf("p1"), chain.resting())
        chain.translate("text", "en", "tr")
        assertEquals(3, broken.calls)
        now += 60_001
        chain.translate("text", "en", "tr")
        assertEquals(4, broken.calls)
    }

    @Test fun chainTimeout() = runBlocking {
        val slow = object : TranslationProvider {
            override val name = "slow"
            override suspend fun translate(text: String, source: String, target: String): String { delay(5_000); return "x" }
        }
        assertNull(ProviderChain(listOf(slow), timeoutMs = 50).translate("a", "en", "tr"))
    }

    @Test fun translatorOrderAndCache() = runBlocking {
        val dir = createTempDir()
        val file = File(dir, "cache/translations.json")
        val provider = Fake("http-1") { t -> if (t.contains("⟦0⟧")) "⟦0⟧ geldi" else "merhaba" }
        val pack = TranslationPack(TranslationPack.Game("ornek-oyun"), terms = listOf(Term("Osk")),
            lines = listOf(TranslationPack.Line("Come here.", "Buraya gel.")))
        val tr = Translator(TranslationCache(file), ProviderChain(listOf(provider)), pack, saveEvery = 1)
        assertEquals(TranslationOrigin.Pack, tr.translate("come here.").origin)
        assertEquals("Osk!", tr.translate("Osk!").text)
        assertEquals(0, provider.calls)
        val t = tr.translate("Osk came")
        assertEquals("Osk geldi", t.text)
        assertEquals(TranslationOrigin.Provider("http-1"), t.origin)
        assertEquals(TranslationOrigin.Cache, tr.translate("osk   came").origin)
        assertTrue(file.isFile)
        assertEquals("Osk geldi", TranslationCache(file).lookup("Osk came"))
    }

    @Test fun packFileAndFuzzy() {
        val json = """{"nino":1,"game":{"id":"ornek-oyun","version":"1.0"},"terms":[{"source":"Osk"}],
            "lines":[{"source":"We need to leave the harbor tonight.","target":"Bu gece limandan ayrılmalıyız."},
                     {"source":"We need to leave the harbor tonight.","target":"tekrar"},{"source":"","target":"boş"}]}"""
        val pack = TranslationPack.parse(json)
        assertEquals(2, pack.warnings)
        assertEquals("Bu gece limandan ayrılmalıyız.", pack.lookup("We need to 1eave the harbor tonight."))
        assertNull(pack.lookup("We need to leave the harbor tonight?"))
        assertEquals(pack.lines, TranslationPack.parse(pack.encode()).lines)
        val bad = runCatching { TranslationPack.parse("""{"nino":2,"game":{"id":"x"},"lines":[]}""") }.exceptionOrNull()
        assertTrue(bad is TranslationPack.LoadException.UnsupportedVersion)
    }

    @Test fun httpProviderTemplates() {
        assertEquals("a\\\"b\\nc", HttpTranslationProvider.jsonEscape("a\"b\nc"))
        assertEquals("Merhaba", HttpTranslationProvider.extract("""{"data":[{"text":"Merhaba"}]}""", listOf("data", "0", "text")))
        assertEquals("Merhaba", HttpTranslationProvider.extract("""["Mer","haba"]""", emptyList()))
        assertNull(HttpTranslationProvider.extract("""{"data":[]}""", listOf("data", "0")))
    }

    @Test fun jsonParsesAndWrites() {
        val v = Json.parse("""{"a":[1,2.5,"xç",true,null],"b":{"c":"\"q\""}}""") as Map<*, *>
        assertEquals(listOf(1L, 2.5, "xç", true, null), v["a"])
        assertEquals("""{"a":[1,2.5,"xç",true,null],"b":{"c":"\"q\""}}""", Json.write(v))
    }

    private class Recorder : SubtitleOutput {
        val log = mutableListOf<String>()
        override suspend fun show(payload: ShowPayload) { synchronized(log) { log += "show:${payload.id}:${payload.text}" } }
        override suspend fun clear(id: Int?) { synchronized(log) { log += "clear:$id" } }
    }

    @Test fun engineShowsAndClears() = runBlocking {
        val out = Recorder()
        val engine = NinoEngine(ReadingPipeline(), Translator(chain = ProviderChain(listOf(Fake("p") { "Selam." }))), out)
        val events = mutableListOf<EngineEvent>()
        val job = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Default).launchCollect(engine, events)
        repeat(3) { engine.processLines(listOf(line("Hello."))) }
        engine.waitUntilIdle()
        repeat(2) { engine.processLines(emptyList()) }
        engine.waitUntilIdle()
        kotlinx.coroutines.withTimeout(2_000) { while (synchronized(out.log) { out.log.size } < 2) delay(10) }
        assertEquals(listOf("show:1:Selam.", "clear:1"), out.log)
        job.cancel()
        engine.close()
    }

    private fun kotlinx.coroutines.CoroutineScope.launchCollect(e: NinoEngine, into: MutableList<EngineEvent>) =
        launch { e.events.collect { synchronized(into) { into += it } } }

    private fun createTempDir(): File = kotlin.io.path.createTempDirectory("nino").toFile()
}
