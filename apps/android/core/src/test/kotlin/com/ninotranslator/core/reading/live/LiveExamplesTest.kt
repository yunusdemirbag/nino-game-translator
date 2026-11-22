// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** okuma.md bölüm 15'teki örnekler. */
class LiveExamplesTest {
    private val nothing = LiveDecision.Nothing
    private fun tr(t: String, replaces: Boolean = false) = LiveDecision.Translate(t, replaces)
    private fun LiveStabilizer.read(text: String, now: Long) = onReading(if (text.isEmpty()) LiveReading.EMPTY else LiveReading.of(text), now)

    @Test fun ex01_noPunctuationNeedsTwoReadings() {
        val s = LiveStabilizer()
        assertEquals(nothing, s.read("Nobody saw us leave", 0))
        assertEquals(tr("Nobody saw us leave"), s.read("Nobody saw us leave", 200))
        assertEquals(nothing, s.read("Nobody saw us leave", 400))
    }

    @Test fun ex02_sentenceEndGoesOnFirstReading() {
        for (t in listOf("Nobody saw us leave.", "Wait!", "Who are you?", "I know…", "\"Run.\"")) {
            val s = LiveStabilizer()
            assertEquals(t, tr(t), s.read(t, 0))
            assertEquals(t, nothing, s.read(t, 200))
        }
    }

    @Test fun ex03_ocrWobbleIsOneTranslation() {
        val s = LiveStabilizer()
        val out = listOf("The bridge will not last", "The bridge will not last", "The bridqe will not last", "The bridqe will not last")
            .mapIndexed { i, t -> s.read(t, i * 200L) }
        assertEquals(1, out.count { it is LiveDecision.Translate })
    }

    @Test fun ex04_gaugeNeverTranslates() {
        val f = LiveNoiseFilter()
        val s = LiveStabilizer()
        val region = LiveRegion.BOTTOM
        var count = 0
        for (i in 0 until 40) {
            val lines = if (i % 2 == 0) listOf(LiveLine("24 / 120", LiveBox(0.45, 0.4, 0.55, 0.5))) else emptyList()
            val d = s.onReading(f.filter(lines, region, i * 200L), i * 200L)
            if (d is LiveDecision.Translate) count++
        }
        assertEquals(0, count)
    }

    @Test fun ex05_typewriterTranslatesOnce() {
        val s = LiveStabilizer()
        assertEquals(nothing, s.read("Nobody", 0))
        assertEquals(nothing, s.read("Nobody saw us", 200))
        assertEquals(tr("Nobody saw us leave the camp, kid."), s.read("Nobody saw us leave the camp, kid.", 400))
        assertEquals(nothing, s.read("Nobody saw us leave the camp, kid.", 600))
    }

    @Test fun ex06_clearAfter800msEmpty() {
        val s = LiveStabilizer()
        s.read("Hello there", 0)
        assertTrue(s.read("Hello there", 100) is LiveDecision.Translate)
        assertEquals(nothing, s.read("", 200))
        assertEquals(nothing, s.read("", 999))
        assertEquals(LiveDecision.Clear, s.read("", 1000))
        assertEquals(nothing, s.read("", 1200))
    }

    @Test fun ex07_flickeringEmptyDoesNotClear() {
        val s = LiveStabilizer()
        s.read("Hold the gate", 0)
        assertTrue(s.read("Hold the gate", 100) is LiveDecision.Translate)
        var t = 100L
        repeat(3) {
            repeat(10) { t += 50; assertEquals(nothing, s.read("", t)) }
            repeat(4) { t += 50; assertEquals(nothing, s.read("Hold the gate", t)) }
        }
    }

    @Test fun ex08_restoreWithin1500ms() {
        val s = LiveStabilizer()
        assertTrue(s.read("Hold the gate.", 0) is LiveDecision.Translate)
        s.read("", 100)
        assertEquals(LiveDecision.Clear, s.read("", 900))
        assertEquals(nothing, s.read("Hold the gate", 1500))
        assertEquals(LiveDecision.Restore("Hold the gate."), s.read("Hold the gate", 2300))
    }

    @Test fun ex09_after1501msTranslatesAgain() {
        val s = LiveStabilizer()
        s.read("Hold the gate.", 0)
        s.read("", 100)
        assertEquals(LiveDecision.Clear, s.read("", 900))
        assertEquals(tr("Hold the gate."), s.read("Hold the gate.", 2401))
    }

    @Test fun ex10_swappedLinesRestore() {
        val s = LiveStabilizer()
        assertEquals(tr("Hold the gate."), s.read("Hold the gate.", 0))
        assertEquals(tr("Run!"), s.read("Run!", 100))
        assertEquals(LiveDecision.Restore("Hold the gate."), s.read("Hold the gate.", 200))
        assertEquals(LiveDecision.Restore("Run!"), s.read("Run!", 300))
    }

    @Test fun ex11_negationIsNewLine() {
        val s = LiveStabilizer()
        assertTrue(s.read("I can carry that for you later.", 0) is LiveDecision.Translate)
        assertTrue(s.read("I can't carry that for you later.", 200) is LiveDecision.Translate)
    }

    @Test fun ex12_truncatedLineIsSame() {
        val s = LiveStabilizer()
        assertTrue(s.read("Through the frozen pass, Kai rode,\nwishing the storm would let him rest.", 0) is LiveDecision.Translate)
        assertEquals(nothing, s.read("Through the frozen pass O rode,", 200))
        assertEquals(nothing, s.read("Through the frozen pass O rode,", 400))
        assertEquals(tr("We should rest here."), s.read("We should rest here.", 600))
    }

    @Test fun ex13_directions() {
        for (t in listOf("Turn Left 120 ft 98 ft", "Keep Left O ft 2 ft", "Turn left", "Make a U-turn")) assertTrue(t, Directions.isDirection(t))
        for (t in listOf("Turn right after the bridge, alright?", "Keep walking, the camp is close.", "Turn it down!")) assertFalse(t, Directions.isDirection(t))
        val f = LiveNoiseFilter()
        val out = f.filter(listOf(LiveLine("Turn Left 120 ft 98 ft"), LiveLine("Turn it down!")), LiveRegion.BOTTOM, 0)
        assertEquals("Turn it down!", out.text)
    }

    @Test fun ex14_wrapping() {
        val short = LineWrapper.wrap("Gitmeliyiz, hemen.")
        assertEquals(listOf("Gitmeliyiz, hemen."), short.lines); assertEquals(1.0, short.scale, 0.0)

        val long = LineWrapper.wrap("Bu kapıyı daha fazla tutamayız, hemen buradan gitmemiz gerekiyor.")
        assertEquals(2, long.lines.size)
        assertTrue(long.lines.all { it.length <= 42 })
        assertTrue(long.lines.maxOf { it.length } - long.lines.minOf { it.length } <= 12)
        assertEquals(1.0, long.scale, 0.0)

        val veryLong = LineWrapper.wrap(
            "Bu kapıyı daha fazla tutamayız, hemen buradan gitmemiz gerekiyor çünkü askerler kuzeyden geliyor " +
                "ve yanımızda yeterince ok kalmadı, köprüyü geçip ormana saklanmalıyız.",
        )
        assertEquals(3, veryLong.lines.size)
        assertTrue(veryLong.scale >= 0.75 && veryLong.scale < 1.0)
    }
}
