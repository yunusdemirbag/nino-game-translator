// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import com.ninotranslator.core.packs.LegacyPack
import com.ninotranslator.core.packs.LegacyPackLibrary
import com.ninotranslator.core.packs.PackKey
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LineFlowTest {
    private val clock = FakeClock()

    private class FakePool(var poolFirst: Boolean = false, var answer: String? = null, var delayMs: Long = 0) : PoolAccess {
        val memory = HashMap<String, String>()
        val asked = ArrayList<Pair<String, Boolean>>()
        val offered = ArrayList<String>()
        override fun lookup(language: String, key: String) = memory["$language/$key"]
        override fun isPoolFirst(game: String?, language: String) = poolFirst
        override val poolFirstDeadlineMs = 300L
        override suspend fun ask(line: String, language: String, game: String?, context: List<String>, force: Boolean): String? {
            asked += line to force; delay(delayMs); return answer
        }
        override fun offer(line: String, game: String?) { offered += line }
        override val contextLines = 4
    }

    private fun onDevice(t: FakeOnDevice, g: Glossary = Glossary.EMPTY, recent: RecentLines = RecentLines(clock.now)) =
        OnDeviceLineTranslator(t, { LineCache.memory() }.let { f -> val m = HashMap<TargetLanguage, LineCache>(); { l: TargetLanguage -> m.getOrPut(l) { f() } } }, { g }, recent, clock.now)

    private val pack = LegacyPackLibrary(listOf(LegacyPack.parse("""{"format":2,"id":"oyun","entries":{"${PackKey.of("Come here.")}":"Buraya gel."}}""", "oyun")))

    private fun translator(pool: FakePool?, dev: FakeOnDevice, online: OnlineLineTranslator? = null, scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)) =
        LineTranslator(pack, pool, onDevice(dev), online, RecentLines(clock.now), scope)

    @Test fun orderPackPoolOnDevice() = runBlocking {
        val pool = FakePool(); val dev = FakeOnDevice()
        val t = translator(pool, dev)
        assertEquals(LineResult.Origin.PACK, t.translate("Come here.", TranslationSettings())!!.origin)
        // Paketler yalnız Türkçede ve açıkken.
        assertEquals(LineResult.Origin.ON_DEVICE, t.translate("Come here.", TranslationSettings(packsEnabled = false))!!.origin)
        assertEquals("[ar] Come here.", t.translate("Come here.", TranslationSettings(target = TargetLanguage.AR))!!.text)
        pool.memory["tr/" + PackKey.of("Run!")] = "Koş!"
        assertEquals(LineResult.Origin.POOL, t.translate("Run!", TranslationSettings())!!.origin)
        assertEquals(listOf("Come here.", "Run!"), pool.offered.filter { it == "Run!" || it == "Come here." }.distinct().let { listOf("Come here.", "Run!").filter { x -> x in it } })
        // Arap harfli satır çevrilmez.
        assertEquals(LineResult.Origin.SAME_LANGUAGE, t.translate("مرحبا", TranslationSettings(target = TargetLanguage.AR))!!.origin)
        dev.fail = true
        assertNull(t.translate("Something new", TranslationSettings()))
        assertTrue(t.lastFailure != null)
    }

    @Test fun poolFirstAsksEvenWhenSharingOffAndSkipsKeyedEngine() = runBlocking {
        val pool = FakePool(poolFirst = true, answer = "Sunucu çevirisi")
        val dev = FakeOnDevice()
        val http = FakeHttp { error("anahtarlı çevirmen çağrılmamalı") }
        val online = OnlineLineTranslator(DeepLEngine("k", http), { LineCache.memory() }, { Glossary.EMPTY }, clock.now)
        val t = translator(pool, dev, online)
        val r = t.translate("Come here.", TranslationSettings(sharePool = false))!!
        assertEquals(LineResult.Origin.POOL, r.origin) // paket de atlanır
        assertEquals(listOf("Come here." to true), pool.asked)
        // Geç gelen cevap: önce cihaz içi, sonra yükseltme.
        pool.answer = "Geç çeviri"; pool.delayMs = 1_000
        val up = CompletableDeferred<LineResult>()
        t.onUpgrade = { up.complete(it) }
        val first = t.translate("Late line", TranslationSettings())!!
        assertEquals(LineResult.Origin.ON_DEVICE, first.origin)
        assertEquals("Geç çeviri", withTimeout(5_000) { up.await() }.text)
        assertTrue(http.requests.isEmpty())
    }

    @Test fun onlineFallsBackAndRests() = runBlocking {
        var code = 500
        val http = FakeHttp { FakeHttp.json(code, """{"translations":[{"text":"Merhaba"}]}""") }
        val online = OnlineLineTranslator(DeepLEngine("k", http), { LineCache.memory() }, { Glossary.EMPTY }, clock.now)
        val t = translator(null, FakeOnDevice(), online)
        assertEquals(LineResult.Origin.ON_DEVICE, t.translate("Hello", TranslationSettings())!!.origin)
        assertEquals(KeyStatus.UNREACHABLE, online.warning)
        code = 200
        assertEquals(LineResult.Origin.ON_DEVICE, t.translate("Hello again", TranslationSettings())!!.origin) // 60 sn dinlenme
        assertEquals(1, http.requests.size)
        clock.advance(60_001)
        val r = t.translate("Hello", TranslationSettings())!!
        assertEquals(LineResult.Origin.ONLINE, r.origin); assertEquals("Merhaba", r.text)
        assertNull(online.warning)
        // DeepL Hintçe desteklemez → cihaz içi.
        assertEquals(LineResult.Origin.ON_DEVICE, t.translate("Hello", TranslationSettings(target = TargetLanguage.HI))!!.origin)
    }

    @Test fun onDeviceTurkishPipeline() = runBlocking {
        val g = Glossary.parse("""{"terms":{"flare gun":"işaret fişeği"},"lines":{"climbing up":"Yukarı tırmanıyorum"}}""")
        val dev = FakeOnDevice(hashMapOf(
            "Fire the Zarmon now!" to "Zarmonu şimdi ateşle",
            "Who fixed the radio? *** Here." to "Telsizi kim onardı? *** Burada.",
            "Who fixed the radio?" to "Telsizi kim onardı",
            "Wait for me." to "Beni bekleyin.",
            "I really need you." to "Sana gerçekten ihtiyacım var.",
        ))
        val recent = RecentLines(clock.now)
        val od = onDevice(dev, g, recent)
        assertEquals("KRATOS: İşaret fişeğini şimdi ateşle!", od.translate("KRATOS: Fire the flare gun now!", TargetLanguage.TR))
        assertEquals("Yukarı tırmanıyorum!", od.translate("Climbing up!", TargetLanguage.TR))
        assertEquals(0, dev.calls.count { it.contains("Climbing", true) })
        // Kısa cümle önceki cümleyle çevrilir.
        assertEquals("Telsizi kim onardı? Burada.", od.translate("Who fixed the radio? Here.", TargetLanguage.TR))
        // Hitap birliği.
        assertEquals("Beni bekle. Sana gerçekten ihtiyacım var.", od.translate("Wait for me. I really need you.", TargetLanguage.TR))
        // Önbellek: ikinci kez çevirmene gitmez.
        val before = dev.calls.size
        od.translate("KRATOS: Fire the flare gun now!", TargetLanguage.TR)
        assertEquals(before, dev.calls.size)
    }

    @Test fun sideTextIsNotOfferedNorRemembered() = runBlocking {
        val pool = FakePool(); val dev = FakeOnDevice()
        val recent = RecentLines(clock.now)
        val t = LineTranslator(pack, pool, onDevice(dev), null, recent, CoroutineScope(SupervisorJob() + Dispatchers.Default))
        assertEquals(LineResult.Origin.ON_DEVICE, t.translate("Find the key", TranslationSettings(sideText = true))!!.origin)
        assertTrue(pool.offered.isEmpty())
        assertTrue(recent.last(5).isEmpty())
        t.translate("Find the key", TranslationSettings())
        assertEquals(listOf("Find the key"), pool.offered)
        assertEquals(1, recent.last(5).size)
    }

    @Test fun contextSeparatorRules() {
        assertEquals("Burada.", OnDeviceLineTranslator.afterSeparator("Tekne nerede? *** Burada.", "Here."))
        assertNull(OnDeviceLineTranslator.afterSeparator("Tekne nerede? **** Burada.", "Here."))
        assertNull(OnDeviceLineTranslator.afterSeparator("*** Burada.", "Here."))
        assertNull(OnDeviceLineTranslator.afterSeparator("A *** B *** C", "x"))
        assertNull(OnDeviceLineTranslator.afterSeparator("A *** " + "b".repeat(40), "Hi"))
    }

    @Test fun languages() {
        assertEquals(TargetLanguage.ID, TargetLanguage.of("in"))
        assertEquals(TargetLanguage.TL, TargetLanguage.of("fil"))
        assertEquals(TargetLanguage.TR, TargetLanguage.of("TR-tr"))
        assertNull(TargetLanguage.of("fi"))
        assertEquals("‏مرحبا\nabc", TargetLanguage.AR.forDisplay("مرحبا\nabc"))
        assertTrue(TargetLanguage.TH.isAlreadyInTarget("สวัสดี"))
        assertTrue(!TargetLanguage.TR.isAlreadyInTarget("Merhaba"))
    }
}
