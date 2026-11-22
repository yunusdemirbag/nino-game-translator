// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.packs

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.GZIPOutputStream

/** Nino'nun kendi deneme paketleriyle (resources/packs: harbor-lights biçim 2 + imzalar, garden-of-ash biçim 1). */
class LegacyPackTest {
    private val lines = listOf(
        "The harbor lights went out right after midnight, and nobody saw the boat leave.",
        "We meet at the old lighthouse.",
    )
    private val harbor get() = TestFiles.pack("harbor-lights")
    private val garden get() = TestFiles.pack("garden-of-ash")

    @Test fun loadsFixturePacks() {
        assertEquals("harbor-lights", harbor.id)
        assertEquals("Harbor Lights", harbor.title)
        assertEquals(7, harbor.entryCount)
        assertEquals(2, harbor.segmentCount)
        assertNotNull("imzalar okunmalı", harbor.fuzzy)
        // 16 harften kısa satırların imzası yok.
        assertEquals(5, harbor.fuzzy!!.size)
        assertEquals("Garden of Ash", garden.title)
        assertEquals(3, garden.entryCount)
        assertNull("havuz paketlerinde bulanık dizin yok", garden.fuzzy)
        assertEquals("Kökler her şeyi hatırlar.", garden.entry(PackKey.longOf("THE ROOTS remember everything!")!!))
    }

    @Test fun storedSignatureEqualsComputed() {
        val index = harbor.fuzzy!!
        for (line in lines) {
            val key = PackKey.longOf(line)!!
            assertNotNull(line, harbor.anyLine(key))
            val i = index.indexOf(key)
            assertTrue(line, i >= 0)
            val folded = FuzzySignature.fold(line)
            assertEquals(FuzzySignature.lengthOf(folded), index.lengths[i])
            assertArrayEquals(FuzzySignature.bloom(folded), index.bloom(i))
        }
        assertEquals(-1, index.indexOf(PackKey.longOf("Now!")!!))
    }

    @Test fun exactAndFuzzyMatchInLibrary() {
        val lib = LegacyPackLibrary(listOf(harbor, garden))
        val tr = harbor.anyLine(PackKey.longOf(lines[0])!!)
        // Konuşmacı etiketi korunur; tam eşleşme oynanan oyunu belirler.
        val m = lib.find("RIVA: " + lines[0])!!
        assertEquals("harbor-lights", m.packId)
        assertEquals("RIVA: $tr", m.text)
        assertEquals("harbor-lights", lib.playedPackId)
        assertEquals(tr, lib.find("RIVA: " + lines[0], showSpeakerNames = false)!!.text)
        // OCR bozuk okuma bulanık eşlemeyle bulunur.
        val damaged = "RIVA: The harb0r lights went out rigbt after midnigt, and nobudy saw the boat leave"
        val f = lib.find(damaged)
        assertNotNull(f)
        assertTrue(f!!.fuzzy)
        assertTrue(f.text.endsWith(tr!!))
        // Tek OCR düzeltmesi (adım 1): birleşen sözcük, fazla harf, rn → m.
        val meet = harbor.anyLine(PackKey.longOf(lines[1])!!)
        assertEquals(meet, lib.find("We meet at the oldlighthouse.")?.text)
        assertEquals(meet, lib.find("We meet at the old lighthousse.")?.text)
        assertEquals(meet, lib.find("We rneet at the old lighthouse.")?.text)
    }

    @Test fun manualGameLimitsSearch() {
        val lib = LegacyPackLibrary(listOf(harbor, garden))
        assertNull(lib.find(lines[1], manualGame = "Garden of Ash"))
        assertNotNull(lib.find(lines[1], manualGame = "harbor-lights"))
        assertNull(lib.find(lines[1], manualGame = "Bilinmeyen Oyun"))
        // Aynı satır iki pakette: elle seçilen oyunun çevirisi gelir.
        assertEquals("Alçal, ses çıkarma.", lib.find("Stay low, keep quiet.", manualGame = "Garden of Ash")?.text)
        assertEquals("Eğil ve sessiz ol.", lib.find("Stay low, keep quiet.", manualGame = "Harbor Lights")?.text)
    }

    @Test fun emptyLibrary() {
        val lib = LegacyPackLibrary(emptyList())
        assertNull(lib.find(lines[0]))
        assertNull(lib.playedPackId)
    }

    private fun gz(s: String): ByteArray = ByteArrayOutputStream().also { o -> GZIPOutputStream(o).use { it.write(s.toByteArray()) } }.toByteArray()

    @Test fun laterKeyWinsAndFormats() {
        val k = PackKey.of("Climb the wall!")!!
        val json = """{"format":2,"id":"x","entries":{"$k":"Duvarı aş!","${k.uppercase()}":"<b>Duvara</b>  tırman!","bad":"y"}}"""
        val p = LegacyPack.load(gz(json).inputStream(), "dosya")
        assertEquals("Duvara tırman!", p.entry(PackKey.longOf("Climb the wall")!!))
        assertEquals("x", p.id); assertEquals("x", p.title)
        assertNull(p.fuzzy)
        val flat = LegacyPack.parse("""{"$k":"Duvarı aş!"}""", "duz-paket")
        assertEquals("duz-paket", flat.id)
        assertEquals("Duvarı aş!", flat.entry(PackKey.longOf("climb the wall")!!))
        assertTrue(runCatching { LegacyPack.parse("""{"format":3,"entries":{"$k":"a"}}""", "a") }.isFailure)
        assertTrue(runCatching { LegacyPack.parse("""{"format":2,"entries":{}}""", "a") }.isFailure)
    }

    @Test fun multiLineAndSentences() {
        val a = PackKey.of("Come here.")!!; val b = PackKey.of("Now!")!!
        val p = LegacyPack.parse("""{"format":2,"id":"t","entries":{"$a":"Buraya gel.","$b":"Hemen!"}}""", "t")
        val lib = LegacyPackLibrary(listOf(p))
        assertEquals("Buraya gel. Hemen!", lib.find("Come here. Now!")?.text)
        assertEquals("Buraya gel.\nHemen!", lib.find("Come here.\nNow!\nMAIN MENU")?.text)
        assertNull(lib.find("Come here.\nSomething else entirely"))
        assertEquals("- Buraya gel.", lib.find("- Come here.")?.text)
    }
}

class FuzzyOneWayTest {
    private val line = "The harbor lights went out right after midnight, and nobody saw the boat leave."

    @Test fun halfAndExcessReadings() {
        val harbor = TestFiles.pack("harbor-lights")
        val lib = LegacyPackLibrary(listOf(harbor, TestFiles.pack("garden-of-ash")))
        val tr = harbor.anyLine(PackKey.longOf(line)!!)!!
        assertNotNull(lib.find(line))
        val half = lib.find("The harbor lights went out right after midnight, and")
        assertEquals(tr, half?.text); assertTrue(half!!.fuzzy)
        val excess = lib.find("$line Press X to skip")
        assertEquals(tr, excess?.text); assertTrue(excess!!.fuzzy)
        assertNull(lib.find("Completely unrelated sentence about purple elephants dancing."))
    }

    @Test fun missIsFastOnLargePack() {
        // Uydurma sözcüklerden 150 bin satırlık paket (gerçek oyun paketi boyunda).
        val rnd = java.util.Random(7)
        val words = listOf("harbor", "lantern", "rope", "tide", "north", "engine", "bay", "guard", "night", "coast",
            "signal", "anchor", "storm", "dock", "crew", "map", "light", "boat", "fog", "shore", "keep", "move", "wait", "now")
        val lines = (0 until 150_000).map { i ->
            val n = 5 + rnd.nextInt(12)
            (0 until n).joinToString(" ") { words[rnd.nextInt(words.size)] }.replaceFirstChar { it.uppercase() } + " $i." to "Satır $i."
        }
        val big = LegacyPack.load(TestFiles.bigPack("big", lines).inputStream(), "big")
        assertNotNull(big.fuzzy)
        val lib = LegacyPackLibrary(listOf(big))
        lib.playedPackId = "big"
        val q = "Nothing in here matches anything at all, really. Purple elephants keep dancing tonight."
        lib.find(q)
        val t0 = System.nanoTime()
        repeat(3) { lib.find(q) }
        val ms = (System.nanoTime() - t0) / 3_000_000
        println("büyük paket ıska: $ms ms")
        assertTrue("ıska $ms ms", ms < 2_000)
    }
}
