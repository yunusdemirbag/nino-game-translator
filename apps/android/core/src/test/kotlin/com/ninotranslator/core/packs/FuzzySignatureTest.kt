// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.packs

import com.ninotranslator.core.translation.LineText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** İmza ve benzerlik vektörleri Python ile bağımsız hesaplandı (resources/packs/make_fixtures.py). */
@Suppress("UNCHECKED_CAST")
class FuzzySignatureTest {
    private val vectors = TestFiles.fixture("fuzzy-vectors.json") as Map<String, Any?>

    @Test fun signatures() {
        for (s in vectors["signatures"] as List<Map<String, Any?>>) {
            val input = s["input"] as String
            val folded = FuzzySignature.fold(input)
            assertEquals(input, s["folded"], folded)
            val len = FuzzySignature.lengthOf(folded)
            if (s["length"] == null) {
                assert(len < FuzzySignature.MIN_LENGTH) { input }
                continue
            }
            assertEquals(input, (s["length"] as Number).toInt(), len)
            val bits = FuzzySignature.bitsFor(len)
            assertEquals(input, (s["bits"] as Number).toInt(), bits)
            val hex = FuzzySignature.toBytes(FuzzySignature.bloom(folded, bits)).joinToString("") { "%02x".format(it) }
            assertEquals(input, s["bloom"], hex)
        }
    }

    @Test fun similarities() {
        for (s in vectors["similarities"] as List<Map<String, Any?>>) {
            val got = FuzzySignature.similarity(s["query"] as String, s["entry"] as String)
            assertEquals(s["query"] as String, (s["similarity"] as Number).toDouble(), got, 1e-9)
        }
    }

    // Etiket ve eşik beklentileri ceviri.md 9.3 / 9.4 metninden elle yazıldı.
    @Test fun looseLabels() {
        val cases = listOf(
            Triple("RIVA: Pass me the rope.", "RIVA: ", "Pass me the rope."),
            Triple("-MARCO: Over here.", "-MARCO: ", "Over here."),
            Triple("CAPTAIN HALE Stay low, keep quiet.", "CAPTAIN HALE ", "Stay low, keep quiet."),
            Triple("Note: this is fine", null, null),
            Triple("Stay low, keep quiet.", null, null),
            Triple("OK", null, null),
        )
        for ((input, label, body) in cases) {
            val got = LineText.looseLabel(input)
            if (label == null) assertNull(input, got)
            else { assertEquals(input, label, got?.prefix); assertEquals(input, body, got?.body) }
        }
    }

    @Test fun thresholds() {
        for (len in 16 until 24) assertEquals(90.0, FuzzySignature.threshold(len, false), 0.0)
        for (len in 24 until 256) assertEquals(80.0, FuzzySignature.threshold(len, false), 0.0)
        for (len in 16 until 24) assertEquals(70.0, FuzzySignature.threshold(len, true), 0.0)
        for (len in 24 until 40) assertEquals(60.0, FuzzySignature.threshold(len, true), 0.0)
        for (len in 40 until 256) assertEquals(55.0, FuzzySignature.threshold(len, true), 0.0)
        assertEquals(5.0, FuzzySignature.MARGIN, 0.0)
        assertEquals(16, FuzzySignature.MIN_LENGTH)
    }

    @Test fun damagedReadings() {
        // OCR izi: ASCII dışı (tipografik hariç), sözcük içi işaret, harf-rakam yan yana, tek harf, 14'ten uzun sözcük.
        assertFalse(FuzzySignature.isDamaged("Stay low, keep quiet, I said."))
        assertFalse(FuzzySignature.isDamaged("Don’t move — I mean it…"))
        assertTrue(FuzzySignature.isDamaged("Stay löw, keep quiet."))
        assertTrue(FuzzySignature.isDamaged("Stay lo|w, keep quiet."))
        assertTrue(FuzzySignature.isDamaged("Wh0 left it?"))
        assertTrue(FuzzySignature.isDamaged("Stay u low, keep quiet."))
        assertTrue(FuzzySignature.isDamaged("Staylowkeepquietnow please."))
    }
}
