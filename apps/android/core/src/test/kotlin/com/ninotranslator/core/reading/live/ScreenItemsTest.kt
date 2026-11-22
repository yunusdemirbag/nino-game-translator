// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ekran öğeleri: 60 sn yenileme, kalkma histerezisi, kart çevirisi önbelleği (sahte saat). */
class ScreenItemsTest {
    private val card = listOf(mapOf<String, Any?>("text" to "AVERY PAWN\nRehinci.", "card" to true))

    // ---- yenileme ----

    @Test fun unchangedCardIsResentEverySixtySecondsWithTwoMinuteDuration() {
        val clock = ManualClock()
        val r = ScreenRefresh()
        assertEquals(ScreenRefresh.Action.Send(card, 120_000), r.set(card, clock.now))
        val sends = ArrayList<Long>()
        while (clock.now < 185_000) {
            clock.advance(1_000)
            assertEquals(ScreenRefresh.Action.None, r.set(card, clock.now)) // aynı liste: hemen yeniden gitmez
            val a = r.tick(clock.now)
            if (a is ScreenRefresh.Action.Send) { assertEquals(card, a.items); assertEquals(120_000, a.durationMs); sends += clock.now }
        }
        assertEquals(listOf(60_000L, 120_000L, 180_000L), sends)
        assertEquals(ScreenRefresh.Action.Clear, r.set(emptyList(), clock.now))
        clock.advance(60_000)
        assertEquals(ScreenRefresh.Action.None, r.tick(clock.now))
        assertEquals(ScreenRefresh.Action.None, r.set(emptyList(), clock.now))
    }

    @Test fun changedListGoesAtOnceAndRestartsTheTimer() {
        val r = ScreenRefresh()
        r.set(card, 0)
        val other = card + mapOf("text" to "Mesaj")
        assertEquals(ScreenRefresh.Action.Send(other), r.set(other, 30_000))
        assertEquals(ScreenRefresh.Action.None, r.tick(60_000))
        assertEquals(ScreenRefresh.Action.Send(other), r.tick(90_000))
    }

    @Test fun manualResultPausesTheRefreshAndResumeResends() {
        val r = ScreenRefresh()
        r.set(card, 0)
        r.pause()
        assertEquals(ScreenRefresh.Action.None, r.tick(60_000))
        assertEquals(ScreenRefresh.Action.None, r.set(card, 61_000))
        assertEquals(ScreenRefresh.Action.Send(card), r.resume(70_000))
        assertEquals(ScreenRefresh.Action.Send(card), r.tick(130_000))
    }

    // ---- histerezis (sahte iz) ----

    private fun trace(v: Int) = RegionTrace(IntArray(FrameTrace.GRID_W * FrameTrace.GRID_H) { v })
    private val box = LiveBox(0.55, 0.4, 0.8, 0.6)

    @Test fun oneMissedReadDoesNotRemoveTheCard() {
        val h = ScreenItemHold()
        h.onSeen(box, trace(40))
        assertFalse(h.onMissing(trace(200), 2_000))
        h.onSeen(box, trace(40))
        assertFalse(h.onMissing(trace(200), 6_000))
        assertFalse(h.onMissing(trace(200), 8_000))
        assertTrue(h.showing)
    }

    @Test fun threeMissesFourSecondsAndAChangedPictureRemoveTheCard() {
        val h = ScreenItemHold()
        h.onSeen(box, trace(40))
        assertFalse(h.onMissing(trace(200), 2_000))
        assertFalse(h.onMissing(trace(200), 4_000))
        assertFalse("3 okuma ama 4 sn dolmadı", h.onMissing(trace(200), 5_500))
        assertTrue(h.onMissing(trace(200), 6_000))
        assertFalse(h.showing)
        assertFalse(h.onMissing(trace(200), 8_000)) // kalkan kart yeniden kalkmaz
    }

    @Test fun unchangedPictureKeepsTheCardEvenAfterManyMisses() {
        val h = ScreenItemHold()
        h.onSeen(box, trace(40))
        var t = 0L
        repeat(30) { t += 2_000; assertFalse(h.onMissing(trace(45), t)) } // gürültü kadar oynama
        assertTrue(h.showing)
        assertTrue(h.onMissing(trace(200), t + 2_000))
    }

    // ---- ortak tahta (NinoCore ScreenItemSender vakaları; 4 sn ilk kaçırmadan sayılır) ----

    private val cardA = listOf(mapOf<String, Any?>("text" to "A", "card" to true))
    private val cardB = listOf(mapOf<String, Any?>("text" to "B", "card" to true))
    private val phoneItems = listOf(mapOf<String, Any?>("text" to "", "backdrop" to true), mapOf<String, Any?>("text" to "Merhaba"))
    private val MAP = ScreenItemBoard.Kind.MAP
    private val PHONE = ScreenItemBoard.Kind.PHONE

    @Test fun boardKeepsAnItemWhileItsRegionLooksTheSame() {
        val b = ScreenItemBoard()
        b.seen(MAP, box, trace(40), cardA)
        for (t in 600L..10_000L step 600) assertFalse("t=$t", b.missing(MAP, trace(42), t))
        assertEquals(cardA, b.list())
    }

    @Test fun boardRemovesAfterThreeMissesFourSecondsAndAChangedRegion() {
        val b = ScreenItemBoard()
        b.seen(MAP, box, trace(40), cardA)
        assertFalse(b.missing(MAP, trace(200), 600))
        assertFalse(b.missing(MAP, trace(200), 1_200))
        assertFalse("3 kaçırma ama 4 sn dolmadı", b.missing(MAP, trace(200), 1_800))
        assertFalse(b.missing(MAP, trace(200), 4_000))
        assertTrue(b.missing(MAP, trace(200), 4_600))
        assertTrue(b.list().isEmpty())
        assertNull(b.area(MAP))
    }

    @Test fun boardReplacesAtOnceAndDropsOnRequest() {
        val b = ScreenItemBoard()
        b.seen(MAP, box, trace(40), cardA)
        assertFalse(b.missing(MAP, trace(40), 600))
        b.seen(MAP, box, trace(40), cardB) // başka kart: hemen değişir
        assertEquals(cardB, b.list())
        assertFalse(b.missing(MAP, trace(200), 1_200))
        assertTrue("menü kapandı: hemen kalkar", b.drop(MAP))
        assertTrue(b.list().isEmpty())
        assertFalse(b.drop(MAP))
        assertFalse("kalkan öğe yeniden kalkmaz", b.missing(MAP, trace(200), 9_000))
    }

    @Test fun boardKindsAreIndependentAndPhoneComesFirst() {
        val b = ScreenItemBoard()
        b.seen(MAP, box, trace(40), cardA)
        b.seen(PHONE, LiveBox(0.59, 0.2, 0.79, 0.82), trace(120), phoneItems)
        assertEquals(phoneItems + cardA, b.list())
        // Telefon kayboldu ve yeri değişti; harita kartı etkilenmez.
        var t = 0L
        var gone = false
        repeat(6) { t += 1_000; gone = b.missing(PHONE, trace(10), t) || gone }
        assertTrue(gone)
        assertEquals(cardA, b.list())
        b.seen(PHONE, LiveBox(0.59, 0.2, 0.79, 0.82), trace(120), phoneItems)
        b.reset()
        assertTrue(b.isEmpty())
        assertNull(b.area(PHONE)); assertNull(b.area(MAP))
    }

    @Test fun mapCardKeeperUsesTheSharedBoard() {
        val b = ScreenItemBoard()
        val k = MapCardKeeper(board = b)
        val crop = LumaPlane(ByteArray(800 * 400), 800, 400)
        runBlocking { k.seen(MapCardText("T", listOf("Cal challenged you to catch a fish"), box), crop, LiveRegion(0.0, 1.0, 0.0, 1.0)) { "x" } }
        assertTrue(b.hold(MAP).showing)
        k.reset()
        assertFalse(k.hold.showing)
    }

    // ---- önbellek ----

    @Test fun reReadCardComesFromTheCacheNotTheTranslator() = runBlocking {
        val k = MapCardKeeper()
        val crop = LumaPlane(ByteArray(800 * 400), 800, 400)
        val region = LiveRegion(0.0, 1.0, 0.0, 1.0)
        val c = MapCardText("CATCH A BIGGER FISH", listOf("Cal challenged you to catch a stoplight", "parrotfish larger than 0.9 kg."), box)
        var calls = 0
        val tr: suspend (MapCardText) -> String? = { calls++; "DAHA BÜYÜK BALIK TUT\nCal seni..." }
        assertEquals("DAHA BÜYÜK BALIK TUT\nCal seni...", k.seen(c, crop, region, tr))
        assertEquals("DAHA BÜYÜK BALIK TUT\nCal seni...", k.seen(c.copy(box = LiveBox(0.55, 0.41, 0.8, 0.61)), crop, region, tr))
        assertEquals(1, calls)
        // Çeviri başarısızsa önbelleğe girmez, sonra yeniden denenir.
        var failCalls = 0
        val other = c.copy(title = "DEPOSIT CASH", sentences = listOf("Make a cash deposit into your BuckMe"))
        assertNull(k.seen(other, crop, region) { failCalls++; null })
        assertEquals("ok", k.seen(other, crop, region) { failCalls++; "ok" })
        assertEquals(2, failCalls)
    }
}
