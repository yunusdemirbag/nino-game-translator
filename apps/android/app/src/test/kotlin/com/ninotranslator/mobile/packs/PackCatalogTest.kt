// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.packs

import org.junit.Assert.assertEquals
import org.junit.Test

class PackCatalogTest {
    @Test fun sameGameShownOnce() {
        val list = listOf(
            PackInfo("gta-6", "Grand Theft Auto VI", 900),
            PackInfo("rdr2", "Red Dead Redemption 2", 50),
            PackInfo("pool-gta-6", "GTA 6", 1200),
            PackInfo("grand-theft-auto-v", "Grand Theft Auto V", 10),
            PackInfo("pool-gta-v", "GTA 5", 20),
        )
        val out = StorePackCatalog.distinctGames(list)
        assertEquals(listOf("pool-gta-6", "rdr2", "pool-gta-v"), out.map { it.id })
        assertEquals(listOf("pool-gta-6", "gta-6"), out[0].ids)
        assertEquals(listOf("pool-gta-v", "grand-theft-auto-v"), out[2].ids)
        assertEquals(listOf("rdr2"), out[1].ids)
    }
}
