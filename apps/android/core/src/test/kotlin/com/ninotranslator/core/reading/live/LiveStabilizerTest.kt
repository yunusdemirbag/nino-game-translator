// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveStabilizerTest {
    private val nothing = LiveDecision.Nothing
    private fun LiveStabilizer.read(text: String, now: Long, trace: RegionTrace? = null, box: LiveBox? = null) =
        onReading(if (text.isEmpty()) LiveReading.EMPTY else LiveReading(text.split('\n').map { LiveLine(it, box) }), now, trace)

    private fun trace(v: Int) = RegionTrace(IntArray(FrameTrace.GRID_W * FrameTrace.GRID_H) { v })

    @Test fun shortReadingIsEmpty() {
        val s = LiveStabilizer()
        s.read("Hello there.", 0)
        assertEquals(nothing, s.read("Hi", 100))
        assertEquals(LiveDecision.Clear, s.read("ok", 900))
    }

    @Test fun garbageNeedsTwoReadingsAnd700ms() {
        val s = LiveStabilizer()
        val g = "Wh@t aRe yoU doing."
        assertTrue(LiveText.isGarbageReading(g))
        assertEquals(nothing, s.read(g, 0))
        assertEquals(nothing, s.read(g, 300))
        assertTrue(s.read(g, 700) is LiveDecision.Translate)
    }

    @Test fun otherTextDoesNotClear() {
        val s = LiveStabilizer()
        s.read("Hold the bridge.", 0)
        assertEquals(nothing, s.read("Something else here", 900))
        assertEquals(nothing, s.read("", 1000))
        assertEquals(nothing, s.read("", 1799))
        assertEquals(LiveDecision.Clear, s.read("", 1800))
    }

    @Test fun emptyResetsCandidate() {
        val s = LiveStabilizer()
        assertEquals(nothing, s.read("We ride", 0))
        assertEquals(nothing, s.read("", 100))
        assertEquals(nothing, s.read("We ride", 200))
        assertTrue(s.read("We ride", 300) is LiveDecision.Translate)
    }

    @Test fun textStillInPlaceHoldsUpTo4000ms() {
        val s = LiveStabilizer()
        val box = LiveBox(0.2, 0.2, 0.8, 0.6)
        s.read("Bright snow everywhere.", 0, trace(100), box)
        assertEquals(nothing, s.read("", 100, trace(105)))
        assertEquals(nothing, s.read("", 2000, trace(110)))
        assertEquals(nothing, s.read("", 4099, trace(100)))
        assertEquals(LiveDecision.Clear, s.read("", 4100, trace(100)))
    }

    @Test fun movedTextClearsAfter800ms() {
        val s = LiveStabilizer()
        val box = LiveBox(0.2, 0.2, 0.8, 0.6)
        s.read("Bright snow everywhere.", 0, trace(100), box)
        assertEquals(nothing, s.read("", 100, trace(100)))
        assertEquals(nothing, s.read("", 2000, trace(200)))
        assertEquals(nothing, s.read("", 2799, trace(200)))
        assertEquals(LiveDecision.Clear, s.read("", 2800, trace(200)))
    }

    @Test fun sameSubtitleRules() {
        fun same(a: String, b: String) = LiveStabilizer.isSameSubtitle(a, b)
        assertFalse(same("I can't do that.", "I can do that."))
        assertFalse(same("Meet me at 6.", "Meet me at 5."))
        assertTrue(same("I dont know.", "I don't know."))
        assertTrue(same("1 can do that.", "I can do that."))
        assertFalse(same("I will n0t go there.", "I will go there."))
        assertFalse(same("I won t go there.", "I will go there."))
        assertTrue(same("I can do that.", "I can't do that.")) // düşen işaret OCR kaybıdır
        assertFalse(same("We ride at dawn, boys", "We ride at dawn"))
        assertFalse(same("Listen, we ride at dawn", "We ride at dawn"))
        assertTrue(same("The bridqe will not last", "The bridge will not last"))
        assertFalse(same("We ride at dawn and", "We ride at dawn and fight the whole army\nof the north."))
        assertTrue(same("of the north.", "We ride at dawn and fight the whole army\nof the north."))
        assertTrue(same("the soldiers must hold this gate tonight", "Brother, the soldiers must hold this gate tonight, or we all die."))
        assertTrue(same("tomorrow before the sun rises we must cross two lakes", "we must cross the river before the sun rises tomorrow"))
        assertFalse(same("", "anything"))
    }

    @Test fun worseRereadIsNotNew() {
        val sent = "We have to find the boat before nightfall."
        assertTrue(LiveStabilizer.isWorseReread("We have to fimd the boat bef0re nightfall.", sent))
        assertFalse(LiveStabilizer.isWorseReread("We have to find the old boat before nightfall.", sent)) // daha çok sözcük
        assertFalse(LiveStabilizer.isWorseReread("Go b0at now.", sent)) // 5 sözcükten az
        val s = LiveStabilizer()
        s.read(sent, 0)
        assertEquals(nothing, s.read("We have to fimd the boat bef0re nightfall.", 200))
    }

    @Test fun replaceInfoForGrowingText() {
        val s = LiveStabilizer()
        assertEquals(LiveDecision.Translate("Hello there.", false), s.read("Hello there.", 0))
        assertEquals(LiveDecision.Translate("Hello there. How are you?", true), s.read("Hello there. How are you?", 200))
        assertEquals(LiveDecision.Translate("Completely different words.", false), s.read("Completely different words.", 400))
        assertTrue(LiveStabilizer.isGrowthOrCorrection("Hello there. How are you?", "Hello there."))
    }

    @Test fun failedTranslationRetriesAfter1000ms() {
        val s = LiveStabilizer()
        s.read("Go away now.", 0)
        s.onTranslationFailed("Go away now.", 0)
        assertEquals(nothing, s.read("Go away now.", 500))
        assertEquals(nothing, s.read("Go away now.", 999))
        assertEquals(LiveDecision.Translate("Go away now.", false), s.read("Go away now.", 1000))
        assertEquals(nothing, s.read("Go away now.", 1200))
    }

    @Test fun restoreHistoryIsFive() {
        val s = LiveStabilizer()
        val lines = listOf("One line.", "Two lines.", "Three lines.", "Four lines.", "Five lines.", "Six lines.", "Seven lines.")
        lines.forEachIndexed { i, t -> assertTrue(s.read(t, i * 100L) is LiveDecision.Translate) }
        // "One" listeden düştü; "Four" hâlâ içinde.
        assertTrue(s.read("One line.", 800) is LiveDecision.Translate)
        assertEquals(LiveDecision.Restore("Four lines."), s.read("Four lines.", 900))
    }

    @Test fun alreadyTranslated() {
        assertFalse(LiveStabilizer.shouldShow("Merhaba dostum", "Merhaba dostum", false))
        assertTrue(LiveStabilizer.shouldShow("Hello friend", "Merhaba dostum", false))
        assertTrue(LiveStabilizer.shouldShow("OK", "OK", true))
        assertFalse(LiveStabilizer.shouldShow("Ayarları değiştir", "Ayarları değiştir", true))
    }

    @Test fun resetForgetsEverything() {
        val s = LiveStabilizer()
        s.read("Hold the gate.", 0)
        s.reset()
        assertEquals(null, s.shownText)
        assertTrue(s.read("Hold the gate.", 100) is LiveDecision.Translate)
    }
}
