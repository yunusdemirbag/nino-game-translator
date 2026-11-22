// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import com.ninotranslator.core.packs.TestFiles
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.security.MessageDigest

class LineCacheTest {
    @After fun forget() = LineCache.forgetOpenFiles()

    @Test fun fileNames() {
        assertEquals("v1-mlkit_p3-en-tr.jsonl", LineCache.fileName("mlkit-p3", "en", "tr"))
        assertEquals("v1-deepl-en-ar.jsonl", LineCache.fileName("deepl", "en", "ar"))
        val hex = MessageDigest.getInstance("SHA-256").digest("gemini:gemini-3.5-flash-lite\u0000en\u0000tr".toByteArray()).joinToString("") { "%02x".format(it) }
        assertEquals("v1h-$hex.jsonl", LineCache.fileName("gemini:gemini-3.5-flash-lite", "en", "tr"))
    }

    @Test fun readsExistingFileAndRepairsTornTail() {
        val dir = TestFiles.tempDir()
        val f = File(dir, "v1-deepl-en-tr.jsonl")
        f.writeText("[\"Hello\",\"Merhaba\"]\n[\"Bye\",\"Hoşça kal\"]\n[\"Hello\",\"Selam\"]\n[\"yarım\",\"sat")
        val c = LineCache.open(dir, "deepl", "tr")
        assertEquals("Selam", c.get("Hello"))
        assertEquals("Hoşça kal", c.get("Bye"))
        assertNull(c.get("yarım"))
        c.put("Run", "Koş")
        assertTrue(f.readText().endsWith("[\"Run\",\"Koş\"]\n"))
        assertTrue(f.readLines().all { it.startsWith("[") && it.endsWith("]") })
        // Aynı dosya tek kez açılır.
        assertTrue(c === LineCache.open(dir, "deepl", "tr"))
    }

    @Test fun evictsLeastRecentlyUsedAndRewrites() {
        val dir = TestFiles.tempDir()
        val c = LineCache.open(dir, "deepl", "tr", capacity = 10)
        for (i in 0 until 10) c.put("k$i", "v$i")
        c.get("k0") // en son kullanılan olur
        c.put("k10", "v10") // 11 > 10: 1 + 10/10 = 2 kayıt atılır (k1, k2)
        assertEquals(9, c.size)
        assertNull(c.get("k1")); assertNull(c.get("k2")); assertEquals("v0", c.get("k0"))
        for (i in 11 until 20) c.put("k$i", "v$i")
        // Dosya satırı 2 × sınıra ulaşınca bellektekilerle yeniden yazılır.
        val lines = File(dir, LineCache.fileName("deepl", "en", "tr")).readLines().size
        assertTrue("satır $lines", lines < 20)
        LineCache.forgetOpenFiles()
        val again = LineCache.open(dir, "deepl", "tr", capacity = 10)
        assertEquals("v19", again.get("k19"))
    }
}
