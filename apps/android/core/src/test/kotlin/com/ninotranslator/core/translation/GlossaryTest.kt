// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import com.ninotranslator.core.json.Json
import com.ninotranslator.core.packs.TestFiles
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.regex.Pattern

class GlossaryTest {
    private val sample = """{
        "_about": "deneme",
        "game": "Deneme",
        "terms": {"grappling hook": "tırmanma kancası", "grappling hook point": "tırmanma kancası noktası", "ammo": "cephane", "  crafting   bench ": "üretim tezgâhı", "1234": "x", "boş": ""},
        "keep": ["Night City", "Kratos"],
        "keepExact": ["Ghost"],
        "phrases": {"gonna": "going to", "c['’]mon": "come on", "(?:yep|yeah) sure": "yes", "bozuk(": "x"},
        "lines": {"Follow me": "Beni takip et", "  I'm OUT of arrows!! ": "Oklarım bitti", "Got it": "Anladım."}
    }"""
    private val g = Glossary.parse(sample)

    @Test fun parsesSections() {
        // Harfsiz ve Türkçesi boş terim alınmaz; boşluklar teklenir.
        assertEquals(4, g.termCount)
        assertEquals("üretim tezgâhı", g.find("Open the crafting bench")[0].target)
        assertEquals(3, g.lineCount)
        assertEquals("Beni takip et", g.line("follow me"))
        assertEquals("Beni takip et!", g.line("  FOLLOW ME! "))
        assertEquals("Oklarım bitti.", g.line("I’m out of arrows."))
        // Türkçede son işaret varsa kaynağınki eklenmez.
        assertEquals("Anladım.", g.line("Got it!"))
        assertNull(g.line("Follow me home"))
    }

    @Test fun phrasesWholeWordAndCase() {
        assertEquals("I'm going to win", g.applyPhrases("I'm gonna win"))
        assertEquals("Come on, move", g.applyPhrases("C'mon, move"))
        assertEquals("come on", g.applyPhrases("c’mon"))
        assertEquals("Yes, over", g.applyPhrases("Yeah sure, over"))
        // Tam sözcük sınırı: "gonnas" değişmez; bozuk ifade atlanır.
        assertEquals("gonnas", g.applyPhrases("gonnas"))
    }

    @Test fun termsLongestFirstWholeWordKeepExact() {
        val hits = g.find("Find the Grappling Hook Point near Night City, Ghost and the ghost carry ammo.")
        assertEquals(listOf("Grappling Hook Point", "Night City", "Ghost", "ammo"), hits.map { it.source })
        assertEquals("tırmanma kancası noktası", hits[0].target)
        assertTrue(hits[1].kept); assertEquals("Night City", hits[1].target)
        assertTrue(hits[2].kept)
        assertEquals("cephane", hits[3].target)
        assertTrue(g.find("ammonia").isEmpty())
        assertTrue(g.properWords.containsAll(listOf("Night", "City", "Kratos", "Ghost")))
    }

    @Test fun userFilesMergeLaterWins() {
        val dir = TestFiles.tempDir()
        File(dir, "a.json").writeText("""{"terms":{"Lockpick":"maymuncuk","Sky Shield":"Gök Kalkanı"},"keep":["Atreus"]}""")
        File(dir, "b.json").writeText("""{"terms":{"lockpick":"kilit açacağı"}}""")
        File(dir, "c.json").writeText("bozuk")
        val merged = Glossary.load(sample, dir)
        assertEquals("kilit açacağı", merged.find("Use the lockpick")[0].target)
        assertEquals("Atreus", merged.find("Atreus, come")[0].target)
        assertNotEquals(g.fingerprint, merged.fingerprint)
        assertTrue(merged.fingerprint.matches(Regex("g[0-9a-f]{8}")))
        assertEquals(g.fingerprint, Glossary.parse(sample).fingerprint)
        assertNull(Glossary.EMPTY.line("follow me"))
        assertTrue(Glossary.load(null, null).isEmpty)
    }

    /** Uygulamayla gelen sözlük (Nino'nun kendi dosyası): okunur, ifadeler derlenir, satır anahtarları sade. */
    @Test fun shippedGlossaryIsValid() {
        val text = File(TestFiles.assets, "glossary-en-tr.json").readText()
        val root = Json.parseObject(text)
        val shipped = Glossary.load(text, null)
        assertFalse(shipped.isEmpty)
        @Suppress("UNCHECKED_CAST") val terms = root["terms"] as Map<String, String>
        assertEquals(terms.size, shipped.termCount)
        for ((en, tr) in terms) {
            assertEquals(en, en.trim().replace(Regex("\\s+"), " "))
            assertTrue(en, tr.isNotBlank())
            assertEquals(en, tr, shipped.find("x $en x").firstOrNull()?.target)
        }
        @Suppress("UNCHECKED_CAST") val phrases = root["phrases"] as Map<String, String>
        for (re in phrases.keys) assertTrue(re, runCatching { Pattern.compile(re) }.isSuccess)
        @Suppress("UNCHECKED_CAST") val lines = root["lines"] as Map<String, String>
        assertEquals("satır anahtarları tekrar etmemeli", lines.keys.map(Glossary::lineKey).toSet().size, shipped.lineCount)
        for ((en, tr) in lines) assertEquals(en, tr, shipped.line(en))
        assertEquals("Oklarım bitti!", shipped.line("I’m out of arrows!"))
        assertEquals("going to", shipped.applyPhrases("gonna"))
    }
}
