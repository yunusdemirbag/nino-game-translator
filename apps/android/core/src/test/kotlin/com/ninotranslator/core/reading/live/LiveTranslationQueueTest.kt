// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading.live

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Sahte çeviri: kaynağa benzemesin diye ters çevrilir. */
private fun tr(t: String) = t.reversed()

class LiveTranslationQueueTest {
    private class Rig(scope: CoroutineScope, pack: Set<String> = emptySet(), failing: Set<String> = emptySet()) {
        val clock = ManualClock()
        val gates = HashMap<String, CompletableDeferred<Unit>>()
        val calls = ArrayList<String>()
        val shows = ArrayList<LiveShow>()
        val failed = ArrayList<String>()
        val q = LiveTranslationQueue(
            scope, clock,
            translate = { t ->
                calls += t
                gates[t]?.await()
                if (t in failing) null else LiveTranslation(tr(t), fromPack = t in pack)
            },
            inPack = { it in pack },
            onShow = { shows += it },
            onFailed = { failed += it },
        )
        fun block(t: String) { gates[t] = CompletableDeferred() }
        fun open(t: String) { gates[t]!!.complete(Unit) }
    }

    private suspend fun settle() = repeat(5) { yield() }

    /** Açılmayan çeviriler testi asmasın diye sonda iptal edilir. */
    private fun run(block: suspend CoroutineScope.() -> Unit) = runBlocking {
        block()
        coroutineContext.cancelChildren()
    }

    @Test fun cleanSentenceGoesAtOnce() = run {
        val r = Rig(this)
        r.q.submit("We ride at dawn.")
        settle()
        assertEquals(listOf("We ride at dawn."), r.calls)
        assertEquals(LiveShow("We ride at dawn.", tr("We ride at dawn."), 15000, false, false, LiveShowKind.NEW), r.shows.single())
    }

    @Test fun brokenHeld800ms() = run {
        val r = Rig(this)
        r.q.submit("We n33d to go.")
        assertEquals("We n33d to go.", r.q.heldText)
        r.clock.now = 799; r.q.tick(); settle()
        assertTrue(r.calls.isEmpty())
        r.clock.now = 800; r.q.tick(); settle()
        assertEquals(listOf("We n33d to go."), r.calls)
    }

    @Test fun partialHeld300ms() = run {
        val r = Rig(this)
        r.q.submit("We ride at dawn")
        r.clock.now = 299; r.q.tick(); settle()
        assertTrue(r.calls.isEmpty())
        r.clock.now = 300; r.q.tick(); settle()
        assertEquals(1, r.calls.size)
    }

    @Test fun packLineIsNotHeld() = run {
        val r = Rig(this, pack = setOf("we ride"))
        r.q.submit("we ride")
        settle()
        assertEquals(listOf("we ride"), r.calls)
        assertTrue(r.shows.single().fromPack)
    }

    @Test fun betterRereadReplacesHoldWithoutRestart() = run {
        val r = Rig(this)
        r.q.submit("We n33d to go now.")
        r.clock.now = 500
        r.q.onReading("We need to go now.")
        assertEquals("We need to go now.", r.q.heldText)
        r.clock.now = 800; r.q.tick(); settle()
        assertEquals(listOf("We need to go now."), r.calls)
    }

    @Test fun cleanMissingLineIsKept() {
        assertEquals("We ride at dawn.\nBring the horses.", LiveTranslationQueue.mergeKeepingCleanLines("We r1de at dawn.\nBring the horses.", "We ride at dawn."))
        run {
            val r = Rig(this)
            r.q.submit("We r1de at dawn.\nBring the horses.")
            r.q.onReading("We ride at dawn.")
            assertEquals("We ride at dawn.\nBring the horses.", r.q.heldText)
        }
    }

    @Test fun negationCorrectionReplacesHold() = run {
        val r = Rig(this)
        r.q.submit("I can do that")
        r.q.onReading("I can't do that")
        assertEquals("I can't do that", r.q.heldText)
    }

    @Test fun unrelatedBrokenIgnored() = run {
        val r = Rig(this)
        r.q.submit("Wait for me")
        r.q.submit("Xq7 zz9")
        assertEquals("Wait for me", r.q.heldText)
    }

    @Test fun emptyRegionFlushesCleanDropsBroken() = run {
        val r = Rig(this)
        r.q.submit("Wait for me")
        r.q.onReading("")
        settle()
        assertEquals(listOf("Wait for me"), r.calls)
        r.q.submit("W4it f0r me n0w")
        r.q.onReading("")
        settle()
        assertEquals(1, r.calls.size)
        assertNull(r.q.heldText)
    }

    @Test fun rereadWithin4000msIsNotNew() = run {
        val r = Rig(this)
        r.q.submit("We ride at dawn.")
        settle()
        r.clock.now = 3000
        r.q.submit("We ride at dawn")
        settle()
        assertEquals(1, r.calls.size)
        r.clock.now = 9000
        r.q.submit("We ride at dawn.")
        settle()
        assertEquals(2, r.calls.size)
    }

    @Test fun atMostTwoWaiting() = run {
        val r = Rig(this)
        r.block("First line here.")
        r.q.submit("First line here.")
        settle()
        for (t in listOf("Second one.", "Third one now.", "Fourth is last.")) r.q.submit(t)
        assertEquals(listOf("Third one now.", "Fourth is last."), r.q.waitingTexts)
        r.open("First line here.")
        settle()
        assertEquals(listOf("First line here.", "Third one now.", "Fourth is last."), r.calls)
    }

    @Test fun correctedReadingReplacesWaiting() = run {
        val r = Rig(this)
        r.block("First line here.")
        r.q.submit("First line here.")
        settle()
        r.q.submit("Hold the gate, men.")
        r.q.submit("Hold the gale, men!")
        assertEquals(listOf("Hold the gale, men!"), r.q.waitingTexts)
    }

    @Test fun partialRunningResultIsHidden() = run {
        val r = Rig(this, pack = setOf("Nobody saw us"))
        r.block("Nobody saw us")
        r.q.submit("Nobody saw us")
        settle()
        r.q.submit("Nobody saw us leave the camp.")
        r.open("Nobody saw us")
        settle()
        assertEquals(listOf("Nobody saw us leave the camp."), r.shows.map { it.source })
    }

    @Test fun lateResultRules() = run {
        val r = Rig(this)
        r.block("We ride at dawn.")
        r.q.submit("We ride at dawn.")
        settle()
        r.clock.now = 100; r.q.onReading("")
        r.clock.now = 2000; r.open("We ride at dawn."); settle()
        assertEquals(LiveTranslationQueue.lateDisplayMs(tr("We ride at dawn.")), r.shows.single().durationMs)
        assertEquals(2000 + 12 * 60L, r.shows.single().durationMs)

        val r2 = Rig(this)
        r2.block("We ride at dawn.")
        r2.q.submit("We ride at dawn.")
        settle()
        r2.clock.now = 100; r2.q.onReading("")
        r2.clock.now = 2601; r2.open("We ride at dawn."); settle()
        assertTrue(r2.shows.isEmpty())
    }

    @Test fun goneRunningCancelledWhenNewWaits() = run {
        val r = Rig(this)
        r.block("We ride at dawn.")
        r.q.submit("We ride at dawn.")
        settle()
        r.clock.now = 100; r.q.onReading("Something else entirely.")
        r.q.submit("Something else entirely.")
        settle()
        assertEquals("Something else entirely.", r.shows.single().source)
        r.open("We ride at dawn."); settle()
        assertEquals(1, r.shows.size)
    }

    @Test fun restoreFromLastEight() = run {
        val r = Rig(this)
        r.q.submit("Hold the gate.")
        settle()
        r.clock.now = 5000
        assertTrue(r.q.restore("Hold the gate"))
        assertEquals(LiveShowKind.RESTORED, r.shows.last().kind)
        assertEquals(tr("Hold the gate."), r.shows.last().translation)
        for (i in 0 until 8) { r.clock.now += 5000; r.q.submit(listOf("Apples fall.", "Birds sing.", "Cats sleep.", "Dogs bark.", "Eagles soar.", "Fish swim.", "Goats climb.", "Horses run.")[i]); settle() }
        assertTrue(!r.q.restore("Hold the gate."))
    }

    @Test fun betterTranslationUpdatesInPlace() = run {
        val r = Rig(this)
        r.q.submit("Hold the gate.")
        settle()
        r.q.onReading("Hold the gate.")
        r.q.improve("Hold the gate.", "Kapıyı tutun.")
        assertEquals(LiveShowKind.UPDATED, r.shows.last().kind)
        assertEquals("Kapıyı tutun.", r.shows.last().translation)

        val p = Rig(this, pack = setOf("Hold the gate."))
        p.q.submit("Hold the gate.")
        settle()
        p.q.improve("Hold the gate.", "Başka")
        assertEquals(1, p.shows.size)
    }

    @Test fun failedTranslationReported() = run {
        val r = Rig(this, failing = setOf("We ride at dawn."))
        r.q.submit("We ride at dawn.")
        settle()
        assertEquals(listOf("We ride at dawn."), r.failed)
        assertTrue(r.shows.isEmpty())
    }

    @Test fun alreadyTurkishNotShown() = run {
        val r = Rig(this)
        val q = LiveTranslationQueue(this, r.clock, { LiveTranslation(it) }, onShow = { r.shows += it })
        q.submit("Tamam, gidelim.")
        settle()
        assertTrue(r.shows.isEmpty())
    }
}
