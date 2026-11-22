// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveNoiseFilterTest {
    private val full = LiveRegion.FULL
    private fun line(t: String, l: Double, top: Double, r: Double, b: Double) = LiveLine(t, LiveBox(l, top, r, b))
    private fun f(vararg ls: LiveLine, now: Long = 0, task: Double? = TaskStripLine.DEFAULT, filter: LiveNoiseFilter = LiveNoiseFilter()) =
        filter.filter(ls.toList(), full, now, task).text

    @Test fun step1_letterCount() {
        assertEquals("No.", f(LiveLine("A"), LiveLine(">>"), LiveLine("No.")))
    }

    @Test fun step2_taskStripLine() {
        assertEquals("We ride at dawn.", f(line("We ride at dawn.", 0.3, 0.80, 0.7, 0.84), line("Find the camp now.", 0.3, 0.91, 0.7, 0.94)))
        // Konuşan adıyla başlayan satır ve hemen altındaki devamı kalır.
        assertEquals(
            "ENZO: Let's go\nright now, come on.",
            f(line("ENZO: Let's go", 0.3, 0.90, 0.7, 0.93), line("right now, come on.", 0.3, 0.935, 0.7, 0.965)),
        )
        // Sınır yoksa kalır.
        assertEquals("Find the camp now.", f(line("Find the camp now.", 0.3, 0.91, 0.7, 0.94), task = null))
    }

    @Test fun step3_staleLine() {
        val nf = LiveNoiseFilter()
        val old = line("Objective: reach the camp", 0.3, 0.70, 0.7, 0.74)
        f(old, now = 0, filter = nf)
        assertEquals("Objective: reach the camp", f(old, now = 9500, filter = nf)) // hepsi eski: dokunma
        val fresh = line("We ride at dawn, boys.", 0.3, 0.745, 0.7, 0.785)
        assertEquals("We ride at dawn, boys.", f(old, fresh, now = 9600, filter = nf))
        assertEquals("Objective: reach the camp\nWe ride at dawn, boys.", f(old, fresh, now = 9600, filter = LiveNoiseFilter()))
    }

    // ---- Adım 3: NinoCore GameFilterChain adım 12 ile aynı ----

    /** Sağ altta duran görev yazısı; altyazı ortadan uzakta, kuralsız seçimde görev yazısı kazanır. */
    private val quest = line("Go to the marker.", 0.72, 0.86, 0.96, 0.89)
    private fun sub(t: String) = line(t, 0.05, 0.60, 0.45, 0.64)

    @Test fun step3_boundaryNineSeconds() {
        val nf = LiveNoiseFilter()
        val old = line("Objective: reach the camp", 0.3, 0.70, 0.7, 0.74)
        val fresh = line("We ride at dawn, boys.", 0.3, 0.745, 0.7, 0.785)
        f(old, now = 0, filter = nf)
        assertEquals("Objective: reach the camp\nWe ride at dawn, boys.", f(old, fresh, now = 8999, filter = nf))
        assertEquals("We ride at dawn, boys.", f(old, fresh, now = 9000, filter = nf))
    }

    @Test fun step3_ninoCoreStaleOnlyBesideNewOne() {
        val nf = LiveNoiseFilter()
        val old = line("Welcome to the old mill, traveler.", 0.3, 0.6, 0.7, 0.65)
        assertEquals(old.text, f(old, now = 0, filter = nf))
        assertEquals(old.text, f(old, now = 9500, filter = nf)) // tek başına: dokunulmaz
        assertEquals("Who goes there?", f(old, line("Who goes there?", 0.3, 0.7, 0.7, 0.75), now = 9600, filter = nf))
    }

    @Test fun step3_fixedQuestLineDoesNotBlockNewSubtitles() {
        val nf = LiveNoiseFilter()
        val subs = listOf(5_000L until 12_000L to "We ride at dawn, boys.", 15_000L until 20_000L to "Where is the horse now?",
            24_000L until 30_000L to "Keep your head down, Arthur.")
        var t = 0L
        while (t <= 30_000L) {
            val s = subs.firstOrNull { t in it.first }?.second
            val got = if (s == null) f(quest, now = t, task = null, filter = nf) else f(quest, sub(s), now = t, task = null, filter = nf)
            val want = if (s != null && t >= 9_000) s else quest.text
            assertEquals("t=$t", want, got)
            t += 200
        }
        // Kural olmadan görev yazısı kazanırdı.
        assertEquals(quest.text, f(quest, sub("Keep your head down, Arthur."), now = 30_000, task = null))
        // Noktalama farkı aynı yazıdır: süre sıfırlanmaz.
        assertEquals("Keep your head down, Arthur.", f(line("go to the marker", 0.72, 0.86, 0.96, 0.89), sub("Keep your head down, Arthur."),
            now = 30_200, task = null, filter = nf))
    }

    @Test fun step3_allStaleUntouched() {
        val nf = LiveNoiseFilter()
        val a = line("Objective: reach the camp", 0.3, 0.70, 0.7, 0.74)
        val b = line("Bring the horses along.", 0.3, 0.745, 0.7, 0.785)
        f(a, b, now = 0, filter = nf)
        assertEquals("Objective: reach the camp\nBring the horses along.", f(a, b, now = 20_000, filter = nf))
    }

    @Test fun step3_lineThatVanishesStartsOver() {
        val nf = LiveNoiseFilter()
        f(quest, now = 0, task = null, filter = nf)
        f(now = 6_000, task = null, filter = nf) // görünmedi: süre sıfırlanır
        f(quest, now = 7_000, task = null, filter = nf)
        val s = sub("We ride at dawn, boys.")
        assertEquals(quest.text, f(quest, s, now = 15_000, task = null, filter = nf)) // 8 sn: henüz eski değil
        assertEquals(s.text, f(quest, s, now = 16_000, task = null, filter = nf)) // 9 sn
    }

    @Test fun step4_giantLine() {
        val logged = ArrayList<String>()
        val nf = LiveNoiseFilter { logged += it }
        assertEquals("", f(line("BIG TITLE here", 0.3, 0.6, 0.7, 0.75), filter = nf))
        assertEquals("", f(line("SHOP", 0.45, 0.6, 0.55, 0.69), filter = nf))
        assertEquals("Run, now!", f(line("Run, now!", 0.4, 0.6, 0.6, 0.69), filter = nf))
        f(line("SHOP", 0.45, 0.6, 0.55, 0.69), filter = nf)
        assertEquals(2, logged.size) // bir kez yazılır
        assertEquals("Unknown place", f(LiveLine("Unknown place"), filter = nf))
    }

    @Test fun step5_controllerHints() {
        for (t in listOf("R2 Aim", "□ Open map", "Aim R2", "X Interact", "Press R2 to fire", "Hold ✕ to open the door", "A e DRINKS",
            "Slowly move the stick to aim", "Tilt ✕ to steer the boat")) assertTrue(t, ControllerHints.isHint(t))
        for (t in listOf("Press the button, Arthur.", "We ride at dawn.", "X marks the spot.")) assertFalse(t, ControllerHints.isHint(t))
    }

    @Test fun step7_wordCleanup() {
        assertEquals("Get in the car", WordCleanup.clean("Get ou\$3e in the car"))
        assertEquals("Across the waters", WordCleanup.clean("Across the waters2aljd"))
        assertEquals("Grab the PS5 R2 2nd 100m x3 3.5kg 10:30pm \$500", WordCleanup.clean("Grab the PS5 R2 2nd 100m x3 3.5kg 10:30pm \$500"))
        assertEquals("I can do it", WordCleanup.clean("l can do it"))
        assertEquals("I'm here, I'll go", WordCleanup.clean("l'm here, l'll go"))
        assertEquals("Go now", WordCleanup.clean("Go now I"))
        assertEquals("Go now", WordCleanup.clean("| Go now"))
        assertEquals("Was it I?", WordCleanup.clean("Was it I?"))
        assertEquals("What?", WordCleanup.clean("What ?"))
        assertEquals("Go.", WordCleanup.clean("Go. ."))
        assertEquals("Wait...", WordCleanup.clean("Wait ..."))
        assertEquals("Wait, now", WordCleanup.clean("Wait ou\$3e, now"))
        assertEquals("We'll lose them", WordCleanup.clean("9? We'll lose them"))
        assertEquals("9 lives", WordCleanup.clean("9 lives"))
    }

    @Test fun step8_sideBySide() {
        assertEquals(
            "MARA: The boat is leaving.",
            f(line("The boat is leaving.", 0.39, 0.80, 0.6, 0.84), line("MARA:", 0.30, 0.805, 0.38, 0.84)),
        )
        // Uzak parçalar ayrı kalır.
        val r = LiveNoiseFilter.mergeSideBySide(listOf(line("Left", 0.0, 0.5, 0.1, 0.55), line("Right", 0.5, 0.5, 0.6, 0.55)))
        assertEquals(2, r.size)
    }

    @Test fun step9_blockSelection() {
        // Menü bloğu elenir, ortalı en alt blok seçilir.
        val out = f(
            line("Items", 0.05, 0.10, 0.15, 0.13), line("Map", 0.05, 0.14, 0.15, 0.17), line("Settings", 0.05, 0.18, 0.15, 0.21),
            line("A distant voice calls out.", 0.35, 0.40, 0.65, 0.44),
            line("We ride at dawn.", 0.35, 0.80, 0.65, 0.84), line("Get some rest.", 0.38, 0.845, 0.62, 0.885),
        )
        assertEquals("We ride at dawn.\nGet some rest.", out)
        // Ortalı blok yoksa en az 3 sözcüklü en alttaki.
        assertEquals("the wind is cold here", f(line("the wind is cold here", 0.05, 0.80, 0.3, 0.84), line("Hm", 0.75, 0.82, 0.8, 0.85)))
        // Hiçbiri yoksa boş.
        assertEquals("", f(line("Hm", 0.05, 0.80, 0.1, 0.84)))
    }

    @Test fun step10_giantBlock() {
        val six = (0 until 6).map { line("Line number $it is here.", 0.3, 0.5 + it * 0.04, 0.7, 0.535 + it * 0.04) }
        assertEquals("", f(*six.toTypedArray()))
        val tall = listOf(line("A tall poster line.", 0.3, 0.38, 0.7, 0.50), line("Another big line.", 0.3, 0.53, 0.7, 0.65))
        assertEquals("", f(*tall.toTypedArray()))
    }

    @Test fun regionRelativeBoxes() {
        // Bölgeye göre kutu karenin oranına çevrilir: alt bölgede 0.8 → karede 0.90 (görev şeridi altında).
        val nf = LiveNoiseFilter()
        val r = LiveRegion.BOTTOM
        val out = nf.filter(listOf(LiveLine("Find the camp now.", LiveBox(0.3, 0.8, 0.7, 0.88))), r, 0)
        assertTrue(out.isEmpty)
    }

    @Test fun joinedWithNewline() {
        val out = LiveNoiseFilter().filter(listOf(LiveLine("We ride"), LiveLine("at dawn.")), full, 0)
        assertEquals("We ride\nat dawn.", out.text)
        assertEquals(2, out.lines.size)
    }
}
