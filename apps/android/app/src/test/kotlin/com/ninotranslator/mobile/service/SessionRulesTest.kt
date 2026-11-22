// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import com.ninotranslator.core.reading.live.LiveShowKind
import com.ninotranslator.core.translation.LineResult
import com.ninotranslator.mobile.data.TvBackgroundShape
import com.ninotranslator.mobile.data.TvDisplayMode
import com.ninotranslator.mobile.data.TvPlacement
import com.ninotranslator.mobile.data.TextColor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PhaseTextsTest {
    @Test fun phaseByStateAndSource() {
        assertEquals(TextRef("phase_preparing"), PhaseTexts.phase(SourceState.Preparing, SourceKind.REMOTE_PLAY))
        assertEquals(TextRef("phase_connecting"), PhaseTexts.phase(SourceState.Connecting, SourceKind.REMOTE_PLAY))
        assertEquals(TextRef("capture_phase_opening"), PhaseTexts.phase(SourceState.Connecting, SourceKind.CAPTURE_CARD))
        assertEquals(TextRef("xbox_phase_connecting"), PhaseTexts.phase(SourceState.Connecting, SourceKind.XBOX))
        assertEquals(TextRef("phase_streaming"), PhaseTexts.phase(SourceState.Streaming, SourceKind.DEBUG_FRAMES))
        assertEquals(TextRef("phase_not_found_host", "192.168.0.5"),
            PhaseTexts.phase(SourceState.Reconnecting("phase_not_found_host", "192.168.0.5"), SourceKind.REMOTE_PLAY))
        assertNull(PhaseTexts.phase(SourceState.Idle, SourceKind.REMOTE_PLAY))
    }

    /** Hizmetin her metin anahtarı Türkçe ve İngilizce strings'te var; yer tutucular aynı (koda gömülü yedek yok). */
    @Test fun everyServiceKeyHasTextInBothLanguages() {
        // Kaynak kodda geçen her aşama/hata/bildirim anahtarı da (kaynakların kendi anahtarları dahil).
        val literal = Regex("\"((?:phase|capture_phase|xbox_phase|screen|notif)_[a-z_]+|capture_(?:black|not_found|no_permission)|error_(?!code\"|description\")[a-z_]+)\"")
        val inCode = java.io.File("src/main/kotlin").walk().filter { it.extension == "kt" }
            .flatMap { f -> literal.findAll(f.readText()).map { it.groupValues[1] } }.toSet()
        assertTrue("anahtar taraması boş", "phase_asleep" in inCode && "error_port" in inCode)
        val keys = ServiceTexts.ALL + inCode
        val files = listOf("values", "values-en").associateWith { java.io.File("src/main/res/$it/strings.xml").readText() }
        fun text(xml: String, k: String) = Regex("<string name=\"${Regex.escape(k)}\"[^>]*>(.*?)</string>").find(xml)?.groupValues?.get(1)
        for (k in keys.toSet()) {
            val tr = text(files.getValue("values"), k); val en = text(files.getValue("values-en"), k)
            assertTrue("values: $k yok", tr != null); assertTrue("values-en: $k yok", en != null)
            val ph = Regex("%\\d\\$[sd]")
            assertEquals("$k yer tutucu", ph.findAll(tr!!).map { it.value }.toList(), ph.findAll(en!!).map { it.value }.toList())
            assertEquals("$k biçimli mi", k in ServiceTexts.WITH_ARG, tr.contains("%1\$s"))
            assertFalse("$k: kaçışsız kesme işareti", Regex("(?<!\\\\)'").containsMatchIn(tr) || Regex("(?<!\\\\)'").containsMatchIn(en))
        }
    }

    @Test fun connectReasonRules() {
        val b = ConnectReasonBook()
        b.onState(SourceState.Connecting)
        assertNull(b.reason)
        b.onState(SourceState.Reconnecting("phase_network"))
        assertEquals("phase_network", b.reason?.key)
        // Bağlanırken önceki neden korunur.
        b.onState(SourceState.Connecting)
        assertEquals("phase_network", b.reason?.key)
        // Nedeni bilinmeyen genel kopma: önceki kalır.
        b.onState(SourceState.Reconnecting("phase_reconnecting"))
        assertEquals("phase_network", b.reason?.key)
        // Yeni neden yazılır.
        b.onState(SourceState.Failed("phase_passcode"))
        assertEquals("phase_passcode", b.reason?.key)
        // Görüntü gelince silinir.
        b.onState(SourceState.Streaming)
        assertNull(b.reason)
    }

    @Test fun captureProblemsGoToErrorCardOnly() {
        val b = ConnectReasonBook()
        b.onState(SourceState.Reconnecting("phase_in_use"))
        b.onState(SourceState.Failed("capture_black"))
        assertEquals("phase_in_use", b.reason?.key)
        assertEquals("capture_black", b.captureProblem?.key)
        b.onState(SourceState.Connecting)
        assertNull(b.captureProblem)
    }

    @Test fun errorPriority() {
        val e = ErrorBook()
        e.set(ServiceTexts.ERROR_TRANSLATION)
        e.set(ServiceTexts.ERROR_MODEL)
        assertEquals(ServiceTexts.ERROR_MODEL, e.top?.key)
        e.set("capture_not_found")
        assertEquals("capture_not_found", e.top?.key)
        e.clear("capture_not_found"); e.clear(ServiceTexts.ERROR_MODEL)
        assertEquals(ServiceTexts.ERROR_TRANSLATION, e.top?.key)
        e.clear(ServiceTexts.ERROR_TRANSLATION)
        assertNull(e.top)
    }
}

class SessionRulesTest {
    @Test fun phoneLinesStackAndReplace() {
        val p = PhoneLines()
        p.show("We ride at dawn.", "Şafakta yola çıkıyoruz.", false, 15000, 0)
        p.show("Where is the horse?", "At nerede?", false, 15000, 100)
        assertEquals("At nerede?", p.state.current)
        assertEquals("Şafakta yola çıkıyoruz.", p.state.previous)
        // Uzayan okuma öncekinin yerine geçer, üste yığılmaz.
        p.show("Where is the horse? Tell me.", "At nerede? Söyle bana.", true, 15000, 200)
        assertEquals("At nerede? Söyle bana.", p.state.current)
        assertEquals("Şafakta yola çıkıyoruz.", p.state.previous)
        // Süre dolunca kalkar.
        assertNull(p.expire(1000))
        assertNull(p.expire(15_199))
        assertNull(p.expire(15_200)?.current)
        assertNull(p.state.current)
    }

    @Test fun phoneLineWrapsAndDefaultDuration() {
        val p = PhoneLines()
        val long = "Bu çok uzun bir çeviri satırıdır ve telefonda tek satıra kesinlikle sığmaz, bölünmesi gerekir."
        val st = p.show(long, long, false, null, 0)
        assertTrue(st.current!!.contains('\n'))
        assertEquals(com.ninotranslator.core.reading.live.LiveTranslationQueue.lateDisplayMs(long), st.untilMs)
        assertEquals(2000L + 4 * 60, PhoneLines().show("Evet.", "Evet.", false, null, 0).untilMs)
    }

    @Test fun styleMapFields() {
        val m = TvStyle.map(StyleInput(background = 72, backgroundShape = TvBackgroundShape.BAND, displayMode = TvDisplayMode.OVERLAY,
            placement = TvPlacement.ABOVE, textColor = TextColor.YELLOW, fontSize = 58))
        assertEquals(72, m["background"])
        assertEquals("band", m["backgroundShape"])
        assertEquals("overlay", m["displayMode"])
        assertEquals("above", m["placement"])
        assertEquals("yellow", m["textColor"])
        assertEquals(58, m["fontSize"])
        assertEquals(setOf("autoSize", "background", "backgroundShape", "bold", "bottomPercent", "displayMode", "font", "fontSize",
            "placement", "stackPrevious", "textColor", "watermark"), m.keys)
    }

    @Test fun modelRetrySchedule() {
        assertEquals(listOf(10_000L, 20_000L, 30_000L, 40_000L, 50_000L), (1..5).map { ModelRetry.delayAfter(it) })
        assertNull(ModelRetry.delayAfter(6))
        assertFalse(ModelRetry.showWarning(1))
        assertTrue(ModelRetry.showWarning(2))
    }

    @Test fun gameFromPacksAfterFiveUniqueLines() {
        val g = GameTracker(enabled = true)
        repeat(4) { assertFalse(g.onShown(LineResult.Origin.PACK, "rdr2", uniquePack = true)) }
        assertNull(g.current)
        assertTrue(g.onShown(LineResult.Origin.PACK, "rdr2", uniquePack = true))
        assertEquals("rdr2", g.current)
        // PS5'in bildirdiği oyun önce gelir; görüntü kesilince silinir.
        assertTrue(g.onPs5("Ghost of Yōtei"))
        assertEquals("Ghost of Yōtei", g.current)
        assertTrue(g.onPs5(null))
        assertEquals("rdr2", g.current)
        // Klipte (kapalı) oyun aranmaz.
        val off = GameTracker(enabled = false)
        repeat(6) { off.onShown(LineResult.Origin.PACK, "rdr2", true) }
        assertNull(off.current)
    }

    @Test fun statusRecentAndCounters() {
        fun line(id: Int, src: String, pack: Boolean, kind: LiveShowKind = LiveShowKind.NEW) = ShownLine(
            id, src, "tr:$src", 15000, false, kind, pack, if (pack) LineResult.Origin.PACK else LineResult.Origin.ON_DEVICE,
            if (pack) "rdr2" else "mlkit-p3", null, null, if (pack) null else 400,
        )
        var s = LiveSnapshot()
        repeat(25) { s = StatusBook.onShown(s, line(it, "line $it", pack = it % 2 == 0)) { id -> "Red Dead $id" } }
        assertEquals(20, s.recent.size)
        assertEquals("line 24", s.recent.first().source)
        assertEquals(25, s.shownLines)
        assertEquals(13, s.packLines)
        assertEquals("Red Dead rdr2", s.packTitle)
        // Yerine konan çeviri ilk satırı günceller; sayaçlar değişmez.
        s = StatusBook.onShown(s, line(99, "line 24", pack = false, kind = LiveShowKind.UPDATED).copy(text = "daha iyi", origin = LineResult.Origin.POOL)) { null }
        assertEquals(25, s.shownLines)
        assertEquals("daha iyi", s.recent.first().translation)
        assertEquals(TranslationOrigin.POOL, s.recent.first().origin)
        assertEquals(20, s.recent.size)
    }
}
