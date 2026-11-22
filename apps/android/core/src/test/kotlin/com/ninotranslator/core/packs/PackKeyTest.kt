// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.packs

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PackKeyTest {
    /** Python ile bağımsız hesaplanmış vektörler (resources/packs/make_fixtures.py). */
    @Test fun keyVectors() {
        @Suppress("UNCHECKED_CAST")
        val list = TestFiles.fixture("key-vectors.json") as List<Map<String, String>>
        assert(list.size >= 15)
        for (v in list) {
            assertEquals(v["input"], v["canon"], PackKey.canonical(v["input"]!!))
            val key = v["key"]!!
            if (key.isEmpty()) assertNull(PackKey.of(v["input"]!!)) else assertEquals(v["input"], key, PackKey.of(v["input"]!!))
        }
    }

    @Test fun runAndQuestionShareKey() {
        assertEquals(PackKey.of("Run."), PackKey.of("Run?"))
        assertEquals(PackKey.parse("ABCDEF0123456789"), PackKey.parse("abcdef0123456789"))
        assertNull(PackKey.parse("xyz"))
        assertEquals("00000000000000ff", PackKey.hex(255))
    }
}
