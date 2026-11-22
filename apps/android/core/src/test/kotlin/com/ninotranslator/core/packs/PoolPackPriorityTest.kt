// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.packs

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Aynı oyunun havuz paketi gelince eski sunucudan inmiş paket devre dışı kalır; başka oyunların paketleri kalır. */
class PoolPackPriorityTest {
    private fun pack(id: String, title: String, line: String, tr: String) =
        LegacyPack.parse("""{"format":2,"id":"$id","title":"$title","entries":{"${"%016x".format(PackKey.longOf(line))}":"$tr"}}""", id)

    @Test fun poolPackWinsForSameGame() {
        val old = pack("harbor", "Harbor Lights", "Open the gate now.", "eski")
        val other = pack("garden", "Garden of Ash", "Keep the lamp lit.", "lamba")
        val pool = pack("pool-harbor-lights", "Harbor Lights", "Open the gate now.", "yeni")
        val lib = LegacyPackLibrary(listOf(old, other, pool))
        assertEquals(listOf("garden", "pool-harbor-lights"), lib.packs.map { it.id })
        assertEquals("yeni", lib.find("Open the gate now.")?.text)
        assertEquals("lamba", lib.find("Keep the lamp lit.")?.text)
        assertNull(lib.pack("harbor"))
    }

    @Test fun oldPackStaysWithoutPoolPack() {
        val old = pack("harbor", "Harbor Lights", "Open the gate now.", "eski")
        assertEquals("eski", LegacyPackLibrary(listOf(old)).find("Open the gate now.")?.text)
    }
}
