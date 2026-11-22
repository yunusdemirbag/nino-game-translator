// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveHelpersTest {
    // --- Bölge ---
    @Test fun regionPresetsAndLimits() {
        assertEquals(RegionPreset.BOTTOM, presetOf(LiveRegion(0.6205, 0.97, 0.14, 0.86)))
        assertEquals(RegionPreset.CUSTOM, presetOf(LiveRegion(0.63, 0.97, 0.14, 0.86)))
        assertEquals(RegionPreset.TOP, presetOf(LiveRegion.TOP))
        assertEquals(RegionPreset.FULL, presetOf(LiveRegion.FULL))
        val tiny = LiveRegion(0.5, 0.51, 0.5, 0.51).clamped()
        assertEquals(0.05, tiny.width, 1e-9); assertEquals(0.05, tiny.height, 1e-9)
        val moved = LiveRegion.BOTTOM.moved(0.5, 0.5)
        assertEquals(1.0, moved.right, 1e-9); assertEquals(1.0, moved.bottom, 1e-9)
        assertEquals(0.72, moved.width, 1e-9)
        val b = LiveRegion.BOTTOM.toFrame(LiveBox(0.0, 0.0, 1.0, 1.0))
        assertEquals(0.14, b.left, 1e-9); assertEquals(0.62, b.top, 1e-9); assertEquals(0.86, b.right, 1e-9); assertEquals(0.97, b.bottom, 1e-9)
    }

    @Test fun subtitleBandAndTaskLine() {
        val samples = (0 until 10).map { LiveBox(0.3, 0.84 + it * 0.001, 0.7, 0.90 + it * 0.001) } + LiveBox(0.3, 0.5, 0.7, 0.6)
        val band = SubtitleBand.learn(samples)!!
        assertEquals(0.84, band.top, 0.002); assertEquals(0.908, band.bottom, 0.002)
        assertNull(SubtitleBand.learn(samples.take(7)))
        assertEquals(0.79, band.narrow(LiveRegion.BOTTOM).top, 0.003)
        assertEquals(LiveRegion.BOTTOM, SubtitleBand(0.97, 0.99).narrow(LiveRegion.BOTTOM))
        assertEquals(0.895, TaskStripLine.compute(null)!!, 1e-9)
        assertEquals(0.94, TaskStripLine.compute(SubtitleBand(0.86, 0.90), listOf(0.04))!!, 1e-9)
        assertNull(TaskStripLine.compute(SubtitleBand(0.90, 0.96), listOf(0.04)))
        assertEquals(0.935, TaskStripLine.compute(SubtitleBand(0.90, 0.96), listOf(0.04), isGta6 = true)!!, 1e-9)
    }

    // --- Kare izi ---
    private fun plane(w: Int, h: Int, f: (Int, Int) -> Int) = LumaPlane(ByteArray(w * h) { i -> f(i % w, i / w).toByte() }, w, h)

    @Test fun cropRoundsToEvenAndRejectsSmall() {
        assertEquals(PixelRect(178, 446, 922, 252), FrameTrace.crop(LiveRegion.BOTTOM, 1280, 720))
        assertNull(FrameTrace.crop(LiveRegion(0.5, 0.51, 0.5, 0.51), 1280, 720))
    }

    @Test fun traces() {
        val a = plane(128, 64) { _, _ -> 100 }
        val b = plane(128, 64) { x, _ -> if (x < 64) 100 else 200 }
        val c = plane(128, 64) { _, _ -> 108 }
        assertEquals(FrameTrace.coarse(a), FrameTrace.coarse(c.let { plane(128, 64) { _, _ -> 101 } }))
        assertTrue(FrameTrace.coarse(a) != FrameTrace.coarse(b))
        val ga = FrameTrace.grid(a); val gb = FrameTrace.grid(b); val gc = FrameTrace.grid(c)
        assertFalse(gc.changedFrom(ga))
        assertTrue(gb.changedFrom(ga))
        assertFalse(gb.changedFrom(ga, LiveBox(0.0, 0.0, 0.45, 1.0))) // yalnız sol yarı
        // Satır adımı
        val strided = LumaPlane(ByteArray(140 * 64) { 100.toByte() }, 128, 64, 140)
        assertFalse(FrameTrace.grid(strided).changedFrom(ga))
    }

    @Test fun unchangedRegionGate() {
        val t = CoarseTrace(byteArrayOf(1, 2, 3))
        val g = UnchangedRegionGate()
        assertFalse(g.shouldReuse(t))
        repeat(20) { assertTrue(g.shouldReuse(t)) }
        assertFalse(g.shouldReuse(t))
        val fast = UnchangedRegionGate(fastDetection = true)
        assertFalse(fast.shouldReuse(t)); assertTrue(fast.shouldReuse(t)); assertTrue(fast.shouldReuse(t)); assertFalse(fast.shouldReuse(t))
    }

    @Test fun readThrottle() {
        val r = ReadThrottle()
        assertTrue(r.tryStart(0)); assertFalse(r.tryStart(300)); r.finish()
        assertFalse(r.tryStart(100)); assertTrue(r.tryStart(300))
    }

    // --- Cümle bölücü ---
    @Test fun sentenceSplitting() {
        assertEquals(listOf("Lt. Dan went up Mt. Fuji.", "Then he left."), LiveSentences.split("Lt. Dan went up Mt. Fuji. Then he left."))
        assertEquals(listOf("J. R. R. Tolkien wrote it."), LiveSentences.split("J. R. R. Tolkien wrote it."))
        assertEquals(listOf("Wait... what?"), LiveSentences.split("Wait... what?"))
        assertEquals(listOf("\"Run.\"", "Go!"), LiveSentences.split("\"Run.\" Go!"))
        assertEquals(listOf("Capt. Price and Sgt. Soap are here."), LiveSentences.split("Capt. Price and Sgt. Soap are here."))
    }

    @Test fun segmentsAndDashes() {
        val s = LiveSentences.segments("- Run! - Where?\n- Over there.\nATREUS: Father,\nwait for me.\nMimir Head: Brother.")
        assertEquals(listOf("- ", "- ", "ATREUS: ", "Mimir Head: "), s.map { it.prefix })
        assertEquals(listOf("Run! - Where?", "Over there.", "Father, wait for me.", "Brother."), s.map { it.body })
        assertEquals("- Run! - Where?\n- Over there.\nATREUS: Father, wait for me.\nMimir Head: Brother.", LiveSentences.join(s))
        assertFalse(LiveSentences.Segment("", "...").translatable)
    }

    @Test fun allCapsSentenceCase() {
        assertEquals("The bridge will not last.", LiveSentences.sentenceCase("THE BRIDGE WILL NOT LAST."))
        assertEquals("I told Atreus to run. Now go!", LiveSentences.sentenceCase("I TOLD ATREUS TO RUN. NOW GO!", setOf("atreus")))
        assertEquals("NO", LiveSentences.sentenceCase("NO"))
        assertEquals("Already fine.", LiveSentences.sentenceCase("Already fine."))
    }

    @Test fun packLookupOrder() {
        val pack = mapOf("We ride." to "Sürüyoruz.", "Go now." to "Şimdi git.", "Hold." to "Tut.", "Run!" to "Koş!")
        assertEquals("Sürüyoruz.", LiveSentences.lookupPack("We ride.", pack::get))
        assertEquals("ARTHUR: Sürüyoruz.", LiveSentences.lookupPack("ARTHUR: We ride.", pack::get))
        assertEquals("Sürüyoruz.\nŞimdi git.", LiveSentences.lookupPack("We ride.\nGo now.", pack::get))
        assertEquals("Tut. Koş!", LiveSentences.lookupPack("Hold. Run!", pack::get))
        assertNull(LiveSentences.lookupPack("Hold. Unknown thing!", pack::get))
        assertEquals("Sürüyoruz.\nMain Menu", LiveSentences.lookupPack("We ride.\nMain Menu", pack::get))
        assertEquals("Sürüyoruz.", LiveSentences.lookupPack("We rlde.", pack::get) { k -> pack.entries.firstOrNull { LiveText.similarity(it.key, k) > 0.8 }?.value })
    }

    // --- Konuşmacı öneki ---
    @Test fun speakerPrefix() {
        assertEquals(SpeakerPrefix.Parsed("MARA", "The boat is leaving."), SpeakerPrefix.parse("MARA: The boat is leaving."))
        assertEquals("Mr. Okafor", SpeakerPrefix.parse("Mr. Okafor：Sit down.")!!.name)
        assertEquals("OLD MAN", SpeakerPrefix.parse("OLD MAN : Hm.")!!.name)
        assertEquals("The boat is leaving.", SpeakerPrefix.parse("Mara:\nThe boat is leaving.")!!.body)
        for (t in listOf("7:45 at the harbor.", "Ratio 16:9", "HTTPS://example.com", "Tip: the door is locked.", "We warned you: run!",
            "Much Too Long A Title: here", "Maximilianus Wetherington: Yo.", "MARA:")) assertNull(t, SpeakerPrefix.parse(t))
        assertEquals("MARA: Tekne kalkıyor.", SpeakerPrefix.withName("MARA", "Tekne kalkıyor."))
        assertEquals("Evet.\nHayır.", SpeakerPrefix.stripNames("MARA: Yes.\nJONAH: No.", "MARA: Evet.\nJONAH: Hayır."))
        assertEquals("Hedef: Kampa dön.", SpeakerPrefix.stripNames("MARA: Back to camp.", "Hedef: Kampa dön."))
    }

    // --- Satır kaydırma ---
    @Test fun wrapKeepsSpeakerWithNextWord() {
        val w = LineWrapper.wrap("ARTHUR: Bu kapıyı daha fazla tutamayız, hemen gitmemiz gerekiyor dostum.")
        assertTrue(w.lines[0].startsWith("ARTHUR: Bu"))
        assertEquals(listOf("Zaten\nsatır sonu var ve bu yazı kırk iki harften uzun olsa da"), LineWrapper.wrap("Zaten\nsatır sonu var ve bu yazı kırk iki harften uzun olsa da").lines)
        assertEquals(1200L, LineWrapper.phoneDisplayMs("Kısa", 500))
        assertEquals(3000L, LineWrapper.phoneDisplayMs("x", 3000))
        assertEquals(2000L + 4 * 60, LineWrapper.phoneDisplayMs("Kısa"))
        assertEquals(8000L, LineWrapper.phoneDisplayMs("a".repeat(200)))
    }

    // --- Oyun algılama ---
    @Test fun gameNames() {
        assertTrue(GameNames.isPs5TitleId("PPSA01234")); assertTrue(GameNames.isPs5TitleId("PPSA01234_00"))
        assertFalse(GameNames.isPs5TitleId("PPS01234")); assertFalse(GameNames.isPs5TitleId("ppsa01234"))
        assertEquals("God of War", GameNames.cleanReportedName("God\u0000 of War\n"))
        assertEquals(120, GameNames.cleanReportedName("x".repeat(300)).length)
        assertTrue(GameNames.sameGame("Grand Theft Auto VI", "GTA 6"))
        assertTrue(GameNames.sameGame("GTA6", "gta 6"))
        assertTrue(GameNames.sameGame("Pokémon", "Pokemon"))
        assertFalse(GameNames.sameGame("GTA V", "GTA 6"))
    }

    @Test fun gameResolverPriority() {
        val g = GameResolver()
        g.screenGame = "GTA 6"; assertEquals("GTA 6", g.current)
        g.packGame = "rdr2"; assertEquals("rdr2", g.current)
        g.userGame = "God of War"; assertEquals("God of War", g.current)
        g.onPs5Reported("God of War Ragnarök")
        assertNull(g.userGame)
        assertEquals("God of War Ragnarök", g.current)
        g.userGame = "Astro Bot"; g.onPs5Reported("Astro Bot"); assertEquals("Astro Bot", g.userGame)
    }

    @Test fun packGuess() {
        val p = PackGameGuesser()
        repeat(4) { assertNull(p.record(setOf("gta6", "genel"))) }
        assertNull(p.record(setOf("gta6", "rdr2")))
        assertEquals("gta6", p.record(setOf("gta6")))
        repeat(20) { p.record(setOf("genel")) }
        assertNull(p.guess())
    }

    @Test fun gta6ScreenHints() {
        assertTrue(Gta6Hints.looksLikeGta6(listOf("Recenter", "Add Marker")))
        assertFalse(Gta6Hints.looksLikeGta6(listOf("Recenter")))
        assertTrue(Gta6Hints.looksLikeGta6(listOf("Jason and Lucia are here")))
        assertFalse(Gta6Hints.looksLikeGta6(listOf("Jason", "Lucia")))
        assertTrue(Gta6Hints.looksLikeGta6(listOf("Brief", "Progress", "Map")))
        assertTrue(Gta6Hints.looksLikeGta6(listOf("whatup")))
        assertTrue(Gta6Hints.looksLikeGta6(emptyList(), phoneRead = true))
    }

    // --- Ek alanlar ve ekranı çevir ---
    @Test fun areaLines() {
        val out = AreaLines.filter(listOf(LiveLine("R2 Aim"), LiveLine("A b"), LiveLine("Find the camp"), LiveLine("ou\$3e")))
        assertEquals(listOf("Find the camp"), out.map { it.text })
        assertEquals(listOf("NEW QUEST", "Find the camp before night falls."), AreaLines.joinParts(listOf("NEW QUEST", "Find the camp", "before night falls.")))
        assertEquals(listOf("Talk to Dutch. Then ride.", "Go."), AreaLines.joinParts(listOf("Talk to Dutch. Then ride.", "Go.")))
        assertEquals(listOf("Ride to Valentine, then Meet Hosea."), AreaLines.joinParts(listOf("Ride to Valentine, then", "Meet Hosea.")))
        assertFalse(AreaLines.worthShowing("Tamam", "Tamam"))
        assertEquals(12000L, AreaLines.screenDisplayMs("Kısa"))
        assertEquals(60000L, AreaLines.screenDisplayMs("a".repeat(2000)))
        assertEquals(8000L + 100 * 50, AreaLines.screenDisplayMs("a".repeat(100)))
    }

    @Test fun screenGrouping() {
        fun l(t: String, a: Double, b: Double, c: Double, d: Double) = LiveLine(t, LiveBox(a, b, c, d))
        val groups = AreaLines.groupForScreen(listOf(
            l("Column one top", 0.05, 0.10, 0.35, 0.14), l("Column one more", 0.05, 0.15, 0.35, 0.19),
            l("Column two top", 0.60, 0.10, 0.90, 0.14), l("Column two more", 0.60, 0.15, 0.90, 0.19),
            l("Wide line across both columns", 0.05, 0.20, 0.90, 0.24),
            l("HUGE TITLE", 0.05, 0.25, 0.35, 0.40),
        ))
        assertEquals(4, groups.size)
        assertEquals(2, groups[0].size)
        assertEquals(30, AreaLines.groupForScreen((0 until 40).map { l("Line $it", 0.0, it * 0.1, 0.1, it * 0.1 + 0.02) }).size)
    }

    @Test fun controllerHintTokens() {
        assertTrue(ControllerHints.isButton("L1")); assertTrue(ControllerHints.isButton("△"))
        assertNotNull(SpeakerPrefix.parse("ENZO: Let's go"))
    }
}
