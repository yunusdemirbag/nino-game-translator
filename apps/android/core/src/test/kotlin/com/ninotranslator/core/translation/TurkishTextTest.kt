// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TurkishTextTest {
    @Test fun sentenceCase() {
        assertEquals("Where is Kratos? I don't know.", TurkishText.sentenceCase("WHERE IS KRATOS? I DON'T KNOW.", setOf("Kratos")))
        assertEquals("OK", TurkishText.sentenceCase("OK"))
        assertEquals("Mixed Case stays", TurkishText.sentenceCase("Mixed Case stays"))
    }

    @Test fun idioms() {
        assertEquals("Watch out, enemies are coming!", TurkishText.applyIdioms("Heads up, we've got company!"))
        assertEquals("I've got your back.", TurkishText.applyIdioms("I’ve got your six."))
    }

    @Test fun postProcess() {
        assertEquals("Ne oldu?", TurkishText.postProcess("Ne oldu .", "What happened?"))
        assertEquals("Hadi!", TurkishText.postProcess("Hadi", "Come on!"))
        assertEquals("Bekle...", TurkishText.postProcess("Bekle.", "Wait..."))
        assertEquals("Tamam", TurkishText.postProcess("Tamam", "Okay."))
        assertEquals("“Koş” dedi.", TurkishText.postProcess("\"Koş\" dedi.", "“Run” he said."))
        assertEquals("\"Koş\" dedi.", TurkishText.postProcess("“Koş”  dedi .", "\"Run\" he said."))
        assertEquals("\"Gel!\"", TurkishText.postProcess("\"Gel!\"", "\"Come!\""))
    }

    @Test fun unifyAddress() {
        assertEquals(listOf("Seni bekliyordum.", "Bekle!", "Sizinle gelin."),
            TurkishText.unifyAddress(listOf("Seni bekliyordum.", "Bekleyin!", "Sizinle gelin.")))
        assertEquals(listOf("Bekleyin!", "Dikkat edin."), TurkishText.unifyAddress(listOf("Bekleyin!", "Dikkat edin.")))
    }

    @Test fun suffixes() {
        assertEquals("Freya'ya", TurkishText.attachSuffix("Freya", "a", proper = true))
        assertEquals("Freya'nın", TurkishText.attachSuffix("Freya", "un", proper = true))
        assertEquals("Kratos'ta", TurkishText.attachSuffix("Kratos", "da", proper = true))
        assertEquals("Gök Kalkanı'nı", TurkishText.attachSuffix("Gök Kalkanı", "ı", proper = true))
        assertEquals("Gök Kalkanı'nda", TurkishText.attachSuffix("Gök Kalkanı", "da", proper = true))
        assertEquals("XP'ye", TurkishText.attachSuffix("XP", "a", proper = true))
        assertEquals("kontrol noktasına", TurkishText.attachSuffix("kontrol noktası", "a", proper = false))
        assertEquals("bekleme süresini", TurkishText.attachSuffix("bekleme süresi", "ı", proper = false))
        assertEquals("kum fırtınasıyla", TurkishText.attachSuffix("kum fırtınası", "la", proper = false))
        assertEquals("erzak sandığı", TurkishText.attachSuffix("erzak sandık", "ı", proper = false))
        assertEquals("Kratos'çok-uzun-bir-ek", TurkishText.attachSuffix("Kratos", "çok-uzun-bir-ek", proper = true))
    }

    @Test fun shield() {
        val g = Glossary.parse("""{"terms":{"flare gun":"işaret fişeği","Sky Shield":"Gök Kalkanı"}}""")
        val s = TermShield.shield("Fire the flare gun at the Sky Shield.", g.find("Fire the flare gun at the Sky Shield."))
        assertEquals("Fire the Zarmon at the Velkor.", s.text)
        assertEquals("Velkor'a Zarmonu ateşle.".let { TermShield.restore(it, s) }, "Gök Kalkanı'na işaret fişeğini ateşle.")
        assertNull(TermShield.restore("Bir şey at.", s))
        assertNull(TermShield.restore("Zarmon Velkor Dorvan", s))
    }
}
