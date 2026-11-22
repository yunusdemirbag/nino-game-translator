// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import com.ninotranslator.core.link.ShowPayload
import com.ninotranslator.core.reading.live.LiveBox
import com.ninotranslator.core.reading.live.LiveLine
import com.ninotranslator.core.reading.live.LiveShowKind
import com.ninotranslator.core.reading.live.ManualClock
import com.ninotranslator.core.translation.Glossary
import com.ninotranslator.core.translation.LineCache
import com.ninotranslator.core.translation.LineResult
import com.ninotranslator.core.translation.LineTranslator
import com.ninotranslator.core.translation.OnDeviceLineTranslator
import com.ninotranslator.core.translation.OnDeviceTranslator
import com.ninotranslator.core.translation.RecentLines
import com.ninotranslator.core.translation.TargetLanguage
import com.ninotranslator.core.translation.TranslationSettings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer

/** Sahte TV: gelenleri yazar. */
class FakeTv : TvOutput {
    val shows = ArrayList<ShowPayload>()
    val clears = ArrayList<Int>()
    val styles = ArrayList<Map<String, Any?>>()
    override val connectedCount = MutableStateFlow(1)
    override val portProblems = MutableStateFlow<Set<Int>>(emptySet())
    override var subtitlesToTv = true
    override fun start() {}
    override fun close() {}
    override suspend fun show(payload: ShowPayload) { if (subtitlesToTv) shows += payload }
    override suspend fun clear(id: Int) { if (subtitlesToTv) clears += id }
    override fun setStyle(style: Map<String, Any?>) { styles += style }
    override suspend fun started() {}
    override suspend fun stopped() {}
}

class ReadingLoopTest {
    private val w = 320
    private val h = 180
    /** Kırpmaya göre (alt bölge) tipik altyazı kutusu. */
    private val box = LiveBox(0.2, 0.55, 0.8, 0.75)

    /** Karenin bütün pikselleri [v]: sahte OCR [v]'ye göre yazı verir. */
    private fun frame(v: Int, at: Long) = VideoFrame(ByteBuffer.wrap(ByteArray(w * h) { v.toByte() }), w, h, w, at)

    private class Rig(
        scope: CoroutineScope,
        script: Map<Int, String>,
        translate: suspend (String) -> LineResult?,
        cfg: LoopConfig = LoopConfig(target = TargetLanguage.NL),
        val box: LiveBox,
        inPack: (String) -> Boolean = { false },
    ) {
        val clock = ManualClock(10_000)
        var ocrCalls = 0
        val shown = ArrayList<ShownLine>()
        val cleared = ArrayList<Int>()
        val failed = ArrayList<String>()
        val tv = FakeTv()
        var status = LiveSnapshot()
        val router = SubtitleRouter(scope, tv, { 1_700_000_000_000 }, { clock.now }) { p, id -> status = StatusBook.withPhone(status, p, id) }
        val loop = ReadingLoop(
            scope, clock,
            reader = { img ->
                ocrCalls++
                val v = img.data[0].toInt() and 0xFF
                script[v]?.split('\n')?.mapIndexed { i, t -> LiveLine(t, LiveBox(box.left, box.top + i * 0.1, box.right, box.bottom + i * 0.1)) } ?: emptyList()
            },
            translate = translate,
            listener = object : ReadingLoop.Listener {
                override fun onShow(line: ShownLine) {
                    shown += line
                    status = StatusBook.onShown(status, line) { null }
                    router.show(line)
                }
                override fun onClear(id: Int) { cleared += id; router.clear(id) }
                override fun onTranslationFailed(source: String) { failed += source }
            },
            inPack = inPack,
        ).also { it.config = cfg }
    }

    private suspend fun settle() = repeat(10) { yield() }

    /** [v] karesini [n] okuma boyunca verir (her okuma arası 200 ms). */
    private suspend fun feed(r: Rig, v: Int, n: Int) = repeat(n) {
        r.clock.advance(200)
        r.loop.offerFrame(frame(v, r.clock.now - 30))
        settle()
        r.loop.tick(); r.router.tick()
        settle()
    }

    private fun run(block: suspend CoroutineScope.() -> Unit) = runBlocking {
        block()
        coroutineContext.cancelChildren()
    }

    private val dutch = mapOf(
        "We ride at dawn." to "Wij vertrekken bij dageraad.",
        "Where is the horse?" to "Waar is het paard?",
        "MARA: The boat is leaving." to "MARA: De boot vertrekt.",
    )

    private fun fakeResult(t: String) = dutch[t]?.let { LineResult(t, it, LineResult.Origin.ON_DEVICE, "mlkit-p3") }

    @Test fun ocrToTvAndPhoneEndToEnd() = run {
        val r = Rig(this, mapOf(32 to "We ride at dawn.", 64 to "Where is the horse?"), { fakeResult(it) }, box = box)
        feed(r, 32, 3)
        val first = r.shown.single()
        assertEquals("Wij vertrekken bij dageraad.", first.text)
        assertEquals(LiveShowKind.NEW, first.kind)
        assertEquals(LineResult.Origin.ON_DEVICE, first.origin)
        // Kutu karenin oranına çevrildi (alt bölge: üst 0.62, boy 0.35).
        val b = first.box!!
        assertEquals(0.62 + 0.55 * 0.35, b.top, 1e-9)
        assertNotNull(first.latencyMs)
        // TV: numaralı show, kutu ve 15 sn süre.
        val p = r.tv.shows.single()
        assertEquals(first.id, p.id)
        assertEquals(15000, p.durationMs)
        assertEquals("We ride at dawn.", p.source)
        assertTrue((p.extras["box"] as Map<*, *>).containsKey("top"))
        // Telefon ve canlı durum.
        assertEquals("Wij vertrekken bij dageraad.", r.status.currentLine)
        assertEquals(1, r.status.shownLines)
        assertEquals(TranslationOrigin.ENGINE, r.status.recent.single().origin)
        // Değişmeyen bölge: aynı kare yeniden okunmadı.
        assertEquals(1, r.ocrCalls)

        // Yeni satır öncekini üste iter.
        feed(r, 64, 3)
        assertEquals(2, r.shown.size)
        assertEquals("Waar is het paard?", r.status.currentLine)
        assertEquals("Wij vertrekken bij dageraad.", r.status.previousLine)
        assertEquals("Waar is het paard?", r.status.recent.first().translation)

        // Bölge boşalır: 800 ms sonra temizle (TV'ye son numarayla).
        feed(r, 0, 6)
        assertEquals(listOf(r.shown.last().id), r.cleared)
        assertEquals(listOf(r.shown.last().id), r.tv.clears)
        assertNull(r.status.currentLine)
        assertNull(r.status.previousLine)
    }

    @Test fun throttleReadsAtMostFivePerSecond() = run {
        val r = Rig(this, mapOf(32 to "We ride at dawn."), { fakeResult(it) }, box = box)
        var accepted = 0
        repeat(20) {
            r.clock.advance(50)
            if (r.loop.offerFrame(frame(32, r.clock.now))) accepted++
            settle()
        }
        assertEquals(5, accepted)
    }

    @Test fun speakerNameHiddenWhenSettingOff() = run {
        val r = Rig(this, mapOf(32 to "MARA: The boat is leaving."), { fakeResult(it) },
            LoopConfig(target = TargetLanguage.NL, showSpeakerNames = false), box)
        feed(r, 32, 3)
        assertEquals("De boot vertrekt.", r.shown.single().text)
    }

    @Test fun phoneTargetSkipsTvButShowsOnPhone() = run {
        val r = Rig(this, mapOf(32 to "We ride at dawn."), { fakeResult(it) }, box = box)
        r.tv.subtitlesToTv = false
        feed(r, 32, 3)
        assertTrue(r.tv.shows.isEmpty())
        assertEquals("Wij vertrekken bij dageraad.", r.status.currentLine)
    }

    @Test fun failedTranslationRetriedWhileOnScreen() = run {
        var fail = true
        val r = Rig(this, mapOf(32 to "We ride at dawn."), { if (fail) null else fakeResult(it) }, box = box)
        feed(r, 32, 2)
        assertEquals(listOf("We ride at dawn."), r.failed)
        assertTrue(r.shown.isEmpty())
        fail = false
        // Ekranda kalırken en erken 1000 ms sonra yeniden çevrilir. Bölge değişmediği için kapı en çok 20 okuma
        // eski okumayı yeniden verir; satır yine her turda beslenir.
        feed(r, 32, 8)
        assertEquals("Wij vertrekken bij dageraad.", r.shown.single().text)
    }

    @Test fun regionChangeReadsImmediately() = run {
        val r = Rig(this, mapOf(32 to "We ride at dawn."), { fakeResult(it) }, box = box)
        feed(r, 32, 2)
        val before = r.ocrCalls
        r.loop.config = r.loop.config.copy(region = com.ninotranslator.core.reading.live.LiveRegion.TOP)
        settle()
        feed(r, 32, 1)
        assertEquals(before + 1, r.ocrCalls)
    }

    @Test fun realLineTranslatorWithFakeOnDeviceEngine() = run {
        val now = { 0L }
        val recent = RecentLines(now)
        val fake = object : OnDeviceTranslator {
            override suspend fun translate(text: String, target: TargetLanguage) = dutch[text] ?: error("bilinmeyen: $text")
        }
        val onDevice = OnDeviceLineTranslator(fake, { LineCache.memory() }, { Glossary.EMPTY }, recent, now)
        val lt = LineTranslator(null, null, onDevice, null, recent, this)
        val settings = TranslationSettings(target = TargetLanguage.NL, packsEnabled = false, sharePool = false)
        val r = Rig(this, mapOf(32 to "Where is the horse?"), { lt.translate(it, settings) }, box = box)
        feed(r, 32, 3)
        assertEquals("Waar is het paard?", r.shown.single().text)
        assertEquals(LineResult.Origin.ON_DEVICE, r.shown.single().origin)
        assertEquals("Waar is het paard?", r.tv.shows.single().text)
    }

    @Test fun packLineIsNotHeld() = run {
        // Küçük harfle başlayan, noktasız okuma "yarım olabilir": normalde 300 ms bekletilir.
        val text = "we ride at dawn"
        val translate: suspend (String) -> LineResult? = { LineResult(it, "şafakta yola çıkıyoruz", LineResult.Origin.PACK, "rdr2") }
        val held = Rig(this, mapOf(32 to text), translate, box = box)
        held.clock.advance(200); held.loop.offerFrame(frame(32, held.clock.now)); settle()
        held.clock.advance(200); held.loop.offerFrame(frame(32, held.clock.now)); settle()
        assertTrue(held.shown.isEmpty())
        val pack = Rig(this, mapOf(32 to text), translate, box = box, inPack = { it == text })
        pack.clock.advance(200); pack.loop.offerFrame(frame(32, pack.clock.now)); settle()
        pack.clock.advance(200); pack.loop.offerFrame(frame(32, pack.clock.now)); settle()
        assertEquals("şafakta yola çıkıyoruz", pack.shown.single().text)
        assertTrue(pack.shown.single().fromPack)
        assertEquals(TranslationOrigin.PACK, pack.status.recent.single().origin)
    }

    @Test fun cropCopyHonoursStride() {
        val stride = 8
        val data = ByteArray(stride * 4) { it.toByte() }
        val f = VideoFrame(ByteBuffer.wrap(data), 6, 4, stride, 0)
        val c = ReadingLoop.copyCrop(f, 2, 1, 2, 2)
        assertEquals(listOf(10, 11, 18, 19), c.data.map { it.toInt() })
    }
    /** Sabit görev yazısı 10 sn durur (kapı eski okumayı yeniden verir); yeni altyazı gelince yalnız o çevrilir. */
    @Test fun fixedQuestLineAgesEvenWhenReadingIsReused() = run {
        val r = Rig(this, mapOf(32 to "Go to the marker.", 64 to "Go to the marker.\nWe ride at dawn."), { fakeResult(it) }, box = box)
        feed(r, 32, 50)
        assertTrue(r.ocrCalls < 50) // okuma yeniden kullanıldı, saat yine ilerledi
        feed(r, 64, 4)
        assertEquals("We ride at dawn.", r.shown.single().source)
    }

    /** Harita açıkken de (altyazı bastırılmış) süzgecin saati işler. */
    @Test fun questLineAgesWhileSubtitlesSuppressed() = run {
        val r = Rig(this, mapOf(32 to "Go to the marker.", 64 to "Go to the marker.\nWe ride at dawn."), { fakeResult(it) },
            LoopConfig(target = TargetLanguage.NL, subtitlesSuppressed = true), box)
        feed(r, 32, 50)
        assertTrue(r.shown.isEmpty())
        r.loop.config = r.loop.config.copy(subtitlesSuppressed = false)
        feed(r, 64, 4)
        assertEquals("We ride at dawn.", r.shown.single().source)
    }
}
