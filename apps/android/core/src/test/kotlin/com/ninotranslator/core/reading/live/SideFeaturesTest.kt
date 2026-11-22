// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class SideFeaturesTest {
    private fun trace(v: Int) = CoarseTrace(byteArrayOf(v.toByte(), 1, 2))
    private fun line(t: String, l: Double = 0.0, top: Double = 0.0, r: Double = 1.0, b: Double = 0.5) = LiveLine(t, LiveBox(l, top, r, b))

    // --- Ek alanlar (okuma.md 11) ---
    @Test fun extraAreaNeedsStableText() {
        val t = ExtraAreaTracker()
        val region = LiveRegion.QUEST
        assertTrue(t.shouldRead(trace(1)))
        assertEquals(ExtraAreaTracker.Decision.Nothing, t.onRead(listOf(line("Go to the docks")), region))
        // İz bir tur değişmedi: yazı kararlı.
        assertFalse(t.shouldRead(trace(1)))
        val d = t.unchangedRound() as ExtraAreaTracker.Decision.Translate
        assertEquals(listOf("Go to the docks"), d.parts)
        assertEquals(0.66, d.box!!.left, 1e-9); assertEquals(0.03, d.box!!.top, 1e-9)
        // Yazı değişmedikçe yeniden çevrilmez.
        assertEquals(ExtraAreaTracker.Decision.Nothing, t.unchangedRound())
        assertTrue(t.shouldRead(trace(2)))
        assertEquals(ExtraAreaTracker.Decision.Nothing, t.onRead(listOf(line("Go to the docks")), region))
        // İz her tur değişse de iki okuma aynı yazıyı verirse çevrilir.
        t.shouldRead(trace(3)); assertEquals(ExtraAreaTracker.Decision.Nothing, t.onRead(listOf(line("Meet Cal at the bar")), region))
        t.shouldRead(trace(4)); assertTrue(t.onRead(listOf(line("Meet Cal at the bar")), region) is ExtraAreaTracker.Decision.Translate)
        // Okuma hatası alanı boş saymaz; iz sıfırlanır.
        assertEquals(ExtraAreaTracker.Decision.Nothing, t.onRead(null, region))
        assertTrue(t.shouldRead(trace(4)))
        // Boşalan alanın kutusu kalkar (iki boş okuma).
        t.shouldRead(trace(5)); assertEquals(ExtraAreaTracker.Decision.Nothing, t.onRead(emptyList(), region))
        t.shouldRead(trace(6)); assertEquals(ExtraAreaTracker.Decision.Clear, t.onRead(listOf(line("X")), region))
    }

    @Test fun extraAreaJoinsParts() {
        val t = ExtraAreaTracker()
        val lines = listOf(line("OBJECTIVE", top = 0.0, b = 0.2), line("Find the car", top = 0.25, b = 0.45), line("and drive home.", top = 0.5, b = 0.7))
        t.shouldRead(trace(1)); t.onRead(lines, LiveRegion.QUEST)
        t.shouldRead(trace(1))
        val d = t.unchangedRound() as ExtraAreaTracker.Decision.Translate
        assertEquals(listOf("OBJECTIVE", "Find the car and drive home."), d.parts)
    }

    // --- Ekranı çevir (okuma.md 12) ---
    @Test fun screenPlanGroupsAndDuration() {
        val lines = listOf(
            line("Welcome to the city", 0.1, 0.10, 0.4, 0.13),
            line("of dreams and dust", 0.1, 0.135, 0.38, 0.165),
            line("Press start to continue", 0.6, 0.80, 0.9, 0.83),
            line("x", 0.6, 0.9, 0.62, 0.92),
        )
        val g = ScreenPlan.groups(lines)
        assertEquals(2, g.size)
        assertEquals("Welcome to the city of dreams and dust", g[0].text)
        assertEquals(2, g[0].lines)
        assertEquals(true, ScreenPlan.item(g[0], "Hayaller şehrine hoş geldin")["paragraphs"])
        assertNull(ScreenPlan.item(g[1], "Devam")["paragraphs"])
        assertEquals(12_000L, ScreenPlan.durationMs(g))
        assertEquals(60_000L, AreaLines.screenDisplayMs("a".repeat(5000)))
        assertEquals(30, ScreenPlan.groups((0 until 40).map { i -> line("Line number $i", (i % 8) * 0.12, (i / 8) * 0.2, (i % 8) * 0.12 + 0.1, (i / 8) * 0.2 + 0.03) }).size)
    }

    // --- Oyun sorma kartı ve ekrandan tanıma (okuma.md 13) ---
    @Test fun askGameCardTiming() {
        val c = GameAskCard(startedAtMs = 0)
        assertFalse(c.check(60_000, gameKnown = false, askGame = true, sharePool = true))
        assertTrue(c.check(120_000, gameKnown = false, askGame = true, sharePool = true)); assertTrue(c.open)
        assertFalse(c.check(135_000, false, true, true))
        assertTrue(c.onGameKnown()); assertFalse(c.open)
        // Oturumda bir kez.
        assertFalse(c.check(400_000, false, true, true))
        // "Değiştir" elle açar; tanınma elle açılanı kapatmaz.
        c.openManually(); assertTrue(c.open); assertFalse(c.onGameKnown()); assertTrue(c.open)
        c.close(neverAgain = false); assertFalse(c.open)
        val never = GameAskCard(0).apply { close(neverAgain = true) }
        assertFalse(never.check(200_000, false, true, true))
        assertFalse(GameAskCard(0).check(200_000, false, askGame = false, sharePool = true))
        assertFalse(GameAskCard(0).check(200_000, false, askGame = true, sharePool = false))
        assertFalse(GameAskCard(0).check(200_000, gameKnown = true, askGame = true, sharePool = true))
        assertEquals(listOf("GTA 6", "The Last of Us"), GameAskCard.suggestions("GTA 6", listOf("Grand Theft Auto VI", "The Last of Us", "the last of us", " ")))
    }

    @Test fun identifyGate() {
        assertEquals(768 to 432, ScreenIdentifyGate.scaledSize(1920, 1080))
        assertEquals(640 to 360, ScreenIdentifyGate.scaledSize(640, 360))
        assertTrue(ScreenIdentifyGate.allowed(sharePool = true, manualGame = false, fromClip = false, ps5Game = false, packGame = false))
        assertFalse(ScreenIdentifyGate.allowed(false, false, false, false, false))
        assertFalse(ScreenIdentifyGate.allowed(true, true, false, false, false))
        assertFalse(ScreenIdentifyGate.allowed(true, false, true, false, false))
        assertFalse(ScreenIdentifyGate.allowed(true, false, false, true, false))
        assertFalse(ScreenIdentifyGate.allowed(true, false, false, false, true))
    }

    // --- Harita kartı (okuma.md 10) ---
    @Test fun mapCardFindAndRules() {
        val lines = listOf(
            line("BUY FLOWERS", 0.62, 0.40, 0.80, 0.43),
            line("Pick up some flowers for Lucia at the shop.", 0.62, 0.435, 0.95, 0.465),
            line("Then drive back home.", 0.62, 0.47, 0.85, 0.50),
            line("1.53 km", 0.62, 0.51, 0.68, 0.54),
            line("Some left side menu text here", 0.05, 0.40, 0.25, 0.43),
        )
        val c = MapCards.find(lines)!!
        assertEquals("BUY FLOWERS", c.title)
        assertEquals(listOf("Pick up some flowers for Lucia at the shop.", "Then drive back home."), c.sentences)
        assertEquals("Go home", MapCards.cleanLine("➤ Go home 2.1 mi"))
        // Gösterilmeyenler.
        assertFalse(MapCards.shows(MapCardText(null, listOf("Drive to the old pier"), LiveBox(0.4, 0.4, 0.8, 0.45))))
        assertFalse(MapCards.shows(MapCardText("TITLE", listOf("Some long enough sentence here"), LiveBox(0.4, 0.05, 0.8, 0.2))))
        assertFalse(MapCards.shows(MapCardText("BAŞLIK", listOf("Çiçek al ve eve dön lütfen"), LiveBox(0.4, 0.4, 0.8, 0.45))))
        assertFalse(MapCards.shows(MapCardText(null, listOf("Drive to the old pier and wait for Cal there"), LiveBox(0.65, 0.2, 0.9, 0.3))))
        assertNull(MapCards.find(listOf(line("Hello", 0.5, 0.5, 0.6, 0.55))))
        assertTrue(MapCards.isPlaceName("RIDEOUT CUSTOMS")); assertFalse(MapCards.isPlaceName("BUY FLOWERS"))
        assertEquals("işaretli banknot ve uyuşturucu", MapCards.fix("işaretli fatura ve narkotik"))
        assertEquals("ÇİÇEK AL", MapCards.upper("çiçek al", "tr"))
        val (below, _) = MapCards.place(c.box, 3)
        assertTrue(below.top > c.box.bottom)
        val (above, _) = MapCards.place(LiveBox(0.6, 0.7, 0.9, 0.9), 3)
        assertTrue(above.bottom < 0.7)
        assertEquals(true, MapCards.item(below, 0.03, "Çiçek al")["card"])
    }

    @Test fun mapCardMemoryAndTiming() {
        val m = MapCardMemory(max = 2)
        val full = MapCardText("BUY FLOWERS", listOf("Pick up some flowers for Lucia at the shop."), LiveBox(0.6, 0.4, 0.9, 0.5))
        val half = MapCardText("BUY FLOWERS", listOf("Pick up some"), LiveBox(0.6, 0.4, 0.9, 0.5))
        m.put(full, "ÇİÇEK AL\nLucia için dükkândan çiçek al.")
        m.put(half, "yarım")
        assertEquals("ÇİÇEK AL\nLucia için dükkândan çiçek al.", m.get(half))
        val s = MapState()
        s.onMapSeen(0)
        assertTrue(s.mapOpen(5_000)); assertFalse(s.mapOpen(5_001))
        assertTrue(s.phoneBlocked(13_000)); assertFalse(s.phoneBlocked(13_001))
        assertEquals(1_500L, s.cardIntervalMs(15_000)); assertEquals(2_000L, s.cardIntervalMs(15_001))
        assertTrue(Gta6Hints.isMapScreen(listOf("RECENTER", "Set Destination")))
    }

    @Test fun gta6SubtitleRules() {
        val r = Gta6SubtitleRules()
        assertTrue(r.drop("Book Ryde (\$82)", LiveBox(0.4, 0.85, 0.6, 0.9), 0))
        assertTrue(r.drop("Meet me later", LiveBox(0.7, 0.8, 0.95, 0.85), 0))
        assertTrue(r.drop("Meet me later", LiveBox(0.0, 0.85, 0.3, 0.9), 0))
        assertFalse(r.drop("Meet me later", LiveBox(0.3, 0.85, 0.7, 0.9), 0))
        r.onPhone(LiveBox(0.4, 0.2, 0.6, 0.8), 1_000)
        assertTrue(r.drop("Where are you", LiveBox(0.42, 0.5, 0.58, 0.55), 1_000))
        assertTrue(r.drop("Where are you", LiveBox(0.3, 0.7, 0.7, 0.75), 1_000))
        assertEquals(0.84, r.blackout(1_000)!!.bottom, 1e-9)
        assertFalse(r.drop("Where are you", LiveBox(0.3, 0.7, 0.7, 0.75), 6_001))
        assertNull(r.blackout(6_001))
        // Oyun GTA 6 diye bilinmiyorsa "her zaman" kuralları uygulanmaz; telefona bağlı olanlar kalır.
        assertFalse(r.drop("Meet me later", LiveBox(0.0, 0.85, 0.3, 0.9), 0, gta6 = false))
        assertFalse(r.drop("Pick me up", LiveBox(0.7, 0.8, 0.95, 0.85), 0, darkOnLight = true, gta6 = false))
        // Bilinen uygulama satırının tamamı ise oyun bilinmese de atılır (okuma.md 9).
        assertTrue(r.drop("Book Ryde", LiveBox(0.7, 0.8, 0.95, 0.85), 0, gta6 = false))
        r.onPhone(LiveBox(0.4, 0.2, 0.6, 0.8), 7_000)
        assertTrue(r.drop("Where are you", LiveBox(0.42, 0.5, 0.58, 0.55), 7_000, gta6 = false))
        r.onMessages(listOf("Meet me at the bar tonight, okay?"), 10_000)
        assertTrue(r.drop("meet me at the bar", LiveBox(0.3, 0.85, 0.7, 0.9), 20_000))
        assertFalse(r.drop("meet me at the bar", LiveBox(0.3, 0.85, 0.7, 0.9), 41_000))
    }

    @Test fun phoneMemoryPersistsAndEmpties() {
        val dir = Files.createTempDirectory("nino-phone").toFile()
        val m = PhoneMessageMemory(dir, "tr", max = 3)
        m.put("See you soon", "Yakında görüşürüz")
        assertEquals("Yakında görüşürüz", PhoneMessageMemory(dir, "tr").get("see you soon!"))
        m.put("a b", "1"); m.put("c d", "2")
        assertEquals(3, m.size())
        m.put("e f", "3")
        assertEquals(1, m.size())
        assertNull(PhoneMessageMemory(dir, "ar").get("e f"))
        assertEquals("Ryde çağır", PhoneFixedTurkish.get("Book Ryde (\$82)"))
        assertNotNull(PhoneFixedTurkish.get("STEPS TODAY"))
    }
}
