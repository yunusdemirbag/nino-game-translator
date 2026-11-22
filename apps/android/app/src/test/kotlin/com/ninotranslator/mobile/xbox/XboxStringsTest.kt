// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.xbox

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Yayının kullandığı her metin anahtarı Türkçe ve İngilizce strings'te olmalı. */
class XboxStringsTest {
    @Test fun everyKeyHasText() {
        val keys = XboxProblem.values().flatMap { listOf(XboxTexts.retryKey(it), XboxTexts.reasonKey(it)) }.toSet() +
            setOf(XboxTexts.GAVE_UP, "xbox_phase_connecting")
        for (dir in listOf("values", "values-en")) {
            val xml = File("src/main/res/$dir/strings.xml").readText()
            for (k in keys) assertTrue("$dir: $k yok", xml.contains("name=\"$k\""))
        }
    }
}
